#include "v32lua.h"

void  node_relational (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);
    int  right_reg  = allocate_register ();
    generate_asm (node -> as.binary.right, right_reg);

    ensure_in_register (dest_reg);
    ensure_in_register (right_reg);

    if (node->as.binary.operator == OP_EQ || node->as.binary.operator == OP_NEQ) {
        emit_asm("PUSH R%d\n", dest_reg);
        emit_asm("PUSH R%d\n", right_reg);
        emit_asm("CALL __builtin_eq\n");
        emit_asm("IADD SP, 2\n");

        if (node->as.binary.operator == OP_NEQ) {
            emit_asm("MOV R%d, R0\n", dest_reg);
            emit_asm("XOR R%d, 3 ; Flip BOXED_FALSE (0xFFC00001) <-> BOXED_TRUE (0xFFC00002)\n", dest_reg);
        } else {
            emit_asm("MOV R%d, R0\n", dest_reg);
        }
    }
    else
    {
        // Ordering operators (<, <=, >, >=) have to work for BOTH numbers
        // and strings. A raw FLT/FGT on the register only makes sense when
        // it holds an actual float -- a boxed string holds a tagged
        // *pointer*, so comparing it directly with FLT/FGT compares
        // meaningless bit patterns instead of string contents. Route
        // through the type-aware runtime comparator instead, then turn
        // its signed result (-1 / 0 / 1) into a Lua boolean.
        emit_asm("PUSH R%d\n", dest_reg);
        emit_asm("PUSH R%d\n", right_reg);
        emit_asm("CALL __builtin_relcmp\n");
        emit_asm("IADD SP, 2\n");

        switch (node -> as.binary.operator)
        {
            case OP_LT:
                emit_asm ("ILT R0, 0 ; true if relcmp result < 0\n");
                break;

            case OP_LE:
                emit_asm ("IGT R0, 0 ; (result > 0) ...\n");
                emit_asm ("XOR R0, 1 ; ...inverted: LE means 'not greater'\n");
                break;

            case OP_GT:
                emit_asm ("IGT R0, 0 ; true if relcmp result > 0\n");
                break;

            case OP_GE:
                emit_asm ("ILT R0, 0 ; (result < 0) ...\n");
                emit_asm ("XOR R0, 1 ; ...inverted: GE means 'not less'\n");
                break;

            default:
                break;
        }

        emit_asm ("MOV R%d, R0\n", dest_reg);
        emit_asm ("IADD R%d, BOXED_BOOLEAN ; Box as Lua Boolean (False/True)\n", dest_reg);
    }
    unlock_register (right_reg);
}

void  node_and (ASTNode *node, int  dest_reg)
{
    int         label_id        = get_next_label ();
    const char *ctx             = get_current_function_name ();
    char        end_label[128];

    // generate label
    snprintf (end_label, sizeof (end_label), "__%s_short_and_%d", ctx, label_id);

    // 1. Ensure dest_reg is available (in case of spilling)
    ensure_in_register (dest_reg);

    // 2. Evaluate Left Operand into dest_reg
    generate_asm (node -> as.binary.left, dest_reg);

    // 3. Short-circuit: if left is falsy, jump to end with falsy result
    emit_falsy_jump (dest_reg, end_label);

    // 4. Otherwise, evaluate Right Operand into dest_reg
    //    dest_reg still holds left value, but we overwrite it with right
    generate_asm (node -> as.binary.right, dest_reg);

    // 5. End label
    emit_asm ("%s:\n", end_label);
}

void  node_or  (ASTNode *node, int  dest_reg)
{
    int         label_id        = get_next_label ();
    const char *ctx             = get_current_function_name ();
    char        end_label[128];

    snprintf (end_label, sizeof (end_label), "__%s_short_or_%d", ctx, label_id);

    // 1. Ensure dest_reg is available (may have been spilled)
    ensure_in_register (dest_reg);

    // 2. Evaluate Left Operand into dest_reg
    generate_asm (node -> as.binary.left, dest_reg);

    // 3. Short-circuit: if left is truthy, jump to end with truthy result
    emit_truthy_jump (dest_reg, end_label);

    // 4. Otherwise, evaluate Right Operand into dest_reg
    //    dest_reg still holds left value, but we overwrite it with right
    generate_asm (node -> as.binary.right, dest_reg);

    // 5. End label
    emit_asm ("%s:\n", end_label);
}
