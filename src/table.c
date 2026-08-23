#include "v32lua.h"

// Returns true if call_node's target resolves (via resolve_static_path) to
// exactly "table.unpack". Used to special-case the two contexts where real
// value-expansion is possible.
bool is_table_unpack_call(ASTNode *call_node)
{
    if (call_node->type != NODE_FUNCTION_CALL) return false;
    char path[256] = {0};
    if (!resolve_static_path(call_node->as.call.target, path)) return false;
    return strcmp(path, "table.unpack") == 0;
}

// Resolves table.unpack(t, [i], [j])'s arguments into synthetic locals
// (t_name/i_name/j_name, each written with a unique suffix so nested or
// repeated unpack calls in the same scope never collide) that survive the
// per-element __builtin_table_get CALLs made by emit_table_unpack_fetch_
// element() below -- ordinary registers would not survive those calls.
void emit_table_unpack_resolve_bounds(ASTNode *call_node, char *t_name, char *i_name, char *j_name, int buf_size)
{
    ASTNode *args  = call_node->as.call.args_head;
    ASTNode *arg_t = args;
    ASTNode *arg_i = arg_t ? arg_t->next : NULL;
    ASTNode *arg_j = arg_i ? arg_i->next : NULL;

    int unique_id = get_next_label();
    snprintf(t_name, buf_size, "__unpack_t_%d", unique_id);
    snprintf(i_name, buf_size, "__unpack_i_%d", unique_id);
    snprintf(j_name, buf_size, "__unpack_j_%d", unique_id);

    // GLOBALS, not locals -- see the earlier debugging note above this
    // function. register_global() claims the next free RAM address and
    // isn't subject to count_function_locals()'s static pre-pass (which
    // runs BEFORE codegen and has no way to know these dynamically-
    // created slots will be needed), so there's no risk of the writes
    // below landing outside the function's reserved stack frame the way
    // register_local() did.
    register_global(t_name);
    register_global(i_name);
    register_global(j_name);

    int reg = allocate_register();
    generate_asm(arg_t, reg);
    ensure_in_register(reg);
    emit_store_variable(t_name, reg);
    unlock_register(reg);

    reg = allocate_register();
    if (arg_i) {
        generate_asm(arg_i, reg);
        ensure_in_register(reg);
    } else {
        emit_asm("    MOV R%d, 1.0 ; default i = 1\n", reg);
    }
    emit_store_variable(i_name, reg);
    unlock_register(reg);

    reg = allocate_register();
    if (arg_j) {
        generate_asm(arg_j, reg);
        ensure_in_register(reg);
    } else {
        emit_load_variable(t_name, reg);
        emit_asm("    PUSH R%d ; table pointer for #t\n", reg);
        emit_asm("    CALL __builtin_len\n");
        emit_asm("    IADD SP, 1\n");
        emit_asm("    MOV R%d, R0 ; default j = #t\n", reg);
    }
    emit_store_variable(j_name, reg);
    unlock_register(reg);
}

// Fetches element k (0-based offset from resolved i) of an already-
// resolved table.unpack(t,i,j) into dest_reg, or BOXED_NIL if the
// resolved index exceeds j. Lua numbers aren't NaN-tagged in this boxing
// scheme (only non-numbers occupy that space), so a loaded number local
// is directly usable in FADD/FGT without a separate unbox step.
void emit_table_unpack_fetch_element(const char *t_name, const char *i_name, const char *j_name, int k, int dest_reg)
{
    int idx_reg = allocate_register();
    emit_load_variable(i_name, idx_reg);
    if (k > 0) {
        emit_asm("    FADD R%d, %d.0 ; index = i + %d\n", idx_reg, k, k);
    }

    int j_reg = allocate_register();
    emit_load_variable(j_name, j_reg);

    int label_id = get_next_label();
    char nil_label[64], done_label[64];
    snprintf(nil_label,  sizeof(nil_label),  "__unpack_nil_%d",  label_id);
    snprintf(done_label, sizeof(done_label), "__unpack_done_%d", label_id);

    emit_asm("    FGT R%d, R%d ; index > j?\n", idx_reg, j_reg);
    emit_asm("    JT  R%d, %s\n", idx_reg, nil_label);

    int t_reg = allocate_register();
    emit_load_variable(t_name, t_reg);
    int fetch_idx_reg = allocate_register();
    emit_load_variable(i_name, fetch_idx_reg);
    if (k > 0) {
        emit_asm("    FADD R%d, %d.0\n", fetch_idx_reg, k);
    }
    emit_asm("    PUSH R%d ; table\n", t_reg);
    emit_asm("    PUSH R%d ; index\n", fetch_idx_reg);
    emit_asm("    CALL __builtin_table_get\n");
    emit_asm("    IADD SP, 2\n");
    emit_asm("    MOV R%d, R0\n", dest_reg);
    emit_asm("    JMP %s\n", done_label);
    unlock_register(t_reg);
    unlock_register(fetch_idx_reg);

    emit_asm("%s:\n", nil_label);
    emit_asm("    MOV R%d, BOXED_NIL\n", dest_reg);

    emit_asm("%s:\n", done_label);

    unlock_register(idx_reg);
    unlock_register(j_reg);
}
