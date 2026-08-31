#include "v32lua.h"

// ============================================================================
// intrinsics_vircon32_sound.c
//
// Native Vircon32 implementations of play(), stop(), pause(), resume().
// Used when neither PICO-8 nor TIC-80 compatibility is enabled -- the same
// dispatch rule that selects emit_vircon32_spr/btn/btnp_intrinsic().
//
// Lua-level API
// -------------
//   play(SOUND [, CHANNEL [, CHANLOOP [, CHANVOL [, STARTINDEX]]]])
//       SOUND       sound resource id (a --#sound name, or a literal)
//       CHANNEL     0-15                       (default 0)
//       CHANLOOP    boolean, loop the channel  (default false)
//       CHANVOL     per-channel volume, float  (default 1.0)
//       STARTINDEX  seek position in samples   (default: no seek)
//       returns     the channel actually used, as a Lua number
//
//   stop   ([CHANNEL])   hard stop  (position resets to 0)
//   pause  ([CHANNEL])   pause      (position retained)
//   resume ([CHANNEL])   resume a paused channel
//       With no argument each applies to ALL 16 channels.
//       All three return nil.
//
// Codegen strategy (hybrid)
// -------------------------
// When every argument is known at compile time, the call folds to a
// straight-line OUT sequence with no CALL and no stack traffic. Otherwise
// the arguments are pushed and __builtin_vircon32_play /
// __builtin_vircon32_chancmd in runtime.s does the nil-defaulting,
// Lua-truthiness decoding and channel clamping at runtime.
//
// "Known at compile time" includes a bare --#sound name: the compiler
// already assigned MUSIC its resource id when it parsed the hint, so
// play(MUSIC, 0) can emit "OUT SPU_ChannelAssignedSound, 0" instead of
// reading the RAM global. That fold is skipped if the program ever
// rebinds the name (see spu_name_is_rebound below), so a reassigned
// MUSIC still behaves like an ordinary variable.
// ============================================================================

extern ASTNode *root_node;   // set by the bison grammar; used for the
                             // rebind check behind --#sound name folding

// ============================================================================
// SPU limits and command mapping
// ============================================================================

#define VIRCON32_SPU_MIN_CHANNEL   0
#define VIRCON32_SPU_MAX_CHANNEL   15
#define VIRCON32_SPU_DEFAULT_VOL   1.0

// stop()/pause()/resume() differ only in which two SPU commands they issue,
// so one emitter and one runtime routine serve all three.
//
// NOTE: Vircon32 has no "ResumeSelectedChannel" command. Re-issuing
// PlaySelectedChannel on a PAUSED channel resumes it from its current
// position (a channel only restarts from 0 if it was STOPPED), so Play is
// the correct per-channel resume. ResumeAllChannels does exist and is used
// for the no-argument form.
typedef struct {
    const char *lua_name;
    const char *selected_cmd;   // when a channel is named
    const char *all_cmd;        // when no channel is named
} Vircon32SPUChannelCmd;

static const Vircon32SPUChannelCmd vircon32_spu_channel_cmds[] = {
    { "stop",   "SPUCommand_StopSelectedChannel",  "SPUCommand_StopAllChannels"   },
    { "pause",  "SPUCommand_PauseSelectedChannel", "SPUCommand_PauseAllChannels"  },
    { "resume", "SPUCommand_PlaySelectedChannel",  "SPUCommand_ResumeAllChannels" },
    { NULL,     NULL,                              NULL                           }
};

// ============================================================================
// Compile-time argument classification
// ============================================================================

// A numeric literal, including a negated one ("-1" parses as OP_UNM around
// a NODE_NUMBER, not as a negative NODE_NUMBER).
static bool spu_static_number (ASTNode *node, double *out_value)
{
    if (node == NULL) {
        return false;
    }

    if (node->type == NODE_NUMBER) {
        *out_value = node->as.number.val;
        return true;
    }

    if (node->type == NODE_UNARY &&
        node->as.unary.operator == OP_UNM &&
        node->as.unary.operand != NULL &&
        node->as.unary.operand->type == NODE_NUMBER) {
        *out_value = -(node->as.unary.operand->as.number.val);
        return true;
    }

    return false;
}

