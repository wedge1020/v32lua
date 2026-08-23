#include "v32lua.h"

// ============================================================================
// table.insert(t, [pos], value) - Inserts value at position (or appends)
// Two call forms: table.insert(t, value) [2 args] or
//                 table.insert(t, pos, value) [3 args]
// ============================================================================
int emit_table_insert_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;
    if (!arg || !arg->next) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "table.insert() expects at least two arguments");
        return 0;
    }
    ASTNode *arg2 = arg->next;
    ASTNode *arg3 = arg2->next;

    ASTNode *pos_node = arg3 ? arg2 : NULL;
    ASTNode *val_node = arg3 ? arg3 : arg2;

    emit_asm("    ;; --- Intrinsic: table.insert(t, [pos], value) ---\n");

    // --- Evaluate each argument, spilling it to the stack right away. ---
    // Any of these sub-expressions could itself contain a nested CALL
    // (e.g. `table.insert(t, #t, v)`), and several runtime helpers
    // (__builtin_len et al.) clobber R0-R2 with no callee-save. Spilling
    // each value to the hardware stack as soon as it's computed, then
    // reloading everything right before the final CALL, makes this immune
    // to whatever a later argument expression does internally -- same
    // pattern used for node_table_set / node_table_constructor.
    int t_reg = allocate_register();
    generate_asm(arg, t_reg);
    ensure_in_register(t_reg);
    emit_asm("    PUSH R%d ; spill table pointer\n", t_reg);

    int pos_reg = allocate_register();
    if (pos_node != NULL) {
        generate_asm(pos_node, pos_reg);
        ensure_in_register(pos_reg);
    } else {
        emit_asm("    MOV R%d, BOXED_NIL\n", pos_reg);  // default: append
    }
    emit_asm("    PUSH R%d ; spill position\n", pos_reg);

    int val_reg = allocate_register();
    generate_asm(val_node, val_reg);
    ensure_in_register(val_reg);

    // Reload in reverse order (LIFO) now that all arguments are safely computed.
    emit_asm("    POP  R%d ; reload position\n", pos_reg);
    emit_asm("    POP  R%d ; reload table pointer\n", t_reg);

    emit_asm("    PUSH R%d ; Table Pointer\n", t_reg);
    emit_asm("    PUSH R%d ; Position\n", pos_reg);
    emit_asm("    PUSH R%d ; Value\n", val_reg);
    emit_asm("    CALL __builtin_table_insert\n");
    emit_asm("    IADD SP, 3\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0\n", dest_reg);
    }

    unlock_register(t_reg);
    unlock_register(pos_reg);
    unlock_register(val_reg);
    return 1;
}

// ============================================================================
// table.remove(t, [pos]) - Removes and returns the element at position
// ============================================================================
int emit_table_remove_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;
    if (!arg) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "table.remove() expects at least one argument");
        return 0;
    }

    emit_asm("    ;; --- Intrinsic: table.remove(t, [pos]) ---\n");

    // --- Evaluate the table pointer, then immediately spill it to the
    //     stack. ---
    // The position expression (e.g. `table.remove(t, #t)`) could itself
    // contain a nested CALL, and several runtime helpers (__builtin_len et
    // al.) clobber R0-R2 with no callee-save. Spilling t_reg right away and
    // reloading it right before the final CALL makes it immune to whatever
    // the position expression does internally -- same pattern used for
    // node_table_set / node_table_constructor / emit_table_insert_intrinsic.
    int t_reg = allocate_register();
    generate_asm(arg, t_reg);
    ensure_in_register(t_reg);
    emit_asm("    PUSH R%d ; spill table pointer\n", t_reg);

    int pos_reg = allocate_register();
    if (arg->next != NULL) {
        generate_asm(arg->next, pos_reg);
        ensure_in_register(pos_reg);
    } else {
        emit_asm("    MOV R%d, BOXED_NIL\n", pos_reg);  // default: remove last element
    }

    emit_asm("    POP  R%d ; reload table pointer\n", t_reg);

    emit_asm("    PUSH R%d ; Table Pointer\n", t_reg);
    emit_asm("    PUSH R%d ; Position\n", pos_reg);
    emit_asm("    CALL __builtin_table_remove\n");
    emit_asm("    IADD SP, 2\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0\n", dest_reg);
    }

    unlock_register(t_reg);
    unlock_register(pos_reg);
    return 1;
}

