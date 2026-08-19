#include "v32lua.h"

bool emit_ipairs_intrinsic(ASTNode *node) {
    // ipairs(t) returns 3 values via the same R0/R2/R3 convention used
    // everywhere else multi-value returns flow in this compiler (see
    // node_return() / node_multiple_assignment()):
    //   R0 = iterator function (__builtin_ipairs_iter)
    //   R2 = state (the table itself)
    //   R3 = initial key (1)
    // This used to build its result on the hardware stack instead, which
    // node_for_generic() never actually consumed correctly -- and worse,
    // clobbered R0 (the iterator function pointer) with the starting
    // index before the caller ever got a chance to capture it, so the
    // very first CALL of any ipairs() loop jumped to whatever raw address
    // 1.0's bit pattern happened to be.

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
    ensure_in_register(table_reg);

    // Order matters: table_reg could physically be R2 or R3 (never R0,
    // since allocate_register() never hands out R0 -- it starts at 1).
    // Writing R0 first is always safe; copying table_reg into R2 BEFORE
    // touching R3 means that even if table_reg == R3, its value is
    // captured into R2 before R3 gets overwritten.
	emit_asm("MOV R0, __builtin_ipairs_iter ; Iterator function\n");
	emit_asm("OR R0, BOXED_FUNCTION  ; Box as function\n");
	emit_asm("MOV R2, R%d            ; State = table\n", table_reg);
	emit_asm("MOV R3, BOXED_NIL      ; Starting index (ipairs_iter treats nil as \"start at 1\")\n");

    unlock_pinned_register(table_reg);
    return true;
}

bool emit_pairs_intrinsic(ASTNode *node) {
    // pairs(t) returns 3 values via the same R0/R2/R3 convention (see
    // emit_ipairs_intrinsic's comment for the full rationale). The
    // previous version pushed a stray extra copy of the table onto the
    // hardware stack that was never cleaned up, and left R0 holding
    // BOXED_NIL -- not the iterator function -- by the time it returned,
    // so every pairs() loop tried to CALL the nil bit pattern as a jump
    // target on its very first iteration.

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
    ensure_in_register(table_reg);

    // We use the built-in __builtin_next as the iterator function.
    // Same ordering rationale as ipairs: R0 first (table_reg is never
    // R0), then R2 = table_reg before R3 might clobber it if they alias.
    emit_asm("MOV R0, __builtin_next ; Iterator function\n");
    emit_asm("OR R0, BOXED_FUNCTION  ; Box as function\n");
    emit_asm("MOV R2, R%d            ; State = table\n", table_reg);
    emit_asm("MOV R3, BOXED_NIL      ; Initial key = nil (next()'s \"start over\" signal)\n");

    unlock_pinned_register(table_reg);
    return true;
}
