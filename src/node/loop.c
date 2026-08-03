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
// Registers used:
//   - scratch: Temporary for evaluating start/limit/step expressions
//   - r_idx, r_lim: For loop condition comparison
//   - r_calc, r_st: For index increment calculation
//   - r_step: For dynamic step sign checking (only if step is not static)
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

    // Generate unique names for loop control variables
    char limit_var[64], step_var[64], index_var[64];
    snprintf(limit_var, sizeof(limit_var), "__limit_%d", label_id);
    snprintf(step_var, sizeof(step_var), "__step_%d", label_id);
    strcpy(index_var, node->as.for_numeric.index_name);

    // Access strings for stack frame references
    char access_limit[128], access_step[128], access_index[128];

    // -------------------------------------------------------------------------
    // STEP 2: Evaluate loop bounds and store as stack locals
    // -------------------------------------------------------------------------
    int scratch = allocate_register();
    // ✅ Short-lived: used for evaluating start/limit/step, then freed
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
        // Default step of 1.0
        is_static_step = 1;
        static_step_val = 1.0;
        emit_asm("MOV R%d, 1.000000 ; Default step = 1.0", scratch);
    } else if (node->as.for_numeric.step_expr->type == NODE_NUMBER) {
        // Compile-time constant step - optimize condition checking
        is_static_step = 1;
        static_step_val = node->as.for_numeric.step_expr->as.number.val;
        emit_asm("MOV R%d, %f ; Static step value", scratch, static_step_val);
    } else {
        // Dynamic step expression - must evaluate at runtime
        generate_asm(node->as.for_numeric.step_expr, scratch);
    }

    register_local(step_var);
    get_variable_access_string(step_var, access_step);
    emit_asm("MOV %s, R%d ; Save loop step to stack", access_step, scratch);

    // Evaluate and store INDEX (start value)
    generate_asm(node->as.for_numeric.start_expr, scratch);
    register_local(index_var);
    get_variable_access_string(index_var, access_index);
    emit_asm("MOV %s, R%d ; Initialize loop index", access_index, scratch);

    // Done with scratch register
    unlock_register(scratch);

    // -------------------------------------------------------------------------
    // STEP 3: Setup loop tracking for break statements
    // -------------------------------------------------------------------------
    push_loop(label_id, LOOP_TYPE_FOR_NUMERIC);

    // Loop start label
    emit_asm("%s:\n", start_label);

    // -------------------------------------------------------------------------
    // STEP 4: Loop condition check
    // -------------------------------------------------------------------------
    int r_idx = allocate_register();
    int r_lim = allocate_register();

    // ✅ These registers are used for condition check - medium liveness
    mark_register_live(r_idx, 5);
    mark_register_live(r_lim, 5);

    // Load index and limit from stack into registers
    emit_asm("MOV R%d, %s", r_idx, access_index);
    emit_asm("MOV R%d, %s", r_lim, access_limit);

    if (is_static_step) {
        // =================================================================
        // OPTIMIZED PATH: Step direction known at compile time
        // =================================================================
        ensure_in_register(r_idx);
        ensure_in_register(r_lim);

        if (static_step_val >= 0.0) {
            // Positive step: loop while index <= limit
            emit_asm("FGT R%d, R%d ; Check if index > limit (exit condition)", r_idx, r_lim);
        } else {
            // Negative step: loop while index >= limit
            emit_asm("FLT R%d, R%d ; Check if index < limit (exit condition)", r_idx, r_lim);
        }
        emit_asm("JT R%d, %s ; Jump to end if loop condition fails", r_idx, end_label);
    } else {
        // =================================================================
        // DYNAMIC PATH: Step direction determined at runtime
        // =================================================================
        int r_step = allocate_register();
        // ✅ Short-lived: only used for sign check
        mark_register_live(r_step, 3);

        emit_asm("MOV R%d, %s", r_step, access_step);
        ensure_in_register(r_idx);
        ensure_in_register(r_lim);

        char pos_lbl[128], chk_lbl[128];
        snprintf(pos_lbl, sizeof(pos_lbl), "__%s_for_pos_%d", ctx, label_id);
        snprintf(chk_lbl, sizeof(chk_lbl), "__%s_for_chk_%d", ctx, label_id);

        // Check if step is positive or negative
        emit_asm("FGE R%d, 0.000000 ; Check if step >= 0", r_step);
        emit_asm("JT R%d, %s ; Jump if step is positive", r_step, pos_lbl);

        // Negative step path: check if index < limit
        emit_asm("FLT R%d, R%d ; index < limit?", r_idx, r_lim);
        emit_asm("JMP %s ; Jump to check", chk_lbl);

        // Positive step path: check if index > limit
        emit_asm("%s:\n", pos_lbl);
        emit_asm("FGT R%d, R%d ; index > limit?", r_idx, r_lim);

        // Common check: if condition is true, exit loop
        emit_asm("%s:\n", chk_lbl);
        emit_asm("JT R%d, %s ; Exit if condition met", r_idx, end_label);

        unlock_register(r_step);
    }

    // Done with condition registers
    unlock_register(r_idx);
    unlock_register(r_lim);

    // -------------------------------------------------------------------------
    // STEP 5: Execute loop body
    // -------------------------------------------------------------------------
    generate_block(node->as.for_numeric.body);

    // -------------------------------------------------------------------------
    // STEP 6: Increment index and loop back
    // -------------------------------------------------------------------------
    int r_calc = allocate_register();
    int r_st = allocate_register();

    // ✅ Short-lived: only used for increment calculation
    mark_register_live(r_calc, 2);
    mark_register_live(r_st, 2);

    // Load current index and step
    emit_asm("MOV R%d, %s", r_calc, access_index);
    emit_asm("MOV R%d, %s", r_st, access_step);

    // Ensure both are in registers (load from stack if spilled)
    ensure_in_register(r_calc);
    ensure_in_register(r_st);

    // Increment: index = index + step
    emit_asm("FADD R%d, R%d ; index += step", r_calc, r_st);

    // Store result back to stack
    emit_asm("MOV %s, R%d ; Update loop index on stack", access_index, r_calc);

    // Clean up increment registers
    unlock_register(r_calc);
    unlock_register(r_st);

    // Jump back to condition check
    emit_asm("JMP %s ; Loop back to condition", start_label);

    // Loop end label
    emit_asm("%s:\n", end_label);

    // -------------------------------------------------------------------------
    // STEP 7: Clean up loop context
    // -------------------------------------------------------------------------
    pop_loop ();
    pop_scope ();
}
