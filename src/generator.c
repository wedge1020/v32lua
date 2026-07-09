#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "codegen.h"

// --- Output Routing ---
static FILE* current_out_stream = NULL;

static FILE* out() {
    return current_out_stream ? current_out_stream : stdout;
}

// --- Columnar & Peephole Optimizer State ---
static char last_emitted_inst[32]   = "";
static char last_emitted_dest[128] = "";
static char last_emitted_src[128]  = "";

static void trim_spaces(char *str) {
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
static int resolve_static_path(ASTNode* node, char* path_buffer) {
    if (!node) return 0;

    if (node->type == NODE_IDENTIFIER) {
        strcpy(path_buffer, node->as.id.name);
        return 1;
    }

    if (node->type == NODE_TABLE_GET && node->as.table_get.key->type == NODE_STRING) {
        char base_path[256] = {0};
        if (resolve_static_path(node->as.table_get.table_expr, base_path)) {
            sprintf(path_buffer, "%s.%s", base_path, node->as.table_get.key->as.string_val.value);
            return 1;
        }
    }
    
    return 0;
}

static void emit_asm(const char* format, ...) {
    char current_instruction[256];
    va_list args;
    
    va_start(args, format);
    vsprintf(current_instruction, format, args);
    va_end(args);

    char *p = current_instruction;
    while (*p == ' ' || *p == '\t') p++;

    if (*p == '\0' || *p == '\r' || *p == '\n' || *p == ';' || strchr(p, ':') != NULL) {
        fprintf(out(), "%s", current_instruction);
        if (strchr(p, ':') != NULL || *p == '\0' || *p == '\r' || *p == '\n') {
            last_emitted_inst[0] = '\0';
            last_emitted_dest[0] = '\0';
            last_emitted_src[0] = '\0';
        }
        return;
    }

    char inst[32] = {0};
    char operands[256] = {0};
    char comment[256] = {0};

    int inst_len = 0;
    while (*p && *p != ' ' && *p != '\t' && *p != '\r' && *p != '\n' && *p != ';') {
        if (inst_len < 31) inst[inst_len++] = *p;
        p++;
    }
    inst[inst_len] = '\0';

    while (*p == ' ' || *p == '\t') p++;

    int op_len = 0;
    while (*p && *p != ';' && *p != '\r' && *p != '\n') {
        if (op_len < 255) operands[op_len++] = *p;
        p++;
    }
    operands[op_len] = '\0';
    trim_spaces(operands);

    if (*p == ';') {
        p++;
        while (*p == ' ' || *p == '\t') p++; 
        int c_len = 0;
        while (*p && *p != '\r' && *p != '\n') {
            if (c_len < 255) comment[c_len++] = *p;
            p++;
        }
        comment[c_len] = '\0';
        trim_spaces(comment);
    }

    if (strcmp(inst, "MOV") == 0) {
        char dest[128] = {0}, src[128] = {0};
        if (sscanf(operands, "%[^,], %[^\n]", dest, src) == 2) {
            trim_spaces(dest);
            trim_spaces(src);

            if (strcmp(dest, src) == 0) {
                fprintf(out(), "    ; Peephole optimized out: %s %s\n", inst, operands);
                return;
            }

            if (strcmp(last_emitted_inst, "MOV") == 0) {
                if (strcmp(dest, last_emitted_src) == 0 && strcmp(src, last_emitted_dest) == 0) {
                    fprintf(out(), "    ; Peephole optimized out: %s %s\n", inst, operands);
                    return;
                }
            }
        }
    }

    if (strlen(comment) > 0) {
        if (strlen(operands) > 0) fprintf(out(), "    %-5s %-30s ; %s\n", inst, operands, comment);
        else fprintf(out(), "    %-5s %-30s ; %s\n", inst, "", comment);
    } else {
        if (strlen(operands) > 0) fprintf(out(), "    %-5s %s\n", inst, operands);
        else fprintf(out(), "    %-5s\n", inst);
    }

    strcpy(last_emitted_inst, inst);
    if (strcmp(inst, "MOV") == 0) {
        char dest[128] = {0}, src[128] = {0};
        if (sscanf(operands, "%[^,], %[^\n]", dest, src) == 2) {
            trim_spaces(dest);
            trim_spaces(src);
            strcpy(last_emitted_dest, dest);
            strcpy(last_emitted_src, src);
        } else {
            last_emitted_dest[0] = '\0';
            last_emitted_src[0] = '\0';
        }
    } else {
        last_emitted_dest[0] = '\0';
        last_emitted_src[0] = '\0';
    }
}

static int check_needs_stack(ASTNode *node) {
    if (!node) return 0;

    switch (node->type) {
        case NODE_FUNCTION_CALL:
        case NODE_CONCAT:
        case NODE_TABLE_SET:
        case NODE_TABLE_GET:
        case NODE_ASM:
        case NODE_RAWASM:
            return 1;

        case NODE_IDENTIFIER:
            if (node->as.id.name && strcmp(node->as.id.name, "self") == 0) return 1;
            break;

        case NODE_RETURN: {
            int ret_count = 0;
            ASTNode *expr = node->as.return_stmt.expressions_head;
            while (expr) {
                ret_count++;
                if (check_needs_stack(expr)) return 1;
                expr = expr->next;
            }
            if (ret_count > 3) return 1;
            break;
        }

        case NODE_WHILE:
            if (check_needs_stack(node->as.while_loop.condition)) return 1;
            if (check_needs_stack(node->as.while_loop.body)) return 1;
            break;

        case NODE_IF:
            if (check_needs_stack(node->as.if_stmt.condition)) return 1;
            if (check_needs_stack(node->as.if_stmt.if_body)) return 1;
            if (check_needs_stack(node->as.if_stmt.else_body)) return 1;
            break;

        case NODE_MULTIPLE_ASSIGNMENT: {
            ASTNode* curr_tgt = node->as.mult_assign.targets_head;
            while (curr_tgt) { if (check_needs_stack(curr_tgt)) return 1; curr_tgt = curr_tgt->next; }
            ASTNode* curr_val = node->as.mult_assign.values_head;
            while (curr_val) { if (check_needs_stack(curr_val)) return 1; curr_val = curr_val->next; }
            break;
        }

        case NODE_ADD:
        case NODE_SUB:
        case NODE_MUL:
        case NODE_DIV:
        case NODE_AND:
        case NODE_OR:
        case NODE_RELATIONAL:
            if (check_needs_stack(node->as.binary.left)) return 1;
            if (check_needs_stack(node->as.binary.right)) return 1;
            break;

        default:
            break;
    }

    return check_needs_stack(node->next);
}

void generate_block (ASTNode *node) {
    while (node != NULL) {
        int temp_reg = allocate_register();
        generate_asm (node, temp_reg); 
        unlock_register(temp_reg);
        
        node = node -> next;
    }
}

static void emit_interpolated_asm (const char *raw_code) {
    const char *p = raw_code;
    while (*p) {
        if (*p == '{') {
            p++; 
            char var_name[256];
            int i = 0;
            while (*p && *p != '}' && i < 255) var_name[i++] = *p++;
            var_name[i] = '\0'; 
            if (*p == '}') p++; 
            fprintf (out(), "[__var_%s]", var_name);
        } else {
            putchar (*p);
            p++;
        }
    }
    putchar ('\n');
    last_emitted_inst[0] = '\0';
    last_emitted_dest[0] = '\0';
    last_emitted_src[0] = '\0';
}

void generate_asm (ASTNode *node, int dest_reg) {
    if (!node) return;

    switch (node -> type) {
        
        case NODE_WHILE: {
            int label_id = get_next_label ();
            const char *ctx = get_current_function_name ();
            push_loop (label_id);
            emit_asm ("__%s_while_start_%d:\n", ctx, label_id);
            
            int cond_reg = allocate_register();
            generate_asm (node -> as.while_loop.condition, cond_reg);
            
            emit_asm ("    JF    R%d, __%s_while_end_%d\n", cond_reg, ctx, label_id);
            unlock_register(cond_reg);
            
            generate_block (node -> as.while_loop.body);
            emit_asm ("    JMP   __%s_while_start_%d\n", ctx, label_id);
            emit_asm ("__%s_while_end_%d:\n", ctx, label_id);
            pop_loop ();
            break;
        }

        case NODE_BREAK: {
            int current_id = current_loop ();
            if (current_id == -1) {
                fprintf (stderr, "Compiler Runtime Error: 'break' declaration found outside loop body scope.\n");
                exit (1);
            }
            emit_asm ("    JMP   __%s_while_end_%d\n", get_current_function_name (), current_id);
            break;
        }

        case NODE_IF: {
            int label_id = get_next_label ();
            const char *ctx = get_current_function_name ();
            
            int cond_reg = allocate_register();
            generate_asm (node -> as.if_stmt.condition, cond_reg);
            
            emit_asm ("    JF    R%d, __%s_else_%d\n", cond_reg, ctx, label_id);
            unlock_register(cond_reg);
            
            generate_block (node -> as.if_stmt.if_body);
            emit_asm ("    JMP   __%s_end_if_%d\n", ctx, label_id);
            
            emit_asm ("__%s_else_%d:\n", ctx, label_id);
            if (node -> as.if_stmt.else_body) generate_block (node -> as.if_stmt.else_body);
            emit_asm ("__%s_end_if_%d:\n", ctx, label_id);
            break;
        }

        case NODE_FUNCTION_DEF: {
            push_function_context (node -> as.function_def.name);
            emit_asm ("_%s:\n", node -> as.function_def.name);
            
            int needs_stack = check_needs_stack(node -> as.function_def.body);
            if (needs_stack) {
                emit_asm ("    PUSH  BP\n");
                emit_asm ("    MOV   BP, SP\n");
            } else {
                emit_asm ("  ; --- Frame pointer omitted (Leaf Function Optimization) ---\n");
            }
            
            generate_block (node -> as.function_def.body);
            
            emit_asm ("__%s_return:\n", get_current_function_name ());
            if (needs_stack) {
                emit_asm ("    MOV   SP, BP\n");
                emit_asm ("    POP   BP\n");
            }
            emit_asm ("  RET\n");
            pop_function_context ();
            break;
        }

        case NODE_FUNCTION_CALL: {
            // 1. HARDWARE INTRINSIC INTERCEPT
            char target_path[256] = {0};
            if (resolve_static_path(node->as.call.target, target_path)) {
                if (strcmp(target_path, "ioports.gpu.clear") == 0) {
                    emit_asm("  ; --- Intrinsic: ioports.gpu.clear() ---\n");
                    ASTNode *arg = node->as.call.args_head;
                    
                    if (arg != NULL) {
                        int color_reg = allocate_register();
                        if (arg->type == NODE_STRING) {
                            const char *color_name = arg->as.string_val.value;
                            unsigned int color_hex = 0x000000FF; // Default (Opaque Black)
                            int is_preset = 1;
                            
                            if (strcmp(color_name, "black") == 0)       color_hex = 0x000000FF; 
                            else if (strcmp(color_name, "white") == 0)  color_hex = 0xFFFFFFFF;
                            else if (strcmp(color_name, "blue") == 0)   color_hex = 0x0000FFFF;
                            else if (strcmp(color_name, "red") == 0)    color_hex = 0xFF0000FF;
                            else if (strcmp(color_name, "green") == 0)  color_hex = 0x00FF00FF;
                            else {
                                is_preset = 0; 
                            }
                            
                            if (is_preset) {
                                emit_asm("    MOV   R%d, %u ; Preset color '%s'\n", color_reg, color_hex, color_name);
                            } else {
                                generate_asm(arg, color_reg);
                            }
                        } else {
                            generate_asm(arg, color_reg);
                        }
                        emit_asm("    OUT   GPU_ClearColor, R%d\n", color_reg);
                        unlock_register(color_reg);
                    }
                    
                    int cmd_reg = allocate_register();
                    emit_asm("    MOV   R%d, 1 ; GPU Command Code for Clear Screen\n", cmd_reg);
                    emit_asm("    OUT   GPU_Command, R%d\n", cmd_reg);
                    unlock_register(cmd_reg);
                    
                    if (dest_reg != 0) {
                        emit_asm("    MOV   R%d, 0 ; return nil\n", dest_reg);
                    }
                    return; // Terminate early
                }
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
            emit_asm ("    CALL  R%d\n", target_reg);
            unlock_register(target_reg);

            if (arg_count > 0) emit_asm ("    ISUB  SP, %d\n", arg_count);
            if (dest_reg != 0) emit_asm ("    MOV   R%d, R0\n", dest_reg);
            break;
        }

        case NODE_FUNCTION_POINTER: {
            emit_asm ("  ; Load address of the mangled function\n");
            emit_asm ("    MOV   R%d, _%s\n", dest_reg, node -> as.func_ptr.mangled_name);
            break;
        }

        case NODE_RETURN: {
            ASTNode *expr = node -> as.return_stmt.expressions_head;
            int ret_idx = 0;
            int arg_count = node -> as.return_stmt.parent_func_arg_count;
            
            while (expr != NULL) {
                int val_reg = allocate_register();
                generate_asm (expr, val_reg); 
                
                if (ret_idx == 0)      { emit_asm ("    MOV   R0, R%d\n", val_reg); }
                else if (ret_idx == 1) { emit_asm ("    MOV   R2, R%d\n", val_reg); }
                else if (ret_idx == 2) { emit_asm ("    MOV   R3, R%d\n", val_reg); }
                else {
                    int offset = 2 + arg_count + (ret_idx - 3);
                    emit_asm ("    MOV   [BP + %d], R%d\n", offset, val_reg);
                }
                unlock_register(val_reg);
                
                ret_idx++;
                expr = expr -> next;
            }
            emit_asm ("    JMP   __%s_return\n", get_current_function_name ());
            break;
        }

        case NODE_MULTIPLE_ASSIGNMENT: {
            int temp_regs[NUM_GPRS]; 
            int val_count = 0;
            
            // 1. Count total targets so we know how many returns to unpack
            int targets_total = 0;
            ASTNode* tgt = node->as.mult_assign.targets_head;
            while(tgt) { targets_total++; tgt = tgt->next; }

            // 2. Evaluate right side values safely into temporary registers
            ASTNode* current_val = node->as.mult_assign.values_head;
            while (current_val != NULL && val_count < NUM_GPRS) {
                
                // If this is the LAST expression, and it is a function call, expand it!
                if (current_val->next == NULL && current_val->type == NODE_FUNCTION_CALL) {
                    emit_asm("  ; --- Expanding multiple returns from function call ---\n");
                    
                    // Call the function directly (dest_reg = 0 leaves results in R0, R2, R3)
                    generate_asm(current_val, 0); 
                    
                    int needed_returns = targets_total - val_count;
                    
                    // Unpack up to 3 values from our ABI return registers
                    if (needed_returns > 0 && val_count < NUM_GPRS) {
                        temp_regs[val_count] = allocate_register();
                        emit_asm("    MOV   R%d, R0\n", temp_regs[val_count++]);
                    }
                    if (needed_returns > 1 && val_count < NUM_GPRS) {
                        temp_regs[val_count] = allocate_register();
                        emit_asm("    MOV   R%d, R2\n", temp_regs[val_count++]);
                    }
                    if (needed_returns > 2 && val_count < NUM_GPRS) {
                        temp_regs[val_count] = allocate_register();
                        emit_asm("    MOV   R%d, R3\n", temp_regs[val_count++]);
                    }
                } else {
                    // Standard evaluation (automatically handles non-last function calls too!)
                    temp_regs[val_count] = allocate_register();
                    generate_asm(current_val, temp_regs[val_count]);
                    val_count++;
                }
                current_val = current_val->next;
            }
            
            // 3. Assign computed values to LHS targets
            ASTNode* current_target = node->as.mult_assign.targets_head;
            int target_idx = 0;
            
            while (current_target != NULL) {
                if (current_target->type == NODE_IDENTIFIER) {
                    get_global_variable_address(current_target->as.id.name);
                    
                    if (target_idx < val_count) {
                        emit_asm("    MOV   [__var_%s], R%d\n", current_target->as.id.name, temp_regs[target_idx]);
                    } else {
                        // Fill remaining targets with nil (0)
                        int zero_reg = allocate_register();
                        emit_asm("    MOV   R%d, 0\n", zero_reg);
                        emit_asm("    MOV   [__var_%s], R%d ; nil fallback\n", current_target->as.id.name, zero_reg);
                        unlock_register(zero_reg);
                    }
                }
                target_idx++;
                current_target = current_target->next;
            }
            
            // 4. Clean up scratchpads
            for (int i = 0; i < val_count; i++) {
                unlock_register(temp_regs[i]);
            }
            break;
        }

        case NODE_ADD: {
            generate_asm (node -> as.binary.left, dest_reg);
            int right_reg = allocate_register ();
            generate_asm (node -> as.binary.right, right_reg);
            emit_asm ("    FADD  R%d, R%d\n", dest_reg, right_reg);
            unlock_register (right_reg);
            break;
        }

        case NODE_SUB: {
            generate_asm (node -> as.binary.left, dest_reg);
            int right_reg = allocate_register ();
            generate_asm (node -> as.binary.right, right_reg);
            emit_asm ("    FSUB  R%d, R%d\n", dest_reg, right_reg);
            unlock_register (right_reg);
            break;
        }
        
        case NODE_MUL: {
            generate_asm (node -> as.binary.left, dest_reg);
            int right_reg = allocate_register ();
            generate_asm (node -> as.binary.right, right_reg);
            emit_asm ("    FMUL  R%d, R%d\n", dest_reg, right_reg);
            unlock_register (right_reg);
            break;
        }
        
        case NODE_DIV: {
            generate_asm (node -> as.binary.left, dest_reg);
            int right_reg = allocate_register ();
            generate_asm (node -> as.binary.right, right_reg);
            emit_asm ("    FDIV  R%d, R%d\n", dest_reg, right_reg);
            unlock_register (right_reg);
            break;
        }

        case NODE_AND: {
            int label_id = get_next_label ();
            generate_asm (node -> as.binary.left, dest_reg);
            emit_asm ("    JF    R%d, __short_and_%d\n", dest_reg, label_id);
            generate_asm (node -> as.binary.right, dest_reg);
            emit_asm ("__short_and_%d:\n", label_id);
            break;
        }

        case NODE_OR: {
            int label_id = get_next_label ();
            generate_asm (node -> as.binary.left, dest_reg);
            emit_asm ("    JT    R%d, __short_or_%d\n", dest_reg, label_id);
            generate_asm (node -> as.binary.right, dest_reg);
            emit_asm ("__short_or_%d:\n", label_id);
            break;
        }

        case NODE_RELATIONAL: {
            generate_asm (node -> as.binary.left, dest_reg);
            int right_reg = allocate_register ();
            generate_asm (node -> as.binary.right, right_reg);
            switch (node -> as.binary.operator) {
                case OP_EQ:  emit_asm ("    FEQ   R%d, R%d\n", dest_reg, right_reg); break;
                case OP_NEQ: emit_asm ("    FNE   R%d, R%d\n", dest_reg, right_reg); break;
                case OP_LT:  emit_asm ("    FLT   R%d, R%d\n", dest_reg, right_reg); break;
                case OP_LE:  emit_asm ("    FLE   R%d, R%d\n", dest_reg, right_reg); break;
                case OP_GT:  emit_asm ("    FGT   R%d, R%d\n", dest_reg, right_reg); break;
                case OP_GE:  emit_asm ("    FGE   R%d, R%d\n", dest_reg, right_reg); break;
            }
            unlock_register (right_reg);
            break;
        }

        case NODE_STRING: {
            int str_id = add_string_literal (node -> as.string_val.value);
            emit_asm ("    MOV   R%d, __string_%d\n", dest_reg, str_id);
            break;
        }

        case NODE_CONCAT: {
            int left_reg = allocate_register();
            generate_asm (node -> as.binary.left, left_reg);
            emit_asm ("    PUSH  R%d\n", left_reg);
            unlock_register(left_reg);
            
            int right_reg = allocate_register();
            generate_asm (node -> as.binary.right, right_reg);
            emit_asm ("    PUSH  R%d\n", right_reg);
            unlock_register(right_reg);
            
            emit_asm ("    CALL  __builtin_strcat\n");
            emit_asm ("    ISUB  SP, 2\n");
            if (dest_reg != 0) emit_asm ("    MOV   R%d, R0\n", dest_reg);
            break;
        }

        case NODE_TABLE_CONSTRUCTOR: {
            emit_asm ("    MOV   R%d, [__heap_pointer] ; Read __heap_pointer\n", dest_reg);
            int zero_reg = allocate_register ();
            emit_asm ("    MOV   R%d, 0\n", zero_reg);
            emit_asm ("    MOV   [R%d], R%d ; Initialize to nil/0\n", dest_reg, zero_reg);
            unlock_register (zero_reg);
            
            int temp_reg = allocate_register();
            emit_asm ("    MOV   R%d, [__heap_pointer]\n", temp_reg);
            emit_asm ("    IADD  R%d, 1\n", temp_reg); 
            emit_asm ("    MOV   [__heap_pointer], R%d ; Advance heap pointer\n", temp_reg);
            unlock_register(temp_reg);
            break;
        }

        case NODE_TABLE_SET: {
            char base_path[256] = {0};
            
            // 1. HARDWARE INTRINSIC CHECK
            if (resolve_static_path(node->as.table_set.table_expr, base_path) && 
                node->as.table_set.key->type == NODE_STRING) {
                
                char full_path[512];
                sprintf(full_path, "%s.%s", base_path, node->as.table_set.key->as.string_val.value);
                
                if (strcmp(full_path, "ioports.gpu.texture") == 0) {
                    int val_reg = allocate_register();
                    generate_asm(node->as.table_set.value, val_reg);
                    emit_asm("    OUT   GPU_SelectedTexture, R%d\n", val_reg); 
                    unlock_register(val_reg);
                    return; // Skip standard table set!
                }
            }

            // 2. STANDARD TABLE SET (Fallback)
            int val_reg = allocate_register();
            generate_asm (node -> as.table_set.value, val_reg);
            emit_asm ("    PUSH  R%d\n", val_reg);
            unlock_register(val_reg);
            
            int key_reg = allocate_register();
            generate_asm (node -> as.table_set.key, key_reg);
            emit_asm ("    PUSH  R%d\n", key_reg);
            unlock_register(key_reg);
            
            int tbl_reg = allocate_register();
            generate_asm (node -> as.table_set.table_expr, tbl_reg);
            emit_asm ("    PUSH  R%d\n", tbl_reg);
            unlock_register(tbl_reg);
            
            emit_asm ("    CALL  __builtin_table_set\n");
            emit_asm ("    ISUB  SP, 3\n");
            break;
        }

        case NODE_TABLE_GET: {
            char base_path[256] = {0};
            
            // 1. HARDWARE INTRINSIC CHECK
            if (resolve_static_path(node->as.table_get.table_expr, base_path) && 
                node->as.table_get.key->type == NODE_STRING) {
                
                char full_path[512];
                sprintf(full_path, "%s.%s", base_path, node->as.table_get.key->as.string_val.value);
                
                if (strcmp(full_path, "ioports.gpu.texture") == 0) {
                    if (dest_reg != 0) {
                        emit_asm("    IN    R%d, GPU_SelectedTexture\n", dest_reg);
                    }
                    return; // Skip standard table get!
                }
            }

            // 2. STANDARD TABLE GET (Fallback)
            int key_reg = allocate_register ();
            generate_asm (node -> as.table_get.key, key_reg);

            int tbl_reg = allocate_register();
            generate_asm (node -> as.table_get.table_expr, tbl_reg);
            
            emit_asm ("    MOV   R1, R%d\n", tbl_reg);
            emit_asm ("    MOV   R2, R%d\n", key_reg);
            emit_asm ("    CALL  __builtin_table_get\n");
            
            unlock_register (key_reg);
            unlock_register (tbl_reg);
            
            if (dest_reg != 0) emit_asm ("    MOV   R%d, R0\n", dest_reg);
            break;
        }

        case NODE_IDENTIFIER: {
            if (strcmp (node -> as.id.name, "self") == 0) {
                emit_asm ("  ; --- Loading local parameter 'self' ---\n");
                emit_asm ("    MOV   R%d, [BP+2]\n", dest_reg); 
            } else {
                emit_asm ("    MOV   R%d, [__var_%s]\n", dest_reg, node -> as.id.name);
            }
            break;
        }
            
        case NODE_NUMBER:
            emit_asm ("    MOV   R%d, %f\n", dest_reg, node -> as.number.val);
            break;
            
        case NODE_ASM: {
            emit_asm ("  ; --- Begin Inline ASM Bubble (existing register states preserved) ---\n");
            get_global_variable_address ("__asm_snap_sp");
            get_global_variable_address ("__asm_snap_bp");
            emit_asm ("    MOV   [__var___asm_snap_sp], SP\n");
            emit_asm ("    MOV   [__var___asm_snap_bp], BP\n");

            for (int i = 0; i < NUM_GPRS; i++) {
                if (is_register_locked (i)) {
                    char snap_name[32];
                    sprintf (snap_name, "__asm_snap_r%d", i);
                    get_global_variable_address (snap_name);
                    emit_asm ("    MOV   [__var_%s], R%d\n", snap_name, i);
                }
            }
            
            emit_interpolated_asm (node -> as.inline_asm.code);

            for (int i = 0; i < NUM_GPRS; i++) {
                if (is_register_locked (i)) {
                    char snap_name[32];
                    sprintf (snap_name, "__asm_snap_r%d", i);
                    emit_asm ("    MOV   R%d, [__var_%s]\n", i, snap_name);
                }
            }

            emit_asm ("    MOV   BP, [__var___asm_snap_bp]\n");
            emit_asm ("    MOV   SP, [__var___asm_snap_sp]\n");
            emit_asm ("  ; --- End Inline ASM Bubble ---\n");
            break;
        }

        case NODE_RAWASM: {
            emit_asm ("  ; --- Begin Raw ASM (Unprotected) ---\n");
            emit_interpolated_asm (node -> as.inline_asm.code);
            emit_asm ("  ; --- End Raw ASM ---\n");
            break;
        }

        case NODE_COMMENT_LINE: {
            fprintf(out(), ";; lua comment: %s\n", node->as.string_val.value);
            break;
        }

        case NODE_COMMENT_BLOCK: {
            fprintf(out(), ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n");
            fprintf(out(), ";; \n");
            fprintf(out(), ";; lua comment: ");
            
            char *text = node->as.string_val.value;
            for (int i = 0; text[i] != '\0'; i++) {
                if (text[i] == '\n') {
                    fprintf(out(), "\n;; lua comment: ");
                } else if (text[i] == '\t') {
                    fprintf(out(), " ");
                } else if (text[i] == '\r') {
                    ; // Skip carriage returns
                } else {
                    putchar(text[i]);
                }
            }
            fprintf(out(), "\n;; \n");
            break;
        }
    }
}

void generate_global_setup (ASTNode *node) {
    while (node != NULL) {
        if (node -> type != NODE_FUNCTION_DEF) {
            ASTNode *next_sibling = node -> next;
            node -> next = NULL;
            int temp_reg = allocate_register();
            generate_asm (node, temp_reg);
            unlock_register (temp_reg);
            node -> next = next_sibling;
        }
        node = node -> next;
    }
}

void generate_functions (ASTNode *node) {
    while (node != NULL) {
        if (node -> type == NODE_FUNCTION_DEF) {
            ASTNode *next_sibling = node -> next;
            node -> next = NULL;
            generate_asm (node, 0); 
            node -> next = next_sibling;
        }
        node = node -> next;
    }
}

void  generate_program (ASTNode *head)
{
    // 1. Open a temporary buffer for the generation pass
    current_out_stream = tmpfile();
    if (!current_out_stream)
    {
        fprintf(stderr, "Compiler Error: Could not create temp file for code generation.\n");
        exit(1);
    }

    // --- PRE-SCAN: Do we actually need a global initialization vector? ---
    int has_globals = 0;
    int globals_need_stack = 0;
    ASTNode *scan = head;
    while (scan != NULL) {
        // Comments and function definitions don't count as executable global code
        if (scan->type != NODE_FUNCTION_DEF &&
            scan->type != NODE_COMMENT_LINE &&
            scan->type != NODE_COMMENT_BLOCK) {

            has_globals = 1;

            // Check if this specific global statement triggers stack usage
            // We copy the node and sever its 'next' pointer temporarily to prevent
            // check_needs_stack from recursing through the entire remaining script.
            ASTNode isolated_node = *scan;
            isolated_node.next = NULL;
            if (check_needs_stack(&isolated_node)) {
                globals_need_stack = 1;
            }
        }
        scan = scan->next;
    }

    // 2. Generate the code
    emit_asm (";; --- Compiled Code Entry Vector ---\n");
    if (has_globals) {
        emit_asm ("    CALL  __init_globals  ; Run top-level setups first\n");
    }
    emit_asm ("    CALL  _main           ; Then hand control to the user\n");
    emit_asm ("    HLT                   ; Halt CPU when main finishes\n\n");

    emit_asm ("; --- Function Definitions ---\n");
    ASTNode *current = head;
    while (current != NULL) {
        if (current -> type == NODE_FUNCTION_DEF) {
            generate_asm (current, 0);
        }
        current = current -> next;
    }

    // 3. Only emit the global init vector if there is actually work to do
    if (has_globals) {
        emit_asm ("\n;; --- Global Initialization Vector ---\n");
        emit_asm ("__init_globals:\n");

        if (globals_need_stack) {
            emit_asm ("    PUSH  BP\n");
            emit_asm ("    MOV   BP, SP\n");
        } else {
            emit_asm ("  ; --- Frame pointer omitted (Leaf Function Optimization) ---\n");
        }

        current = head;
        while (current != NULL) {
            if (current -> type != NODE_FUNCTION_DEF) {
                int temp_reg = allocate_register();
                generate_asm (current, temp_reg);
                unlock_register (temp_reg);
            }
            current = current -> next;
        }

        if (globals_need_stack) {
            emit_asm ("    MOV   SP, BP\n");
            emit_asm ("    POP   BP\n");
        }
        emit_asm ("  RET\n");
    }

    // 4. Generation complete. Now output the required headers to the REAL stdout
    fprintf(stdout, ";; --- System Constants ---\n");
    fprintf(stdout, "%%define __heap_pointer 0\n");

    fprintf(stdout, "\n;; --- Global Variable RAM Map ---\n");
    emit_variable_map();
    fprintf(stdout, "\n");

    // 5. Dump the compiled code from the temp buffer directly underneath
    rewind(current_out_stream);
    char buffer[1024];
    while (fgets(buffer, sizeof(buffer), current_out_stream)) {
        fprintf(stdout, "%s", buffer);
    }

    // 6. Clean up
    fclose(current_out_stream);
    current_out_stream = NULL;
}
