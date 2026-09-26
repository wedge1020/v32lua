#include "v32lua.h"

#define MAX_SPR_ARGS 7  // n, x, y, w, h, flip_x, flip_y

static bool pico8_push_args (ASTNode *node, int max_args,
                             const char *names[], int *out_arg_count);
static void pico8_warn_unsupported_once (int *flag, int line, const char *what);

/**
 * Emits assembly for the spr() intrinsic (PICO-8 compatibility).
 *
 * Syntax:
 *   spr(n, x, y)               -> draw sprite n at (x, y)
 *   spr(n, x, y, w, h)         -> draw with width/height
 *   spr(n, x, y, w, h, fx, fy) -> draw with flip flags
 *
 * @param node The AST node representing the function call.
 * @return     true if successfully emitted, false on error.
 */
bool emit_pico8_spr_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- PICO-8 spr() Intrinsic ---\n");

    // --- Collect up to MAX_SPR_ARGS arguments ---
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[MAX_SPR_ARGS] = { NULL };
    while (curr != NULL && arg_count < MAX_SPR_ARGS) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    // --- Push arguments right-to-left (standard ABI) ---
    // Order: flip_y (6), flip_x (5), h (4), w (3), y (2), x (1), n (0)

    // Args 6-5: flip_y, flip_x (default = false)
    for (int i = 6; i >= 5; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (arg_count > i) {
            generate_asm(args[i], reg);
            emit_asm("PUSH R%d ; Arg %d: %s\n", reg, i + 1, i == 6 ? "flip_y" : "flip_x");
        } else {
            emit_asm("MOV R%d, BOXED_FALSE ; Default %s\n", reg, i == 6 ? "flip_y" : "flip_x");
            emit_asm("PUSH R%d\n", reg);
        }
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    // Args 4-3: h, w (default = 1.0)
    for (int i = 4; i >= 3; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (arg_count > i) {
            generate_asm(args[i], reg);
            emit_asm("PUSH R%d ; Arg %d: %s\n", reg, i + 1, i == 4 ? "h" : "w");
        } else {
            emit_asm("MOV R%d, 1.000000 ; Default %s\n", reg, i == 4 ? "h" : "w");
            emit_asm("PUSH R%d\n", reg);
        }
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    // Args 2-0: y, x, n (required; pad with NIL if missing)
    for (int i = 2; i >= 0; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (arg_count > i) {
            generate_asm(args[i], reg);
        } else {
            emit_asm("MOV R%d, BOXED_NIL ; Missing required arg!\n", reg);
        }
        emit_asm("PUSH R%d ; Arg %d\n", reg, i + 1);
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    // --- Call runtime subroutine and clean up stack ---
    emit_asm("CALL __builtin_pico8_spr\n");
    emit_asm("IADD SP, %d ; Clean up spr() arguments\n", MAX_SPR_ARGS);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; spr() returns nil\n", dest_reg);
    }
    return true;
}

/**
 * Emits assembly for the btn() intrinsic (PICO-8 compatibility).
 *
 * Syntax:
 *   btn()                -> returns bitfield for player 0
 *   btn(button)          -> returns true if button is pressed (player 0)
 *   btn(button, player)  -> returns true if button is pressed for specified player
 *
 * @param node     The AST node representing the function call.
 * @param dest_reg The destination register for the result (0 = discard).
 * @return          true if successfully emitted, false on error.
 */
static bool pico8_emit_button (ASTNode *node, int dest_reg, const char *routine)
{
    // btn(i, [p]) / btnp(i, [p]): [BP+2] = i (nil -> bitfield), [BP+3] = p
    static const char *names[2] = { "button", "player" };
    int arg_count = 0;
    pico8_push_args (node, 2, names, &arg_count);

    emit_asm("CALL %s\n", routine);
    emit_asm("IADD SP, 2 ; Clean up button arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }
    return true;
}

bool emit_pico8_btn_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- PICO-8 btn() Intrinsic ---\n");
    return pico8_emit_button (node, dest_reg, "__builtin_pico8_btn");
}

/**
 * Emits assembly for the PICO-8 add() intrinsic.
 *
 * Syntax:
 *   add(t, v)      -> append v to the end of table t
 *   add(t, v, i)   -> insert v before position i, shifting existing
 *                      elements up (real PICO-8 semantics)
 *
 * Returns the value that was added (PICO-8 behavior).
 *
 * add(t, v, i) is table.insert(t, i, v) with value/position swapped --
 * this now emits exactly what emit_table_insert_intrinsic() emits
 * (same push order, same __builtin_table_insert CALL) instead of going
 * through the separate __builtin_pico8_add routine, which only
 * overwrote the target slot rather than shifting -- a real behavioral
 * gap vs PICO-8 whenever an explicit index was passed.
 * __builtin_pico8_add is now dead code; safe to delete from the
 * runtime once this is verified in v32sim.
 */
bool emit_pico8_add_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- PICO-8 add() Intrinsic (delegates to table.insert) ---\n");

    ASTNode *arg = node->as.call.args_head;
    if (!arg || !arg->next) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "PICO-8 add() expects at least two arguments: add(t, v [, i])");
        return false;
    }
    ASTNode *t_node   = arg;
    ASTNode *val_node = arg->next;
    ASTNode *pos_node = val_node->next;   // optional index i

    // Same spill-then-reload pattern as emit_table_insert_intrinsic(): any
    // of these sub-expressions may contain a nested CALL, and
    // __builtin_table_insert's callee-saves don't help until we're
    // actually inside it.
    int t_reg = allocate_register();
    generate_asm(t_node, t_reg);
    ensure_in_register(t_reg);
    emit_asm("    PUSH R%d ; spill table pointer\n", t_reg);

    int pos_reg = allocate_register();
    if (pos_node != NULL) {
        generate_asm(pos_node, pos_reg);
        ensure_in_register(pos_reg);
    } else {
        emit_asm("    MOV R%d, BOXED_NIL\n", pos_reg);  // default: append
    }
    emit_asm("    PUSH R%d ; spill position\n", pos_reg);

    int val_reg = allocate_register();
    generate_asm(val_node, val_reg);
    ensure_in_register(val_reg);

    emit_asm("    POP  R%d ; reload position\n", pos_reg);
    emit_asm("    POP  R%d ; reload table pointer\n", t_reg);

    emit_asm("    PUSH R%d ; Table Pointer\n", t_reg);
    emit_asm("    PUSH R%d ; Position\n", pos_reg);
    emit_asm("    PUSH R%d ; Value\n", val_reg);
    emit_asm("    CALL __builtin_table_insert\n");
    emit_asm("    IADD SP, 3\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0 ; PICO-8 add() returns the inserted value\n", dest_reg);
    }

    unlock_register(t_reg);
    unlock_register(pos_reg);
    unlock_register(val_reg);
    return true;
}

