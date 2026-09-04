#include "v32lua.h"

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
// Channel-ownership tracking for music.volume()/sfx.volume()'s no-channel
// "apply to every channel I've used" mode.
//
// Two RAM words, VIRCON32_MUSIC_CHANNEL_MASK and VIRCON32_SFX_CHANNEL_MASK,
// each a 16-bit-relevant bitmask: bit N set means channel N was last
// assigned a sound by that namespace's .play(). Ownership is exclusive --
// claiming a channel for one namespace releases it from the other -- since
// a channel doesn't actually belong to music or sfx at the hardware level,
// only by convention in how the game's .play() calls have been using it.
// Only .play() ever touches these masks; .pause()/.resume()/.stop()/
// .volume() leave them alone, so a paused or stopped channel is still
// found by the tracked-channels mode until something else claims it.
//
// This helper handles the COMPILE-TIME-KNOWN channel case (the static-fold
// branches of emit_vircon32_play_intrinsic/emit_vircon32_sfx_play_intrinsic
// below). The dynamic (CALL) paths do the identical claim/release directly
// in assembly -- see the "Track channel ownership" block inline in
// __builtin_vircon32_play and __builtin_vircon32_sfx_play in vircon32.s --
// since the channel isn't known until the runtime routine resolves it.
// ============================================================================
static void emit_vircon32_claim_channel_static (int channel, bool for_music)
{
    const char *own_mask   = for_music ? "VIRCON32_MUSIC_CHANNEL_MASK" : "VIRCON32_SFX_CHANNEL_MASK";
    const char *other_mask = for_music ? "VIRCON32_SFX_CHANNEL_MASK"   : "VIRCON32_MUSIC_CHANNEL_MASK";

    unsigned int bit        = (1u << (unsigned int) channel);
    unsigned int clear_mask = ~bit;

    int reg = allocate_register();

    emit_asm("MOV  R%d, [%s]", reg, own_mask);
    emit_asm("OR   R%d, 0x%X ; claim channel %d", reg, bit, channel);
    emit_asm("MOV  [%s], R%d", own_mask, reg);

    emit_asm("MOV  R%d, [%s]", reg, other_mask);
    emit_asm("AND  R%d, 0x%X ; release channel %d, if the other namespace had it", reg, clear_mask, channel);
    emit_asm("MOV  [%s], R%d", other_mask, reg);

    unlock_register(reg);
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

        emit_vircon32_claim_channel_static(static_channel, true /* for_music */);

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
// intrinsics/spu sound namespaces
//
// The music.* / sfx.* sound API, plus the compile-time alias mechanism.
//
// Paste AFTER the existing sound-intrinsics block (after
// emit_vircon32_channel_cmd_intrinsic() ends). It reuses spu_static_number(),
// spu_static_sound_id() and spu_push_optional_arg() from that block.
//
//   music.play(SOUND [, CHANNEL [, LOOP [, VOL [, START]]]])  -> channel used
//   music.pause  ([CHANNEL])
//   music.resume ([CHANNEL])
//   music.stop   ([CHANNEL])
//   music.playing([CHANNEL])                                  -> boolean
//   music.volume (VOL [, CHANNEL])    CHANNEL: omitted/nil -> music's
//                                      tracked channels; -1 -> true global;
//                                      0-15 -> that channel
//
//   sfx.play(SOUND [, CHANNEL [, VOL [, SPEED]]])             -> channel used
//   sfx.stop([CHANNEL])
//   sfx.volume(VOL [, CHANNEL])       CHANNEL: same three modes, against
//                                      sfx's tracked channels instead
//
// music defaults to channel 0. sfx, given no channel, round-robins over
// channels 1-15 so channel 0 stays free for music. sfx never loops: the
// play command overwrites SPU_ChannelLoopEnabled from the sound's own
// PlayWithLoop flag, so sfx.play() explicitly clears it afterwards. Anything
// sustained is what music.play(..., true) is for.
//
// The bare play()/pause()/resume()/stop() names are GONE. They were four of
// the most collision-prone identifiers in a game codebase, which is what the
// old resolve_symbol() guard in the dispatcher was working around. Anyone who
// wants them back declares them, which the alias mechanism below makes exact:
//
//     play = music.play
//     blip = sfx.play
// ============================================================================


// ============================================================================
// Compile-time intrinsic aliases
//
// "play = music.play" records an alias and emits nothing. Later calls to
// play(...) compile to exactly the same inline OUT sequence music.play(...)
// would have produced -- no runtime value, no CALL, no RAM.
//
// The cost of that is that an alias is a NAME, not a VALUE: it cannot be
// stored in a table, passed to a function, or captured by a closure. Doing
// so is a compile error that says as much, rather than a silent miscompile.
// (If first-class sound-function values are ever wanted, the precedent is
// __mathfn_sin / __mathfn_log in runtime.s -- real labels boxed with
// BOXED_FUNCTION -- not this table.)
// ============================================================================

// Intrinsic paths that may be aliased. An alias to anything else is simply
// not recognized, and the assignment compiles as an ordinary (broken) table
// read, exactly as it does today.
static const char *spu_aliasable_paths[] = {
    "music.play",
    "music.pause",
    "music.resume",
    "music.stop",
    "music.playing",
    "music.volume",
    "sfx.play",
    "sfx.stop",
    "sfx.volume",
    NULL
};

// Names an alias may not shadow: doing so would make the namespace itself
// unreachable for the rest of the program.
static const char *spu_alias_reserved[] = {
    "music", "sfx", "ioports", "system", "string", "math", "table", NULL
};

typedef struct SPUAliasNode {
    char                *name;   // the alias the program declared
    const char          *path;   // canonical intrinsic path it stands for
    struct SPUAliasNode *next;
} SPUAliasNode;

static SPUAliasNode *spu_alias_head = NULL;

static const char *spu_aliasable_lookup (const char *path)
{
    for (int i = 0; spu_aliasable_paths[i] != NULL; i++) {
        if (strcmp(spu_aliasable_paths[i], path) == 0) {
            return spu_aliasable_paths[i];
        }
    }
    return NULL;
}

// Public: the canonical intrinsic path `name` stands for, or NULL.
const char *resolve_intrinsic_alias (const char *name)
{
    if (name == NULL) {
        return NULL;
    }

    for (SPUAliasNode *a = spu_alias_head; a != NULL; a = a->next) {
        if (strcmp(a->name, name) == 0) {
            return a->path;
        }
    }
    return NULL;
}

bool is_intrinsic_alias (const char *name)
{
    return (resolve_intrinsic_alias(name) != NULL);
}

static void spu_alias_register (const char *name, const char *path, int line)
{
    for (int i = 0; spu_alias_reserved[i] != NULL; i++) {
        if (strcmp(spu_alias_reserved[i], name) == 0) {
            compiler_error(ERR_SEMANTIC, line,
                "'%s' cannot be used as an alias name: it is a sound/library "
                "namespace", name);
            return;
        }
    }

    const char *existing = resolve_intrinsic_alias(name);
    if (existing != NULL) {
        if (strcmp(existing, path) != 0) {
            compiler_error(ERR_SEMANTIC, line,
                "'%s' is already a compile-time alias for %s and cannot be "
                "redefined as %s", name, existing, path);
        }
        return;   // same alias declared twice: harmless
    }

    SPUAliasNode *a = (SPUAliasNode *) malloc (sizeof (SPUAliasNode));
    if (a == NULL) {
        compiler_error(ERR_INTERNAL, line, "Memory allocation failed registering alias '%s'", name);
        return;
    }

    a->name = strdup(name);
    a->path = path;
    a->next = spu_alias_head;
    spu_alias_head = a;
}

// True if this assignment node is (entirely) a set of alias declarations.
// node_multiple_assignment() uses this to emit nothing for it.
bool is_intrinsic_alias_assignment (ASTNode *node)
{
    if (node == NULL) {
        return false;
    }

    // One caller, one valid node type. Returning a bland "false" for
    // anything else hides a wiring mistake behind a cart that emits a doomed
    // table read and halts at runtime. Say so at compile time instead.
    if (node->type != NODE_MULTIPLE_ASSIGNMENT) {
        compiler_error(ERR_INTERNAL, node->line_number,
            "is_intrinsic_alias_assignment() expects the NODE_MULTIPLE_ASSIGNMENT "
            "node, got node type %d", (int) node->type);
        return false;
    }

    ASTNode *t = node->as.mult_assign.targets_head;
    if (t == NULL) {
        return false;
    }

    int aliases = 0, targets = 0;
    for (; t != NULL; t = t->next) {
        targets++;
        if (t->type == NODE_IDENTIFIER && is_intrinsic_alias(t->as.id.name)) {
            aliases++;
        }
    }

    if (aliases == 0) {
        return false;
    }

    if (aliases != targets) {
        // "a, play = 1, music.play" -- half of this has a runtime value and
        // half does not, and there is no sensible half-emission. Refuse
        // rather than pick one.
        compiler_error(ERR_SEMANTIC, node->line_number,
            "an intrinsic alias must be declared on its own, not mixed with "
            "ordinary assignments on the same line");
        return true;
    }

    return true;
}

// Walk the AST recording alias declarations. Run once, before codegen, so an
// alias declared at the bottom of the file still governs a call at the top.
//
// The default case here recurses into nothing, which is the SAFE direction
// for this pass -- unlike spu_name_is_rebound(), whose default must assume
// the worst. A node type this walker fails to descend into means a missed
// alias, and a missed alias produces a loud "Undeclared function" at the
// call site. A missed REBIND, by contrast, would silently fold the wrong
// resource id, which is why that walk is exhaustive and this one need not be.
static void spu_alias_scan (ASTNode *node)
{
    for (; node != NULL; node = node->next) {
        switch (node->type) {

            case NODE_MULTIPLE_ASSIGNMENT: {
                ASTNode *t = node->as.mult_assign.targets_head;
                ASTNode *v = node->as.mult_assign.values_head;

                while (t != NULL && v != NULL) {
                    if (t->type == NODE_IDENTIFIER && v->type == NODE_TABLE_GET) {
                        char path[256] = {0};

                        if (resolve_static_path(v, path)) {
                            const char *canon = spu_aliasable_lookup(path);
                            if (canon != NULL) {
                                if (node->as.mult_assign.is_local) {
                                    compiler_warning(ERR_SEMANTIC, node->line_number,
                                        "'local %s = %s' declares a COMPILE-TIME alias, which is "
                                        "program-wide -- the 'local' does not scope it",
                                        t->as.id.name, canon);
                                }
                                spu_alias_register(t->as.id.name, canon, node->line_number);
                            }
                        }
                    }
                    t = t->next;
                    v = v->next;
                }
                break;
            }

            case NODE_WHILE:
                spu_alias_scan(node->as.while_loop.body);
                break;
            case NODE_REPEAT:
                spu_alias_scan(node->as.repeat_loop.body);
                break;
            case NODE_FOR_NUMERIC:
                spu_alias_scan(node->as.for_numeric.body);
                break;
            case NODE_FOR_GENERIC:
                spu_alias_scan(node->as.for_generic.body);
                break;
            case NODE_IF:
                spu_alias_scan(node->as.if_stmt.if_body);
                spu_alias_scan(node->as.if_stmt.else_body);
                break;
            case NODE_DO_BLOCK:
                spu_alias_scan(node->as.do_block.body);
                break;
            case NODE_FUNCTION_DEF:
                spu_alias_scan(node->as.function_def.body);
                break;
            case NODE_FUNCTION_POINTER:
                spu_alias_scan(node->as.func_ptr.func_def);
                break;

            default:
                break;
        }
    }
}

void register_intrinsic_aliases_prepass (ASTNode *root)
{
    spu_alias_scan(root);
}


// ============================================================================
// sfx.play(SOUND [, CHANNEL [, VOL [, SPEED]]])
//
// Same port ordering rules as music.play() -- stop before assigning, loop
// and position after the play command -- see the notes on
// __builtin_vircon32_play in runtime.s.
//
// With no CHANNEL the call goes to the runtime routine, which takes the next
// channel from the round-robin cursor. That is the common form and the
// smaller emission: five pushes and a CALL, versus the cursor arithmetic
// inlined at every jump and footstep in the game.
// ============================================================================
bool emit_vircon32_sfx_play_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *args[4] = { NULL };
    int      arg_count = 0;

    for (ASTNode *curr = node->as.call.args_head;
         curr != NULL && arg_count < 4;
         curr = curr->next) {
        args[arg_count++] = curr;
    }

    if (arg_count < 1) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                       "sfx.play() requires at least 1 argument: sfx.play(sound [, channel [, volume [, speed]]])");
        return false;
    }

    runtime_req.needs_vircon32 = true;

    int    static_sound   = 0;
    int    static_channel = 0;
    double static_volume  = VIRCON32_SPU_DEFAULT_VOL;
    double static_speed   = 1.0;

    bool sound_ok  = spu_static_sound_id(args[0], &static_sound);
    bool volume_ok = (args[2] == NULL);
    bool speed_ok  = (args[3] == NULL);

    // A folded emission needs an explicit channel: the auto path has to read
    // and advance the cursor, which is the runtime routine's job.
    bool channel_ok = false;

    if (args[1] != NULL && args[1]->type != NODE_NIL) {
        double channel_val;
        if (spu_static_number(args[1], &channel_val)) {
            if (channel_val < VIRCON32_SPU_MIN_CHANNEL ||
                channel_val > VIRCON32_SPU_MAX_CHANNEL) {
                compiler_error(ERR_SEMANTIC, node->line_number,
                               "sfx.play(): channel must be %d-%d (got %g)",
                               VIRCON32_SPU_MIN_CHANNEL, VIRCON32_SPU_MAX_CHANNEL, channel_val);
                return false;
            }
            static_channel = (int) channel_val;
            channel_ok     = true;
        }
    }

    if (args[2] != NULL) {
        volume_ok = spu_static_number(args[2], &static_volume);
    }
    if (args[3] != NULL) {
        speed_ok = spu_static_number(args[3], &static_speed);
    }

    // ------------------------------------------------------------------
    // STATIC PATH: explicit literal channel, everything else literal.
    // ------------------------------------------------------------------
    if (sound_ok && channel_ok && volume_ok && speed_ok) {
        emit_asm("    ;; --- Vircon32 sfx.play() Intrinsic (static fold) ---");

        emit_asm("OUT  SPU_SelectedChannel, %d", static_channel);
        emit_asm("OUT  SPU_Command, SPUCommand_StopSelectedChannel ; a sound only assigns to a stopped channel");
        emit_asm("OUT  SPU_ChannelAssignedSound, %d ; sound id", static_sound);

        int reg = allocate_register();
        emit_asm("MOV  R%d, %f", reg, static_volume);
        emit_asm("OUT  SPU_ChannelVolume, R%d ; channel volume", reg);
        emit_asm("MOV  R%d, %f", reg, static_speed);
        emit_asm("OUT  SPU_ChannelSpeed, R%d ; playback speed / pitch", reg);
        unlock_register(reg);

        emit_asm("OUT  SPU_Command, SPUCommand_PlaySelectedChannel");

        // Cleared AFTER the command, which has just set it from the sound's
        // own PlayWithLoop flag. An sfx never loops.
        emit_asm("OUT  SPU_ChannelLoopEnabled, 0 ; sfx never loops");

        emit_vircon32_claim_channel_static(static_channel, false /* for_music */);

        if (dest_reg != 0) {
            emit_asm("MOV  R%d, %f ; sfx.play() returns the channel used",
                     dest_reg, (double) static_channel);
        }

        return true;
    }

    // ------------------------------------------------------------------
    // RUNTIME PATH. Pushed last-to-first so arg 1 lands at [BP+2].
    // ------------------------------------------------------------------
    emit_asm("    ;; --- Vircon32 sfx.play() Intrinsic ---");

    spu_push_optional_arg(args[3], "Arg 4: speed");
    spu_push_optional_arg(args[2], "Arg 3: volume");

    // An omitted or explicitly-nil channel means "allocate one for me".
    if (args[1] != NULL && args[1]->type != NODE_NIL) {
        spu_push_optional_arg(args[1], "Arg 2: channel");
    } else {
        emit_asm("MOV  R0, BOXED_NIL");
        emit_asm("PUSH R0 ; Arg 2: no channel -> round-robin allocation");
    }

    int sound_reg = allocate_register();
    generate_asm(args[0], sound_reg);
    emit_asm("PUSH R%d ; Arg 1: sound", sound_reg);
    unlock_register(sound_reg);

    emit_asm("CALL __builtin_vircon32_sfx_play");
    emit_asm("IADD SP, 4 ; Clean up sfx.play() arguments");

    if (dest_reg != 0) {
        emit_asm("MOV  R%d, R0 ; sfx.play() returns the channel used", dest_reg);
    }

    return true;
}


