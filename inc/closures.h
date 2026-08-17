#ifndef __CLOSURES_H
#define __CLOSURES_H

#include "v32lua.h"

// ===========================================================================
// Closure / upvalue analysis
//
// Single top-down pass over the AST, executed once before any codegen.
// For every NODE_FUNCTION_DEF (top-level or nested) it computes:
//   - upvalues:     names it references that live in an ENCLOSING function
//   - boxed_locals: names of its OWN locals/params that a nested closure
//                    of ITS OWN captures
//
// This has to happen before codegen because a local can be captured by a
// closure that appears textually LATER in the same function body -- by the
// time we reach the local's declaration we already need to know whether to
// box it.
// ===========================================================================

typedef struct FuncAnalysisFrame
{
    ASTNode                  *def_node;   // NULL for implicit top-level chunk
    NameList                 *bound;      // names currently in scope list:
                                          // block scopes save/restore the
                                          // head to pop cleanly)
    NameList                 *free_vars;  // names referenced but not bound
    struct FuncAnalysisFrame *parent;
} FuncAnalysisFrame;

void  analyze_block          (ASTNode    *, FuncAnalysisFrame *);
void  analyze_expr           (ASTNode    *, FuncAnalysisFrame *);
void  resolve_capture        (const char *, FuncAnalysisFrame *);
void  analyze_identifier_use (const char *, FuncAnalysisFrame *);
void  analyze_expr           (ASTNode    *, FuncAnalysisFrame *);
void  analyze_block          (ASTNode    *, FuncAnalysisFrame *);
void  analyze_closures       (ASTNode    *);

#endif
