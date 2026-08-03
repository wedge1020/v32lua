#include "v32lua.h"

// Allocate storage for the global variables exactly once
int  o_optflag  = 0; // by default, no compiler optimizations take place
bool g_debug_mode = false;
const char *g_asm_filename = NULL;
const char *g_lua_filename = NULL;
int g_temp_asm_line        = 0;      // Adjust buffer size to match your project's original size
int g_current_lua_line = 0;
char g_current_label[256];      // Adjust buffer size to match your project's original size
FILE *temp_debug_stream = NULL;

// Private to this module; cannot be accidentally modified by other files
FILE *active_out_stream = NULL;

/* Sets the target stream for compilation output */
void  set_output_stream (FILE* stream)
{
    active_out_stream  = stream;
}

/* Returns the current output stream, safely falling back to stdout if none is set */
FILE *out (void)
{
    if (active_out_stream == NULL)
    {
        // Safe fallback: allows debug runs without -o to still print to the console
        return (stdout);
    }
    return (active_out_stream);
}

/* Closes the stream if open and resets the internal pointer */
void  close_output_stream (void)
{
    if ((active_out_stream != NULL) &&
        (active_out_stream != stdout))
       {
        fclose (active_out_stream);
        active_out_stream   = NULL;
    }
}

// --- Columnar & Peephole Optimizer State ---
char last_emitted_inst[32]   = "";
char last_emitted_dest[128] = "";
char last_emitted_src[128]  = "";

void trim_spaces(char *str) {
    int len = strlen(str);
    while (len > 0 && (str[len-1] == ' ' || str[len-1] == '\t' || str[len-1] == '\r' || str[len-1] == '\n')) {
        str[len-1] = '\0';
        len--;
    }
    int start = 0;
    while (str[start] == ' ' || str[start] == '\t') start++;
    if (start > 0) memmove(str, str + start, strlen(str + start) + 1);
}

// Recursively flattens an AST chain like table_get(table_get("ioports", "gpu"), "clear")
// into a flat C string "ioports.gpu.clear". Returns 1 if successful, 0 if dynamic.
int resolve_static_path(ASTNode* node, char* path_buffer) {
    if (!node)
    {
        fprintf (stderr, "[resolve_static_path] node is NULL\n");
        return 0;
    }

    if (node->type == NODE_IDENTIFIER) {
        strcpy(path_buffer, node->as.id.name);
        return (1);
    }

    if (node->type == NODE_TABLE_GET && node->as.table_get.key->type == NODE_STRING) {
        char base_path[256] = {0};
        if (resolve_static_path(node->as.table_get.table_expr, base_path)) {
            sprintf(path_buffer, "%s.%s", base_path, node->as.table_get.key->as.string_val.value);
            return (1);
        }
    }
    
    return 0;
}

int get_expected_arity(ASTNode *target) {
    if (!target) return -1;

    // 1. Direct function call: foo(1, 2)
    if (target->type == NODE_IDENTIFIER) {
        SymbolNode *sym = resolve_symbol(target->as.id.name);
        if (sym && sym->is_function) {
            return sym->arity;
        }
    }

    // 2. Method or static table call: player:draw() -> resolves to "player.draw"
    char path_buf[256] = {0};
    if (resolve_static_path(target, path_buf)) {
        // First, try direct lookup
        SymbolNode *sym = resolve_symbol(path_buf);
        if (sym && sym->is_function) {
            return sym->arity;
        }

        // NEW: Try mangled lookup by converting '.' and ':' to '_'
        char mangled_buf[256];
        strncpy(mangled_buf, path_buf, sizeof(mangled_buf) - 1);
        mangled_buf[sizeof(mangled_buf) - 1] = '\0';

        for (int i = 0; mangled_buf[i] != '\0'; i++) {
            if (mangled_buf[i] == '.' || mangled_buf[i] == ':') {
                mangled_buf[i] = '_';
            }
        }

        sym = resolve_symbol(mangled_buf);
        if (sym && sym->is_function) {
            return sym->arity;
        }
    }

    return -1;
}

int count_function_locals(ASTNode* node) {
    int count = 0;

    // Traverse sibling statements in the current block
    while (node != NULL) {
        switch (node->type) {
            case NODE_MULTIPLE_ASSIGNMENT:
                // Check if this assignment is a local declaration
                if (node->as.mult_assign.is_local) {
                    // Count how many variables are in the target list
                    ASTNode* target = node->as.mult_assign.targets_head;
                    while (target != NULL) {
                        count++;
                        target = target->next;
                    }
                }
                break;

            case NODE_IF: {
                // Recurse into both branches of an IF statement
                int  max       = 0;
                int  tmpcount  = 0;
                max            = count_function_locals (node -> as.if_stmt.if_body);
                tmpcount       = count_function_locals (node -> as.if_stmt.else_body);
                if (tmpcount  >  max)
                {
                    max        = tmpcount;
                }
                count          = count + max;
                break;
            }

            case NODE_WHILE:
                // Recurse into WHILE loop bodies
                count += count_function_locals(node->as.while_loop.body);
                break;

            case NODE_FOR_NUMERIC:
                // Adds 3 to the stack requirement frame frame (+1 index, +1 limit, +1 step)
                count += 3 + count_function_locals(node->as.for_numeric.body);
                break;

            case NODE_FUNCTION_DEF:
                // CRITICAL BOUNDARY: Do NOT recurse into nested function definitions!
                // Any locals inside a closure/nested function belong to THAT function's 
                // stack frame, not our current enclosing function.
                break;

            default:
                break;
        }

        node = node->next; // Move to the next statement in the block
    }

    return count;
}

