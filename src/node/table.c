#include "v32lua.h"

static int  pin_reg   (int r);
static void unpin_reg (int r, int was);

// `_ENV[k]` / `_ENV[k] = v`: globals looked up by NAME at runtime, through a
// table of (name, RAM address) for every global the program has, emitted
// after codegen (emit_env_table()). Only when _ENV isn't a variable the
// program declared itself.
bool g_uses_env = false;
static bool is_env_ref (ASTNode *e)
{
    if (e == NULL || e->type != NODE_IDENTIFIER || strcmp (e->as.id.name, "_ENV") != 0)
        return false;
    SymbolNode *sym = resolve_symbol ("_ENV");
    return sym == NULL;
}



void  node_table_constructor (ASTNode *node, int dest_reg)
{
    // 1. Allocate new table
    emit_asm("CALL __builtin_table_new\n");
    emit_asm("MOV R%d, R0\n", dest_reg);

    // 2. If there are initializers, process them
    if (node->as.table_constructor.initializers_head != NULL) {
        ASTNode *field = node->as.table_constructor.initializers_head;
        int array_index = 1; // Lua arrays are 1-indexed

        while (field != NULL) {
            // -----------------------------------------------------------
            // FIX: '...' inside a table constructor (`{...}` or
            // `{fixed, ...}`) previously fell into the generic
            // array-style branch below, calling generate_asm() directly
            // on this field -- but NODE_VARIADIC_EXPR's case in
            // generate_asm() is an unimplemented stub (emits only a
            // comment), leaving the "value" register holding whatever
            // garbage was already sitting in it. The table ended up with
            // exactly one bogus element regardless of how many actual
            // vararg values the caller passed -- including zero.
            //
            // Real Lua only expands '...' to ALL of its values when it
            // is the LAST field in the constructor; this grammar only
            // ever produces a single, standalone NODE_VARIADIC_EXPR
            // field, so field->next is expected to be NULL here for any
            // construct reachable from valid source.
            //
            // Requires the ENCLOSING function to actually be variadic;
            // node_function_def() stashes the two stack offsets needed
            // for this on context_stack_head specifically for this use.
            // A non-variadic context (vararg_count_offset == -1) safely
            // contributes zero elements instead of emitting bad code.
            // -----------------------------------------------------------
            if (field->type == NODE_VARIADIC_EXPR) {
                if (context_stack_head != NULL && context_stack_head->vararg_count_offset != -1) {
                    int count_reg = allocate_register();
                    int idx_reg   = allocate_register();
                    int addr_reg  = allocate_register();
                    int val_reg   = allocate_register();
                    int key_reg   = allocate_register();

                    mark_register_live(count_reg, 30);
                    mark_register_live(idx_reg,   30);

                    int vco = context_stack_head->vararg_count_offset;
                    int vfo = context_stack_head->vararg_first_offset;
                    int fpc = context_stack_head->fixed_param_count;

                    // vararg_count = (runtime total arg count) - (this
                    // function's own fixed/named parameter count)
                    emit_asm("MOV R%d, BP", addr_reg);
                    emit_asm("IADD R%d, %d ; BP offset of runtime arg count", addr_reg, vco);
                    emit_asm("MOV R%d, [R%d] ; runtime total argument count", count_reg, addr_reg);
                    emit_asm("ISUB R%d, %d ; subtract fixed param count -> vararg count", count_reg, fpc);

                    emit_asm("MOV R%d, 0 ; vararg loop index", idx_reg);

                    int loop_id = get_next_label();
                    const char *ctx = get_current_function_name();
                    char loop_label[128], end_label[128];
                    snprintf(loop_label, sizeof(loop_label), "__%s_vararg_expand_%d", ctx, loop_id);
                    snprintf(end_label,   sizeof(end_label),   "__%s_vararg_expand_end_%d", ctx, loop_id);

                    emit_asm("%s:", loop_label);

                    // Destructive comparison -- test a scratch copy, never idx_reg itself.
                    emit_asm("MOV R%d, R%d ; scratch copy (ILT is destructive)", val_reg, idx_reg);
                    emit_asm("ILT R%d, R%d ; index < vararg count?", val_reg, count_reg);
                    emit_asm("JF R%d, %s", val_reg, end_label);

                    // Load the actual vararg value from [BP + vfo + idx].
                    emit_asm("MOV R%d, BP", addr_reg);
                    emit_asm("IADD R%d, %d ; base offset of the first vararg value", addr_reg, vfo);
                    emit_asm("IADD R%d, R%d ; + loop index", addr_reg, idx_reg);
                    emit_asm("MOV R%d, [R%d] ; the vararg value itself (already a boxed Lua value)", val_reg, addr_reg);

                    // Key = array_index + idx, as a boxed Lua float.
                    emit_asm("MOV R%d, R%d", key_reg, idx_reg);
                    emit_asm("IADD R%d, %d ; base array index for this batch", key_reg, array_index);
                    emit_asm("CIF R%d ; key as Lua float", key_reg);

                    emit_asm("PUSH R%d ; table pointer", dest_reg);
                    emit_asm("PUSH R%d ; key", key_reg);
                    emit_asm("PUSH R%d ; value", val_reg);
                    emit_asm("CALL __builtin_table_set");
                    emit_asm("IADD SP, 3");

                    emit_asm("IADD R%d, 1", idx_reg);
                    emit_asm("JMP %s", loop_label);
                    emit_asm("%s:", end_label);

                    unlock_register(count_reg);
                    unlock_register(idx_reg);
                    unlock_register(addr_reg);
                    unlock_register(val_reg);
                    unlock_register(key_reg);
                }

                field = field->next;
                continue;
            }

            // Handle array-style initializer (just a value expression)
            if (field->type != NODE_TABLE_SET) {
                int val_reg = allocate_pinned_register();
                int key_reg = allocate_pinned_register();

                mark_register_live(val_reg, 2);
                mark_register_live(key_reg, 2);

                emit_asm("PUSH R%d ; spill destination register (protect across possible nested CALL in value expr)", dest_reg);

                generate_asm(field, val_reg);
                ensure_in_register(val_reg);

                emit_asm("PUSH R%d ; spill value (protect across key evaluation)", val_reg);

                ASTNode *key_node = make_node(NODE_NUMBER);
                key_node->as.number.val = array_index;
                generate_asm(key_node, key_reg);
                free(key_node);

                ensure_in_register(key_reg);

                emit_asm("POP  R%d ; reload spilled value", val_reg);
                emit_asm("POP  R%d ; reload spilled destination register", dest_reg);

                emit_asm("PUSH R%d ; table pointer", dest_reg);
                emit_asm("PUSH R%d ; key", key_reg);
                emit_asm("PUSH R%d ; value", val_reg);
                emit_asm("CALL __builtin_table_set");
                emit_asm("IADD SP, 3 ; clean up stack");

                unlock_pinned_register(val_reg);
                unlock_pinned_register(key_reg);

                array_index++;
            }
            // Handle record-style initializer (key = value, or [key] = value)
            else {
                int table_reg = dest_reg;
                int val_reg = allocate_pinned_register();
                int key_reg = allocate_pinned_register();

                mark_register_live(val_reg, 2);
                mark_register_live(key_reg, 2);

                emit_asm("PUSH R%d ; spill table pointer (protect across possible nested CALL in value expr)", table_reg);

                generate_asm(field->as.table_set.value, val_reg);
                ensure_in_register(val_reg);
                emit_asm("PUSH R%d ; spill value (protect across possible nested CALLs in key expr)", val_reg);

                generate_asm(field->as.table_set.key, key_reg);
                ensure_in_register(key_reg);

                emit_asm("POP  R%d ; reload spilled value", val_reg);
                emit_asm("POP  R%d ; reload spilled table pointer", table_reg);

                emit_asm("PUSH R%d ; table pointer", table_reg);
                emit_asm("PUSH R%d ; key", key_reg);
                emit_asm("PUSH R%d ; value", val_reg);
                emit_asm("CALL __builtin_table_set");
                emit_asm("IADD SP, 3 ; clean up stack");

                unlock_pinned_register(val_reg);
                unlock_pinned_register(key_reg);
            }

            field = field->next;
        }
    }
}