// ============================================================================
// sfx.stop([CHANNEL])
//
// With a channel, this is an ordinary per-channel stop. WITHOUT one it must
// NOT become StopAllChannels the way music.stop() does -- that would silence
// the music too. It stops channels 1-15 and leaves channel 0 alone.
// ============================================================================
bool emit_vircon32_sfx_stop_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg_channel = node->as.call.args_head;

    runtime_req.needs_vircon32 = true;

    if (arg_channel != NULL && arg_channel->type != NODE_NIL) {
        // Identical to stop(ch); reuse the shared emitter.
        return emit_vircon32_channel_cmd_intrinsic(node, dest_reg, "stop");
    }

    emit_asm("    ;; --- Vircon32 sfx.stop() Intrinsic (all sfx channels) ---");
    emit_asm("CALL __builtin_vircon32_sfx_stop_all ; channels 1-15; music on 0 keeps playing");

    if (dest_reg != 0) {
        emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
    }

    return true;
}


// ============================================================================
// music.playing([CHANNEL]) -> true only while the channel is actually playing
//
// SPU_ChannelState is a read-only integer port returning one of
// channel_stopped 0x40, channel_paused 0x41, channel_playing 0x42.
//
// This exists so a pause/resume toggle can ask the hardware instead of
// tracking a Lua flag. A flag drifts the moment a sound ends on its own --
// the program still believes it is playing, and the next toggle pauses an
// already-stopped channel instead of resuming it.
// ============================================================================
bool emit_vircon32_music_playing_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg_channel = node->as.call.args_head;

    runtime_req.needs_vircon32 = true;

    emit_asm("    ;; --- Vircon32 music.playing() Intrinsic ---");

    // Select the channel (default 0).
    if (arg_channel == NULL || arg_channel->type == NODE_NIL) {
        emit_asm("OUT  SPU_SelectedChannel, 0");
    } else {
        double channel_val;
        if (spu_static_number(arg_channel, &channel_val)) {
            if (channel_val < VIRCON32_SPU_MIN_CHANNEL ||
                channel_val > VIRCON32_SPU_MAX_CHANNEL) {
                compiler_error(ERR_SEMANTIC, node->line_number,
                               "music.playing(): channel must be %d-%d (got %g)",
                               VIRCON32_SPU_MIN_CHANNEL, VIRCON32_SPU_MAX_CHANNEL, channel_val);
                return false;
            }
            emit_asm("OUT  SPU_SelectedChannel, %d", (int) channel_val);
        } else {
            int reg = allocate_register();
            generate_asm(arg_channel, reg);
            emit_asm("CFI  R%d ; Lua float -> channel index", reg);
            emit_asm("OUT  SPU_SelectedChannel, R%d", reg);
            unlock_register(reg);
        }
    }

    if (dest_reg == 0) {
        // Called for effect only: the port read has no side effect worth
        // keeping, but the channel selection above might be relied on.
        return true;
    }

    int         lbl = get_next_label();
    const char *ctx = get_current_function_name();

    char true_label[192], end_label[192];
    snprintf(true_label, sizeof(true_label), "__%s_music_playing_yes_%d", ctx, lbl);
    snprintf(end_label,  sizeof(end_label),  "__%s_music_playing_end_%d", ctx, lbl);

    // IEQ is destructive and 2-operand: it overwrites dest_reg with the 0/1
    // result, which is fine -- the raw state is not needed afterwards.
    emit_asm("IN   R%d, SPU_ChannelState", dest_reg);
    emit_asm("IEQ  R%d, 0x42 ; channel_playing", dest_reg);
    emit_asm("JT   R%d, %s", dest_reg, true_label);
    emit_asm("MOV  R%d, BOXED_FALSE", dest_reg);
    emit_asm("JMP  %s", end_label);
    emit_asm("%s:", true_label);
    emit_asm("MOV  R%d, BOXED_TRUE", dest_reg);
    emit_asm("%s:", end_label);

    return true;
}

