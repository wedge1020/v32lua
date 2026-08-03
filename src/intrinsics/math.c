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

    int arg_reg = allocate_register();
	register_pinned[arg_reg] = 1;
    generate_asm(arg, arg_reg);
    emit_asm("FLR R%d ; Floor the value\n", arg_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d ; Transfer result to dest_reg\n", dest_reg, arg_reg);
    }

	register_pinned[arg_reg] = 0;
    unlock_register(arg_reg);
    return true;
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

    int arg_reg = allocate_register();
    int tmp_reg = allocate_register();
	register_pinned[arg_reg] = 1;
	register_pinned[tmp_reg] = 1;
    generate_asm(arg, arg_reg);

    // Compute sqrt(x) = x^0.5
    emit_asm("MOV R%d, 0.5 ; Load exponent\n", tmp_reg);
    emit_asm("POW R%d, R%d ; Compute x^0.5\n", arg_reg, tmp_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R%d ; Transfer result\n", dest_reg, arg_reg);
    }

	register_pinned[arg_reg] = 0;
	register_pinned[tmp_reg] = 0;
    unlock_register(tmp_reg);
    unlock_register(arg_reg);
    return true;
}
