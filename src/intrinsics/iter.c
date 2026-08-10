#include "v32lua.h"

bool emit_pairs_intrinsic(ASTNode *node) {
    // pairs(t) returns: next, t, nil
    // next is the table iteration function
    // t is the table itself
    // nil is the starting key

    ASTNode *arg = node->as.call.args_head;
    if (!arg) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "pairs() requires 1 argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: pairs(t) ---\n");

    // Evaluate table argument
    int table_reg = allocate_pinned_register();
    generate_asm(arg, table_reg);

    // Push table for next() call
    emit_asm("PUSH R%d             ; Table argument for next()\n", table_reg);

    // Return: next function, table, nil
    // We'll use the built-in __builtin_next as the iterator
    emit_asm("MOV R0, __builtin_next ; Iterator function\n");
    emit_asm("OR R0, BOXED_FUNCTION  ; Box as function\n");

    // Store table in a temporary location
    // For now, we return it on the stack
    emit_asm("PUSH R%d             ; Table (state for next)\n", table_reg);
    emit_asm("PUSH R0             ; nil (starting key)\n");
    emit_asm("MOV R0, BOXED_NIL\n");
    emit_asm("PUSH R0\n");

    unlock_pinned_register(table_reg);
    return true;
}

bool emit_ipairs_intrinsic(ASTNode *node) {
    // ipairs(t) returns: ipairs_iter, t, 1
    // ipairs_iter is a custom iterator that does numeric iteration

    ASTNode *arg = node->as.call.args_head;
    if (!arg) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "ipairs() requires 1 argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: ipairs(t) ---\n");

    // Evaluate table argument
    int table_reg = allocate_pinned_register();
    generate_asm(arg, table_reg);

    // Return: __builtin_ipairs_iter, table, 1
    emit_asm("MOV R0, __builtin_ipairs_iter ; Iterator function\n");
    emit_asm("OR R0, BOXED_FUNCTION  ; Box as function\n");

    emit_asm("PUSH R%d             ; Table (state)\n", table_reg);
    emit_asm("MOV R0, 1.000000      ; Starting index\n");
    emit_asm("PUSH R0             ; Starting key = 1\n");

    unlock_pinned_register(table_reg);
    return true;
}