// Lua truthiness of a compile-time-known value.
// Returns 1 (truthy), 0 (falsy), or -1 (only knowable at runtime).
//
// Note that EVERY number is truthy in Lua, 0 included -- play(S, 0, 0)
// therefore loops. That is correct Lua, however surprising it looks.
static int spu_static_truth (ASTNode *node)
{
    if (node == NULL) {
        return 0;                       // argument omitted -> default false
    }

    switch (node->type) {
        case NODE_BOOLEAN:  return node->as.boolean.val ? 1 : 0;
        case NODE_NIL:      return 0;
        case NODE_NUMBER:   return 1;
        case NODE_STRING:   return 1;
        case NODE_UNARY:    return (node->as.unary.operator == OP_UNM) ? 1 : -1;
        default:            return -1;
    }
}

// True if `name` is bound to anything other than its --#sound hint anywhere
// in the program: assigned to, used as a loop variable, declared as a
// parameter, or merely mentioned inside inline assembly. Any of those make
// the compile-time resource id an unsafe substitute for a RAM read.
//
// The switch is exhaustive on purpose and its default returns true: a node
// type added later that this function has not been taught to walk must
// suppress the fold rather than silently license a wrong one.
static bool spu_name_is_rebound (ASTNode *node, const char *name)
{
    for (; node != NULL; node = node->next) {
        switch (node->type) {

            // ---- the actual rebinding cases ------------------------------
            case NODE_MULTIPLE_ASSIGNMENT:
                for (ASTNode *t = node->as.mult_assign.targets_head; t != NULL; t = t->next) {
                    if (t->type == NODE_IDENTIFIER &&
                        t->as.id.name != NULL &&
                        strcmp(t->as.id.name, name) == 0) {
                        return true;
                    }
                }
                if (spu_name_is_rebound(node->as.mult_assign.values_head, name)) return true;
                break;

            case NODE_FOR_NUMERIC:
                if (node->as.for_numeric.index_name != NULL &&
                    strcmp(node->as.for_numeric.index_name, name) == 0) {
                    return true;
                }
                if (spu_name_is_rebound(node->as.for_numeric.start_expr, name)) return true;
                if (spu_name_is_rebound(node->as.for_numeric.stop_expr,  name)) return true;
                if (spu_name_is_rebound(node->as.for_numeric.step_expr,  name)) return true;
                if (spu_name_is_rebound(node->as.for_numeric.body,       name)) return true;
                break;

            case NODE_FOR_GENERIC:
                for (ASTNode *v = node->as.for_generic.var_list; v != NULL; v = v->next) {
                    if (v->type == NODE_IDENTIFIER &&
                        v->as.id.name != NULL &&
                        strcmp(v->as.id.name, name) == 0) {
                        return true;
                    }
                }
                if (spu_name_is_rebound(node->as.for_generic.iter_expr, name)) return true;
                if (spu_name_is_rebound(node->as.for_generic.body,      name)) return true;
                break;

            case NODE_FUNCTION_DEF:
                for (ASTNode *p = node->as.function_def.params; p != NULL; p = p->next) {
                    if (p->type == NODE_IDENTIFIER &&
                        p->as.id.name != NULL &&
                        strcmp(p->as.id.name, name) == 0) {
                        return true;   // shadowed by a parameter
                    }
                }
                if (spu_name_is_rebound(node->as.function_def.body, name)) return true;
                break;

            // Hand-written assembly can store to the global behind the
            // compiler's back. Refuse the fold if the name appears at all.
            case NODE_ASM:
            case NODE_RAWASM:
                if (node->as.inline_asm.code != NULL &&
                    strstr(node->as.inline_asm.code, name) != NULL) {
                    return true;
                }
                break;

            // ---- pure structure: walk children ---------------------------
            case NODE_WHILE:
                if (spu_name_is_rebound(node->as.while_loop.condition, name)) return true;
                if (spu_name_is_rebound(node->as.while_loop.body,      name)) return true;
                break;

            case NODE_REPEAT:
                if (spu_name_is_rebound(node->as.repeat_loop.body,      name)) return true;
                if (spu_name_is_rebound(node->as.repeat_loop.condition, name)) return true;
                break;

            case NODE_IF:
                if (spu_name_is_rebound(node->as.if_stmt.condition, name)) return true;
                if (spu_name_is_rebound(node->as.if_stmt.if_body,   name)) return true;
                if (spu_name_is_rebound(node->as.if_stmt.else_body, name)) return true;
                break;

            case NODE_DO_BLOCK:
                if (spu_name_is_rebound(node->as.do_block.body, name)) return true;
                break;

            case NODE_FUNCTION_CALL:
                if (spu_name_is_rebound(node->as.call.target,    name)) return true;
                if (spu_name_is_rebound(node->as.call.args_head, name)) return true;
                break;

            case NODE_FUNCTION_POINTER:
                if (spu_name_is_rebound(node->as.func_ptr.func_def, name)) return true;
                break;

            case NODE_RETURN:
                if (spu_name_is_rebound(node->as.return_stmt.expressions_head, name)) return true;
                break;

            case NODE_TABLE_CONSTRUCTOR:
                if (spu_name_is_rebound(node->as.table_constructor.initializers_head, name)) return true;
                break;

            case NODE_TABLE_SET:
                if (spu_name_is_rebound(node->as.table_set.table_expr, name)) return true;
                if (spu_name_is_rebound(node->as.table_set.key,        name)) return true;
                if (spu_name_is_rebound(node->as.table_set.value,      name)) return true;
                break;

            case NODE_TABLE_GET:
                if (spu_name_is_rebound(node->as.table_get.table_expr, name)) return true;
                if (spu_name_is_rebound(node->as.table_get.key,        name)) return true;
                break;

            case NODE_UNARY:
                if (spu_name_is_rebound(node->as.unary.operand, name)) return true;
                break;

            case NODE_ADD:  case NODE_SUB:  case NODE_MUL:  case NODE_DIV:
            case NODE_FLOORDIV: case NODE_MOD: case NODE_POW:
            case NODE_AND:  case NODE_OR:   case NODE_RELATIONAL:
            case NODE_CONCAT:
                if (spu_name_is_rebound(node->as.binary.left,  name)) return true;
                if (spu_name_is_rebound(node->as.binary.right, name)) return true;
                break;

            // ---- leaves: nothing to walk, nothing to rebind --------------
            case NODE_IDENTIFIER:
            case NODE_NUMBER:
            case NODE_STRING:
            case NODE_BOOLEAN:
            case NODE_NIL:
            case NODE_BREAK:
            case NODE_VARIADIC_EXPR:
            case NODE_COMMENT_LINE:
            case NODE_COMMENT_BLOCK:
            case NODE_CART_HINT:
            case NODE_TIC80_SECTION_HEADER:
            case NODE_TIC80_ASSET_DATA:
            case NODE_TIC80_SECTION_FOOTER:
                break;

            default:
                return true;   // unknown node type -> refuse to fold
        }
    }

    return false;
}

