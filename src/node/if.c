#include "v32lua.h"

void  node_if (ASTNode *node)
{
    int         label_id  = get_next_label ();
    const char *ctx       = get_current_function_name ();
    char        else_label[128], end_label[128];
    snprintf(else_label, sizeof(else_label), "__%s_else_%d", ctx, label_id);
    snprintf(end_label, sizeof(end_label), "__%s_end_if_%d", ctx, label_id);

    // Jump to else/end when the condition is nil or false (compiled as
    // jumps: see node/cond.c)
    generate_cond_jump (node -> as.if_stmt.condition, false, else_label);
    
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