int check_needs_stack (ASTNode *node)
{
    if (node  == NULL)
    {
        return (0);
    }

    switch (node -> type) {
        case NODE_FOR_NUMERIC:
        case NODE_CONCAT:
        case NODE_TABLE_SET:
        case NODE_TABLE_GET:
        case NODE_ASM:
        case NODE_RAWASM:
            return (1);

        case NODE_FUNCTION_CALL: {
            // If it's a compile-time intrinsic like hex(), it doesn't need stack space!
            if (node -> as.call.target -> type == NODE_IDENTIFIER) {
                const char *name = node -> as.call.target -> as.id.name;
                if (strcmp (name, "hex") == 0) {
                    return 0; // Leaf intrinsic: no stack required
                }
            }
            return (1); // Standard function call: stack required
        }

        case NODE_IDENTIFIER:
            if (node->as.id.name && strcmp(node->as.id.name, "self") == 0) return (1);
            break;

        case NODE_RETURN: {
            int ret_count = 0;
            ASTNode *expr = node->as.return_stmt.expressions_head;
            while (expr) {
                ret_count++;
                if (check_needs_stack(expr)) return (1);
                expr = expr->next;
            }
            if (ret_count > 3) return (1);
            break;
        }

        case NODE_WHILE:
            if (check_needs_stack(node->as.while_loop.condition)) return (1);
            if (check_needs_stack(node->as.while_loop.body)) return (1);
            break;

        case NODE_IF:
            if (check_needs_stack (node -> as.if_stmt.condition)) return (1);
            if (check_needs_stack (node -> as.if_stmt.if_body))   return (1);
            if (check_needs_stack (node -> as.if_stmt.else_body)) return (1);
            //fprintf (stderr, "[IF] stack check: doesn't need one\n");
            break;

        case NODE_MULTIPLE_ASSIGNMENT: {
            ASTNode* curr_tgt = node->as.mult_assign.targets_head;
            while (curr_tgt) { if (check_needs_stack(curr_tgt)) return (1); curr_tgt = curr_tgt->next; }
            ASTNode* curr_val = node->as.mult_assign.values_head;
            while (curr_val) { if (check_needs_stack(curr_val)) return (1); curr_val = curr_val->next; }
            break;
        }

        case NODE_ADD:
        case NODE_SUB:
        case NODE_MUL:
        case NODE_DIV:
        case NODE_MOD:
        case NODE_AND:
        case NODE_OR:
        case NODE_RELATIONAL:
            if (check_needs_stack(node->as.binary.left))  return (1);
            if (check_needs_stack(node->as.binary.right)) return (1);
            break;

        default:
            break;
    }

    return check_needs_stack (node -> next);
}

void generate_block(ASTNode *head) {
    ASTNode *current = head;
    while (current != NULL) {
        // Only allocate if the statement needs a result register
        if (current->type != NODE_BREAK && current->type != NODE_RETURN) {
            int temp_reg = allocate_register();

			// ✅ Mark as live for this statement
            mark_register_live (temp_reg, 1);

            generate_asm(current, temp_reg);
            unlock_register(temp_reg);
        } else {
            // Statements that don't produce values
            generate_asm(current, 0);  // Pass 0 to indicate no dest_reg needed
        }
        current = current->next;
    }
}

