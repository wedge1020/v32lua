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
    struct SymbolNode* next;
} SymbolNode;

typedef struct ScopeNode {
    SymbolNode* symbols;      // Variables declared in this specific scope
    int local_offset_counter; // Tracks [BP - 1], [BP - 2], etc., for this function
    struct ScopeNode* parent; // Pointer to the enclosing scope
} ScopeNode;

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
extern int next_ram_address; // Address 0 is reserved for our heap_pointer
  
int  get_next_label (void);

#endif
