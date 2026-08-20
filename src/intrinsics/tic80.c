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

    // FIX: these registers were allocated with allocate_pinned_register(),
    // which sets register_pinned[reg] = 1. Releasing them with plain
    // unlock_register() clears the inventory slot but leaves the pinned
    // flag set forever -- every phase of allocate_register() except the
    // emergency pinned-register-stealing phase refuses to hand out a
    // pinned register, so each print() call was permanently retiring 3
    // registers from circulation for the rest of compilation. Programs
    // with enough print() calls (or enough of anything else register-
    // hungry downstream) would eventually exhaust the free pool and fall
    // into the emergency path, which silently force-spills a register
    // some OTHER, unrelated piece of code still believes is safely
    // pinned -- corrupting whatever value that code expected to still be
    // there. unlock_pinned_register() clears BOTH the pin and the
    // inventory slot, which is what these registers actually need.
    unlock_pinned_register(reg_val);
    unlock_pinned_register(reg_x);
    unlock_pinned_register(reg_y);

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

/**
 * Emits assembly for the pmem() intrinsic (TIC-80 compatibility).
 *
 * Syntax:
 *   pmem(index)          -> returns byte value at index (read)
 *   pmem(index, value)  -> writes byte value at index, returns value
 */
bool emit_tic80_pmem_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 pmem() Intrinsic ---\n");

    // Collect up to 2 arguments (index, value)
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[2] = { NULL, NULL };
    while (curr != NULL && arg_count < 2) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count < 1) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "TIC-80 pmem() requires at least 1 argument: pmem(index[, value])");
        return false;
    }

    // Push arguments right-to-left: value (if present), index
    if (arg_count >= 2) {
        // Write operation: push value then index
        int reg = allocate_register();
        register_pinned[reg] = 1;
        generate_asm(args[1], reg);  // value
        emit_asm("PUSH R%d ; Arg 2: value\n", reg);
        register_pinned[reg] = 0;
        unlock_register(reg);
    } else {
        // Read operation: push nil as placeholder for value
        emit_asm("MOV R0, BOXED_NIL\n");
        emit_asm("PUSH R0 ; Arg 2: value (nil for read)\n");
    }

    // Push index (always required)
    int reg = allocate_register();
    register_pinned[reg] = 1;
    generate_asm(args[0], reg);  // index
    emit_asm("PUSH R%d ; Arg 1: index\n", reg);
    register_pinned[reg] = 0;
    unlock_register(reg);

    // Call runtime subroutine
    emit_asm("CALL __builtin_tic80_pmem\n");
    emit_asm("IADD SP, 2 ; Clean up pmem() arguments\n");

    // Transfer result to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the fget() intrinsic (TIC-80 sprite flags).
 *
 * Syntax: fget(sprite_id, flag_bit) -> returns 0 or 1
 */
bool emit_tic80_fget_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 fget() Intrinsic (Sprite Flags) ---\n");

    // Collect exactly 2 arguments: sprite_id, flag_bit
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[2] = { NULL, NULL };
    while (curr != NULL && arg_count < 2) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count < 2) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "TIC-80 fget() requires 2 arguments: fget(sprite_id, flag_bit)");
        return false;
    }

    // Push arguments right-to-left: flag_bit, sprite_id
    int reg = allocate_register();
    generate_asm(args[1], reg);  // flag_bit
    emit_asm("PUSH R%d ; Arg 2: flag_bit\n", reg);
    unlock_register(reg);

    reg = allocate_register();
    generate_asm(args[0], reg);  // sprite_id
    emit_asm("PUSH R%d ; Arg 1: sprite_id\n", reg);
    unlock_register(reg);

    // Call runtime subroutine
    emit_asm("CALL __builtin_tic80_fget\n");
    emit_asm("IADD SP, 2 ; Clean up fget() arguments\n");

    // Transfer result to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the fset() intrinsic (TIC-80 sprite flags).
 *
 * Syntax: fset(sprite_id, flag_bit, value) -> returns value
 */
