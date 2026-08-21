#include "v32lua.h"

void  node_while (ASTNode *node)
{
    int  cond_reg    = allocate_register ();
    int  label_id    = get_next_label ();
    const char *ctx  = get_current_function_name ();
    char end_label[128];
    snprintf(end_label, sizeof(end_label), "__%s_while_end_%d", ctx, label_id);

    push_loop(label_id, LOOP_TYPE_WHILE);  // Pass loop type

    emit_asm ("__%s_while_start_%d:\n", ctx, label_id);

    // ✅ Used for condition check
    mark_register_live (cond_reg, 2);
    
    generate_asm (node -> as.while_loop.condition, cond_reg);
    
    // AUDITED: Replaced hardware JF with NaN-box falsy check!
    emit_falsy_jump (cond_reg, end_label);
    unlock_register (cond_reg);
    
    push_scope (); 
    generate_block (node -> as.while_loop.body);
    pop_scope ();
    
    emit_asm ("JMP __%s_while_start_%d\n", ctx, label_id);
    emit_asm ("%s:\n", end_label);
    pop_loop ();
}

// ===========================================================================
// NUMERIC FOR LOOP: for index = start, limit, step do ... end
//
// Strategy:
//   1. Evaluate loop bounds (start, limit, step) and store as stack locals
//   2. Generate conditional check at loop start
//   3. Execute loop body
//   4. Increment index and jump back
//
// CLOSURE NOTE: if a nested closure captures the index variable, its slot
// holds a box pointer, not the value -- so every place this function reads
// or writes the index directly (condition check, increment) has to go
// through emit_load_variable()/emit_initialize_local() instead of touching
// access_index directly. The increment step specifically uses
// emit_initialize_local() (not emit_store_variable()) so that, when boxed,
// EACH iteration gets a fresh box -- matching Lua's per-iteration capture
// semantics instead of aliasing every iteration's closures to one cell.
// ===========================================================================
void  node_for_numeric (ASTNode *node)
{
    int label_id = get_next_label();
    const char *ctx = get_current_function_name();

    char start_label[128], end_label[128];
    snprintf(start_label, sizeof(start_label), "__%s_for_start_%d", ctx, label_id);
    snprintf(end_label, sizeof(end_label), "__%s_for_end_%d", ctx, label_id);

    // -------------------------------------------------------------------------
    // STEP 1: Enter loop scope and allocate stack storage for loop variables
    // -------------------------------------------------------------------------
    push_scope();

    // Generate unique names for loop control variables. NOTE: 'control_var'
    // is the loop's own hidden driving counter -- it is what STEP 4 checks
    // against the limit and what STEP 6 increments. It is completely
    // separate from 'index_var' (the user-visible Lua loop variable `i`).
    //
    // Lua semantics require that assigning to the loop variable inside the
    // body (e.g. `i = 100`) NEVER affects iteration. Previously this
    // function used index_var for both roles, so a body-side write to `i`
    // silently corrupted the loop's own bookkeeping and could terminate
    // iteration early. Now the loop drives itself entirely off control_var
    // (raw, unboxed, never visible to Lua source -- same category as
    // limit_var/step_var) and simply copies control_var's value into
    // index_var fresh at the top of every iteration, so the body can do
    // whatever it wants with `i` without any effect on the loop.
    char limit_var[64], step_var[64], control_var[64], index_var[64];
    snprintf(limit_var, sizeof(limit_var), "__limit_%d", label_id);
    snprintf(step_var, sizeof(step_var), "__step_%d", label_id);
    snprintf(control_var, sizeof(control_var), "__ctrl_%d", label_id);
    strcpy(index_var, node->as.for_numeric.index_name);

    // Access strings for stack frame references (limit/step/control are all
    // compiler-synthetic names Lua source can never capture, so they're
    // never boxed -- raw access for these three).
    char access_limit[128], access_step[128], access_control[128];

    // -------------------------------------------------------------------------
    // STEP 2: Evaluate loop bounds and store as stack locals
    // -------------------------------------------------------------------------
    int scratch = allocate_register();
    mark_register_live(scratch, 3);

    // Evaluate and store LIMIT
    generate_asm(node->as.for_numeric.stop_expr, scratch);
    register_local(limit_var);
    get_variable_access_string(limit_var, access_limit);
    emit_asm("MOV %s, R%d ; Save loop limit to stack", access_limit, scratch);

    // Evaluate and store STEP
    int is_static_step = 0;
    double static_step_val = 1.0;

    if (!node->as.for_numeric.step_expr) {
        is_static_step = 1;
        static_step_val = 1.0;
        emit_asm("MOV R%d, 1.000000 ; Default step = 1.0", scratch);
    } else if (node->as.for_numeric.step_expr->type == NODE_NUMBER) {
        is_static_step = 1;
        static_step_val = node->as.for_numeric.step_expr->as.number.val;
        emit_asm("MOV R%d, %f ; Static step value", scratch, static_step_val);
    } else {
        generate_asm(node->as.for_numeric.step_expr, scratch);
    }

    register_local(step_var);
    get_variable_access_string(step_var, access_step);
    emit_asm("MOV %s, R%d ; Save loop step to stack", access_step, scratch);

    // Evaluate and store the hidden CONTROL variable (start value). This is
    // the loop's real driver -- raw stack slot, never boxed, never touched
    // by anything the Lua body can name.
    generate_asm(node->as.for_numeric.start_expr, scratch);
    register_local(control_var);
    get_variable_access_string(control_var, access_control);
    emit_asm("MOV %s, R%d ; Save loop control counter to stack", access_control, scratch);

    // Register the user-visible INDEX variable too. Its actual value gets
    // populated from control_var at the top of each iteration (STEP 4b
    // below), but we register + initialize it here as well so it exists
    // with a sane value even if the loop body never runs a single iteration
    // (e.g. `for i = 10, 1 do ... end`) and something after the loop reads it.
    SymbolNode *index_sym = register_local(index_var);
    emit_initialize_local(index_sym, scratch);

    // Done with scratch register
    unlock_register(scratch);

    // -------------------------------------------------------------------------
    // STEP 3: Setup loop tracking for break statements
    // -------------------------------------------------------------------------
    push_loop(label_id, LOOP_TYPE_FOR_NUMERIC);

    emit_asm("%s:\n", start_label);

        // -------------------------------------------------------------------------
    // STEP 4: Loop condition check (against the hidden control variable)
    // -------------------------------------------------------------------------
    int r_idx = allocate_register();
    int r_lim = allocate_register();
    int r_idx_val = allocate_register();   // NEW: FGT/FLT below is destructive and
                                            // overwrites r_idx with its 0/1 boolean
                                            // result -- this register keeps an
                                            // untouched copy of the actual control
                                            // value for STEP 4b to publish into `i`.

    mark_register_live(r_idx, 5);
    mark_register_live(r_lim, 5);
    mark_register_live(r_idx_val, 5);

    // Load control counter (never boxed) and limit (never boxed) into registers.
    emit_asm("MOV R%d, %s", r_idx, access_control);
    emit_asm("MOV R%d, R%d ; preserve control value -- FGT/FLT below is destructive", r_idx_val, r_idx);
    emit_asm("MOV R%d, %s", r_lim, access_limit);

    if (is_static_step) {
        ensure_in_register(r_idx);
        ensure_in_register(r_lim);

        if (static_step_val >= 0.0) {
            emit_asm("FGT R%d, R%d ; Check if control > limit (exit condition)", r_idx, r_lim);
        } else {
            emit_asm("FLT R%d, R%d ; Check if control < limit (exit condition)", r_idx, r_lim);
        }
        emit_asm("JT R%d, %s ; Jump to end if loop condition fails", r_idx, end_label);
    } else {
        int r_step = allocate_register();
        mark_register_live(r_step, 3);

        emit_asm("MOV R%d, %s", r_step, access_step);
        ensure_in_register(r_idx);
        ensure_in_register(r_lim);

        char pos_lbl[128], chk_lbl[128];
        snprintf(pos_lbl, sizeof(pos_lbl), "__%s_for_pos_%d", ctx, label_id);
        snprintf(chk_lbl, sizeof(chk_lbl), "__%s_for_chk_%d", ctx, label_id);

        emit_asm("FGE R%d, 0.000000 ; Check if step >= 0", r_step);
        emit_asm("JT R%d, %s ; Jump if step is positive", r_step, pos_lbl);

        emit_asm("FLT R%d, R%d ; control < limit?", r_idx, r_lim);
        emit_asm("JMP %s ; Jump to check", chk_lbl);

        emit_asm("%s:\n", pos_lbl);
        emit_asm("FGT R%d, R%d ; control > limit?", r_idx, r_lim);

        emit_asm("%s:\n", chk_lbl);
        emit_asm("JT R%d, %s ; Exit if condition met", r_idx, end_label);

        unlock_register(r_step);
    }

    // -------------------------------------------------------------------------
    // STEP 4b: Publish the (preserved, pre-comparison) control counter into
    // the user-visible index variable for this iteration. r_idx itself is
    // NOT safe to use here -- FGT/FLT above destructively overwrote it with
    // their 0/1 comparison result. r_idx_val still holds the real value.
    // -------------------------------------------------------------------------
    emit_initialize_local(index_sym, r_idx_val);

    unlock_register(r_idx);
    unlock_register(r_lim);
    unlock_register(r_idx_val);

    // -------------------------------------------------------------------------
    // STEP 5: Execute loop body
    // -------------------------------------------------------------------------
    generate_block(node->as.for_numeric.body);

    // -------------------------------------------------------------------------
    // STEP 6: Increment the hidden control variable and loop back. Note
    // this reads/writes control_var, NOT index_var -- so anything the body
    // did to `i` is irrelevant to iteration.
    // -------------------------------------------------------------------------
    int r_calc = allocate_register();
    int r_st = allocate_register();

    mark_register_live(r_calc, 2);
    mark_register_live(r_st, 2);

    emit_asm("MOV R%d, %s", r_calc, access_control);
    emit_asm("MOV R%d, %s", r_st, access_step);

    ensure_in_register(r_calc);
    ensure_in_register(r_st);

    emit_asm("FADD R%d, R%d ; control += step", r_calc, r_st);

    // Plain raw store back into the hidden control slot -- no boxing, no
    // closure semantics, this variable is never Lua-visible.
    emit_asm("MOV %s, R%d ; Save incremented control counter", access_control, r_calc);

    unlock_register(r_calc);
    unlock_register(r_st);

    emit_asm("JMP %s ; Loop back to condition", start_label);
    emit_asm("%s:\n", end_label);

    // -------------------------------------------------------------------------
    // STEP 7: Clean up loop context
    // -------------------------------------------------------------------------
    pop_loop ();
    pop_scope ();
}

