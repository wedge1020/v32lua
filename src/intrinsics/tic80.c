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

// TIC-80 print(text [, x [, y [, color [, fixed [, scale [, smallfont]]]]]])
// -> width of the printed text in TIC-80 pixels.
// x/y default to 0 and color to 15, like TIC-80. The BIOS font is white, so
// color is applied as a GPU multiply color (it used to be ignored). The
// returned width -- used by the common `local w = print(s, 0, -6)` centering
// idiom -- is #text * 6 (TIC-80's default font advance); it used to be
// whatever R0 held. fixed/scale/smallfont are accepted and ignored.
// Arguments are pushed as they are evaluated (they used to sit in pinned
// registers across each other's evaluation, so print(f(), g(), 0) could
// clobber f()'s result).
bool emit_tic80_print_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 print() Intrinsic ---\n");

    ASTNode *args[4] = { NULL };
    int n = 0;
    for (ASTNode *c = node->as.call.args_head; c != NULL && n < 4; c = c->next) args[n++] = c;
    if (n < 1) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                       "TIC-80 print() requires at least 1 argument: print(text [, x, y, color])");
        return false;
    }

    // [BP+5] = text, [BP+4] = x, [BP+3] = y, [BP+2] = color
    static const char *defaults[4] = { NULL, "0.0", "0.0", "15.0" };
    for (int i = 0; i < 4; i++) {
        int reg = allocate_register();
        if (args[i] != NULL && args[i]->type != NODE_NIL) {
            generate_asm(args[i], reg);
        } else {
            emit_asm("MOV R%d, %s\n", reg, defaults[i] ? defaults[i] : "BOXED_NIL");
        }
        emit_asm("PUSH R%d ; print arg %d\n", reg, i + 1);
        unlock_register(reg);
    }
    emit_asm("CALL __builtin_tic80_print\n");
    emit_asm("IADD SP, 4\n");
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; text width\n", dest_reg);
    }
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

    // map([x=0], [y=0], [w=30], [h=17], [sx=0], [sy=0], [colorkey=-1],
    //     [scale=1], [remap]) -- every argument is optional in TIC-80
    // (`map()` draws the first screen of the map). The remap callback is
    // not supported.
    int arg_count = 0;
    ASTNode *args[9] = { NULL };
    for (ASTNode *curr = node->as.call.args_head; curr != NULL && arg_count < 9; curr = curr->next) {
        args[arg_count++] = curr;
    }
    if (arg_count >= 9) {
        compiler_warning(ERR_SEMANTIC, node->line_number,
                         "map(): the remap callback is not supported and is ignored");
    }

    static const char *defaults[8] = { "0.0", "0.0", "30.0", "17.0", "0.0", "0.0",
                                       "16.0", /* colorkey: none (opaque) */ "1.0" };
    static const char *names[8]    = { "x", "y", "w", "h", "sx", "sy", "color_key", "scale" };

    // Push right-to-left: scale, color_key, sy, sx, h, w, y, x
    for (int i = 7; i >= 0; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (i < arg_count) {
            generate_asm(args[i], reg);
            ensure_in_register(reg);
        } else {
            emit_asm("MOV R%d, %s ; default\n", reg, defaults[i]);
        }
        emit_asm("PUSH R%d ; Arg %d: %s\n", reg, i + 1, names[i]);
        register_pinned[reg] = 0;
        unlock_register(reg);
    }

    emit_asm("CALL __builtin_tic80_map\n");
    emit_asm("IADD SP, 8 ; Clean up map() arguments\n");

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
        emit_asm("CFI R1 ; ports take integers, Lua numbers are floats\n");
        emit_asm("OUT SPU_SelectedSound, R1\n");
    }

    // Set channel (default 0)
    if (args[1]) {
        generate_asm(args[1], 1);
        emit_asm("CFI R1\n");
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

// ============================================================================
// TIC-80 sfx(id [, note [, duration [, channel [, volume [, speed]]]]])
// TIC-80 music([track [, frame [, row [, loop [, sustain]]]]])
// ----------------------------------------------------------------------------
// Both were empty stubs (sfx() evaluated its id into R1 and did nothing).
// They now use the same placeholder tone bank as the PICO-8 layer (see
// register_pico8_tone_bank(): 8 generated tones, id -> tone id & 7), on the
// native sfx.play()/music.play() machinery:
//   - sfx(-1 [,...,channel])  stops that channel (or every sfx channel)
//   - channel (TIC-80: 0-3) is passed through; absent -> auto channel
//   - note/duration/volume/speed are accepted and not reproduced
//   - music(track) loops the track's tone; music() / music(-1) stops it
// A cart's own WAVES/SFX/MUSIC data is not synthesized (not implemented).
// ============================================================================
bool emit_tic80_sfx_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 sfx() Intrinsic (tone bank) ---\n");

    ASTNode *args[6] = { NULL };
    int n = 0;
    for (ASTNode *c = node->as.call.args_head; c != NULL && n < 6; c = c->next) args[n++] = c;
    if (n < 1) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "sfx() requires at least 1 argument: sfx(id [, note, duration, channel, volume, speed])");
        return false;
    }

    register_pico8_tone_bank();
    runtime_req.needs_vircon32 = true;

    ASTNode *channel = (n >= 4 && args[3]->type != NODE_NIL) ? args[3] : NULL;

    double id;
    if (spu_static_number(args[0], &id)) {
        if (id < 0) {
            ASTNode *stop = make_node(NODE_FUNCTION_CALL);
            stop->line_number       = node->line_number;
            if (channel != NULL) {
                // detach the channel expression from the TIC-80 arg chain
                ASTNode *copy = malloc(sizeof(ASTNode));
                memcpy(copy, channel, sizeof(ASTNode));
                copy->next = NULL;
                stop->as.call.args_head = copy;
            }
            return emit_vircon32_sfx_stop_intrinsic(stop, dest_reg);
        }
        ASTNode *tone = make_node(NODE_NUMBER);
        tone->as.number.val = (double)(pico8_tone_base_id + (((int) id) & (PICO8_TONE_COUNT - 1)));
        if (channel != NULL) {
            ASTNode *copy = malloc(sizeof(ASTNode));
            memcpy(copy, channel, sizeof(ASTNode));
            copy->next = NULL;
            tone->next = copy;
        }
        ASTNode *call = make_node(NODE_FUNCTION_CALL);
        call->line_number       = node->line_number;
        call->as.call.args_head = tone;
        return emit_vircon32_sfx_play_intrinsic(call, dest_reg);
    }

    // Dynamic id: shared runtime routine resolves the tone at run time.
    // [BP+2] = id, [BP+3] = channel or nil, [BP+4] = tone base (raw int)
    emit_asm("MOV  R0, %d ; tone bank mask\n", PICO8_TONE_COUNT - 1);
    emit_asm("PUSH R0\n");
    emit_asm("MOV  R0, %d ; tone bank base id\n", pico8_tone_base_id);
    emit_asm("PUSH R0\n");
    if (channel != NULL) {
        int reg = allocate_register();
        generate_asm(channel, reg);
        emit_asm("PUSH R%d ; channel\n", reg);
        unlock_register(reg);
    } else {
        emit_asm("MOV  R0, BOXED_NIL\n");
        emit_asm("PUSH R0 ; channel -> auto\n");
    }
    int reg = allocate_register();
    generate_asm(args[0], reg);
    emit_asm("PUSH R%d ; sfx id\n", reg);
    unlock_register(reg);
    emit_asm("CALL __builtin_tonebank_sfx\n");
    emit_asm("IADD SP, 4\n");
    if (dest_reg != 0) {
        emit_asm("MOV R%d, BOXED_NIL\n", dest_reg);
    }
    return true;
}

