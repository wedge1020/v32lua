#ifndef _GC_H
#define _GC_H
// Heap management mode (src/gc.c): --gc none | arena, --gc-check

#define GC_NONE                0
#define GC_ARENA               1
#define GC_MARKSWEEP_RESERVED  2     // parsed only to say "not implemented yet"

#define ARENA_MAX_DEPTH        16    // open arena.mark()s at once
#define FREE_BIN_COUNT         22    // __malloc free lists: 2^0 .. 2^21 words

extern int  g_gc_mode;
extern bool g_gc_check;
extern bool g_cli_gc_set;
extern bool g_cli_gc_check_set;

int         gc_parse_mode       (const char *name);
const char *gc_mode_name        (int mode);
bool        gc_asm_flag         (const char *name, size_t len);
void        gc_settle_options   (void);
int         gc_emit_defines     (FILE *f);
void        gc_emit_init        (void);
void        gc_emit_safepoint   (void);
void        gc_emit_store_check (int container_reg, int value_reg);

#endif