/**
 * Emits assembly for the mget() intrinsic (PICO-8 compatibility).
 *
 * Syntax: mget(x, y) -> returns sprite ID at map position (x, y)
 */
bool emit_pico8_mget_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- PICO-8 mget() Intrinsic ---\n");

    // Collect exactly 2 arguments: x, y
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[2] = { NULL, NULL };
    while (curr != NULL && arg_count < 2) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count < 2) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "PICO-8 mget() requires 2 arguments: mget(x, y)");
        return false;
    }

    // Push arguments right-to-left: y, x
    int reg = allocate_register();
    generate_asm(args[1], reg);  // y
    emit_asm("PUSH R%d ; Arg 2: y\n", reg);
    unlock_register(reg);

    reg = allocate_register();
    generate_asm(args[0], reg);  // x
    emit_asm("PUSH R%d ; Arg 1: x\n", reg);
    unlock_register(reg);

    // Call runtime subroutine
    emit_asm("CALL __builtin_pico8_mget\n");
    emit_asm("IADD SP, 2 ; Clean up mget() arguments\n");

    // Transfer result to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the mset() intrinsic (PICO-8 compatibility).
 *
 * Syntax: mset(x, y, v) -> sets sprite ID at map position (x, y) to v
 */
bool emit_pico8_mset_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- PICO-8 mset() Intrinsic ---\n");

    // Collect exactly 3 arguments: x, y, v
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[3] = { NULL, NULL, NULL };
    while (curr != NULL && arg_count < 3) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count < 3) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "PICO-8 mset() requires 3 arguments: mset(x, y, v)");
        return false;
    }

    // Push arguments right-to-left: v, y, x
    int reg = allocate_register();
    generate_asm(args[2], reg);  // v
    emit_asm("PUSH R%d ; Arg 3: value\n", reg);
    unlock_register(reg);

    reg = allocate_register();
    generate_asm(args[1], reg);  // y
    emit_asm("PUSH R%d ; Arg 2: y\n", reg);
    unlock_register(reg);

    reg = allocate_register();
    generate_asm(args[0], reg);  // x
    emit_asm("PUSH R%d ; Arg 1: x\n", reg);
    unlock_register(reg);

    // Call runtime subroutine
    emit_asm("CALL __builtin_pico8_mset\n");
    emit_asm("IADD SP, 3 ; Clean up mset() arguments\n");

    // Transfer result to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the map() intrinsic (PICO-8 compatibility).
 *
 * Real PICO-8 syntax: map(celx, cely, sx, sy, celw, celh, [layer])
 *   celx, cely : map cell coordinates to start reading from
 *   sx, sy     : screen position (raw PICO-8 pixel space) to draw at
 *   celw, celh : width/height of the region to draw, in cells
 *   layer      : optional sprite-flag bitmask filter (see runtime TODO
 *                -- not yet applied)
 *
 * Previously this took (x, y, w, h, sx, sy, [color_key]) -- screen
 * position and cell offset swapped relative to real PICO-8, and a
 * color_key parameter real PICO-8's map() doesn't have. Fixed to match
 * the real signature.
 */
bool emit_pico8_map_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- PICO-8 map() Intrinsic ---\n");

    // Every argument is optional (PICO-8 0.2 defaults: 0,0,0,0,128,32,
    // layer 0) -- absent ones are NIL-padded and defaulted by the runtime.
    // Arguments are pushed as they are evaluated, right-to-left, so a
    // nested CALL in one can't clobber another.
    static const char *names[7] = { "celx", "cely", "sx", "sy", "celw", "celh", "layer" };
    int arg_count = 0;
    pico8_push_args (node, 7, names, &arg_count);

    emit_asm("CALL __builtin_pico8_map\n");
    emit_asm("IADD SP, 7 ; Clean up map() arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; map() returns nil\n", dest_reg);
    }
    return true;
}

/**
 * Emits assembly for PICO-8 cls(color) intrinsic
 * color can be: palette index (0-15), hex string ("0xRRGGBB"), or hex number
 */
bool emit_pico8_cls_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- PICO-8 cls() Intrinsic ---\n");

    ASTNode *arg = node->as.call.args_head;
    int reg = allocate_register();
    if (arg != NULL) {
        generate_asm(arg, reg);
    } else {
        emit_asm("MOV R%d, 0.000000 ; Default cls() color: 0 (black)\n", reg);
    }
    emit_asm("PUSH R%d ; Arg 1: color\n", reg);
    unlock_register(reg);

    emit_asm("CALL __builtin_pico8_cls\n");
    emit_asm("IADD SP, 1 ; Clean up cls() arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; cls() returns nil\n", dest_reg);
    }
    return true;
}

/**
 * PICO-8 btnp(i, [p]) -- true on the first frame of a press, then with
 * PICO-8's 15-frame-delay / 4-frame autorepeat. (This used to take
 * TIC-80's btnp(id, hold, period) signature, so a player argument landed
 * in "hold" and the runtime selected a gamepad from the wrong stack slot.)
 */
bool emit_pico8_btnp_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- PICO-8 btnp() Intrinsic ---\n");
    return pico8_emit_button (node, dest_reg, "__builtin_pico8_btnp");
}

/**
 * Emits assembly for the PICO-8 rnd([x]) intrinsic.
 *
 * PICO-8 semantics (distinct from Lua math.random(), which switches to
 * integer-valued results once given an argument):
 *   rnd()   -> float in [0, 1)
 *   rnd(x)  -> float in [0, x)
 *
 * rnd() with no argument is identical to math.random() with no
 * argument and is delegated straight there. rnd(x) calls
 * __builtin_random with NO arguments (its [0,1) float form) and scales
 * the result by x itself, rather than routing through math.random(x)'s
 * integer path.
 */