// Resolve a bare identifier that names a --#sound resource to its id.
static bool spu_static_sound_id (ASTNode *node, int *out_id)
{
    double literal;

    // A plain numeric literal is already a resource id.
    if (spu_static_number(node, &literal)) {
        *out_id = (int) literal;
        return true;
    }

    if (node == NULL || node->type != NODE_IDENTIFIER || node->as.id.name == NULL) {
        return false;
    }

    for (CARTresource *res = sounds_head; res != NULL; res = res->next) {
        if (res->var_name != NULL && strcmp(res->var_name, node->as.id.name) == 0) {
            if (spu_name_is_rebound(root_node, node->as.id.name)) {
                return false;   // the program reassigns it; read RAM instead
            }
            *out_id = res->id;
            return true;
        }
    }

    return false;
}

// Push one optional argument, or BOXED_NIL when it was not supplied.
static void spu_push_optional_arg (ASTNode *arg, const char *label)
{
    if (arg != NULL) {
        int reg = allocate_register();
        generate_asm(arg, reg);
        emit_asm("PUSH R%d ; %s", reg, label);
        unlock_register(reg);
    } else {
        emit_asm("MOV  R0, BOXED_NIL");
        emit_asm("PUSH R0 ; %s omitted -> runtime default", label);
    }
}