// ============================================================================
// music.volume(VOL [, CHANNEL]) / sfx.volume(VOL [, CHANNEL])
//
// VOL is required. CHANNEL has THREE distinct meanings, chosen by what the
// call site wrote:
//
//   music.volume(VOL)        no channel at all (omitted, or an explicit
//                             `nil`) -- apply VOL to every channel THIS
//                             NAMESPACE currently owns (see the channel-
//                             ownership tracking notes on
//                             emit_vircon32_claim_channel_static() above).
//                             sfx.volume(0.3) therefore ducks only the
//                             sound-effect channels currently in use, and
//                             leaves music's channel alone -- unlike a
//                             literal -1, which reaches the true hardware
//                             global.
//   music.volume(VOL, -1)    the actual SPU_GlobalVolume port -- every
//                             channel, unconditionally, regardless of who
//                             claimed what.
//   music.volume(VOL, N)     N in 0-15 -- that one channel's
//                             SPU_ChannelVolume, exactly as before. Does
//                             NOT change channel ownership -- only .play()
//                             claims/releases a channel.
//
// One emitter serves both namespaces for modes 2 and 3 (which are namespace-
// agnostic), but mode 1 needs to know which namespace's mask to read, so
// `lua_name` is used to pick VIRCON32_MUSIC_CHANNEL_MASK vs.
// VIRCON32_SFX_CHANNEL_MASK.
// ============================================================================
bool emit_vircon32_volume_intrinsic (ASTNode *node, int dest_reg, const char *lua_name)
{
    ASTNode *arg_vol     = node->as.call.args_head;
    ASTNode *arg_channel = (arg_vol != NULL) ? arg_vol->next : NULL;

    if (arg_vol == NULL) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                       "%s() requires a volume argument: %s(volume [, channel])",
                       lua_name, lua_name);
        return false;
    }

    if (arg_channel != NULL && arg_channel->next != NULL) {
        compiler_warning(ERR_SEMANTIC, node->line_number,
                         "%s() takes at most 2 arguments (volume, channel); extra arguments ignored",
                         lua_name);
    }

    runtime_req.needs_vircon32 = true;

    bool is_music = (strncmp(lua_name, "music.", 6) == 0);

    // ------------------------------------------------------------------
    // MODE 1: no channel argument at all -- apply to every channel this
    // namespace currently owns. Which channels those are is only known at
    // runtime (the ownership mask lives in RAM), so this is always a CALL,
    // even when VOL is a compile-time literal.
    // ------------------------------------------------------------------
    if (arg_channel == NULL || arg_channel->type == NODE_NIL) {
        const char *own_mask = is_music ? "VIRCON32_MUSIC_CHANNEL_MASK" : "VIRCON32_SFX_CHANNEL_MASK";

        emit_asm("    ;; --- Vircon32 %s() Intrinsic (tracked channels) ---", lua_name);

        emit_asm("MOV  R0, %s", own_mask);
        emit_asm("PUSH R0 ; Arg 2: mask address");

        int vol_reg = allocate_register();
        generate_asm(arg_vol, vol_reg);
        emit_asm("PUSH R%d ; Arg 1: volume", vol_reg);
        unlock_register(vol_reg);

        emit_asm("CALL __builtin_vircon32_volume_mask");
        emit_asm("IADD SP, 2 ; Clean up %s() arguments", lua_name);

        if (dest_reg != 0) {
            emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
        }
        return true;
    }

    // ------------------------------------------------------------------
    // MODES 2 & 3: an explicit channel argument was given. -1 means the
    // real hardware global; 0-15 means that one channel. Neither mode
    // touches the ownership masks.
    // ------------------------------------------------------------------
    double static_vol;
    bool   vol_ok = spu_static_number(arg_vol, &static_vol);

    double channel_val;
    bool   channel_literal = spu_static_number(arg_channel, &channel_val);
    bool   channel_ok         = false;
    bool   channel_is_global  = false;
    int    static_channel     = 0;

    if (channel_literal) {
        if (channel_val == -1) {
            channel_ok        = true;
            channel_is_global = true;
        } else if (channel_val >= VIRCON32_SPU_MIN_CHANNEL && channel_val <= VIRCON32_SPU_MAX_CHANNEL) {
            channel_ok     = true;
            static_channel = (int) channel_val;
        } else {
            compiler_error(ERR_SEMANTIC, node->line_number,
                           "%s(): channel must be -1 (global) or %d-%d (got %g)",
                           lua_name, VIRCON32_SPU_MIN_CHANNEL, VIRCON32_SPU_MAX_CHANNEL, channel_val);
            return false;
        }
    }
    // else: dynamic channel -- channel_ok stays false, forces the runtime
    // path below, which itself checks for -1 vs. 0-15 at runtime.

    // ------------------------------------------------------------------
    // STATIC PATH: literal volume and a literal channel (-1 or 0-15).
    // ------------------------------------------------------------------
    if (vol_ok && channel_ok) {
        emit_asm("    ;; --- Vircon32 %s() Intrinsic (static fold) ---", lua_name);

        // Float port either way -- stage through a register, same reasoning
        // as SPU_ChannelVolume elsewhere in this file: integer OUT
        // immediates are proven throughout this codebase, float ones are
        // not.
        int reg = allocate_register();
        emit_asm("MOV  R%d, %f", reg, static_vol);

        if (channel_is_global) {
            emit_asm("OUT  SPU_GlobalVolume, R%d ; global volume", reg);
        } else {
            emit_asm("OUT  SPU_SelectedChannel, %d", static_channel);
            emit_asm("OUT  SPU_ChannelVolume, R%d ; channel volume", reg);
        }
        unlock_register(reg);

        if (dest_reg != 0) {
            emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
        }
        return true;
    }

    // ------------------------------------------------------------------
    // DYNAMIC PATH: runtime checks the channel value for -1 vs. 0-15 and
    // clamps. Pushed last-to-first so volume lands at [BP+2]. The channel
    // argument is a real (non-nil) expression here -- mode 1 above already
    // handled "no channel" -- so it is pushed as-is, no nil-defaulting.
    // ------------------------------------------------------------------
    emit_asm("    ;; --- Vircon32 %s() Intrinsic ---", lua_name);

    int chan_reg = allocate_register();
    generate_asm(arg_channel, chan_reg);
    emit_asm("PUSH R%d ; Arg 2: channel (-1 = global)", chan_reg);
    unlock_register(chan_reg);

    int vol_reg = allocate_register();
    generate_asm(arg_vol, vol_reg);
    emit_asm("PUSH R%d ; Arg 1: volume", vol_reg);
    unlock_register(vol_reg);

    emit_asm("CALL __builtin_vircon32_volume");
    emit_asm("IADD SP, 2 ; Clean up %s() arguments", lua_name);

    if (dest_reg != 0) {
        emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
    }

    return true;
}

