#include "v32lua.h"

// ============================================================================
// Multi-value lists
// ----------------------------------------------------------------------------
// Lua lets the LAST expression of a list expand to all of its values:
//     f(a, ...)          f(a, g())          f(unpack(t))
//     return x, ...      return x, g()      {a, g()}      local a, b = ...
// Here a "multi-value tail" is `...`, unpack(t [, i [, j]]) (PICO-8's or
// table.unpack) or a call to a Lua function that may return several values.
// emit_mv_to_buf() leaves such a tail's values in MV_BUF[0 .. n-1] with n in
// [RET_COUNT] (see the MV_MAX note in register.h and the helpers at the end
// of runtime/table.s); the list contexts then push / store / return them.
// ============================================================================

extern ASTNode *g_last_exec_call;

static bool in_variadic_function (void)
{
    return context_stack_head != NULL && context_stack_head->vararg_count_offset != -1;
}

// The function symbol a call resolves to statically, or NULL.
static SymbolNode *mv_call_symbol (ASTNode *call, bool *is_unknown)
{
    ASTNode *target = call->as.call.target;
    *is_unknown = true;
    if (target == NULL) return NULL;

    if (target->type == NODE_IDENTIFIER) {
        SymbolNode *s = resolve_function_symbol (target->as.id.name);
        if (s == NULL) s = resolve_symbol (target->as.id.name);
        if (s == NULL) {
            *is_unknown = false;      // no such variable: an intrinsic
            return NULL;
        }
        if (s->is_function) *is_unknown = false;
        return s->is_function ? s : NULL;
    }

    if (call->as.call.is_method_call) return NULL;

    char path[256] = {0};
    if (!resolve_static_path (target, path)) return NULL;
    SymbolNode *s = resolve_symbol (path);
    if (s == NULL) {
        char m[256];
        snprintf (m, sizeof m, "%s", path);
        for (int i = 0; m[i]; i++) if (m[i] == '.' || m[i] == ':') m[i] = '_';
        s = resolve_symbol (m);
    }
    if (s != NULL && s->is_function) { *is_unknown = false; return s; }
    // a library namespace (math.floor, string.sub, ...): intrinsics
    static const char *libs[] = { "math.", "string.", "table.", "os.", "io.",
        "gpu.", "spu.", "inp.", "mem.", "tim.", "tilemap.", "ioports.", "coroutine.",
        "kbd.", NULL };
    for (int i = 0; libs[i]; i++)
        if (strncmp (path, libs[i], strlen (libs[i])) == 0) { *is_unknown = false; return NULL; }
    return NULL;
}

bool mv_is_unpack (ASTNode *e)
{
    if (e == NULL || e->type != NODE_FUNCTION_CALL) return false;
    if (is_table_unpack_call (e)) return true;
    ASTNode *t = e->as.call.target;
    return t != NULL && t->type == NODE_IDENTIFIER && strcmp (t->as.id.name, "__mv_unpack") == 0;
}

// Can e produce more (or fewer) than one value when it ends a list?
bool mv_is_tail (ASTNode *e)
{
    if (e == NULL) return false;
    if (e->type == NODE_VARIADIC_EXPR) return e->as.vararg.index == 0;
    if (e->type != NODE_FUNCTION_CALL) return false;
    if (mv_is_unpack (e)) return true;
    bool unknown;
    SymbolNode *s = mv_call_symbol (e, &unknown);
    if (s != NULL) return s->return_count > 1 || s->returns_mv;
    return unknown;
}

