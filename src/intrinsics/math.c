#include "v32lua.h"

/**
 * Emits assembly for the math.floor(x) intrinsic.
 *
 * Rounds x down to the nearest integer (toward negative infinity).
 * Delegates to the runtime library's __builtin_floor subroutine.
 *
 * @param node     The AST node representing the function call.
 * @param dest_reg The destination register for the result (0 = discard).
 * @return         true if successfully emitted, false on error.
 */
bool emit_math_floor_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.floor() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.floor(x) ---\n");

    int arg_reg = allocate_pinned_register();

    generate_asm(arg, arg_reg);

    emit_asm("FLR R%d ; Floor the value\n", arg_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, arg_reg);
    }

    unlock_pinned_register(arg_reg);

    return (true);
}

/**
 * Emits assembly for the math.sqrt(x) intrinsic.
 *
 * Returns the square root of x.
 *
 * @param node     The AST node representing the function call.
 * @param dest_reg The destination register for the result (0 = discard).
 * @return         true if successfully emitted, false on error.
 */
bool emit_math_sqrt_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.sqrt() expects exactly one argument");  // ✅ Fixed error message
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.sqrt(x) ---\n");

    int arg_reg = allocate_pinned_register();
    int tmp_reg = allocate_pinned_register();

    generate_asm(arg, arg_reg);

    // Compute sqrt(x) = x^0.5
    emit_asm("MOV R%d, 0.5 ; Load exponent\n", tmp_reg);
    emit_asm("POW R%d, R%d ; Compute x^0.5\n", arg_reg, tmp_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d ; Transfer result\n", dest_reg, arg_reg);
    }

    unlock_pinned_register(tmp_reg);
    unlock_pinned_register(arg_reg);

    return true;
}

// ============================================================================
// Tier 1: Single-argument math intrinsics with direct Vircon32 instructions
// ============================================================================

/**
 * Emits assembly for the math.sin(x) intrinsic.
 * Calculates sine of x (in radians).
 */
bool emit_math_sin_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.sin() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.sin(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);
    emit_asm("SIN R%d ; Compute sine\n", arg_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, arg_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

/**
 * Emits assembly for the math.abs(x) intrinsic.
 * Returns absolute value of x.
 */
bool emit_math_abs_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.abs() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.abs(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);
    emit_asm("FABS R%d ; Absolute value\n", arg_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, arg_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

/**
 * Emits assembly for the math.ceil(x) intrinsic.
 * Rounds x up to nearest integer.
 */
bool emit_math_ceil_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.ceil() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.ceil(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);
    emit_asm("CEIL R%d ; Ceiling\n", arg_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, arg_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

/**
 * Emits assembly for the math.acos(x) intrinsic.
 * Returns arc cosine of x in radians.
 */
bool emit_math_acos_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.acos() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.acos(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);
    emit_asm("ACOS R%d ; Arc cosine\n", arg_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, arg_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

/**
 * Emits assembly for the math.log(x) intrinsic.
 * Returns natural logarithm of x.
 */
bool emit_math_log_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.log() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.log(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);
    emit_asm("LOG R%d ; Natural log\n", arg_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, arg_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

// ============================================================================
// Tier 2: Two-argument math intrinsics
// ============================================================================

/**
 * Emits assembly for the math.pow(x, y) intrinsic.
 * Returns x raised to power y.
 */
bool emit_math_pow_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || !arg->next || arg->next->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.pow() expects exactly two arguments");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.pow(x, y) ---\n");

    int x_reg = allocate_pinned_register();
    int y_reg = allocate_pinned_register();

    generate_asm(arg, x_reg);
    generate_asm(arg->next, y_reg);

    emit_asm("POW R%d, R%d ; R%d = R%d ^ R%d\n", x_reg, y_reg, x_reg, x_reg, y_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, x_reg);
    }

    unlock_pinned_register(x_reg);
    unlock_pinned_register(y_reg);
    return true;
}

/**
 * Emits assembly for the math.atan2(y, x) intrinsic.
 * Returns arc tangent of y/x in radians.
 */
bool emit_math_atan2_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || !arg->next || arg->next->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.atan2() expects exactly two arguments");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.atan2(y, x) ---\n");

    int y_reg = allocate_pinned_register();
    int x_reg = allocate_pinned_register();

    generate_asm(arg, y_reg);      // First arg = y
    generate_asm(arg->next, x_reg); // Second arg = x

    emit_asm("ATAN2 R%d, R%d ; R%d = atan2(R%d, R%d)\n", y_reg, x_reg, y_reg, y_reg, x_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, y_reg);
    }

    unlock_pinned_register(y_reg);
    unlock_pinned_register(x_reg);
    return true;
}

/**
 * Emits assembly for the math.random() intrinsic.
 *
 * Lua math.random() has three forms:
 *   math.random()      -> float in [0, 1)
 *   math.random(n)     -> integer in [1, n]
 *   math.random(m, n)  -> integer in [m, n]
 *
 * Delegates to runtime subroutine __builtin_random which handles
 * all cases and accesses the Vircon32 RNG hardware port (0x100).
 */
