#include "v32lua.h"

// ============================================================================
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
// ============================================================================

// A free variable was found somewhere inside `origin` (the innermost
// function). Walk outward through enclosing frames looking for the name in
// their bound sets. If found at frame `owner`, mark `owner` as needing to
// box that local, and register the name as an upvalue on every frame from
// `origin` up to (but not including) `owner` -- so the value gets threaded
// down through each intervening closure, not just the innermost one.
void resolve_capture (const char *name, FuncAnalysisFrame *origin)
{
    FuncAnalysisFrame *search = origin->parent;
    while (search != NULL && search->def_node != NULL) {
        if (name_list_contains(search->bound, name)) {
            // Found the owner. Mark it for boxing.
            name_list_add(&search->def_node->as.function_def.boxed_locals, name);

            // Thread it as an upvalue through every frame strictly between
            // origin and the owner (inclusive of origin itself).
            for (FuncAnalysisFrame *f = origin; f != search; f = f->parent) {
                name_list_add(&f->def_node->as.function_def.upvalues, name);
            }
            return;
        }
        search = search->parent;
    }
    // Not found in any enclosing function -- it's a global. Nothing to do:
    // globals are reachable from anywhere with no capture machinery needed.
}

// Record a plain identifier reference (read OR write -- both count).
void analyze_identifier_use (const char *name, FuncAnalysisFrame *frame)
{
    if (name_list_contains(frame->bound, name)) {
        return; // bound locally, not free
    }
    if (name_list_add(&frame->free_vars, name)) {
        resolve_capture(name, frame);
    }
}

void analyze_expr (ASTNode *node, FuncAnalysisFrame *frame)
{
    if (node == NULL) return;

    switch (node->type) {
        case NODE_IDENTIFIER:
            analyze_identifier_use(node->as.id.name, frame);
            break;

        case NODE_NUMBER:
        case NODE_STRING:
        case NODE_BOOLEAN:
        case NODE_NIL:
        case NODE_COMMENT_LINE:
        case NODE_COMMENT_BLOCK:
        case NODE_ASM:      // Raw/interpolated asm text isn't parsed for
        case NODE_RAWASM:   // identifiers -- out of scope for capture analysis.
            break;

        case NODE_ADD: case NODE_SUB: case NODE_MUL: case NODE_DIV:
        case NODE_FLOORDIV: case NODE_MOD: case NODE_AND: case NODE_OR:
        case NODE_RELATIONAL: case NODE_CONCAT:
            analyze_expr(node->as.binary.left, frame);
            analyze_expr(node->as.binary.right, frame);
            break;

        case NODE_UNARY:
            analyze_expr(node->as.unary.operand, frame);
            break;

        case NODE_TABLE_GET:
            analyze_expr(node->as.table_get.table_expr, frame);
            analyze_expr(node->as.table_get.key, frame);
            break;

        case NODE_TABLE_SET:
            analyze_expr(node->as.table_set.table_expr, frame);
            analyze_expr(node->as.table_set.key, frame);
            analyze_expr(node->as.table_set.value, frame);
            break;

        case NODE_TABLE_CONSTRUCTOR:
            for (ASTNode *e = node->as.table_constructor.initializers_head; e; e = e->next)
                analyze_expr(e, frame);
            break;

        case NODE_FUNCTION_CALL:
            analyze_expr(node->as.call.target, frame);
            for (ASTNode *a = node->as.call.args_head; a; a = a->next)
                analyze_expr(a, frame);
            break;

        case NODE_FUNCTION_POINTER:
            if (node->as.func_ptr.func_def != NULL) {
                analyze_expr(node->as.func_ptr.func_def, frame);
            }
            break;

        case NODE_FUNCTION_DEF: {
            // Entering a new closure. Push a fresh frame seeded with its
            // own parameters, analyze its body, then pop.
            FuncAnalysisFrame child = { .def_node = node, .bound = NULL,
                                         .free_vars = NULL, .parent = frame };
            for (ASTNode *p = node->as.function_def.params; p; p = p->next) {
                if (p->type == NODE_IDENTIFIER && strcmp(p->as.id.name, "...") != 0) {
                    name_list_add(&child.bound, p->as.id.name);
                }
            }
            analyze_block(node->as.function_def.body, &child);
            break;
        }

        default:
            break;
    }
}