bool emit_pico8_rnd_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (arg == NULL) {
        return emit_math_random_intrinsic(node, dest_reg);
    }
    if (arg->next != NULL) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "PICO-8 rnd() expects 0 or 1 arguments");
        return false;
    }

    emit_asm("    ;; --- PICO-8 rnd(x) Intrinsic ---\n");

    int x_reg = allocate_register();
    register_pinned[x_reg] = 1;
    generate_asm(arg, x_reg);
    emit_asm("PUSH R%d ; spill x across __builtin_random CALL\n", x_reg);
    register_pinned[x_reg] = 0;

    emit_asm("MOV  R0, BOXED_NIL\n");
    emit_asm("PUSH R0 ; [BP+3] = no arg 2\n");
    emit_asm("PUSH R0 ; [BP+2] = no arg 1 -> float in [0,1)\n");
    emit_asm("CALL __builtin_random\n");
    emit_asm("IADD SP, 2\n");

    int result_reg = (dest_reg != 0) ? dest_reg : allocate_register();
    emit_asm("POP  R%d ; reload x\n", x_reg);
    emit_asm("MOV  R%d, R0 ; [0,1) sample\n", result_reg);
    emit_asm("FMUL R%d, R%d ; scale to [0, x)\n", result_reg, x_reg);

    unlock_register(x_reg);
    if (dest_reg == 0) unlock_register(result_reg);
    return true;
}

/**
 * Emits assembly for the PICO-8 sgn(x) intrinsic.
 * Returns 1.0 if x >= 0, -1.0 if x < 0 (PICO-8 maps 0 -> 1, not 0).
 */
bool emit_pico8_sgn_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;
    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "PICO-8 sgn() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- PICO-8 sgn(x) Intrinsic ---\n");

    int arg_reg = allocate_register();
    generate_asm(arg, arg_reg);

    int flag_reg = allocate_register();
    emit_asm("MOV R%d, R%d ; preserve value before destructive FLT\n", flag_reg, arg_reg);
    emit_asm("FLT R%d, 0.0 ; (x < 0) ? 1 : 0\n", flag_reg);

    int result_reg = (dest_reg != 0) ? dest_reg : allocate_register();
    int label_id = get_next_label();
    char done_label[64];
    snprintf(done_label, sizeof(done_label), "__pico8_sgn_done_%d", label_id);

    emit_asm("MOV R%d, 1.0\n", result_reg);
    emit_asm("JF  R%d, %s\n", flag_reg, done_label);
    emit_asm("MOV R%d, -1.0\n", result_reg);
    emit_asm("%s:\n", done_label);

    unlock_register(arg_reg);
    unlock_register(flag_reg);
    if (dest_reg == 0) unlock_register(result_reg);
    return true;
}

/**
 * Emits assembly for the PICO-8 mid(a, b, c) intrinsic.
 * Returns the median of the three arguments, via
 *   mid = max(min(a,b), min(max(a,b), c))
 * using the ISA's non-branching FMIN/FMAX directly (same instructions
 * math.min()/math.max() use), so no branches are needed.
 */
bool emit_pico8_mid_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;
    if (!arg || !arg->next || !arg->next->next || arg->next->next->next != NULL) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "PICO-8 mid() expects exactly three arguments");
        return false;
    }

    emit_asm("    ;; --- PICO-8 mid(a, b, c) Intrinsic ---\n");

    // Each argument is pushed as soon as it is evaluated: a nested CALL in
    // b or c (mid(0, rnd(10), 5)) used to clobber a's still-live register.
    int a_reg = allocate_register();
    int b_reg = allocate_register();
    int c_reg = allocate_register();
    generate_asm(arg, a_reg);
    emit_asm("PUSH R%d ; mid: spill a\n", a_reg);
    generate_asm(arg->next, b_reg);
    emit_asm("PUSH R%d ; mid: spill b\n", b_reg);
    generate_asm(arg->next->next, c_reg);
    emit_asm("POP  R%d ; mid: reload b\n", b_reg);
    emit_asm("POP  R%d ; mid: reload a\n", a_reg);

    int min_ab = allocate_register();
    int max_ab = allocate_register();
    emit_asm("MOV  R%d, R%d\n", min_ab, a_reg);
    emit_asm("FMIN R%d, R%d ; min(a,b)\n", min_ab, b_reg);
    emit_asm("MOV  R%d, R%d\n", max_ab, a_reg);
    emit_asm("FMAX R%d, R%d ; max(a,b)\n", max_ab, b_reg);
    emit_asm("FMIN R%d, R%d ; min(max(a,b), c)\n", max_ab, c_reg);
    emit_asm("FMAX R%d, R%d ; mid = max(min(a,b), min(max(a,b),c))\n", min_ab, max_ab);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d\n", dest_reg, min_ab);
    }

    unlock_register(a_reg);
    unlock_register(b_reg);
    unlock_register(c_reg);
    unlock_register(min_ab);
    unlock_register(max_ab);
    return true;
}

/**
 * Emits assembly for the PICO-8 foreach(t, f) intrinsic.
 *
 * Calls f(v) for every value in table t's sequence part (1..#t), in
 * order -- exactly `for v in all(t) do f(v) end`. Return values from f
 * are discarded, and iteration never stops early (unlike old Lua 5.1's
 * table.foreach(), which stopped on a non-nil return -- real PICO-8's
 * foreach() does not).
 *
 * KNOWN LIMITATION: f is called dynamically (not known at compile
 * time), so the compiler can't push an argument count for it the way
 * a normal call site does when its target is statically known to be
 * variadic. A variadic callback (function f(...) ... end) will misread
 * its argument count here. Same limitation table.sort()'s comparator
 * argument already has -- not new to foreach.
 */
bool emit_pico8_foreach_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg_t = node->as.call.args_head;
    if (!arg_t || !arg_t->next || arg_t->next->next != NULL) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "PICO-8 foreach() expects exactly two arguments: foreach(t, f)");
        return false;
    }
    ASTNode *arg_f = arg_t->next;

    emit_asm("    ;; --- PICO-8 foreach(t, f) Intrinsic ---\n");

    // Same spill-then-reload pattern as emit_table_sort_intrinsic()/
    // emit_table_insert_intrinsic(): evaluating arg_f could itself
    // contain a nested CALL, so t is spilled to the stack immediately
    // after being evaluated rather than trusted to survive in-register.
    int t_reg = allocate_register();
    generate_asm(arg_t, t_reg);
    ensure_in_register(t_reg);
    emit_asm("    PUSH R%d ; spill table pointer\n", t_reg);

    int f_reg = allocate_register();
    generate_asm(arg_f, f_reg);
    ensure_in_register(f_reg);

    emit_asm("    POP  R%d ; reload table pointer\n", t_reg);

    emit_asm("    PUSH R%d ; Table Pointer\n", t_reg);
    emit_asm("    PUSH R%d ; Callback function\n", f_reg);
    emit_asm("    CALL __builtin_pico8_foreach\n");
    emit_asm("    IADD SP, 2\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, BOXED_NIL ; foreach() returns nothing\n", dest_reg);
    }

    unlock_register(t_reg);
    unlock_register(f_reg);
    return true;
}

