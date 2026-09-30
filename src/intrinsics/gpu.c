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
// Packed RGBA colors -- shared by ioports.gpu.clear(r, g, b [, a]) and
// rgba(r, g, b [, a])
// ============================================================================

// Clamp a compile-time-known color component to 0..255, warning if the
// literal was out of range (or fractional, which truncates like CFI would).
static unsigned int rgba_fold_component (double value, const char *fname, const char *name, int line, bool warn)
{
    if (value < 0.0 || value > 255.0) {
        if (warn)
            compiler_warning (ERR_SEMANTIC, line,
                "%s: %s component %g is outside 0..255; clamped", fname, name, value);
        value = (value < 0.0) ? 0.0 : 255.0;
    } else if (value != (double)(int) value) {
        if (warn)
            compiler_warning (ERR_SEMANTIC, line,
                "%s: %s component %g is not a whole number; truncated", fname, name, value);
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
static void rgba_push_component (ASTNode *arg, const char *fname, const char *name, int line)
{
    double value;
    int reg = allocate_register ();
    register_pinned[reg] = 1;

    if (spu_static_number (arg, &value)) {
        unsigned int c = rgba_fold_component (value, fname, name, line, true);
        emit_asm ("MOV R%d, %u ; %s: %s = %u\n", reg, c, fname, name, c);
    } else {
        int bound = allocate_register ();
        register_pinned[bound] = 1;
        generate_asm (arg, reg);
        if (strcmp (name, "alpha") == 0) {
            // a nil alpha at run time is opaque, like a literal nil
            emit_asm ("MOV R%d, R%d\n", bound, reg);
            emit_asm ("IEQ R%d, BOXED_NIL\n", bound);
            int id = get_next_label ();
            const char *ctx = get_current_function_name ();
            emit_asm ("JF  R%d, __%s_rgba_alpha_%d\n", bound, ctx, id);
            emit_asm ("MOV R%d, 255.0 ; %s: nil alpha -> 255\n", reg, fname);
            emit_asm ("__%s_rgba_alpha_%d:\n", ctx, id);
        }
        emit_asm ("MOV R%d, 0.0\n", bound);
        emit_asm ("FMAX R%d, R%d ; %s: %s >= 0\n", reg, bound, fname, name);
        emit_asm ("MOV R%d, 255.0\n", bound);
        emit_asm ("FMIN R%d, R%d ; %s: %s <= 255\n", reg, bound, fname, name);
        emit_asm ("CFI R%d\n", reg);
        register_pinned[bound] = 0;
        unlock_register (bound);
    }

    emit_asm ("PUSH R%d ; %s: %s component\n", reg, fname, name);
    register_pinned[reg] = 0;
    unlock_register (reg);
}

static const char *rgba_names[4] = { "red", "green", "blue", "alpha" };

// The packed word of (r, g, b [, a]) when every component is a numeric
// literal (a missing or nil alpha is 255). No warnings: the emitter gives
// them.
bool rgba_static_word (ASTNode **args, int argc, unsigned int *word)
{
    if (argc != 3 && argc != 4) return false;
    double v[4] = { 0.0, 0.0, 0.0, 255.0 };
    for (int i = 0; i < 3; i++)
        if (!spu_static_number (args[i], &v[i])) return false;
    if (argc == 4 && args[3]->type != NODE_NIL && !spu_static_number (args[3], &v[3]))
        return false;
    unsigned int c[4];
    for (int i = 0; i < 4; i++) c[i] = rgba_fold_component (v[i], "", rgba_names[i], 0, false);
    *word = (c[3] << 24) | (c[2] << 16) | (c[1] << 8) | c[0];
    return true;
}

// Packs (r, g, b [, a]) into the GPU's 0xAABBGGRR word: folded at compile
// time when every component is a literal, else each component is clamped
// to 0..255, truncated and combined with SHL/OR at run time. A missing or
// nil alpha is 255. argc must be 3 or 4. Returns the register that holds
// the word (allocated here; the caller unlocks it), or -1 after an error.
int emit_pack_rgba (const char *fname, ASTNode **args, int argc, int line)
{
    bool has_alpha = (argc == 4 && args[3]->type != NODE_NIL);

    for (int i = 0; i < 3; i++) {
        if (args[i]->type == NODE_STRING || args[i]->type == NODE_NIL) {
            compiler_error (ERR_SEMANTIC, line, "%s: %s component must be a number", fname, rgba_names[i]);
            return -1;
        }
    }
    if (has_alpha && args[3]->type == NODE_STRING) {
        compiler_error (ERR_SEMANTIC, line, "%s: alpha component must be a number", fname);
        return -1;
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
            c[i] = rgba_fold_component (v[i], fname, rgba_names[i], line, true);
        unsigned int packed = (c[3] << 24) | (c[2] << 16) | (c[1] << 8) | c[0];

        int color_reg = allocate_register ();
        emit_asm ("MOV R%d, 0x%.8X ; %s(%u, %u, %u, %u) -> 0xAABBGGRR\n",
                  color_reg, packed, fname, c[0], c[1], c[2], c[3]);
        return color_reg;
    }

    // --- Runtime pack: push r, g, b, a; pop a, b, g, r ---
    for (int i = 0; i < 3; i++)
        rgba_push_component (args[i], fname, rgba_names[i], line);
    if (has_alpha) {
        rgba_push_component (args[3], fname, rgba_names[3], line);
    } else {
        emit_asm ("MOV R0, 255 ; %s: alpha defaults to opaque\n", fname);
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

    register_pinned[tmp] = 0;
    unlock_register (tmp);
    register_pinned[acc] = 0;
    return acc;
}

/**
 * rgba(r, g, b [, a]) -- native Vircon32 mode: the RAW packed 0xAABBGGRR
 * word (not a Lua number), for spr()'s color_mult, ioports.gpu.clear(color),
 * ioports.gpu.multiply / bgcolor ... Components are clamped to 0..255 and
 * truncated; a missing or nil alpha is 255 -- exactly clear(r, g, b [, a]).
 *
 * CAVEAT: a raw word whose top bits match a NaN-box tag IS that value to
 * the rest of the language: rgba(0, 0, 192, 255) is 0xFFC00000 = nil, and
 * 0xFF8xxxxx reads as a table. Passing it straight to a call is safe;
 * storing it in a table, testing it, or comparing it with nil is not
 * (hex() has the same issue). Keep the components as numbers and call
 * rgba() where the color is used.
 */
bool emit_rgba_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *args[5] = { NULL };
    int      argc    = 0;
    for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next) {
        if (argc < 5) args[argc] = a;
        argc++;
    }
    if (argc != 3 && argc != 4) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "rgba(): expected 3 or 4 arguments (rgba(r, g, b [, a])), got %d", argc);
        return false;
    }
    emit_asm ("    ;; --- Intrinsic: rgba() -> raw packed 0xAABBGGRR ---\n");
    int reg = emit_pack_rgba ("rgba()", args, argc, node->line_number);
    if (reg < 0) return false;
    if (dest_reg != 0 && dest_reg != reg)
        emit_asm ("MOV R%d, R%d ; rgba() result (a raw word, not a number)\n", dest_reg, reg);
    unlock_register (reg);
    return true;
}

