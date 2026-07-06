void  compile_node (ASTNode *node, SymbolTable *current_scope, int32_t * current_stack_offset)
{
    if (node != NULL)
    {
        switch (node->type)
        {
            case NODE_ASSIGN:
                const int8_t *var_name  = node -> data.assign.name;
                Symbol *sym             = scope_lookup (current_scope, var_name);

                // Generate the value assignment calculation
                compile_node (node -> data.assign.value, current_scope, current_stack_offset);
                if (sym && sym -> is_local)
                {
                    // It is a confirmed local variable; address it by frame stack offset
                    fprintf (stdout, "    MOV [BP + %d], R0 ; Assign local %s\n", sym -> stack_offset, var_name);
                }
                else
                {
                    // It is an implicit global; target a global memory block label
                    fprintf (stdout, "    MOV [global_%s], R0 ; Assign global\n", var_name);
                }
                break;

                case NODE_IDENTIFIER:
                const int8_t *var_name  = node -> data.identifier.name;
                Symbol *sym             = scope_lookup (current_scope, var_name);
                if (sym && sym -> is_local)
                {
                    fprintf (stdout, "    MOV R0, [BP + %d] ; Read local %s\n", sym->stack_offset, var_name);
                }
                else
                {
                    fprintf (stdout, "    MOV R0, [global_%s] ; Read global\n", var_name);
                }
                break;

            case NODE_WHILE:
                // A while loop introduces a new lexical block scope in Lua
                SymbolTable *loop_scope  = scope_enter (current_scope);

                // 1. Output loop start labels...
                // 2. Compile condition in the current scope context
                compile_node (node -> data.while_loop.condition, loop_scope, current_stack_offset);

                // 3. Compile loop body inside the loop's context
                compile_node (node -> data.while_loop.body, loop_scope, current_stack_offset);

                // Clean up and exit loop scope block
                current_scope = scope_exit (loop_scope);
                break;

            // Handle other node types...
            default:
                break;
        }
    }
}