bool emit_math_random_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;
    int arg_count = 0;

    // Count arguments (0, 1, or 2 are valid)
    if (arg) {
        arg_count++;
        if (arg->next) {
            arg_count++;
            if (arg->next->next) {
                compiler_error(ERR_SYNTAX, node->line_number,
                    "math.random() expects 0, 1, or 2 arguments");
                return false;
            }
        }
    }

    emit_asm("    ;; --- Intrinsic: math.random() ---\n");

    // Push arguments onto stack in reverse order (C ABI)
    // Lua passes: arg1, arg2 (for math.random(m, n))
    // C expects:  n, m (right-to-left)

    int arg1_reg = 0, arg2_reg = 0;

    if (arg_count >= 1) {
        arg1_reg = allocate_pinned_register();
        generate_asm(arg, arg1_reg);
        emit_asm("    PUSH R%d       ; Push first argument\n", arg1_reg);
    }

    if (arg_count == 2) {
        arg2_reg = allocate_pinned_register();
        generate_asm(arg->next, arg2_reg);
        emit_asm("    PUSH R%d       ; Push second argument\n", arg2_reg);
    }

    // Call the runtime subroutine
    emit_asm("    CALL __builtin_random\n");

    // Clean up stack: 2 args = pop 2, 1 arg = pop 1, 0 args = pop 0
    if (arg_count > 0) {
        emit_asm("    IADD SP, %d    ; Clean up %d argument(s)\n", arg_count, arg_count);
    }

    // Result is in R0
    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0    ; Transfer result to dest_reg\n", dest_reg);
    }

    if (arg1_reg) unlock_pinned_register(arg1_reg);
    if (arg2_reg) unlock_pinned_register(arg2_reg);

    return true;
}

/**
 * Emits assembly for the math.randomseed(x) intrinsic.
 *
 * Seeds the Vircon32 RNG with x.
 * Returns nil.
 */
bool emit_math_randomseed_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.randomseed() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.randomseed(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);

    // Push argument for runtime call
    emit_asm("    PUSH R%d       ; Push seed argument\n", arg_reg);

    // Call runtime subroutine
    emit_asm("    CALL __builtin_randomseed\n");

    // Clean up stack (1 argument)
    emit_asm("    IADD SP, 1    ; Clean up 1 argument\n");

    // Result is in R0 (nil)
    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0    ; Transfer result (nil) to dest_reg\n", dest_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

/**
 * Emits assembly for the math.cos(x) intrinsic.
 *
 * Uses identity: cos(x) = sin(x + PI/2)
 * Delegates to runtime subroutine __builtin_cos.
 */
bool emit_math_cos_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.cos() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.cos(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);

    // Push argument for runtime call
    emit_asm("    PUSH R%d       ; Push argument\n", arg_reg);
    emit_asm("    CALL __builtin_cos\n");
    emit_asm("    IADD SP, 1    ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0    ; Transfer result to dest_reg\n", dest_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

/**
 * Emits assembly for the math.atan(x) intrinsic.
 *
 * Uses identity: atan(x) = atan2(x, 1)
 * Uses Vircon32 ATAN2 instruction directly.
 */
bool emit_math_atan_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.atan() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.atan(x) ---\n");

    int x_reg = allocate_pinned_register();
    int one_reg = allocate_pinned_register();

    generate_asm(arg, x_reg);

    // Load constant 1.0
    emit_asm("    MOV R%d, 1.0     ; Load constant 1 for ATAN2\n", one_reg);

    // ATAN2 takes: DSTREG, SRCREG where DSTREG = y, SRCREG = x
    // So we need: ATAN2 x_reg, one_reg to get atan2(x, 1)
    // But ATAN2 stores result in DSTREG, so we use x_reg as both y and result
    emit_asm("ATAN2 R%d, R%d ; R%d = atan2(x, 1) = atan(x)\n", x_reg, one_reg, x_reg);

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R%d    ; Transfer result to dest_reg\n", dest_reg, x_reg);
    }

    unlock_pinned_register(x_reg);
    unlock_pinned_register(one_reg);
    return true;
}

/**
 * Emits assembly for the math.exp(x) intrinsic.
 *
 * Uses identity: exp(x) = pow(e, x)
 * Delegates to runtime subroutine __builtin_exp.
 */
