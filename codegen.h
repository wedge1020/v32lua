#ifndef CODEGEN_H
#define CODEGEN_H

// --- Enums ---
typedef enum {
    NODE_WHILE,
    NODE_BREAK,
    NODE_IF,
    NODE_FUNCTION_DEF,
    NODE_FUNCTION_CALL,
    NODE_FUNCTION_POINTER,
    NODE_RETURN,
    NODE_MULTIPLE_ASSIGNMENT,
    NODE_ADD,
    NODE_SUB,
    NODE_MUL,
    NODE_DIV,
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
typedef struct astnode ASTNode;
struct astnode {
    NodeType type;
    ASTNode* next; // For linked lists of statements/expressions

    union {
        struct {
            ASTNode* condition;
            ASTNode* body;
        } while_loop;

        struct {
            ASTNode* condition;
            ASTNode* if_body;
            ASTNode* else_body;
        } if_stmt;

        struct {
            char* name;
            ASTNode* params;  // <-- Add this to hold your 'self' parameter (and others)
            ASTNode* body;
        } function_def;

        struct {
            ASTNode* target;
            ASTNode* args_head;
            int is_method_call; // <-- Add this boolean flag
        } call;

        // Inside your ASTNode union:
        struct {
            char* mangled_name;
        } func_ptr;

        struct {
            ASTNode* expressions_head;
            int parent_func_arg_count;
        } return_stmt;

        struct {
            ASTNode* right_side_call;
            ASTNode* targets_head;
        } mult_assign;

        struct {
            ASTNode* left;
            ASTNode* right;
            Operator operator;
        } binary;

        struct {
            char* value;
        } string_val;

        struct {
            ASTNode* table_expr;
            ASTNode* key;
            ASTNode* value;
        } table_set;

        struct {
            ASTNode* table_expr;
            ASTNode* key;
        } table_get;

        struct {
            char* name;
        } id;

        struct {
            double val;
        } number;
    } as;
};

// --- Core Compiler Functions ---
void generate_asm(ASTNode* node);

// --- Context & Memory Management (implemented in context.c) ---
int get_next_label(void);
int add_string_literal(const char* str);
void emit_string_data_section(void);

void push_function_context(const char* name);
void pop_function_context(void);
const char* get_current_function_name(void);

ASTNode *make_node_binary (NodeType, ASTNode *, ASTNode *);

void push_loop(int id);
void pop_loop(void);
int current_loop(void);

int get_global_variable_address(const char* name);
void  generate_global_setup (ASTNode *);
void  generate_functions (ASTNode *);

#endif // CODEGEN_H
