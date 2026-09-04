/**
 * intrinsics_vircon32.c
 * 
 * Native Vircon32 implementations of spr(), btn(), btnp()
 * Used when neither PICO-8 nor TIC-80 compatibility is enabled.
 * 
 * These intrinsics provide direct access to Vircon32 hardware features:
 * - spr(): GPU region drawing with scale, rotation, color multiply, blending
 * - btn(): Direct gamepad button state polling
 * - btnp(): Edge-detected button press (pressed this frame only)
 */

#include "v32lua.h"

// ============================================================================
// Button ID to Vircon32 IOPort mapping (11 buttons in Vircon32 order)
// Order: Left, Right, Up, Down, Start, A, B, X, Y, L, R
// ============================================================================
static const char *vircon32_button_ports[11] = {
    "INP_GamepadLeft",
    "INP_GamepadRight",
    "INP_GamepadUp",
    "INP_GamepadDown",
    "INP_GamepadButtonStart",
    "INP_GamepadButtonA",
    "INP_GamepadButtonB",
    "INP_GamepadButtonX",
    "INP_GamepadButtonY",
    "INP_GamepadButtonL",
    "INP_GamepadButtonR"
};

// ============================================================================
// Blending mode constants for Vircon32 GPU
// ============================================================================
#define VIRCON32_BLEND_ALPHA    0x20
#define VIRCON32_BLEND_ADD      0x21
#define VIRCON32_BLEND_SUBTRACT 0x22

int  vircon32_sfx_cursor_base          = -1;
int  vircon32_btn_prev_state_base      = -1;
int  vircon32_music_channel_mask_base  = -1;
int  vircon32_sfx_channel_mask_base    = -1;

