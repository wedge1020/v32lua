#ifndef _V32MOUSE_H
#define _V32MOUSE_H

// v32mouse mouse support (src/v32mouse.c, runtime/v32mouse.s on v32io.s)
extern bool v32mouse_wanted;        // the program uses mouse()/mouse.*/stat(32..34)
extern int  v32mouse_default_port;  // --mouse / --#mouse (config.h default)
extern bool g_cli_mouse_set;

void  v32mouse_prescan               (const char *);
int   v32mouse_emit_defines          (FILE *);
void  v32mouse_emit_setup            (void);
void  v32mouse_emit_frame_end_hook   (void);
void  v32mouse_emit_frame_start_hook (void);
int   v32mouse_call_values           (const char *);
int   emit_v32mouse_intrinsic        (ASTNode *, int);
int   try_emit_mouse_namespace_intrinsic (ASTNode *, int, const char *);
int   emit_pico8_stat_intrinsic      (ASTNode *, int);

// keyboard + mouse frame hooks together (system.wait(), the drivers)
void  v32io_emit_frame_end_hooks     (void);
void  v32io_emit_frame_start_hooks   (void);

#endif
