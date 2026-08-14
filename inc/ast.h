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

        struct {
            struct astnode* var_list; // Linked list of variable names (k, v, etc.)
            struct astnode* iter_expr; // The iterator expression (e.g., pairs(t))
            struct astnode* body;
        } for_generic;

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
			int is_variadic;  // NEW
        } function_def;

        struct {
            struct astnode* target;
            struct astnode* args_head; // Linked list of arguments
            int is_method_call;
        } call;
        
        // In the func_ptr union:
        struct {
            char* mangled_name;
            struct astnode* func_def;  // Function definition for anonymous functions
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
            bool val;
        } boolean;

        struct {
            struct astnode *operand;
            Operator operator;
        } unary;

        struct {
            char* value;
        } string_val;

        struct {
            struct astnode* initializers_head; // Linked list of table_set nodes
        } table_constructor;

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

// Global state for TIC80 asset processing
extern char *current_tic80_section;
extern uint32_t tic80_palette[16];
extern bool tic80_use_custom_palette;
extern bool tic80_has_any_assets;
extern TIC80AssetData *current_tic80_assets;

// Function declarations
void process_tic80_section(const char *section, TIC80AssetData *assets);
TIC80AssetData *parse_tic80_asset_line(const char *line);
void generate_vtex_from_tic80(const char *output_path);
bool tic80_has_assets(void);
bool tic80_has_custom_palette(void);
uint32_t tic80_get_palette_color(int index);

extern char cart_version[64];
extern char cart_title[128];
extern CARTresource *textures_head;
extern CARTresource *sounds_head;
extern int next_texture_id;
extern int next_sound_id;
extern int yylineno;

////////////////////////////////////////////////////////////////////////////////////////
//
// AST function prototypes
//
ASTNode *make_node                   (NodeType);
ASTNode *make_node_ident             (const char *);
ASTNode *make_node_string            (const char *);
ASTNode *make_node_cart_hint         (const char *);
ASTNode *make_node_unary             (Operator,     ASTNode    *);
ASTNode *make_node_binary            (NodeType,     ASTNode    *, ASTNode *);
ASTNode *make_node_function_def      (const char *, ASTNode    *, ASTNode *);
ASTNode *make_node_method_def        (ASTNode    *, const char *, int,       ASTNode *, ASTNode *);
ASTNode *make_node_table_constructor (ASTNode    *);
ASTNode *make_node_table_get         (ASTNode    *, ASTNode    *);
ASTNode *make_node_table_set         (ASTNode    *, ASTNode    *, ASTNode *);
ASTNode *make_node_boolean           (bool);
ASTNode *make_node_nil               (void);
bool     try_get_immediate_operand   (ASTNode    *, char       *, size_t);

#endif