bool emit_tic80_music_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 music() Intrinsic (tone bank) ---\n");

    register_pico8_tone_bank();
    runtime_req.needs_vircon32 = true;

    ASTNode *track = node->as.call.args_head;
    double t = -1.0;
    if (track != NULL && !spu_static_number(track, &t)) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "music(): the track number must be a compile-time constant");
        return false;
    }

    if (t < 0) {
        // music() / music(-1): stop -- music plays on channel 0
        ASTNode *chan0 = make_node(NODE_NUMBER);
        chan0->as.number.val = 0.0;
        ASTNode *stop = make_node(NODE_FUNCTION_CALL);
        stop->line_number       = node->line_number;
        stop->as.call.args_head = chan0;
        return emit_vircon32_channel_cmd_intrinsic(stop, dest_reg, "stop");
    }

    ASTNode *tone = make_node(NODE_NUMBER);
    tone->as.number.val = (double)(pico8_tone_base_id + (((int) t) & (PICO8_TONE_COUNT - 1)));
    // music.play(SOUND, CHANNEL, CHANLOOP): channel 0, loop on
    ASTNode *chan0_m = make_node(NODE_NUMBER);
    chan0_m->as.number.val = 0.0;
    tone->next = chan0_m;
    chan0_m->next = make_node_boolean(true);
    ASTNode *call = make_node(NODE_FUNCTION_CALL);
    call->line_number       = node->line_number;
    call->as.call.args_head = tone;
    return emit_vircon32_play_intrinsic(call, dest_reg);
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
 * Emits assembly for the time() intrinsic (TIC-80 compatibility).
 *
 * Syntax: time() -> returns milliseconds since cartridge began execution
 *
 * TIC-80 time() returns milliseconds, but Vircon32's TIM_CurrentTime returns
 * seconds since system start. We multiply by 1000 to convert to milliseconds.
 */