// ============================================================================
// play(SOUND [, CHANNEL [, CHANLOOP [, CHANVOL [, STARTINDEX]]]])
// ============================================================================
bool emit_vircon32_play_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *args[5] = { NULL };
    int      arg_count = 0;

    for (ASTNode *curr = node->as.call.args_head;
         curr != NULL && arg_count < 5;
         curr = curr->next) {
        args[arg_count++] = curr;
    }

    if (arg_count < 1) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                       "play() requires at least 1 argument: play(sound [, channel [, loop [, volume [, start]]]])");
        return false;
    }

    runtime_req.needs_vircon32 = true;

    // ------------------------------------------------------------------
    // Classify every argument. The static path needs all of them known.
    // ------------------------------------------------------------------
    int    static_sound   = 0;
    int    static_channel = 0;
    int    static_loop    = 0;
    double static_volume  = VIRCON32_SPU_DEFAULT_VOL;
    double static_start   = 0.0;

    bool   sound_ok   = spu_static_sound_id(args[0], &static_sound);
    bool   channel_ok = (args[1] == NULL);      // omitted -> channel 0
    bool   volume_ok  = (args[3] == NULL);      // omitted -> 1.0
    bool   start_ok   = (args[4] == NULL);      // omitted -> no seek
    bool   has_start  = (args[4] != NULL);

    int    loop_truth = spu_static_truth(args[2]);
    bool   loop_ok    = (loop_truth >= 0);
    if (loop_ok) {
        static_loop = loop_truth;
    }

    if (args[1] != NULL) {
        double channel_val;
        if (spu_static_number(args[1], &channel_val)) {
            // A literal channel index is checkable right here.
            if (channel_val < VIRCON32_SPU_MIN_CHANNEL ||
                channel_val > VIRCON32_SPU_MAX_CHANNEL) {
                compiler_error(ERR_SEMANTIC, node->line_number,
                               "play(): channel must be %d-%d (got %g)",
                               VIRCON32_SPU_MIN_CHANNEL, VIRCON32_SPU_MAX_CHANNEL, channel_val);
                return false;
            }
            static_channel = (int) channel_val;
            channel_ok     = true;
        }
    }

    if (args[3] != NULL) {
        volume_ok = spu_static_number(args[3], &static_volume);
    }

    if (args[4] != NULL) {
        start_ok = spu_static_number(args[4], &static_start);
    }

    // ------------------------------------------------------------------
    // STATIC PATH: everything folded, no CALL, no stack traffic.
    // ------------------------------------------------------------------
    if (sound_ok && channel_ok && loop_ok && volume_ok && start_ok) {
        emit_asm("    ;; --- Vircon32 play() Intrinsic (static fold) ---");

        // Channel first: every per-channel port below acts on whatever
        // SPU_SelectedChannel currently names.
        emit_asm("OUT  SPU_SelectedChannel, %d", static_channel);

        // Stop before assigning. WriteSPUChannelAssignedSound() in the
        // console silently IGNORES the write unless the channel is in the
        // Stopped state ("sounds can only be assigned to a non playing
        // channel"), so playing a new sound on a channel that is still
        // busy would otherwise replay whatever was assigned last, with no
        // error anywhere. Stopping first is free on an idle channel.
        emit_asm("OUT  SPU_Command, SPUCommand_StopSelectedChannel ; a sound only assigns to a stopped channel");
        emit_asm("OUT  SPU_ChannelAssignedSound, %d ; sound id", static_sound);

        // SPU_ChannelVolume is a float port (clamped 0-8 by the console);
        // integer immediates in OUT are proven throughout this codebase but
        // float immediates are not, so stage it through a register.
        int vol_reg = allocate_register();
        emit_asm("MOV  R%d, %f", vol_reg, static_volume);
        emit_asm("OUT  SPU_ChannelVolume, R%d ; channel volume", vol_reg);
        unlock_register(vol_reg);

        emit_asm("OUT  SPU_Command, SPUCommand_PlaySelectedChannel");

        // Loop and position are written AFTER the play command, and this
        // ordering is load-bearing. PlayChannel() in the console does, for
        // a stopped or already-playing channel:
        //
        //     TargetChannel.LoopEnabled = ChannelSound->PlayWithLoop;
        //     TargetChannel.Position    = 0;
        //
        // so a loop flag or a seek written BEFORE the command is discarded
        // by the command itself. Writing them after makes both stick --
        // the channel is in the Playing state by then, and nothing else
        // touches either field.
        //
        // The loop flag is written unconditionally, including when it is
        // 0: play() has just overwritten it from the sound's own
        // PlayWithLoop, which may be true, and play(s, ch) with no loop
        // argument must mean "do not loop" rather than "inherit whatever
        // the sound happens to say".
        emit_asm("OUT  SPU_ChannelLoopEnabled, %d ; loop (after play: play overwrites this)", static_loop);

        if (has_start) {
            // SPU_ChannelPosition is an INTEGER port -- a sample index,
            // clamped by the console to 0..length-1. It is not a float.
            emit_asm("OUT  SPU_ChannelPosition, %d ; seek (after play: play rewinds to 0)",
                     (int) static_start);
        }

        if (dest_reg != 0) {
            emit_asm("MOV  R%d, %f ; play() returns the channel used",
                     dest_reg, (double) static_channel);
        }

        return true;
    }

    // ------------------------------------------------------------------
    // DYNAMIC PATH: push all five, let the runtime sort out nil defaults,
    // Lua truthiness and channel clamping.
    //
    // Pushed last-to-first so arg 1 lands at [BP+2].
    // ------------------------------------------------------------------
    emit_asm("    ;; --- Vircon32 play() Intrinsic ---");

    spu_push_optional_arg(args[4], "Arg 5: startindex");
    spu_push_optional_arg(args[3], "Arg 4: chanvol");
    spu_push_optional_arg(args[2], "Arg 3: chanloop");
    spu_push_optional_arg(args[1], "Arg 2: channel");

    int sound_reg = allocate_register();
    generate_asm(args[0], sound_reg);
    emit_asm("PUSH R%d ; Arg 1: sound", sound_reg);
    unlock_register(sound_reg);

    emit_asm("CALL __builtin_vircon32_play");
    emit_asm("IADD SP, 5 ; Clean up play() arguments");

    if (dest_reg != 0) {
        emit_asm("MOV  R%d, R0 ; play() returns the channel used", dest_reg);
    }

    return true;
}

