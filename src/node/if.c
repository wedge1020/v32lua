#include "v32lua.h"

void  node_if (ASTNode *node)
{
    int         cond_reg  = allocate_register ();
    int         label_id  = get_next_label ();
    const char *ctx       = get_current_function_name ();
    char        else_label[128], end_label[128];
    snprintf(else_label, sizeof(else_label), "__%s_else_%d", ctx, label_id);
    snprintf(end_label, sizeof(end_label), "__%s_end_if_%d", ctx, label_id);

    // ✅ Used for condition check
    mark_register_live (cond_reg, 2);
    
    generate_asm (node -> as.if_stmt.condition, cond_reg);
    
    // AUDITED: Jump to else/end if the condition is Nil or False!
    emit_falsy_jump (cond_reg, else_label);
    unlock_register (cond_reg);
    
    push_scope ();
    generate_block (node -> as.if_stmt.if_body);
    pop_scope ();
    
    emit_asm ("JMP %s\n", end_label);
    emit_asm ("%s:\n", else_label);

    if (node -> as.if_stmt.else_body)
    {
        push_scope ();
        generate_block (node -> as.if_stmt.else_body);
        pop_scope ();
    }
    emit_asm ("%s:\n", end_label);
}
