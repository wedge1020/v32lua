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
    // node_while/node_repeat/node_for_numeric/node_for_generic) -- these
    // tags are NOT interchangeable prefixes. A missing case here silently
    // falls through to the default and jumps to a label that loop type
    // never actually defines -- an unresolved-label error at assembly
    // time (this already happened once for LOOP_TYPE_FOR_GENERIC before
    // it got its own explicit case; LOOP_TYPE_REPEAT gets the same
    // explicit treatment here rather than risking silently falling into
    // the "while" default).
    LoopType    type = current_loop_type ();
    const char *tag;
    switch (type) {
        case LOOP_TYPE_FOR_NUMERIC: tag = "for";     break;
        case LOOP_TYPE_FOR_GENERIC: tag = "for_gen"; break;
        case LOOP_TYPE_REPEAT:      tag = "repeat";  break;
        case LOOP_TYPE_WHILE:
        default:                    tag = "while";   break;
    }
    emit_asm ("JMP __%s_%s_end_%d\n", get_current_function_name (), tag, current_id);
}

void  node_return (ASTNode *node)
{
    ASTNode *expr = node -> as.return_stmt.expressions_head;
    int ret_idx = 0;

    if (expr != NULL && expr->next == NULL && expr->type == NODE_FUNCTION_CALL) {
        ASTNode    *call_target = expr->as.call.target;
        SymbolNode *callee_sym  = NULL;

        if (call_target->type == NODE_IDENTIFIER) {
            callee_sym = resolve_symbol(call_target->as.id.name);
        } else {
            char path_buf[256] = {0};
            if (resolve_static_path(call_target, path_buf)) {
                callee_sym = resolve_symbol(path_buf);
                if (callee_sym == NULL) {
                    for (int i = 0; path_buf[i] != '\0'; i++) {
                        if (path_buf[i] == '.' || path_buf[i] == ':') path_buf[i] = '_';
                    }
                    callee_sym = resolve_symbol(path_buf);
                }
            }
        }

        if (callee_sym != NULL && callee_sym->is_function && callee_sym->return_count > 1) {
            generate_asm(expr, 0);

            // Tail-forward ALL of the callee's return values -- see the
            // long-standing comment this preserves: the callee's own
            // node_return() already left values 4+ in the shared
            // __extra_ret_N globals, and nothing runs between that CALL
            // and this function's own immediate return, so there's
            // nothing further to copy. This path never touches
            // R0/R2/R3 itself, so it isn't subject to the hazard fixed
            // below -- the callee's own return already established them
            // correctly and this function just passes them through.
            ret_idx = callee_sym->return_count;
            expr = NULL;
        }
    }

    // -----------------------------------------------------------------
    // FIX: return values destined for R0/R2/R3 (ret_idx 0/1/2) are
    // computed and IMMEDIATELY SPILLED to the hardware stack -- NOT
    // moved into R0/R2/R3 right away. They're only popped into their
    // real destination register in one final pass, after every return
    // expression has been fully evaluated.
    //
    // Why: `return i, t[i], t[i] * 2` computes three expressions, and
    // the 2nd and 3rd both contain their own nested CALL (a table
    // lookup). Runtime routines like __builtin_table_get return their
    // result in R0 and use R0-R8 freely as scratch -- they have no
    // concept of the compiler considering R0 "already holding this
    // statement's first return value." The previous approach --
    // lock_register(target_raw_reg) right after moving a value into
    // R0/R2/R3 -- only stops the COMPILER's own allocator from handing
    // that register out again; it does nothing to stop a raw hardware
    // CALL from clobbering it. The 2nd return value's table lookup
    // silently destroyed the 1st return value already sitting in R0,
    // and nothing ever re-established it before the final RET -- so a
    // 3-value return where later values contain nested calls handed
    // back a corrupted FIRST value while the later ones stayed correct.
    //
    // Values beyond the 3rd don't need this treatment: they're written
    // straight to their dedicated __extra_ret_N global, which is
    // memory, not a shared scratch register, and so isn't at risk from
    // a later expression's CALL the same way.
    // -----------------------------------------------------------------
    int push_order[3];   // which raw slot (0->R0, 1->R2, 2->R3), in push order
    int push_count = 0;

    while (expr != NULL) {
        int val_reg = allocate_register();
        generate_asm (expr, val_reg);
        ensure_in_register (val_reg);

        if (ret_idx < 3) {
            emit_asm ("PUSH R%d ; spill return value %d (protect across later nested CALLs)\n", val_reg, ret_idx);
            push_order[push_count++] = ret_idx;
        } else {
            // 4th and later return values: write straight into the
            // shared "extra return slot" global -- memory, not a
            // register, so no spill/reload protection needed here.
            char slot_access[128];
            get_extra_return_slot_access(ret_idx - 3, slot_access);
            emit_asm ("MOV %s, R%d ; extra return value %d\n", slot_access, val_reg, ret_idx);
        }

        unlock_register(val_reg);

        ret_idx++;
        expr = expr -> next;
    }

    // Pop in REVERSE (LIFO) order, straight into each value's real
    // destination register -- the register name IS the destination,
    // no intermediate MOV needed.
    for (int k = push_count - 1; k >= 0; k--) {
        int slot = push_order[k];
        const char *raw_reg = (slot == 0) ? "R0" : (slot == 1) ? "R2" : "R3";
        emit_asm ("POP %s ; restore return value %d\n", raw_reg, slot);
    }

    SymbolNode *fn_sym      = resolve_symbol (get_current_function_name ());
    int         max_returns = (fn_sym != NULL) ? fn_sym -> return_count : ret_idx;
    // (No 3-cap here anymore -- max_returns can legitimately be > 3.)

    // -----------------------------------------------------------------
    // Pad any return slot THIS return statement didn't populate, because
    // a DIFFERENT 'return' elsewhere in the same function returns more
    // values (see count_max_return_values()). Unchanged from before --
    // this only ever touches slots >= ret_idx, which by definition
    // weren't part of the pop sequence above, so there's no ordering
    // conflict with it.
    // -----------------------------------------------------------------
    if (ret_idx < max_returns) {
        if (ret_idx <= 0 && max_returns >= 1) emit_asm ("MOV R0, BOXED_NIL ; pad unused return slot\n");
        if (ret_idx <= 1 && max_returns >= 2) emit_asm ("MOV R2, BOXED_NIL ; pad unused return slot\n");
        if (ret_idx <= 2 && max_returns >= 3) emit_asm ("MOV R3, BOXED_NIL ; pad unused return slot\n");

        if (max_returns > 3) {
            int pad_reg = allocate_register();
            emit_asm ("MOV R%d, BOXED_NIL ; nil value for padding extra return slots\n", pad_reg);

            int start = (ret_idx > 3) ? ret_idx : 3;
            for (int idx = start; idx < max_returns; idx++) {
                char slot_access[128];
                get_extra_return_slot_access(idx - 3, slot_access);
                emit_asm ("MOV %s, R%d ; pad unused return slot %d\n", slot_access, pad_reg, idx);
            }

            unlock_register(pad_reg);
        }
    }

    emit_asm ("JMP __%s_return\n", get_current_function_name ());
}
