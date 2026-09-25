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
        if (strcmp (blendmode, "alpha") == 0 || strcmp (blendmode, "default") == 0)
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

// ============================================================================
// ioports.gpu.clear() -- helpers
// ============================================================================

// Clamp a compile-time-known color component to 0..255, warning if the
// literal was out of range (or fractional, which truncates like CFI would).
static unsigned int gpu_clear_fold_component (double value, const char *name, int line)
{
    if (value < 0.0 || value > 255.0) {
        compiler_warning (ERR_SEMANTIC, line,
            "ioports.gpu.clear(): %s component %g is outside 0..255; clamped", name, value);
        value = (value < 0.0) ? 0.0 : 255.0;
    } else if (value != (double)(int) value) {
        compiler_warning (ERR_SEMANTIC, line,
            "ioports.gpu.clear(): %s component %g is not a whole number; truncated", name, value);
    }
    return (unsigned int) value;
}

// Evaluate one RGBA component and PUSH it as a clamped 0..255 INTEGER.
//
// Literal components are folded and pushed as an integer immediate. Anything
// else is evaluated as a normal Lua (float) expression, clamped to 0.0..255.0
// with FMAX/FMIN (register-register form, same as math.min()/mid() use), then
// converted with CFI. Each component is pushed immediately after it is
// computed, so a component expression that CALLs (a function call, table
// lookup, ...) can't clobber a component computed earlier -- register
// contents do not survive CALL boundaries.
static void gpu_clear_push_component (ASTNode *arg, const char *name, int line)
{
    double value;
    int reg = allocate_register ();
    register_pinned[reg] = 1;

    if (spu_static_number (arg, &value)) {
        unsigned int c = gpu_clear_fold_component (value, name, line);
        emit_asm ("MOV R%d, %u ; clear(): %s = %u\n", reg, c, name, c);
    } else {
        int bound = allocate_register ();
        register_pinned[bound] = 1;
        generate_asm (arg, reg);
        emit_asm ("MOV R%d, 0.0\n", bound);
        emit_asm ("FMAX R%d, R%d ; clear(): %s >= 0\n", reg, bound, name);
        emit_asm ("MOV R%d, 255.0\n", bound);
        emit_asm ("FMIN R%d, R%d ; clear(): %s <= 255\n", reg, bound, name);
        emit_asm ("CFI R%d\n", reg);
        register_pinned[bound] = 0;
        unlock_register (bound);
    }

    emit_asm ("PUSH R%d ; clear(): %s component\n", reg, name);
    register_pinned[reg] = 0;
    unlock_register (reg);
}

/**
 * Emits assembly for ioports.gpu.clear().
 *
 * Forms:
 *   ioports.gpu.clear()                  -- reuse current GPU_ClearColor
 *   ioports.gpu.clear("black")           -- preset name (string literal)
 *   ioports.gpu.clear(0xFF202020)        -- packed 0xAABBGGRR literal
 *   ioports.gpu.clear(hex("0xFF202020")) -- packed, raw 32-bit word
 *   ioports.gpu.clear(expr)              -- packed, passed through as-is
 *   ioports.gpu.clear(r, g, b [, a])     -- components 0..255, a defaults 255
 *
 * NUMERIC LITERALS: v32lua numbers are float32, so a packed color written
 * as a plain literal (0xFF202020) used to be emitted as
 * "MOV Rn, 4280295456.000000" -- the GPU received the FLOAT's bit pattern,
 * not the color. A literal is now folded to its raw 32-bit integer at
 * compile time, the same word hex() would produce. A packed color held in a
 * VARIABLE is still passed through untouched, so it must have come from
 * hex() (or the r,g,b,a form) to hold a raw word.
 *
 * The r,g,b[,a] form packs to the GPU's 0xAABBGGRR layout: at compile time
 * when every component is a literal, otherwise at runtime (each component
 * clamped to 0..255, then combined with SHL/OR). An explicit nil for `a`
 * means "opaque" (255), exactly like omitting it.
 */