// ============================================================================
// table.pack(...) - Packs a positional argument list into a new table with
// a .n field set to the argument count.
//
// SCOPE NOTE: this only handles a syntactically-known argument list
// (table.pack(a, b, c)) -- the same shape as a table constructor {a, b, c}.
// It does NOT forward an enclosing function's own '...' variadic parameter
// (table.pack(...) called from inside a variadic function). None of the
// current unit tests exercise that pattern; flagging it as a known gap.
//
// The .n field is set from the STATIC argument count (the AST arg list
// length), not from #table after the fact -- this matters because a nil
// argument in the middle (table.pack("a", nil, "c")) creates a hole in the
// array part, and #table would stop at that hole and undercount. Real
// Lua's table.pack always sets .n to the true argument count regardless of
// holes, which is exactly what using the static count gives us for free.
// ============================================================================
int emit_table_pack_intrinsic(ASTNode *node, int dest_reg)
{
    emit_asm("    ;; --- Intrinsic: table.pack(...) ---\n");

    int arg_count = 0;
    for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next) {
        arg_count++;
    }

    // --- Create the new table, spill its pointer immediately. ---
    // Every argument expression below could itself contain a nested CALL,
    // and __builtin_table_new / __builtin_table_set both clobber R0-R2 with
    // no callee-save -- same defensive spill-immediately pattern used by
    // node_table_constructor() and emit_table_insert_intrinsic().
    emit_asm("    CALL __builtin_table_new\n");
    int t_reg = allocate_register();
    emit_asm("    MOV R%d, R0\n", t_reg);

    // --- Evaluate and store each positional argument: t[i] = arg_i ---
    int idx = 1;
    for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next, idx++) {
        emit_asm("    PUSH R%d ; spill table pointer\n", t_reg);

        int val_reg = allocate_register();
        generate_asm(a, val_reg);
        ensure_in_register(val_reg);
        emit_asm("    PUSH R%d ; spill value\n", val_reg);

        emit_asm("    POP  R%d ; reload value\n", val_reg);
        emit_asm("    POP  R%d ; reload table pointer\n", t_reg);

        int key_reg = allocate_register();
        emit_asm("    MOV R%d, %d\n", key_reg, idx);
        emit_asm("    CIF R%d ; key as Lua float\n", key_reg);

        emit_asm("    PUSH R%d ; Table Pointer\n", t_reg);
        emit_asm("    PUSH R%d ; Key\n", key_reg);
        emit_asm("    PUSH R%d ; Value\n", val_reg);
        emit_asm("    CALL __builtin_table_set\n");
        emit_asm("    IADD SP, 3\n");

        unlock_register(val_reg);
        unlock_register(key_reg);
    }

    // --- Set the .n field: t["n"] = arg_count ---
    int n_string_id = add_string_literal("n");
    int n_key_reg = allocate_register();
    emit_asm("    MOV R%d, __string_%d\n", n_key_reg, n_string_id);
    emit_asm("    OR  R%d, BOXED_ROMSTRING ; Box as ROM String\n", n_key_reg);

    int n_val_reg = allocate_register();
    emit_asm("    MOV R%d, %d\n", n_val_reg, arg_count);
    emit_asm("    CIF R%d ; n as Lua float\n", n_val_reg);

    emit_asm("    PUSH R%d ; Table Pointer\n", t_reg);
    emit_asm("    PUSH R%d ; Key \"n\"\n", n_key_reg);
    emit_asm("    PUSH R%d ; Value (count)\n", n_val_reg);
    emit_asm("    CALL __builtin_table_set\n");
    emit_asm("    IADD SP, 3\n");

    unlock_register(n_key_reg);
    unlock_register(n_val_reg);

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R%d\n", dest_reg, t_reg);
    }

    unlock_register(t_reg);
    return 1;
}

// ============================================================================
// table.concat(list [, sep [, i [, j]]]) - Concatenate array elements into a string
// ============================================================================
int emit_table_concat_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg_t = node->as.call.args_head;
    if (!arg_t) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "table.concat() expects at least one argument");
        return 0;
    }
    ASTNode *arg_sep = arg_t->next;
    ASTNode *arg_i   = arg_sep ? arg_sep->next : NULL;
    ASTNode *arg_j   = arg_i   ? arg_i->next   : NULL;

    emit_asm("    ;; --- Intrinsic: table.concat(t, [sep], [i], [j]) ---\n");

    // Evaluate every argument first, spilling each to the stack immediately
    // -- any of these sub-expressions could contain a nested CALL, and
    // runtime helpers clobber R0-R2 with no callee-save. Same defensive
    // pattern as table.insert/table.remove/table.pack.
    int t_reg = allocate_register();
    generate_asm(arg_t, t_reg);
    ensure_in_register(t_reg);
    emit_asm("    PUSH R%d ; spill table pointer\n", t_reg);

    int sep_reg = allocate_register();
    if (arg_sep) {
        generate_asm(arg_sep, sep_reg);
        ensure_in_register(sep_reg);
    } else {
        emit_asm("    MOV R%d, BOXED_NIL ; default: no separator\n", sep_reg);
    }
    emit_asm("    PUSH R%d ; spill separator\n", sep_reg);

    int i_reg = allocate_register();
    if (arg_i) {
        generate_asm(arg_i, i_reg);
        ensure_in_register(i_reg);
    } else {
        emit_asm("    MOV R%d, BOXED_NIL ; default: i = 1\n", i_reg);
    }
    emit_asm("    PUSH R%d ; spill i\n", i_reg);

    int j_reg = allocate_register();
    if (arg_j) {
        generate_asm(arg_j, j_reg);
        ensure_in_register(j_reg);
    } else {
        emit_asm("    MOV R%d, BOXED_NIL ; default: j = #t\n", j_reg);
    }

    // Reload in reverse (LIFO) now that everything is safely computed.
    emit_asm("    POP  R%d ; reload i\n", i_reg);
    emit_asm("    POP  R%d ; reload separator\n", sep_reg);
    emit_asm("    POP  R%d ; reload table pointer\n", t_reg);

    emit_asm("    PUSH R%d ; Table Pointer\n", t_reg);
    emit_asm("    PUSH R%d ; Separator\n", sep_reg);
    emit_asm("    PUSH R%d ; i\n", i_reg);
    emit_asm("    PUSH R%d ; j\n", j_reg);
    emit_asm("    CALL __builtin_table_concat\n");
    emit_asm("    IADD SP, 4\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0\n", dest_reg);
    }

    unlock_register(t_reg);
    unlock_register(sep_reg);
    unlock_register(i_reg);
    unlock_register(j_reg);
    return 1;
}
