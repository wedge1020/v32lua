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
 * Emits assembly for the Pico-8 add() intrinsic.
 *
 * Syntax:
 *   add(t)                -> error (need at least 2 args)
 *   add(t, v)             -> append v to end of table t
 *   add(t, v, i)          -> insert v at position i in table t
 *
 * Returns the value that was added (Pico-8 behavior).
 *
 * @param node     The AST node representing the function call.
 * @param dest_reg The destination register for the result (0 = discard).
 * @return          true if successfully emitted, false on error.
 */
bool emit_pico8_add_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- PICO-8 add() Intrinsic ---\n");

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
        // TODO: Emit error or handle gracefully
        return false;
    }

    // --- Push arguments right-to-left (standard ABI) ---
    // Order on stack: index (or nil), value, table
    // This matches __builtin_add expected stack: [BP+4]=table, [BP+3]=value, [BP+2]=index

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
    emit_asm("CALL __builtin_pico8_add\n");

    // --- Clean up stack (3 arguments) ---
    emit_asm("IADD SP, 3 ; Clean up add() arguments\n");

    // --- Transfer return value if needed ---
    // __builtin_add returns the inserted value in R0 (Pico-8 add() behavior)
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value (the inserted value)\n", dest_reg);
    }

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
 * Syntax: map(x, y, w, h, sx, sy[, color_key])
 * color_key is optional and defaults to 16 (opaque)
 */
bool emit_pico8_map_intrinsic(ASTNode *node) {
    emit_asm("    ;; --- PICO-8 map() Intrinsic ---\n");

    // Collect up to 7 arguments
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[7] = { NULL }; // Now supports 7 arguments
    while (curr != NULL && arg_count < 7) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count < 6) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "PICO-8 map() requires at least 6 arguments: map(x, y, w, h, sx, sy)");
        return false;
    }

    // Push arguments right-to-left: color_key (or default), sy, sx, h, w, y, x
    // If color_key is not provided, push 16 (opaque) as default
    if (arg_count >= 7) {
        int reg = allocate_register();
        generate_asm(args[6], reg);  // color_key
        emit_asm("PUSH R%d ; Arg 7: color_key\n", reg);
        unlock_register(reg);
    } else {
        emit_asm("MOV R0, 16.000000 ; Default color_key (opaque)\n");
        emit_asm("PUSH R0 ; Arg 7: color_key (default)\n");
    }

    // Push the 6 required arguments (sy, sx, h, w, y, x)
    for (int i = 5; i >= 0; i--) {
        int reg = allocate_register();
        generate_asm(args[i], reg);
        emit_asm("PUSH R%d ; Arg %d: %s\n", reg, i+1,
                 i == 0 ? "x" : (i == 1 ? "y" : (i == 2 ? "w" :
                 (i == 3 ? "h" : (i == 4 ? "sx" : "sy")))));
        unlock_register(reg);
    }

    // Call runtime subroutine
    emit_asm("CALL __builtin_pico8_map\n");
    emit_asm("IADD SP, 7 ; Clean up map() arguments (now 7 total)\n");

    return true;
}

/**
 * Emits assembly for PICO-8 cls(color) intrinsic
 * color can be: palette index (0-15), hex string ("0xRRGGBB"), or hex number
 */
bool emit_pico8_cls_intrinsic(ASTNode *node) {
    emit_asm("    ;; --- PICO-8 cls() Intrinsic ---\n");

    ASTNode *arg = node->as.call.args_head;

    if (arg == NULL) {
        // Default: clear to black (palette index 0)
        //    emit_asm("MOV R1, 0x%.8X ; cls() with palette index 0\n",
           //          pico8_palette[0]);
    }
    else if (arg->type == NODE_NUMBER) {
        double val = arg->as.number.val;
        int int_val = (int)val;

        if (int_val >= 0 && int_val < 16) {
           //     emit_asm("MOV R1, 0x%.8X ; Palette index %d\n",
               //          pico8_palette[int_val], int_val);
        } else {
            // Treat as direct color value
            emit_asm("MOV R1, ");
            generate_asm(arg, 1);
            emit_asm("\n");
        }
    }
    else if (arg->type == NODE_STRING) {
        // Parse hex string like "0xFFFFCCCC" or "#RRGGBB"
        const char *color_str = arg->as.string_val.value;
        unsigned int color = 0xFF000000; // Default black if parse fails

        if (color_str[0] == '0' && (color_str[1] == 'x' || color_str[1] == 'X')) {
            if (sscanf(color_str + 2, "%x", &color) == 1) {
                // Ensure alpha channel is set for 6-digit hex (0xRRGGBB)
                if (strlen(color_str) == 8) { // "0xRRGGBB" is 8 chars
                    color |= 0xFF; // Make opaque
                }
            }
        }
        // Handle CSS-style hex (#RRGGBB)
        else if (color_str[0] == '#' && strlen(color_str) == 7) {
            if (sscanf(color_str + 1, "%x", &color) == 1) {
                color |= 0xFF; // Make opaque
            }
        }

        emit_asm("MOV R1, 0x%.8X ; Hex color from string\n", color);
    }
    else {
        // Dynamic expression - evaluate at runtime
        int reg = allocate_register();
        generate_asm(arg, reg);
        emit_asm("MOV R1, R%d ; Color from expression\n", reg);
        unlock_register(reg);
    }

    emit_asm("OUT GPU_ClearColor, R1\n");
    emit_asm("OUT GPU_Command, GPUCommand_ClearScreen\n");

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