// ============================================================================
// PICO-8 sfx(n [, channel[, offset[, length]]])
// ============================================================================
// offset/length (sub-clip playback into a longer SFX) have no equivalent on
// the native sfx.play() and are silently unsupported -- flagged with one
// compiler_warning() rather than emitted as if they did something.
//
// n < 0 is PICO-8's "stop" form (sfx(-1 [, channel])); forwarded straight to
// sfx.stop()'s own emitter, which already knows single-channel vs. all-sfx-
// channels.
//
// A literal n folds entirely at compile time (no CALL): the placeholder
// tone id is just an immediate, computed right here and handed to
// emit_vircon32_sfx_play_intrinsic() as a synthetic NODE_NUMBER argument, so
// it takes that emitter's own static-fold path exactly as if the cart had
// written the resolved sound id itself.
//
// A dynamic n (celeste.lua's `psfx` wrapper -- sfx(num), where num is a
// parameter, not a literal) can't be folded, since the mapping itself needs
// a runtime AND -- __builtin_tonebank_sfx (vircon32.s) does the same mapping in
// assembly and then does exactly what __builtin_vircon32_sfx_play does.
bool emit_pico8_sfx_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *args[4] = { NULL };
    int      arg_count = 0;
    for (ASTNode *curr = node->as.call.args_head; curr != NULL && arg_count < 4; curr = curr->next) {
        args[arg_count++] = curr;
    }

    if (arg_count < 1) {
        compiler_error (ERR_SEMANTIC, node->line_number,
                         "sfx() requires at least 1 argument: sfx(n [, channel[, offset[, length]]])");
        return false;
    }

    if (args[2] != NULL || args[3] != NULL) {
        compiler_warning (ERR_SEMANTIC, node->line_number,
                           "sfx(): offset/length arguments have no Vircon32 equivalent and are ignored");
    }

    // A cart with __sfx__ data (a .p8, or --#p8) plays its own synthesized
    // SFX through __builtin_pico8_sfx (pico8.s): PICO-8 channel c is SPU
    // channel 4 + c (0-3 belong to music), loops follow the SFX. Otherwise
    // the placeholder tone bank stands in.
    bool real   = register_pico8_sfx_sounds ();
    if (real) {
        runtime_req.needs_vircon32 = true;
        if (args[1] != NULL) {
            int reg = allocate_register ();
            generate_asm (args[1], reg);
            emit_asm ("PUSH R%d ; sfx(): channel\n", reg);
            unlock_register (reg);
        } else {
            emit_asm ("MOV  R0, BOXED_NIL\n");
            emit_asm ("PUSH R0 ; sfx(): channel omitted -> any free\n");
        }
        int reg = allocate_register ();
        generate_asm (args[0], reg);
        emit_asm ("PUSH R%d ; sfx(): n\n", reg);
        unlock_register (reg);
        emit_asm ("CALL __builtin_pico8_sfx\n");
        emit_asm ("IADD SP, 2\n");
        if (dest_reg != 0) emit_asm ("MOV  R%d, BOXED_NIL\n", dest_reg);
        return true;
    }
    register_pico8_tone_bank ();
    int  base   = real ? pico8_sfx_base_id : pico8_tone_base_id;
    int  mask   = real ? 63 : PICO8_TONE_COUNT - 1;
    runtime_req.needs_vircon32 = true;

    double n_val;
    if (spu_static_number (args[0], &n_val)) {

        if (n_val < 0) {
            // sfx(-1 [, channel]): stop form.
            ASTNode *stop_node = make_node (NODE_FUNCTION_CALL);
            stop_node->line_number       = node->line_number;
            stop_node->as.call.args_head = args[1];
            return emit_vircon32_sfx_stop_intrinsic (stop_node, dest_reg);
        }

        int tone_id = base + (((int) n_val) & mask);

        ASTNode *sound_lit = make_node (NODE_NUMBER);
        sound_lit->as.number.val = (double) tone_id;
        sound_lit->next          = args[1];   // channel, or NULL -> auto

        ASTNode *call_node = make_node (NODE_FUNCTION_CALL);
        call_node->line_number       = node->line_number;
        call_node->as.call.args_head = sound_lit;
        return emit_vircon32_sfx_play_intrinsic (call_node, dest_reg);
    }

    // Dynamic index: resolve the tone mapping at runtime.
    emit_asm("    ;; --- PICO-8 sfx() Intrinsic (dynamic index) ---\n");

    emit_asm("MOV  R0, %d ; sound bank mask\n", mask);
    emit_asm("PUSH R0 ; Arg 4: bank size - 1\n");
    emit_asm("MOV  R0, %d ; sound bank base id\n", base);
    emit_asm("PUSH R0 ; Arg 3: bank base id\n");

    if (args[1] != NULL) {
        int reg = allocate_register();
        generate_asm (args[1], reg);
        emit_asm ("PUSH R%d ; Arg 2: channel\n", reg);
        unlock_register (reg);
    } else {
        emit_asm ("MOV  R0, BOXED_NIL\n");
        emit_asm ("PUSH R0 ; Arg 2: channel omitted -> auto\n");
    }

    int n_reg = allocate_register();
    generate_asm (args[0], n_reg);
    emit_asm ("PUSH R%d ; Arg 1: pico8 sfx index (signed; <0 means stop)\n", n_reg);
    unlock_register (n_reg);

    emit_asm ("CALL __builtin_tonebank_sfx\n");
    emit_asm ("IADD SP, 4 ; Clean up sfx() arguments\n");

    if (dest_reg != 0) {
        emit_asm ("MOV  R%d, R0\n", dest_reg);
    }

    return true;
}

