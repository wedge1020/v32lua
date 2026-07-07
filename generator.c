#include "codegen.h"

// External utilities from context.c
int get_next_label(void);
int add_string_literal(const char* str);
const char* get_current_function_name(void);
void push_function_context(const char* name);
void pop_function_context(void);
void push_loop(int id);
void pop_loop(void);
int current_loop(void);

void generate_asm(ASTNode* node) {
    if (!node) return;

    switch(node->type) {
        
        case NODE_WHILE: {
            int label_id = get_next_label();
            const char* ctx = get_current_function_name();
            push_loop(label_id);
            
            printf("__%s_while_start_%d:\n", ctx, label_id);
            generate_asm(node->as.while_loop.condition);
            printf("  JF __%s_while_end_%d\n", ctx, label_id);
            
            generate_asm(node->as.while_loop.body);
            
            printf("  JMP __%s_while_start_%d\n", ctx, label_id);
            printf("__%s_while_end_%d:\n", ctx, label_id);
            pop_loop();
            break;
        }

        case NODE_BREAK: {
            int current_id = current_loop();
            if (current_id == -1) {
                fprintf(stderr, "Syntax Error: 'break' outside of loop context.\n");
                exit(1);
            }
            printf("  JMP __%s_while_end_%d\n", get_current_function_name(), current_id);
            break;
        }

        case NODE_IF: {
            int label_id = get_next_label();
            const char* ctx = get_current_function_name();
            
            generate_asm(node->as.if_stmt.condition);
            printf("  JF __%s_else_%d\n", ctx, label_id);
            
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
            printf("%s:\n", node->as.function_def.name);
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

        case NODE_RETURN: {
            ASTNode* expr = node->as.return_stmt.expressions_head;
            int ret_idx = 0;
            int arg_count = node->as.return_stmt.parent_func_arg_count;
            
            while (expr != NULL) {
                generate_asm(expr); // Result in R0
                if (ret_idx == 0)      { /* Stays in R0 */ }
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

        case NODE_AND: {
            int label_id = get_next_label();
            generate_asm(node->as.binary.left);
            printf("  JF __short_and_%d\n", label_id);
            generate_asm(node->as.binary.right);
            printf("__short_and_%d:\n", label_id);
            break;
        }

        case NODE_OR: {
            int label_id = get_next_label();
            generate_asm(node->as.binary.left);
            printf("  JT __short_or_%d\n", label_id);
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
                case OP_EQ:  printf("  FEQ R0, R1, R0\n"); break;
                case OP_NEQ: printf("  FNE R0, R1, R0\n"); break;
                case OP_LT:  printf("  FLT R0, R1, R0\n"); break;
                case OP_GT:  printf("  FGT R0, R1, R0\n"); break;
                case OP_LE:  printf("  FLE R0, R1, R0\n"); break;
                case OP_GE:  printf("  FGE R0, R1, R0\n"); break;
            }
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
            printf("  SUB SP, 2\n");
            break;
        }

        case NODE_TABLE_CONSTRUCTOR: {
            printf("  MOV R0, [__heap_pointer]\n");
            printf("  PUSH R0\n");
            printf("  MOV R1, 0\n");
            printf("  MOV [R0], R1\n"); // Head pointer = NULL
            printf("  MOV R1, [__heap_pointer]\n");
            printf("  ADD R1, 1\n");
            printf("  MOV [__heap_pointer], R1\n");
            printf("  POP R0\n");
            break;
        }

        case NODE_TABLE_SET: {
            generate_asm(node->as.table_set.value); printf("  PUSH R0\n");
            generate_asm(node->as.table_set.key);   printf("  PUSH R0\n");
            generate_asm(node->as.table_set.table_expr); printf("  PUSH R0\n");
            printf("  CALL __builtin_table_set\n");
            printf("  SUB SP, 3\n");
            break;
        }

        case NODE_TABLE_GET: {
            generate_asm(node->as.table_get.key);   printf("  PUSH R0\n");
            generate_asm(node->as.table_get.table_expr); printf("  PUSH R0\n");
            printf("  CALL __builtin_table_get\n");
            printf("  SUB SP, 2\n");
            break;
        }
        
        // Basic terminal fallbacks for compilation flow tracing
        case NODE_IDENTIFIER:
            printf("  MOV R0, [%s]\n", node->as.id.name);
            break;
        case NODE_NUMBER:
            printf("  MOV R0, %f\n", node->as.number.val);
            break;
    }
}
