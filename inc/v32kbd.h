#ifndef _V32KBD_H
#define _V32KBD_H

// v32kbd keyboard support (src/v32kbd.c, runtime/v32io.s, runtime/v32kbd.s)
#define V32KBD_QUEUE_SIZE  64      // events kbd.read()/kbd.event() can hold

extern bool v32kbd_wanted;         // the program uses key()/keyp()/kbd.*
extern int  v32kbd_default_port;   // --keyboard / --#keyboard (config.h default)
extern bool g_cli_keyboard_set;

void  v32kbd_prescan               (const char *);
int   v32kbd_emit_defines          (FILE *);
void  v32kbd_emit_setup            (void);
void  v32kbd_emit_frame_end_hook   (void);
void  v32kbd_emit_frame_start_hook (void);
bool  emit_v32kbd_key_intrinsic    (ASTNode *, int, const char *, bool);
bool  try_emit_kbd_namespace_intrinsic (ASTNode *, int, const char *);

#endif