// The raw word color(n) gives for a compile-time number: floor, then wrap
// into 32 bits (negative numbers count down from 2^32, so -1 is
// 0xFFFFFFFF); outside -2^31 .. 2^32 it saturates, as __bit_in does.
bool color_static_word (ASTNode *arg, unsigned int *word)
{
    double v;
    if (!spu_static_number (arg, &v)) return false;
    v = floor (v);
    if (v >= 4294967296.0)       *word = 0xFFFFFFFFu;
    else if (v < -2147483648.0)  *word = 0x80000000u;
    else if (v < 0.0)            *word = (unsigned int) (long long) (v + 4294967296.0);
    else                         *word = (unsigned int) (long long) v;
    return true;
}

/**
 * color(n) -- native Vircon32 mode: a number as the RAW 32-bit word
 * (0xAABBGGRR for a color), for color_mult, ioports.gpu.clear(color),
 * ioports.gpu.multiply ... The number is floored and wrapped into 32 bits
 * (-1 -> 0xFFFFFFFF), the same conversion the bitwise operators use
 * (__bit_in). A literal folds at compile time, exactly. At run time a
 * v32lua number is a float32, which holds only 24 significant bits: a
 * computed 0x802040FF has already been rounded (to 0x80204100) before
 * color() sees it -- use rgba() or hex() for full 32-bit colors, and
 * color() for words that fit in 24 significant bits (small integers,
 * 0xAA000000-style alpha-only words, colors with low bytes that are
 * zero). Same NaN-box caveat as rgba(): pass the result on, don't store
 * or test it.
 */
bool emit_color_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;
    int argc = 0;
    for (ASTNode *a = arg; a != NULL; a = a->next) argc++;
    if (argc != 1) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "color(): expected 1 argument (color(n)), got %d", argc);
        return false;
    }
    if (arg->type == NODE_STRING || arg->type == NODE_NIL || arg->type == NODE_BOOLEAN) {
        compiler_error (ERR_SEMANTIC, node->line_number, "color(): the argument must be a number");
        return false;
    }
    unsigned int word;
    if (color_static_word (arg, &word)) {
        double v;
        spu_static_number (arg, &v);
        if (v >= 4294967296.0 || v < -2147483648.0)
            compiler_warning (ERR_SEMANTIC, node->line_number,
                "color(): %g does not fit in 32 bits; saturated to 0x%08X", v, word);
        if (dest_reg != 0)
            emit_asm ("MOV R%d, 0x%08X ; color(%.0f)\n", dest_reg, word, v);
        return true;
    }
    runtime_req.needs_math = true;       // __bit_in lives in math.s
    int r = allocate_register ();
    generate_asm (arg, r);
    ensure_in_register (r);
    emit_asm ("    ;; --- Intrinsic: color() -> raw 32-bit word (floor, wrap) ---\n");
    emit_asm ("PUSH R1\n");
    emit_asm ("PUSH R2\n");
    emit_asm ("PUSH R3\n");
    emit_asm ("PUSH R7\n");
    emit_asm ("MOV R1, R%d\n", r);
    emit_asm ("MOV R7, 0 ; integer (not 16.16) conversion\n");
    emit_asm ("CALL __bit_in\n");
    emit_asm ("MOV R0, R1\n");
    emit_asm ("POP R7\n");
    emit_asm ("POP R3\n");
    emit_asm ("POP R2\n");
    emit_asm ("POP R1\n");
    if (dest_reg != 0)
        emit_asm ("MOV R%d, R0 ; color() result (a raw word, not a number)\n", dest_reg);
    unlock_register (r);
    return true;
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
        int color_reg = emit_pack_rgba ("ioports.gpu.clear()", args, argc, node->line_number);
        if (color_reg < 0) return;
        emit_asm ("OUT GPU_ClearColor, R%d\n", color_reg);
        unlock_register (color_reg);
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