// ============================================================================
// PICO-8 music(n [, fade_len[, channel_mask]])
// ============================================================================
// fade_len (crossfade time) and channel_mask (which of PICO-8's 4 pattern
// channels the track claims) both describe multi-channel PATTERN playback
// that has no equivalent once a "track" is just one placeholder tone; both
// are accepted and silently ignored rather than warned about, since nearly
// every real PICO-8 music() call passes them (celeste.lua's do, on every
// call site) and a warning on each would just be noise for a parameter that
// was never going to have a Vircon32 equivalent.
//
// Every music() call site actually seen in celeste.lua uses a literal track
// number, so only the static-fold path is implemented; a dynamic track
// number is a compile error naming the limitation rather than a silent
// wrong-tone result. (A dynamic choice of cue can still be made through
// sfx()/psfx(), which does support it.)
bool emit_pico8_music_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *args[3] = { NULL };
    int      arg_count = 0;
    for (ASTNode *curr = node->as.call.args_head; curr != NULL && arg_count < 3; curr = curr->next) {
        args[arg_count++] = curr;
    }

    if (arg_count < 1) {
        compiler_error (ERR_SEMANTIC, node->line_number,
                         "music() requires at least 1 argument: music(n [, fade_len[, channel_mask]])");
        return false;
    }

    runtime_req.needs_vircon32 = true;

    // A cart with __music__ data: the runtime sequencer plays the song
    // pattern by pattern from the SFX sounds (pico8_audio.c, pico8.s).
    if (pico8_has_audio () && register_pico8_sfx_sounds ()) {
        int reg = allocate_register ();
        generate_asm (args[0], reg);
        emit_asm ("PUSH R%d ; music(): pattern\n", reg);
        unlock_register (reg);
        emit_asm ("CALL __builtin_pico8_music\n");
        emit_asm ("IADD SP, 1\n");
        if (dest_reg != 0) emit_asm ("MOV  R%d, BOXED_NIL\n", dest_reg);
        return true;
    }

    double n_val;
    if (!spu_static_number (args[0], &n_val)) {
        compiler_error (ERR_SEMANTIC, node->line_number,
                         "music(): a computed track number needs the cart's __music__ "
                         "data (compile the .p8, or add --#p8 \"cart.p8\")");
        return false;
    }

    if (n_val < 0) {
        // music(-1 [, fade_len]): stop. Fade is not supported; stop now.
        // An explicit literal channel 0 (not an omitted/NULL arg) so this
        // takes emit_vircon32_channel_cmd_intrinsic()'s single-channel
        // path -- an omitted channel means "every channel" there, which
        // would also cut any sfx() still playing.
        ASTNode *chan0 = make_node (NODE_NUMBER);
        chan0->as.number.val = 0.0;

        ASTNode *stop_node = make_node (NODE_FUNCTION_CALL);
        stop_node->line_number       = node->line_number;
        stop_node->as.call.args_head = chan0;
        return emit_vircon32_channel_cmd_intrinsic (stop_node, dest_reg, "stop");
    }

    // No cart data: loop a placeholder tone on channel 0.
    bool song_loops = true;
    register_pico8_tone_bank ();
    int tone_id = pico8_tone_base_id + (((int) n_val) & (PICO8_TONE_COUNT - 1));

    ASTNode *sound_lit = make_node (NODE_NUMBER);
    sound_lit->as.number.val = (double) tone_id;
    // music.play(SOUND, CHANNEL, CHANLOOP): channel 0 (music's channel),
    // loop on. (This used to pass `true` as the SECOND argument -- which is
    // the CHANNEL -- so music never looped.)
    ASTNode *chan0_m = make_node (NODE_NUMBER);
    chan0_m->as.number.val = 0.0;
    sound_lit->next = chan0_m;
    chan0_m->next   = make_node_boolean (song_loops);

    ASTNode *call_node = make_node (NODE_FUNCTION_CALL);
    call_node->line_number       = node->line_number;
    call_node->as.call.args_head = sound_lit;
    return emit_vircon32_play_intrinsic (call_node, dest_reg);
}

// ============================================================================
// PICO-8 count(t) -> #t
// ============================================================================
// PICO-8 0.2+ defines count(tbl) as the table's length (#tbl); the runtime
// reads it from the table header (__builtin_pico8_count, pico8.s).
//
// The 2-argument occurrence-counting form count(t, v) is a compile error
// naming the limitation.
bool emit_pico8_count_intrinsic (ASTNode *node, int dest_reg)
{
    int      arg_count = 0;
    ASTNode *curr      = node->as.call.args_head;
    ASTNode *args[2]   = { NULL, NULL };
    while (curr != NULL && arg_count < 2) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count < 1) {
        compiler_error (ERR_SEMANTIC, node->line_number,
                         "count() requires 1 argument: count(t)");
        return false;
    }

    if (args[1] != NULL) {
        compiler_error (ERR_SEMANTIC, node->line_number,
                         "count(t, v) occurrence counting is not supported; "
                         "only count(t) (element count)");
        return false;
    }

    // Single-argument call: evaluate t straight into a register and push
    // immediately -- no second argument can interleave a nested CALL, so
    // no spill-then-reload dance is needed (same shape as mget()).
    int t_reg = allocate_register ();
    generate_asm (args[0], t_reg);
    emit_asm ("PUSH R%d ; Arg 1: table\n", t_reg);
    unlock_register (t_reg);

    emit_asm ("CALL __builtin_pico8_count\n");
    emit_asm ("IADD SP, 1 ; Clean up count() arguments\n");

    if (dest_reg != 0) {
        emit_asm ("MOV R%d, R0 ; count result\n", dest_reg);
    }

    return true;
}

// ============================================================================
// PICO-8 del(t, v) -> remove first occurrence of v from sequence part of t
// ============================================================================
// Removes and returns the first element equal to v (1..#t scan, then
// table_remove semantics for the shift-down). Equality is bitwise on the
// boxed word -- exact for the pointer/boolean/nil values celeste passes;
// string CONTENT is not compared (see __builtin_pico8_del header comment).
bool emit_pico8_del_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;
    if (!arg || !arg->next || arg->next->next) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "PICO-8 del() expects exactly two arguments: del(t, v)");
        return false;
    }
    ASTNode *t_node = arg;
    ASTNode *v_node = arg->next;

    // Same spill-then-reload pattern as add()/table.insert: evaluating v
    // may contain a nested CALL that clobbers t's register.
    int t_reg = allocate_register ();
    generate_asm (t_node, t_reg);
    ensure_in_register (t_reg);
    emit_asm ("    PUSH R%d ; spill table pointer\n", t_reg);

    int v_reg = allocate_register ();
    generate_asm (v_node, v_reg);
    ensure_in_register (v_reg);

    emit_asm ("    POP  R%d ; reload table pointer\n", t_reg);

    // ABI: [BP+3] = t, [BP+2] = v
    emit_asm ("    PUSH R%d ; Arg 1: table\n", t_reg);
    emit_asm ("    PUSH R%d ; Arg 2: value\n", v_reg);
    emit_asm ("    CALL __builtin_pico8_del\n");
    emit_asm ("    IADD SP, 2 ; Clean up del() arguments\n");

    if (dest_reg != 0) {
        emit_asm ("    MOV R%d, R0 ; removed value (or nil)\n", dest_reg);
    }

    unlock_register (t_reg);
    unlock_register (v_reg);
    return true;
}