// Does this function body return a multi-value tail anywhere (`return ...`,
// `return x, g()` with g's count unknown)? Its callers then read the count
// from RET_COUNT instead of trusting the static return_count.
bool body_returns_mv (ASTNode *node)
{
    for (; node != NULL; node = node->next) {
        switch (node->type) {
            case NODE_RETURN: {
                ASTNode *e = node->as.return_stmt.expressions_head;
                while (e != NULL && e->next != NULL) e = e->next;
                if (e != NULL && mv_is_tail (e)) return true;
                break;
            }
            case NODE_IF:
                if (body_returns_mv (node->as.if_stmt.if_body) ||
                    body_returns_mv (node->as.if_stmt.else_body)) return true;
                break;
            case NODE_WHILE:       if (body_returns_mv (node->as.while_loop.body)) return true; break;
            case NODE_REPEAT:      if (body_returns_mv (node->as.repeat_loop.body)) return true; break;
            case NODE_FOR_NUMERIC: if (body_returns_mv (node->as.for_numeric.body)) return true; break;
            case NODE_FOR_GENERIC: if (body_returns_mv (node->as.for_generic.body)) return true; break;
            case NODE_DO_BLOCK:    if (body_returns_mv (node->as.do_block.body)) return true; break;
            default: break;
        }
    }
    return false;
}

// A register other than R2/R3 (which may hold return values 1 and 2).
static int alloc_not_r2r3 (void)
{
    int p2 = register_pinned[2], p3 = register_pinned[3];
    register_pinned[2] = register_pinned[3] = 1;
    int r = allocate_register ();
    register_pinned[2] = p2;
    register_pinned[3] = p3;
    return r;
}

// Evaluates e; afterwards its values are MV_BUF[0 .. n-1], n = [RET_COUNT].
// Clobbers every register (like any call).
void emit_mv_to_buf (ASTNode *e)
{
    runtime_req.needs_tables = true;      // the helpers live in table.s

    if (e->type == NODE_VARIADIC_EXPR) {
        if (in_variadic_function ()) {
            emit_asm ("MOV R2, BP\n");
            emit_asm ("IADD R2, %d\n", context_stack_head->vararg_count_offset);
            emit_asm ("MOV R2, [R2] ; arguments passed\n");
            emit_asm ("ISUB R2, %d ; -> number of varargs\n", context_stack_head->fixed_param_count);
            emit_asm ("MOV R1, BP\n");
            emit_asm ("IADD R1, %d ; the first vararg\n", context_stack_head->vararg_first_offset);
            emit_asm ("CALL __mv_from_mem\n");
        } else {
            emit_asm ("MOV R1, 0\n");
            emit_asm ("MOV [RET_COUNT], R1 ; `...` outside a vararg function: no values\n");
        }
        return;
    }

    if (mv_is_unpack (e)) {
        ASTNode *a = e->as.call.args_head;
        int r = allocate_pinned_register ();
        for (int k = 0; k < 3; k++) {
            if (a != NULL) {
                generate_asm (a, r);
                ensure_in_register (r);
                a = a->next;
            } else {
                emit_asm ("MOV R%d, BOXED_NIL\n", r);
            }
            emit_asm ("PUSH R%d ; unpack() argument %d\n", r, k + 1);
        }
        unlock_pinned_register (r);
        emit_asm ("CALL __mv_unpack\n");
        emit_asm ("IADD SP, 3\n");
        return;
    }

    int r = alloc_not_r2r3 ();
    mark_register_live (r, 4);
    generate_asm (e, r);
    ensure_in_register (r);
    if (e->type == NODE_FUNCTION_CALL && g_last_exec_call == e) {
        // a Lua call: values 0-2 are in R0/R2/R3, the rest already in MV_BUF
        emit_asm ("MOV [0x%08X], R0 ; return values 0-2 into MV_BUF\n", mv_buf_base);
        emit_asm ("MOV [0x%08X], R2\n", mv_buf_base + 1);
        emit_asm ("MOV [0x%08X], R3\n", mv_buf_base + 2);
    } else {
        emit_asm ("MOV [0x%08X], R%d ; a single value\n", mv_buf_base, r);
        emit_asm ("MOV R%d, 1\n", r);
        emit_asm ("MOV [RET_COUNT], R%d\n", r);
    }
    unlock_register (r);
}

