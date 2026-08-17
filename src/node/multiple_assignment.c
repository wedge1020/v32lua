#include "v32lua.h"

void node_multiple_assignment(ASTNode *node)
{
    ASTNode *curr_tgt             = node -> as.mult_assign.targets_head;
    ASTNode *curr_val             = node -> as.mult_assign.values_head;
    int      val_reg              = -1;

    // --- Intercept Bare Local Declarations ---
     if (node->as.mult_assign.is_local && node->as.mult_assign.values_head == NULL) {
        while (curr_tgt != NULL) {
            if (curr_tgt->type == NODE_IDENTIFIER) {
                SymbolNode *sym = register_local(curr_tgt->as.id.name);
                int temp_reg = allocate_register();
                emit_asm("MOV R%d, BOXED_NIL", temp_reg);
                emit_initialize_local(sym, temp_reg);
                unlock_register(temp_reg);
            }
            curr_tgt = curr_tgt->next;
        }
        return;
    }

    // =========================================================================
    // Check if RHS is a single function call that returns multiple values
    // =========================================================================
    if (curr_val != NULL && curr_val->next == NULL && curr_val->type == NODE_FUNCTION_CALL) {
        // Determine the return count STATICALLY. First check the builtin
        // table (math.modf/frexp/etc.), then -- if that comes back as the
        // default of 1 -- check whether it's a plain call to a
        // user-defined function we've already tracked a real return_count
        // for (see count_max_return_values() / mark_global_as_function()).
        // Only ONE of these should ever win; do not repeat the builtin
        // lookup after the user-defined check, or it silently overwrites
        // whatever the user-defined check found.
        char callee_path[256] = {0};
        int  return_count     = 1;

        if (resolve_static_path(curr_val->as.call.target, callee_path)) {
            return_count = get_builtin_return_count(callee_path);
        }

        if (return_count == 1 && curr_val->as.call.target->type == NODE_IDENTIFIER) {
            SymbolNode *callee_sym = resolve_symbol(curr_val->as.call.target->as.id.name);
            if (callee_sym != NULL && callee_sym->is_function && callee_sym->return_count > 1) {
                return_count = callee_sym->return_count;
            }
        }

        if (return_count > 1) {
            // This is a multi-return function call (e.g., math.modf, math.frexp,
            // or a user-defined function with more than one 'return' expression)
            generate_asm(curr_val, 0);  // dest_reg=0 means don't store to single reg

            // -----------------------------------------------------------------
            // Assign return values from R0, R2, R3, ... to targets, following
            // the SAME layout node_return() uses to produce them: value 0 in
            // R0, value 1 in R2, value 2 in R3 (R1 is never used for this).
            // Each value is copied into its OWN freshly allocated register
            // before being handed to emit_initialize_local()/
            // emit_store_variable() -- do not read from one register and
            // store from a different, uninitialized one.
            // -----------------------------------------------------------------
            int reg_index = 0;
            while (curr_tgt != NULL && reg_index < return_count) {
                if (curr_tgt->type == NODE_IDENTIFIER) {
                    int tmp_reg = allocate_register();

                    if (reg_index == 0) {
                        emit_asm("MOV R%d, R0 ; Read return value 0", tmp_reg);
                    } else if (reg_index == 1) {
                        emit_asm("MOV R%d, R2 ; Read return value 1", tmp_reg);
                    } else if (reg_index == 2) {
                        emit_asm("MOV R%d, R3 ; Read return value 2", tmp_reg);
                    } else {
                        // node_return() places value 3+ on the stack at
                        // [BP + 2 + arg_count + (index - 3)], relative to
                        // the CALLEE's own frame -- retrieving that correctly
                        // from here would need the callee's arg_count, which
                        // isn't available at this call site. Rather than
                        // guess and risk silently reading the wrong stack
                        // slot, fail loudly until this is deliberately
                        // implemented.
                        compiler_error(ERR_INTERNAL, -1,
                            "Multi-return assignment with more than 3 values is not yet supported");
                    }

                    if (node->as.mult_assign.is_local) {
                        SymbolNode *sym = register_local(curr_tgt->as.id.name);
                        emit_initialize_local(sym, tmp_reg);   // may allocate a box
                    } else {
                        emit_store_variable(curr_tgt->as.id.name, tmp_reg);   // writes through the box if boxed
                    }

                    unlock_register(tmp_reg);
                }

                curr_tgt = curr_tgt->next;
                reg_index++;
            }

            // -----------------------------------------------------------------
            // Pad remaining targets with NIL.
            // -----------------------------------------------------------------
            while (curr_tgt != NULL) {
                if (curr_tgt->type == NODE_IDENTIFIER) {
                    int temp_reg = allocate_register();
                    emit_asm("MOV R%d, BOXED_NIL ; Pad missing return value with Nil", temp_reg);

                    if (node->as.mult_assign.is_local) {
                        SymbolNode *sym = register_local(curr_tgt->as.id.name);
                        emit_initialize_local(sym, temp_reg);
                    } else {
                        emit_store_variable(curr_tgt->as.id.name, temp_reg);
                    }

                    unlock_register(temp_reg);
                }

                curr_tgt = curr_tgt->next;
            }

            return;  // Early exit - we handled all assignments
        }
    }

    // --- Standard & Multiple Assignment Evaluation ---
    while (curr_tgt != NULL)
    {
        if (curr_tgt->type == NODE_TABLE_GET && curr_val != NULL) {
            if (try_emit_table_set_intrinsic(curr_tgt->as.table_get.table_expr,
                                             curr_tgt->as.table_get.key,
                                             curr_val))
            {
                curr_tgt = curr_tgt->next;
                curr_val = curr_val->next;
                continue;
            }
        }

        val_reg = allocate_pinned_register();
        mark_register_live(val_reg, 1);

        if (curr_val != NULL) {
            generate_asm(curr_val, val_reg);
            curr_val = curr_val->next;
        } else {
            emit_asm("MOV R%d, BOXED_NIL ; Pad missing value with Nil", val_reg);
        }

        ensure_in_register(val_reg);

        if (curr_tgt->type == NODE_IDENTIFIER) {
            if (node->as.mult_assign.is_local) {
                SymbolNode *sym = register_local(curr_tgt->as.id.name);

                if (g_verbose_debug) {
                    fprintf(stderr, "[debug] node_multiple_assignment() Declaring local: %s (val_reg=R%d, boxed=%d)\n",
                            curr_tgt->as.id.name, val_reg, sym->is_boxed);
                }

                emit_initialize_local(sym, val_reg);
            } else {
                if (g_verbose_debug) {
                    fprintf(stderr, "[debug] node_multiple_assignment() Assigning: %s (val_reg=R%d)\n",
                            curr_tgt->as.id.name, val_reg);
                }

                emit_store_variable(curr_tgt->as.id.name, val_reg);
            }
        }
        else if (curr_tgt->type == NODE_TABLE_GET)
        {
            int table_reg = allocate_pinned_register();
            int key_reg   = allocate_pinned_register();

            generate_asm(curr_tgt->as.table_get.table_expr, table_reg);
            generate_asm(curr_tgt->as.table_get.key, key_reg);

            emit_asm("PUSH R%d ; Push Table Pointer", table_reg);
            emit_asm("PUSH R%d ; Push Key", key_reg);
            emit_asm("PUSH R%d ; Push Value", val_reg);
            emit_asm("CALL __builtin_table_set");
            emit_asm("IADD SP, 3 ; Clean up stack");

            unlock_pinned_register(table_reg);
            unlock_pinned_register(key_reg);
        }

        unlock_pinned_register(val_reg);
        curr_tgt = curr_tgt->next;
    }
}
