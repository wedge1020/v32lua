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

    int raw_reg_used[3] = {0, 0, 0}; // index 0->R0, 1->R2, 2->R3

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
            ret_idx = callee_sym->return_count;
            if (ret_idx > 3) ret_idx = 3;
            expr = NULL;
        }
    }

    while (expr != NULL) {
        int val_reg = allocate_register();
        generate_asm (expr, val_reg);

        // -------------------------------------------------------------
        // Which fixed raw register (if any) does THIS return value land
        // in? Tracked explicitly so we can correctly decide below whether
        // it's safe to unlock val_reg.
        // -------------------------------------------------------------
        int target_raw_reg = -1;

        if (ret_idx == 0)      { emit_asm ("MOV R0, R%d\n", val_reg); target_raw_reg = 0; raw_reg_used[0] = 1; }
        else if (ret_idx == 1) { emit_asm ("MOV R2, R%d\n", val_reg); target_raw_reg = 2; raw_reg_used[1] = 1; }
        else if (ret_idx == 2) { emit_asm ("MOV R3, R%d\n", val_reg); target_raw_reg = 3; raw_reg_used[2] = 1; }
        else {
            int offset = 2 + arg_count + (ret_idx - 3);
            emit_asm ("MOV [BP + %d], R%d\n", offset, val_reg);
        }

        if (target_raw_reg != -1) {
            // Lock the raw register so a LATER return expression in this
            // same statement can't get it handed back out as scratch
            // (the original clobbered-register bug this whole block
            // exists to prevent).
            lock_register(target_raw_reg);
        }

        // -------------------------------------------------------------
        // FIX: only unlock val_reg here if it is NOT the very raw
        // register we just locked above. allocate_register() is free to
        // hand back R0/R2/R3 as val_reg for any expression -- nothing
        // pins them away from it -- so val_reg == target_raw_reg is a
        // normal, expected outcome (visible directly in the generated
        // asm as a redundant "MOV R2, R2"). lock_register() and
        // unlock_register() both operate on the SAME per-register-number
        // state; unconditionally unlocking val_reg here immediately
        // cancelled the lock_register() call above whenever they
        // coincided, leaving R0/R2/R3 unprotected again one statement
        // early. The very next return-expression's allocate_register()
        // call would then happily hand that "free" register straight
        // back out as ITS OWN scratch space, overwriting the value that
        // was supposed to be safely parked there for the return -- e.g.
        // `return lo, hi, a + b + c` computing `a + b + c` directly on
        // top of the register still holding `hi`.
        //
        // When they DO coincide, the post-loop unlock block below (which
        // runs once every expression in this return statement has been
        // evaluated) is what correctly releases it instead.
        // -------------------------------------------------------------
        if (val_reg != target_raw_reg) {
            unlock_register(val_reg);
        }

        ret_idx++;
        expr = expr -> next;
    }

    if (raw_reg_used[0]) unlock_register(0);
    if (raw_reg_used[1]) unlock_register(2);
    if (raw_reg_used[2]) unlock_register(3);

    SymbolNode *fn_sym      = resolve_symbol (get_current_function_name ());
    int         max_returns = (fn_sym != NULL) ? fn_sym -> return_count : ret_idx;
    if (max_returns > 3) max_returns = 3;

    if (ret_idx < max_returns) {
        if (ret_idx <= 0 && max_returns >= 1) emit_asm ("MOV R0, BOXED_NIL ; pad unused return slot\n");
        if (ret_idx <= 1 && max_returns >= 2) emit_asm ("MOV R2, BOXED_NIL ; pad unused return slot\n");
        if (ret_idx <= 2 && max_returns >= 3) emit_asm ("MOV R3, BOXED_NIL ; pad unused return slot\n");
    }

    emit_asm ("JMP __%s_return\n", get_current_function_name ());
}