// ============================================================================
// PICO-8 sin(x) -- x in TURNS (1.0 = full circle), result INVERTED
// ============================================================================
// pico8 sin(x) = -sin(x * 2*PI). Same hardware SIN instruction as
// math.sin(x); the only difference is the turns->radians scale on input
// and the sign flip on output, both foldable into two float ops around
// it -- no runtime subroutine needed.
//
// (Inversion note: PICO-8's sin returns -sin at 0.25 turns -- sin(0.25)
// is -1 -- because the y axis points down on screen. Celeste's bobbing
// amplitudes etc. were authored against that convention, so the flip
// must not be dropped.)
bool emit_pico8_sin_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "PICO-8 sin() expects exactly one argument: sin(x)");
        return false;
    }

    emit_asm ("    ;; --- Intrinsic: PICO-8 sin(x) [turns, inverted] ---\n");

    int arg_reg = allocate_register ();
    generate_asm (arg, arg_reg);

    // 1. turns -> radians: x = x * 2*PI   (FMUL is two-operand: Rx *= Ry)
    int tmp_reg = allocate_register ();
    emit_asm ("    MOV  R%d, 6.283185307179586 ; 2*PI\n", tmp_reg);
    emit_asm ("    FMUL R%d, R%d ; x = x * 2*PI (turns -> radians)\n",
               arg_reg, tmp_reg);

    // 2. hardware sine (same instruction math.sin uses)
    emit_asm ("    SIN  R%d ; sin(radians)\n", arg_reg);

    // 3. invert: result = 0 - result   (no FNEG; FSUB from a zero reg)
    emit_asm ("    MOV  R%d, 0\n", tmp_reg);
    emit_asm ("    FSUB R%d, R%d ; pico8 flip: 0 - sin\n", tmp_reg, arg_reg);

    if (dest_reg != 0) {
        emit_asm ("    MOV  R%d, R%d ; Transfer result to dest_reg\n",
                   dest_reg, tmp_reg);
    }

    unlock_register (tmp_reg);
    unlock_register (arg_reg);
    return true;
}

// ============================================================================
// PICO-8 cos(x) -- x in TURNS (1.0 = full circle), NOT inverted
// ============================================================================
// pico8 cos(x) = cos(x * 2*PI). Unlike sin(), PICO-8's cos is a plain
// cosine: cos(0)=1, cos(0.25)=0, cos(0.5)=-1. (The sin inversion exists
// to match the screen's down-pointing y axis; cos has no such stake.)
// So: scale turns->radians, hardware COS, no sign flip.
//
// NOTE the tempting identity that is WRONG here: cos(x) is NOT
// sin(x + 0.25) under PICO-8 semantics -- it is -sin(x + 0.25), because
// sin itself is inverted. Going straight to COS avoids that trap.
bool emit_pico8_cos_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "PICO-8 cos() expects exactly one argument: cos(x)");
        return false;
    }

    emit_asm ("    ;; --- Intrinsic: PICO-8 cos(x) [turns, not inverted] ---\n");

    int arg_reg = allocate_register ();
    generate_asm (arg, arg_reg);

    // turns -> radians
    int tmp_reg = allocate_register ();
    emit_asm ("    MOV  R%d, 6.283185307179586 ; 2*PI\n", tmp_reg);
    emit_asm ("    FMUL R%d, R%d ; x = x * 2*PI (turns -> radians)\n",
               arg_reg, tmp_reg);

    // There is NO COS instruction on Vircon32 (only SIN/ACOS/ATAN2) -- the
    // old "COS Rn" failed to assemble. cos(r) = sin(r + PI/2), no flip.
    emit_asm ("    FADD R%d, 1.5707963267948966 ; + PI/2\n", arg_reg);
    emit_asm ("    SIN  R%d ; cos(radians) = sin(radians + PI/2)\n", arg_reg);

    if (dest_reg != 0) {
        emit_asm ("    MOV  R%d, R%d ; Transfer result to dest_reg\n",
                   dest_reg, arg_reg);
    }

    unlock_register (tmp_reg);
    unlock_register (arg_reg);
    return true;
}

// ============================================================================
// PICO-8 tan(x) -- x in TURNS, inverted (inherited from sin/cos)
// ============================================================================
// pico8 tan(x) = pico8_sin(x) / pico8_cos(x)
//             = (-sin_rad(2*PI*x)) / cos_rad(2*PI*x)
//             = -tan_rad(2*PI*x).
// The inversion is inherited, not chosen: tan is defined as sin/cos, and
// only the sin half is flipped. Reuses the existing __builtin_tan runtime
// routine (same one math.tan delegates to): scale turns->radians, CALL,
// flip the sign of R0.
//
// celeste.lua never calls tan(); this exists for API completeness.
bool emit_pico8_tan_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "PICO-8 tan() expects exactly one argument: tan(x)");
        return false;
    }

    emit_asm ("    ;; --- Intrinsic: PICO-8 tan(x) [turns, inverted] ---\n");

    int arg_reg = allocate_register ();
    generate_asm (arg, arg_reg);

    // turns -> radians
    int tmp_reg = allocate_register ();
    emit_asm ("    MOV  R%d, 6.283185307179586 ; 2*PI\n", tmp_reg);
    emit_asm ("    FMUL R%d, R%d ; x = x * 2*PI (turns -> radians)\n",
               arg_reg, tmp_reg);

    // delegate to the runtime routine math.tan uses ([BP+2] = radians)
    emit_asm ("    PUSH R%d ; radians argument\n", arg_reg);
    emit_asm ("    CALL __builtin_tan\n");
    emit_asm ("    IADD SP, 1 ; Clean up tan() argument\n");

    // flip: result = 0 - R0   (no FNEG; FSUB from a zero reg)
    emit_asm ("    MOV  R%d, 0\n", tmp_reg);
    emit_asm ("    FSUB R%d, R0 ; pico8 flip: 0 - tan\n", tmp_reg);

    if (dest_reg != 0) {
        emit_asm ("    MOV  R%d, R%d ; Transfer result to dest_reg\n",
                   dest_reg, tmp_reg);
    }

    unlock_register (tmp_reg);
    unlock_register (arg_reg);
    return true;
}

