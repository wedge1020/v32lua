#include "v32lua.h"

ScopeNode* current_scope = NULL;
ScopeNode* global_scope = NULL;
int next_ram_address = 1; // Address 0 is reserved for our heap_pointer

void init_global_scope(void) {
    if (global_scope != NULL) return;
    global_scope = (ScopeNode*)calloc(1, sizeof(ScopeNode));
    current_scope = global_scope;
}

void push_scope(void) {
    ScopeNode* new_scope = (ScopeNode*)calloc(1, sizeof(ScopeNode));
    new_scope->parent = current_scope;
    
    // Inherit the local stack offset from the parent so variables in 
    // nested blocks don't overwrite variables in outer blocks!
    if (current_scope != NULL) {
        new_scope->local_offset_counter = current_scope->local_offset_counter;
    } else {
        new_scope->local_offset_counter = 1; // Start locals at [BP - 1]
    }
    
    current_scope = new_scope;
}

void pop_scope(void) {
    if (current_scope == global_scope || current_scope == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Scope underflow: tried to pop global scope!");
    }
    
    ScopeNode* old_scope = current_scope;
    current_scope = current_scope->parent;
    
    // Free the symbols in the scope we are leaving
    SymbolNode* sym = old_scope->symbols;
    while (sym != NULL) {
        SymbolNode* next_sym = sym->next;
        free(sym->name);
        free(sym);
        sym = next_sym;
    }
    free(old_scope);
}

// Lookup a variable starting from the innermost scope outward
SymbolNode* resolve_symbol(const char* name) {
    ScopeNode* search_scope = current_scope;
    
    while (search_scope != NULL) {
        SymbolNode* sym = search_scope->symbols;
        while (sym != NULL) {
            if (strcmp(sym->name, name) == 0) {
                return sym; // Found it!
            }
            sym = sym->next;
        }
        search_scope = search_scope->parent; // Move down the stack
    }
    return NULL; // Not found anywhere
}

// Add a local variable to the *current* scope
SymbolNode* register_local(const char* name) {
    SymbolNode* sym = (SymbolNode*)calloc(1, sizeof(SymbolNode));
    sym->name = strdup(name);
    sym->type = SYM_LOCAL;
    sym->location = current_scope->local_offset_counter++; // Allocate [BP - offset]
    
    sym->next = current_scope->symbols;
    current_scope->symbols = sym;
    return sym;
}

// Add a global variable to the *global* (bottom-most) scope
SymbolNode* register_global(const char* name) {
    // Safety check - if global scope isn't initialized, do it now
    if (global_scope == NULL) init_global_scope();

    SymbolNode* sym = (SymbolNode*)calloc(1, sizeof(SymbolNode));
    sym->name = strdup(name);
    sym->type = SYM_GLOBAL;
    sym->location = next_ram_address++; // Allocate fixed RAM address
    
    sym->next = global_scope->symbols;
    global_scope->symbols = sym;
    return sym;
}

