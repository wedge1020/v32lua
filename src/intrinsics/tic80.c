#include "v32lua.h"

#define MAX_TIC80_SPR_ARGS 9  // id, x, y, colorkey, scale, flip, rotate, w, h

/**
 * Emits assembly for the spr() intrinsic (TIC-80 compatibility).
 *
 * Syntax:
 *   spr(id, x, y)
 *   spr(id, x, y, colorkey)
 *   spr(id, x, y, colorkey, scale)
 *   spr(id, x, y, colorkey, scale, flip)
 *   spr(id, x, y, colorkey, scale, flip, rotate)
 *   spr(id, x, y, colorkey, scale, flip, rotate, w, h)
 *
 * @param node The AST node representing the function call.
 * @return     true if successfully emitted, false on error.
 */
bool emit_tic80_spr_intrinsic(ASTNode *node)
{
    emit_asm("    ;; --- TIC-80 spr() Intrinsic ---\n");

    // --- Collect up to MAX_TIC80_SPR_ARGS arguments ---
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[MAX_TIC80_SPR_ARGS] = { NULL };
    while (curr != NULL && arg_count < MAX_TIC80_SPR_ARGS) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    // --- Push arguments right-to-left (standard ABI) ---
    // Order: h (9), rotate (8), flip (7), scale (6), colorkey (5), y (4), x (3), id (2)

    // Args 9-8: h, rotate (default = 1, 0)
    for (int i = 9; i >= 8; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (arg_count > i) {
            generate_asm(args[i], reg);
            emit_asm("PUSH R%d ; Arg %d: %s\n", reg, i - 1, i == 9 ? "h" : "rotate");
        } else {
            emit_asm("MOV R%d, %s ; Default %s\n", reg, i == 9 ? "1.000000" : "0.000000", i == 9 ? "h" : "rotate");
            emit_asm("PUSH R%d\n", reg);
        }
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    // Args 7-6: flip, scale (default = 0, 1)
    for (int i = 7; i >= 6; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (arg_count > i) {
            generate_asm(args[i], reg);
            emit_asm("PUSH R%d ; Arg %d: %s\n", reg, i - 1, i == 7 ? "flip" : "scale");
        } else {
            emit_asm("MOV R%d, %s ; Default %s\n", reg, i == 7 ? "0.000000" : "1.000000", i == 7 ? "flip" : "scale");
            emit_asm("PUSH R%d\n", reg);
        }
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    // Args 5-4: colorkey, y (default = -1, required)
    for (int i = 5; i >= 4; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (arg_count > i) {
            generate_asm(args[i], reg);
        } else if (i == 5) {
            emit_asm("MOV R%d, -1.000000 ; Default colorkey\n", reg);
        } else {
            emit_asm("MOV R%d, BOXED_NIL ; Missing required arg!\n", reg);
        }
        emit_asm("PUSH R%d ; Arg %d: %s\n", reg, i - 1, i == 5 ? "colorkey" : "y");
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    // Args 3-2: x, id (required)
    for (int i = 3; i >= 2; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (arg_count > (i - 2)) {
            generate_asm(args[i - 2], reg);
        } else {
            emit_asm("MOV R%d, BOXED_NIL ; Missing required arg!\n", reg);
        }
        emit_asm("PUSH R%d ; Arg %d: %s\n", reg, i - 1, i == 3 ? "x" : "id");
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    // --- Call runtime subroutine and clean up stack ---
    emit_asm("CALL __builtin_tic80_spr\n");
    emit_asm("IADD SP, %d ; Clean up spr() arguments\n", MAX_TIC80_SPR_ARGS);

    return true;
}

/**
 * Emits assembly for the btn() intrinsic (TIC-80 compatibility).
 *
 * Syntax:
 *   btn(id) -> returns true if button is pressed
 *
 * @param node     The AST node representing the function call.
 * @param dest_reg The destination register for the result (0 = discard).
 * @return          true if successfully emitted, false on error.
 */
bool emit_tic80_btn_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- TIC-80 btn() Intrinsic ---\n");

    // --- Collect up to 1 argument (button_id) ---
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[1] = { NULL };
    while (curr != NULL && arg_count < 1) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    // --- Push arguments right-to-left (standard ABI) ---
    // Arg 0: Button ID (required)
    int reg = allocate_register();
    register_pinned[reg] = 1;
    if (arg_count > 0) {
        generate_asm(args[0], reg);
    } else {
        emit_asm("MOV R%d, BOXED_NIL ; Missing required arg!\n", reg);
    }
    emit_asm("PUSH R%d ; Arg 1: Button ID\n", reg);
    register_pinned[reg] = 0;
    unlock_register(reg);

    // --- Call runtime subroutine and clean up stack ---
    emit_asm("CALL __builtin_tic80_btn\n");
    emit_asm("IADD SP, 1 ; Clean up btn() arguments\n");

    // Transfer result from R0 to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the btnp() intrinsic (TIC-80 compatibility).
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
bool emit_tic80_btnp_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- TIC-80 btnp() Intrinsic ---\n");

    // --- Collect up to 3 arguments (id, hold, period) ---
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[3] = { NULL };
    while (curr != NULL && arg_count < 3) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    // --- Push arguments right-to-left (standard ABI) ---
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

    // --- Call runtime subroutine and clean up stack ---
    emit_asm("CALL __builtin_tic80_btnp\n");
    emit_asm("IADD SP, 3 ; Clean up btnp() arguments\n");

    // Transfer result from R0 to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the add() intrinsic (TIC-80 compatibility).
 * Maintains PICO-8 behavior for compatibility.
 *
 * Syntax:
 *   add(t, v)             -> append v to end of table t
 *   add(t, v, i)          -> insert v at position i in table t
 *
 * @param node     The AST node representing the function call.
 * @param dest_reg The destination register for the result (0 = discard).
 * @return          true if successfully emitted, false on error.
 */
bool emit_tic80_add_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- TIC-80 add() Intrinsic ---\n");

    // --- Collect up to 3 arguments (table, value, index) ---
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[3] = { NULL, NULL, NULL };
    while (curr != NULL && arg_count < 3) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    // --- Need at least 2 arguments: table and value ---
    if (arg_count < 2) {
        return false;
    }

    // --- Push arguments right-to-left (standard ABI) ---
    // Order on stack: index (or nil), value, table

    // Arg 2: Index (optional, default = nil which means append)
    if (arg_count >= 3) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        generate_asm(args[2], reg);
        emit_asm("PUSH R%d ; Arg 3: index\n", reg);
        register_pinned[reg] = 0;
        unlock_register(reg);
    } else {
        // Default: push NIL to trigger append behavior
        emit_asm("MOV R0, BOXED_NIL ; Default index (nil = append)\n");
        emit_asm("PUSH R0 ; Arg 3: index (default nil)\n");
    }

    // Arg 1: Value (required)
    int val_reg = allocate_register();
    register_pinned[val_reg] = 1;
    generate_asm(args[1], val_reg);
    emit_asm("PUSH R%d ; Arg 2: value\n", val_reg);
    register_pinned[val_reg] = 0;
    unlock_register(val_reg);

    // Arg 0: Table (required)
    int tab_reg = allocate_register();
    register_pinned[tab_reg] = 1;
    generate_asm(args[0], tab_reg);
    emit_asm("PUSH R%d ; Arg 1: table\n", tab_reg);
    register_pinned[tab_reg] = 0;
    unlock_register(tab_reg);

    // --- Call runtime subroutine ---
    emit_asm("CALL __builtin_tic80_add\n");

    // --- Clean up stack (3 arguments) ---
    emit_asm("IADD SP, 3 ; Clean up add() arguments\n");

    // --- Transfer return value if needed ---
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value (the inserted value)\n", dest_reg);
    }

    return true;
}