// ============================================================================
// GENERIC FOR: for var_list in iter_expr do ... end
//
// Two calling conventions in play here, both mirroring conventions already
// established elsewhere in this compiler rather than inventing new ones:
//
//   1. iter_expr evaluation: the grammar (for_start var_list TOKEN_IN
//      expr_list ...) means iter_expr is always an expr_list -- either a
//      single expression (typically pairs(t)/ipairs(t), or any call that
//      itself returns 3 values), or an explicit list of up to 3
//      expressions (`for i,v in f, s, var do`). The single-expression form
//      returns all 3 values itself via R0/R2/R3 -- the same multi-return
//      convention node_return()/node_multiple_assignment() use everywhere
//      else. The explicit-list form evaluates each expression separately
//      and places them into R0/R2/R3 by hand.
//
//   2. Per-iteration iterator calls: CALL iterator(state, key) returns its
//      results the same way any 2-or-3-value function return does in this
//      compiler -- R0 = new key (or nil/false when done), R2 = first
//      value, R3 = second value (rarely used by iterators, kept for
//      generality).
//
// FIX 3 (this pass): the per-iteration call to the iterator function
// previously pushed STATE then KEY, which (because the last value pushed
// always lands at [BP+2], closest to the return address) put the KEY at
// [BP+2] and the STATE at [BP+3]. That happened to match the two
// hand-written runtime iterators (__builtin_next, __builtin_ipairs_iter),
// which were hand-tuned to read that exact layout -- but it is BACKWARDS
// relative to how this compiler assigns parameter offsets to an ordinary
// Lua function. register_parameter() assigns ascending offsets starting
// at [BP+2] in declaration order, so for `function simple_iter(t, i)`,
// `t` (first declared) is [BP+2] and `i` (second declared) is [BP+3].
// A custom iterator written in Lua (`for i,v in simple_iter, t15, 0 do`)
// was therefore getting KEY bound to its `t` parameter and STATE (a
// table) bound to its `i` parameter -- on the first call this passes a
// non-table into `t[i]`, which trips __runtime_error_not_table and HLTs
// the CPU.
//
// The push order below is now STATE pushed last (-> [BP+2], matching a
// normal iterator function's first parameter) and KEY pushed first (->
// [BP+3], matching its second parameter). __builtin_next and
// __builtin_ipairs_iter in runtime.s have been updated to read the new
// (now-correct, and now-consistent-with-everything-else) offsets to
// match. This is a breaking change to those two routines' internal
// offsets -- they must be updated together with this function.
//
// Previously this function invented a third, incompatible convention
// (reading return values off the hardware stack via [SP-0]/[SP-1]), which
// matched neither the compiler's own multi-return convention nor the
// actual behavior of the hand-written iterators in runtime.s. It also
// checked the CURRENT key for nil BEFORE ever calling the iterator, which
// is backwards for next()/pairs() -- whose documented calling convention
// is to pass nil to mean "give me the first key." That meant every
// pairs() loop saw pairs()'s own initial nil key at the very first check
// and exited before the iterator was ever called. And it only ever
// evaluated the first node of iter_expr, silently dropping the state/
// control-variable expressions in the explicit-list form.
//
// FIX 2 (retained): loop control registers are unpinned around the call
// and body so the body doesn't exhaust the register file.
// ============================================================================
void node_for_generic(ASTNode *node)
{
    int label_id = get_next_label();
    const char *ctx = get_current_function_name();

    char start_label[128], end_label[128];
    snprintf(start_label, sizeof(start_label), "__%s_for_gen_start_%d", ctx, label_id);
    snprintf(end_label, sizeof(end_label), "__%s_for_gen_end_%d", ctx, label_id);

    // ---------------------------------------------------------------------
    // STEP 1: Enter loop scope
    // ---------------------------------------------------------------------
    push_scope();
    push_loop(label_id, LOOP_TYPE_FOR_GENERIC);

    // ---------------------------------------------------------------------
    // STEP 2: Evaluate iterator expression(s) into R0/R2/R3
    // ---------------------------------------------------------------------
    int iter_reg = allocate_pinned_register();
    int state_reg = allocate_pinned_register();
    int key_reg = allocate_pinned_register();

    mark_register_live(iter_reg, 10);
    mark_register_live(state_reg, 10);
    mark_register_live(key_reg, 10);

    ASTNode *iter_list_head = node->as.for_generic.iter_expr;

    if (iter_list_head != NULL && iter_list_head->next != NULL) {
        // Explicit list form: f, s, var (var is optional -> defaults to nil)
        ASTNode *f_node = iter_list_head;
        ASTNode *s_node = f_node->next;
        ASTNode *v_node = s_node->next;

        // -------------------------------------------------------------
        // FIX: Compute f/s/v into pinned registers AND explicitly spill
        // each one to the hardware stack immediately after computing it
        // -- BEFORE generating the next expression in the list. Pinning
        // alone (the previous approach) does NOT survive a nested CALL:
        // it only stops the COMPILER's allocator from reassigning that
        // register number, it does not stop a raw hardware CALL to a
        // no-callee-save runtime routine from clobbering the register's
        // actual contents. `for i,v in reverse_iter, t16, #t16 + 1 do`
        // is exactly this case -- the control-variable expression
        // (`#t16 + 1`) emits `CALL __builtin_len`, which internally
        // calls `__builtin_table_len`, which uses R2 as scratch with no
        // save/restore. If state_reg (holding t16) happens to land on
        // R2 -- it does -- its value is silently destroyed before it's
        // ever copied into the iterator-state slot, corrupting every
        // subsequent call to the custom iterator for the rest of the
        // loop with garbage instead of the real table.
        //
        // Same fix shape as node_table_set(): spill right after
        // computing, reload in reverse (LIFO) order right before use.
        // -------------------------------------------------------------
        generate_asm(f_node, iter_reg);
        ensure_in_register(iter_reg);
        emit_asm("PUSH R%d ; spill iterator function (protect across possible nested CALLs in state/control exprs)\n", iter_reg);

        generate_asm(s_node, state_reg);
        ensure_in_register(state_reg);
        emit_asm("PUSH R%d ; spill state (protect across possible nested CALLs in control-var expr)\n", state_reg);

        if (v_node != NULL) {
            generate_asm(v_node, key_reg);
            ensure_in_register(key_reg);
        }

        // Reload in reverse (LIFO) order: state_reg was pushed LAST, so
        // it must be popped FIRST.
        emit_asm("POP R%d ; reload spilled state\n", state_reg);
        emit_asm("POP R%d ; reload spilled iterator function\n", iter_reg);

        emit_asm("MOV R0, R%d ; Iterator function (explicit list form)\n", iter_reg);
        emit_asm("MOV R2, R%d ; State (explicit list form)\n", state_reg);
        if (v_node != NULL) {
            emit_asm("MOV R3, R%d ; Initial control variable (explicit list form)\n", key_reg);
        } else {
            emit_asm("MOV R3, BOXED_NIL ; Initial control variable omitted, defaults to nil\n");
        }
    } else {
        // Single-expression form: pairs(t) / ipairs(t) / any call that
        // itself returns 3 values via R0/R2/R3.
        generate_asm(iter_list_head, 0);
    }

    // ---------------------------------------------------------------------
    // STEP 2.5: Store iterator results in local variables
    // ---------------------------------------------------------------------
    char iter_func_var[64], state_var[64], key_var[64];
    snprintf(iter_func_var, sizeof(iter_func_var), "__for_iter_%d", label_id);
    snprintf(state_var, sizeof(state_var), "__for_state_%d", label_id);
    snprintf(key_var, sizeof(key_var), "__for_key_%d", label_id);

    register_local(iter_func_var);
    register_local(state_var);
    register_local(key_var);

    char access_iter[128], access_state[128], access_key[128];

    get_variable_access_string(iter_func_var, access_iter);
    get_variable_access_string(state_var, access_state);
    get_variable_access_string(key_var, access_key);

    emit_asm("MOV %s, R0         ; Store iterator function\n", access_iter);
    emit_asm("MOV %s, R2         ; Store state\n", access_state);
    emit_asm("MOV %s, R3         ; Store initial key\n", access_key);

    // FIX 2: Now that we've stored the loop control values in stack locals,
    // we can UNPIN the registers we used for setup.
    unlock_pinned_register(iter_reg);
    unlock_pinned_register(state_reg);
    unlock_pinned_register(key_reg);

    // ---------------------------------------------------------------------
    // STEP 3: Create local variables for loop vars
    // ---------------------------------------------------------------------
    ASTNode *var = node->as.for_generic.var_list;
    char **var_names = NULL;
    SymbolNode **var_syms = NULL;
    int var_count = 0;

    ASTNode *curr = var;
    while (curr != NULL) {
        var_count++;
        curr = curr->next;
    }

    var_names = (char **)malloc(var_count * sizeof(char *));
    var_syms  = (SymbolNode **)malloc(var_count * sizeof(SymbolNode *));
    curr = var;
    for (int i = 0; i < var_count && curr != NULL; i++) {
        var_names[i] = curr->as.id.name;
        var_syms[i]  = register_local(var_names[i]);
        curr = curr->next;
    }

    // ---------------------------------------------------------------------
    // STEP 4: Loop start label
    // ---------------------------------------------------------------------
    emit_asm("%s:\n", start_label);

    // ---------------------------------------------------------------------
    // STEP 5: Call iterator_func(state, current_key), THEN check the
    //         RETURNED key for nil/false -- not the key about to be
    //         passed in. See the function-level comment above for why
    //         checking beforehand is wrong for next()/pairs().
    // ---------------------------------------------------------------------
    int saved_pinned[NUM_GPRS];
    for (int i = 0; i < NUM_GPRS; i++) {
        saved_pinned[i] = register_pinned[i];
    }
    for (int i = 0; i < NUM_GPRS; i++) {
        register_pinned[i] = 0;
    }

    // -----------------------------------------------------------------
    // Push arguments for iterator call: iterator(state, current_key).
    //
    // FIX 3: KEY is pushed FIRST (-> lands at [BP+3]) and STATE is
    // pushed LAST (-> lands at [BP+2], since the last value pushed
    // always ends up closest to the return address). This makes STATE
    // the callee's first formal parameter and KEY its second formal
    // parameter -- matching how register_parameter() assigns offsets to
    // an ordinary Lua function's own declared parameters (ascending from
    // [BP+2] in declaration order). This is what makes a user-written
    // iterator like `function simple_iter(t, i)` receive the table in
    // `t` and the running index in `i`, instead of the reverse.
    //
    // __builtin_next and __builtin_ipairs_iter have been updated to read
    // [BP+2]=state/table, [BP+3]=key/index to match this new order.
    // -----------------------------------------------------------------
    int arg_reg = allocate_register();
    mark_register_live(arg_reg, 2);

    get_variable_access_string(key_var, access_key);
    emit_asm("MOV R%d, %s           ; Load current key into register\n", arg_reg, access_key);
    emit_asm("PUSH R%d               ; Arg 2: current key (pushed first -> [BP+3])\n", arg_reg);

    get_variable_access_string(state_var, access_state);
    emit_asm("MOV R%d, %s           ; Load state into register\n", arg_reg, access_state);
    emit_asm("PUSH R%d               ; Arg 1: state (pushed last -> [BP+2])\n", arg_reg);

    unlock_register(arg_reg);

    // Call iterator function
    get_variable_access_string(iter_func_var, access_iter);
    emit_asm("MOV R0, %s        ; Load iterator function\n", access_iter);
    emit_asm("CALL __builtin_exec ; Validate and execute iterator (unboxes tag, handles closures)\n");
    emit_asm("IADD SP, 2         ; Clean up 2 arguments\n");

    // Iterator results come back via R0/R2/R3. Lock R2/R3 BEFORE allocating
    // any scratch register below -- otherwise allocate_register() can (and
    // did) hand back R2 or R3 for the falsy-check scratch register, since a
    // real hardware CALL doesn't touch this compiler's own register_inventory
    // bookkeeping. The scratch register's own MOV then clobbers the very
    // return value it's sitting on top of, before the loop-variable
    // assignments below ever get to read it. R0 doesn't need locking here --
    // allocate_register() never hands out R0 in the first place (its scan
    // starts at index 1). Same hazard node_multiple_assignment's PASS1
    // already guards against for this exact register set.
    lock_register(2);
    lock_register(3);

    // Check the RETURNED key (R0), not the key we just passed in.
    int check_reg = allocate_register();
    mark_register_live(check_reg, 5);
    emit_asm("MOV R%d, R0        ; Copy returned key for falsy check\n", check_reg);
    emit_falsy_jump(check_reg, end_label);
    unlock_register(check_reg);

    // Store new key for next iteration
    emit_asm("MOV %s, R0        ; Save new key for next iteration\n", access_key);

    // -----------------------------------------------------------------
    // FIX: assign loop variables from R0/R2/R3 THROUGH emit_initialize_
    // local(), not a raw MOV into get_variable_access_string()'s slot.
    //
    // Two separate problems with the raw MOV this replaces:
    //
    //   1. It completely ignored sym->is_boxed. get_variable_access_
    //      string() only ever returns a variable's SLOT address -- it
    //      has no idea whether that slot holds a raw value or a BOX
    //      POINTER (for a variable captured by a nested closure); that
    //      distinction is applied by the emit_load_variable()/emit_
    //      store_variable()/emit_initialize_local() layer, which this
    //      code bypassed entirely. For a boxed loop variable, the raw
    //      MOV overwrote the box POINTER itself with the raw iteration
    //      value -- not the box's contents. Every later read of that
    //      variable (including from inside the closure capturing it)
    //      then dereferenced that raw value as if it were a valid heap
    //      address, corrupting whatever memory happened to sit there.
    //      (Confirmed directly: v32sim faulted with a stack-overflow
    //      trap inside the closure's own body, at the exact `MOV R5,
    //      [R5]` dereference of a corrupted "box pointer" that was
    //      actually just the raw captured value's own NaN-tagged bit
    //      pattern being read as a memory address.)
    //
    //   2. Even routed through emit_store_variable() (write through the
    //      EXISTING box) instead, every closure created across every
    //      iteration would still alias the SAME one box -- exactly the
    //      bug node_for_numeric's own CLOSURE_NOTE already documents
    //      and fixes for its index variable, via emit_initialize_local()
    //      instead of emit_store_variable(): a closure created in
    //      iteration N must keep seeing iteration N's value even after
    //      later iterations run, which requires a FRESH box every
    //      iteration, not a shared one.
    //
    // emit_initialize_local() itself internally calls __malloc for any
    // BOXED variable, which clobbers R0-R3 and R6 (see its own comment).
    // With up to 3 loop variables all sourced from R0/R2/R3, boxing the
    // FIRST one would destroy the raw values still waiting in R2/R3 for
    // the second and third -- so PASS 1 spills all of them to the
    // hardware stack in one unbroken block BEFORE any per-variable
    // store/box logic runs, and PASS 2 pops them back one at a time,
    // right before each is actually consumed. Same two-pass shape as
    // node_return()'s and node_multiple_assignment()'s equivalent fixes.
    // -----------------------------------------------------------------
    int raw_regs[3] = {0, 2, 3};
    int used_count = (var_count < 3) ? var_count : 3;

    for (int i = 0; i < used_count; i++) {
        emit_asm("PUSH R%d ; spill loop variable %d's raw value (protect across possible boxing __malloc)\n",
                 raw_regs[i], i);
    }

    // R2/R3 have now been fully consumed (spilled to the hardware stack)
    // -- safe to release the lock taken above.
    unlock_register(2);
    unlock_register(3);

    for (int i = used_count - 1; i >= 0; i--) {
        int tmp_reg = allocate_register();
        emit_asm("POP R%d ; restore loop variable %d's raw value\n", tmp_reg, i);
        emit_initialize_local(var_syms[i], tmp_reg);
        unlock_register(tmp_reg);
    }

    // ---------------------------------------------------------------------
    // STEP 6: Execute Loop Body
    // ---------------------------------------------------------------------
    push_scope();
    generate_block(node->as.for_generic.body);
    pop_scope();

    emit_asm("JMP %s\n", start_label);

    // ---------------------------------------------------------------------
    // STEP 7: Loop end label
    // ---------------------------------------------------------------------
    emit_asm("%s:\n", end_label);

    for (int i = 0; i < NUM_GPRS; i++) {
        register_pinned[i] = saved_pinned[i];
    }

    free(var_names);
    free(var_syms);

    pop_loop();
    pop_scope();
}

