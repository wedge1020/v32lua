// =====================================================================
// Replace your generate_asm, generate_global_setup, and generate_program 
// functions in generator.c with the code below!
// =====================================================================

void generate_asm(ASTNode *node, int dest_reg) {
    if (node == NULL) return;

    switch (node->type) {
        case NODE_WHILE: {
            int label_id = get_next_label();
            const char *ctx = get_current_function_name();
            push_loop(label_id);
            emit_asm("__%s_while_start_%d:\n", ctx, label_id);
            
            int cond_reg = allocate_register();
            generate_asm(node->as.while_loop.condition, cond_reg);
            
            emit_asm("JF R%d, __%s_while_end_%d\n", cond_reg, ctx, label_id);
            unlock_register(cond_reg);
            
            // NEW: Push a local scope for the while loop block!
            push_scope(); 
            generate_block(node->as.while_loop.body);
            pop_scope();
            
            emit_asm("JMP __%s_while_start_%d\n", ctx, label_id);
            emit_asm("__%s_while_end_%d:\n", ctx, label_id);
            pop_loop();
            break;
        }

        case NODE_BREAK: {
            int current_id = current_loop();
            if (current_id == -1) {
                fprintf(stderr, "Compiler Runtime Error: 'break' declaration found outside loop.\n");
                exit(1);
            }
            emit_asm("JMP __%s_while_end_%d\n", get_current_function_name(), current_id);
            break;
        }

        case NODE_IF: {
            int label_id = get_next_label();
            const char *ctx = get_current_function_name();
            
            int cond_reg = allocate_register();
            generate_asm(node->as.if_stmt.condition, cond_reg);
            
            emit_asm("JF R%d, __%s_else_%d\n", cond_reg, ctx, label_id);
            unlock_register(cond_reg);
            
            // NEW: Push local scope for IF body
            push_scope();
            generate_block(node->as.if_stmt.if_body);
            pop_scope();
            
            emit_asm("JMP __%s_end_if_%d\n", ctx, label_id);
            emit_asm("__%s_else_%d:\n", ctx, label_id);
            
            if (node->as.if_stmt.else_body) {
                // NEW: Push local scope for ELSE body
                push_scope();
                generate_block(node->as.if_stmt.else_body);
                pop_scope();
            }
            emit_asm("__%s_end_if_%d:\n", ctx, label_id);
            break;
        }

        case NODE_FUNCTION_DEF: {
            const char *func_name = node->as.function_def.name;
            push_function_context(func_name);

            // Emit function prologue
            emit_asm("__function_%s:\n", func_name);
            int needs_stack = check_needs_stack(node->as.function_def.body);
            if (needs_stack) {
                emit_asm("PUSH BP\n");
                emit_asm("MOV BP, SP\n");
            } else {
                emit_asm("    ;; --- Frame pointer omitted (Leaf Function Optimization) ---\n");
            }

            // NEW: Push a new scope for the function body!
            push_scope();

            // NEW: Register function parameters into the local scope as [BP + 2], [BP + 3]
            int param_offset = 2; 
            ASTNode *p = node->as.function_def.params;
            while (p != NULL) {
                if (p->type == NODE_IDENTIFIER) {
                    register_parameter(p->as.id.name, param_offset++);
                }
                p = p->next;
            }

            generate_block(node->as.function_def.body);
            pop_scope(); // Exit function scope

            // Emit function epilogue
            emit_asm("__%s_return:\n", func_name);
            if (needs_stack) {
                emit_asm("MOV SP, BP\n");
                emit_asm("POP BP\n");
            }
            emit_asm("    RET\n");

            pop_function_context();
            break;
        }

        case NODE_MULTIPLE_ASSIGNMENT: {
            ASTNode* curr_tgt = node->as.mult_assign.targets_head;
            ASTNode* curr_val = node->as.mult_assign.values_head;

            while (curr_tgt != NULL && curr_val != NULL) {
                int val_reg = allocate_register();
                generate_asm(curr_val, val_reg);

                if (curr_tgt->type == NODE_IDENTIFIER) {
                    // NEW: If this is a `local` assignment, register it in the current scope!
                    if (node->as.mult_assign.is_local) {
                        register_local(curr_tgt->as.id.name);
                    }
                    
                    // Retrieve the correct assembly access string ([var_x] vs [BP - 1])
                    char var_access[256];
                    get_variable_access_string(curr_tgt->as.id.name, var_access);
                    emit_asm("MOV %s, R%d\n", var_access, val_reg);
                }
                
                unlock_register(val_reg);
                curr_tgt = curr_tgt->next;
                curr_val = curr_val->next;
            }
            break;
        }

        case NODE_IDENTIFIER: {
            // NEW: Dynamically lookup identifier location
            char var_access[256];
            get_variable_access_string(node->as.id.name, var_access);
            emit_asm("MOV R%d, %s\n", dest_reg, var_access);
            break;
        }

        // ... [The rest of your AST nodes (NODE_NUMBER, NODE_ADD, NODE_FUNCTION_CALL) 
        // remain completely unchanged!] ...
    }
}

