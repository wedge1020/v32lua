#include "v32lua.h"

// Special-cased multi-assignment RHS: table.unpack(t, [i], [j]).
// target_count is known at COMPILE TIME (the literal number of LHS
// names), so this unrolls into target_count straight-line fetch blocks
// rather than needing a runtime loop or the generic multi-return
// register/global protocol.
static void emit_multiple_assignment_table_unpack(ASTNode *targets_head, ASTNode *call_node, bool is_local)
{
    int target_count = 0;

    for (ASTNode *t = targets_head; t != NULL; t = t->next) target_count++;

    emit_asm("    ;; --- table.unpack(t, [i], [j]) as multi-assignment RHS (%d targets) ---\n", target_count);

    char t_name[48], i_name[48], j_name[48];
    emit_table_unpack_resolve_bounds(call_node, t_name, i_name, j_name, sizeof(t_name));

    ASTNode *curr_tgt = targets_head;
    for (int k = 0; k < target_count && curr_tgt != NULL; k++, curr_tgt = curr_tgt->next) {
        int val_reg = allocate_register();
        emit_table_unpack_fetch_element(t_name, i_name, j_name, k, val_reg);

        if (curr_tgt->type == NODE_IDENTIFIER) {
            if (is_local) {
                SymbolNode *sym = register_local(curr_tgt->as.id.name);
                emit_initialize_local(sym, val_reg);
            } else {
                emit_store_variable(curr_tgt->as.id.name, val_reg);
            }
        }
        unlock_register(val_reg);
    }
}

