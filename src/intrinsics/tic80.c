#include "v32lua.h"

#define MAX_TIC80_SPR_ARGS 9  // id, x, y, colorkey, scale, flip, rotate, w, h

// TIC-80 default 16-color palette (32-bit AABBGGRR for Vircon32 GPU)
// These can be overridden by cartridge PALETTE section
/*
uint32_t tic80_palette[16] = {
    0xFF2C1C1A,
    0xFF5D275D,
    0xFF533EB1,
    0xFF577DEF,
    0xFF75CDFF,
    0xFF70F0A7,
    0xFF64B738,
    0xFF797125,
    0xFF6F3629,
    0xFFC95D3B,
    0xFFF6A641,
    0xFFF7EF73,
    0xFFF4F4F4,
    0xFFC2B094,
    0xFF866C56,
    0xFF573C33
};*/

// Set custom palette from cartridge (called after parsing TIC80 assets)
void tic80_set_custom_palette(const uint32_t *new_palette) {
    for (int i = 0; i < 16; i++) {
        tic80_palette[i] = new_palette[i];
    }
}

/**
 * Emits assembly for the spr() intrinsic (TIC-80 compatibility).
 *
 *      Corrected argument mapping to include 'w' parameter.
 *      Previous code skipped w (args[7]) and pushed h twice.
 *
 * Stack layout:
 *   [BP+2]  = id      (args[0])
 *   [BP+3]  = x       (args[1])
 *   [BP+4]  = y       (args[2])
 *   [BP+5]  = colorkey (args[3])
 *   [BP+6]  = scale   (args[4])
 *   [BP+7]  = flip    (args[5])
 *   [BP+8]  = rotate  (args[6])
 *   [BP+9]  = w       (args[7])
 *   [BP+10] = h       (args[8])
 */
bool emit_tic80_spr_intrinsic(ASTNode *node) {
    emit_asm("    ;; --- TIC-80 spr() Intrinsic ---\n");

    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[9] = { NULL };
    while (curr != NULL && arg_count < 9) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    // Push arguments 10-8 (h, w, rotate)
    for (int stack_pos = 10; stack_pos >= 8; stack_pos--) {
        int arg_idx;
        if (stack_pos == 10) arg_idx = 8;   // h (args[8])
        else if (stack_pos == 9) arg_idx = 7; // w (args[7])
        else arg_idx = 6;                   // rotate (args[6])

        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (arg_count > arg_idx) {
            generate_asm(args[arg_idx], reg);
        } else {
            emit_asm("MOV R%d, %s ; Default %s\n", reg,
                     stack_pos == 10 ? "1.000000" : (stack_pos == 9 ? "1.000000" : "0.000000"),
                     stack_pos == 10 ? "h" : (stack_pos == 9 ? "w" : "rotate"));
        }
        emit_asm("PUSH R%d ; Arg %d: %s\n", reg, stack_pos-1,
                 stack_pos == 10 ? "h" : (stack_pos == 9 ? "w" : "rotate"));
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    // Args 7-6: flip (arg 5), scale (arg 4)
    for (int stack_pos = 7; stack_pos >= 6; stack_pos--) {
        int arg_idx = (stack_pos == 7) ? 5 : 4;
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (arg_count > arg_idx) {
            generate_asm(args[arg_idx], reg);
        } else {
            emit_asm("MOV R%d, %s ; Default %s\n", reg,
                     stack_pos == 7 ? "0.000000" : "1.000000",
                     stack_pos == 7 ? "flip" : "scale");
        }
        emit_asm("PUSH R%d ; Arg %d: %s\n", reg, stack_pos-1,
                 stack_pos == 7 ? "flip" : "scale");
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    // Args 5-4: colorkey (arg 3), y (arg 2)
    for (int stack_pos = 5; stack_pos >= 4; stack_pos--) {
        int arg_idx = stack_pos - 2;
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (arg_count > arg_idx) {
            generate_asm(args[arg_idx], reg);
        } else if (stack_pos == 5) {
            emit_asm("MOV R%d, -1.000000 ; Default colorkey\n", reg);
        } else {
            emit_asm("MOV R%d, BOXED_NIL ; Missing required arg!\n", reg);
        }
        emit_asm("PUSH R%d ; Arg %d: %s\n", reg, stack_pos-1,
                 stack_pos == 5 ? "colorkey" : "y");
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    // Args 3-2: x (arg 1), id (arg 0)
    for (int stack_pos = 3; stack_pos >= 2; stack_pos--) {
        int arg_idx = stack_pos - 2;
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (arg_count > arg_idx) {
            generate_asm(args[arg_idx], reg);
        } else {
            emit_asm("MOV R%d, BOXED_NIL ; Missing required arg!\n", reg);
        }
        emit_asm("PUSH R%d ; Arg %d: %s\n", reg, stack_pos-1,
                 stack_pos == 3 ? "x" : "id");
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    emit_asm("CALL __builtin_tic80_spr\n");
    emit_asm("IADD SP, 9 ; Clean up spr() arguments\n");

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
bool emit_tic80_btn_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 btn() Intrinsic ---\n");

    // Collect up to 1 argument (button_id)
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[1] = { NULL };
    while (curr != NULL && arg_count < 1) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    // Push arguments right-to-left (standard ABI)
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

    // Call runtime subroutine and clean up stack
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
bool emit_tic80_btnp_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 btnp() Intrinsic ---\n");

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
bool emit_tic80_add_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 add() Intrinsic ---\n");

    // Collect up to 3 arguments (table, value, index)
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[3] = { NULL, NULL, NULL };
    while (curr != NULL && arg_count < 3) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    // Need at least 2 arguments: table and value
    if (arg_count < 2) {
        return false;
    }

    // Push arguments right-to-left (standard ABI)
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

    // Call runtime subroutine
    emit_asm("CALL __builtin_tic80_add\n");

    // Clean up stack (3 arguments)
    emit_asm("IADD SP, 3 ; Clean up add() arguments\n");

    // Transfer return value if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value (the inserted value)\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for TIC-80 cls(color) intrinsic
 * color can be: palette index (0-15), hex string ("0xRRGGBB"), or hex number
 */
bool emit_tic80_cls_intrinsic(ASTNode *node) {
    emit_asm("    ;; --- TIC-80 cls() Intrinsic ---\n");

    ASTNode *arg = node->as.call.args_head;

    if (arg == NULL) {
        // Default: clear to black (palette index 0)
        emit_asm("MOV R1, 0x%.8X ; cls() with palette index 0\n",
                 tic80_palette[0]);
    }
    else if (arg->type == NODE_NUMBER) {
        double val = arg->as.number.val;
        int int_val = (int)val;

        if (int_val >= 0 && int_val < 16) {
            emit_asm("MOV R1, 0x%.8X ; Palette index %d\n",
                     tic80_palette[int_val], int_val);
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