void generate_global_setup(ASTNode* node) {
    if (node == NULL) return;
    
    if (node->type == NODE_FUNCTION_DEF) {
        // Register the function name in the global scope explicitly
        mark_global_as_function(node->as.function_def.name);
        
        emit_asm("    ;; Load address of the mangled function\n");
        emit_asm("    MOV   R1, __function_%s\n", node->as.function_def.name);
        
        // Dynamically get its global access string
        char var_access[256];
        get_variable_access_string(node->as.function_def.name, var_access);
        emit_asm("    MOV   %s, R1\n", var_access);
    }
    
    generate_global_setup(node->next);
}

void generate_program(ASTNode* head) {
    // =========================================================================
    // CRITICAL NEW ADDITION: Initialize the global scope before compiling!
    init_global_scope(); 
    // =========================================================================

    // 1. Temporary output routing
    current_out_stream = tmpfile();
    if (!current_out_stream) {
        fprintf(stderr, "Compiler Error: Failed to create temporary file for code generation.\n");
        exit(1);
    }
    
    emit_asm(";; --- Compiled Code Entry Vector ---\n");
    emit_asm("    CALL  __init_globals                 ; Run top-level setups first\n");
    emit_asm("    CALL  __function_main                ; Then hand control to the user\n");
    emit_asm("    HLT                                  ; Halt CPU when main finishes\n\n");

    emit_asm(";; --- Function Definitions ---\n");
    ASTNode* current = head;
    while (current != NULL) {
        if (current->type == NODE_FUNCTION_DEF) {
            generate_asm(current, 0);
        }
        current = current->next;
    }

    int has_globals = 0;
    int globals_need_stack = 0;
    current = head;
    while (current != NULL) {
        if (current->type != NODE_FUNCTION_DEF) {
            has_globals = 1;
            if (check_needs_stack(current)) globals_need_stack = 1;
        }
        current = current->next;
    }
    
    emit_asm("\n;; --- Global Initialization Vector ---\n");
    emit_asm("__init_globals:\n");
    
    if (globals_need_stack) {
        emit_asm("PUSH BP\n");
        emit_asm("MOV BP, SP\n");
    } else {
        emit_asm("    ;; --- Frame pointer omitted (Leaf Function Optimization) ---\n");
    }

    generate_global_setup(head);

    current = head;
    while (current != NULL) {
        if (current->type != NODE_FUNCTION_DEF) {
            int temp_reg = allocate_register();
            generate_asm(current, temp_reg);
            unlock_register(temp_reg);
        }
        current = current->next;
    }

    if (globals_need_stack) {
        emit_asm("MOV SP, BP\n");
        emit_asm("POP BP\n");
    }
    emit_asm("RET\n\n");

    fprintf(stdout, ";; --- System Constants ---\n");
    fprintf(stdout, "%%define heap_pointer 0\n");

    fprintf(stdout, "\n;; --- Global Variable RAM Map ---\n");
    emit_variable_map();
    fprintf(stdout, "\n");

    rewind(current_out_stream);
    char buffer[1024];
    while (fgets(buffer, sizeof(buffer), current_out_stream) != NULL) {
        fputs(buffer, stdout);
    }
    fclose(current_out_stream);
    current_out_stream = NULL;

    emit_runtime_library();
    emit_string_data_section();
}
