#include "v32lua.h"

/**
 * Emits assembly for the ioports.gpu.draw() intrinsic.
 *
 * Dispatches GPU draw commands based on the provided mode argument.
 * Supports static string literals, numeric literals, and dynamic variables.
 *
 * Modes:
 *   "draw"     -> GPUCommand_DrawRegion (default)
 *   "zoom"     -> GPUCommand_DrawRegionZoomed
 *   "rotate"   -> GPUCommand_DrawRegionRotated
 *   "rotozoom" -> GPUCommand_DrawRegionRotozoomed
 *   0          -> DrawRegion (default)
 *   1          -> DrawRegionZoomed
 *   2          -> DrawRegionRotated
 *   3          -> DrawRegionRotozoomed
 *
 * @param node     The AST node representing the function call.
 * @param dest_reg The destination register for the result (0 = discard).
 *                 If provided, returns BOXED_NIL (no meaningful return value).
 * @return         true if successfully emitted.
 */
bool emit_gpu_draw_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg_mode = node->as.call.args_head;

    emit_asm("    ;; --- Intrinsic: ioports.gpu.draw(mode) ---\n");

    // =====================================================================
    // CASE A: No argument -> Default to standard draw
    // =====================================================================
    if (arg_mode == NULL) {
        emit_asm("OUT GPU_Command, GPUCommand_DrawRegion\n");
        if (dest_reg != 0) {
            emit_asm("MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
        }
        return true;
    }

    // =====================================================================
    // CASE B: Static String Literal -> Fold directly to GPU command
    // =====================================================================
    if (arg_mode->type == NODE_STRING) {
        const char *val = arg_mode->as.string_val.value;

        if      (strcmp(val, "draw")     == 0) emit_asm("OUT GPU_Command, GPUCommand_DrawRegion\n");
        else if (strcmp(val, "zoom")     == 0) emit_asm("OUT GPU_Command, GPUCommand_DrawRegionZoomed\n");
        else if (strcmp(val, "rotate")   == 0) emit_asm("OUT GPU_Command, GPUCommand_DrawRegionRotated\n");
        else if (strcmp(val, "rotozoom") == 0) emit_asm("OUT GPU_Command, GPUCommand_DrawRegionRotozoomed\n");
        else {
            // Unrecognized string: fallback to default draw
            emit_asm("OUT GPU_Command, GPUCommand_DrawRegion\n");
        }

        if (dest_reg != 0) {
            emit_asm("MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
        }
        return true;
    }

    // =====================================================================
    // CASE C: Static Number Literal -> Map to GPU command
    // =====================================================================
    if (arg_mode->type == NODE_NUMBER) {
        int cmd = (int)arg_mode->as.number.val;

        if      (cmd == 1) emit_asm("OUT GPU_Command, GPUCommand_DrawRegionZoomed\n");
        else if (cmd == 2) emit_asm("OUT GPU_Command, GPUCommand_DrawRegionRotated\n");
        else if (cmd == 3) emit_asm("OUT GPU_Command, GPUCommand_DrawRegionRotozoomed\n");
        else {
            // 0 or invalid: default to standard draw
            emit_asm("OUT GPU_Command, GPUCommand_DrawRegion\n");
        }

        if (dest_reg != 0) {
            emit_asm("MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
        }
        return true;
    }

    // =====================================================================
    // CASE D: Dynamic Variable -> Runtime evaluation with nil-check
    // =====================================================================
    int mode_reg = allocate_register();
	register_pinned[mode_reg] = 1;
    generate_asm(arg_mode, mode_reg);

    int label_id = get_next_label();
    const char *ctx = get_current_function_name();

    char is_nil_label[128], end_label[128];
    snprintf(is_nil_label, sizeof(is_nil_label), "__%s_gpu_draw_nil_%d", ctx, label_id);
    snprintf(end_label,    sizeof(end_label),    "__%s_gpu_draw_end_%d", ctx, label_id);

    int scratch = allocate_register();
	register_pinned[scratch] = 1;

    // Check for runtime nil (no argument provided)
    emit_asm("MOV R%d, R%d\n",          scratch, mode_reg);
    emit_asm("IEQ R%d, BOXED_NIL ; Check for runtime nil\n", scratch);
    emit_asm("JT R%d, %s ; If nil, jump to default fallback\n", scratch, is_nil_label);

    // Not nil: cast float to integer for GPU command
    emit_asm("CFI R%d\n", mode_reg);
    emit_asm("JMP %s\n",   end_label);

    // Nil fallback: use default draw mode (0)
    emit_asm("%s:\n", is_nil_label);
    emit_asm("MOV R%d, 0 ; Runtime nil -> Default to draw (0)\n", mode_reg);

    emit_asm("%s:\n", end_label);

    // Dispatch the resolved mode to the GPU
    emit_asm("OUT GPU_Command, R%d ; Trigger GPU operation\n", mode_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
    }

	register_pinned[mode_reg] = 0;
	register_pinned[scratch] = 0;

    unlock_register(scratch);
    unlock_register(mode_reg);

    return true;
}

void emit_gpu_blending_intrinsic (ASTNode *node, int  dest_reg)
{
    emit_asm ("    ;; --- Intrinsic: ioports.gpu.blending() ---\n");
    ASTNode *arg = node -> as.call.args_head;

    if (arg != NULL && arg -> type == NODE_STRING)
    {
        const char *blendmode = arg -> as.string_val.value;
        if (strcmp (blendmode, "alpha") == 0)
            emit_asm ("OUT GPU_ActiveBlending, GPUBlendingMode_Alpha\n");
        else if (strcmp (blendmode, "add") == 0)
            emit_asm ("OUT GPU_ActiveBlending, GPUBlendingMode_Add\n");
        else if (strcmp (blendmode, "subtract") == 0)
            emit_asm ("OUT GPU_ActiveBlending, GPUBlendingMode_Subtract\n");
        else
            compiler_error (ERR_SEMANTIC, yylineno, "%s: invalid blending mode '%s'", "ioports.gpu.blending()", blendmode);
    }
    else
    {
        compiler_error (ERR_SEMANTIC, yylineno, "%s: invalid blending mode", "ioports.gpu.blending()");
    }

    if (dest_reg != 0) {
        emit_asm ("    MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
    }
}

void emit_gpu_clear_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm ("    ;; --- Intrinsic: ioports.gpu.clear() ---\n");
    ASTNode *arg = node->as.call.args_head;

    if (arg != NULL) {
        int color_reg = allocate_register();
		register_pinned[color_reg] = 1;
        if (arg->type == NODE_STRING) {
            const char *color_name = arg->as.string_val.value;
            unsigned int color_hex = 0x000000FF; // Default Opaque Black
            int is_preset = 1;

            if      (strcmp(color_name, "black") == 0) color_hex = 0xFF000000; 
            else if (strcmp(color_name, "white") == 0) color_hex = 0xFFFFFFFF;
            else if (strcmp(color_name, "blue") == 0)  color_hex = 0xFFFF0000;
            else if (strcmp(color_name, "red") == 0)   color_hex = 0xFF0000FF;
            else if (strcmp(color_name, "green") == 0) color_hex = 0xFF00FF00;
            else is_preset = 0; 
            
            if (is_preset) {
                emit_asm ("MOV R%d, 0x%.8X ; Preset color '%s'\n", color_reg, color_hex, color_name);
            } else {
                generate_asm(arg, color_reg);
            }
        } else {
            generate_asm(arg, color_reg);
        }
        emit_asm ("OUT GPU_ClearColor, R%d\n", color_reg);
		register_pinned[color_reg] = 0;
        unlock_register(color_reg);
    }

    emit_asm ("OUT GPU_Command, GPUCommand_ClearScreen\n");
    if (dest_reg != 0) {
        emit_asm ("MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
    }
}