void  generate_asm (ASTNode *node, int  dest_reg)
{
    if (node                    != NULL)
    {
        // Automatically synchronize the tracker with the current AST element's source line
        if (g_debug_mode) {
            g_current_lua_line = node->line_number; // Assumes your parser sets node->line_number
        }

        switch (node -> type)
        {
            case NODE_WHILE: {
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
                break;
            }

			case NODE_FOR_NUMERIC: {
				// =========================================================================
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
				// =========================================================================

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
				pop_loop();
				pop_scope();
				break;
			}

            case NODE_BREAK: {
                int current_id = current_loop();
                if (current_id == -1) {
                    fprintf(stderr, "Compiler Runtime Error: 'break' declaration found outside loop.\n");
                    exit(1);
                }

                LoopType type = current_loop_type();
                const char* prefix = (type == LOOP_TYPE_FOR_NUMERIC) ? "for" : "while";
                emit_asm("JMP __%s_%s_end_%d\n", get_current_function_name(), prefix, current_id);
                break;
            }

            case NODE_IF: {
                int         cond_reg  = allocate_register ();
                int         label_id  = get_next_label ();
                const char *ctx       = get_current_function_name ();
                char        else_label[128], end_label[128];
                snprintf(else_label, sizeof(else_label), "__%s_else_%d", ctx, label_id);
                snprintf(end_label, sizeof(end_label), "__%s_end_if_%d", ctx, label_id);

				// ✅ Used for condition check
				mark_register_live (cond_reg, 2);
                
                generate_asm (node -> as.if_stmt.condition, cond_reg);
                
                // AUDITED: Jump to else/end if the condition is Nil or False!
                emit_falsy_jump (cond_reg, else_label);
                unlock_register (cond_reg);
                
                push_scope ();
                generate_block (node -> as.if_stmt.if_body);
                pop_scope ();
                
                emit_asm ("JMP %s\n", end_label);
                emit_asm ("%s:\n", else_label);
            
                if (node -> as.if_stmt.else_body)
                {
                    push_scope ();
                    generate_block (node -> as.if_stmt.else_body);
                    pop_scope ();
                }
                emit_asm ("%s:\n", end_label);
                break;
            }

            case NODE_FUNCTION_DEF: {
                const char *func_name = node->as.function_def.name;
                push_function_context(func_name);

                if (g_debug_mode) {
                    snprintf(g_current_label, sizeof(g_current_label), "func_%s", func_name);
                }

                emit_asm("__function_%s:\n", func_name);

                // --- OPTIMIZATION: Check eligibility for Frame Pointer Omission ---
                int num_locals = count_function_locals(node->as.function_def.body);
				emit_asm("PUSH BP\n");
				emit_asm("MOV BP, SP\n");

				reset_spill_slots(-(num_locals + 1));
				int total_stack = num_locals + NUM_GPRS;
				if (total_stack > 0) {
					emit_asm("ISUB SP, %d ; Reserve stack for locals + spills\n", total_stack);
				}

				// ✅ CRITICAL FIX: Initialize spill slots AFTER local variables
				//reset_spill_slots(-(num_locals + NUM_GPRS));  // ✅ Initialize spill slots AFTER locals
                push_scope();

                // =============================================================
                // PARAMETER TRAVERSAL:
                // Arity is already safely stored on the symbol from Stage 4!
                // We only need to map parameters to stack offsets [BP + 2], etc.
                // =============================================================
                int param_offset = 2;
                ASTNode *p = node->as.function_def.params;
                while (p != NULL) {
                    if (p->type == NODE_IDENTIFIER) {
                        register_parameter(p->as.id.name, param_offset++);
                    }
                    p = p->next;
                }
                // =============================================================

                generate_block(node->as.function_def.body);
                pop_scope();

                // --- Function Epilogue ---
                emit_asm("__%s_return:\n", func_name);
				emit_asm("MOV SP, BP\n");
				emit_asm("POP BP\n");
                emit_asm("RET\n");
                emit_asm("\n");

                pop_function_context();
                break;
            }

            case NODE_UNARY: {
                // Evaluate the operand into dest_reg
                generate_asm(node->as.unary.operand, dest_reg);
                
                if (node->as.unary.operator == OP_LEN) {
                    // Push the operand to the stack
                    emit_asm ("PUSH R%d\n", dest_reg);
                    
                    // Call the built-in
                    emit_asm ("CALL __builtin_len\n");
                    
                    // Clean up the stack
                    emit_asm ("IADD SP, 1\n");
                    
                    // Move the returned length into the destination register
                    emit_asm ("MOV R%d, R0\n", dest_reg);

                }
                else if (node->as.unary.operator == OP_NOT) {
                    int label_id = get_next_label();
                    const char *ctx = get_current_function_name(); // Fetch context
                    char to_true_label[128], end_label[128];
                    snprintf(to_true_label, sizeof(to_true_label), "__%s_not_true_%d", ctx, label_id); // Prefix added
                    snprintf(end_label, sizeof(end_label), "__%s_not_end_%d", ctx, label_id);         // Prefix added
                    int  scratch_reg  = allocate_register ();

					// ✅ Short-lived scratch
					mark_register_live(scratch_reg, 2);

                    ensure_in_register(dest_reg);  // Reload dest_reg if it was spilled by allocate_register()

                    // 1. Check if Nil or False using scratch register
                    emit_asm("MOV R%d, R%d\n", scratch_reg, dest_reg);
                    emit_asm("IEQ R%d, BOXED_NIL ; Is Nil?\n", scratch_reg);
                    emit_asm("JT  R%d, %s\n", scratch_reg, to_true_label);
                    emit_asm("MOV R%d, R%d\n", scratch_reg, dest_reg);
                    emit_asm("IEQ R%d, BOXED_FALSE ; Is False?\n", scratch_reg);
                    emit_asm("JT  R%d, %s\n", scratch_reg, to_true_label);

                    // 2. If truthy, return BOXED_FALSE
                    emit_asm("MOV R%d, BOXED_FALSE ; Return False\n", dest_reg);
                    emit_asm("JMP %s\n", end_label);

                    // 3. If falsy, return BOXED_TRUE
                    emit_asm("%s:\n", to_true_label);
                    emit_asm("MOV R%d, BOXED_TRUE ; Return True\n", dest_reg);
                    emit_asm("%s:\n", end_label);
                    unlock_register (scratch_reg);
                }
                else if (node -> as.unary.operator == OP_UNM) {
                    emit_asm ("PUSH R%d\n", dest_reg);
                    emit_asm ("CALL __builtin_unm\n");
                    emit_asm ("IADD SP, 1\n");
                    emit_asm ("MOV R%d, R0\n", dest_reg);
                }
                break;
            }
                             
            case NODE_MULTIPLE_ASSIGNMENT: {
                ASTNode *curr_tgt = node->as.mult_assign.targets_head;
                ASTNode *curr_val = node->as.mult_assign.values_head;
                int      val_reg  = -1;

                // --- Intercept Bare Local Declarations (e.g., "local x, y") ---
                if (node->as.mult_assign.is_local && node->as.mult_assign.values_head == NULL) {
                    while (curr_tgt != NULL) {
                        if (curr_tgt->type == NODE_IDENTIFIER) {
                            // Register local symbol and initialize to canonical Nil (BOXED_NIL)
                            SymbolNode *sym = register_local(curr_tgt->as.id.name);
                            char access_str[128];
                            get_variable_access_string(sym->name, access_str);

                            emit_asm("    ;; Bare local '%s' initialized to nil", sym->name);
                            emit_asm("MOV %s, BOXED_NIL", access_str);
                        }
                        curr_tgt = curr_tgt->next;
                    }
                    break;
                }

                // --- Standard & Multiple Assignment Evaluation ---
                while (curr_tgt != NULL) {
                    // =========================================================================
                    // 1. ATTEMPT HARDWARE INTRINSIC FIRST (Immediate Folding / Lazy Evaluation)
                    // =========================================================================
                    // Only check if we are targeting a table property AND have a valid value node
                    if (curr_tgt->type == NODE_TABLE_GET && curr_val != NULL) {
                        if (try_emit_table_set_intrinsic(curr_tgt->as.table_get.table_expr,
                                                         curr_tgt->as.table_get.key,
                                                         curr_val))
                        {
                            // Intrinsic successfully emitted (either folded to immediate or 
                            // evaluated on-demand)! Advance pointers and skip standard allocation.
                            curr_tgt = curr_tgt->next;
                            curr_val = curr_val->next;
                            continue;
                        }
                    }

                    // =========================================================================
                    // 2. STANDARD EVALUATION (Identifiers, Fallback Dynamic Tables, or Nils)
                    // =========================================================================
                    val_reg = allocate_register();

					// ✅ Value register used immediately for assignment
					mark_register_live(val_reg, 1);

                    if (curr_val != NULL) {
                        // Evaluate the right-hand expression into our temporary register
                        generate_asm(curr_val, val_reg);
                        curr_val = curr_val->next;
                    } else {
                        // Lua rule: If values run out, remaining targets are assigned nil
                        emit_asm("MOV R%d, BOXED_NIL ; Pad missing value with Nil", val_reg);
                    }

                    ensure_in_register(val_reg);

                    // Assign evaluated value to the target
                    if (curr_tgt->type == NODE_IDENTIFIER) {
                        if (node->as.mult_assign.is_local) {
                            register_local(curr_tgt->as.id.name);
                        }
                        char access_str[128];
                        get_variable_access_string(curr_tgt->as.id.name, access_str);
                        emit_asm("MOV %s, R%d", access_str, val_reg);
                    }
                    else if (curr_tgt->type == NODE_TABLE_GET)
                    {
                        // Fallback: Dynamic heap table assignment (table[key] = value)
                        int table_reg = allocate_register();
                        int key_reg   = allocate_register();

                        generate_asm(curr_tgt->as.table_get.table_expr, table_reg);
                        generate_asm(curr_tgt->as.table_get.key, key_reg);

                        emit_asm("PUSH R%d ; Push Table Pointer", table_reg);
                        emit_asm("PUSH R%d ; Push Key", key_reg);
                        emit_asm("PUSH R%d ; Push Value", val_reg);
                        emit_asm("CALL __builtin_table_set");
                        emit_asm("IADD SP, 3 ; Clean up stack");

                        unlock_register(table_reg);
                        unlock_register(key_reg);
                    }

                    unlock_register(val_reg);
                    curr_tgt = curr_tgt->next;
                }
                break;
            }

            case NODE_IDENTIFIER: {
                ////////////////////////////////////////////////////////////////////////
                //
                // NEW: Dynamically lookup identifier location
                //
                char  var_access[256];
                get_variable_access_string (node -> as.id.name, var_access);
                emit_asm ("MOV R%d, %s\n", dest_reg, var_access);
                break;
            }

			case NODE_FUNCTION_CALL: {
				// =========================================================================
				// FUNCTION CALL: f(x, y, z) or obj:method(a, b)
				//
				// Strategy:
				//   1. Try hardware/builtin intrinsic first (fast path)
				//   2. Resolve target function (direct or method call)
				//   3. Evaluate and push arguments right-to-left (C ABI convention)
				//   4. Push implicit 'self' for method calls (last, so it's at [BP+2])
				//   5. Execute call and handle return value
				//
				// Registers used:
				//   - target_reg: Function pointer (PINNED during arg evaluation)
				//   - table_reg: Table for method calls (spilled after lookup)
				//   - arg_reg: Temporary for each argument evaluation
				//   - pad_reg: For padding missing arguments
				// =========================================================================

				// -------------------------------------------------------------------------
				// STEP 0: Hardware & Builtin Intrinsic Fast Path
				// -------------------------------------------------------------------------
				// Check if this call can be handled as a compile-time intrinsic
				if (try_emit_call_intrinsic(node, dest_reg)) {
					break; // Intrinsic handled - skip standard call generation
				}

				// -------------------------------------------------------------------------
				// STEP 0.5: FFI Integration - Check for C Native Functions
				// -------------------------------------------------------------------------
				SymbolNode *target_sym = NULL;

				// Resolve the target symbol
				if (node->as.call.target->type == NODE_IDENTIFIER) {
					// Direct function call: foo()
					target_sym = resolve_symbol(node->as.call.target->as.id.name);
				} else {
					// Method or table call: obj:method() or obj.method()
					char path_buf[256] = {0};
					if (resolve_static_path(node->as.call.target, path_buf)) {
						target_sym = resolve_symbol(path_buf);
						if (!target_sym) {
							// Try mangled lookup: convert '.' and ':' to '_'
							for (int i = 0; path_buf[i] != '\0'; i++) {
								if (path_buf[i] == '.' || path_buf[i] == ':') {
									path_buf[i] = '_';
								}
							}
							target_sym = resolve_symbol(path_buf);
						}
					}
				}

				// Determine if this is a C ABI call (FFI)
				bool is_c_call = (target_sym != NULL && target_sym->is_c_native == 1);

				// -------------------------------------------------------------------------
				// STEP 1: Allocate and Pin Target Register
				// -------------------------------------------------------------------------
				int total_arg_count = 0;
				int target_reg = allocate_register();
				int table_reg = -1; // Only used for method calls

				// 🔒 CRITICAL: Pin target_reg to prevent spilling during argument evaluation
				//    This ensures the function pointer stays valid while we push arguments
				register_pinned[target_reg] = 1;

				// ✅ Mark as live for the duration of call setup
				mark_register_live(target_reg, 10);

				// -------------------------------------------------------------------------
				// STEP 1.5: Resolve Target Function Pointer & Cache 'self'
				// -------------------------------------------------------------------------
				if (node->as.call.is_method_call) {
					// Method call: obj:method() - need to resolve method and cache 'self'
					emit_asm("    ; --- Method call: resolve target and cache 'self' ---\n");

					ASTNode *table_get_node = node->as.call.target;
					table_reg = allocate_register();
					int key_reg = allocate_register();

					// ✅ Short-lived registers for lookup
					mark_register_live(table_reg, 5);
					mark_register_live(key_reg, 2);

					// Evaluate table expression (the object)
					generate_asm(table_get_node->as.table_get.table_expr, table_reg);

					// Evaluate method key
					generate_asm(table_get_node->as.table_get.key, key_reg);

					// Ensure both are in registers (may have been spilled)
					ensure_in_register(table_reg);
					ensure_in_register(key_reg);

					// Try hardware intrinsic for table get first
					if (!try_emit_table_get_intrinsic(
							table_get_node->as.table_get.table_expr,
							table_get_node->as.table_get.key,
							target_reg)) {
						// Fallback: Runtime table lookup
						emit_asm("PUSH R%d ; Arg1: Table pointer for method lookup\n", table_reg);
						emit_asm("PUSH R%d ; Arg2: Method key\n", key_reg);
						emit_asm("CALL __builtin_table_get\n");
						emit_asm("IADD SP, 2 ; Clean up lookup arguments\n");
						emit_asm("MOV R%d, R0 ; Store retrieved method pointer\n", target_reg);
					}

					// Clean up key register
					unlock_register(key_reg);

					// 🟡 Spill table_reg and target_reg to free registers for argument eval
					//    But keep them PINNED so they won't be reused
					spill_register(table_reg);
					spill_register(target_reg);
				} else {
					// Direct function call: foo() or module.func()
					if (!is_c_call) {
						// Standard Lua function - resolve target
						generate_asm(node->as.call.target, target_reg);
						// ✅ Spill it now so it doesn't block register allocation
						spill_register(target_reg);
					}
					// For C calls, target_reg is unused (we call by name)
				}

				// -------------------------------------------------------------------------
				// STEP 2: Evaluate & Push Explicit Arguments (Right-to-Left)
				// -------------------------------------------------------------------------
				// Count explicit arguments
				int explicit_arg_count = 0;
				ASTNode *curr = node->as.call.args_head;
				while (curr != NULL) {
					explicit_arg_count++;
					curr = curr->next;
				}

				// --- Handle Missing Arguments (Arity Padding) ---
				int actual_passed_count = explicit_arg_count +
										(node->as.call.is_method_call ? 1 : 0);
				int expected_arity = get_expected_arity(node->as.call.target);

				if (expected_arity > actual_passed_count) {
					int missing_args = expected_arity - actual_passed_count;
					emit_asm("    ; --- Padding %d omitted arguments ---\n",
							 missing_args, is_c_call ? "with 0 (C ABI)" : "with Nil");

					// Allocate register for padding value
					int pad_reg = allocate_register();
					// ✅ Short-lived: only used for padding
					mark_register_live(pad_reg, missing_args + 1);

					if (is_c_call) {
						emit_asm("MOV R%d, 0 ; C ABI default value\n", pad_reg);
					} else {
						emit_asm("MOV R%d, BOXED_NIL ; Lua Nil for missing args\n", pad_reg);
					}

					ensure_in_register(pad_reg);

					// Push padding values (rightmost args first)
					for (int i = 0; i < missing_args; i++) {
						emit_asm("PUSH R%d ; Pad omitted argument\n", pad_reg);
						total_arg_count++;
					}

					unlock_register(pad_reg);
				}

				// --- Push Explicit Arguments (Right-to-Left for C ABI) ---
				if (explicit_arg_count > 0) {
					// Allocate array for reverse traversal
					ASTNode **arg_array = (ASTNode **)malloc(sizeof(ASTNode *) * explicit_arg_count);
					if (arg_array == NULL) {
						compiler_error(ERR_INTERNAL, -1, "Out of memory for arg buffer");
					}

					// Collect arguments
					curr = node->as.call.args_head;
					for (int i = 0; i < explicit_arg_count; i++) {
						arg_array[i] = curr;
						curr = curr->next;
					}

					emit_asm("    ; --- Pushing explicit arguments Right-to-Left ---\n");

					// Push in reverse order: Arg N, Arg N-1, ..., Arg 1
					for (int i = explicit_arg_count - 1; i >= 0; i--) {
						int arg_reg = allocate_register();
						// ✅ Short-lived: used for one argument evaluation
						mark_register_live(arg_reg, 2);

						// Evaluate argument into register
						generate_asm(arg_array[i], arg_reg);

						// For C ABI, unbox the Lua value
						if (is_c_call) {
							emit_asm("    ; --- Unbox for C ABI ---\n");
							emit_asm("AND R%d, BOXED_PAYLOAD ; Strip NaN tag bits\n", arg_reg);
						}

						// Ensure register is loaded (may have been spilled by nested calls)
						ensure_in_register(arg_reg);

						// Push onto stack
						emit_asm("PUSH R%d\n", arg_reg);
						unlock_register(arg_reg);
						total_arg_count++;
					}

					free(arg_array);
				}

				// -------------------------------------------------------------------------
				// STEP 3: Push Implicit 'self' for Method Calls (LAST)
				// -------------------------------------------------------------------------
				if (node->as.call.is_method_call) {
					emit_asm("    ; --- Pushing implicit 'self' (Top of arg stack) ---\n");

					// ✅ Ensure table_reg is loaded from its spill slot
					ensure_in_register(table_reg);

					emit_asm("PUSH R%d ; Arg 1: self\n", table_reg);
					unlock_register(table_reg); // No longer needed
					total_arg_count++;
				}

				// -------------------------------------------------------------------------
				// STEP 4: Execute Call & Clean Up Stack
				// -------------------------------------------------------------------------
				if (is_c_call) {
					// --- Direct C ABI Call ---
					// For C calls, target_reg is unused (we call by symbol name)
					unlock_register(target_reg);
					register_pinned[target_reg] = 0; // Clear pin

					emit_asm("    ; --- Direct C ABI Call ---\n");
					emit_asm("CALL _%s ; Call C symbol directly\n", target_sym->name);

					// Caller cleanup for C ABI
					if (total_arg_count > 0) {
						emit_asm("IADD SP, %d ; C ABI caller cleanup\n", total_arg_count);
					}

					// Box return value back to Lua representation
					if (dest_reg != 0) {
						emit_asm("    ; --- Box C return value ---\n");
						emit_asm("MOV R%d, R0\n", dest_reg);
						emit_asm("OR R%d, 0x7FF00000 ; Apply Lua Number tag\n", dest_reg);
					}
				} else {
					// --- Lua Function Call (via __builtin_exec) ---

					// 🔓 UNPIN target_reg now that arguments are pushed
					register_pinned[target_reg] = 0;

					// ✅ Reload target_reg if it was spilled during argument evaluation
					if (target_reg != 0) {
						ensure_in_register(target_reg);
						emit_asm("MOV R0, R%d ; Prepare boxed target for validation\n", target_reg);
					}

					unlock_register(target_reg);

					// Call the Lua function executor (handles tag validation & tail-call)
					emit_asm("CALL __builtin_exec ; Validate and execute\n");

					// Clean up arguments from stack
					if (total_arg_count > 0) {
						emit_asm("IADD SP, %d ; Clean up call arguments\n", total_arg_count);
					}

					// Store return value if caller needs it
					if (dest_reg != 0) {
						emit_asm("MOV R%d, R0 ; Store return value\n", dest_reg);
					}
				}

				break;
			}

            case NODE_FUNCTION_POINTER: {
                emit_asm ("    ;; Load and box address of the mangled function\n");
                emit_asm ("MOV R%d, __function_%s\n", dest_reg, node -> as.func_ptr.mangled_name);
                // AUDITED: Apply Function NaN tag (Bit 31=1, Bit 22=0)
                emit_asm ("OR R%d, BOXED_FUNCTION ; Box as Function\n", dest_reg);
                break;
            }

            case NODE_RETURN: {
                ASTNode *expr = node -> as.return_stmt.expressions_head;
                int ret_idx = 0;
                int arg_count = node -> as.return_stmt.parent_func_arg_count;
                
                while (expr != NULL) {
                    int val_reg = allocate_register();
                    generate_asm (expr, val_reg);
                    
                    if (ret_idx == 0)      { emit_asm ("MOV R0, R%d\n", val_reg); }
                    else if (ret_idx == 1) { emit_asm ("MOV R2, R%d\n", val_reg); }
                    else if (ret_idx == 2) { emit_asm ("MOV R3, R%d\n", val_reg); }
                    else {
                        int offset = 2 + arg_count + (ret_idx - 3);
                        emit_asm ("MOV [BP + %d], R%d\n", offset, val_reg);
                    }
                    unlock_register(val_reg);
                    
                    ret_idx++;
                    expr = expr -> next;
                }
                emit_asm ("JMP __%s_return\n", get_current_function_name ());
                break;
            }

            case NODE_ADD: {
                generate_asm (node -> as.binary.left, dest_reg);
                int  right_reg  = allocate_register();  // May spill another value

				// ✅ Will be used immediately, short-lived
				mark_register_live (right_reg, 1);

                generate_asm (node -> as.binary.right, right_reg);

                // Ensure both are in registers (load from stack if spilled)
                ensure_in_register (dest_reg);
                ensure_in_register (right_reg);

                emit_asm("FADD R%d, R%d\n", dest_reg, right_reg);
                unlock_register(right_reg);
                break;
            }

            case NODE_MUL: {
                generate_asm (node -> as.binary.left, dest_reg);
                int  right_reg  = allocate_register ();

				// ✅ Will be used immediately, short-lived
				mark_register_live (right_reg, 1);

                generate_asm (node -> as.binary.right, right_reg);

                // Ensure both are in registers (load from stack if spilled)
                ensure_in_register (dest_reg);
                ensure_in_register (right_reg);

                emit_asm ("FMUL R%d, R%d\n", dest_reg, right_reg);
                unlock_register (right_reg);
                break;
            }

            case NODE_SUB: {
                generate_asm (node -> as.binary.left, dest_reg);
                int  right_reg  = allocate_register ();

				// ✅ Will be used immediately, short-lived
				mark_register_live (right_reg, 1);

                generate_asm (node -> as.binary.right, right_reg);

                // Ensure both are in registers (load from stack if spilled)
                ensure_in_register (dest_reg);
                ensure_in_register (right_reg);

                emit_asm ("FSUB R%d, R%d\n", dest_reg, right_reg);
                unlock_register (right_reg);
                break;
            }
        
            case NODE_DIV: {
                generate_asm (node -> as.binary.left, dest_reg);
                int  right_reg  = allocate_register ();

				// ✅ Will be used immediately, short-lived
				mark_register_live (right_reg, 1);

                generate_asm (node -> as.binary.right, right_reg);

                // Ensure both are in registers (load from stack if spilled)
                ensure_in_register (dest_reg);
                ensure_in_register (right_reg);

                emit_asm ("FDIV R%d, R%d\n", dest_reg, right_reg);
                unlock_register (right_reg);
                break;
            }

            case NODE_MOD: {
                generate_asm (node -> as.binary.left, dest_reg);
                int  right_reg  = allocate_register();

				// ✅ Will be used immediately, short-lived
				mark_register_live (right_reg, 1);

                generate_asm (node -> as.binary.right, right_reg);

                // Ensure both are in registers (load from stack if spilled)
                ensure_in_register (dest_reg);
                ensure_in_register (right_reg);

                // Cast to integers for modulo (Lua % uses integer division)
                emit_asm ("CFI R%d ; Cast left to int\n", dest_reg);
                emit_asm ("CFI R%d ; Cast right to int\n", right_reg);

                // Perform integer modulo
                emit_asm ("IMOD R%d, R%d\n", dest_reg, right_reg);

                // Cast result back to float (Lua numbers are floats)
                emit_asm ("CIF R%d ; Cast result back to float\n", dest_reg);

                unlock_register (right_reg);
                break;
            }

            case NODE_BOOLEAN:
                if (node -> as.boolean.val)
                {
                    emit_asm ("MOV R%d, BOXED_TRUE ; literal true\n",   dest_reg);
                }
                else
                {
                    emit_asm ("MOV R%d, BOXED_FALSE ; literal false\n", dest_reg);
                }
                break;

            case NODE_NIL:
                emit_asm ("MOV R%d, BOXED_NIL; the lua nil\n", dest_reg);
                break;

			case NODE_AND: {
				int         label_id        = get_next_label ();
				const char *ctx             = get_current_function_name ();
				char        end_label[128];

				snprintf (end_label, sizeof (end_label), "__%s_short_and_%d", ctx, label_id);

				// 1. Ensure dest_reg is available (may have been spilled)
				ensure_in_register (dest_reg);

				// 2. Evaluate Left Operand into dest_reg
				generate_asm (node -> as.binary.left, dest_reg);

				// 3. Short-circuit: if left is falsy, jump to end with falsy result
				emit_falsy_jump (dest_reg, end_label);

				// 4. Otherwise, evaluate Right Operand into dest_reg
				//    dest_reg still holds left value, but we overwrite it with right
				generate_asm (node -> as.binary.right, dest_reg);

				// 5. End label
				emit_asm ("%s:\n", end_label);

				break;
			}

			case NODE_OR: {
				int         label_id        = get_next_label ();
				const char *ctx             = get_current_function_name ();
				char        end_label[128];

				snprintf (end_label, sizeof (end_label), "__%s_short_or_%d", ctx, label_id);

				// 1. Ensure dest_reg is available (may have been spilled)
				ensure_in_register (dest_reg);

				// 2. Evaluate Left Operand into dest_reg
				generate_asm (node -> as.binary.left, dest_reg);

				// 3. Short-circuit: if left is truthy, jump to end with truthy result
				emit_truthy_jump (dest_reg, end_label);

				// 4. Otherwise, evaluate Right Operand into dest_reg
				//    dest_reg still holds left value, but we overwrite it with right
				generate_asm (node -> as.binary.right, dest_reg);

				// 5. End label
				emit_asm ("%s:\n", end_label);

				break;
			}

            case NODE_RELATIONAL: {
                generate_asm (node -> as.binary.left, dest_reg);
                int right_reg = allocate_register ();
                generate_asm (node -> as.binary.right, right_reg);

                ensure_in_register (dest_reg);
                ensure_in_register (right_reg);
                
                if (node -> as.binary.operator == OP_EQ || node -> as.binary.operator == OP_NEQ) {
                    emit_asm ("PUSH R%d\n", dest_reg);
                    emit_asm ("PUSH R%d\n", right_reg);
                    emit_asm ("CALL __builtin_eq\n");
                    emit_asm ("IADD SP, 2\n");
                    
                    if (node -> as.binary.operator == OP_NEQ) {
                        emit_asm ("MOV R%d, R0\n", dest_reg);
                        emit_asm ("IEQ R%d, 0 ; Invert to true if it was false\n", dest_reg);
                    } else {
                        emit_asm ("MOV R%d, R0\n", dest_reg);
                    }

                }
                else
                {
                    switch (node -> as.binary.operator) {
                        case OP_LT:  emit_asm ("FLT R%d, R%d\n", dest_reg, right_reg); break;
                        case OP_LE:  emit_asm ("FLE R%d, R%d\n", dest_reg, right_reg); break;
                        case OP_GT:  emit_asm ("FGT R%d, R%d\n", dest_reg, right_reg); break;
                        case OP_GE:  emit_asm ("FGE R%d, R%d\n", dest_reg, right_reg); break;
                        default: break;
                    }
                    emit_asm ("IADD R%d, BOXED_BOOLEAN ; Box as Lua Boolean (False/True)\n", dest_reg);
                }
                unlock_register (right_reg);
                break;
            }

            case NODE_STRING: {
                // Register the literal and get its ID
                //int str_id = add_string_literal (node -> as.string_val.value);
                int string_id = add_string_literal(node->as.string_val.value);
                
                // Load the raw pointer into the destination register
                emit_asm ("MOV R%d, __string_%d\n", dest_reg, string_id);
                
                // Apply the NaN-box String Tag (Base NaN + Bit 22)
                emit_asm ("OR R%d, BOXED_ROMSTRING ; Box as ROM String\n", dest_reg);
                break;
            }

            case NODE_CONCAT: {
                int left_reg = allocate_register();
                generate_asm (node -> as.binary.left, left_reg);
                emit_asm ("PUSH R%d\n", left_reg);
                unlock_register(left_reg);
                
                int right_reg = allocate_register();
                generate_asm (node -> as.binary.right, right_reg);
                ensure_in_register (right_reg);
                emit_asm ("PUSH R%d\n", right_reg);
                unlock_register(right_reg);
                
                emit_asm ("CALL __builtin_strcat\n");
                emit_asm ("IADD SP, 2\n");
                if (dest_reg != 0)
                    emit_asm ("MOV R%d, R0\n", dest_reg);
                break;
            }

            case NODE_TABLE_CONSTRUCTOR: {
                // Call the built-in to allocate a new table
                emit_asm ("CALL __builtin_table_new\n");
                // Move the returned tagged pointer into the destination register
                emit_asm ("MOV R%d, R0\n", dest_reg);
                
                // (If you want to support {1, 2, 3} later, you would loop through 
                // the node's children here and call __builtin_table_set for each one)
                break;
            }

            case NODE_TABLE_SET: {
                // 1. Attempt to emit as a hardware intrinsic FIRST, passing only the AST node!
                if (try_emit_table_set_intrinsic(node->as.table_set.table_expr,
                                                 node->as.table_set.key,
                                                 node->as.table_set.value))
                {
                    // Intrinsic handled the emission (either via immediate or on-demand register)!
                    break;
                }

                // 2. Fallback: Dynamic heap assignment (table[key] = value)
                int  val_reg    = allocate_register ();
                int  table_reg  = allocate_register ();
                int  key_reg    = allocate_register ();

				// ✅ All used immediately for table operation
				mark_register_live (val_reg,   2);
				mark_register_live (table_reg, 2);
				mark_register_live (key_reg,   2);

                generate_asm (node -> as.table_set.value,      val_reg);
                generate_asm (node -> as.table_set.table_expr, table_reg);
                generate_asm (node -> as.table_set.key,        key_reg);

                ensure_in_register (val_reg);
                ensure_in_register (table_reg);
                ensure_in_register (key_reg);

                emit_asm ("PUSH R%d ; table pointer", table_reg);
                emit_asm ("PUSH R%d ; key",           key_reg);
                emit_asm ("PUSH R%d ; value",         val_reg);
                emit_asm ("CALL __builtin_table_set ; store key-value pair in table");
                emit_asm ("IADD SP, 3 ; clean up stack arguments");

                unlock_register (val_reg);
                unlock_register (table_reg);
                unlock_register (key_reg);
                break;
            }

            case NODE_TABLE_GET: {
                // 1. Attempt hardware intrinsic read directly into dest_reg
                if (try_emit_table_get_intrinsic(node->as.table_get.table_expr,
                                                 node->as.table_get.key,
                                                 dest_reg)) {
                    break; // Successfully emitted Vircon32 IN instruction!
                }

                // 2. Fallback: Dynamic heap table lookup
                int table_reg = allocate_register();
                int key_reg   = allocate_register();

				// ✅ Short-lived
				mark_register_live(table_reg, 2);
				mark_register_live(key_reg, 2);

                generate_asm(node->as.table_get.table_expr, table_reg);
                generate_asm(node->as.table_get.key, key_reg);

                ensure_in_register(table_reg);
                ensure_in_register(key_reg);

                emit_asm ("PUSH R%d ; Arg1: Table Pointer", table_reg);
                emit_asm ("PUSH R%d ; Arg2: Key", key_reg);

                emit_asm ("CALL __builtin_table_get");
                emit_asm ("IADD SP, 2 ; Clean up stack");
                emit_asm ("MOV R%d, R0 ; Store result in destination register", dest_reg);

                unlock_register (table_reg);
                unlock_register (key_reg);
                break;
            }

            case NODE_NUMBER:
                emit_asm ("MOV R%d, %f\n", dest_reg, node -> as.number.val);
                break;

            case NODE_ASM: {
                emit_asm ("    ;; --- Begin Inline ASM Bubble (existing register states preserved) ---\n");
                
                // Get the formatted string for SP and BP snapshots
                char sp_access[256];
                char bp_access[256];
                get_variable_access_string ("asm_snap_sp", sp_access);
                get_variable_access_string ("asm_snap_bp", bp_access);
                
                emit_asm ("MOV %s, SP\n", sp_access);
                emit_asm ("MOV %s, BP\n", bp_access);

                for (int i = 0; i < NUM_GPRS; i++) {
                    if (is_register_locked (i)) {
                        char snap_name[32];
                        sprintf (snap_name, "asm_snap_r%d", i);
                        
                        char reg_access[256];
                        get_variable_access_string (snap_name, reg_access);
                        emit_asm ("MOV %s, R%d\n", reg_access, i);
                    }
                }
                
                emit_interpolated_asm (node->as.inline_asm.code);

                for (int i = 0; i < NUM_GPRS; i++) {
                    if (is_register_locked (i)) {
                        char snap_name[32];
                        sprintf (snap_name, "asm_snap_r%d", i);
                        
                        char reg_access[256];
                        get_variable_access_string (snap_name, reg_access);
                        emit_asm ("MOV R%d, %s\n", i, reg_access);
                    }
                }

                emit_asm ("MOV BP, %s\n", bp_access);
                emit_asm ("MOV SP, %s\n", sp_access);
                emit_asm ("    ;; --- End Inline ASM Bubble ---\n");
                break;
            }

            case NODE_RAWASM: {
                emit_asm ("    ;; --- Begin Raw ASM (Unprotected) ---\n");
                emit_interpolated_asm (node -> as.inline_asm.code);
                emit_asm ("    ;; --- End Raw ASM ---\n");
                break;
            }

            case NODE_COMMENT_LINE:
                emit_asm ("%s", node -> as.string_val.value);
                break;

            case NODE_COMMENT_BLOCK: {
                // Split block comments by newline and prepend ';' to every individual line
                char *buffer = strdup(node->as.string_val.value);
                if (buffer != NULL) {
                    char *line = strtok(buffer, "\n");
                    emit_asm (";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n");
                    emit_asm (";; \n");
                    while (line != NULL) {
                        emit_asm (";;@ %s", line);
                        line = strtok(NULL, "\n");
                    }
                    free(buffer);
                    emit_asm (";; \n");
                }
                break;
            }

            case NODE_CART_HINT: {
                // Only indexed resources (textures/audio) generate runtime Lua variables
                if ((node -> as.cart_hint.resource_id != -1) &&
                    (node -> as.cart_hint.name        != NULL))
                {
                    char  var_access[256];

                    ////////////////////////////////////////////////////////////////////
                    //
                    // Automatically register provided name as a global variable
                    //
                    get_variable_access_string (node -> as.cart_hint.name, var_access);
                    
                    emit_asm ("    ;; Texture: Initialize '%s' to resource ID %d\n", 
                             node -> as.cart_hint.name,
                             node -> as.cart_hint.resource_id);
                             
                    // FIX: Stage the immediate resource ID into our scratch register first,
                    // then move the register's contents into the memory address!
                    emit_asm ("MOV R%d, %f\n", dest_reg, 
                              (float) node -> as.cart_hint.resource_id);
                    emit_asm ("MOV %s, R%d\n", var_access, dest_reg);
                }
                break;
            }
        }
    }
}