void node_multiple_assignment(ASTNode *node)
{
    ASTNode *curr_tgt             = node -> as.mult_assign.targets_head;
    ASTNode *curr_val             = node -> as.mult_assign.values_head;
    int      val_reg              = -1;

    // "play = music.play" has no runtime value to store.
    if (is_intrinsic_alias_assignment(node)) {
        return;
    }

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

    // --- Special case: table.unpack(t, [i], [j]) as a multi-assignment ---
    // --- RHS -- see emit_multiple_assignment_table_unpack() for why this ---
    // --- can't go through the generic multi-return path below. ---
    if (curr_val != NULL && curr_val->next == NULL &&
        is_table_unpack_call(curr_val))
    {
        emit_multiple_assignment_table_unpack(curr_tgt, curr_val, node->as.mult_assign.is_local);
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
            // PASS 1: Copy ALL raw return values out of their source location
            // (fixed registers R0/R2/R3 for values 1-3, the shared
            // __extra_ret_N globals for value 4 onward -- see
            // get_extra_return_slot_access()) into freshly allocated,
            // protected temp registers FIRST, as one uninterrupted block,
            // before touching any target's storage.
            //
            // Lock the raw return-value REGISTERS themselves (R0/R2/R3, up
            // to 3 of them) BEFORE allocating any tmp_reg. Without this,
            // allocate_register() could hand back R2 (or R3) as the
            // tmp_reg for return value 0, clobbering it before return
            // value 1 is ever read out of it. Locking R0/R2/R3 up front
            // makes them ineligible for that allocation entirely, so every
            // tmp_reg is guaranteed to land somewhere else until all
            // register-sourced raw values are safely copied out. Values
            // from the extra-return globals don't need this protection --
            // they live in memory, not in the register file, so they can't
            // be clobbered by allocate_register() picking a temp register.
            //
            // extract_count is no longer clamped/rejected at 3 -- values
            // beyond the 3rd just come from a different source. If
            // extract_count somehow exceeds the compiler's supported
            // maximum (3 + MAX_EXTRA_RETURN_SLOTS), get_extra_return_slot_
            // access() below raises a clear compiler_error at the exact
            // offending slot rather than silently truncating results.
            // -----------------------------------------------------------------
            int extract_count = return_count;

            int raw_regs[3] = {0, 2, 3}; // physical registers node_return() places values 1-3 in
            int reg_source_count = (extract_count < 3) ? extract_count : 3;

            for (int i = 0; i < reg_source_count; i++) {
                lock_register(raw_regs[i]);
            }

            int *tmp_regs = (int *) malloc(sizeof(int) * extract_count);
            if (tmp_regs == NULL) {
                compiler_error(ERR_INTERNAL, -1, "Out of memory extracting multi-return values");
            }

            for (int i = 0; i < extract_count; i++) {
                tmp_regs[i] = allocate_register();
                mark_register_live(tmp_regs[i], extract_count + 2); // survive the whole copy+store pass

                if (i < 3) {
                    emit_asm("MOV R%d, R%d ; Read return value %d", tmp_regs[i], raw_regs[i], i);
                } else {
                    char slot_access[128];
                    get_extra_return_slot_access(i - 3, slot_access);
                    emit_asm("MOV R%d, %s ; Read return value %d", tmp_regs[i], slot_access, i);
                }
            }

            // Raw registers are now fully copied out -- safe to release.
            for (int i = 0; i < reg_source_count; i++) {
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

            free(tmp_regs);

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
    //
    // FIX: values must ALL be evaluated BEFORE any target is written, or a
    // swap idiom like `a, b = b, a` breaks. The old version evaluated and
    // immediately stored one target/value pair at a time -- so by the time
    // the SECOND value expression (reading 'a') was evaluated, the FIRST
    // target ('a') had already been overwritten with 'b's original value.
    // That's exactly the bug: `sa, sb = sb, sa` produced sa=2 (correct)
    // then sb=2 (wrong -- should be 1, sa's ORIGINAL value).
    //
    // This mirrors the same evaluate-everything-first discipline the
    // multi-return-call branch above already uses for the identical class
    // of hazard. PASS 1 evaluates every value and pushes it to the stack;
    // PASS 2 (after every value is safely evaluated, before any target is
    // touched) pops them back off in reverse and performs the actual
    // assignments/table-sets.
    //
    // NOTE: this bypasses the try_emit_table_set_intrinsic() fast path
    // that used to run per-pair for NODE_TABLE_GET targets -- table-set
    // targets now always go through the general __builtin_table_set CALL
    // in Pass 2 instead. That's a correctness-over-micro-optimization
    // trade-off; flagging it in case that intrinsic mattered for perf and
    // you want to fold it back into Pass 2's NODE_TABLE_GET branch later.
    {
        ASTNode *targets_arr[64];
        int      n = 0;
        ASTNode *t = curr_tgt;
        while (t != NULL) {
            if (n >= 64) {
                compiler_error(ERR_INTERNAL, -1,
                    "Multiple assignment exceeds 64-target internal limit");
            }
            targets_arr[n++] = t;
            t = t->next;
        }

        // PASS 1: evaluate every RHS value (nil-padding missing ones) and
        // push it to the stack immediately, in target order, BEFORE any
        // target is written.
        ASTNode *scan_val = curr_val;
        for (int i = 0; i < n; i++) {
            int tmp_reg = allocate_pinned_register();
            mark_register_live(tmp_reg, 1);

            if (scan_val != NULL) {
                generate_asm(scan_val, tmp_reg);
                scan_val = scan_val->next;
            } else {
                emit_asm("MOV R%d, BOXED_NIL ; Pad missing value with Nil", tmp_reg);
            }

            ensure_in_register(tmp_reg);
            emit_asm("PUSH R%d ; Pass 1: hold evaluated RHS value #%d until all targets are known", tmp_reg, i);
            unlock_pinned_register(tmp_reg);
        }

        // PASS 2: pop values back off in REVERSE (stack is LIFO, so the
        // LAST value pushed -- the last target's -- comes off first) and
        // perform the actual assignments.
        for (int i = n - 1; i >= 0; i--) {
            ASTNode *tgt = targets_arr[i];

            val_reg = allocate_pinned_register();
            mark_register_live(val_reg, 1);
            emit_asm("POP R%d ; Pass 2: retrieve evaluated RHS value for target #%d", val_reg, i);

            if (tgt->type == NODE_IDENTIFIER) {
                if (node->as.mult_assign.is_local) {
                    SymbolNode *sym = register_local(tgt->as.id.name);

                    if (g_verbose_debug) {
                        fprintf(stderr, "[debug] node_multiple_assignment() Declaring local: %s (val_reg=R%d, boxed=%d)\n",
                                tgt->as.id.name, val_reg, sym->is_boxed);
                    }

                    emit_initialize_local(sym, val_reg);
                } else {
                    if (g_verbose_debug) {
                        fprintf(stderr, "[debug] node_multiple_assignment() Assigning: %s (val_reg=R%d)\n",
                                tgt->as.id.name, val_reg);
                    }

                    emit_store_variable(tgt->as.id.name, val_reg);
                }
            }
            else if (tgt->type == NODE_TABLE_GET)
            {
                int table_reg = allocate_pinned_register();
                int key_reg   = allocate_pinned_register();

                generate_asm(tgt->as.table_get.table_expr, table_reg);
                generate_asm(tgt->as.table_get.key, key_reg);

                emit_asm("PUSH R%d ; Push Table Pointer", table_reg);
                emit_asm("PUSH R%d ; Push Key", key_reg);
                emit_asm("PUSH R%d ; Push Value", val_reg);
                emit_asm("CALL __builtin_table_set");
                emit_asm("IADD SP, 3 ; Clean up stack");

                unlock_pinned_register(table_reg);
                unlock_pinned_register(key_reg);
            }

            unlock_pinned_register(val_reg);
        }
    }
}
