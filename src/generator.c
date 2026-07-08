#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "codegen.h"

void  generate_block (ASTNode *node) {
    while (node != NULL) {
        generate_asm (node); // Now safely processes exactly one node
        node = node -> next;
    }
}

static void  emit_interpolated_asm (const char *raw_code) {
    const char *p = raw_code;

    while (*p) {
        if (*p == '{') {
            p++; // Skip the '{'
            char var_name[256];
            int i = 0;

            // Extract the variable name until we hit '}'
            while (*p && *p != '}' && i < 255) {
                var_name[i++] = *p++;
            }
            var_name[i] = '\0'; // Null-terminate

            if (*p == '}') p++; // Skip the '}'

            // Output the Vircon32 memory bracket syntax for your variables
            // Example: {height} becomes [__var_height]
            fprintf (stdout, "[__var_%s]", var_name);

        } else {
            // Just output standard assembly characters
            putchar (*p);
            p++;
        }
    }
    putchar ('\n');
}

void  generate_asm (ASTNode *node) {
    if (!node) return;

    switch (node -> type) {
        
        case NODE_WHILE: {
            int label_id = get_next_label ();
            const char *ctx = get_current_function_name ();
            push_loop (label_id);
            
            fprintf (stdout, "__%s_while_start_%d:\n", ctx, label_id);
            generate_asm (node -> as.while_loop.condition);
            
            fprintf (stdout, "    JF    R0, __%s_while_end_%d\n", ctx, label_id);
            
            generate_block (node -> as.while_loop.body);
            
            fprintf (stdout, "    JMP   __%s_while_start_%d\n", ctx, label_id);
            fprintf (stdout, "__%s_while_end_%d:\n", ctx, label_id);
            pop_loop ();
            break;
        }

        case NODE_BREAK: {
            int current_id = current_loop ();
            if (current_id == -1) {
                fprintf (stderr, "Compiler Runtime Error: 'break' declaration found outside loop body scope.\n");
                exit (1);
            }
            fprintf (stdout, "    JMP   __%s_while_end_%d\n", get_current_function_name (), current_id);
            break;
        }

        case NODE_IF: {
            int label_id = get_next_label ();
            const char *ctx = get_current_function_name ();
            
            generate_asm (node -> as.if_stmt.condition);
            
            fprintf (stdout, "    JF    R0, __%s_else_%d\n", ctx, label_id);
            
            generate_block (node -> as.if_stmt.if_body);
            fprintf (stdout, "    JMP   __%s_end_if_%d\n", ctx, label_id);
            
            fprintf (stdout, "__%s_else_%d:\n", ctx, label_id);
            if (node -> as.if_stmt.else_body) {
                generate_block (node -> as.if_stmt.else_body);
            }
            fprintf (stdout, "__%s_end_if_%d:\n", ctx, label_id);
            break;
        }

        case NODE_FUNCTION_DEF: {
            push_function_context (node -> as.function_def.name);
            fprintf (stdout, "_%s:\n", node -> as.function_def.name);
            fprintf (stdout, "    PUSH  BP\n");
            fprintf (stdout, "    MOV   BP, SP\n");
            
            generate_block (node -> as.function_def.body);
            
            fprintf (stdout, "__%s_return:\n", get_current_function_name ());
            fprintf (stdout, "    MOV   SP, BP\n");
            fprintf (stdout, "    POP   BP\n");
            fprintf (stdout, "  RET\n");
            pop_function_context ();
            break;
        }

        case NODE_FUNCTION_CALL: {
            int arg_count = 0;

            if (node -> as.call.is_method_call) {
                fprintf (stdout, "  ; --- Injecting implicit 'self' ---\n");
                generate_asm (node -> as.call.target -> as.table_get.table_expr);
                fprintf (stdout, "    PUSH  R0\n");
                arg_count++;
            }

            ASTNode *current_arg = node -> as.call.args_head;
            while (current_arg != NULL) {
                generate_asm (current_arg);
                fprintf (stdout, "    PUSH  R0\n");
                arg_count++;
                current_arg = current_arg -> next;
            }

            generate_asm (node -> as.call.target);
            fprintf (stdout, "    CALL  R0\n");

            if (arg_count > 0) {
                fprintf (stdout, "    ISUB  SP, %d\n", arg_count);
            }
            break;
        }

        case NODE_FUNCTION_POINTER: {
            fprintf (stdout, "  ; Load address of the mangled function into R0\n");
            fprintf (stdout, "    MOV   R0, _%s\n", node -> as.func_ptr.mangled_name);
            break;
        }

        case NODE_RETURN: {
            ASTNode *expr = node -> as.return_stmt.expressions_head;
            int ret_idx = 0;
            int arg_count = node -> as.return_stmt.parent_func_arg_count;
            
            while (expr != NULL) {
                generate_asm (expr); 
                if (ret_idx == 0)      { /*Value naturally preserved in R0 */ }
                else if (ret_idx == 1) { fprintf (stdout, "    MOV   R2, R0\n"); }
                else if (ret_idx == 2) { fprintf (stdout, "    MOV   R3, R0\n"); }
                else {
                    int offset = 2 + arg_count + (ret_idx - 3);
                    fprintf (stdout, "    MOV   [BP + %d], R0\n", offset);
                }
                ret_idx++;
                expr = expr -> next;
            }
            fprintf (stdout, "    JMP   __%s_return\n", get_current_function_name ());
            break;
        }

        case NODE_MULTIPLE_ASSIGNMENT: {
            generate_asm (node -> as.mult_assign.right_side_call);
            if (node -> as.mult_assign.targets_head && node -> as.mult_assign.targets_head -> type == NODE_IDENTIFIER) {
                int addr = get_global_variable_address (node -> as.mult_assign.targets_head -> as.id.name);
                fprintf (stdout, "    MOV   [%d], R0 ; Assigning to RAM-based variable: _%s\n", addr, node -> as.mult_assign.targets_head -> as.id.name);
            }
            break;
        }

        case NODE_ADD: {
            generate_asm (node -> as.binary.left);
            int left_reg = allocate_register ();
            fprintf (stdout, "    MOV   R%d, R0\n", left_reg);

            generate_asm (node -> as.binary.right);
            fprintf (stdout, "    FADD  R%d, R0\n", left_reg);
            fprintf (stdout, "    MOV   R0, R%d\n", left_reg); // Result back to R0
            
            unlock_register (left_reg);
            break;
        }

        case NODE_SUB: {
            generate_asm (node -> as.binary.left);
            int left_reg = allocate_register ();
            fprintf (stdout, "    MOV   R%d, R0\n", left_reg);

            generate_asm (node -> as.binary.right);
            fprintf (stdout, "    FSUB  R%d, R0\n", left_reg);
            fprintf (stdout, "    MOV   R0, R%d\n", left_reg);
            
            unlock_register (left_reg);
            break;
        }
        
        case NODE_MUL: {
            generate_asm (node -> as.binary.left);
            int left_reg = allocate_register ();
            fprintf (stdout, "    MOV   R%d, R0\n", left_reg);

            generate_asm (node -> as.binary.right);
            fprintf (stdout, "    FMUL  R%d, R0\n", left_reg);
            fprintf (stdout, "    MOV   R0, R%d\n", left_reg);
            
            unlock_register (left_reg);
            break;
        }
        
        case NODE_DIV: {
            generate_asm (node -> as.binary.left);
            int left_reg = allocate_register ();
            fprintf (stdout, "    MOV   R%d, R0\n", left_reg);

            generate_asm (node -> as.binary.right);
            fprintf (stdout, "    FDIV  R%d, R0\n", left_reg);
            fprintf (stdout, "    MOV   R0, R%d\n", left_reg);
            
            unlock_register (left_reg);
            break;
        }

        case NODE_AND: {
            int label_id = get_next_label ();
            generate_asm (node -> as.binary.left);
            
            fprintf (stdout, "    JF    R0, __short_and_%d\n", label_id);
            
            generate_asm (node -> as.binary.right);
            fprintf (stdout, "__short_and_%d:\n", label_id);
            break;
        }

        case NODE_OR: {
            int label_id = get_next_label ();
            generate_asm (node -> as.binary.left);
            
            fprintf (stdout, "    JT    R0, __short_or_%d\n", label_id);
            
            generate_asm (node -> as.binary.right);
            fprintf (stdout, "__short_or_%d:\n", label_id);
            break;
        }

        case NODE_RELATIONAL: {
            generate_asm (node -> as.binary.left);
            int left_reg = allocate_register ();
            fprintf (stdout, "    MOV   R%d, R0\n", left_reg);

            generate_asm (node -> as.binary.right);
            
            switch (node -> as.binary.operator) {
                case OP_EQ: fprintf (stdout, "    FEQ   R%d, R0\n", left_reg); break;
                case OP_NEQ: fprintf (stdout, "    FNE   R%d, R0\n", left_reg); break;
                case OP_LT: fprintf (stdout, "    FLT   R%d, R0\n", left_reg); break;
                case OP_LE: fprintf (stdout, "    FLE   R%d, R0\n", left_reg); break;
                case OP_GT: fprintf (stdout, "    FGT   R%d, R0\n", left_reg); break;
                case OP_GE: fprintf (stdout, "    FGE   R%d, R0\n", left_reg); break;
            }
            
            fprintf (stdout, "    MOV   R0, R%d\n", left_reg);
            unlock_register (left_reg);
            break;
        }

        case NODE_STRING: {
            int str_id = add_string_literal (node -> as.string_val.value);
            fprintf (stdout, "    MOV   R0, __string_%d\n", str_id);
            break;
        }

        case NODE_CONCAT: {
            generate_asm (node -> as.binary.left);
            fprintf (stdout, "    PUSH  R0\n");
            generate_asm (node -> as.binary.right);
            fprintf (stdout, "    PUSH  R0\n");
            fprintf (stdout, "    CALL  __builtin_strcat\n");
            fprintf (stdout, "    ISUB  SP, 2\n");
            break;
        }

        case NODE_TABLE_CONSTRUCTOR: {
            fprintf (stdout, "    MOV   R0, [0] ; Read __heap_pointer\n");
            int ptr_reg = allocate_register ();
            fprintf (stdout, "    MOV   R%d, R0\n", ptr_reg);
            
            int zero_reg = allocate_register ();
            fprintf (stdout, "    MOV   R%d, 0\n", zero_reg);
            fprintf (stdout, "    MOV   [R%d], R%d ; Initialize to nil/0\n", ptr_reg, zero_reg);
            unlock_register (zero_reg);
            
            fprintf (stdout, "    MOV   R0, [0]\n");
            fprintf (stdout, "    IADD  R0, 1\n"); 
            fprintf (stdout, "    MOV   [0], R0 ; Advance heap pointer\n");
            
            fprintf (stdout, "    MOV   R0, R%d ; Return allocated pointer\n", ptr_reg);
            unlock_register (ptr_reg);
            break;
        }

        case NODE_TABLE_SET: {
            generate_asm (node -> as.table_set.value);
            fprintf (stdout, "    PUSH  R0\n");
            generate_asm (node -> as.table_set.key);
            fprintf (stdout, "    PUSH  R0\n");
            generate_asm (node -> as.table_set.table_expr);
            fprintf (stdout, "    PUSH  R0\n");
            fprintf (stdout, "    CALL  __builtin_table_set\n");
            fprintf (stdout, "    ISUB  SP, 3\n");
            break;
        }

        case NODE_TABLE_GET: {
            generate_asm (node -> as.table_get.key);
            int key_reg = allocate_register ();
            fprintf (stdout, "    MOV   R%d, R0\n", key_reg);

            generate_asm (node -> as.table_get.table_expr);
            
            // Expected by __builtin_table_get: R1 = Table Pointer, R2 = Key
            fprintf (stdout, "    MOV   R1, R0\n");
            fprintf (stdout, "    MOV   R2, R%d\n", key_reg);
            fprintf (stdout, "    CALL  __builtin_table_get\n");
            
            unlock_register (key_reg);
            // Result safely sitting in R0
            break;
        }

        case NODE_IDENTIFIER: {
            if (strcmp (node -> as.id.name, "self") == 0) {
                fprintf (stdout, "  ; --- Loading local parameter 'self' ---\n");
                fprintf (stdout, "    MOV   R0, [BP+2]\n"); 
            } else {
                fprintf (stdout, "    MOV   R0, [__var_%s]\n", node -> as.id.name);
            }
            break;
        }
            
        case NODE_NUMBER:
            fprintf (stdout, "    MOV   R0, %f\n", node -> as.number.val);
            break;
            
        case NODE_ASM: {
            fprintf (stdout, "  ; --- Begin Inline ASM Bubble (existing register states preserved) ---\n");

            // 1. Allocate and snapshot stack controls to safe RAM slots
            int sp_snap = get_global_variable_address ("__asm_snap_sp");
            int bp_snap = get_global_variable_address ("__asm_snap_bp");
            fprintf (stdout, "    MOV   [%d], SP\n", sp_snap);
            fprintf (stdout, "    MOV   [%d], BP\n", bp_snap);

            // 2. Map and snapshot ONLY the currently allocated active registers
            for (int i = 0; i < NUM_GPRS; i++) {
                if (is_register_locked (i)) {
                    char snap_name[16];
                    sprintf (snap_name, "__asm_snap_r%d", i);
                    int reg_ram_addr = get_global_variable_address (snap_name);
                    fprintf (stdout, "    MOV   [%d], R%d\n", reg_ram_addr, i);
                }
            }
            
            // 3. Output User's Raw Assembly
            emit_interpolated_asm (node -> as.inline_asm.code);

            // 4. Restore the allocated active working registers from RAM
            for (int i = 0; i < NUM_GPRS; i++) {
                if (is_register_locked (i)) {
                    char snap_name[16];
                    sprintf (snap_name, "__asm_snap_r%d", i);
                    int reg_ram_addr = get_global_variable_address (snap_name);
                    fprintf (stdout, "    MOV   R%d, [%d]\n", i, reg_ram_addr);
                }
            }

            // 5. Force restore the stack frame and pointer, deleting any user stack errors
            fprintf (stdout, "    MOV   BP, [%d]\n", bp_snap);
            fprintf (stdout, "    MOV   SP, [%d]\n", sp_snap);

            fprintf (stdout, "  ; --- End Inline ASM Bubble (previous register states restored) ---\n");
            break;
        }

        case NODE_RAWASM: {
            fprintf (stdout, "  ; --- Begin Raw ASM (Unprotected) ---\n");
            emit_interpolated_asm (node -> as.inline_asm.code);
            fprintf (stdout, "  ; --- End Raw ASM ---\n");
            break;
        }
    }
}