void  node_table_set (ASTNode *node)
{
    // 1. Attempt to emit as a hardware intrinsic FIRST, passing only the AST node!
    if (try_emit_table_set_intrinsic(node->as.table_set.table_expr,
                                     node->as.table_set.key,
                                     node->as.table_set.value))
    {
        // Intrinsic handled the emission (either via immediate or on-demand register)!
        return;
    }

    if (is_env_ref (node->as.table_set.table_expr)) {
        g_uses_env = true;
        int reg = allocate_register ();
        generate_asm (node->as.table_set.value, reg);
        ensure_in_register (reg);
        emit_asm ("PUSH R%d ; _ENV value", reg);
        unlock_register (reg);
        reg = allocate_register ();
        generate_asm (node->as.table_set.key, reg);
        ensure_in_register (reg);
        emit_asm ("PUSH R%d ; _ENV key (global name)", reg);
        unlock_register (reg);
        emit_asm ("CALL __builtin_env_set");
        emit_asm ("IADD SP, 2");
        return;
    }

    // 2. Fallback: Dynamic heap assignment (table[key] = value)
    int  val_reg    = allocate_pinned_register ();
    int  table_reg  = allocate_pinned_register ();
    int  key_reg    = allocate_pinned_register ();

    // All used immediately for table operation
    mark_register_live (val_reg,   2);
    mark_register_live (table_reg, 2);
    mark_register_live (key_reg,   2);

    // --- Evaluate VALUE first, then immediately spill it to the stack. ---
    // Register pinning only stops the COMPILER's allocator from reusing
    // val_reg's slot -- it does NOT protect the physical register from being
    // clobbered by a runtime CALL emitted while generating the table/key
    // sub-expressions. `t[#t + 1] = v` is exactly that case: the key
    // expression (`#t + 1`) emits `CALL __builtin_len`, which internally
    // calls `__builtin_table_len` / `__builtin_string_len` -- both of which
    // use R0-R2 as scratch with NO callee-save. If val_reg lands in R0-R2
    // (it does, typically R2), its value is silently destroyed before we
    // ever get to push it as the argument to __builtin_table_set.
    //
    // Spilling it to the hardware stack right away, then reloading it
    // immediately before the call, makes it immune to whatever the
    // table/key expressions do internally, including nested CALLs.
    generate_asm (node -> as.table_set.value, val_reg);
    ensure_in_register (val_reg);
    emit_asm ("PUSH R%d ; spill value (protect across possible nested CALLs in table/key exprs)", val_reg);

    // -----------------------------------------------------------------
    // FIX: the TABLE POINTER needs exactly the same protection as the
    // value above, and previously had none. `t[key_expr] = v` where
    // key_expr contains its own nested CALL -- e.g. `pending[k .. "_mod"]
    // = v * 10` (string concat -> CALL __builtin_strcat), or `t[f()] = v`,
    // or `t[#x] = v` -- evaluates table_expr into table_reg FIRST, then
    // generates the key expression SECOND. If that key expression emits
    // any CALL to a runtime routine that doesn't save/restore registers
    // (most of them don't -- e.g. __builtin_strcat freely clobbers
    // R1-R8, and reliably leaves R3 = 0 on every exit path), and
    // table_reg happens to land on one of those clobbered registers,
    // the table pointer is silently replaced with garbage (observed:
    // exactly 0, a non-table bit pattern) before __builtin_table_set
    // ever runs. allocate_pinned_register() does NOT protect against
    // this -- pinning only stops the COMPILER's allocator from handing
    // that register number to something else; it has no effect on a raw
    // hardware CALL clobbering the register's actual contents.
    //
    // Spilling table_reg to the hardware stack immediately after it's
    // computed -- before the key expression (which may contain nested
    // CALLs) is generated at all -- makes it immune, the same way the
    // value already is above.
    // -----------------------------------------------------------------
    generate_asm (node -> as.table_set.table_expr, table_reg);
    ensure_in_register (table_reg);
    emit_asm ("PUSH R%d ; spill table pointer (protect across possible nested CALLs in key expr)", table_reg);

    generate_asm (node -> as.table_set.key, key_reg);
    ensure_in_register (key_reg);

    // Reload in reverse (LIFO) order: table_reg was pushed LAST (after
    // val_reg), so it must be popped FIRST.
    emit_asm ("POP  R%d ; reload spilled table pointer", table_reg);
    emit_asm ("POP  R%d ; reload spilled value", val_reg);

    emit_asm ("PUSH R%d ; table pointer", table_reg);
    emit_asm ("PUSH R%d ; key",           key_reg);
    emit_asm ("PUSH R%d ; value",         val_reg);
    emit_asm ("CALL __builtin_table_set ; store key-value pair in table");
    emit_asm ("IADD SP, 3 ; clean up stack arguments");

    unlock_pinned_register (val_reg);
    unlock_pinned_register (table_reg);
    unlock_pinned_register (key_reg);
}


