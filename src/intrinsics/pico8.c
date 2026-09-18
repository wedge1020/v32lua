#include "v32lua.h"

#define MAX_SPR_ARGS 7  // n, x, y, w, h, flip_x, flip_y

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
bool emit_pico8_spr_intrinsic(ASTNode *node)
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
bool emit_pico8_btn_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- PICO-8 btn() Intrinsic ---\n");

    // --- Collect up to 2 arguments (button_id, player_id) ---
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[2] = { NULL };
    while (curr != NULL && arg_count < 2) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    // --- Push arguments right-to-left (standard ABI) ---

    // Arg 1: Player ID (default = 0)
    int reg = allocate_register();
    register_pinned[reg] = 1;
    if (arg_count > 1) {
        generate_asm(args[1], reg);
        emit_asm("PUSH R%d ; Arg 2: Player ID\n", reg);
    } else {
        emit_asm("MOV R%d, 0.000000 ; Default Player 0\n", reg);
        emit_asm("PUSH R%d\n", reg);
    }
    register_pinned[reg] = 0;
    unlock_register(reg);

    // Arg 0: Button ID (or BOXED_NIL for bitfield mode)
    reg = allocate_register();
    register_pinned[reg] = 1;
    if (arg_count > 0) {
        generate_asm(args[0], reg);
        emit_asm("PUSH R%d ; Arg 1: Button ID\n", reg);
    } else {
        emit_asm("MOV R%d, BOXED_NIL ; Trigger bitfield mode\n", reg);
        emit_asm("PUSH R%d\n", reg);
    }
    register_pinned[reg] = 0;
    unlock_register(reg);

    // --- Call runtime subroutine and clean up stack ---
    emit_asm("CALL __builtin_pico8_btn\n");
    emit_asm("IADD SP, 2 ; Clean up btn() arguments\n");

    // Transfer result from R0 to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }

    return true;
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
bool emit_pico8_map_intrinsic(ASTNode *node) {
    emit_asm("    ;; --- PICO-8 map() Intrinsic ---\n");

    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[7] = { NULL };
    while (curr != NULL && arg_count < 7) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count < 6) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "PICO-8 map() requires at least 6 arguments: "
                      "map(celx, cely, sx, sy, celw, celh)");
        return false;
    }

    // Push right-to-left: layer (or default 0), celh, celw, sy, sx, cely, celx
    if (arg_count >= 7) {
        int reg = allocate_register();
        generate_asm(args[6], reg);  // layer
        emit_asm("PUSH R%d ; Arg 7: layer\n", reg);
        unlock_register(reg);
    } else {
        emit_asm("MOV R0, 0.000000 ; Default layer (draw everything)\n");
        emit_asm("PUSH R0 ; Arg 7: layer (default)\n");
    }

    static const char *names[6] = { "celx", "cely", "sx", "sy", "celw", "celh" };
    for (int i = 5; i >= 0; i--) {
        int reg = allocate_register();
        generate_asm(args[i], reg);
        emit_asm("PUSH R%d ; Arg %d: %s\n", reg, i + 1, names[i]);
        unlock_register(reg);
    }

    emit_asm("CALL __builtin_pico8_map\n");
    emit_asm("IADD SP, 7 ; Clean up map() arguments\n");

    return true;
}

/**
 * Emits assembly for PICO-8 cls(color) intrinsic
 * color can be: palette index (0-15), hex string ("0xRRGGBB"), or hex number
 */
bool emit_pico8_cls_intrinsic(ASTNode *node) {
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

    return true;
}

/**
 * Emits assembly for the btnp() intrinsic (PICO-8 compatibility).
 *
 * Syntax:
 *   btnp(id) -> returns true if button was pressed this frame
 *   btnp(id, hold) -> returns true with custom hold
 *   btnp(id, hold, period) -> returns true with custom hold and period
 *
 * @param node     The AST node representing the function call.
 * @param dest_reg The destination register for the result (0 = discard).
 * @return          true if successfully emitted, false on error.
 */
bool emit_pico8_btnp_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- PICO-8 btnp() Intrinsic ---\n");

    // Collect up to 3 arguments (id, hold, period)
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[3] = { NULL };
    while (curr != NULL && arg_count < 3) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    // Push arguments right-to-left (standard ABI)
    // Order: period (2), hold (1), id (0)

    // Arg 2: period (default = -1)
    int reg = allocate_register();
    register_pinned[reg] = 1;
    if (arg_count > 2) {
        generate_asm(args[2], reg);
    } else {
        emit_asm("MOV R%d, -1.000000 ; Default period\n", reg);
    }
    emit_asm("PUSH R%d ; Arg 3: period\n", reg);
    register_pinned[reg] = 0;
    unlock_register(reg);

    // Arg 1: hold (default = -1)
    reg = allocate_register();
    register_pinned[reg] = 1;
    if (arg_count > 1) {
        generate_asm(args[1], reg);
    } else {
        emit_asm("MOV R%d, -1.000000 ; Default hold\n", reg);
    }
    emit_asm("PUSH R%d ; Arg 2: hold\n", reg);
    register_pinned[reg] = 0;
    unlock_register(reg);

    // Arg 0: Button ID (required)
    reg = allocate_register();
    register_pinned[reg] = 1;
    if (arg_count > 0) {
        generate_asm(args[0], reg);
    } else {
        emit_asm("MOV R%d, BOXED_NIL ; Missing required arg!\n", reg);
    }
    emit_asm("PUSH R%d ; Arg 1: Button ID\n", reg);
    register_pinned[reg] = 0;
    unlock_register(reg);

    // Call runtime subroutine and clean up stack
    emit_asm("CALL __builtin_pico8_btnp\n");
    emit_asm("IADD SP, 3 ; Clean up btnp() arguments\n");

    // Transfer result from R0 to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }

    return true;
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

    emit_asm("CALL __builtin_random ; no args -> R0 = float in [0,1)\n");

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

    int a_reg = allocate_register();
    int b_reg = allocate_register();
    int c_reg = allocate_register();
    generate_asm(arg, a_reg);
    generate_asm(arg->next, b_reg);
    generate_asm(arg->next->next, c_reg);

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