bool emit_tic80_time_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- TIC-80 time() Intrinsic ---\n");

    // time() takes no arguments, but we still need to handle the call
    // Check for any arguments and evaluate them for side effects (Lua semantics)
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL) {
        int reg = allocate_register();
        generate_asm(curr, reg);
        unlock_register(reg);
        curr = curr->next;
    }

    // TIM_CurrentTime is the timer's real-time-of-day clock (seconds
    // elapsed WITHIN the current day, 0-86399 per spec Part 7 sec 1.2.2)
    // -- it is NOT an elapsed-since-start counter, so it can't stand in
    // for TIC-80's time(), which must return milliseconds since the
    // cart began execution. TIM_FrameCounter is the correct source: it
    // counts frames elapsed since the last console power-on/reset at a
    // fixed 60 Hz, so multiplying by (1000.0 / 60.0) gives milliseconds
    // since program start -- what TIC-80's time() actually returns.
    if (dest_reg != 0) {
        emit_asm("    IN R%d, TIM_FrameCounter ; Get frames elapsed since program start\n", dest_reg);
        emit_asm("    CIF R%d ; Convert hardware integer to Lua float\n", dest_reg);
        emit_asm("    FMUL R%d, 16.666667 ; Convert frames to milliseconds (1000/60)\n", dest_reg);
    } else {
        emit_asm("    IN R0, TIM_FrameCounter ; Get frames elapsed since program start\n");
        emit_asm("    CIF R0 ; Convert hardware integer to Lua float\n");
        emit_asm("    FMUL R0, 16.666667 ; Convert frames to milliseconds (1000/60)\n");
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

// ============================================================================
// TIC-80 memory: peek/peek1/peek2/peek4, poke/poke1/poke2/poke4, memcpy,
// memset -- on an emulated 96 KB RAM (see runtime/tic80.s). The first use
// sets tic80_uses_memory, which makes emit.c put the RAM's initial contents
// (palette, tiles, sprites, map) in the cart.
// ============================================================================
bool tic80_uses_memory = false;

// Pushes `count` call arguments right to left; a missing one is `fill`
// (a literal number) or nil when fill is NULL.
static void push_mem_args (ASTNode *node, int count, const char *fill)
{
    ASTNode *args[3] = { NULL, NULL, NULL };
    int n = 0;
    for (ASTNode *a = node->as.call.args_head; a != NULL && n < 3; a = a->next) args[n++] = a;

    for (int i = count - 1; i >= 0; i--) {
        int reg = allocate_register();
        register_pinned[reg] = 1;
        if (i < n && args[i] != NULL) {
            generate_asm(args[i], reg);
            ensure_in_register(reg);
        } else if (fill != NULL) {
            emit_asm("MOV R%d, %s\n", reg, fill);
        } else {
            emit_asm("MOV R%d, BOXED_NIL\n", reg);
        }
        emit_asm("PUSH R%d ; arg %d\n", reg, i + 1);
        register_pinned[reg] = 0;
        unlock_register(reg);
    }
}

bool emit_tic80_memory_intrinsic (ASTNode *node, const char *func_name, int dest_reg)
{
    int         min_args = 1, pushed = 0;
    const char *routine  = NULL;
    const char *bits     = NULL;   // fixed width for peekN/pokeN

    if      (strcmp(func_name, "peek")  == 0) { routine = "__builtin_tic80_peek"; }
    else if (strcmp(func_name, "peek1") == 0) { routine = "__builtin_tic80_peek"; bits = "1.0"; }
    else if (strcmp(func_name, "peek2") == 0) { routine = "__builtin_tic80_peek"; bits = "2.0"; }
    else if (strcmp(func_name, "peek4") == 0) { routine = "__builtin_tic80_peek"; bits = "4.0"; }
    else if (strcmp(func_name, "poke")  == 0) { routine = "__builtin_tic80_poke"; min_args = 2; }
    else if (strcmp(func_name, "poke1") == 0) { routine = "__builtin_tic80_poke"; min_args = 2; bits = "1.0"; }
    else if (strcmp(func_name, "poke2") == 0) { routine = "__builtin_tic80_poke"; min_args = 2; bits = "2.0"; }
    else if (strcmp(func_name, "poke4") == 0) { routine = "__builtin_tic80_poke"; min_args = 2; bits = "4.0"; }
    else if (strcmp(func_name, "memcpy") == 0) { routine = "__builtin_tic80_memcpy"; min_args = 3; }
    else if (strcmp(func_name, "memset") == 0) { routine = "__builtin_tic80_memset"; min_args = 3; }
    else return false;

    int argc = 0;
    for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next) argc++;
    if (argc < min_args) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                       "TIC-80 %s() needs at least %d argument%s", func_name, min_args,
                       min_args == 1 ? "" : "s");
        return false;
    }

    tic80_uses_memory = true;
    emit_asm("    ;; --- TIC-80 %s() ---\n", func_name);

    if (strcmp(routine, "__builtin_tic80_peek") == 0) {
        if (bits != NULL) {
            // peekN(addr): [BP+3] = N, [BP+2] = addr
            int reg = allocate_register();
            emit_asm("MOV R%d, %s\n", reg, bits);
            emit_asm("PUSH R%d ; bits\n", reg);
            unlock_register(reg);
            push_mem_args(node, 1, NULL);
            pushed = 2;
        } else {
            push_mem_args(node, 2, NULL);      // peek(addr [, bits])
            pushed = 2;
        }
    } else if (strcmp(routine, "__builtin_tic80_poke") == 0) {
        if (bits != NULL) {
            int reg = allocate_register();
            emit_asm("MOV R%d, %s\n", reg, bits);
            emit_asm("PUSH R%d ; bits\n", reg);
            unlock_register(reg);
            push_mem_args(node, 2, NULL);
        } else {
            push_mem_args(node, 3, NULL);      // poke(addr, value [, bits])
        }
        pushed = 3;
    } else {
        push_mem_args(node, 3, NULL);          // memcpy / memset
        pushed = 3;
    }

    emit_asm("CALL %s\n", routine);
    emit_asm("IADD SP, %d\n", pushed);
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0\n", dest_reg);
    }
    return true;
}

