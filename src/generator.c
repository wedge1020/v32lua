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
static FILE *active_out_stream = NULL;

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
    if (!node) return 0;

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
        case NODE_FUNCTION_CALL:
        case NODE_CONCAT:
        case NODE_TABLE_SET:
        case NODE_TABLE_GET:
        case NODE_ASM:
        case NODE_RAWASM:
            return (1);

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

void  generate_block (ASTNode *head)
{
    ASTNode *current   = head;
    while (current    != NULL)
    {
        int  temp_reg  = allocate_register();
        generate_asm (current, temp_reg);
        unlock_register (temp_reg);
        current        = current -> next; // Move to the next sibling statement
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

                push_loop (label_id);
                emit_asm ("__%s_while_start_%d:\n", ctx, label_id);
                
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

            case NODE_BREAK: {
                int  current_id  = current_loop ();
                if (current_id  == -1)
                {
                    fprintf (stderr, "Compiler Runtime Error: 'break' declaration found outside loop.\n");
                    exit (1);
                }

                emit_asm("JMP __%s_while_end_%d\n", get_current_function_name (), current_id);
                break;
            }

            case NODE_IF: {
                int         cond_reg  = allocate_register ();
                int         label_id  = get_next_label ();
                const char *ctx       = get_current_function_name ();
                char        else_label[128], end_label[128];
                snprintf(else_label, sizeof(else_label), "__%s_else_%d", ctx, label_id);
                snprintf(end_label, sizeof(end_label), "__%s_end_if_%d", ctx, label_id);
                
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
                bool has_params = (node->as.function_def.params != NULL);
                bool body_needs_stack = check_needs_stack(node->as.function_def.body);

                bool omit_frame_pointer = (o_optflag >= 1) && !body_needs_stack && (num_locals == 0) && !has_params;

                if (!omit_frame_pointer) {
                    emit_asm("PUSH BP\n");
                    emit_asm("MOV BP, SP\n");
                    
                    if (num_locals > 0) {
                        emit_asm("    ;; Reserve stack space for %d local variable(s)\n", num_locals);
                        emit_asm("ISUB SP, %d\n", num_locals);
                    }
                } else {
                    emit_asm("    ;; OPTIMIZATION (-O1): Frame pointer omitted (Leaf Function)\n");
                }

                push_scope();

                int param_offset = 2; 
                ASTNode *p = node->as.function_def.params;
                while (p != NULL) {
                    if (p->type == NODE_IDENTIFIER) {
                        register_parameter(p->as.id.name, param_offset++);
                    }
                    p = p->next;
                }

                generate_block(node->as.function_def.body);
                pop_scope(); 

                // --- Function Epilogue ---
                emit_asm("__%s_return:\n", func_name);
                if (!omit_frame_pointer) {
                    emit_asm("MOV SP, BP\n");
                    emit_asm("POP BP\n");
                }
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
                    emit_asm ("ISUB SP, 1\n");
                    
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

                    // 1. Check if Nil or False using scratch register
                    emit_asm("MOV R%d, R%d\n", scratch_reg, dest_reg);
                    emit_asm("IEQ R%d, 0xFFC00000 ; Is Nil?\n", scratch_reg);
                    emit_asm("JT  R%d, %s\n", scratch_reg, to_true_label);
                    emit_asm("MOV R%d, R%d\n", scratch_reg, dest_reg);
                    emit_asm("IEQ R%d, 0xFFC00001 ; Is False?\n", scratch_reg);
                    emit_asm("JT  R%d, %s\n", scratch_reg, to_true_label);

                    // 2. If truthy, return VAL_FALSE (0xFFC00001)
                    emit_asm("MOV R%d, 0xFFC00001 ; Return False\n", dest_reg);
                    emit_asm("JMP %s\n", end_label);

                    // 3. If falsy, return VAL_TRUE (0xFFC00002)
                    emit_asm("%s:\n", to_true_label);
                    emit_asm("MOV R%d, 0xFFC00002 ; Return True\n", dest_reg);
                    emit_asm("%s:\n", end_label);
					unlock_register (scratch_reg);
                }
                else if (node->as.unary.operator == OP_UNM) {
                    emit_asm ("PUSH R%d\n", dest_reg);
                    emit_asm ("CALL __builtin_unm\n");
                    emit_asm ("ISUB SP, 1\n");
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
                            // Register local symbol and initialize to canonical Nil (0xFFC00000)
                            SymbolNode *sym = register_local(curr_tgt->as.id.name);
                            char access_str[128];
                            get_variable_access_string(sym->name, access_str);

                            emit_asm("    ;; Bare local '%s' initialized to nil", sym->name);
                            emit_asm("MOV %s, 0xFFC00000", access_str);
                        }
                        curr_tgt = curr_tgt->next;
                    }
                    break;
                }

                // --- Standard & Multiple Assignment Evaluation ---
                while (curr_tgt != NULL) {
                    val_reg = allocate_register();

                    if (curr_val != NULL) {
                        // Evaluate the right-hand expression into our temporary register
                        generate_asm(curr_val, val_reg);
                        curr_val = curr_val->next;
                    } else {
                        // Lua rule: If values run out, remaining targets are assigned nil
                        emit_asm("MOV R%d, 0xFFC00000 ; Pad missing value with Nil", val_reg);
                    }

                    // Assign evaluated value to the target
                    if (curr_tgt->type == NODE_IDENTIFIER) {
                        if (node->as.mult_assign.is_local) {
                            register_local(curr_tgt->as.id.name);
                        }
                        char access_str[128];
                        get_variable_access_string(curr_tgt->as.id.name, access_str);
                        emit_asm("MOV %s, R%d", access_str, val_reg);
                    }
                    else if (curr_tgt->type == NODE_TABLE_GET) {
                        // Handle table index assignment: table[key] = value
                        int table_reg = allocate_register();
                        int key_reg   = allocate_register();

                        generate_asm(curr_tgt->as.table_get.table_expr, table_reg);
                        generate_asm(curr_tgt->as.table_get.key, key_reg);

                        emit_asm("PUSH R%d ; Push Table Pointer", table_reg);
                        emit_asm("PUSH R%d ; Push Key", key_reg);
                        emit_asm("PUSH R%d ; Push Value", val_reg);
                        emit_asm("CALL __builtin_table_set");
                        emit_asm("ISUB SP, 3 ; Clean up stack");

                        unlock_register(key_reg);
                        unlock_register(table_reg);
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

                // 1. HARDWARE & BUILTIN INTRINSIC INTERCEPT
                if (try_emit_call_intrinsic(node, dest_reg)) {
                    break; // Intrinsic handled! Skip standard Lua call generation.
                }

                // 2. STANDARD LUA FUNCTION CALL (Fallback)
                int arg_count = 0;

                if (node -> as.call.is_method_call) {
                    emit_asm ("  ; --- Injecting implicit 'self' ---\n");
                    int self_reg = allocate_register();
                    generate_asm (node -> as.call.target -> as.table_get.table_expr, self_reg);
                    emit_asm ("    PUSH  R%d\n", self_reg);
                    unlock_register(self_reg);
                    arg_count++;
                }

                ASTNode *current_arg = node -> as.call.args_head;
                while (current_arg != NULL) {
                    int arg_reg = allocate_register();
                    generate_asm (current_arg, arg_reg);
                    emit_asm ("    PUSH  R%d\n", arg_reg);
                    unlock_register(arg_reg);
                    arg_count++;
                    current_arg = current_arg -> next;
                }

                int target_reg = allocate_register();
                generate_asm (node -> as.call.target, target_reg);
                
                // AUDITED: Strip the 0xFF800000 NaN tag before jumping!
                emit_asm ("AND R%d, 0x003FFFFF ; Unbox code pointer\n", target_reg);
				emit_asm ("OR  R%d, 0x20000000 ; restore memory page bit\n", target_reg);
                emit_asm ("CALL R%d\n", target_reg);
                unlock_register(target_reg);

                if (arg_count > 0) emit_asm ("ISUB SP, %d\n", arg_count);
                if (dest_reg != 0) emit_asm ("MOV R%d, R0\n", dest_reg);
                break;
            }

            case NODE_FUNCTION_POINTER: {
                emit_asm ("    ;; Load and box address of the mangled function\n");
                emit_asm ("MOV R%d, __function_%s\n", dest_reg, node -> as.func_ptr.mangled_name);
                // AUDITED: Apply Function NaN tag (Bit 31=1, Bit 22=0)
                emit_asm ("OR R%d, 0xFF800000 ; Box as Function\n", dest_reg);
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
				// OPTIMIZATION (-O1): x + 0.0 -> x
				if ((o_optflag                                >= 1) &&
					(node -> as.binary.right -> type          == NODE_NUMBER) &&
					(node -> as.binary.right -> as.number.val == 0.0))
				{
					generate_asm (node -> as.binary.left, dest_reg);
					break;
				}

				// OPTIMIZATION (-O1): 0.0 + x -> x
				if ((o_optflag                                >= 1) &&
					(node -> as.binary.left -> type           == NODE_NUMBER) &&
					(node -> as.binary.left -> as.number.val  == 0.0))
				{
					generate_asm (node -> as.binary.right, dest_reg);
					break;
				}

				generate_asm (node -> as.binary.left, dest_reg);
				int  right_reg                                 = allocate_register ();
				generate_asm (node -> as.binary.right, right_reg);
				emit_asm ("FADD R%d, R%d\n", dest_reg, right_reg);
				unlock_register (right_reg);
				break;
			}

            case NODE_MUL: {
                // OPTIMIZATION (-O1): x * 1.0 -> x
                if ((o_optflag                                >= 1) &&
					(node -> as.binary.right -> type          == NODE_NUMBER) &&
					(node -> as.binary.right -> as.number.val == 1.0))
				{
                    generate_asm (node -> as.binary.left, dest_reg);
                    break;
                }

                // OPTIMIZATION (-O1): x * 0.0 -> 0.0 (Assuming left operand has no function call side effects)
                if ((o_optflag                                >= 1) &&
					(node -> as.binary.right -> type          == NODE_NUMBER) &&
					(node -> as.binary.right -> as.number.val == 0.0))
				{
                    if (!check_needs_stack (node -> as.binary.left)) {
                        emit_asm ("MOV R%d, 0.000000 ; Optimized multiplication by zero\n", dest_reg);
                        break;
                    }
                }

                generate_asm (node -> as.binary.left, dest_reg);
                int  right_reg                                 = allocate_register ();
                generate_asm (node -> as.binary.right, right_reg);
                emit_asm ("FMUL R%d, R%d\n", dest_reg, right_reg);
                unlock_register (right_reg);
                break;
            }

            case NODE_SUB: {
				// OPTIMIZATION (-O1): x - 0.0 -> x
				if ((o_optflag                                >= 1) &&
					(node -> as.binary.right -> type          == NODE_NUMBER) &&
					(node -> as.binary.right -> as.number.val == 0.0))
				{
					generate_asm (node -> as.binary.left, dest_reg);
					break;
				}

                generate_asm (node -> as.binary.left, dest_reg);
                int  right_reg                                 = allocate_register ();
                generate_asm (node -> as.binary.right, right_reg);
                emit_asm ("FSUB R%d, R%d\n", dest_reg, right_reg);
                unlock_register (right_reg);
                break;
            }
        
            case NODE_DIV: {
                // OPTIMIZATION (-O1): x / 1.0 -> x
                if ((o_optflag                                >= 1) &&
					(node -> as.binary.right -> type          == NODE_NUMBER) &&
					(node -> as.binary.right -> as.number.val == 1.0))
				{
                    generate_asm (node -> as.binary.left, dest_reg);
                    break;
                }

                generate_asm (node -> as.binary.left, dest_reg);
                int  right_reg                                 = allocate_register ();
                generate_asm (node -> as.binary.right, right_reg);
                emit_asm ("FDIV R%d, R%d\n", dest_reg, right_reg);
                unlock_register (right_reg);
                break;
            }

            case NODE_AND: {
                int label_id = get_next_label();
                const char *ctx = get_current_function_name(); // Fetch context
                char end_label[128];
                snprintf(end_label, sizeof(end_label), "__%s_short_and_%d", ctx, label_id); // Prefix added

                // 1. Evaluate Left Operand into dest_reg
                generate_asm(node->as.binary.left, dest_reg);
                
                emit_falsy_jump(dest_reg, end_label);
                
                // 2. Otherwise, evaluate Right Operand into dest_reg
                generate_asm(node->as.binary.right, dest_reg);    emit_asm("%s:\n", end_label);
                break;
            }

            case NODE_OR: {
                int label_id = get_next_label();
                const char *ctx = get_current_function_name(); // Fetch context
                char end_label[128];
                snprintf(end_label, sizeof(end_label), "__%s_short_or_%d", ctx, label_id); // Prefix added

                // 1. Evaluate Left Operand into dest_reg
                generate_asm(node->as.binary.left, dest_reg);
                
                emit_truthy_jump(dest_reg, end_label);
                
                // 2. Otherwise, evaluate Right Operand into dest_reg
                generate_asm(node->as.binary.right, dest_reg);
                emit_asm("%s:\n", end_label);
                break;
            }

            case NODE_RELATIONAL: {
                generate_asm (node -> as.binary.left, dest_reg);
                int right_reg = allocate_register ();
                generate_asm (node -> as.binary.right, right_reg);
                
                if (node -> as.binary.operator == OP_EQ || node -> as.binary.operator == OP_NEQ) {
                    emit_asm ("PUSH R%d\n", dest_reg);
                    emit_asm ("PUSH R%d\n", right_reg);
                    emit_asm ("CALL __builtin_eq\n");
                    emit_asm ("ISUB SP, 2\n");
                    
                    if (node -> as.binary.operator == OP_NEQ) {
                        emit_asm ("MOV R%d, R0\n", dest_reg);
                        emit_asm ("IEQ R%d, 0 ; Invert to true if it was false\n", dest_reg);
                    } else {
                        emit_asm ("MOV R%d, R0\n", dest_reg);
                    }
                    // Box the 0/1 result from equality checking into a NaN boolean!
                    emit_asm ("IADD R%d, 0xFFC00001 ; Box as Lua Boolean (False/True)\n", dest_reg);
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
                    // AUDITED: Box raw 0/1 hardware comparison result into 0xFFC00001/0xFFC00002!
                    emit_asm ("IADD R%d, 0xFFC00001 ; Box as Lua Boolean (False/True)\n", dest_reg);
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
                emit_asm ("OR R%d, 0x7FC00000 ; Box as String\n", dest_reg);
                break;
            }

            case NODE_CONCAT: {
                int left_reg = allocate_register();
                generate_asm (node -> as.binary.left, left_reg);
                emit_asm ("PUSH R%d\n", left_reg);
                unlock_register(left_reg);
                
                int right_reg = allocate_register();
                generate_asm (node -> as.binary.right, right_reg);
                emit_asm ("PUSH R%d\n", right_reg);
                unlock_register(right_reg);
                
                emit_asm ("CALL __builtin_strcat\n");
                emit_asm ("ISUB SP, 2\n");
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
                // 1. HARDWARE INTRINSIC INTERCEPT (e.g., ioports.gpu.x = 10)
                if (try_emit_table_set_intrinsic(node)) {
                    return; // Terminate early, skipping dynamic table assignment
                }

                int table_reg = allocate_register();
                int key_reg = allocate_register();
                int val_reg = allocate_register();

                // 1. Evaluate table, key, and value
                generate_asm(node->as.table_set.table_expr, table_reg);
                generate_asm(node->as.table_set.key, key_reg);
                generate_asm(node->as.table_set.value, val_reg);

                // 2. Push arguments (Reverse order: Table, Key, Value)
                emit_asm("    PUSH R%d\n", table_reg);
                emit_asm("    PUSH R%d\n", key_reg);
                emit_asm("    PUSH R%d\n", val_reg);

                // 3. Call the built-in and clean up
                emit_asm("    CALL __builtin_table_set\n");
                emit_asm("    ISUB SP, 3\n");

                unlock_register(table_reg);
                unlock_register(key_reg);
                unlock_register(val_reg);
                break;
            }

            case NODE_TABLE_GET: {
                // 1. HARDWARE INTRINSIC INTERCEPT (e.g., val = ioports.gpu.x)
                if (try_emit_table_get_intrinsic(node, dest_reg)) {
                    return; // Terminate early, skipping dynamic table lookup
                }

                int table_reg = allocate_register();
                int key_reg = allocate_register();

                // 1. Evaluate the table and the key
                generate_asm(node->as.table_get.table_expr, table_reg);
                generate_asm(node->as.table_get.key, key_reg);

                // 2. Push arguments (Reverse order: Table, then Key)
                emit_asm("    PUSH R%d\n", table_reg);
                emit_asm("    PUSH R%d\n", key_reg);

                // 3. Call the built-in and clean up
                emit_asm("    CALL __builtin_table_get\n");
                emit_asm("    ISUB SP, 2\n");

                // 4. Move result to destination register
                emit_asm("    MOV R%d, R0\n", dest_reg);

                unlock_register(table_reg);
                unlock_register(key_reg);
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

            case NODE_COMMENT_LINE: {
                fprintf (out (), ";;@ %s\n", node->as.string_val.value);
                break;
            }

            case NODE_COMMENT_BLOCK: {
                fprintf(out(), ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n");
                fprintf(out(), ";; \n");
                fprintf(out(), ";;@ ");
                
                char *text = node->as.string_val.value;
                for (int i = 0; text[i] != '\0'; i++) {
                    if (text[i] == '\n') {
                        fprintf(out(), "\n;;@ ");
                    } else if (text[i] == '\t') {
                        fprintf(out(), " ");
                    } else if (text[i] == '\r') {
                        ; // Skip carriage returns
                    } else {
                        fputc (text[i], out ());
                    }
                }
                fprintf(out(), "\n;; \n");
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
    emit_asm ("__init_globals:\n");
    emit_asm ("MOV R0, %d ; heap start", next_ram_address);
    emit_asm ("MOV [heap_pointer], R0");

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
    //int      globals_need_stack  = 0;
    char     buffer[1024];
    char    *check               = NULL;
    int      final_line_offset   = 0; 

    init_global_scope (); 

    FILE *temp_asm_stream = tmpfile();
    if (g_debug_mode) {
        temp_debug_stream = tmpfile();
        g_temp_asm_line = 1;
        g_current_label[0] = '\0';
    }

    FILE *final_out_stream = out();
    set_output_stream(temp_asm_stream);
    
    // --- (AST Traversal & Code Generation occurs here) ---
    // ... all your emit_asm calls execute and populate both temp streams ...
    emit_asm (";; --- Compiled Code Entry Vector ---\n");
    emit_asm ("CALL __init_globals  ; Run top-level setups first\n");
    emit_asm ("__start:\n");
    emit_asm ("CALL __function_main ; Then hand control to the user\n");
    emit_asm ("WAIT\n");
    emit_asm ("JMP __start\n");
    emit_asm ("HLT                  ; Halt CPU when main finishes\n");

    emit_asm ("\n;; --- Function Definitions ---\n");
    current = head;
    while (current != NULL)
    {
        if (current -> type == NODE_FUNCTION_DEF) {
            generate_asm (current, 0);
        }/* else if (check_needs_stack (current)) {
            globals_need_stack = 1;
        }*/
        current = current->next;
    }

    generate_global_setup (head);

    // Restore output back to your final target file
    set_output_stream (final_out_stream);

    fprintf (out(), ";; --- Global Variable RAM Map ---\n");
    final_line_offset           = final_line_offset + 2;
    
    // Factor in the dynamic size of your variables
    final_line_offset += emit_variable_map();
    fprintf (out(), "\n");
    final_line_offset           = final_line_offset + 1;

    // Dump your buffered assembly code to the final file
    rewind (temp_asm_stream);
    while ((check = fgets (buffer, sizeof (buffer), temp_asm_stream)) != NULL) {
        fputs (buffer, out());
    }
    fclose (temp_asm_stream);

    // Write out trailing runtime items
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
            
            // --- ADD TRACKER HERE ---
            int last_seen_lua_line = -1; 
            
            while (fgets(dbg_buffer, sizeof(dbg_buffer), temp_debug_stream) != NULL)
            {
                int rel_line = 0;
                int lua_line = 0;
                char label[256] = "";
                
                int items = sscanf(dbg_buffer, "%d,%d,%255s", &rel_line, &lua_line, label);
                if (items >= 2)
                {
                    // --- ONLY PROCESS IF THE LUA LINE HAS CHANGED ---
                    if (lua_line != last_seen_lua_line)
                    {
                        last_seen_lua_line = lua_line; // Update the tracker
                        
                        // Scale the relative assembly line using our calculated header offset
                        int actual_asm_line = final_line_offset + rel_line;
                        
                        if (items == 3) {
                            label[strcspn(label, "\r\n")] = 0; // Guard against loose carriage returns
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