// ===========================================================================
// REPEAT/UNTIL LOOP: repeat ... until condition
//
// The two things that make this genuinely different from `while`, not just
// a cosmetic reordering:
//
//   1. The body always executes at least once -- the condition is checked
//      AFTER the body runs, not before. So there's no falsy-check-then-skip
//      at the top the way node_while() has; instead we run the body
//      unconditionally, then check whether to loop again.
//
//   2. The until-condition is evaluated INSIDE THE BODY'S OWN SCOPE. A local
//      declared partway through the body (`local done = ...`) must still be
//      visible when the until-expression is generated. This is why
//      push_scope()/pop_scope() here wrap BOTH generate_block(body) AND
//      generate_asm(condition) -- pop_scope() is deliberately deferred
//      until after the condition has been fully generated, unlike every
//      other loop type in this compiler, where the condition (if any) is
//      evaluated in the OUTER scope, before the loop's own scope is pushed.
//
// break support works identically to every other loop type: push_loop()
// before the body, and node_break() looks up LOOP_TYPE_REPEAT to build the
// matching "__<func>_repeat_end_<id>" label (see node_break()'s tag switch).
// ===========================================================================
void  node_repeat (ASTNode *node)
{
    int  label_id   = get_next_label ();
    const char *ctx  = get_current_function_name ();
    char start_label[128], end_label[128];
    snprintf(start_label, sizeof(start_label), "__%s_repeat_start_%d", ctx, label_id);
    snprintf(end_label,   sizeof(end_label),   "__%s_repeat_end_%d",   ctx, label_id);

    push_loop(label_id, LOOP_TYPE_REPEAT);

    emit_asm ("%s:\n", start_label);

    // -----------------------------------------------------------------
    // Body and condition share ONE scope -- see the function-level
    // comment above for why pop_scope() is deferred past the condition.
    // -----------------------------------------------------------------
    push_scope ();
    generate_block (node -> as.repeat_loop.body);

    int  cond_reg = allocate_register ();
    mark_register_live (cond_reg, 2);
    generate_asm (node -> as.repeat_loop.condition, cond_reg);

    pop_scope ();

    // Loop again if the condition is falsy; stop (fall through to
    // end_label) if it's truthy -- the inverse of while's falsy-jump,
    // matching repeat/until's inverted "stop when true" semantics.
    emit_truthy_jump (cond_reg, end_label);
    unlock_register (cond_reg);

    emit_asm ("JMP %s\n", start_label);
    emit_asm ("%s:\n", end_label);

    pop_loop ();
}
