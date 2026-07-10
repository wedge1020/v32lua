#include "codegen.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

// --- Scoped Symbol Table ---
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

// State pointers
static ScopeNode* current_scope = NULL;
static ScopeNode* global_scope = NULL;
static int next_ram_address = 1;

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
        new_scope->local_offset_counter = 1; // Start at [BP - 1]
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
    SymbolNode* sym = (SymbolNode*)calloc(1, sizeof(SymbolNode));
    sym->name = strdup(name);
    sym->type = SYM_GLOBAL;
    sym->location = next_ram_address++; // Allocate fixed RAM address
    
    sym->next = global_scope->symbols;
    global_scope->symbols = sym;
    return sym;
}

// This replaces `get_global_variable_address` in context.c
void get_variable_access_string(const char* name, char* output_buffer) {
    SymbolNode* sym = resolve_symbol(name);
    
    if (sym == NULL) {
        // In Lua, undeclared variables implicitly become globals
        sym = register_global(name); 
    }
    
    if (sym->type == SYM_LOCAL) {
        // Format as a stack offset: [BP - 1]
        sprintf(output_buffer, "[BP - %d]", sym->location);
    } else {
        // Format as a static RAM label: [var_x]
        sprintf(output_buffer, "[%s%s]", sym->is_function ? "func_" : "var_", sym->name);
    }
}


// --- Direct RAM Allocator ---
/*typedef struct GlobalVarNode {
    char* name;
    int ram_address;
    int is_function;
    struct GlobalVarNode* next;
} GlobalVarNode;

static GlobalVarNode* globals_head = NULL;
static int next_ram_address = 1; // Address 0 is reserved for our heap_pointer
*/
/*
void mark_global_as_function(const char* name) {
    // Ensure the variable is allocated an address first
    get_global_variable_address(name);
    
    GlobalVarNode* current = globals_head;
    while (current != NULL) {
        if (strcmp(current->name, name) == 0) {
            current->is_function = 1;
            return;
        }
        current = current->next;
    }
}

const char* get_global_prefix(const char* name) {
    GlobalVarNode* current = globals_head;
    while (current != NULL) {
        if (strcmp(current->name, name) == 0) {
            return current->is_function ? "func_" : "var_";
        }
        current = current->next;
    }
    return "var_"; // Default fallback for safety
}
*/

// --- Register Inventory Implementation ---
// 0 means free, 1 means currently holding data
static int register_inventory[NUM_GPRS] = {0}; 

void lock_register(int reg) {
    if (reg >= 0 && reg < NUM_GPRS) {
        register_inventory[reg] = 1;
    }
}

void unlock_register(int reg) {
    if (reg >= 0 && reg < NUM_GPRS) {
        register_inventory[reg] = 0;
    }
}

int is_register_locked(int reg) {
    if (reg >= 0 && reg < NUM_GPRS) {
        return register_inventory[reg];
    }
    return 0;
}

int allocate_register(void) {
    for (int i = 0; i < NUM_GPRS; i++) {
        if (!register_inventory[i]) {
            register_inventory[i] = 1;
            return i;
        }
    }
	compiler_error(ERR_INTERNAL, -1, "Register inventory exhausted!");
	return -1;
}

// --- Label Generator & Function Context Stack ---

// Define the node structure for our linked list stack
typedef struct FunctionContextNode {
    const char* name;
    int label_counter;
    struct FunctionContextNode* next;
} FunctionContextNode;

// Head pointer for the stack
static FunctionContextNode* context_stack_head = NULL;

// Fallback counter for statements outside functions
static int global_label_counter = 0; 

int get_next_label(void) {
    if (context_stack_head == NULL) {
        // We are in the global scope
        return global_label_counter++;
    }
    // Return and increment the counter for the current function scope
    return context_stack_head->label_counter++;
}

void push_function_context(const char* name) {
    FunctionContextNode* new_node = (FunctionContextNode*)malloc(sizeof(FunctionContextNode));
    if (new_node == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Out of memory allocating function context for '%s'", name);
    }
    
    // Initialize the new context
    new_node->name = name; 
    new_node->label_counter = 0; // Reset counter for this new function
    
    // Push it onto the top of the stack
    new_node->next = context_stack_head;
    context_stack_head = new_node;
}

void pop_function_context(void) {
    if (context_stack_head == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Function context stack underflow (tried to pop global scope)");
    }
    
    // Pop and free the top node to prevent memory leaks
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

// --- String Literal Tracking ---
typedef struct StringLiteralNode {
    int id;
    char* value;
    struct StringLiteralNode* next;
} StringLiteralNode;

static StringLiteralNode* strings_head = NULL;
static int string_counter = 0;

int add_string_literal(const char* str) {
    // Check if duplicate string already exists
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

void emit_string_data_section(void) {
    if (strings_head == NULL) return;
    
    printf("\n; --- String Literal Allocations ---\n");
    StringLiteralNode* current = strings_head;
    while (current != NULL) {
        printf("__string_%d:\n", current->id);
        printf("  integer ");
        for (int i = 0; current->value[i] != '\0'; i++) {
            printf("%d, ", (int)current->value[i]);
        }
        printf("0\n"); // Null terminator word
        current = current->next;
    }
}

// --- Loop Stack (for break statements) ---

// Define the node structure for our linked list stack
typedef struct LoopContextNode {
    int loop_id;
    struct LoopContextNode* next;
} LoopContextNode;

// Head pointer for the loop stack
static LoopContextNode* loop_stack_head = NULL;

void push_loop(int id) {
    LoopContextNode* new_node = (LoopContextNode*)malloc(sizeof(LoopContextNode));
    if (new_node == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Out of memory allocating loop context");
    }
    
    new_node->loop_id = id;
    
    // Push it onto the top of the stack
    new_node->next = loop_stack_head;
    loop_stack_head = new_node;
}

void pop_loop(void) {
    if (loop_stack_head == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Loop stack underflow (No loop to pop)");
    }
    
    // Pop and free the top node to prevent memory leaks
    LoopContextNode* old_head = loop_stack_head;
    loop_stack_head = loop_stack_head->next;
    free(old_head);
}

int current_loop(void) {
    if (loop_stack_head == NULL) {
        return -1; // Return -1 if we are not currently inside any loop
    }
    return loop_stack_head->loop_id;
}

int get_global_variable_address(const char* name) {
    GlobalVarNode* current = globals_head;
    while (current != NULL) {
        if (strcmp(current->name, name) == 0) {
            return current->ram_address;
        }
        current = current->next;
    }

    // Allocate a raw RAM location to avoid Cartridge ROM write conflicts
    GlobalVarNode* new_node = (GlobalVarNode*)malloc(sizeof(GlobalVarNode));
    if (new_node == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Out of memory allocating global variable node");
    }
    
    new_node->name = strdup(name);
    new_node->ram_address = next_ram_address++;
    new_node->next = globals_head;
    globals_head = new_node;
    
    return new_node->ram_address;
}

void emit_variable_map(void) {
    GlobalVarNode *current = globals_head;
    while (current != NULL) {
        // Use get_global_prefix instead of a hardcoded "var_"
        fprintf(stdout, "%%define %s%s %d\n", 
                get_global_prefix(current->name), 
                current->name, 
                current->ram_address);
        current = current->next;
    }
}
