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
        // default of 1 -- check whether it's a call to a user-defined
        // function we've already tracked a real return_count for (see
        // count_max_return_values() / mark_global_as_function()).
        char callee_path[256] = {0};
        int  return_count     = 1;

        if (resolve_static_path(curr_val->as.call.target, callee_path)) {
            return_count = get_builtin_return_count(callee_path);
        }

        // -----------------------------------------------------------------
        // FIX: resolve the callee symbol for BOTH plain identifier calls
        // (foo()) AND method/dotted calls (obj:foo() / obj.foo()).
        //
        // Method and dotted calls always desugar their call target into a
        // NODE_TABLE_GET (table_expr + string key) -- never a bare
        // NODE_IDENTIFIER -- regardless of whether the source used '.' or
        // ':'. The old check here only looked up the callee's symbol when
        // curr_val->as.call.target->type == NODE_IDENTIFIER, which is
        // NEVER true for a method call. That meant return_count silently
        // stayed at its default of 1 for every method/dotted call, so the
        // Pass-1/Pass-2 multi-value extraction below never ran: only R0
        // (the first return value) was ever captured, and every additional
        // assignment target got nil-padded instead of reading R2/R3 --
        // e.g. `local min, max = obj:min_max(5)` always left `max` as nil.
        //
        // resolve_static_path() already flattened the call target into a
        // dotted path (e.g. "obj.min_max") above. Try that directly first
        // (covers plain identifiers too, and any oddball global registered
        // with a literal dot in its name), then fall back to the mangled
        // underscore form that mangle_method_name() / the colon-method
        // parser rules actually register table:method()/table.method()
        // definitions under (e.g. "obj_min_max").
        // -----------------------------------------------------------------
        if (return_count == 1) {
            SymbolNode *callee_sym = NULL;

            if (curr_val->as.call.target->type == NODE_IDENTIFIER) {
                callee_sym = resolve_symbol(curr_val->as.call.target->as.id.name);
            } else if (callee_path[0] != '\0') {
                callee_sym = resolve_symbol(callee_path);

                if (callee_sym == NULL) {
                    char mangled_buf[256];
                    strncpy(mangled_buf, callee_path, sizeof(mangled_buf) - 1);
                    mangled_buf[sizeof(mangled_buf) - 1] = '\0';

                    for (int i = 0; mangled_buf[i] != '\0'; i++) {
                        if (mangled_buf[i] == '.' || mangled_buf[i] == ':') {
                            mangled_buf[i] = '_';
                        }
                    }

                    callee_sym = resolve_symbol(mangled_buf);
                }
            }

            if (callee_sym != NULL && callee_sym->is_function && callee_sym->return_count > 1) {
                return_count = callee_sym->return_count;
            }
        }

        if (return_count > 1) {
            // This is a multi-return function call (e.g., math.modf, math.frexp,
            // or a user-defined function -- including a method -- with more
            // than one 'return' expression)
            generate_asm(curr_val, 0);  // dest_reg=0 means don't store to single reg

            // -----------------------------------------------------------------
            // PASS 1: Copy ALL raw return values (R0, R2, R3) out of their
            // fixed registers into freshly allocated, protected temp
            // registers FIRST, as one uninterrupted block, before touching
            // any target's storage.
            //
            // Lock the raw return-value registers themselves BEFORE
            // allocating any tmp_reg. Without this, allocate_register()
            // could hand back R2 (or R3) as the tmp_reg for return value 0,
            // clobbering it before return value 1 is ever read out of it --
            // the same hazard as before, just one level further in. Locking
            // R0/R2/R3 up front makes them ineligible for that allocation
            // entirely, so every tmp_reg is guaranteed to land somewhere
            // else until all raw values are safely copied out.
            // -----------------------------------------------------------------
            int extract_count = return_count;
            if (extract_count > 3) {
                compiler_error(ERR_INTERNAL, -1,
                    "Multi-return assignment with more than 3 values is not yet supported");
                extract_count = 3; // keep going defensively after reporting
            }

            int raw_regs[3] = {0, 2, 3}; // physical registers node_return() places values in

            for (int i = 0; i < extract_count; i++) {
                lock_register(raw_regs[i]);
            }

            int tmp_regs[3];
            for (int i = 0; i < extract_count; i++) {
                tmp_regs[i] = allocate_register();
                mark_register_live(tmp_regs[i], extract_count + 2); // survive the whole copy+store pass

                emit_asm("MOV R%d, R%d ; Read return value %d", tmp_regs[i], raw_regs[i], i);
            }

            // Raw registers are now fully copied out -- safe to release.
            for (int i = 0; i < extract_count; i++) {
                unlock_register(raw_regs[i]);
            }

            // -----------------------------------------------------------------
            // PASS 2: Every return value is now safely parked in its own
            // protected register, in order. Storing can no longer clobber a
            // still-pending return value -- there isn't one anymore.
            // -----------------------------------------------------------------
            int reg_index = 0;
            while (curr_tgt != NULL && reg_index < extract_count) {
                if (curr_tgt->type == NODE_IDENTIFIER) {
                    int tmp_reg = tmp_regs[reg_index];

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

            // Unlock any extracted values that had no matching target
            // (more return values than targets on the LHS).
            for (int i = reg_index; i < extract_count; i++) {
                unlock_register(tmp_regs[i]);
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