void  node_table_get (ASTNode *node, int  dest_reg)
{
    // 1. Attempt hardware intrinsic read directly into dest_reg
    if (try_emit_table_get_intrinsic(node->as.table_get.table_expr,
                                     node->as.table_get.key,
                                     dest_reg)) {
        return; // Successfully emitted Vircon32 IN instruction!
    }

    if (is_env_ref (node->as.table_get.table_expr)) {
        g_uses_env = true;
        int key_reg = allocate_register();
        generate_asm(node->as.table_get.key, key_reg);
        ensure_in_register(key_reg);
        emit_asm ("PUSH R%d ; _ENV key (global name)", key_reg);
        unlock_register (key_reg);
        emit_asm ("CALL __builtin_env_get");
        emit_asm ("IADD SP, 1");
        emit_asm ("MOV R%d, R0", dest_reg);
        return;
    }

    // 2. t.field (string-literal key): inline first probe
    if (node->as.table_get.key != NULL && node->as.table_get.key->type == NODE_STRING && dest_reg != 0)
    {
        int t_reg = allocate_register ();
        mark_register_live (t_reg, 3);
        generate_asm (node->as.table_get.table_expr, t_reg);
        ensure_in_register (t_reg);
        int pt = pin_reg (t_reg);                  // k_reg must not be t_reg
        int k_reg = allocate_register ();          // literal: a MOV, no CALL
        mark_register_live (k_reg, 2);
        generate_asm (node->as.table_get.key, k_reg);
        ensure_in_register (k_reg);
        emit_getk_lookup (t_reg, k_reg, node->as.table_get.key, dest_reg);
        unpin_reg (t_reg, pt);
        unlock_register (k_reg);
        unlock_register (t_reg);
        return;
    }

    // 3. t[k] where k's evaluation can't CALL (a variable or literal):
    //    array part read inline when k is a whole number in 1..capacity
    if (dest_reg != 0 && expr_is_simple_load (node->as.table_get.key))
    {
        int t_reg = allocate_register ();
        mark_register_live (t_reg, 3);
        generate_asm (node->as.table_get.table_expr, t_reg);
        ensure_in_register (t_reg);
        int pt = pin_reg (t_reg);                  // k_reg must not be t_reg
        int k_reg = allocate_register ();
        mark_register_live (k_reg, 2);
        generate_asm (node->as.table_get.key, k_reg);
        ensure_in_register (k_reg);
        emit_index_lookup (t_reg, k_reg, node->as.table_get.key, dest_reg);
        unpin_reg (t_reg, pt);
        unlock_register (k_reg);
        unlock_register (t_reg);
        return;
    }

    // 4. Fallback: Dynamic heap table lookup.
    // Each operand is pushed as soon as it is computed, so the table value
    // never has to survive the key expression in a register (the key may
    // CALL, and the allocator could hand the same register out twice).
    ASTNode *key = node->as.table_get.key;
    int table_reg = allocate_register();
    mark_register_live(table_reg, 2);
    generate_asm(node->as.table_get.table_expr, table_reg);
    ensure_in_register(table_reg);
    emit_asm ("PUSH R%d ; Arg1: Table Pointer", table_reg);
    unlock_register (table_reg);

    int key_reg = allocate_register();
    mark_register_live(key_reg, 2);
    generate_asm(key, key_reg);
    ensure_in_register(key_reg);
    emit_asm ("PUSH R%d ; Arg2: Key", key_reg);
    unlock_register (key_reg);

    // A string-literal key (t.field) takes the literal fast path: its
    // hash is precomputed in ROM (see __builtin_table_getk in table.s).
    if (key != NULL && key->type == NODE_STRING)
        emit_asm ("CALL __builtin_table_getk");
    else
        emit_asm ("CALL __builtin_table_get");
    emit_asm ("IADD SP, 2 ; Clean up stack");
    emit_asm ("MOV R%d, R0 ; Store result in destination register", dest_reg);
}