// ============================================================================
// PICO-8 camera([x, y]) -> set draw offset; no args resets to (0,0)
// ============================================================================
bool emit_pico8_camera_intrinsic (ASTNode *node, int dest_reg)
{
    int      arg_count = 0;
    ASTNode *curr      = node->as.call.args_head;
    ASTNode *args[2]   = { NULL, NULL };
    while (curr != NULL && arg_count < 2) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count > 2) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "PICO-8 camera() expects at most 2 arguments: camera([x, y])");
        return false;
    }

    // Push right-to-left: y (or NIL), then x (or NIL)
    for (int i = 1; i >= 0; i--) {
        if (args[i] != NULL) {
            int reg = allocate_register ();
            generate_asm (args[i], reg);
            emit_asm ("    PUSH R%d ; Arg %d\n", reg, i + 1);
            unlock_register (reg);
        } else {
            emit_asm ("    MOV R0, BOXED_NIL\n");
            emit_asm ("    PUSH R0 ; Arg %d absent -> reset to 0\n", i + 1);
        }
    }

    emit_asm ("    CALL __builtin_pico8_camera\n");
    emit_asm ("    IADD SP, 2 ; Clean up camera() arguments\n");

    if (dest_reg != 0) {
        emit_asm ("    MOV R%d, R0\n", dest_reg);   // BOXED_NIL
    }
    return true;
}

// ============================================================================
// Shared argument-pusher for the PICO-8 shape primitives.
// Evaluates args right-to-left into pinned registers and pushes them, so a
// nested CALL inside any argument expression can't clobber an already-
// evaluated one. NIL-pads absent trailing arguments.
// ============================================================================
static bool pico8_push_args (ASTNode *node, int max_args,
                             const char *names[], int *out_arg_count)
{
    ASTNode *args[16] = { NULL };
    int      arg_count = 0;
    if (max_args > 16) max_args = 16;
    for (ASTNode *curr = node->as.call.args_head;
         curr != NULL && arg_count < max_args; curr = curr->next) {
        args[arg_count++] = curr;
    }
    *out_arg_count = arg_count;

    for (int i = max_args - 1; i >= 0; i--) {
        int reg = allocate_register ();
        register_pinned[reg] = 1;
        if (i < arg_count) {
            generate_asm (args[i], reg);
            emit_asm ("    PUSH R%d ; Arg %d: %s\n", reg, i + 1, names[i]);
        } else {
            emit_asm ("    MOV R%d, BOXED_NIL ; Default %s\n", reg, names[i]);
            emit_asm ("    PUSH R%d\n", reg);
        }
        register_pinned[reg] = 0;
        unlock_register (reg);
    }
    return true;
}

// ============================================================================
// PICO-8 rectfill(x0, y0, x1, y1 [, color]) -- filled rectangle from corners
// ============================================================================
// Runtime: __builtin_pico8_rectfill. Corner order is normalized at runtime
// (FMIN/FMAX); color defaults per PICO-8 to the current draw color, which
// this API layer does not track -- absent color NIL-pads and the runtime
// clamps to 0. celeste always passes an explicit color.
bool emit_pico8_rectfill_intrinsic (ASTNode *node, int dest_reg)
{
    static const char *names[5] = { "x0", "y0", "x1", "y1", "color" };
    int arg_count = 0;
    pico8_push_args (node, 5, names, &arg_count);

    if (arg_count < 4) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "PICO-8 rectfill() expects at least 4 arguments: "
            "rectfill(x0, y0, x1, y1 [, color])");
        return false;
    }

    emit_asm ("    CALL __builtin_pico8_rectfill\n");
    emit_asm ("    IADD SP, 5 ; Clean up rectfill() arguments\n");

    if (dest_reg != 0) {
        emit_asm ("    MOV R%d, R0\n", dest_reg);
    }
    return true;
}

// ============================================================================
// PICO-8 circfill(x, y, r [, color]) -- filled circle
// ============================================================================
bool emit_pico8_circfill_intrinsic (ASTNode *node, int dest_reg)
{
    static const char *names[4] = { "x", "y", "radius", "color" };
    int arg_count = 0;
    pico8_push_args (node, 4, names, &arg_count);

    if (arg_count < 3) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "PICO-8 circfill() expects at least 3 arguments: "
            "circfill(x, y, r [, color])");
        return false;
    }

    emit_asm ("    CALL __builtin_pico8_circfill\n");
    emit_asm ("    IADD SP, 4 ; Clean up circfill() arguments\n");

    if (dest_reg != 0) {
        emit_asm ("    MOV R%d, R0\n", dest_reg);
    }
    return true;
}

// ============================================================================
// PICO-8 line(x0, y0, x1, y1 [, color]) -- 1px line between two points
// ============================================================================
bool emit_pico8_line_intrinsic (ASTNode *node, int dest_reg)
{
    static const char *names[5] = { "x0", "y0", "x1", "y1", "color" };
    int arg_count = 0;
    pico8_push_args (node, 5, names, &arg_count);

    if (arg_count < 4) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "PICO-8 line() expects at least 4 arguments: "
            "line(x0, y0, x1, y1 [, color])");
        return false;
    }

    emit_asm ("    CALL __builtin_pico8_line\n");
    emit_asm ("    IADD SP, 5 ; Clean up line() arguments\n");

    if (dest_reg != 0) {
        emit_asm ("    MOV R%d, R0\n", dest_reg);
    }
    return true;
}

// ============================================================================
// PICO-8 print(str [, x [, y [, color]]])
// ============================================================================
// Wraps __builtin_print via __builtin_pico8_print, which converts PICO-8
// screen coordinates (camera-adjusted, scaled, centered) to Vircon32 ones.
// PICO-8's no-coordinate form prints at the cursor; this layer has no
// cursor, so absent x/y NIL-pad and the runtime clamps to (0,0).
// celeste always passes x and y.
//
// DISPATCH NOTE: the generic print() handler in try_emit_call_intrinsic()
// runs BEFORE the console-API if/else chain -- add a needs_pico8 guard
// there (or check print here first in the pico8 section), exactly like
// the music() dispatch-order fix.
bool emit_pico8_print_intrinsic (ASTNode *node, int dest_reg)
{
    static const char *names[4] = { "str", "x", "y", "color" };
    int arg_count = 0;
    pico8_push_args (node, 4, names, &arg_count);

    if (arg_count < 1) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "PICO-8 print() expects at least 1 argument: print(str [, x [, y [, color]]])");
        return false;
    }

    emit_asm ("    CALL __builtin_pico8_print\n");
    emit_asm ("    IADD SP, 4 ; Clean up print() arguments\n");

    if (dest_reg != 0) {
        emit_asm ("    MOV R%d, R0 ; passthrough string\n", dest_reg);
    }
    return true;
}

// ============================================================================
// Warn once per compile about a PICO-8 call that is accepted but has no
// Vircon32 equivalent (so carts that use it still build).
// ============================================================================
static void pico8_warn_unsupported_once (int *flag, int line, const char *what)
{
    if (*flag) return;
    *flag = 1;
    compiler_warning (ERR_SEMANTIC, line, "%s", what);
}