void analyze_block (ASTNode *node, FuncAnalysisFrame *frame)
{
    while (node != NULL) {
        switch (node->type) {
            case NODE_MULTIPLE_ASSIGNMENT: {
                // Values are evaluated BEFORE new locals come into scope
                // ('local x = x' reads the outer x), so analyze them first.
                for (ASTNode *v = node->as.mult_assign.values_head; v; v = v->next)
                    analyze_expr(v, frame);

                for (ASTNode *t = node->as.mult_assign.targets_head; t; t = t->next) {
                    if (t->type == NODE_IDENTIFIER) {
                        if (node->as.mult_assign.is_local) {
                            name_list_add(&frame->bound, t->as.id.name);
                        } else {
                            analyze_identifier_use(t->as.id.name, frame); // write to an existing var
                        }
                    } else {
                        analyze_expr(t, frame); // e.g. table.field = ...
                    }
                }
                break;
            }

            case NODE_IF: {
                analyze_expr(node->as.if_stmt.condition, frame);
                NameList *saved = frame->bound;
                analyze_block(node->as.if_stmt.if_body, frame);
                frame->bound = saved;
                analyze_block(node->as.if_stmt.else_body, frame);
                frame->bound = saved;
                break;
            }

            case NODE_WHILE: {
                analyze_expr(node->as.while_loop.condition, frame);
                NameList *saved = frame->bound;
                analyze_block(node->as.while_loop.body, frame);
                frame->bound = saved;
                break;
            }

            case NODE_FOR_NUMERIC: {
                analyze_expr(node->as.for_numeric.start_expr, frame);
                analyze_expr(node->as.for_numeric.stop_expr, frame);
                analyze_expr(node->as.for_numeric.step_expr, frame);
                NameList *saved = frame->bound;
                name_list_add(&frame->bound, node->as.for_numeric.index_name);
                analyze_block(node->as.for_numeric.body, frame);
                frame->bound = saved;
                break;
            }

            case NODE_FOR_GENERIC: {
                analyze_expr(node->as.for_generic.iter_expr, frame);
                NameList *saved = frame->bound;
                for (ASTNode *v = node->as.for_generic.var_list; v; v = v->next) {
                    if (v->type == NODE_IDENTIFIER) name_list_add(&frame->bound, v->as.id.name);
                }
                analyze_block(node->as.for_generic.body, frame);
                frame->bound = saved;
                break;
            }

            case NODE_RETURN:
                for (ASTNode *e = node->as.return_stmt.expressions_head; e; e = e->next)
                    analyze_expr(e, frame);
                break;

            case NODE_FUNCTION_DEF:
                // A named function statement: `local function f() ... end` /
                // `function f() ... end`. Its own name isn't "bound" the way
                // a local is here (mark_global_as_function still handles
                // that globally), but its BODY is a nested closure exactly
                // like an anonymous one.
                analyze_expr(node, frame);
                break;

            default:
                analyze_expr(node, frame); // expression statements, calls, etc.
                break;
        }
        node = node->next;
    }
}

// Entry point: call this once, before generate_program()/generate_functions().
void analyze_closures (ASTNode *program)
{
    FuncAnalysisFrame top = { .def_node = NULL, .bound = NULL,
                               .free_vars = NULL, .parent = NULL };
    analyze_block(program, &top);

    // Cache upvalue_count on every function_def we touched, so codegen
    // doesn't have to re-walk the list every time it needs the length.
    // (Cheap enough to just do a second sweep here rather than thread a
    // callback through the analysis above.)
    // NOTE: implement via the same traversal shape as analyze_block/
    // analyze_expr if you want it computed eagerly; alternatively just
    // call name_list_length(node->as.function_def.upvalues) lazily wherever
    // upvalue_count is currently read below, and drop the cached field.
}
