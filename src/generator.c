#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "codegen.h"

// --- Peephole Optimizer State ---
static char last_emitted_instruction[256] = "";

// A smart wrapper around fprintf that intercepts assembly before it is printed
// to eliminate redundant instructions.
static void emit_asm(const char* format, ...) {
    char current_instruction[256];
    va_list args;
    
    va_start(args, format);
    vsprintf(current_instruction, format, args);
    va_end(args);

    // We only attempt to optimize lines that look like standard instructions 
    // (starting with spaces, avoiding labels and comments)
    if (strncmp(current_instruction, "    MOV", 7) == 0) {
        char dest[128] = {0}, src[128] = {0};
        
        // Parse the destination and source from the current MOV instruction
        if (sscanf(current_instruction, "    MOV   %[^,], %s", dest, src) == 2) {
            
            // Clean up any trailing newlines from parsing
            src[strcspn(src, "\r\n")] = 0;
            dest[strcspn(dest, "\r\n")] = 0;

            // PEEPHOLE RULE 1: Redundant Register Move (e.g., MOV R0, R0)
            if (strcmp(dest, src) == 0) {
                fprintf(stdout, "    ; Peephole optimized out: %s", current_instruction);
                return; // Skip emitting
            }

            // PEEPHOLE RULE 2: Redundant Load/Store Reversal
            char last_dest[128] = {0}, last_src[128] = {0};
            if (sscanf(last_emitted_instruction, "    MOV   %[^,], %s", last_dest, last_src) == 2) {
                last_src[strcspn(last_src, "\r\n")] = 0;
                last_dest[strcspn(last_dest, "\r\n")] = 0;
                
                // If current is "MOV A, B" and last was "MOV B, A"
                if (strcmp(dest, last_src) == 0 && strcmp(src, last_dest) == 0) {
                    fprintf(stdout, "    ; Peephole optimized out: %s", current_instruction);
                    return; // Skip emitting
                }
            }
        }
    }

    // If it survived the optimizer, print it to the file
    fprintf(stdout, "%s", current_instruction);

    // Only remember actual instructions for peephole lookbacks. 
    // If we hit a label (starts with text) or a blank line, clear the memory 
    // so we don't accidentally optimize across branch boundaries.
    if (current_instruction[0] == ' ' && current_instruction[4] != ';') {
        strcpy(last_emitted_instruction, current_instruction);
    } else {
        last_emitted_instruction[0] = '\0';
    }
}

