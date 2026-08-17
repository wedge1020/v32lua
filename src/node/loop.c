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
// GENERIC FOR LOOP: for k, v in pairs(t) do ... end
//
// Strategy:
//   1. Evaluate the iterator expression (e.g., pairs(t))
//   2. This should return: iterator_func, state, initial_key
//   3. Store these in local variables
//   4. Generate while(true) loop that calls iterator_func(state, key)
//   5. Check for nil to break
//   6. Assign loop variables and execute body
//
// FIX 2: When executing the loop body, temporarily unpin the loop control
// registers (iter_reg, state_reg, key_reg) to allow the body code to reuse
// them. This prevents register exhaustion when the loop body contains function
// calls or complex expressions that need many registers.
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
    // STEP 2: Evaluate iterator expression
    // For: for k,v in pairs(t) do
    // iter_expr = pairs(t) which should return: iter_func, state, first_key
    // ---------------------------------------------------------------------
    int iter_reg = allocate_pinned_register();
    int state_reg = allocate_pinned_register();
    int key_reg = allocate_pinned_register();

    mark_register_live(iter_reg, 10);
    mark_register_live(state_reg, 10);
    mark_register_live(key_reg, 10);

    // Evaluate the iterator expression - should return 3 values on stack
    generate_asm(node->as.for_generic.iter_expr, 0);

    // The iterator function call (pairs/ipairs) should leave:
    // R0 = iterator function
    // [SP-1] = state (table)
    // [SP-2] = initial key
    // But we need to capture these into variables

    // ---------------------------------------------------------------------
    // STEP 2.5: Store iterator results in local variables
    // ---------------------------------------------------------------------
    char iter_func_var[64], state_var[64], key_var[64];
    snprintf(iter_func_var, sizeof(iter_func_var), "__for_iter_%d", label_id);
    snprintf(state_var, sizeof(state_var), "__for_state_%d", label_id);
    snprintf(key_var, sizeof(key_var), "__for_key_%d", label_id);

    // Register locals
    register_local(iter_func_var);
    register_local(state_var);
    register_local(key_var);

    char access_iter[128], access_state[128], access_key[128];

    get_variable_access_string(iter_func_var, access_iter);
    get_variable_access_string(state_var, access_state);
    get_variable_access_string(key_var, access_key);

    // Store iterator function (R0)
    emit_asm("MOV %s, R0         ; Store iterator function\n", access_iter);

    // Pop state from stack (should be at [SP-1] relative to current SP)
    emit_asm("MOV R0, [SP-1]     ; Load state\n");
    emit_asm("MOV %s, R0         ; Store state\n", access_state);

    // Pop initial key from stack (should be at [SP-2])
    emit_asm("MOV R0, [SP-2]     ; Load initial key\n");
    emit_asm("MOV %s, R0         ; Store initial key\n", access_key);
    emit_asm("IADD SP, 2         ; Clean up 2 stack values\n");

    // FIX 2: Now that we've stored the loop control values in stack locals,
    // we can UNPIN the registers we used for setup. The values are safe in
    // the stack variables, so we don't need to keep them in registers.
    unlock_pinned_register(iter_reg);
    unlock_pinned_register(state_reg);
    unlock_pinned_register(key_reg);

    // ---------------------------------------------------------------------
    // STEP 3: Create local variables for loop vars
    // ---------------------------------------------------------------------
    ASTNode *var = node->as.for_generic.var_list;
    char **var_names = NULL;
    SymbolNode **var_syms = NULL;   // NEW: keep the symbols, not just names
    int var_count = 0;

    ASTNode *curr = var;
    while (curr != NULL) {
        var_count++;
        curr = curr->next;
    }

    var_names = (char **)malloc(var_count * sizeof(char *));
    var_syms  = (SymbolNode **)malloc(var_count * sizeof(SymbolNode *));   // NEW
    curr = var;
    for (int i = 0; i < var_count && curr != NULL; i++) {
        var_names[i] = curr->as.id.name;
        var_syms[i]  = register_local(var_names[i]);   // NEW: capture the symbol
        curr = curr->next;
    }

    // ---------------------------------------------------------------------
    // STEP 4: Loop start label
    // ---------------------------------------------------------------------
    emit_asm("%s:\n", start_label);

    // ---------------------------------------------------------------------
    // STEP 5: Check if key is nil (end of iteration)
    // ---------------------------------------------------------------------
    // FIX 2: Use a temporary register for the check, don't pin it
    int check_reg = allocate_register();
    mark_register_live(check_reg, 5);

    get_variable_access_string(key_var, access_key);
    emit_asm("MOV R%d, %s        ; Load current key\n", check_reg, access_key);
    emit_falsy_jump(check_reg, end_label);
    unlock_register(check_reg);

    // ---------------------------------------------------------------------
    // STEP 6: Assign loop variables from iterator results
    // Call: iterator_func(state, current_key)
    // ---------------------------------------------------------------------
    // FIX 2: Temporarily unpin any loop-related registers before evaluating body
    // This allows the body to reuse registers without causing exhaustion
    //
    // Save current pinning state for loop control registers
    int saved_pinned[NUM_GPRS];
    for (int i = 0; i < NUM_GPRS; i++) {
        saved_pinned[i] = register_pinned[i];
    }

    // Unpin all registers temporarily for body evaluation
    for (int i = 0; i < NUM_GPRS; i++) {
        register_pinned[i] = 0;
    }

    // Push arguments for iterator call: state, current_key
    int arg_reg = allocate_register();
    mark_register_live(arg_reg, 2);

    get_variable_access_string(state_var, access_state);
    emit_asm("MOV R%d, %s           ; Load state into register\n", arg_reg, access_state);
    emit_asm("PUSH R%d               ; Arg 2: state\n", arg_reg);

    get_variable_access_string(key_var, access_key);
    emit_asm("MOV R%d, %s           ; Load current key into register\n", arg_reg, access_key);
    emit_asm("PUSH R%d               ; Arg 1: current key\n", arg_reg);

    unlock_register(arg_reg);

    // Call iterator function
    get_variable_access_string(iter_func_var, access_iter);
    emit_asm("MOV R0, %s        ; Load iterator function\n", access_iter);
    emit_asm("CALL R0            ; Call iterator(state, key)\n");
    emit_asm("IADD SP, 2         ; Clean up 2 arguments\n");

    // R0 now contains the new key (or nil if done)
    // Results are on stack: [SP-0] = new_key, [SP-1] = value1, [SP-2] = value2, ...

    // Store new key for next iteration
    emit_asm("MOV %s, R0        ; Save new key for next iteration\n", access_key);

    // Assign loop variables from stack
    for (int i = 0; i < var_count && i < 3; i++) {
        char var_access[128];
        get_variable_access_string(var_names[i], var_access);

        // Pop value from stack (values are pushed in order: key, val1, val2...)
        emit_asm("MOV R0, [SP-%d]     ; Load value %d from stack\n", i, i);
        emit_asm("MOV %s, R0        ; Assign to loop variable '%s'\n",
                 var_access, var_names[i]);
    }

    // Clean up iterator results from stack
    emit_asm("IADD SP, %d       ; Clean up %d values from stack\n",
             var_count > 0 ? var_count : 1, var_count > 0 ? var_count : 1);

    // ---------------------------------------------------------------------
    // STEP 7: Execute Loop Body
    // ---------------------------------------------------------------------
    // FIX 2: Body is evaluated with unpinned registers, allowing it to
    // reuse registers that were previously pinned for loop control
    push_scope();
    generate_block(node->as.for_generic.body);
    pop_scope();

    // Jump back to start
    emit_asm("JMP %s\n", start_label);

    // ---------------------------------------------------------------------
    // STEP 8: Loop end label
    // ---------------------------------------------------------------------
    emit_asm("%s:\n", end_label);

    // Restore pinning state after loop body
    for (int i = 0; i < NUM_GPRS; i++) {
        register_pinned[i] = saved_pinned[i];
    }

    // Clean up
    pop_loop();
    pop_scope();

    if (var_names != NULL) {
        free(var_names);
    }
}
