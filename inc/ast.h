#ifndef _AST_H
#define _AST_H

////////////////////////////////////////////////////////////////////////////////////////
//
// linked list for various CART resources
//
typedef struct cart_resource CARTresource;
struct cart_resource
{
    int           id;
    char         *var_name;
    char         *filename;
    CARTresource *next;
};

////////////////////////////////////////////////////////////////////////////////////////
//
// ASTNode structure
//
typedef struct astnode {
    NodeType type;
	int  line_number;
    struct astnode* next; // Sibling pointer for statements in a block

    union {
        struct {
            struct astnode* condition;
            struct astnode* body;
        } while_loop;

		struct {
			char* index_name;          // The loop variable name (e.g., "i")
			struct astnode* start_expr;
			struct astnode* stop_expr;
			struct astnode* step_expr; // Can be NULL (defaults to 1.0)
			struct astnode* body;
		} for_numeric;

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
            int is_local;
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

        struct {
            char* action;    // e.g., "version", "texture", "title"
            char* name;      // e.g., "background" (NULL for non-indexed hints)
            char* value;     // e.g., "filename.png" or "1.0"
            int resource_id; // Assigned sequential ID (0, 1, 2...)
        } cart_hint;
    } as;
} ASTNode;

extern char cart_version[64];
extern char cart_title[128];
extern CARTresource *textures_head;
extern CARTresource *sounds_head;
extern int next_texture_id;
extern int yylineno;

////////////////////////////////////////////////////////////////////////////////////////
//
// AST function prototypes
//
ASTNode *make_node (NodeType);
ASTNode *make_node_ident (const char *);
ASTNode *make_node_string (const char *);
ASTNode *make_node_cart_hint (const char *);
ASTNode *make_node_unary (Operator, ASTNode *);
ASTNode *make_node_binary (NodeType  type, ASTNode *left, ASTNode *right);
ASTNode *make_node_table_constructor (void);
ASTNode *make_node_table_get (ASTNode *table_expr, ASTNode *key_expr);
ASTNode *make_node_table_set (ASTNode *table_expr, ASTNode *key_expr, ASTNode *value_expr);

#endif
