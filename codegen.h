#ifndef CODEGEN_H
#define CODEGEN_H

// --- Enums ---
typedef enum {
    NODE_WHILE,
    NODE_BREAK,
    NODE_IF,
    NODE_FUNCTION_DEF,
    NODE_FUNCTION_CALL,
    NODE_RETURN,
    NODE_MULTIPLE_ASSIGNMENT,
    NODE_AND,
    NODE_OR,
    NODE_RELATIONAL,
    NODE_STRING,
    NODE_CONCAT,
    NODE_TABLE_CONSTRUCTOR,
    NODE_TABLE_SET,
    NODE_TABLE_GET,
    NODE_IDENTIFIER,
    NODE_NUMBER
} NodeType;

typedef enum {
    OP_EQ,
    OP_NEQ,
    OP_LT,
    OP_GT,
    OP_LE,
    OP_GE
} Operator;

// --- AST Node Structure ---
typedef struct ASTNode {
    NodeType type;
    struct ASTNode* next; // For linked lists of statements/expressions

    union {
        struct {
            struct ASTNode* condition;
            struct ASTNode* body;
        } while_loop;

        struct {
            struct ASTNode* condition;
            struct ASTNode* if_body;
            struct ASTNode* else_body;
        } if_stmt;

        struct {
            char* name;
            struct ASTNode* body;
        } function_def;

        struct {
            char* name;
            struct ASTNode* args_head; 
        } call; // Standardized as 'call' to fix the GCC error

        struct {
            struct ASTNode* expressions_head;
            int parent_func_arg_count;
        } return_stmt;

        struct {
            struct ASTNode* right_side_call;
            struct ASTNode* targets_head;
        } mult_assign;

        struct {
            struct ASTNode* left;
            struct ASTNode* right;
            Operator operator;
        } binary;

        struct {
            char* value;
        } string_val;

        struct {
            struct ASTNode* table_expr;
            struct ASTNode* key;
            struct ASTNode* value;
        } table_set;

        struct {
            struct ASTNode* table_expr;
            struct ASTNode* key;
        } table_get;

        struct {
            char* name;
        } id;

        struct {
            double val;
        } number;
    } as;
} ASTNode;

// --- Core Compiler Functions ---
void generate_asm(ASTNode* node);

// --- Context & Memory Management (implemented in context.c) ---
int get_next_label(void);
int add_string_literal(const char* str);
void emit_string_data_section(void);

void push_function_context(const char* name);
void pop_function_context(void);
const char* get_current_function_name(void);

void push_loop(int id);
void pop_loop(void);
int current_loop(void);

int get_global_variable_address(const char* name);

#endif // CODEGEN_H
