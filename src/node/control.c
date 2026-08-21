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

            // Tail-forward ALL of the callee's return values, not just the
            // first 3 (previously clamped here with "if (ret_idx > 3)
            // ret_idx = 3"). The callee's own node_return() already left
            // values 4+ sitting in the shared __extra_ret_N global slots --
            // since nothing runs between that CALL and this function's own
            // immediate return, those slots are still exactly as the
            // callee left them, so there's nothing further to copy.
            ret_idx = callee_sym->return_count;
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
            // 4th and later return values: write into the shared "extra
            // return slot" globals instead of a fixed register -- see
            // get_extra_return_slot_access() for the full rationale.
            char slot_access[128];
            get_extra_return_slot_access(ret_idx - 3, slot_access);
            emit_asm ("MOV %s, R%d ; extra return value %d\n", slot_access, val_reg, ret_idx);
        }

        if (target_raw_reg != -1) {
            // Lock the raw register so a LATER return expression in this
            // same statement can't get it handed back out as scratch.
            lock_register(target_raw_reg);
        }

        // Only unlock val_reg here if it is NOT the very raw register we
        // just locked above -- see the original comment block this
        // preserves: val_reg == target_raw_reg is a normal, expected
        // outcome, and unconditionally unlocking here would cancel the
        // lock_register() call one statement early.
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
    // (No 3-cap here anymore -- max_returns can legitimately be > 3 now.)

    // -----------------------------------------------------------------
    // Pad any return slot THIS return statement didn't populate, because
    // a DIFFERENT 'return' elsewhere in the same function returns more
    // values (see count_max_return_values()). R0/R2/R3 padding is
    // unchanged; slots 4+ are padded through the same shared globals
    // used above.
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