// ---------------------------------------------------------------------------
// t.field with a string-literal key, first probe inline.
//
// The literal's content hash is known at compile time (the same FNV-1a the
// string pool stores in front of each literal, see emit.c), and pooled
// literals are unique per content, so the lookup is: check it's a table
// with a hash part, index the slot, compare the stored key with the literal
// box. That hits in ~20 instructions; anything else (not a table, empty
// hash part, a different key in the slot -- a collision, or a run-time
// string equal by content) goes to __builtin_table_getk as before.
// table_reg and key_reg hold the table and the boxed literal and are left
// untouched; the value lands in dest_reg.
// ---------------------------------------------------------------------------
// While a table/key pair is in use, the allocator must not hand either
// register out again as scratch. Their "live" distances are only hints and
// run out after a few emitted instructions, after which Phase 2 treats them
// as dead: the inline lookup below then got its scratch register == the
// key register ("MOV R1, [R0+3] ; hash block" ... "IEQ R1, R1"), so the key
// check always passed and a lookup returned whatever the probed slot held
// (warm_wheels' menu: `s.selected[s.current] = ...` indexed nil). Pinning
// is honoured by every allocation phase; the previous pin state is restored.
static int pin_reg (int r)
{
    if (r <= 0 || r >= NUM_GPRS) return 1;
    int was = register_pinned[r];
    register_pinned[r] = 1;
    return was;
}
static void unpin_reg (int r, int was)
{
    if (r > 0 && r < NUM_GPRS && !was) register_pinned[r] = 0;
}