bool emit_math_exp_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.exp() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.exp(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);

    // Push argument for runtime call
    emit_asm("    PUSH R%d       ; Push argument\n", arg_reg);
    emit_asm("    CALL __builtin_exp\n");
    emit_asm("    IADD SP, 1    ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0    ; Transfer result to dest_reg\n", dest_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

// ============================================================================
// Quick Wins: Direct Vircon32 instruction mappings
// ============================================================================

/**
 * Emits assembly for the math.fmod(x, y) intrinsic.
 *
 * Returns x - y * floor(x/y) (floating point modulus).
 * Uses Vircon32 FMOD instruction directly.
 */
bool emit_math_fmod_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || !arg->next || arg->next->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.fmod() expects exactly two arguments");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.fmod(x, y) ---\n");

    int x_reg = allocate_pinned_register();
    int y_reg = allocate_pinned_register();

    generate_asm(arg, x_reg);
    generate_asm(arg->next, y_reg);

    emit_asm("FMOD R%d, R%d ; R%d = fmod(R%d, R%d)\n", x_reg, y_reg, x_reg, x_reg, y_reg);

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, x_reg);
    }

    unlock_pinned_register(x_reg);
    unlock_pinned_register(y_reg);
    return true;
}

/**
 * Emits assembly for the math.max(x, y) intrinsic.
 *
 * Returns the larger of x and y.
 * Uses Vircon32 FMAX instruction directly.
 */
bool emit_math_max_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || !arg->next || arg->next->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.max() expects exactly two arguments");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.max(x, y) ---\n");

    int x_reg = allocate_pinned_register();
    int y_reg = allocate_pinned_register();

    generate_asm(arg, x_reg);
    generate_asm(arg->next, y_reg);

    emit_asm("FMAX R%d, R%d ; R%d = max(R%d, R%d)\n", x_reg, y_reg, x_reg, x_reg, y_reg);

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, x_reg);
    }

    unlock_pinned_register(x_reg);
    unlock_pinned_register(y_reg);
    return true;
}

/**
 * Emits assembly for the math.min(x, y) intrinsic.
 *
 * Returns the smaller of x and y.
 * Uses Vircon32 FMIN instruction directly.
 */
bool emit_math_min_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || !arg->next || arg->next->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.min() expects exactly two arguments");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.min(x, y) ---\n");

    int x_reg = allocate_pinned_register();
    int y_reg = allocate_pinned_register();

    generate_asm(arg, x_reg);
    generate_asm(arg->next, y_reg);

    emit_asm("FMIN R%d, R%d ; R%d = min(R%d, R%d)\n", x_reg, y_reg, x_reg, x_reg, y_reg);

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, x_reg);
    }

    unlock_pinned_register(x_reg);
    unlock_pinned_register(y_reg);
    return true;
}

// ============================================================================
// Additional Math Functions - Runtime-based implementations
// ============================================================================

/**
 * Emits assembly for the math.asin(x) intrinsic.
 *
 * Arc sine: asin(x) = atan2(x, sqrt(1 - x^2))
 * Delegates to runtime subroutine __builtin_asin.
 */
bool emit_math_asin_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.asin() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.asin(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);

    emit_asm("    PUSH R%d       ; Push argument\n", arg_reg);
    emit_asm("    CALL __builtin_asin\n");
    emit_asm("    IADD SP, 1    ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0    ; Transfer result to dest_reg\n", dest_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

/**
 * Emits assembly for the math.tan(x) intrinsic.
 *
 * Tangent: tan(x) = sin(x) / cos(x)
 * Delegates to runtime subroutine __builtin_tan.
 */
bool emit_math_tan_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.tan() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.tan(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);

    emit_asm("    PUSH R%d       ; Push argument\n", arg_reg);
    emit_asm("    CALL __builtin_tan\n");
    emit_asm("    IADD SP, 1    ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0    ; Transfer result to dest_reg\n", dest_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

/**
 * Emits assembly for the math.deg(x) intrinsic.
 *
 * Convert radians to degrees: deg(x) = x * 180 / PI
 * Delegates to runtime subroutine __builtin_deg.
 */
bool emit_math_deg_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.deg() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.deg(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);

    emit_asm("    PUSH R%d       ; Push argument\n", arg_reg);
    emit_asm("    CALL __builtin_deg\n");
    emit_asm("    IADD SP, 1    ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0    ; Transfer result to dest_reg\n", dest_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

/**
 * Emits assembly for the math.rad(x) intrinsic.
 *
 * Convert degrees to radians: rad(x) = x * PI / 180
 * Delegates to runtime subroutine __builtin_rad.
 */
bool emit_math_rad_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.rad() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.rad(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);

    emit_asm("    PUSH R%d       ; Push argument\n", arg_reg);
    emit_asm("    CALL __builtin_rad\n");
    emit_asm("    IADD SP, 1    ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0    ; Transfer result to dest_reg\n", dest_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

/**
 * Emits assembly for the math.log10(x) intrinsic.
 *
 * Base-10 logarithm: log10(x) = log(x) / log(10)
 * Delegates to runtime subroutine __builtin_log10.
 */
bool emit_math_log10_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "math.log10() expects exactly one argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: math.log10(x) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);

    emit_asm("    PUSH R%d       ; Push argument\n", arg_reg);
    emit_asm("    CALL __builtin_log10\n");
    emit_asm("    IADD SP, 1    ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0    ; Transfer result to dest_reg\n", dest_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}
