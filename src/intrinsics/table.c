#include "v32lua.h"

// ============================================================================
// table.remove(t, [pos]) - Removes and returns the element at position
// ============================================================================
int emit_table_remove_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;
    if (!arg) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "table.remove() expects at least one argument");
        return 0;
    }

    emit_asm("    ;; --- Intrinsic: table.remove(t, [pos]) ---\n");
    int t_reg = allocate_register();
    generate_asm(arg, t_reg);

    int pos_reg = allocate_register();
    if (arg->next != NULL) {
        generate_asm(arg->next, pos_reg);
    } else {
        emit_asm("    MOV R%d, BOXED_NIL\n", pos_reg);  // default: remove last element
    }

    emit_asm("    PUSH R%d ; Table Pointer\n", t_reg);
    emit_asm("    PUSH R%d ; Position\n", pos_reg);
    emit_asm("    CALL __builtin_table_remove\n");
    emit_asm("    IADD SP, 2\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0\n", dest_reg);
    }

    unlock_register(t_reg);
    unlock_register(pos_reg);
    return 1;
}
