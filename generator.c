#include <stdio.h>
#include <stdlib.h>
#include "codegen.h"

void generate_asm(ASTNode* node) {
    if (!node) return;

    switch(node->type) {
        
        case NODE_WHILE: {
            int label_id = get_next_label();
            const char* ctx = get_current_function_name();
            push_loop(label_id);
            
            printf("__%s_while_start_%d:\n", ctx, label_id);
            generate_asm(node->as.while_loop.condition);
            
            printf("  JF R0, __%s_while_end_%d\n", ctx, label_id);
            
            generate_asm(node->as.while_loop.body);
            
            printf("  JMP __%s_while_start_%d\n", ctx, label_id);
            printf("__%s_while_end_%d:\n", ctx, label_id);
            pop_loop();
            break;
        }

        case NODE_BREAK: {
            int current_id = current_loop();
            if (current_id == -1) {
                fprintf(stderr, "Compiler Runtime Error: 'break' declaration found outside loop body scope.\n");
                exit(1);
            }
            printf("  JMP __%s_while_end_%d\n", get_current_function_name(), current_id);
            break;
        }

        case NODE_IF: {
            int label_id = get_next_label();
            const char* ctx = get_current_function_name();
            
            generate_asm(node->as.if_stmt.condition);
            
            printf("  JF R0, __%s_else_%d\n", ctx, label_id);
            
            generate_asm(node->as.if_stmt.if_body);
            printf("  JMP __%s_end_if_%d\n", ctx, label_id);
            
            printf("__%s_else_%d:\n", ctx, label_id);
            if (node->as.if_stmt.else_body) {
                generate_asm(node->as.if_stmt.else_body);
            }
            printf("__%s_end_if_%d:\n", ctx, label_id);
            break;
        }

        case NODE_FUNCTION_DEF: {
            push_function_context(node->as.function_def.name);
            printf("_%s:\n", node->as.function_def.name);
            printf("  PUSH BP\n");
            printf("  MOV BP, SP\n");
            
            generate_asm(node->as.function_def.body);
            
            printf("__%s_return:\n", get_current_function_name());
            printf("  MOV SP, BP\n");
            printf("  POP BP\n");
            printf("  RET\n");
            pop_function_context();
            break;
        }

        case NODE_FUNCTION_CALL: {
            int arg_count = 0;
            ASTNode* current_arg = node->as.call.args_head;

            // 1. Evaluate and push all arguments
            while (current_arg != NULL) {
                generate_asm(current_arg);
                printf("  PUSH R0\n");
                arg_count++;
                current_arg = current_arg->next;
            }

            // 2. Evaluate the target expression (e.g., table lookup or variable)
            // This will leave the function's memory address in R0
            generate_asm(node->as.call.target);

            // 3. Dynamically call the address stored in R0
            printf("  CALL R0\n");

            // 4. Clean up the stack
            if (arg_count > 0) {
                printf("  ISUB SP, %d\n", arg_count);
            }
            break;
        }

		case NODE_FUNCTION_POINTER: {
            printf("  ; Load address of the mangled function into R0\n");
            printf("  MOV R0, _%s\n", node->as.func_ptr.mangled_name);
            break;
        }

        case NODE_RETURN: {
            ASTNode* expr = node->as.return_stmt.expressions_head;
            int ret_idx = 0;
            int arg_count = node->as.return_stmt.parent_func_arg_count;
            
            while (expr != NULL) {
                generate_asm(expr); 
                if (ret_idx == 0)      { /* Value naturally preserved in R0 */ }
                else if (ret_idx == 1) { printf("  MOV R2, R0\n"); }
                else if (ret_idx == 2) { printf("  MOV R3, R0\n"); }
                else {
                    int offset = 2 + arg_count + (ret_idx - 3);
                    printf("  MOV [BP + %d], R0\n", offset);
                }
                ret_idx++;
                expr = expr->next;
            }
            printf("  JMP __%s_return\n", get_current_function_name());
            break;
        }

        case NODE_MULTIPLE_ASSIGNMENT: {
            generate_asm(node->as.mult_assign.right_side_call);
            if (node->as.mult_assign.targets_head && node->as.mult_assign.targets_head->type == NODE_IDENTIFIER) {
                int addr = get_global_variable_address(node->as.mult_assign.targets_head->as.id.name);
                printf("  MOV [%d], R0 ; Assigning to RAM variable: _%s\n", addr, node->as.mult_assign.targets_head->as.id.name);
            }
            break;
        }

        case NODE_AND: {
            int label_id = get_next_label();
            generate_asm(node->as.binary.left);
            
            printf("  JF R0, __short_and_%d\n", label_id);
            
            generate_asm(node->as.binary.right);
            printf("__short_and_%d:\n", label_id);
            break;
        }

        case NODE_OR: {
            int label_id = get_next_label();
            generate_asm(node->as.binary.left);
            
            printf("  JT R0, __short_or_%d\n", label_id);
            
            generate_asm(node->as.binary.right);
            printf("__short_or_%d:\n", label_id);
            break;
        }

        case NODE_RELATIONAL: {
            generate_asm(node->as.binary.left);
            printf("  PUSH R0\n");
            generate_asm(node->as.binary.right);
            printf("  POP R1\n");
            
            switch (node->as.binary.operator) {
                case OP_EQ:  printf("  IEQ R1, R0\n"); break;
                case OP_NEQ: printf("  INE R1, R0\n"); break;
                case OP_LT:  printf("  ILT R1, R0\n"); break; 
                case OP_GT:  printf("  IGT R1, R0\n"); break; 
                case OP_LE:  printf("  ILE R1, R0\n"); break; 
                case OP_GE:  printf("  IGE R1, R0\n"); break; 
            }
            printf("  MOV R0, R1\n");
            break;
        }

        case NODE_STRING: {
            int str_id = add_string_literal(node->as.string_val.value);
            printf("  MOV R0, __string_%d\n", str_id);
            break;
        }

        case NODE_CONCAT: {
            generate_asm(node->as.binary.left);
            printf("  PUSH R0\n");
            generate_asm(node->as.binary.right);
            printf("  PUSH R0\n");
            printf("  CALL __builtin_strcat\n");
            // Corrected: Structural stack adjustment
            printf("  ISUB SP, 2\n");
            break;
        }

        case NODE_TABLE_CONSTRUCTOR: {
            printf("  MOV R0, [0] ; Read __heap_pointer from RAM slot 0\n");
            printf("  PUSH R0\n");
            printf("  MOV R1, 0\n");
            printf("  MOV [R0], R1\n");
            printf("  MOV R1, [0]\n");
            // Corrected: Pointer allocation math requires integer addition
            printf("  IADD R1, 1\n"); 
            printf("  MOV [0], R1 ; Update active RAM heap track pointer\n");
            printf("  POP R0\n");
            break;
        }

        case NODE_TABLE_SET: {
            generate_asm(node->as.table_set.value);      printf("  PUSH R0\n");
            generate_asm(node->as.table_set.key);        printf("  PUSH R0\n");
            generate_asm(node->as.table_set.table_expr); printf("  PUSH R0\n");
            printf("  CALL __builtin_table_set\n");
            // Corrected: Structural stack adjustment
            printf("  ISUB SP, 3\n");
            break;
        }

        case NODE_TABLE_GET: {
            generate_asm(node->as.table_get.key);        printf("  PUSH R0\n");
            generate_asm(node->as.table_get.table_expr); printf("  PUSH R0\n");
            printf("  CALL __builtin_table_get\n");
            // Corrected: Structural stack adjustment
            printf("  ISUB SP, 2\n");
            break;
        }
        
        case NODE_IDENTIFIER: {
            int addr = get_global_variable_address(node->as.id.name);
            printf("  MOV R0, [%d] ; Fetching from RAM variable: _%s\n", addr, node->as.id.name);
            break;
        }
            
        case NODE_NUMBER:
            printf("  MOV R0, %f\n", node->as.number.val);
            break;
    }
}
