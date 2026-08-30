#include "v32lua.h"

// Address 0 is reserved for the HEAP_POINTER variable itself!
int next_ram_address = 3;

CompilerConfig o_config;

ScopeNode* current_scope = NULL;
ScopeNode* global_scope = NULL;

FunctionContextNode *context_stack_head = NULL;
int global_label_counter = 0; 
int vircon32_btn_prev_state_base = -1;

void init_global_scope(void) {
    if (global_scope != NULL) return;
    global_scope = (ScopeNode*)calloc(1, sizeof(ScopeNode));
    global_scope->local_offset_counter = 1;  // ← ADD THIS LINE
    current_scope = global_scope;
}

//////////////////////////////////////////////////////////////////////////////
//
// Like push_scope(), but for the OUTERMOST scope of a function body.
//
// `parent` is set to whatever scope was actually active when this function
// was reached -- NOT hardcoded to global_scope -- because pop_scope() relies
// on `parent` to correctly restore current_scope when this scope is popped.
// A nested function popping back into a hardcoded global_scope instead of
// its real enclosing scope corrupts the caller's notion of "current scope"
// for the rest of that caller's body, and eventually trips pop_scope()'s
// underflow guard when the caller tries to pop a scope that's already been
// silently replaced.
//
// Cross-function variable lookups are blocked a different way: this scope
// is tagged is_function_boundary, and resolve_symbol() stops walking past
// any scope with that flag set (falling back only to the real global scope,
// never into an enclosing function's locals). That's what makes closures
// safe -- not the parent pointer, which now just does its original job of
// letting pop_scope() unwind correctly.
//
void  push_function_scope (void)
{
    ScopeNode *new_scope               = (ScopeNode *) calloc (1, sizeof (ScopeNode));
    new_scope -> parent                = current_scope;   // real caller scope, for pop_scope()
    new_scope -> local_offset_counter  = 1;
    new_scope -> is_function_boundary  = true;
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

// Lookup a variable starting from the innermost scope outward.
//
// Ordinary block scopes (if/while/for, pushed via push_scope()) are walked
// normally via `parent`, since they're still part of the SAME function's
// frame. When the walk reaches a function-boundary scope (pushed via
// push_function_scope()), that scope's own symbols -- the function's own
// params/locals/upvalues -- are still checked normally, but the walk does
// NOT continue into that scope's `parent` (which is just whatever caller
// happened to invoke this function, an unrelated frame at runtime). Instead
// it jumps straight to the real global scope, so plain global names are
// still visible from any nesting depth, without ever exposing an enclosing
// function's locals to a nested one.
SymbolNode *resolve_symbol (const char *name)
{
    ScopeNode *search_scope = current_scope;

    while (search_scope != NULL)
    {
        SymbolNode *sym = search_scope->symbols;
        while (sym != NULL)
        {
            if (strcmp (sym -> name, name) == 0)
            {
                return (sym); // Found it!
            }
            sym = sym -> next;
        }

        if (search_scope->is_function_boundary && search_scope != global_scope)
        {
            // Don't walk into the caller's scope -- skip straight to
            // globals, which remain visible from any depth.
            search_scope = global_scope;
            continue;
        }

        search_scope = search_scope -> parent;
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

    //////////////////////////////////////////////////////////////////////////
    //
    // SAFETY NET: at the chunk's top level, current_scope IS global_scope --
    // there is no function frame to own a [BP-N] slot, and anything stored
    // there dies when __global_scope_initialization RETs. Handing out a
    // stack offset here also appends a SYM_LOCAL to global_scope->symbols,
    // where emit_variable_map() would print its offset as if it were an
    // absolute RAM address (offsets 1/2 alias FTOA_SCRATCH_PTR_A/B, 0
    // aliases HEAP_POINTER).
    //
    // register_all_globals_prepass() should already have claimed a real RAM
    // word for every top-level 'local', so in practice this branch only
    // catches names introduced by a codegen path the prepass doesn't walk.
    // Promote rather than fabricate a bogus slot. (Heap placement is safe
    // either way now: generate_global_setup() emits the symbolic HEAP_START
    // rather than baking in next_ram_address before this can run.)
    //
    if (current_scope                   == global_scope)
    {
        return (register_global (name));
    }

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
    sym -> return_count       = count_max_return_values (def_node -> as.function_def.body);
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
// get_extra_return_slot_access(): Compute the assembly access string for the
// Nth "extra" return-value slot (N = 0 for the 4th return value overall,
// N = 1 for the 5th, etc). Values 1-3 of any multi-return function travel
// in the fixed hardware registers R0/R2/R3, exactly as before. Everything
// from the 4th value onward travels through a small bank of dedicated
// global words instead -- one per slot, auto-registered via the SAME
// global-variable machinery Lua globals already use (register_global() /
// get_variable_access_string()), so no changes to the assembler or output
// format are required.
//
// Why plain globals instead of stack slots: the call site would otherwise
// need to know, for every single call, how many argument words the callee
// itself will read (self + fixed params + vararg marker) so it could push
// the extra-return placeholders at the exact matching stack offset --
// fragile, and impossible for calls made through a function VALUE
// (obj.cb(), a table of callbacks, etc.) where the target isn't known
// until runtime. A small fixed bank of globals sidesteps all of that: the
// callee writes directly into slot (return_index - 3), the caller reads
// the same slot right back out, and -- because both sides always read/
// write these slots as the very next thing after the CALL instruction,
// before any other Lua call can run -- there's no window for another call
// to clobber them in between. This even makes `return f()` tail-forwarding
// of a >3-value call work for free: the inner call's node_return() already
// left the right values sitting in these slots, and the outer function
// just leaves them untouched.
//
// Naming: slots are auto-registered as globals named "__extra_ret_N". The
// leading double underscore follows the same reserved-name convention
// already used for other compiler-internal state (e.g. "__for_iter_%d").
// ============================================================================
void get_extra_return_slot_access(int extra_index, char *output_buffer)
{
    if (extra_index < 0 || extra_index >= MAX_EXTRA_RETURN_SLOTS) {
        compiler_error(ERR_INTERNAL, -1,
            "Multi-return value index %d exceeds the maximum of %d extra "
            "return slots (%d total return values supported)",
            extra_index, MAX_EXTRA_RETURN_SLOTS, 3 + MAX_EXTRA_RETURN_SLOTS);
        return;
    }

    char slot_name[32];
    snprintf(slot_name, sizeof(slot_name), "__extra_ret_%d", extra_index);
    get_variable_access_string(slot_name, output_buffer);
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

    new_node -> name                 = name;
    new_node -> label_counter        = 0;
    new_node -> def_node             = def_node;
    new_node -> vararg_count_offset  = -1;
    new_node -> vararg_first_offset  = -1;
    new_node -> fixed_param_count    = 0;

    new_node -> next                 = context_stack_head;
    context_stack_head               = new_node;
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

    // NEW: same check register_local() already does. A parameter captured
    // by a nested closure needs to end up boxed too -- see node_function_def
    // below for the entry-time step that actually allocates the box.
    if (context_stack_head != NULL && context_stack_head->def_node != NULL) {
        NameList *boxed = context_stack_head->def_node->as.function_def.boxed_locals;
        if (name_list_contains(boxed, name)) {
            sym->is_boxed = true;
        }
    }

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

// ============================================================================
// register_all_globals_prepass() / prepass_walk()
//
// `is_chunk_top_level` is 1 ONLY while walking the outermost statement list
// of the chunk itself -- never inside a function body, and never inside a
// nested block (if/do/while/repeat/for), all of which push a real child
// scope at codegen time and therefore own genuine [BP-N] stack slots.
//
// WHY TOP-LEVEL 'local' IS REGISTERED AS A GLOBAL HERE:
//
// At the top level of the chunk, current_scope IS global_scope. register_local()
// has no way to know that, so it happily hands the name a *stack* offset from
// global_scope->local_offset_counter (1, 2, 3, ...) and appends a SYM_LOCAL
// node to global_scope->symbols -- the very list emit_variable_map() turns
// into the cart's RAM map. Offsets 1 and 2 alias FTOA_SCRATCH_PTR_A/B and
// offset 0 aliases HEAP_POINTER, so those names came out of the variable map
// pointing straight at reserved low memory.
//
// Worse, whether that happened at all was pure luck of ordering: functions are
// generated BEFORE generate_global_setup(), so any top-level local that some
// function body happened to mention got silently promoted to a real global by
// get_variable_access_string() -> register_global() first, and register_local()
// then just found that existing symbol and reused it. Two 'local' declarations
// on adjacent lines could therefore land in two completely different storage
// classes depending only on whether a function elsewhere in the file named
// them. (Concretely: ORB_MINX..ORB_MAXY were referenced inside define_region()
// and got clean sequential RAM words; ORB_W/ORB_H were never referenced by any
// function and got "RAM addresses" 0x1 and 0x2 -- the FTOA scratch pointers.)
//
// A top-level local also cannot live on the stack even in principle: its slot
// belongs to __global_scope_initialization's frame, which RETs before init()
// or game_loop() ever run. Anything that outlives that RET has to be in RAM.
//
// So: top-level 'local' is now uniformly a global, which is exactly the
// behavior the referenced ones already had. Doing it HERE, in the prepass,
// rather than lazily at codegen time matters -- next_ram_address must be
// final before generate_global_setup() computes the heap start from it.
// ============================================================================
static void  prepass_walk (ASTNode *node, int is_chunk_top_level)
{
    while (node != NULL)
    {
        switch (node -> type)
        {
            case NODE_FUNCTION_DEF:
                // ✅ Always register as global (local keyword is silently ignored)
                mark_global_as_function (node);
                prepass_walk (node->as.function_def.body, 0);
                break;

            case NODE_MULTIPLE_ASSIGNMENT:
                // Plain (non-local) assignment anywhere => global, as before.
                // A 'local' declaration => global ONLY at the chunk's own top
                // level; inside a function or a nested block it stays a real
                // stack local. See the header comment above.
                if (!node->as.mult_assign.is_local || is_chunk_top_level) {
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
                prepass_walk(node->as.if_stmt.if_body,   0);
                prepass_walk(node->as.if_stmt.else_body, 0);
                break;

            case NODE_DO_BLOCK:
                prepass_walk(node->as.do_block.body, 0);
                break;

            case NODE_WHILE:
                prepass_walk(node->as.while_loop.body, 0);
                break;

            case NODE_REPEAT:
                prepass_walk(node->as.repeat_loop.body, 0);
                break;

            case NODE_FOR_NUMERIC:
            case NODE_FOR_GENERIC:
                prepass_walk(node->as.for_numeric.body, 0);
                break;

            default:
                break;
        }
        node = node->next;
    }
}

void  register_all_globals_prepass (ASTNode *node)
{
    prepass_walk (node, 1);
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

// ============================================================================
// count_max_return_values: scan a function's own body (NOT descending into
// nested function definitions -- those get their own count when THEY are
// processed) for 'return' statements, and return the largest number of
// expressions any one of them returns. Different branches of a function
// can legally return different counts in Lua; the call site only needs to
// know the maximum so it knows how many stack/register slots to read.
// ============================================================================
int count_max_return_values (ASTNode *node)
{
    int max_count = 1; // No explicit return, or a bare 'return', still
                        // behaves like one value (nil) at a single-target
                        // site -- matches the existing default elsewhere.
    while (node != NULL) {
        switch (node->type) {
            case NODE_RETURN: {
                int count = 0;
                for (ASTNode *e = node->as.return_stmt.expressions_head; e != NULL; e = e->next) {
                    count++;
                }

                // -----------------------------------------------------
                // FIX (passthrough undercount): a return statement with
                // exactly ONE expression, where that expression is
                // itself a call to a function already known to return
                // more than one value, actually contributes THAT many
                // values to this function's own max return count -- not
                // just "1" for being a single comma-separated expression.
                // Without this, a passthrough function like
                //   function passthrough() return inner_pair() end
                // gets statically registered as return_count=1, so ITS
                // OWN callers (via node_multiple_assignment()) never
                // extract past R0 even after node_return() itself is
                // fixed to correctly forward R0/R2/R3.
                //
                // ORDER LIMITATION: this only works if the callee's own
                // return_count has already been computed by the time
                // THIS function is processed by the register_all_
                // globals_prepass() walk -- i.e. the callee must be
                // defined/registered earlier. A forward reference to a
                // not-yet-processed multi-return callee will still
                // undercount here.
                // -----------------------------------------------------
                if (count == 1 &&
                    node->as.return_stmt.expressions_head->type == NODE_FUNCTION_CALL) {
                    ASTNode    *call_target = node->as.return_stmt.expressions_head->as.call.target;
                    SymbolNode *callee_sym  = NULL;

                    if (call_target->type == NODE_IDENTIFIER) {
                        callee_sym = resolve_symbol(call_target->as.id.name);
                    } else {
                        char path_buf[256] = {0};
                        if (resolve_static_path(call_target, path_buf)) {
                            callee_sym = resolve_symbol(path_buf);
                            if (callee_sym == NULL) {
                                for (int i = 0; path_buf[i] != '\0'; i++) {
                                    if (path_buf[i] == '.' || path_buf[i] == ':') path_buf[i] = '_';
                                }
                                callee_sym = resolve_symbol(path_buf);
                            }
                        }
                    }

                    if (callee_sym != NULL && callee_sym->is_function &&
                        callee_sym->return_count > count) {
                        count = callee_sym->return_count;
                    }
                }

                if (count > max_count) max_count = count;
                break;
            }
            case NODE_IF: {
                int a = count_max_return_values(node->as.if_stmt.if_body);
                int b = count_max_return_values(node->as.if_stmt.else_body);
                if (a > max_count) max_count = a;
                if (b > max_count) max_count = b;
                break;
            }
            case NODE_WHILE: {
                int c = count_max_return_values(node->as.while_loop.body);
                if (c > max_count) max_count = c;
                break;
            }
            case NODE_REPEAT: {
                int c = count_max_return_values(node->as.repeat_loop.body);
                if (c > max_count) max_count = c;
                break;
            }
            case NODE_FOR_NUMERIC: {
                int c = count_max_return_values(node->as.for_numeric.body);
                if (c > max_count) max_count = c;
                break;
            }
            case NODE_FOR_GENERIC: {
                int c = count_max_return_values(node->as.for_generic.body);
                if (c > max_count) max_count = c;
                break;
            }
            case NODE_DO_BLOCK: {
                int c = count_max_return_values(node->as.do_block.body);
                if (c > max_count) max_count = c;
                break;
            }
            case NODE_FUNCTION_DEF:
                // Boundary: a nested function's own returns are its own.
                break;
            default:
                break;
        }
        node = node->next;
    }
    return max_count;
}