// `return e1, ..., ek, tail`: the tail's values follow e1..ek. Leaves the
// list as a function return (R0/R2/R3 + MV_BUF[3..], RET_COUNT) and jumps
// to the function's return label.
void emit_mv_return (ASTNode *exprs)
{
    int k = 0;
    ASTNode *tail = exprs;
    while (tail->next != NULL) { tail = tail->next; k++; }

    // a lone call to a Lua function already leaves exactly this state
    if (k == 0 && tail->type == NODE_FUNCTION_CALL && !mv_is_unpack (tail)) {
        int r = alloc_not_r2r3 ();
        mark_register_live (r, 4);
        generate_asm (tail, r);
        ensure_in_register (r);
        if (g_last_exec_call != tail) {
            emit_asm ("MOV R0, R%d ; an intrinsic: one value\n", r);
            emit_asm ("MOV R%d, 1\n", r);
            emit_asm ("MOV [RET_COUNT], R%d\n", r);
        }
        unlock_register (r);
        emit_asm ("JMP __%s_return\n", get_current_function_name ());
        return;
    }

    int i = 0;
    for (ASTNode *e = exprs; e != tail; e = e->next, i++) {
        int r = allocate_register ();
        generate_asm (e, r);
        ensure_in_register (r);
        emit_asm ("PUSH R%d ; return value %d (the list follows)\n", r, i);
        unlock_register (r);
    }
    emit_mv_to_buf (tail);
    if (k > 0) {
        emit_asm ("MOV R1, %d\n", k);
        emit_asm ("CALL __mv_shift ; make room for %d leading value(s)\n", k);
        for (int j = k - 1; j >= 0; j--) {
            emit_asm ("POP R0\n");
            emit_asm ("MOV [0x%08X], R0 ; return value %d\n", mv_buf_base + j, j);
        }
    }
    emit_asm ("MOV R0, [0x%08X]\n", mv_buf_base);
    emit_asm ("MOV R2, [0x%08X]\n", mv_buf_base + 1);
    emit_asm ("MOV R3, [0x%08X]\n", mv_buf_base + 2);
    emit_asm ("JMP __%s_return\n", get_current_function_name ());
}

// {..., tail}: the tail's values become t[base], t[base + 1], ...
// table_reg holds the table and is preserved.
void emit_mv_table_tail (ASTNode *tail, int table_reg, int base)
{
    emit_asm ("PUSH R%d ; the table under construction\n", table_reg);
    emit_mv_to_buf (tail);
    emit_asm ("POP R%d\n", table_reg);
    emit_asm ("PUSH R%d\n", table_reg);
    emit_asm ("MOV R0, %d\n", base);
    emit_asm ("PUSH R0 ; first key\n");
    emit_asm ("CALL __mv_to_table\n");
    emit_asm ("IADD SP, 1\n");
    emit_asm ("POP R%d\n", table_reg);
}

// Pushes `count` values for assignment targets: MV_BUF[0 ..], nil past
// [RET_COUNT].
void emit_mv_push_values (int count)
{
    int r = allocate_register ();
    int id = get_next_label ();
    const char *ctx = get_current_function_name ();
    for (int k = 0; k < count; k++) {
        if (k >= MV_MAX) {
            emit_asm ("MOV R%d, BOXED_NIL ; past the longest list\n", r);
            emit_asm ("PUSH R%d\n", r);
            continue;
        }
        emit_asm ("MOV R%d, [RET_COUNT]\n", r);
        emit_asm ("IGT R%d, %d\n", r, k);
        emit_asm ("JF  R%d, __%s_mvnil_%d_%d\n", r, ctx, id, k);
        emit_asm ("MOV R%d, [0x%08X] ; value %d of the list\n", r, mv_buf_base + k, k);
        emit_asm ("JMP __%s_mvpush_%d_%d\n", ctx, id, k);
        emit_asm ("__%s_mvnil_%d_%d:\n", ctx, id, k);
        emit_asm ("MOV R%d, BOXED_NIL\n", r);
        emit_asm ("__%s_mvpush_%d_%d:\n", ctx, id, k);
        emit_asm ("PUSH R%d ; value %d for its target\n", r, k);
    }
    unlock_register (r);
}
