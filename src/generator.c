#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "codegen.h"

void generate_block (ASTNode *node) {
    while (node != NULL) {
        // Blocks evaluate statements, we allocate a scratch register for the statement
        // and immediately free it since the result isn't needed by a parent expression.
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

void generate_asm (ASTNode *node, int dest_reg) {
    if (!node) return;

    switch (node -> type) {
        
        case NODE_WHILE: {
            int label_id = get_next_label ();
            const char *ctx = get_current_function_name ();
            push_loop (label_id);
            
            fprintf (stdout, "__%s_while_start_%d:\n", ctx, label_id);
            
            // Evaluate condition into a temporary register
            int cond_reg = allocate_register();
            generate_asm (node -> as.while_loop.condition, cond_reg);
            
            fprintf (stdout, "    JF    R%d, __%s_while_end_%d\n", cond_reg, ctx, label_id);
            unlock_register(cond_reg);
            
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
            
            // Evaluate condition into a temporary register
            int cond_reg = allocate_register();
            generate_asm (node -> as.if_stmt.condition, cond_reg);
            
            fprintf (stdout, "    JF    R%d, __%s_else_%d\n", cond_reg, ctx, label_id);
            unlock_register(cond_reg);
            
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
                int self_reg = allocate_register();
                generate_asm (node -> as.call.target -> as.table_get.table_expr, self_reg);
                fprintf (stdout, "    PUSH  R%d\n", self_reg);
                unlock_register(self_reg);
                arg_count++;
            }

            ASTNode *current_arg = node -> as.call.args_head;
            while (current_arg != NULL) {
                int arg_reg = allocate_register();
                generate_asm (current_arg, arg_reg);
                fprintf (stdout, "    PUSH  R%d\n", arg_reg);
                unlock_register(arg_reg);
                arg_count++;
                current_arg = current_arg -> next;
            }

            int target_reg = allocate_register();
            generate_asm (node -> as.call.target, target_reg);
            fprintf (stdout, "    CALL  R%d\n", target_reg);
            unlock_register(target_reg);

            if (arg_count > 0) {
                fprintf (stdout, "    ISUB  SP, %d\n", arg_count);
            }
            
            // The ABI dictates return values are in R0. Move to the requested destination.
            if (dest_reg != 0) {
                fprintf (stdout, "    MOV   R%d, R0\n", dest_reg);
            }
            break;
        }

        case NODE_FUNCTION_POINTER: {
            fprintf (stdout, "  ; Load address of the mangled function\n");
            fprintf (stdout, "    MOV   R%d, _%s\n", dest_reg, node -> as.func_ptr.mangled_name);
            break;
        }

        case NODE_RETURN: {
            ASTNode *expr = node -> as.return_stmt.expressions_head;
            int ret_idx = 0;
            int arg_count = node -> as.return_stmt.parent_func_arg_count;
            
            while (expr != NULL) {
                int val_reg = allocate_register();
                generate_asm (expr, val_reg); 
                
                // ABI routing for multiple returns
                if (ret_idx == 0)      { fprintf (stdout, "    MOV   R0, R%d\n", val_reg); }
                else if (ret_idx == 1) { fprintf (stdout, "    MOV   R2, R%d\n", val_reg); }
                else if (ret_idx == 2) { fprintf (stdout, "    MOV   R3, R%d\n", val_reg); }
                else {
                    int offset = 2 + arg_count + (ret_idx - 3);
                    fprintf (stdout, "    MOV   [BP + %d], R%d\n", offset, val_reg);
                }
                unlock_register(val_reg);
                
                ret_idx++;
                expr = expr -> next;
            }
            fprintf (stdout, "    JMP   __%s_return\n", get_current_function_name ());
            break;
        }

        case NODE_MULTIPLE_ASSIGNMENT: {
            generate_asm (node -> as.mult_assign.right_side_call, dest_reg);
            if (node -> as.mult_assign.targets_head && node -> as.mult_assign.targets_head -> type == NODE_IDENTIFIER) {
                int addr = get_global_variable_address (node -> as.mult_assign.targets_head -> as.id.name);
                fprintf (stdout, "    MOV   [%d], R%d ; Assigning to RAM-based variable: _%s\n", addr, dest_reg, node -> as.mult_assign.targets_head -> as.id.name);
            }
            break;
        }

        case NODE_ADD: {
            generate_asm (node -> as.binary.left, dest_reg);
            int right_reg = allocate_register ();
            
            generate_asm (node -> as.binary.right, right_reg);
            fprintf (stdout, "    FADD  R%d, R%d\n", dest_reg, right_reg);
            
            unlock_register (right_reg);
            break;
        }

        case NODE_SUB: {
            generate_asm (node -> as.binary.left, dest_reg);
            int right_reg = allocate_register ();
            
            generate_asm (node -> as.binary.right, right_reg);
            fprintf (stdout, "    FSUB  R%d, R%d\n", dest_reg, right_reg);
            
            unlock_register (right_reg);
            break;
        }
        
        case NODE_MUL: {
            generate_asm (node -> as.binary.left, dest_reg);
            int right_reg = allocate_register ();
            
            generate_asm (node -> as.binary.right, right_reg);
            fprintf (stdout, "    FMUL  R%d, R%d\n", dest_reg, right_reg);
            
            unlock_register (right_reg);
            break;
        }
        
        case NODE_DIV: {
            generate_asm (node -> as.binary.left, dest_reg);
            int right_reg = allocate_register ();
            
            generate_asm (node -> as.binary.right, right_reg);
            fprintf (stdout, "    FDIV  R%d, R%d\n", dest_reg, right_reg);
            
            unlock_register (right_reg);
            break;
        }

        case NODE_AND: {
            int label_id = get_next_label ();
            generate_asm (node -> as.binary.left, dest_reg);
            
            fprintf (stdout, "    JF    R%d, __short_and_%d\n", dest_reg, label_id);
            
            generate_asm (node -> as.binary.right, dest_reg);
            fprintf (stdout, "__short_and_%d:\n", label_id);
            break;
        }

        case NODE_OR: {
            int label_id = get_next_label ();
            generate_asm (node -> as.binary.left, dest_reg);
            
            fprintf (stdout, "    JT    R%d, __short_or_%d\n", dest_reg, label_id);
            
            generate_asm (node -> as.binary.right, dest_reg);
            fprintf (stdout, "__short_or_%d:\n", label_id);
            break;
        }

        case NODE_RELATIONAL: {
            generate_asm (node -> as.binary.left, dest_reg);
            int right_reg = allocate_register ();

            generate_asm (node -> as.binary.right, right_reg);
            
            switch (node -> as.binary.operator) {
                case OP_EQ:  fprintf (stdout, "    FEQ   R%d, R%d\n", dest_reg, right_reg); break;
                case OP_NEQ: fprintf (stdout, "    FNE   R%d, R%d\n", dest_reg, right_reg); break;
                case OP_LT:  fprintf (stdout, "    FLT   R%d, R%d\n", dest_reg, right_reg); break;
                case OP_LE:  fprintf (stdout, "    FLE   R%d, R%d\n", dest_reg, right_reg); break;
                case OP_GT:  fprintf (stdout, "    FGT   R%d, R%d\n", dest_reg, right_reg); break;
                case OP_GE:  fprintf (stdout, "    FGE   R%d, R%d\n", dest_reg, right_reg); break;
            }
            
            unlock_register (right_reg);
            break;
        }

        case NODE_STRING: {
            int str_id = add_string_literal (node -> as.string_val.value);
            fprintf (stdout, "    MOV   R%d, __string_%d\n", dest_reg, str_id);
            break;
        }

        case NODE_CONCAT: {
            int left_reg = allocate_register();
            generate_asm (node -> as.binary.left, left_reg);
            fprintf (stdout, "    PUSH  R%d\n", left_reg);
            unlock_register(left_reg);
            
            int right_reg = allocate_register();
            generate_asm (node -> as.binary.right, right_reg);
            fprintf (stdout, "    PUSH  R%d\n", right_reg);
            unlock_register(right_reg);
            
            fprintf (stdout, "    CALL  __builtin_strcat\n");
            fprintf (stdout, "    ISUB  SP, 2\n");
            
            if (dest_reg != 0) {
                fprintf (stdout, "    MOV   R%d, R0\n", dest_reg);
            }
            break;
        }

        case NODE_TABLE_CONSTRUCTOR: {
            fprintf (stdout, "    MOV   R%d, [0] ; Read __heap_pointer\n", dest_reg);
            
            int zero_reg = allocate_register ();
            fprintf (stdout, "    MOV   R%d, 0\n", zero_reg);
            fprintf (stdout, "    MOV   [R%d], R%d ; Initialize to nil/0\n", dest_reg, zero_reg);
            unlock_register (zero_reg);
            
            int temp_reg = allocate_register();
            fprintf (stdout, "    MOV   R%d, [0]\n", temp_reg);
            fprintf (stdout, "    IADD  R%d, 1\n", temp_reg); 
            fprintf (stdout, "    MOV   [0], R%d ; Advance heap pointer\n", temp_reg);
            unlock_register(temp_reg);
            
            // Pointer already resting in dest_reg
            break;
        }

        case NODE_TABLE_SET: {
            int val_reg = allocate_register();
            generate_asm (node -> as.table_set.value, val_reg);
            fprintf (stdout, "    PUSH  R%d\n", val_reg);
            unlock_register(val_reg);
            
            int key_reg = allocate_register();
            generate_asm (node -> as.table_set.key, key_reg);
            fprintf (stdout, "    PUSH  R%d\n", key_reg);
            unlock_register(key_reg);
            
            int tbl_reg = allocate_register();
            generate_asm (node -> as.table_set.table_expr, tbl_reg);
            fprintf (stdout, "    PUSH  R%d\n", tbl_reg);
            unlock_register(tbl_reg);
            
            fprintf (stdout, "    CALL  __builtin_table_set\n");
            fprintf (stdout, "    ISUB  SP, 3\n");
            break;
        }

        case NODE_TABLE_GET: {
            int key_reg = allocate_register ();
            generate_asm (node -> as.table_get.key, key_reg);

            int tbl_reg = allocate_register();
            generate_asm (node -> as.table_get.table_expr, tbl_reg);
            
            // Expected by __builtin_table_get: R1 = Table Pointer, R2 = Key
            fprintf (stdout, "    MOV   R1, R%d\n", tbl_reg);
            fprintf (stdout, "    MOV   R2, R%d\n", key_reg);
            fprintf (stdout, "    CALL  __builtin_table_get\n");
            
            unlock_register (key_reg);
            unlock_register (tbl_reg);
            
            // Result is in R0 per ABI
            if (dest_reg != 0) {
                fprintf (stdout, "    MOV   R%d, R0\n", dest_reg);
            }
            break;
        }

        case NODE_IDENTIFIER: {
            if (strcmp (node -> as.id.name, "self") == 0) {
                fprintf (stdout, "  ; --- Loading local parameter 'self' ---\n");
                fprintf (stdout, "    MOV   R%d, [BP+2]\n", dest_reg); 
            } else {
                fprintf (stdout, "    MOV   R%d, [__var_%s]\n", dest_reg, node -> as.id.name);
            }
            break;
        }
            
        case NODE_NUMBER:
            fprintf (stdout, "    MOV   R%d, %f\n", dest_reg, node -> as.number.val);
            break;
            
        case NODE_ASM: {
            fprintf (stdout, "  ; --- Begin Inline ASM Bubble (existing register states preserved) ---\n");

            int sp_snap = get_global_variable_address ("__asm_snap_sp");
            int bp_snap = get_global_variable_address ("__asm_snap_bp");
            fprintf (stdout, "    MOV   [%d], SP\n", sp_snap);
            fprintf (stdout, "    MOV   [%d], BP\n", bp_snap);

            for (int i = 0; i < NUM_GPRS; i++) {
                if (is_register_locked (i)) {
                    char snap_name[16];
                    sprintf (snap_name, "__asm_snap_r%d", i);
                    int reg_ram_addr = get_global_variable_address (snap_name);
                    fprintf (stdout, "    MOV   [%d], R%d\n", reg_ram_addr, i);
                }
            }
            
            emit_interpolated_asm (node -> as.inline_asm.code);

            for (int i = 0; i < NUM_GPRS; i++) {
                if (is_register_locked (i)) {
                    char snap_name[16];
                    sprintf (snap_name, "__asm_snap_r%d", i);
                    int reg_ram_addr = get_global_variable_address (snap_name);
                    fprintf (stdout, "    MOV   R%d, [%d]\n", i, reg_ram_addr);
                }
            }

            fprintf (stdout, "    MOV   BP, [%d]\n", bp_snap);
            fprintf (stdout, "    MOV   SP, [%d]\n", sp_snap);

            fprintf (stdout, "  ; --- End Inline ASM Bubble ---\n");
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

void generate_global_setup (ASTNode *node) {
    while (node != NULL) {
        if (node -> type != NODE_FUNCTION_DEF) {
            ASTNode *next_sibling = node -> next;
            node -> next = NULL;
            
            // Run global level evaluation using a scratch register
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
            
            // Functions handle their own internal context logic, dest_reg is arbitrary
            generate_asm (node, 0); 
            
            node -> next = next_sibling;
        }
        node = node -> next;
    }
}

void generate_program (ASTNode *head) {
    fprintf (stdout, ";; --- Compiled Code Entry Vector ---\n");
    fprintf (stdout, "    CALL  __init_globals  ; Run top-level setups first\n");
    fprintf (stdout, "    CALL  _main           ; Then hand control to the user\n");
    fprintf (stdout, "    HLT                   ; Halt CPU when main finishes\n\n");

    fprintf (stdout, "; --- Function Definitions ---\n");
    ASTNode *current = head;
    while (current != NULL) {
        if (current -> type == NODE_FUNCTION_DEF) {
            generate_asm (current, 0);
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
            int temp_reg = allocate_register();
            generate_asm (current, temp_reg);
            unlock_register (temp_reg);
        }
        current = current -> next;
    }

    fprintf (stdout, "    MOV   SP, BP\n");
    fprintf (stdout, "    POP   BP\n");
    fprintf (stdout, "    RET\n");
}