void generate_global_setup (ASTNode *node)
{
    // 1. Emit the section header and entry label
    emit_asm ("\n; --- Global Variable & Runtime Initialization ---\n");
    emit_asm ("__global_scope_initialization:\n");
    emit_asm ("PUSH BP\n");
    emit_asm ("MOV BP, SP\n");
    if (next_ram_address >= 4)
        emit_asm ("MOV R0, %d ; heap start", next_ram_address);
    else
        emit_asm ("MOV R0, 4  ; heap start (minimum bound, for nil/false/true)");
    emit_asm ("MOV [HEAP_POINTER], R0");

    if (node != NULL)
    {
        ASTNode *current = node;

        while (current != NULL)
        {
            // 2. Filter out function definitions!
            // We only want top-level statements, assignments, and hints here.
            if (current -> type != NODE_FUNCTION_DEF)
            {
                // Allocate a temporary register from your inventory
                int temp_reg = allocate_register ();

                // Compile the top-level instruction (e.g., binding function pointers,
                // initializing variables, setting up cart hint resource IDs)
                generate_asm (current, temp_reg);

                // Return the register to the pool
                unlock_register (temp_reg);
            }

            // Move to the next statement in the AST chain
            current = current -> next;
        }
    }

    // 4. Emit RET to prevent falling through into __malloc or the runtime library
    emit_asm ("MOV SP, BP\n");
    emit_asm ("POP BP\n");
    emit_asm ("RET\n");
}