// Recursively scans a block of AST nodes to determine if it performs any operations
// that require an explicit stack frame layout (Leaf Function Optimization).
static int check_needs_stack(ASTNode *node) {
    if (!node) return 0;

    switch (node->type) {
        // Core operations that invoke internal subroutines, alter SP, or manipulate context
        case NODE_FUNCTION_CALL:
        case NODE_CONCAT:
        case NODE_TABLE_SET:
        case NODE_TABLE_GET:
        case NODE_ASM:
        case NODE_RAWASM:
            return 1;

        case NODE_IDENTIFIER:
            // OOP method invocations that read implicit 'self' parameters depend on [BP+2]
            if (node->as.id.name && strcmp(node->as.id.name, "self") == 0) {
                return 1;
            }
            break;

        case NODE_RETURN: {
            int ret_count = 0;
            ASTNode *expr = node->as.return_stmt.expressions_head;
            while (expr) {
                ret_count++;
                if (check_needs_stack(expr)) return 1;
                expr = expr->next;
            }
            // Vircon32 layout spills return parameters 4+ directly onto stack offsets via BP
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

        case NODE_MULTIPLE_ASSIGNMENT:
            if (check_needs_stack(node->as.mult_assign.right_side_call)) return 1;
            if (check_needs_stack(node->as.mult_assign.targets_head)) return 1;
            break;

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

    // Traverse remaining sequential sibling statements in this block
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

            while (*p && *p != '}' && i < 255) {
                var_name[i++] = *p++;
            }
            var_name[i] = '\0'; 

            if (*p == '}') p++; 

            fprintf (stdout, "[__var_%s]", var_name);

        } else {
            putchar (*p);
            p++;
        }
    }
    putchar ('\n');
    // Clear optimizer state after raw asm since we don't know what it did
    last_emitted_instruction[0] = '\0'; 
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
            if (node -> as.if_stmt.else_body) {
                generate_block (node -> as.if_stmt.else_body);
            }
            emit_asm ("__%s_end_if_%d:\n", ctx, label_id);
            break;
        }

        case NODE_FUNCTION_DEF: {
            push_function_context (node -> as.function_def.name);
            emit_asm ("_%s:\n", node -> as.function_def.name);
            
            // Run AST pre-scan to determine if stack activation record can be safely omitted
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

            if (arg_count > 0) {
                emit_asm ("    ISUB  SP, %d\n", arg_count);
            }
            
            if (dest_reg != 0) {
                emit_asm ("    MOV   R%d, R0\n", dest_reg);
            }
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
            generate_asm (node -> as.mult_assign.right_side_call, dest_reg);
            if (node -> as.mult_assign.targets_head && node -> as.mult_assign.targets_head -> type == NODE_IDENTIFIER) {
                // Ensure global variable tracker structures map out RAM allocation offsets
                get_global_variable_address (node -> as.mult_assign.targets_head -> as.id.name);
                emit_asm ("    MOV   [__var_%s], R%d ; Assigning to RAM-based variable\n", node -> as.mult_assign.targets_head -> as.id.name, dest_reg);
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
            
            if (dest_reg != 0) {
                emit_asm ("    MOV   R%d, R0\n", dest_reg);
            }
            break;
        }

        case NODE_TABLE_CONSTRUCTOR: {
            emit_asm ("    MOV   R%d, [0] ; Read __heap_pointer\n", dest_reg);
            
            int zero_reg = allocate_register ();
            emit_asm ("    MOV   R%d, 0\n", zero_reg);
            emit_asm ("    MOV   [R%d], R%d ; Initialize to nil/0\n", dest_reg, zero_reg);
            unlock_register (zero_reg);
            
            int temp_reg = allocate_register();
            emit_asm ("    MOV   R%d, [0]\n", temp_reg);
            emit_asm ("    IADD  R%d, 1\n", temp_reg); 
            emit_asm ("    MOV   [0], R%d ; Advance heap pointer\n", temp_reg);
            unlock_register(temp_reg);
            break;
        }

        case NODE_TABLE_SET: {
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
            int key_reg = allocate_register ();
            generate_asm (node -> as.table_get.key, key_reg);

            int tbl_reg = allocate_register();
            generate_asm (node -> as.table_get.table_expr, tbl_reg);
            
            emit_asm ("    MOV   R1, R%d\n", tbl_reg);
            emit_asm ("    MOV   R2, R%d\n", key_reg);
            emit_asm ("    CALL  __builtin_table_get\n");
            
            unlock_register (key_reg);
            unlock_register (tbl_reg);
            
            if (dest_reg != 0) {
                emit_asm ("    MOV   R%d, R0\n", dest_reg);
            }
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

            // Cleaned up unused variable declarations while keeping memory maps safe
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

void generate_program (ASTNode *head) {
    emit_asm (";; --- Compiled Code Entry Vector ---\n");
    emit_asm ("    CALL  __init_globals  ; Run top-level setups first\n");
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

    emit_asm ("\n;; --- Global Initialization Vector ---\n");
    emit_asm ("__init_globals:\n");
    emit_asm ("    PUSH  BP\n");
    emit_asm ("    MOV   BP, SP\n");

    current = head;
    while (current != NULL) {
        if (current -> type != NODE_FUNCTION_DEF) {
            int temp_reg = allocate_register();
            generate_asm (current, temp_reg);
            unlock_register (temp_reg);
        }
        current = current -> next;
    }

    emit_asm ("    MOV   SP, BP\n");
    emit_asm ("    POP   BP\n");
    emit_asm ("    RET\n");
}