bool emit_tic80_fset_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 fset() Intrinsic (Sprite Flags) ---\n");

    // Collect exactly 3 arguments: sprite_id, flag_bit, value
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[3] = { NULL, NULL, NULL };
    while (curr != NULL && arg_count < 3) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count < 3) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "TIC-80 fset() requires 3 arguments: fset(sprite_id, flag_bit, value)");
        return false;
    }

    // Push arguments right-to-left: value, flag_bit, sprite_id
    int reg = allocate_register();
    generate_asm(args[2], reg);  // value
    emit_asm("PUSH R%d ; Arg 3: value\n", reg);
    unlock_register(reg);

    reg = allocate_register();
    generate_asm(args[1], reg);  // flag_bit
    emit_asm("PUSH R%d ; Arg 2: flag_bit\n", reg);
    unlock_register(reg);

    reg = allocate_register();
    generate_asm(args[0], reg);  // sprite_id
    emit_asm("PUSH R%d ; Arg 1: sprite_id\n", reg);
    unlock_register(reg);

    // Call runtime subroutine
    emit_asm("CALL __builtin_tic80_fset\n");
    emit_asm("IADD SP, 3 ; Clean up fset() arguments\n");

    // Transfer result to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer return value\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the sync() intrinsic (TIC-80 compatibility).
 *
 * Syntax: sync([mask [, bank [, tocart]]])
 *
 * Real TIC-80 sync() copies data between VRAM and one of several cart
 * memory banks. Vircon32 has no equivalent bank-switching mechanism --
 * its map/texture/palette data is already directly addressable -- so
 * there's nothing to synchronize. This is intentionally a no-op: it
 * exists purely so debug-only calls to sync() don't fail to compile.
 * Arguments are still evaluated (and discarded) to preserve Lua's
 * argument-evaluation-has-side-effects semantics.
 */