// ============================================================================
// spr(region_id, x, y[, scale_x][, scale_y][, angle_deg][, color_mult][, blend_mode])
//
// Draws a texture region (sprite) at position (x, y) with optional:
// - scale_x, scale_y: Float scaling factors (default: 1.0)
// - angle_deg: Rotation in degrees 0-360, counter-clockwise (default: 0)
// - color_mult: RGBA color multiplication value (default: 0xFFFFFFFF)
// - blend_mode: Blending mode (default: VIRCON32_BLEND_ALPHA)
//
// Dispatches entirely at RUNTIME, in __builtin_vircon32_spr, to whichever of
// GPUCommand_DrawRegion / Zoomed / Rotated / Rotozoomed the actual scale/
// angle values need -- see the notes on that routine in runtime.s. Every
// call goes through the one runtime routine; there is no compile-time-folded
// straight-line path the way music.play()/sfx.play() have one.
//
// TWO BUGS FIXED HERE DURING THE spr() AUDIT (2026-09-04):
//
// 1. EXPLICIT-NIL ON AN OPTIONAL ARGUMENT WAS NOT DEFAULTED.
//    "has_scale_x = (arg_count >= 4)" etc. only looked at ARGUMENT COUNT.
//    spr(id, x, y, nil, nil, 45) -- the normal Lua idiom for "skip scale,
//    I want angle_deg" -- has arg_count 6, so has_scale_x/has_scale_y both
//    came back true, and the NODE_NIL argument was compiled the same as any
//    other expression: generate_asm() on a NODE_NIL emits the raw NaN-boxed
//    BOXED_NIL bit pattern into a register, which then got PUSHed and used
//    by __builtin_vircon32_spr directly as a float scale factor. Unlike
//    play()/btn()'s optional arguments, that runtime routine does NOT
//    nil-check scale_x/scale_y/angle_deg/color_mult/blend_mode -- it trusts
//    the stack slot to already hold a real number -- so this silently
//    corrupted GPU_DrawingScaleX/Y (and, via the FEQ dispatch chain, could
//    also send the draw down the wrong one of the four GPUCommand_DrawRegion*
//    variants). Fixed by checking the AST node type, not just the count:
//    both "argument absent" and "argument present but NODE_NIL" now push
//    the compiler-side literal default, exactly like the argument was never
//    written.
//
// 2. NO RETURN VALUE WAS EVER WRITTEN TO dest_reg.
//    The old signature was emit_vircon32_spr_intrinsic(ASTNode *), with no
//    dest_reg parameter at all -- the call site passed only `node` and
//    silently discarded whatever dest_reg the caller wanted filled. spr()
//    correctly returns nothing in Lua, but a call sitting in an expression
//    context ("local unused = spr(1, 10, 10)") still needs its destination
//    register set to nil; instead it was left holding whatever value
//    happened to already be there. dest_reg is now a real parameter and
//    BOXED_NIL is written to it when non-zero, matching every other
//    intrinsic in this file.
// ============================================================================
bool emit_vircon32_spr_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- Vircon32 spr() Intrinsic ---\n");

    // Collect all arguments (up to 8 possible)
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[8] = { NULL };
    while (curr != NULL && arg_count < 8) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count < 3) {
        compiler_error(ERR_SYNTAX, node->line_number,
                      "spr() requires at least 3 arguments: spr(region_id, x, y)");
        return false;
    }

    if (curr != NULL) {
        compiler_warning(ERR_SEMANTIC, node->line_number,
            "spr() takes at most 8 arguments; extra arguments ignored");
    }

    // "Given" means present AND not an explicit nil -- absent and NODE_NIL
    // both fall through to the compiler-side default below. See bug 1 above.
    #define SPR_ARG_GIVEN(i) \
        ((i) < arg_count && args[(i)] != NULL && args[(i)]->type != NODE_NIL)

    bool has_scale_x    = SPR_ARG_GIVEN(3);
    bool has_scale_y    = SPR_ARG_GIVEN(4);
    bool has_angle      = SPR_ARG_GIVEN(5);
    bool has_color_mult = SPR_ARG_GIVEN(6);
    bool has_blend_mode = SPR_ARG_GIVEN(7);

    #undef SPR_ARG_GIVEN

    // =========================================================================
    // Push optional arguments right-to-left (for runtime subroutine)
    // Stack order: [blend_mode, color_mult, angle_deg, scale_y, scale_x, y, x, region_id]
    // =========================================================================

    // Arg 8: blend_mode (default: VIRCON32_BLEND_ALPHA)
    if (has_blend_mode) {
        int reg = allocate_register();
        generate_asm(args[7], reg);
        emit_asm("PUSH R%d ; Arg 8: blend_mode\n", reg);
        unlock_register(reg);
    } else {
        emit_asm("MOV R0, %d.000000 ; Default blend_mode (alpha)\n", VIRCON32_BLEND_ALPHA);
        emit_asm("PUSH R0\n");
    }

    // Arg 7: color_mult (default: 0xFFFFFFFF)
    if (has_color_mult) {
        int reg = allocate_register();
        generate_asm(args[6], reg);
        emit_asm("PUSH R%d ; Arg 7: color_mult\n", reg);
        unlock_register(reg);
    } else {
        emit_asm("MOV R0, 4294967295.000000 ; Default color_mult (0xFFFFFFFF)\n");
        emit_asm("PUSH R0\n");
    }

    // Arg 6: angle_deg (default: 0)
    if (has_angle) {
        int reg = allocate_register();
        generate_asm(args[5], reg);
        emit_asm("PUSH R%d ; Arg 6: angle_deg\n", reg);
        unlock_register(reg);
    } else {
        emit_asm("MOV R0, 0.000000 ; Default angle_deg (0)\n");
        emit_asm("PUSH R0\n");
    }

    // Arg 5: scale_y (default: 1.0)
    if (has_scale_y) {
        int reg = allocate_register();
        generate_asm(args[4], reg);
        emit_asm("PUSH R%d ; Arg 5: scale_y\n", reg);
        unlock_register(reg);
    } else {
        emit_asm("MOV R0, 1.000000 ; Default scale_y (1.0)\n");
        emit_asm("PUSH R0\n");
    }

    // Arg 4: scale_x (default: 1.0)
    if (has_scale_x) {
        int reg = allocate_register();
        generate_asm(args[3], reg);
        emit_asm("PUSH R%d ; Arg 4: scale_x\n", reg);
        unlock_register(reg);
    } else {
        emit_asm("MOV R0, 1.000000 ; Default scale_x (1.0)\n");
        emit_asm("PUSH R0\n");
    }

    // Required args: y, x, region_id (in that order for stack)
    for (int i = 2; i >= 0; i--) {
        int reg = allocate_register();
        generate_asm(args[i], reg);
        emit_asm("PUSH R%d ; Arg %d: %s\n", reg, i + 1,
                 i == 0 ? "region_id" : (i == 1 ? "x" : "y"));
        unlock_register(reg);
    }

    emit_asm("CALL __builtin_vircon32_spr\n");
    emit_asm("IADD SP, 8 ; Clean up spr() arguments\n");

    // spr() returns nothing in Lua. See bug 2 in the header comment above --
    // dest_reg used to be silently dropped by this function entirely.
    if (dest_reg != 0) {
        emit_asm("MOV R%d, BOXED_NIL ; spr() returns nothing\n", dest_reg);
    }

    return true;
}

