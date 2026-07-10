#ifndef CODEGEN_H
#define CODEGEN_H

////////////////////////////////////////////////////////////////////////////////////////
//
// --- Register Inventory ---
// Vircon32 has R0-R15, but R14 is BP and R15 is SP. 
// We will track general purpose registers R0 through R13.
//
#define NUM_GPRS 14 

void  lock_register (int);
void  unlock_register (int);
int   is_register_locked (int);
int   allocate_register (void); 

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
    NODE_NUMBER,
    NODE_UNARY,
    NODE_ASM,
    NODE_RAWASM,
    NODE_COMMENT_LINE,
    NODE_COMMENT_BLOCK
} NodeType;

typedef enum {
    OP_EQ,
    OP_NEQ,
    OP_LT,
    OP_GT,
    OP_LE,
    OP_GE,
    OP_LEN,
    OP_NOT,
    OP_UNM
} Operator;

typedef enum {
    ERR_LEXICAL,
    ERR_SYNTAX,
    ERR_SEMANTIC,
    ERR_INTERNAL
} ErrorType;

// --- AST Node Structure ---
typedef struct astnode {
    NodeType type;
    struct astnode* next; // Sibling pointer for statements in a block

    union {
        struct {
            struct astnode* condition;
            struct astnode* body;
        } while_loop;

        struct
        {
            struct astnode *condition;
            struct astnode *if_body;
            struct astnode *else_body; // Can be NULL
        } if_stmt;

        struct {
            char* name;
            struct astnode* params;
            struct astnode* body;
        } function_def;

        struct {
            struct astnode* target;
            struct astnode* args_head; // Linked list of arguments
            int is_method_call;
        } call;
        
        struct {
            char* mangled_name;
        } func_ptr;
        
        struct {
            struct astnode* expressions_head; // Linked list of return values
            int parent_func_arg_count;
        } return_stmt;

        struct {
            struct astnode *targets_head; // Linked list of variables to assign to
            struct astnode *values_head;  // Linked list of expressions to assign
            int is_local; // <--- ADD THIS
        } mult_assign;

        struct {
            struct astnode *left;
            struct astnode *right;
            Operator operator;
        } binary;

        struct {
            struct astnode *operand;
            Operator operator;
        } unary;

        struct {
            char* value;
        } string_val;

        struct {
            struct astnode* table_expr;
            struct astnode* key;
            struct astnode* value;
        } table_set;

        struct {
            struct astnode* table_expr;
            struct astnode* key;
        } table_get;

        struct {
            char* name;
        } id;

        struct {
            double val;
        } number;

        struct {
            char* code;
        } inline_asm; 
    } as;
} ASTNode;

// ============================================================================
// --- Scoped Symbol Table (Replaces flat GlobalVarNode list) ---
// ============================================================================

typedef enum { SYM_GLOBAL, SYM_LOCAL } SymbolType;

typedef struct SymbolNode {
    char* name;
    SymbolType type;
    int location;             // RAM address for globals, BP offset for locals
    int is_function;
    struct SymbolNode* next;
} SymbolNode;

typedef struct ScopeNode {
    SymbolNode* symbols;      // Variables declared in this specific scope
    int local_offset_counter; // Tracks [BP - 1], [BP - 2], etc., for this function
    struct ScopeNode* parent; // Pointer to the enclosing scope
} ScopeNode;


// --- Core Compiler Functions ---
void generate_asm(ASTNode* node, int dest_reg);
void generate_program(ASTNode* head);
void generate_global_setup(ASTNode* node);
void generate_functions(ASTNode* node);

void compiler_error(ErrorType type, int line, const char* format, ...);

// --- Context & Memory Management ---
int get_next_label(void);
int add_string_literal(const char* str);
void emit_string_data_section(void);

void push_function_context (const char* name);
void pop_function_context (void);
const char* get_current_function_name (void);

////////////////////////////////////////////////////////////////////////////////////////
//
// AST support functions (ast.c)
//
ASTNode *make_node_unary (Operator, ASTNode *);
ASTNode *make_node_binary (NodeType, ASTNode *, ASTNode *);
ASTNode *make_node_table_constructor (void);
ASTNode *make_node_table_get (ASTNode *, ASTNode *);
ASTNode *make_node_table_set (ASTNode *, ASTNode *, ASTNode *);


void push_loop(int id);
void pop_loop(void);
int current_loop(void);

void emit_variable_map(void);

void mark_global_as_function(const char* name);

void  init_global_scope (void);
void  get_variable_access_string(const char *, char *);

void  push_scope (void);
void  pop_scope (void);

void emit_runtime_library (void);

SymbolNode *register_parameter (const char *, int);
SymbolNode *register_local (const char *);

#endif // CODEGEN_H
