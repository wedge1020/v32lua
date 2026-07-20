#ifndef __CONTEXT_H
#define __CONTEXT_H

// ============================================================================
// --- Scoped Symbol Table (Replaces flat GlobalVarNode list) ---
// ============================================================================

typedef enum { SYM_GLOBAL, SYM_LOCAL } SymbolType;

typedef struct SymbolNode {
    char* name;
    SymbolType type;
    int location;             // RAM address for globals, BP offset for locals
    int is_function;
	int arity;
    struct SymbolNode* next;
} SymbolNode;

typedef struct ScopeNode {
    SymbolNode* symbols;      // Variables declared in this specific scope
    SymbolNode* last;         // last symbol in list
    int local_offset_counter; // Tracks [BP - 1], [BP - 2], etc., for this function
    struct ScopeNode* parent; // Pointer to the enclosing scope
} ScopeNode;

// ============================================================================
// --- Function Context Stack ---
// ============================================================================
typedef struct FunctionContextNode {
    const char* name;
    int label_counter;
    struct FunctionContextNode* next;
} FunctionContextNode;

// ============================================================================
// --- String Literal Tracking ---
// ============================================================================

typedef struct StringLiteralNode {
    int id;
    char* value;
    struct StringLiteralNode* next;
} StringLiteralNode;

extern StringLiteralNode *strings_head;
extern int string_counter;

extern ScopeNode *current_scope;
extern ScopeNode *global_scope;
extern int        next_ram_address;
extern FunctionContextNode *context_stack_head;
extern int global_label_counter; 
  
int         get_next_label               (void);
void        init_global_scope            (void);
SymbolNode *resolve_symbol               (const char *);
int         add_string_literal           (const char *);
void        register_all_globals_prepass (ASTNode *);
SymbolNode *register_global              (const char *);
SymbolNode *register_local               (const char *);
SymbolNode *register_parameter           (const char *, int);
void        mark_global_as_function      (const char *, ASTNode *);
const char *get_current_function_name    (void);
void        get_variable_access_string   (const char *, char *);
void        push_function_context        (const char *);
void        pop_function_context         (void);
void        pop_scope                    (void);
void        push_scope                   (void);
void        push_loop                    (int);
void        pop_loop                     (void);
int         current_loop                 (void);

#endif