// ============================================================================
// btn(id[, player])
//
// Returns true if button 'id' is currently pressed.
//
// Button IDs (Vircon32 IOPorts order):
//   0 = Left, 1 = Right, 2 = Up, 3 = Down
//   4 = Start, 5 = A, 6 = B, 7 = X, 8 = Y
//   9 = L (Left Shoulder), 10 = R (Right Shoulder)
//
// If player is specified, selects that gamepad (0-3).
// If player is not specified, uses the currently selected gamepad.
// ============================================================================
bool emit_vircon32_btn_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- Vircon32 btn() Intrinsic ---\n");

    // Collect arguments
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[2] = { NULL };
    while (curr != NULL && arg_count < 2) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count < 1) {
        compiler_error(ERR_SYNTAX, node->line_number,
                      "btn() requires at least 1 argument: btn(id)");
        return false;
    }

    bool has_player = (arg_count >= 2);

    // Push player or nil (to indicate "use current gamepad")
    if (has_player) {
        int reg = allocate_register();
        generate_asm(args[1], reg);
        emit_asm("PUSH R%d ; Arg 2: player\n", reg);
        unlock_register(reg);
    } else {
        emit_asm("MOV R0, BOXED_NIL\n");
        emit_asm("PUSH R0 ; No player specified - use current gamepad\n");
    }

    // Button ID (required)
    int id_reg = allocate_register();
    generate_asm(args[0], id_reg);
    emit_asm("PUSH R%d ; Arg 1: button_id\n", id_reg);
    unlock_register(id_reg);

    // Call runtime subroutine
    emit_asm("CALL __builtin_vircon32_btn\n");
    emit_asm("IADD SP, 2 ; Clean up btn() arguments\n");

    // Transfer result to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer result to dest_reg\n", dest_reg);
    }

    return true;
}

// ============================================================================
// btnp(id[, player])
//
// Returns true only on the frame the button was first pressed.
//
// Same parameters as btn(). Uses edge detection via frame counter.
// ============================================================================
bool emit_vircon32_btnp_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- Vircon32 btnp() Intrinsic ---\n");

    // Collect arguments (same as btn)
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    ASTNode *args[2] = { NULL };
    while (curr != NULL && arg_count < 2) {
        args[arg_count++] = curr;
        curr = curr->next;
    }

    if (arg_count < 1) {
        compiler_error(ERR_SYNTAX, node->line_number,
                      "btnp() requires at least 1 argument: btnp(id)");
        return false;
    }

    bool has_player = (arg_count >= 2);

    // Push player or nil
    if (has_player) {
        int reg = allocate_register();
        generate_asm(args[1], reg);
        emit_asm("PUSH R%d ; Arg 2: player\n", reg);
        unlock_register(reg);
    } else {
        emit_asm("MOV R0, BOXED_NIL\n");
        emit_asm("PUSH R0 ; No player specified - use current gamepad\n");
    }

    // Button ID (required)
    int id_reg = allocate_register();
    generate_asm(args[0], id_reg);
    emit_asm("PUSH R%d ; Arg 1: button_id\n", id_reg);
    unlock_register(id_reg);

    // Call runtime subroutine
    emit_asm("CALL __builtin_vircon32_btnp\n");
    emit_asm("IADD SP, 2 ; Clean up btnp() arguments\n");

    // Transfer result to dest_reg if needed
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Transfer result to dest_reg\n", dest_reg);
    }

    return true;
}