void  generate_global_setup (ASTNode *node) {
    while (node != NULL) {
        if (node -> type != NODE_FUNCTION_DEF) {
            ASTNode *next_sibling = node -> next;
            node -> next = NULL;
            generate_asm (node);
            node -> next = next_sibling;
        }
        node = node -> next;
    }
}

void  generate_functions (ASTNode *node) {
    while (node != NULL) {
        if (node -> type == NODE_FUNCTION_DEF) {
            ASTNode *next_sibling = node -> next;
            node -> next = NULL;
            generate_asm (node);
            node -> next = next_sibling;
        }
        node = node -> next;
    }
}

void  generate_program (ASTNode *head) {
    fprintf (stdout, ";; --- Compiled Code Entry Vector ---\n");
    fprintf (stdout, "    CALL  __init_globals  ; Run top-level setups first\n");
    fprintf (stdout, "    CALL  _main           ; Then hand control to the user\n");
    fprintf (stdout, "    HLT                   ; Halt CPU when main finishes\n\n");

    fprintf (stdout, "; --- Function Definitions ---\n");
    ASTNode *current = head;
    while (current != NULL) {
        if (current -> type == NODE_FUNCTION_DEF) {
            generate_asm (current);
        }
        current = current -> next;
    }

    fprintf (stdout, "\n;; --- Global Initialization Vector ---\n");
    fprintf (stdout, "__init_globals:\n");
    fprintf (stdout, "    PUSH  BP\n");
    fprintf (stdout, "    MOV   BP, SP\n");

    current = head;
    while (current != NULL) {
        if (current -> type != NODE_FUNCTION_DEF) {
            generate_asm (current);
        }
        current = current -> next;
    }

    fprintf (stdout, "    MOV   SP, BP\n");
    fprintf (stdout, "    POP   BP\n");
    fprintf (stdout, "  RET\n");
}