// ============================================================================
// Dispatch for the whole music.* / sfx.* surface.
//
// Called from try_emit_call_intrinsic() once func_name has been resolved
// (and run through resolve_intrinsic_alias()). Returns 1 if handled.
// ============================================================================
int try_emit_sound_namespace_intrinsic (ASTNode *node, int dest_reg, const char *func_name)
{
    bool is_music = (strncmp(func_name, "music.", 6) == 0);
    bool is_sfx   = (strncmp(func_name, "sfx.",   4) == 0);

    if (!is_music && !is_sfx) {
        return 0;
    }

    // In PICO-8 / TIC-80 mode the sound API is that console's, not this one.
    // Without this the call would fall through to a dynamic table lookup
    // against a "music" global that nothing ever creates.
    if (runtime_req.needs_pico8 || runtime_req.needs_tic80) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "'%s' is the native Vircon32 sound API and is not available under "
            "the pico8/tic80 API modes", func_name);
        return 0;
    }

    if (strcmp(func_name, "music.play")    == 0) return emit_vircon32_play_intrinsic(node, dest_reg);
    if (strcmp(func_name, "music.stop")    == 0) return emit_vircon32_channel_cmd_intrinsic(node, dest_reg, "stop");
    if (strcmp(func_name, "music.pause")   == 0) return emit_vircon32_channel_cmd_intrinsic(node, dest_reg, "pause");
    if (strcmp(func_name, "music.resume")  == 0) return emit_vircon32_channel_cmd_intrinsic(node, dest_reg, "resume");
    if (strcmp(func_name, "music.playing") == 0) return emit_vircon32_music_playing_intrinsic(node, dest_reg);
    if (strcmp(func_name, "music.volume")  == 0) return emit_vircon32_volume_intrinsic(node, dest_reg, "music.volume");

    if (strcmp(func_name, "sfx.play")      == 0) return emit_vircon32_sfx_play_intrinsic(node, dest_reg);
    if (strcmp(func_name, "sfx.stop")      == 0) return emit_vircon32_sfx_stop_intrinsic(node, dest_reg);
    if (strcmp(func_name, "sfx.volume")    == 0) return emit_vircon32_volume_intrinsic(node, dest_reg, "sfx.volume");

    // Same reasoning as the system.* guard: an unrecognized dotted call
    // otherwise skips the "Undeclared function" check and miscompiles into a
    // dynamic lookup against a table that does not exist.
    compiler_error(ERR_SEMANTIC, node->line_number,
        "Unknown sound function '%s'", func_name);
    return 0;
}
