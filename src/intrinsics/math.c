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
 * Returns the square root of x. Delegates to the runtime library's
 * __builtin_sqrt subroutine.
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
