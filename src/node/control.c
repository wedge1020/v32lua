#include "v32lua.h"

void  node_break (void)
{
    int  current_id     = current_loop ();
    if (current_id     == -1)
    {
        fprintf (stderr, "Compiler Runtime Error: 'break' declaration found outside loop.\n");
        exit (1);
    }

    // Each loop type builds its own exit label with a different tag (see
    // node_while/node_for_numeric/node_for_generic) -- 'while' and 'for'
    // are NOT interchangeable prefixes, and for_gen has a THIRD tag of its
    // own. A two-way ternary here silently mapped LOOP_TYPE_FOR_GENERIC
    // onto the 'while' label, which node_for_generic never actually
    // defines -- 'break' inside a generic for loop jumped to a label that
    // didn't exist: an unresolved-label error at assembly time.
    LoopType    type = current_loop_type ();
    const char *tag;
    switch (type) {
        case LOOP_TYPE_FOR_NUMERIC: tag = "for";     break;
        case LOOP_TYPE_FOR_GENERIC: tag = "for_gen"; break;
        case LOOP_TYPE_WHILE:
        default:                    tag = "while";   break;
    }
    emit_asm ("JMP __%s_%s_end_%d\n", get_current_function_name (), tag, current_id);
}

void  node_return (ASTNode *node)
{
    ASTNode *expr = node -> as.return_stmt.expressions_head;
    int ret_idx = 0;
    int arg_count = node -> as.return_stmt.parent_func_arg_count;
    
    while (expr != NULL) {
        int val_reg = allocate_register();
        generate_asm (expr, val_reg);
        
        if (ret_idx == 0)      { emit_asm ("MOV R0, R%d\n", val_reg); }
        else if (ret_idx == 1) { emit_asm ("MOV R2, R%d\n", val_reg); }
        else if (ret_idx == 2) { emit_asm ("MOV R3, R%d\n", val_reg); }
        else {
            int offset = 2 + arg_count + (ret_idx - 3);
            emit_asm ("MOV [BP + %d], R%d\n", offset, val_reg);
        }
        unlock_register(val_reg);
        
        ret_idx++;
        expr = expr -> next;
    }
    emit_asm ("JMP __%s_return\n", get_current_function_name ());
}
