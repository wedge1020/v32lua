// ============================================================================
//  arena.* -- explicit heap arenas, with --gc arena (src/gc.c)
//
//    local m = arena.mark()   -- open an arena: returns the heap top (a number)
//    ...                      -- allocate freely: strings, tables, closures
//    arena.release(m)         -- free all of it at once, close m (and any
//                             -- arena opened after it)
//    arena.used()             -- heap words in use right now
//
//  The runtime is runtime/arena.s. Without --gc arena the calls are refused
//  at compile time: a program written for arenas would otherwise run out of
//  memory with no hint as to why.
// ============================================================================
#include "v32lua.h"

static bool arena_no_args (ASTNode *node, const char *name)
{
    if (node->as.call.args_head != NULL) {
        compiler_error (ERR_SEMANTIC, node->line_number, "%s() takes no arguments", name);
        return false;
    }
    return true;
}

int emit_arena_intrinsic (ASTNode *node, int dest_reg, const char *func_name)
{
    bool known = strcmp (func_name, "arena.mark") == 0 ||
                 strcmp (func_name, "arena.release") == 0 ||
                 strcmp (func_name, "arena.used") == 0;
    if (!known) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "Unknown arena function '%s' (there are arena.mark, arena.release, arena.used)", func_name);
        return 0;
    }
    if (g_gc_mode != GC_ARENA) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "%s() needs arena mode: compile with --gc arena or add a --#gc arena hint", func_name);
        return 0;
    }

    if (strcmp (func_name, "arena.mark") == 0) {
        if (!arena_no_args (node, func_name)) return 0;
        emit_asm ("    CALL __arena_mark ; arena.mark()\n");
        if (dest_reg != 0) emit_asm ("    MOV R%d, R0\n", dest_reg);
        return 1;
    }
    if (strcmp (func_name, "arena.used") == 0) {
        if (!arena_no_args (node, func_name)) return 0;
        emit_asm ("    CALL __arena_used ; arena.used()\n");
        if (dest_reg != 0) emit_asm ("    MOV R%d, R0\n", dest_reg);
        return 1;
    }
    // arena.release(m)
    ASTNode *arg = node->as.call.args_head;
    if (arg == NULL || arg->next != NULL) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "arena.release() expects exactly one argument: the value arena.mark() returned");
        return 0;
    }
    emit_runtime_call_intrinsic (node, dest_reg, 1, "__arena_release");
    return 1;
}