void  generate_functions (ASTNode *node)
{
    while (node                   != NULL)
    {
        if (node -> type          == NODE_FUNCTION_DEF)
        {
            ASTNode *next_sibling  = node -> next;
            node -> next           = NULL;
            generate_asm (node, 0);
            node -> next           = next_sibling;
        }
        node                       = node -> next;
    }
}

void  show_global_symbol_list (const char *label)
{
    SymbolNode *tmp  = global_scope ? global_scope -> symbols : NULL;
    fprintf (stderr, "[debug] show_global_symbol_list(\"%s\")\n", label);
    while (tmp      != NULL)
    {
        fprintf (stderr, "[debug] %%define %s%s %d\n", (tmp -> is_function == 1) ? "func" : "var", tmp -> name, tmp -> location);
        tmp          = tmp -> next;
    }
}

void generate_program (ASTNode *head)
{
    ASTNode *current             = NULL;
    char     buffer[1024];
    char    *check               = NULL;
    int      final_line_offset   = 0; 

    // =========================================================================
    // 1. CONDITIONAL ENTRY POINT CHECKS
    // =========================================================================
    SymbolNode *init_sym      = resolve_symbol("init");
    SymbolNode *main_sym      = resolve_symbol("main");
    SymbolNode *game_loop_sym = resolve_symbol("game_loop");

    bool has_init      = (init_sym != NULL && init_sym->is_function == 1);
    bool has_main      = (main_sym != NULL && main_sym->is_function == 1);
    bool has_game_loop = (game_loop_sym != NULL && game_loop_sym->is_function == 1);

    // If neither main() nor game_loop() exists, halt compilation immediately
    if (!has_main && !has_game_loop)
    {
        compiler_error(ERR_SEMANTIC, -1, 
            "Compilation failed: Your program must declare either a 'main()' or a 'game_loop()' function.");
    }

    // =========================================================================
    // 2. CODE GENERATION SETUP
    // =========================================================================
    FILE *temp_asm_stream = tmpfile();
    if (g_debug_mode) {
        temp_debug_stream = tmpfile();
        g_temp_asm_line = 1;
        g_current_label[0] = '\0';
    }

    FILE *final_out_stream = out();
    set_output_stream(temp_asm_stream);
    
    // =========================================================================
    // 3. EMIT COMPILED CODE ENTRY VECTOR
    // =========================================================================
    emit_asm (";; --- Compiled Code Entry Vector ---\n");
    emit_asm ("CALL __global_scope_initialization  ; Run top-level setups first\n");
    
    // If init() exists, execute it immediately after global variable setup
    if (has_init)
    {
        emit_asm ("CALL __function_init   ; Run user-defined init function\n");
    }

    // Route to main() if available; fall back to game_loop() otherwise
    if (has_main)
    {
        w_mainwait  = 1; // look for WAIT, issue warning if not found
        emit_asm ("CALL __function_main ; Execute main execution cycle\n");
    }
    else if (has_game_loop)
    {
        emit_asm ("__start:\n");
        emit_asm ("CALL __function_game_loop ; Execute game loop tick\n");
        emit_asm ("WAIT\n");
        emit_asm ("JMP __start\n");
    }

    emit_asm ("HLT                  ; Safe-guard halt\n");

    // =========================================================================
    // 4. FUNCTION DEFINITIONS & GLOBAL INITIALIZERS
    // =========================================================================
    emit_asm ("\n;; --- Function Definitions ---\n");
    current = head;
    while (current != NULL)
    {
        if (current -> type == NODE_FUNCTION_DEF) {
            generate_asm (current, 0);
        }
        current = current->next;
    }

    generate_global_setup (head);

    // Restore output back to the final compilation output file
    set_output_stream (final_out_stream);

    fprintf (out(), ";; --- Global Variable RAM Map ---\n");
    final_line_offset           = final_line_offset + 2;
    
    final_line_offset += emit_variable_map();
    fprintf (out(), "\n");
    final_line_offset           = final_line_offset + 1;

    // Flush buffered compiler assembly to our output target
    rewind (temp_asm_stream);
    while ((check = fgets (buffer, sizeof (buffer), temp_asm_stream)) != NULL) {
        fputs (buffer, out());
    }
    fclose (temp_asm_stream);

    emit_runtime_library ();
    emit_string_data_section ();

    // --- GENERATE DEBUG FILE ---
    if (g_debug_mode && temp_debug_stream != NULL)
    {
        char debug_filename[1024];
        snprintf(debug_filename, sizeof(debug_filename), "%s.debug", g_asm_filename);
        
        FILE *debug_file = fopen(debug_filename, "w");
        if (debug_file != NULL)
        {
            rewind(temp_debug_stream);
            char dbg_buffer[512];
            int last_seen_lua_line = -1; 
            
            while (fgets(dbg_buffer, sizeof(dbg_buffer), temp_debug_stream) != NULL)
            {
                int rel_line = 0;
                int lua_line = 0;
                char label[256] = "";
                
                int items = sscanf(dbg_buffer, "%d,%d,%255s", &rel_line, &lua_line, label);
                if (items >= 2)
                {
                    if (lua_line != last_seen_lua_line)
                    {
                        last_seen_lua_line = lua_line;
                        int actual_asm_line = final_line_offset + rel_line;
                        
                        if (items == 3) {
                            label[strcspn(label, "\r\n")] = 0;
                            fprintf(debug_file, "%s,%d,%s,%d,%s\n", g_asm_filename, actual_asm_line, g_lua_filename, lua_line, label);
                        } else {
                            fprintf(debug_file, "%s,%d,%s,%d\n", g_asm_filename, actual_asm_line, g_lua_filename, lua_line);
                        }
                    }
                }
            }
            fclose(debug_file);
        }
        fclose(temp_debug_stream);
        temp_debug_stream = NULL; 
    }
}
