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

        // Channel first: SPU_ChannelAssignedSound and every other
        // per-channel port below act on whatever SPU_SelectedChannel
        // currently names.
        emit_asm("OUT  SPU_SelectedChannel, %d", static_channel);
        emit_asm("OUT  SPU_ChannelAssignedSound, %d ; sound id", static_sound);

        // SPU_ChannelVolume and SPU_ChannelPosition are float ports.
        // Integer immediates in OUT are used throughout this codebase and
        // are known good; float immediates are not, so those two are
        // staged through a register rather than emitted as immediates.
        int vol_reg = allocate_register();
        emit_asm("MOV  R%d, %f", vol_reg, static_volume);
        emit_asm("OUT  SPU_ChannelVolume, R%d ; channel volume", vol_reg);
        unlock_register(vol_reg);

        emit_asm("OUT  SPU_ChannelLoopEnabled, %d ; loop", static_loop);
        emit_asm("OUT  SPU_Command, SPUCommand_PlaySelectedChannel");

        // The seek is issued AFTER the play command on purpose: starting a
        // stopped channel resets its position to 0, so writing
        // SPU_ChannelPosition first would simply be overwritten.
        if (has_start) {
            int pos_reg = allocate_register();
            emit_asm("MOV  R%d, %f", pos_reg, static_start);
            emit_asm("OUT  SPU_ChannelPosition, R%d ; seek to start index", pos_reg);
            unlock_register(pos_reg);
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

// ============================================================================
// ioports.spu.cmd(mode) / ioports.spu.command(mode)
//
// The low-level escape hatch beneath play()/stop()/pause()/resume(): issues
// one raw SPU command against whatever channel SPU_SelectedChannel currently
// names, with no channel selection, no sound assignment and no defaulting of
// its own. Pair it with the ioports.spu.* properties when the intrinsics
// don't expose the exact sequence you need:
//
//     ioports.spu.channel   = 2
//     ioports.spu.chansound = MUSIC
//     ioports.spu.chanloop  = true
//     ioports.spu.cmd("play")
//
// Accepted argument forms:
//   omitted           -> "play"
//   string literal    -> name below (compile-time resolved)
//   number literal    -> index below (compile-time resolved)
//   anything else     -> evaluated at runtime as a number index
//
//   name         index  SPU command
//   ----------   -----  --------------------------------
//   "play"           0  SPUCommand_PlaySelectedChannel
//   "pause"          1  SPUCommand_PauseSelectedChannel
//   "stop"           2  SPUCommand_StopSelectedChannel
//   "pauseall"       3  SPUCommand_PauseAllChannels
//   "resume"         4  SPUCommand_ResumeAllChannels
//   "allstop"        5  SPUCommand_StopAllChannels
//
//   Also accepted as names: "resumeall" (= "resume"), "stopall" (= "allstop").
//
// Returns nil.
//
// CHANGES FROM THE PREVIOUS IMPLEMENTATION
// ----------------------------------------
// 1. An unrecognized name or index is now a compile error. It used to fall
//    back to "play" silently, so ioports.spu.cmd("halt") -- or a typo like
//    "stopAll" -- started playback instead of doing what was asked, with
//    nothing emitted to say so.
//
// 2. The dynamic path no longer OUTs the mode index raw. It used to emit
//    CFI + "OUT SPU_Command, Rmode", writing 0-5 to a port whose commands
//    are 0x30-0x35 -- so every dynamic ioports.spu.cmd(n) sent a command
//    the SPU does not define, while the literal paths (which emit the
//    SPUCommand_* symbols) worked. The index is now resolved through an
//    explicit compare chain against those same symbols, so the two paths
//    agree and neither depends on the numeric opcode layout.
// ============================================================================

// Defined alongside the play()/stop() emitters further down this file.
// A static function may be declared before it is defined within the same
// translation unit, which is what lets this routine sit at its original
// position while sharing that helper.
static bool spu_static_number (ASTNode *node, double *out_value);

typedef struct {
    const char *name;      // spelling accepted in Lua source
    int         index;     // numeric form accepted in Lua source
    const char *asm_cmd;   // assembler constant actually emitted
} SPUCommandMap;

// The six commands, in index order. The dynamic compare chain walks this
// table, so index N must stay at position N.
static const SPUCommandMap spu_commands[] = {
    { "play",     0, "SPUCommand_PlaySelectedChannel"  },
    { "pause",    1, "SPUCommand_PauseSelectedChannel" },
    { "stop",     2, "SPUCommand_StopSelectedChannel"  },
    { "pauseall", 3, "SPUCommand_PauseAllChannels"     },
    { "resume",   4, "SPUCommand_ResumeAllChannels"    },
    { "allstop",  5, "SPUCommand_StopAllChannels"      }
};

#define SPU_COMMAND_COUNT ((int)(sizeof(spu_commands) / sizeof(spu_commands[0])))

// Alternate spellings for the all-channel commands, whose original names
// ("resume", "allstop") read oddly next to "pauseall".
static const SPUCommandMap spu_command_aliases[] = {
    { "resumeall", 4, "SPUCommand_ResumeAllChannels" },
    { "stopall",   5, "SPUCommand_StopAllChannels"   }
};

#define SPU_ALIAS_COUNT ((int)(sizeof(spu_command_aliases) / sizeof(spu_command_aliases[0])))

// Every accepted name, for error messages.
static void spu_command_name_list (char *buffer, size_t size)
{
    buffer[0] = '\0';

    for (int i = 0; i < SPU_COMMAND_COUNT; i++) {
        strncat(buffer, "\"", size - strlen(buffer) - 1);
        strncat(buffer, spu_commands[i].name, size - strlen(buffer) - 1);
        strncat(buffer, "\", ", size - strlen(buffer) - 1);
    }

    for (int i = 0; i < SPU_ALIAS_COUNT; i++) {
        strncat(buffer, "\"", size - strlen(buffer) - 1);
        strncat(buffer, spu_command_aliases[i].name, size - strlen(buffer) - 1);
        strncat(buffer, (i + 1 < SPU_ALIAS_COUNT) ? "\", " : "\"", size - strlen(buffer) - 1);
    }
}

static const SPUCommandMap *spu_command_by_name (const char *name)
{
    for (int i = 0; i < SPU_COMMAND_COUNT; i++) {
        if (strcmp(spu_commands[i].name, name) == 0) {
            return &spu_commands[i];
        }
    }

    for (int i = 0; i < SPU_ALIAS_COUNT; i++) {
        if (strcmp(spu_command_aliases[i].name, name) == 0) {
            return &spu_command_aliases[i];
        }
    }

    return NULL;
}

static const SPUCommandMap *spu_command_by_index (int index)
{
    if (index < 0 || index >= SPU_COMMAND_COUNT) {
        return NULL;
    }
    return &spu_commands[index];
}

bool emit_spu_cmd_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg_mode = node->as.call.args_head;

    emit_asm("    ;; --- Intrinsic: ioports.spu.cmd(mode) ---");

    if (arg_mode != NULL && arg_mode->next != NULL) {
        compiler_warning(ERR_SEMANTIC, node->line_number,
                         "ioports.spu.cmd() takes at most 1 argument (mode); extra arguments ignored");
    }

    // =====================================================================
    // CASE A: omitted, or an explicit nil -> "play"
    // =====================================================================
    if (arg_mode == NULL || arg_mode->type == NODE_NIL) {
        emit_asm("OUT  SPU_Command, %s ; default mode", spu_commands[0].asm_cmd);

        if (dest_reg != 0) {
            emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
        }
        return true;
    }

    // =====================================================================
    // CASE B: string literal -> resolved now
    // =====================================================================
    if (arg_mode->type == NODE_STRING) {
        const char          *val = arg_mode->as.string_val.value;
        const SPUCommandMap *cmd = spu_command_by_name(val);

        if (cmd == NULL) {
            char names[256];
            spu_command_name_list(names, sizeof(names));
            compiler_error(ERR_SEMANTIC, node->line_number,
                           "ioports.spu.cmd(): unknown mode \"%s\". Valid modes: %s", val, names);
            return false;
        }

        emit_asm("OUT  SPU_Command, %s ; \"%s\"", cmd->asm_cmd, val);

        if (dest_reg != 0) {
            emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
        }
        return true;
    }

    // =====================================================================
    // CASE C: number literal -> resolved now
    // =====================================================================
    {
        double literal;
        if (spu_static_number(arg_mode, &literal)) {
            const SPUCommandMap *cmd = spu_command_by_index((int) literal);

            if (cmd == NULL) {
                compiler_error(ERR_SEMANTIC, node->line_number,
                               "ioports.spu.cmd(): mode index must be 0-%d (got %g)",
                               SPU_COMMAND_COUNT - 1, literal);
                return false;
            }

            emit_asm("OUT  SPU_Command, %s ; mode %d (\"%s\")",
                     cmd->asm_cmd, cmd->index, cmd->name);

            if (dest_reg != 0) {
                emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
            }
            return true;
        }
    }

    // =====================================================================
    // CASE D: runtime value -> nil-check, then resolve the index through an
    // explicit compare chain.
    //
    // The chain exists so that the emitted command is always one of the
    // SPUCommand_* symbols, exactly as in the literal paths above. Adding a
    // base opcode to the index would be shorter, but would bake in the
    // assumption that the six commands occupy contiguous opcodes -- and
    // would silently emit an undefined command the day that stops holding.
    //
    // An out-of-range index at runtime issues no command at all. There is no
    // sensible fallback: guessing "play" here is what made the previous
    // silent-fallback behaviour so hard to debug.
    // =====================================================================
    int mode_reg = allocate_register();
    register_pinned[mode_reg] = 1;
    generate_asm(arg_mode, mode_reg);

    int         label_id = get_next_label();
    const char *ctx      = get_current_function_name();

    char end_label[160], case_label[160];
    snprintf(end_label, sizeof(end_label), "__%s_spu_cmd_end_%d", ctx, label_id);

    int scratch = allocate_register();
    register_pinned[scratch] = 1;

    // nil -> the same default as an omitted argument
    emit_asm("MOV  R%d, R%d", scratch, mode_reg);
    emit_asm("IEQ  R%d, BOXED_NIL ; check for runtime nil", scratch);
    emit_asm("JT   R%d, __%s_spu_cmd_default_%d", scratch, ctx, label_id);

    emit_asm("CFI  R%d ; Lua float -> mode index", mode_reg);

    for (int i = 0; i < SPU_COMMAND_COUNT; i++) {
        emit_asm("MOV  R%d, R%d", scratch, mode_reg);
        emit_asm("IEQ  R%d, %d", scratch, spu_commands[i].index);
        emit_asm("JT   R%d, __%s_spu_cmd_%d_%d", scratch, ctx, spu_commands[i].index, label_id);
    }

    emit_asm("JMP  %s ; unknown mode -> no command issued", end_label);

    emit_asm("__%s_spu_cmd_default_%d:", ctx, label_id);
    emit_asm("OUT  SPU_Command, %s ; nil -> default mode", spu_commands[0].asm_cmd);
    emit_asm("JMP  %s", end_label);

    for (int i = 0; i < SPU_COMMAND_COUNT; i++) {
        snprintf(case_label, sizeof(case_label), "__%s_spu_cmd_%d_%d",
                 ctx, spu_commands[i].index, label_id);
        emit_asm("%s:", case_label);
        emit_asm("OUT  SPU_Command, %s ; \"%s\"", spu_commands[i].asm_cmd, spu_commands[i].name);

        if (i + 1 < SPU_COMMAND_COUNT) {
            emit_asm("JMP  %s", end_label);
        }
    }

    emit_asm("%s:", end_label);

    if (dest_reg != 0) {
        emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
    }

    register_pinned[mode_reg] = 0;
    register_pinned[scratch]  = 0;
    unlock_register(scratch);
    unlock_register(mode_reg);

    return true;
}