void emit_getk_lookup (int table_reg, int key_reg, ASTNode *key, int dest_reg)
{
    uint32_t h = 0x811C9DC5u;
    for (const unsigned char *c = (const unsigned char *) key->as.string_val.value; *c; c++) {
        h ^= (uint32_t)(*c & 0xFF);
        h *= 16777619u;
    }
    const char *ctx = get_current_function_name ();
    int id = get_next_label ();
    int pt = pin_reg (table_reg), pk = pin_reg (key_reg);
    int a  = allocate_register ();
    mark_register_live (a, 1);

    emit_asm ("MOV  R0, R%d ; inline t.%s\n", table_reg, key->as.string_val.value);
    emit_asm ("AND  R0, BOXED_DATA\n");
    emit_asm ("IEQ  R0, BOXED_TABLE\n");
    emit_asm ("JF   R0, __%s_getk_slow_%d\n", ctx, id);
    emit_asm ("MOV  R0, R%d\n", table_reg);
    emit_asm ("AND  R0, BOXED_PAYLOAD\n");
    emit_asm ("MOV  R%d, [R0+3] ; hash block\n", a);
    emit_asm ("MOV  R0, R%d\n", a);
    emit_asm ("IEQ  R0, 0\n");
    emit_asm ("JT   R0, __%s_getk_slow_%d\n", ctx, id);
    emit_asm ("MOV  R0, [R%d] ; capacity (power of two)\n", a);
    emit_asm ("ISUB R0, 1\n");
    emit_asm ("AND  R0, 0x%08X ; key hash\n", h);
    emit_asm ("SHL  R0, 1\n");
    emit_asm ("IADD R0, R%d ; slot - 2\n", a);
    emit_asm ("MOV  R%d, [R0+2] ; stored key\n", a);
    emit_asm ("IEQ  R%d, R%d\n", a, key_reg);
    emit_asm ("JF   R%d, __%s_getk_slow_%d\n", a, ctx, id);
    emit_asm ("MOV  R%d, [R0+3] ; value\n", dest_reg);
    emit_asm ("JMP  __%s_getk_done_%d\n", ctx, id);
    emit_asm ("__%s_getk_slow_%d:\n", ctx, id);
    emit_asm ("PUSH R%d\n", table_reg);
    emit_asm ("PUSH R%d\n", key_reg);
    emit_asm ("CALL __builtin_table_getk\n");
    emit_asm ("IADD SP, 2\n");
    emit_asm ("MOV  R%d, R0\n", dest_reg);
    emit_asm ("__%s_getk_done_%d:\n", ctx, id);
    unlock_register (a);
    unpin_reg (key_reg, pk);
    unpin_reg (table_reg, pt);
}