// The RAM image's initial contents, as segments: start, byte count, bytes
// packed 4 per word (low byte first); the list ends with -1. Only a cart
// that uses peek/poke gets them.
static void emit_ram_segment (FILE *f, int start, const uint8_t *bytes, int count)
{
    fprintf(f, "    integer %d, %d\n", start, count);
    for (int i = 0; i < count; i += 4) {
        uint32_t w = 0;
        for (int k = 0; k < 4 && i + k < count; k++) w |= (uint32_t) bytes[i + k] << (8 * k);
        fprintf(f, "%s0x%08X%s", (i / 4) % 8 == 0 ? "    integer " : "", w,
                ((i / 4) % 8 == 7 || i + 4 >= count) ? "\n" : ", ");
    }
}

void emit_tic80_ram_rom (FILE *f)
{
    fprintf(f, "\n;; --- TIC-80 RAM image for peek/poke (%s) ---\n__tic80_ram_rom:\n",
            tic80_uses_memory ? "palette, tiles, sprites, map" : "unused");
    if (tic80_uses_memory) {
        uint8_t pal[56];
        for (int i = 0; i < 16; i++) {
            uint32_t c = tic80_get_palette_color(i);          // AABBGGRR
            pal[i * 3]     = c & 0xFF;
            pal[i * 3 + 1] = (c >> 8) & 0xFF;
            pal[i * 3 + 2] = (c >> 16) & 0xFF;
        }
        for (int i = 0; i < 8; i++) pal[48 + i] = (uint8_t) ((2 * i) | ((2 * i + 1) << 4)); // palette map: identity
        emit_ram_segment(f, 0x3FC0, pal, 56);

        static uint8_t sheet[16384];     // tiles 0x4000 + sprites 0x6000: 32 bytes per 8x8
        for (int t = 0; t < 512; t++) {
            for (int k = 0; k < 32; k++) {
                int i0 = k * 2, i1 = k * 2 + 1;
                int x0 = (t % 16) * 8 + i0 % 8, y0 = (t / 16) * 8 + i0 / 8;
                int x1 = (t % 16) * 8 + i1 % 8, y1 = (t / 16) * 8 + i1 / 8;
                sheet[t * 32 + k] = (uint8_t) ((get_tic80_tile_pixel(x0, y0) & 15) |
                                               ((get_tic80_tile_pixel(x1, y1) & 15) << 4));
            }
        }
        emit_ram_segment(f, 0x4000, sheet, 16384);

        if (tic80_has_map && tic80_map_width > 0 && tic80_map_width <= 240) {
            static uint8_t map[240 * 136];
            memset(map, 0, sizeof map);
            for (int y = 0; y < tic80_map_height && y < 136; y++)
                for (int x = 0; x < tic80_map_width; x++)
                    map[y * 240 + x] = tic80_map_data[y * tic80_map_width + x];
            emit_ram_segment(f, 0x8000, map, 240 * 136);
        }
    }
    fprintf(f, "    integer -1\n");
}

// TIC-80 functions with nothing to act on here: trace() (debug console
// output), key()/keyp() (keyboard -- Vircon32 has gamepads only, so no key
// is ever down). Arguments are still evaluated, for their side effects.
bool emit_tic80_stub_intrinsic (ASTNode *node, const char *func_name, int dest_reg)
{
    const char *result;
    if      (strcmp(func_name, "trace") == 0) result = "BOXED_NIL";
    else if (strcmp(func_name, "key")   == 0) result = "BOXED_FALSE";
    else if (strcmp(func_name, "keyp")  == 0) result = "BOXED_FALSE";
    else return false;

    emit_asm("    ;; --- TIC-80 %s(): no-op on Vircon32 ---\n", func_name);
    for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next) {
        if (a->type == NODE_NUMBER || a->type == NODE_STRING || a->type == NODE_IDENTIFIER) continue;
        int reg = allocate_register();
        generate_asm(a, reg);
        unlock_register(reg);
    }
    if (dest_reg != 0) emit_asm("MOV R%d, %s\n", dest_reg, result);
    return true;
}
