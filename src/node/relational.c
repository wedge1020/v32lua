#include "v32lua.h"

void  node_relational (ASTNode *node, int  dest_reg)
{
    // Comparisons are compiled as jumps (node/cond.c); as a value the
    // boolean is materialized once at the end.
    generate_bool_value (node, dest_reg);
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
