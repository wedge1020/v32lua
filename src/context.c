#include "v32lua.h"

// Address 0 is reserved for the HEAP_POINTER variable itself!
int next_ram_address = 1;

CompilerConfig o_config;

ScopeNode* current_scope = NULL;
ScopeNode* global_scope = NULL;

FunctionContextNode *context_stack_head = NULL;
int global_label_counter = 0; 

void init_global_scope(void) {
    if (global_scope != NULL) return;
    global_scope = (ScopeNode*)calloc(1, sizeof(ScopeNode));
    global_scope->local_offset_counter = 1;  // ← ADD THIS LINE
    current_scope = global_scope;
}

//////////////////////////////////////////////////////////////////////////////
//
// Like push_scope(), but for the OUTERMOST scope of a function body. Its
// parent is the global scope only -- never the enclosing function's local
// scope. Cross-function references must always go through the explicit
// upvalue mechanism (SYM_UPVALUE symbols registered by register_upvalue),
// never through a raw scope-chain walk into a frame that may not even be
// on the stack anymore by the time this function runs.
//
void  push_function_scope (void)
{
    ScopeNode *new_scope               = (ScopeNode *) calloc (1, sizeof (ScopeNode));
    new_scope -> parent                = global_scope;
    new_scope -> local_offset_counter  = 1;
    current_scope                      = new_scope;
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
SymbolNode *resolve_symbol (const char *name)
{
    ScopeNode *search_scope = current_scope;
    
    while (search_scope                    != NULL)
    {
        SymbolNode *sym                     = search_scope->symbols;
        while (sym                         != NULL)
        {
            if (strcmp (sym -> name, name) == 0)
            {
                return (sym); // Found it!
            }
            sym                             = sym -> next;
        }
        search_scope                        = search_scope -> parent; // Move down the stack
    }
    return (NULL); // Not found anywhere
}

// Search ONLY the immediate current block scope (do not traverse parent pointers!)
SymbolNode *resolve_local_symbol_current_scope (const char *name)
{
    if (current_scope == NULL) return NULL;
    
    SymbolNode *sym = current_scope->symbols;
    while (sym != NULL)
    {
        if (strcmp (sym->name, name) == 0)
        {
            return sym;
        }
        sym = sym->next;
    }
    return NULL;
}

// Add a local variable to the *current* scope
SymbolNode *register_local (const char* name)
{
    SymbolNode *sym                      = resolve_local_symbol_current_scope (name);
    if (sym                             != NULL)
        return sym;

    sym                                  = (SymbolNode *) calloc (1, sizeof (SymbolNode));
    sym -> name                          = strdup(name);
    sym -> type                          = SYM_LOCAL;
    sym -> location                      = current_scope -> local_offset_counter;
    current_scope -> local_offset_counter++;

    //////////////////////////////////////////////////////////////////////////
    //
    // if the enclosing function's pre-pass found that a nested closure
    // captures this name, mark it boxed. Every read/write of this local
    // will go through emit_load_variable()/emit_store_variable() from now
    // on instead of a bare MOV.
    //
    if ((context_stack_head             != NULL) &&
        (context_stack_head -> def_node != NULL))
    {
        NameList *boxed                  = context_stack_head -> def_node -> as.function_def.boxed_locals;
        if (name_list_contains(boxed, name))
        {
            sym -> is_boxed              = true;
        }
    }

    if (current_scope -> last           == NULL)
    {
        current_scope -> symbols         = sym;
    }
    else
    {
        current_scope -> last -> next    = sym;
    }
    current_scope -> last                = sym;

    return (sym);
}

SymbolNode* register_global (const char *name)
{
    SymbolNode *sym                   = resolve_symbol (name);
    if (sym                          != NULL)
    {
        return (sym); // Already registered, do not allocate a new slot!
    }

    sym                               = (SymbolNode *) calloc (1, sizeof (SymbolNode));
    sym -> name                       = strdup (name);
    sym -> type                       = SYM_GLOBAL;
    sym -> location                   = next_ram_address; // Sequentially assign RAM slots from 1 upwards
    sym -> is_function                = 0;
    next_ram_address                  = next_ram_address + 1;

    if (global_scope                 == NULL)
    {
        init_global_scope ();
    }

    if (global_scope -> last         == NULL)
    {
        global_scope -> symbols       = sym;
    }
    else
    {
        global_scope -> last -> next  = sym;
    }

    global_scope -> last              = sym;
    
    return (sym);
}

void  mark_global_as_function (ASTNode *def_node)
{
    if (def_node             == NULL)
        return;

    const char *name          = def_node -> as.function_def.name;
    ASTNode    *params        = def_node -> as.function_def.params;
    ASTNode    *ptmp          = NULL;
    SymbolNode *sym           = register_global (name);
    int         count         = 0;
    int         has_variadic  = 0;

    sym -> is_function        = 1;
    sym -> def_node           = def_node;   // lets node_identifier() find the
                                            // upvalue list when loading this 
                                            // function by its bare name
    ptmp                      = params;
    while (ptmp              != NULL)
    {
        if (ptmp -> type     == NODE_IDENTIFIER)
        {
            if (0            == strcmp (ptmp -> as.id.name, "..."))
            {
                has_variadic  = 1;
            }
            else
            {
                count         = count + 1;
            }
        }
        ptmp                  = ptmp -> next;
    }

    sym -> arity              = count;
    sym -> is_variadic        = has_variadic;
}

////////////////////////////////////////////////////////////////////////////////////////
//
// compose the variable prefix (function vs variable), since everything is
// technically a variable in lua.
//
void get_variable_access_string(const char *name, char *output_buffer) {
    SymbolNode *sym = resolve_symbol(name);

    if (sym == NULL) {
        sym = register_global(name);
    }

    if (sym->type == SYM_GLOBAL) {
        if (sym->is_function == 1) {
            sprintf(output_buffer, "[func_%s]", sym->name);  // ← Keep brackets
        } else {
            sprintf(output_buffer, "[var_%s]", sym->name);
        }
    } else {
        if (sym->location < 0) {
            int stack_offset = (-(sym->location));
            sprintf(output_buffer, "[BP + %d]", stack_offset);
        } else {
            sprintf(output_buffer, "[BP - %d]", sym->location);
        }
    }
}

// ============================================================================
// --- Label Generator
// ============================================================================
int get_next_label (void)
{
    if (context_stack_head == NULL)
    {
        return global_label_counter++;
    }
    return context_stack_head->label_counter++;
}

void  push_function_context (const char *name, ASTNode *def_node)
{
    FunctionContextNode *new_node  = (FunctionContextNode *) malloc (sizeof (FunctionContextNode));
    if (new_node                  == NULL)
    {
        compiler_error (ERR_INTERNAL, -1,
                        "Out of memory allocating function context for '%s'", name);
    }
    
    new_node -> name               = name; 
    new_node -> label_counter      = 0; 
    new_node -> def_node           = def_node;
    
    new_node -> next               = context_stack_head;
    context_stack_head             = new_node;
}

void  pop_function_context (void)
{
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

int add_string_literal (const char *str)
{
    // Check if string already exists
    StringLiteralNode *current = strings_head;
    while (current != NULL) {
        if (strcmp(current->value, str) == 0) {
            return current->id;
        }
        current = current->next;
    }

    // String not found, add it
    StringLiteralNode *new_node = (StringLiteralNode *) malloc(sizeof(StringLiteralNode));
    if (new_node == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Out of memory allocating string literal");
    }

    new_node->id    = string_counter++;
    new_node->value = strdup(str);
    new_node->next  = strings_head;
    strings_head    = new_node;
    return (new_node->id);
}

// ============================================================================
// --- Loop Stack (for break statements) ---
// ============================================================================

typedef struct LoopContextNode {
    int loop_id;
    LoopType loop_type;  // NEW: Track loop type
    struct LoopContextNode* next;
} LoopContextNode;

static LoopContextNode* loop_stack_head = NULL;

// Modified push_loop to accept loop type
void push_loop(int id, LoopType type) {
    LoopContextNode* new_node = (LoopContextNode*)malloc(sizeof(LoopContextNode));
    if (new_node == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Out of memory allocating loop context");
    }

    new_node->loop_id = id;
    new_node->loop_type = type;  // Store the loop type
    new_node->next = loop_stack_head;
    loop_stack_head = new_node;
}

// New function to get current loop type
LoopType current_loop_type(void) {
    if (loop_stack_head == NULL) {
        return -1;
    }
    return loop_stack_head->loop_type;
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

SymbolNode *register_parameter (const char *name, int offset)
{
    SymbolNode *sym = (SymbolNode *) calloc (1, sizeof (SymbolNode));
    if (!sym) {
        compiler_error(ERR_INTERNAL, -1, "Out of memory allocating parameter");
    }
    
    sym->name     = strdup (name);
    sym->type     = SYM_LOCAL;
    sym->location = -offset; // Store as negative so we know it's a parameter!
    
    // Cleanly append to the scope list and maintain 'last'
    if (current_scope->last == NULL)
    {
        current_scope->symbols = sym;
    }
    else
    {
        current_scope->last->next = sym;
    }
    current_scope->last = sym;

    return sym;
}

void  register_all_globals_prepass (ASTNode *node)
{
    while (node != NULL)
    {
        switch (node -> type)
        {
            case NODE_FUNCTION_DEF:
                // ✅ Always register as global (local keyword is silently ignored)
                mark_global_as_function (node);
                register_all_globals_prepass (node->as.function_def.body);
                break;

            /* once we get local functions implemented...
            case NODE_FUNCTION_DEF:
                // Check if next node is a local multiple assignment
                bool is_local = false;
                if (node->next != NULL && node->next->type == NODE_MULTIPLE_ASSIGNMENT) {
                    is_local = node->next->as.mult_assign.is_local;
                }

                if (!is_local) {
                    mark_global_as_function (node);
                }
                register_all_globals_prepass(node->as.function_def.body);
                break;
                */

            case NODE_MULTIPLE_ASSIGNMENT:
                if (!node->as.mult_assign.is_local) {
                    ASTNode *tgt = node->as.mult_assign.targets_head;
                    while (tgt != NULL) {
                        if (tgt->type == NODE_IDENTIFIER) {
                            register_global(tgt->as.id.name);
                        }
                        tgt = tgt->next;
                    }
                }
                break;

            // ✅ NEW: Recurse into control structures
            case NODE_IF:
                register_all_globals_prepass(node->as.if_stmt.if_body);
                register_all_globals_prepass(node->as.if_stmt.else_body);
                break;

            case NODE_WHILE:
                register_all_globals_prepass(node->as.while_loop.body);
                break;

            case NODE_FOR_NUMERIC:
            case NODE_FOR_GENERIC:
                register_all_globals_prepass(node->as.for_numeric.body);
                break;

            default:
                break;
        }
        node = node->next;
    }
}

// ============================================================================
// NameList helpers -- a tiny dedup-on-insert set used by the closure
// analysis pass and by the resolved upvalue/boxed_locals lists it produces.
// ============================================================================

bool name_list_contains (NameList *list, const char *name)
{
    for (NameList *n = list; n != NULL; n = n->next) {
        if (strcmp(n->name, name) == 0) return true;
    }
    return false;
}

// Adds `name` to *list if not already present. Returns true if it was
// actually added (useful for counting).
bool name_list_add (NameList **list, const char *name)
{
    if (name_list_contains(*list, name)) return false;

    NameList *n = (NameList *) malloc(sizeof(NameList));
    if (n == NULL) {
        compiler_error(ERR_INTERNAL, -1, "Out of memory building upvalue list");
    }
    n->name = strdup(name);
    n->next = *list;
    *list   = n;
    return true;
}

int name_list_length (NameList *list)
{
    int count = 0;
    for (NameList *n = list; n != NULL; n = n->next) count++;
    return count;
}

// Register a received upvalue as a hidden trailing parameter. Identical in
// shape to register_parameter() (same negative-offset [BP+N] addressing),
// but tagged SYM_UPVALUE and always boxed: the slot holds a box pointer,
// never a raw value, because the box is what makes it shared with the
// enclosing function's copy of the same variable.
SymbolNode *register_upvalue (const char *name, int offset)
{
    SymbolNode *sym = (SymbolNode *) calloc(1, sizeof(SymbolNode));
    if (!sym) {
        compiler_error(ERR_INTERNAL, -1, "Out of memory allocating upvalue '%s'", name);
    }

    sym->name     = strdup(name);
    sym->type     = SYM_UPVALUE;
    sym->location = -offset;   // same convention as register_parameter
    sym->is_boxed = true;

    if (current_scope->last == NULL) {
        current_scope->symbols = sym;
    } else {
        current_scope->last->next = sym;
    }
    current_scope->last = sym;

    return sym;
}