void emit_gpu_clear_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm ("    ;; --- Intrinsic: ioports.gpu.clear() ---\n");

    ASTNode *args[5] = { NULL };
    int      argc    = 0;
    for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next) {
        if (argc < 5) args[argc] = a;
        argc++;
    }

    if (argc == 2 || argc > 4) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "ioports.gpu.clear(): expected 0, 1, 3 or 4 arguments "
            "(clear(), clear(color), clear(r, g, b [, a])), got %d", argc);
        return;
    }

    // =====================================================================
    // clear(r, g, b [, a])
    // =====================================================================
    if (argc >= 3) {
        static const char *names[4] = { "red", "green", "blue", "alpha" };
        bool has_alpha = (argc == 4 && args[3]->type != NODE_NIL);

        for (int i = 0; i < 3; i++) {
            if (args[i]->type == NODE_STRING || args[i]->type == NODE_NIL) {
                compiler_error (ERR_SEMANTIC, node->line_number,
                    "ioports.gpu.clear(): %s component must be a number", names[i]);
                return;
            }
        }
        if (has_alpha && args[3]->type == NODE_STRING) {
            compiler_error (ERR_SEMANTIC, node->line_number,
                "ioports.gpu.clear(): alpha component must be a number");
            return;
        }

        // --- All literal: fold to one packed word ---
        double v[4] = { 0.0, 0.0, 0.0, 255.0 };
        bool all_static = true;
        for (int i = 0; i < 3; i++)
            all_static = all_static && spu_static_number (args[i], &v[i]);
        if (has_alpha)
            all_static = all_static && spu_static_number (args[3], &v[3]);

        if (all_static) {
            unsigned int c[4];
            for (int i = 0; i < 4; i++)
                c[i] = gpu_clear_fold_component (v[i], names[i], node->line_number);
            unsigned int packed = (c[3] << 24) | (c[2] << 16) | (c[1] << 8) | c[0];

            int color_reg = allocate_register ();
            emit_asm ("MOV R%d, 0x%.8X ; clear(%u, %u, %u, %u) -> 0xAABBGGRR\n",
                      color_reg, packed, c[0], c[1], c[2], c[3]);
            emit_asm ("OUT GPU_ClearColor, R%d\n", color_reg);
            unlock_register (color_reg);
        } else {
            // --- Runtime pack: push r, g, b, a; pop a, b, g, r ---
            for (int i = 0; i < 3; i++)
                gpu_clear_push_component (args[i], names[i], node->line_number);
            if (has_alpha) {
                gpu_clear_push_component (args[3], names[3], node->line_number);
            } else {
                emit_asm ("MOV R0, 255 ; clear(): alpha defaults to opaque\n");
                emit_asm ("PUSH R0\n");
            }

            int acc = allocate_register ();
            register_pinned[acc] = 1;
            int tmp = allocate_register ();
            register_pinned[tmp] = 1;

            emit_asm ("POP R%d ; alpha\n", acc);
            emit_asm ("SHL R%d, 8\n", acc);
            emit_asm ("POP R%d ; blue\n", tmp);
            emit_asm ("OR R%d, R%d\n", acc, tmp);
            emit_asm ("SHL R%d, 8\n", acc);
            emit_asm ("POP R%d ; green\n", tmp);
            emit_asm ("OR R%d, R%d\n", acc, tmp);
            emit_asm ("SHL R%d, 8\n", acc);
            emit_asm ("POP R%d ; red\n", tmp);
            emit_asm ("OR R%d, R%d ; R%d = 0xAABBGGRR\n", acc, tmp, acc);
            emit_asm ("OUT GPU_ClearColor, R%d\n", acc);

            register_pinned[tmp] = 0;
            unlock_register (tmp);
            register_pinned[acc] = 0;
            unlock_register (acc);
        }
    }

    // =====================================================================
    // clear(color)
    // =====================================================================
    else if (argc == 1) {
        ASTNode *arg = args[0];
        double   num;
        int color_reg = allocate_register();
        register_pinned[color_reg] = 1;

        if (arg->type == NODE_STRING) {
            const char *color_name = arg->as.string_val.value;
            unsigned int color_hex = 0;

            if      (strcmp(color_name, "black") == 0) color_hex = 0xFF000000;
            else if (strcmp(color_name, "white") == 0) color_hex = 0xFFFFFFFF;
            else if (strcmp(color_name, "blue") == 0)  color_hex = 0xFFFF0000;
            else if (strcmp(color_name, "red") == 0)   color_hex = 0xFF0000FF;
            else if (strcmp(color_name, "green") == 0) color_hex = 0xFF00FF00;
            else {
                // A string literal that isn't a preset can never be a color;
                // this used to silently write the string's NaN-boxed pointer.
                compiler_error (ERR_SEMANTIC, node->line_number,
                    "ioports.gpu.clear(): unknown color name '%s' "
                    "(expected \"black\", \"white\", \"blue\", \"red\" or \"green\")",
                    color_name);
                return;
            }
            emit_asm ("MOV R%d, 0x%.8X ; Preset color '%s'\n", color_reg, color_hex, color_name);
        } else if (spu_static_number (arg, &num)) {
            // Packed literal: emit the raw 32-bit word, not a float.
            // Negative literals are taken as two's complement (-1 == 0xFFFFFFFF).
            if (num < -2147483648.0 || num > 4294967295.0 || num != (double)(long long) num) {
                compiler_warning (ERR_SEMANTIC, node->line_number,
                    "ioports.gpu.clear(): %g is not a valid packed 32-bit color", num);
            }
            unsigned int word = (unsigned int)(long long) num;
            emit_asm ("MOV R%d, 0x%.8X ; Packed color literal (raw word, not float)\n",
                      color_reg, word);
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