// ---------------------------------------------------------------------------
// t[k], array part inline: when t is a table and k a whole number in
// 1..capacity, read the slot directly (a nil there is the answer: a key is
// never in both parts). Anything else calls __builtin_table_get. A numeric
// literal key skips the run-time integer checks.
// ---------------------------------------------------------------------------
void emit_index_lookup (int table_reg, int key_reg, ASTNode *key, int dest_reg)
{
    const char *ctx = get_current_function_name ();
    int id = get_next_label ();
    bool lit = (key->type == NODE_NUMBER);
    if (lit)
    {
        double v = key->as.number.val;
        if (v < 1 || v > 65535 || v != (double)(int) v) lit = false;
        if (!lit) goto general;   // not an array index at all: no fast path
    }
    else if (key->type != NODE_IDENTIFIER)
        goto general;             // string/nil/boolean literal: hash part
    {
        int pt = pin_reg (table_reg), pk = pin_reg (key_reg);   // see pin_reg()
        int a = allocate_register ();
        unpin_reg (key_reg, pk);
        unpin_reg (table_reg, pt);
        mark_register_live (a, 1);
        emit_asm ("MOV  R0, R%d ; inline t[i]\n", table_reg);
        emit_asm ("AND  R0, BOXED_DATA\n");
        emit_asm ("IEQ  R0, BOXED_TABLE\n");
        emit_asm ("JF   R0, __%s_idx_slow_%d\n", ctx, id);
        if (lit)
        {
            emit_asm ("MOV  R%d, %d\n", a, (int) key->as.number.val);
        }
        else
        {
            emit_asm ("MOV  R0, R%d\n", key_reg);
            emit_asm ("AND  R0, NAN_VALUE\n");
            emit_asm ("IEQ  R0, NAN_VALUE\n");
            emit_asm ("JT   R0, __%s_idx_slow_%d ; not a number\n", ctx, id);
            emit_asm ("MOV  R%d, R%d\n", a, key_reg);
            emit_asm ("CFI  R%d\n", a);
            emit_asm ("MOV  R0, R%d\n", a);
            emit_asm ("CIF  R0\n");
            emit_asm ("IEQ  R0, R%d\n", key_reg);
            emit_asm ("JF   R0, __%s_idx_slow_%d ; not a whole number (or -0)\n", ctx, id);
            emit_asm ("MOV  R0, R%d\n", a);
            emit_asm ("ILT  R0, 1\n");
            emit_asm ("JT   R0, __%s_idx_slow_%d\n", ctx, id);
        }
        emit_asm ("MOV  R0, R%d\n", table_reg);
        emit_asm ("AND  R0, BOXED_PAYLOAD\n");
        emit_asm ("MOV  R0, [R0] ; flags: array capacity in the low 16 bits\n");
        emit_asm ("AND  R0, TABLE_ARRAYSIZE\n");
        emit_asm ("ILT  R0, R%d ; capacity < i ?\n", a);
        emit_asm ("JT   R0, __%s_idx_slow_%d\n", ctx, id);
        emit_asm ("MOV  R0, R%d\n", table_reg);
        emit_asm ("AND  R0, BOXED_PAYLOAD\n");
        emit_asm ("MOV  R0, [R0+2] ; array data\n");
        emit_asm ("IADD R0, R%d\n", a);
        emit_asm ("ISUB R0, 1\n");
        emit_asm ("MOV  R%d, [R0]\n", dest_reg);
        emit_asm ("JMP  __%s_idx_done_%d\n", ctx, id);
        unlock_register (a);
    }
    emit_asm ("__%s_idx_slow_%d:\n", ctx, id);
general:
    emit_asm ("PUSH R%d\n", table_reg);
    emit_asm ("PUSH R%d\n", key_reg);
    emit_asm ("CALL __builtin_table_get\n");
    emit_asm ("IADD SP, 2\n");
    emit_asm ("MOV  R%d, R0\n", dest_reg);
    emit_asm ("__%s_idx_done_%d:\n", ctx, id);
}

// A variable or literal: loading it is a MOV (or two), never a CALL.
bool expr_is_simple_load (ASTNode *n)
{
    if (n == NULL) return false;
    switch (n->type)
    {
        case NODE_NUMBER: case NODE_STRING: case NODE_NIL: case NODE_BOOLEAN:
            return true;
        case NODE_IDENTIFIER: {
            if (n->as.id.name == NULL || is_intrinsic_alias (n->as.id.name)) return false;
            if (strcmp (n->as.id.name, "self") == 0 || strcmp (n->as.id.name, "_ENV") == 0) return false;
            SymbolNode *sym = resolve_symbol (n->as.id.name);
            return !(sym != NULL && sym->is_function);
        }
        default:
            return false;
    }
}
