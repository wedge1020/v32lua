#ifndef __CONTEXT_H
#define __CONTEXT_H

// ============================================================================
// --- Scoped Symbol Table (Replaces flat GlobalVarNode list) ---
// ============================================================================

typedef enum { SYM_GLOBAL, SYM_LOCAL, SYM_UPVALUE } SymbolType;

typedef struct SymbolNode
{
    char       *name;
    SymbolType  type;
    int         location;
    int         is_function;
    int         arity;
    int         is_c_native;
    int         is_variadic;
    bool        is_boxed;     // slot holds a box pointer, not the value
    ASTNode    *def_node;     // for is_function symbols
    struct SymbolNode* next;
} SymbolNode;

// A simple, dedup-on-insert linked set of names. Used both as the scratch
// "currently bound" set during free-variable analysis and as the resolved
// upvalues/boxed_locals list attached to a NODE_FUNCTION_DEF.
//
typedef struct namelist
{
    char            *name;
    struct namelist *next;
} NameList;

// ============================================================================
// --- Function Context Stack ---
// ============================================================================
typedef struct FunctionContextNode
{
    const char                 *name;
    int                         label_counter;
    ASTNode                    *def_node;      // function_def this context belongs
    struct FunctionContextNode *next;
} FunctionContextNode;

typedef struct ScopeNode
{
    SymbolNode       *symbols;              // Variables declared in scope
    SymbolNode       *last;                 // last symbol in list
    int               local_offset_counter; // Tracks [BP - 1], [BP - 2]
    struct ScopeNode *parent;               // Pointer to the enclosing scope
    bool              is_function_boundary; // NEW: true only for the scope a
                                            // function's OWN body starts in
                                            // (see push_function_scope()).
                                            // resolve_symbol() checks this
                                            // scope's own symbols, then
                                            // refuses to keep walking into
                                            // whatever scope happened to be
                                            // active when this function was
                                            // defined -- that's a different,
                                            // possibly-long-gone frame at
                                            // runtime. pop_scope() ignores
                                            // this flag entirely; it always
                                            // restores via `parent`, which
                                            // still points to the REAL
                                            // caller scope.
} ScopeNode;

// ============================================================================
// --- Runtime Module Configuration ---
// ============================================================================
typedef struct {
    // Core features
    bool needs_memory_alloc;  // Always true for heap
    bool needs_exec;
	bool needs_print;
	bool needs_math;
	bool needs_iters;
    bool needs_strings;
    bool needs_tables;

    // API modes (mutually exclusive)
    bool needs_pico8;
    bool needs_tic80;

} RuntimeRequirements;

extern RuntimeRequirements runtime_req;

// ============================================================================
// --- String Literal Tracking ---
// ============================================================================

typedef struct StringLiteralNode {
    int id;
    char* value;
    struct StringLiteralNode* next;
} StringLiteralNode;

#define DEFAULT_FFI_RAM_RESERVE  65536 // 64 kW default (256 KB)
#define FFI_SAFETY_PADDING         256 // 256 word alignment/padding buffer

typedef struct {
    int ffi_ram_reserve_words; // Explicit reserve set by user or default
    int ffi_max_mem_detected;  // Discovered via ;;FFI_MAX_MEM
} CompilerConfig;

extern CompilerConfig o_config;

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
void        register_all_globals_prepass (ASTNode    *);
SymbolNode *register_global              (const char *);
SymbolNode *register_local               (const char *);
SymbolNode *register_parameter           (const char *, int);
void        mark_global_as_function      (ASTNode    *);
void        mark_global_as_c_function    (const char *, int);
const char *get_current_function_name    (void);
void        get_variable_access_string   (const char *, char       *);
void        push_function_context        (const char *, ASTNode    *);
void        pop_function_context         (void);
void        pop_scope                    (void);
void        push_scope                   (void);
void        push_function_scope          (void);
LoopType    current_loop_type            (void);
void        push_loop                    (int,          LoopType);
void        pop_loop                     (void);
int         current_loop                 (void);
void        analyze_closures             (ASTNode    *);
SymbolNode *register_upvalue             (const char *, int);
void        emit_load_variable           (const char *, int);
void        emit_store_variable          (const char *, int);
void        emit_initialize_local        (SymbolNode *, int);
void        emit_load_function_value     (ASTNode    *, const char *, int);
bool        name_list_contains           (NameList   *, const char *);
bool        name_list_add                (NameList  **, const char *);
int         name_list_length             (NameList   *);
SymbolNode *register_upvalue             (const char *, int);

#endif