bool emit_tic80_sync_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 sync() Intrinsic (no-op: no cart banks on Vircon32) ---\n");

    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL) {
        int reg = allocate_register();
        generate_asm(curr, reg);   // evaluate for side effects only
        unlock_register(reg);
        curr = curr->next;
    }

    if (dest_reg != 0) {
        emit_asm("MOV R%d, BOXED_NIL\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the pix() intrinsic (TIC-80 compatibility).
 * Syntax: pix(x, y, color) -- draws a single pixel. Write-only; see
 * __builtin_tic80_pix's header comment for why the read form isn't
 * supported on this GPU.
 */
bool emit_tic80_pix_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 pix() Intrinsic ---\n");

    ASTNode *args[3] = { NULL, NULL, NULL };
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL && arg_count < 3) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count != 3) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "TIC-80 pix() requires 3 arguments: pix(x, y, color)");
        return false;
    }

    // Push right-to-left: color, y, x
    for (int i = 2; i >= 0; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        generate_asm(args[i], reg);
        emit_asm("PUSH R%d ; pix() arg %d\n", reg, i);
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    emit_asm("CALL __builtin_tic80_pix\n");
    emit_asm("IADD SP, 3 ; Clean up pix() arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer result to dest_reg\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the line() intrinsic (TIC-80 compatibility).
 * Syntax: line(x0, y0, x1, y1, color)
 */
bool emit_tic80_line_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 line() Intrinsic ---\n");

    ASTNode *args[5] = { NULL, NULL, NULL, NULL, NULL };
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL && arg_count < 5) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count != 5) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "TIC-80 line() requires 5 arguments: line(x0, y0, x1, y1, color)");
        return false;
    }

    for (int i = 4; i >= 0; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        generate_asm(args[i], reg);
        emit_asm("PUSH R%d ; line() arg %d\n", reg, i);
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    emit_asm("CALL __builtin_tic80_line\n");
    emit_asm("IADD SP, 5 ; Clean up line() arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer result to dest_reg\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the rect() intrinsic (TIC-80 compatibility).
 * Syntax: rect(x, y, w, h, color) -- filled rectangle
 */
bool emit_tic80_rect_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 rect() Intrinsic ---\n");

    ASTNode *args[5] = { NULL, NULL, NULL, NULL, NULL };
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL && arg_count < 5) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count != 5) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "TIC-80 rect() requires 5 arguments: rect(x, y, w, h, color)");
        return false;
    }

    for (int i = 4; i >= 0; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        generate_asm(args[i], reg);
        emit_asm("PUSH R%d ; rect() arg %d\n", reg, i);
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    emit_asm("CALL __builtin_tic80_rect\n");
    emit_asm("IADD SP, 5 ; Clean up rect() arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer result to dest_reg\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the rectb() intrinsic (TIC-80 compatibility).
 * Syntax: rectb(x, y, w, h, color) -- rectangle border only
 */
bool emit_tic80_rectb_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 rectb() Intrinsic ---\n");

    ASTNode *args[5] = { NULL, NULL, NULL, NULL, NULL };
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL && arg_count < 5) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count != 5) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "TIC-80 rectb() requires 5 arguments: rectb(x, y, w, h, color)");
        return false;
    }

    for (int i = 4; i >= 0; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        generate_asm(args[i], reg);
        emit_asm("PUSH R%d ; rectb() arg %d\n", reg, i);
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    emit_asm("CALL __builtin_tic80_rectb\n");
    emit_asm("IADD SP, 5 ; Clean up rectb() arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer result to dest_reg\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the circ() intrinsic (TIC-80 compatibility).
 * Syntax: circ(x, y, radius, color) -- filled circle
 */
bool emit_tic80_circ_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 circ() Intrinsic ---\n");

    ASTNode *args[4] = { NULL, NULL, NULL, NULL };
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL && arg_count < 4) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count != 4) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "TIC-80 circ() requires 4 arguments: circ(x, y, radius, color)");
        return false;
    }

    // Push right-to-left: color, radius, y, x
    for (int i = 3; i >= 0; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        generate_asm(args[i], reg);
        emit_asm("PUSH R%d ; circ() arg %d\n", reg, i);
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    emit_asm("CALL __builtin_tic80_circ\n");
    emit_asm("IADD SP, 4 ; Clean up circ() arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer result to dest_reg\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the circb() intrinsic (TIC-80 compatibility).
 * Syntax: circb(x, y, radius, color) -- circle outline (1px border)
 */
bool emit_tic80_circb_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 circb() Intrinsic ---\n");

    ASTNode *args[4] = { NULL, NULL, NULL, NULL };
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL && arg_count < 4) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count != 4) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                      "TIC-80 circb() requires 4 arguments: circb(x, y, radius, color)");
        return false;
    }

    for (int i = 3; i >= 0; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        generate_asm(args[i], reg);
        emit_asm("PUSH R%d ; circb() arg %d\n", reg, i);
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    emit_asm("CALL __builtin_tic80_circb\n");
    emit_asm("IADD SP, 4 ; Clean up circb() arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer result to dest_reg\n", dest_reg);
    }

    return true;
}

/**
 * Emits assembly for the exit() intrinsic (TIC-80 compatibility).
 * Syntax: exit() or exit(anything) -- real TIC-80 exit() takes no
 * parameters and only *requests* termination: it doesn't stop execution
 * immediately, the current TIC() call keeps running to completion, and
 * TIC-80 stops calling TIC() again after this frame. tomb_of_the_tic.lua
 * calls it as exit(selectedLevel) with no guard afterward, which only
 * makes sense under that deferred semantics -- so any argument passed is
 * accepted (evaluated for Lua side effects, matching sync()'s precedent)
 * and then discarded; only the deferred-stop behavior is real.
 */
bool emit_tic80_exit_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 exit() Intrinsic ---\n");

    // Evaluate and discard any arguments, purely for side effects.
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL) {
        int reg = allocate_register();
        generate_asm(curr, reg);
        unlock_register(reg);
        curr = curr->next;
    }

    char flag_access[128];
    get_variable_access_string("TIC80_EXIT_FLAG", flag_access);

    int flag_reg = allocate_register();
    emit_asm("MOV R%d, 1\n", flag_reg);
    emit_asm("MOV %s, R%d ; request exit after this frame finishes\n", flag_access, flag_reg);
    unlock_register(flag_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, BOXED_NIL ; exit() has no meaningful return value\n", dest_reg);
    }

    return true;
}
