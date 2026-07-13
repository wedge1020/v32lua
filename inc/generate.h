#ifndef __GENERATE_H
#define __GENERATE_H

extern char  last_emitted_inst[32];
extern char  last_emitted_dest[128];
extern char  last_emitted_src[128];

// Debug flags set by your main argument parser (e.g., main.c)
int         g_debug_mode   = 0;    // Set to 1 if -g is passed
const char *g_asm_filename = NULL; // Pointer to output filename (e.g., "main.asm")
const char *g_lua_filename = NULL; // Pointer to input filename (e.g., "main.lua")

// State tracking variables used during AST code generation
int   g_temp_asm_line    = 1;  // Tracks current relative line inside the temp buffer
int   g_current_lua_line = 0;  // Tracks active source line being evaluated
char  g_current_label[256] = ""; // Captures a label for the current line
FILE *temp_debug_stream  = NULL; // Temporary buffer for tracking debug lines

FILE *out (void);
void  set_output_stream(FILE* stream);
void  close_output_stream(void);
void  trim_spaces (char *);
int   resolve_static_path (ASTNode *, char *);
int   check_needs_stack (ASTNode *);
void  generate_block (ASTNode *);
void  generate_asm (ASTNode *, int);
void  generate_global_setup (ASTNode *);
void  generate_functions (ASTNode *);
void  generate_program (ASTNode *);

#endif