// Shared shape for the simple "push N args, CALL, result in R0" primitives.
static bool pico8_simple_call (ASTNode *node, int dest_reg, int max_args,
                               const char *names[], int min_args,
                               const char *routine, const char *usage)
{
    int arg_count = 0;
    pico8_push_args (node, max_args, names, &arg_count);
    if (arg_count < min_args) {
        compiler_error (ERR_SEMANTIC, node->line_number, "PICO-8 %s", usage);
        return false;
    }
    emit_asm ("    CALL %s\n", routine);
    emit_asm ("    IADD SP, %d\n", max_args);
    if (dest_reg != 0) {
        emit_asm ("    MOV R%d, R0\n", dest_reg);
    }
    return true;
}

// rect(x0, y0, x1, y1 [, col]) -- rectangle outline
bool emit_pico8_rect_intrinsic (ASTNode *node, int dest_reg)
{
    static const char *names[5] = { "x0", "y0", "x1", "y1", "color" };
    return pico8_simple_call (node, dest_reg, 5, names, 4, "__builtin_pico8_rect",
                              "rect() expects at least 4 arguments: rect(x0, y0, x1, y1 [, color])");
}

// pset(x, y [, col])
bool emit_pico8_pset_intrinsic (ASTNode *node, int dest_reg)
{
    static const char *names[3] = { "x", "y", "color" };
    return pico8_simple_call (node, dest_reg, 3, names, 2, "__builtin_pico8_pset",
                              "pset() expects at least 2 arguments: pset(x, y [, color])");
}

// circ(x, y [, r [, col]]) -- circle outline
bool emit_pico8_circ_intrinsic (ASTNode *node, int dest_reg)
{
    static const char *names[4] = { "x", "y", "radius", "color" };
    return pico8_simple_call (node, dest_reg, 4, names, 2, "__builtin_pico8_circ",
                              "circ() expects at least 2 arguments: circ(x, y [, r [, color]])");
}

// color([col]) -- set the pen used when a primitive's color is omitted
bool emit_pico8_color_intrinsic (ASTNode *node, int dest_reg)
{
    static const char *names[1] = { "color" };
    return pico8_simple_call (node, dest_reg, 1, names, 0, "__builtin_pico8_color", "");
}

// fget(n [, f]) -- sprite flags from __gff__ (number, or boolean for bit f)
bool emit_pico8_fget_intrinsic (ASTNode *node, int dest_reg)
{
    static const char *names[2] = { "sprite", "flag" };
    return pico8_simple_call (node, dest_reg, 2, names, 1, "__builtin_pico8_fget",
                              "fget() expects 1 or 2 arguments: fget(n [, f])");
}

// fset(n, [f,] v)
bool emit_pico8_fset_intrinsic (ASTNode *node, int dest_reg)
{
    static const char *names[3] = { "sprite", "flag_or_value", "value" };
    return pico8_simple_call (node, dest_reg, 3, names, 2, "__builtin_pico8_fset",
                              "fset() expects 2 or 3 arguments: fset(n, [f,] v)");
}

// pal() / palt() -- palette remapping has no cheap Vircon32 equivalent
// (sprite colors are baked into the texture). Accepted as no-ops with one
// warning so carts still build; arguments are still evaluated for their
// side effects.
bool emit_pico8_pal_intrinsic (ASTNode *node, int dest_reg, const char *name)
{
    static int warned_pal = 0, warned_palt = 0;
    int *flag = (strcmp (name, "palt") == 0) ? &warned_palt : &warned_pal;
    char msg[160];
    snprintf (msg, sizeof (msg),
              "%s() is not supported on Vircon32 (palette remapping of baked sprite "
              "colors); calls compile to no-ops", name);
    pico8_warn_unsupported_once (flag, node->line_number, msg);

    for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next) {
        if (a->type == NODE_NUMBER || a->type == NODE_NIL || a->type == NODE_BOOLEAN ||
            a->type == NODE_STRING || a->type == NODE_IDENTIFIER) {
            continue;   // no side effects to preserve
        }
        int reg = allocate_register ();
        generate_asm (a, reg);
        unlock_register (reg);
    }
    if (dest_reg != 0) {
        emit_asm ("    MOV R%d, BOXED_NIL ; %s() returns nil here\n", dest_reg, name);
    }
    return true;
}

// sspr(sx, sy, sw, sh, dx, dy [, dw, dh [, flip_x, flip_y]])
bool emit_pico8_sspr_intrinsic (ASTNode *node, int dest_reg)
{
    static const char *names[10] = { "sx", "sy", "sw", "sh", "dx", "dy",
                                     "dw", "dh", "flip_x", "flip_y" };
    return pico8_simple_call (node, dest_reg, 10, names, 6, "__builtin_pico8_sspr",
        "sspr() expects at least 6 arguments: sspr(sx, sy, sw, sh, dx, dy [, dw, dh [, flip_x, flip_y]])");
}

/**
 * PICO-8 sqrt(x): like math.sqrt, but a negative x gives 0 (as in PICO-8)
 * rather than NaN -- which here would be read back as a boxed value.
 */
bool emit_pico8_sqrt_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;
    if (arg == NULL || arg->next != NULL) {
        compiler_error(ERR_SEMANTIC, node->line_number, "PICO-8 sqrt() expects 1 argument");
        return false;
    }
    emit_asm("    ;; --- PICO-8 sqrt(x) Intrinsic ---\n");
    int x_reg = (dest_reg != 0) ? dest_reg : allocate_register();
    generate_asm(arg, x_reg);
    ensure_in_register(x_reg);
    int t_reg = allocate_register();
    mark_register_live(t_reg, 1);
    emit_asm("MOV  R%d, 0.0\n", t_reg);
    emit_asm("FMAX R%d, R%d ; sqrt(negative) = 0, as in PICO-8\n", x_reg, t_reg);
    emit_asm("MOV  R%d, 0.5\n", t_reg);
    emit_asm("POW  R%d, R%d\n", x_reg, t_reg);
    unlock_register(t_reg);
    if (dest_reg == 0) unlock_register(x_reg);
    return true;
}

/**
 * PICO-8 flip(): show the frame drawn so far and wait for the next one
 * (1/30 s, or 1/60 s in an _update60 cart). Carts that run their own loop
 * (`while true do ... flip() end`, typically from _init) depend on it.
 */
bool emit_pico8_flip_intrinsic(ASTNode *node, int dest_reg)
{
    (void) node;
    emit_asm("    ;; --- PICO-8 flip() ---\n");
    emit_asm("CALL __builtin_pico8_flip\n");
    if (dest_reg != 0) emit_asm("MOV R%d, BOXED_NIL\n", dest_reg);
    return true;
}