////////////////////////////////////////////////////////////////////////////////////////
//
// compose the variable prefix (function vs variable), since everything is
// technically a variable in lua.
//
void  get_variable_access_string (const char *name, char *output_buffer)
{
    SymbolNode *sym             = resolve_symbol (name);
    
    ////////////////////////////////////////////////////////////////////////////////////
    //
    // If not found, auto-register it as a global variable
    //
    if (sym                    == NULL)
    {
        sym                     = register_global (name); 
    }

    ////////////////////////////////////////////////////////////////////////////////////
    //
    // Check if it's a global symbol
    //
    if (sym -> type            == SYM_GLOBAL)
    {
        if (sym -> is_function == 1)
        {
            sprintf (output_buffer, "[func_%s]", sym -> name);
        }
        else
        {
            sprintf (output_buffer, "[var_%s]", sym -> name);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////
    //
    // else it is a local variable, use BP offset
    //
    else
    {
        ////////////////////////////////////////////////////////////////////////////////
        //
        // It's a parameter! (e.g. location -2 formats as [BP + 2])
        //
        if (sym -> location    <  0)
        {
            sprintf (output_buffer, "[BP + %d]", -sym -> location);
        }

        ////////////////////////////////////////////////////////////////////////////////
        //
        // It's a local! (e.g. location 1 formats as [BP - 1])
        //
        else
        {
            sprintf (output_buffer, "[BP - %d]", sym -> location);
        }
    }
}

void  mark_global_as_function (const char *name)
{
    SymbolNode *sym     = resolve_symbol (name);
    if (sym            == NULL)
    {
        sym             = register_global (name);
    }
    sym -> is_function  = 1;
    sym -> type         = SYM_GLOBAL;
}

// ============================================================================
// --- Label Generator & Function Context Stack ---
// ============================================================================

typedef struct FunctionContextNode {
    const char* name;
    int label_counter;
    struct FunctionContextNode* next;
} FunctionContextNode;

static FunctionContextNode* context_stack_head = NULL;
static int global_label_counter = 0; 

int get_next_label(void) {
    if (context_stack_head == NULL) {
        return global_label_counter++;
    }
    return context_stack_head->label_counter++;
}

void push_function_context(const char* name) {
    FunctionContextNode* new_node = (FunctionContextNode*)malloc(sizeof(FunctionContextNode));
    if (new_node == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Out of memory allocating function context for '%s'", name);
    }
    
    new_node->name = name; 
    new_node->label_counter = 0; 
    
    new_node->next = context_stack_head;
    context_stack_head = new_node;
}

void pop_function_context(void) {
    if (context_stack_head == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Function context stack underflow (tried to pop global scope)");
    }
    
    FunctionContextNode* old_head = context_stack_head;
    context_stack_head = context_stack_head->next;
    free(old_head);
}

const char* get_current_function_name(void) {
    if (context_stack_head == NULL) {
        return "global";
    }
    return context_stack_head->name;
}

StringLiteralNode* strings_head = NULL;
int string_counter = 0;

int add_string_literal(const char* str) {
    StringLiteralNode* current = strings_head;
    while (current != NULL) {
        if (strcmp(current->value, str) == 0) {
            return current->id;
        }
        current = current->next;
    }

    StringLiteralNode* new_node = (StringLiteralNode*)malloc(sizeof(StringLiteralNode));
    if (new_node == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Out of memory allocating string literal");
    }
    
    new_node->id = string_counter++;
    new_node->value = strdup(str);
    new_node->next = strings_head;
    strings_head = new_node;
    return new_node->id;
}

// ============================================================================
// --- Loop Stack (for break statements) ---
// ============================================================================

typedef struct LoopContextNode {
    int loop_id;
    struct LoopContextNode* next;
} LoopContextNode;

static LoopContextNode* loop_stack_head = NULL;

void push_loop(int id) {
    LoopContextNode* new_node = (LoopContextNode*)malloc(sizeof(LoopContextNode));
    if (new_node == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Out of memory allocating loop context");
    }
    
    new_node->loop_id = id;
    new_node->next = loop_stack_head;
    loop_stack_head = new_node;
}

void pop_loop(void) {
    if (loop_stack_head == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Loop stack underflow (No loop to pop)");
    }
    
    LoopContextNode* old_head = loop_stack_head;
    loop_stack_head = loop_stack_head->next;
    free(old_head);
}

int current_loop(void) {
    if (loop_stack_head == NULL) {
        return -1; 
    }
    return loop_stack_head->loop_id;
}
//
// Add to context.c
SymbolNode* register_parameter(const char* name, int offset) {
    SymbolNode* sym = (SymbolNode*)calloc(1, sizeof(SymbolNode));
    sym->name = strdup(name);
    sym->type = SYM_LOCAL;
    sym->location = -offset; // Store as negative so we know it's a parameter!
    
    sym->next = current_scope->symbols;
    current_scope->symbols = sym;
    return sym;
}
