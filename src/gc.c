// ============================================================================
//  gc.c -- heap management mode: --gc none | arena, --gc-check
//
//  v32lua's heap is a bump allocator (__malloc in runtime/memory.s): it never
//  frees. That stays the default (--gc none): nothing below is emitted and
//  the generated code is what it always was.
//
//  --gc arena adds explicit arenas: arena.mark() remembers the heap top,
//  arena.release(m) puts it back, freeing in one step everything allocated
//  since (runtime/arena.s). Safe as long as nothing made inside the arena is
//  still referenced from outside it after the release. Two things keep the
//  common cases safe automatically:
//    - a table made BEFORE the arena that grows inside it (t[#t+1] = x on a
//      long-lived list) gets its new array/hash block "pinned": the release
//      keeps the heap up to that block (__malloc_owned, memory.s);
//    - the runtime's own long-lived buffers (PICO-8/TIC-80 RAM, the ftoa
//      scratch strings, promoted tilemaps) are always pinned.
//  What is NOT automatic is a value made in the arena and stored somewhere
//  older (a global, a table made before the mark, an upvalue): after the
//  release that reference dangles. --gc-check (debug builds) turns every
//  such store into a red panic screen naming the problem, at the store.
//
//  Runtime .s files hold mode-specific code between ';#if NAME' and
//  ';#endif' lines, which emit_embedded_asm() keeps or drops
//  (gc_asm_flag() below says which names are on). Assembly sees only the
//  lines for the selected mode, so --gc none costs nothing.
// ============================================================================
#include "v32lua.h"

int  g_gc_mode         = V32LUA_DEFAULT_GC;         // GC_NONE / GC_ARENA
bool g_gc_check        = V32LUA_DEFAULT_GC_CHECK;   // --gc-check
bool g_cli_gc_set      = false;                     // --gc given: --#gc is ignored
bool g_cli_gc_check_set = false;                    // --gc-check given

// "none" / "arena" -> mode; -1 = unknown. "marksweep" is reserved: the
// caller reports it as not implemented yet.
int gc_parse_mode (const char *name)
{
    if (name == NULL)                       return -1;
    if (strcmp (name, "none")  == 0)        return GC_NONE;
    if (strcmp (name, "arena") == 0)        return GC_ARENA;
    if (strcmp (name, "marksweep") == 0)    return GC_MARKSWEEP_RESERVED;
    return -1;
}

const char *gc_mode_name (int mode)
{
    switch (mode) {
        case GC_ARENA: return "arena";
        default:       return "none";
    }
}

// Is the ';#if NAME' block of the runtime kept? (emit_embedded_asm)
bool gc_asm_flag (const char *name, size_t len)
{
    if (len == 8 && strncmp (name, "GC_ARENA", 8) == 0)  return g_gc_mode == GC_ARENA;
    if (len == 7 && strncmp (name, "GC_NONE", 7) == 0)   return g_gc_mode == GC_NONE;
    if (len == 8 && strncmp (name, "GC_CHECK", 8) == 0)  return g_gc_mode == GC_ARENA && g_gc_check;
    return false;
}

// After option and hint processing: settle the combination. --gc-check
// without an arena has nothing to check (warn once, drop it).
void gc_settle_options (void)
{
    if (g_gc_check && g_gc_mode != GC_ARENA) {
        compiler_warning (ERR_SEMANTIC, -1,
            "--gc-check / --#gc-check only checks arenas; ignored without --gc arena");
        g_gc_check = false;
    }
}

// Arena RAM (fixed words, from emit_variable_map(), before HEAP_START):
//   ARENA_FLOOR    innermost open mark (raw heap address), 0 = no arena open
//   ARENA_PIN_TOP  heap top that a release must keep (pinned blocks below)
//   ARENA_DEPTH    number of open marks
//   ARENA_STACK    the open marks, oldest first (ARENA_MAX_DEPTH words)
// Returns the number of lines printed (for the source map's line offset).
int gc_emit_defines (FILE *f)
{
    if (g_gc_mode != GC_ARENA) return 0;
    fprintf (f, "%%define  ARENA_FLOOR              0x%.8X\n", next_ram_address);
    fprintf (f, "%%define  ARENA_PIN_TOP            0x%.8X\n", next_ram_address + 1);
    fprintf (f, "%%define  ARENA_DEPTH              0x%.8X\n", next_ram_address + 2);
    fprintf (f, "%%define  ARENA_STACK              0x%.8X\n", next_ram_address + 3);
    fprintf (f, "%%define  ARENA_MAX_DEPTH          %d\n", ARENA_MAX_DEPTH);
    next_ram_address += 3 + ARENA_MAX_DEPTH;
    return 5;
}

// The arena words start at 0 (no arena open, nothing pinned): from
// generate_global_setup(), after HEAP_POINTER is set and the ftoa scratch
// pointers are zeroed. The two 48-word ftoa scratch buffers (string.s) are
// allocated here, before any arena can be open, instead of on first use:
// almost every program turns a number into text sooner or later, usually
// inside its frame -- that is, inside an arena -- and a first allocation
// there is a pinned block (memory.s __malloc_owned), which keeps that whole
// arena's garbage below it allocated. 96 words at boot instead.
void gc_emit_init (void)
{
    if (g_gc_mode != GC_ARENA) return;
    emit_asm ("MOV R0, 0\n");
    emit_asm ("MOV [ARENA_FLOOR], R0   ; --gc arena: no arena open\n");
    emit_asm ("MOV [ARENA_PIN_TOP], R0 ; nothing pinned\n");
    emit_asm ("MOV [ARENA_DEPTH], R0\n");
    emit_asm ("MOV R0, 48\n");
    emit_asm ("PUSH R0\n");
    emit_asm ("CALL __malloc\n");
    emit_asm ("MOV [FTOA_SCRATCH_PTR_A], R0 ; arena mode: allocated before any arena\n");
    emit_asm ("CALL __malloc\n");
    emit_asm ("MOV [FTOA_SCRATCH_PTR_B], R0\n");
    emit_asm ("IADD SP, 1\n");
}

// A point where no allocation is half done and no runtime routine is
// running: the end of a frame (beside the v32io frame-end hooks). Nothing
// uses it yet -- arenas are released by the program, not here -- it is
// the hook a collecting mode would run from.
void gc_emit_safepoint (void)
{
    // (no mode collects at a safepoint yet)
}

// --gc-check: the escape check before a store of a Lua value. container_reg
// holds the RAW address of the object written into (an upvalue cell), or
// -1 for a global (always older than any arena). value_reg holds the boxed
// value. The routines preserve every register. (Table stores are checked
// inside __builtin_table_set / __builtin_setmetatable, table.s.)
void gc_emit_store_check (int container_reg, int value_reg)
{
    if (!(g_gc_mode == GC_ARENA && g_gc_check)) return;
    if (container_reg < 0) {
        emit_asm ("PUSH R%d ; --gc-check: may this value go in a global?\n", value_reg);
        emit_asm ("CALL __arena_check_global\n");
        emit_asm ("IADD SP, 1\n");
        return;
    }
    emit_asm ("PUSH R%d ; --gc-check: container\n", container_reg);
    emit_asm ("PUSH R%d ; --gc-check: value\n", value_reg);
    emit_asm ("CALL __arena_check_store\n");
    emit_asm ("IADD SP, 2\n");
}