// ============================================================================
// stop([CHANNEL]) / pause([CHANNEL]) / resume([CHANNEL])
//
// One emitter for all three; `lua_name` selects the command pair.
// ============================================================================
bool emit_vircon32_channel_cmd_intrinsic (ASTNode *node, int dest_reg, const char *lua_name)
{
    const Vircon32SPUChannelCmd *cmd = NULL;

    for (int i = 0; vircon32_spu_channel_cmds[i].lua_name != NULL; i++) {
        if (strcmp(vircon32_spu_channel_cmds[i].lua_name, lua_name) == 0) {
            cmd = &vircon32_spu_channel_cmds[i];
            break;
        }
    }

    if (cmd == NULL) {
        compiler_error(ERR_INTERNAL, node->line_number,
                       "emit_vircon32_channel_cmd_intrinsic(): unknown command '%s'", lua_name);
        return false;
    }

    runtime_req.needs_vircon32 = true;

    ASTNode *arg_channel = node->as.call.args_head;

    if (arg_channel != NULL && arg_channel->next != NULL) {
        compiler_warning(ERR_SEMANTIC, node->line_number,
                         "%s() takes at most 1 argument (channel); extra arguments ignored", lua_name);
    }

    // ------------------------------------------------------------------
    // No channel (or an explicit nil): the all-channels form.
    // ------------------------------------------------------------------
    if (arg_channel == NULL || arg_channel->type == NODE_NIL) {
        emit_asm("    ;; --- Vircon32 %s() Intrinsic (all channels) ---", lua_name);
        emit_asm("OUT  SPU_Command, %s", cmd->all_cmd);

        if (dest_reg != 0) {
            emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
        }
        return true;
    }

    // ------------------------------------------------------------------
    // Literal channel: fold, and range-check while we can.
    // ------------------------------------------------------------------
    double channel_val;
    if (spu_static_number(arg_channel, &channel_val)) {
        if (channel_val < VIRCON32_SPU_MIN_CHANNEL ||
            channel_val > VIRCON32_SPU_MAX_CHANNEL) {
            compiler_error(ERR_SEMANTIC, node->line_number,
                           "%s(): channel must be %d-%d (got %g)",
                           lua_name, VIRCON32_SPU_MIN_CHANNEL, VIRCON32_SPU_MAX_CHANNEL, channel_val);
            return false;
        }

        emit_asm("    ;; --- Vircon32 %s() Intrinsic (static fold) ---", lua_name);
        emit_asm("OUT  SPU_SelectedChannel, %d", (int) channel_val);
        emit_asm("OUT  SPU_Command, %s", cmd->selected_cmd);

        if (dest_reg != 0) {
            emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
        }
        return true;
    }

    // ------------------------------------------------------------------
    // Dynamic channel: runtime decides nil vs. value, and clamps.
    // Pushed last-to-first so channel lands at [BP+2].
    // ------------------------------------------------------------------
    emit_asm("    ;; --- Vircon32 %s() Intrinsic ---", lua_name);

    emit_asm("MOV  R0, %s", cmd->all_cmd);
    emit_asm("PUSH R0 ; Arg 3: command when channel is nil");
    emit_asm("MOV  R0, %s", cmd->selected_cmd);
    emit_asm("PUSH R0 ; Arg 2: command for the selected channel");

    int chan_reg = allocate_register();
    generate_asm(arg_channel, chan_reg);
    emit_asm("PUSH R%d ; Arg 1: channel", chan_reg);
    unlock_register(chan_reg);

    emit_asm("CALL __builtin_vircon32_chancmd");
    emit_asm("IADD SP, 3 ; Clean up %s() arguments", lua_name);

    if (dest_reg != 0) {
        emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
    }

    return true;
}
