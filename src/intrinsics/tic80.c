#include "v32lua.h"
#include "tic80_assets.h"

#define MAX_TIC80_SPR_ARGS 9  // id, x, y, colorkey, scale, flip, rotate, w, h

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
            emit_asm("MOV R%d, 16.000000 ; Default colorkey\n", reg);
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

// Add to tic80.c
bool emit_tic80_print_intrinsic(ASTNode *node) {
    emit_asm("    ;; --- TIC-80 print(value, x, y) Intrinsic ---\n");

    // Extract arguments: value (arg0), x (arg1), y (arg2)
    ASTNode *arg_val = node->as.call.args_head;
    ASTNode *arg_x   = (arg_val != NULL) ? arg_val->next : NULL;
    ASTNode *arg_y   = (arg_x   != NULL) ? arg_x->next   : NULL;

    if (arg_val == NULL || arg_x == NULL || arg_y == NULL) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                       "TIC-80 print() requires 3 arguments: print(value, x, y)");
    }

    int reg_val = allocate_pinned_register();
    int reg_x   = allocate_pinned_register();
    int reg_y   = allocate_pinned_register();

    generate_asm(arg_val, reg_val);
    generate_asm(arg_x, reg_x);
    generate_asm(arg_y, reg_y);

    // Convert coordinates to hardware integers
    emit_asm("CFI R%d ; Convert X to hardware integer\n", reg_x);
    emit_asm("CFI R%d ; Convert Y to hardware integer\n", reg_y);

    // Push in order expected by runtime: x, y, value
    emit_asm("PUSH R%d ; Push X coordinate\n", reg_x);
    emit_asm("PUSH R%d ; Push Y coordinate\n", reg_y);
    emit_asm("PUSH R%d ; Push value\n", reg_val);

    emit_asm("CALL __builtin_print\n");
    emit_asm("IADD SP, 3 ; Clean up arguments\n");

    unlock_register(reg_val);
    unlock_register(reg_x);
    unlock_register(reg_y);

    return true;
}

/**
 * Emits assembly for the mget() intrinsic (TIC-80 compatibility).
 *
 * Syntax: mget(x, y) -> returns sprite ID at map position (x, y)
 */
bool emit_tic80_mget_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 mget() Intrinsic ---\n");

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
                      "TIC-80 mget() requires 2 arguments: mget(x, y)");
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
    emit_asm("CALL __builtin_tic80_mget\n");
    emit_asm("IADD SP, 2 ; Clean up mget() arguments\n");

    // Transfer result to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the mset() intrinsic (TIC-80 compatibility).
 *
 * Syntax: mset(x, y, v) -> sets sprite ID at map position (x, y) to v
 */
bool emit_tic80_mset_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 mset() Intrinsic ---\n");

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
                      "TIC-80 mset() requires 3 arguments: mset(x, y, v)");
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
    emit_asm("CALL __builtin_tic80_mset\n");
    emit_asm("IADD SP, 3 ; Clean up mset() arguments\n");

    // Transfer result to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the map() intrinsic (TIC-80 compatibility).
 *
 * Syntax: map(x, y, w, h, sx, sy[, color_key])
 * color_key is optional and defaults to 16 (opaque)
 */
bool emit_tic80_map_intrinsic(ASTNode *node) {
    emit_asm("    ;; --- TIC-80 map() Intrinsic ---\n");

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
                      "TIC-80 map() requires at least 6 arguments: map(x, y, w, h, sx, sy)");
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
    emit_asm("CALL __builtin_tic80_map\n");
    emit_asm("IADD SP, 7 ; Clean up map() arguments (now 7 total)\n");

    return true;
}

// ============================================================================
// Sound API Intrinsics
// ============================================================================

bool emit_tic80_play_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 play() Intrinsic ---\n");

    // play(sound_id, channel, volume, speed)
    // Maps to SPU registers

    ASTNode *args[4] = {NULL};
    int arg_count = 0;
    for (ASTNode *curr = node->as.call.args_head; curr && arg_count < 4; curr = curr->next) {
        args[arg_count++] = curr;
    }

    // Set selected sound
    if (args[0]) {
        generate_asm(args[0], 1);  // R1 = sound_id
        emit_asm("OUT SPU_SelectedSound, R1\n");
    }

    // Set channel (default 0)
    if (args[1]) {
        generate_asm(args[1], 1);
        emit_asm("OUT SPU_SelectedChannel, R1\n");
    } else {
        emit_asm("MOV R1, 0\n");
        emit_asm("OUT SPU_SelectedChannel, R1\n");
    }

    // Set volume (default 1.0)
    if (args[2]) {
        generate_asm(args[2], 1);
        emit_asm("OUT SPU_ChannelVolume, R1\n");
    }

    // Set speed (default 1.0)
    if (args[3]) {
        generate_asm(args[3], 1);
        emit_asm("OUT SPU_ChannelSpeed, R1\n");
    }

    // Play command
    emit_asm("OUT SPU_Command, SPUCommand_PlaySelectedChannel\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
    }

    return true;
}

bool emit_tic80_sfx_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 sfx() Intrinsic ---\n");

    // sfx(sfx_id, channel, volume, speed)
    // Same as play() but for SFX (0-31)

    // For now, just map to play() with SFX offset
    ASTNode *sfx_arg = node->as.call.args_head;
    if (sfx_arg) {
        // Convert SFX ID to sound ID (assuming SFX are stored first)
        generate_asm(sfx_arg, 1);
        emit_asm("IADD R1, %d ; SFX offset\n", 0); // TODO: actual offset
    }

    // Call play intrinsic with modified sound ID
    // ... (rest similar to play)

    return true;
}

bool emit_tic80_music_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 music() Intrinsic ---\n");

    // music(track_id, channel, volume, speed)
    // TODO: Implement music playback

    return true;
}
