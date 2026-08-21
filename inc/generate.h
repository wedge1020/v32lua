#ifndef __GENERATE_H
#define __GENERATE_H

extern char  last_emitted_inst[32];
extern char  last_emitted_dest[128];
extern char  last_emitted_src[128];

// Debug flags set by your main argument parser (e.g., main.c)
extern bool        g_debug_mode;    // Set to 1 if -g is passed
extern const char *g_asm_filename; // Pointer to output filename (e.g., "main.asm")
extern const char *g_lua_filename; // Pointer to input filename (e.g., "main.lua")

// State tracking variables used during AST code generation
extern int   g_temp_asm_line;  // Tracks current relative line inside the temp buffer
extern int   g_current_lua_line;  // Tracks active source line being evaluated
extern char  g_current_label[256]; // Captures a label for the current line
extern FILE *temp_debug_stream; // Temporary buffer for tracking debug lines
extern FILE *active_out_stream;

////////////////////////////////////////////////////////////////////////////////////////
//
// node type function prototypes
//
void  node_add                 (ASTNode *, int);
void  node_and                 (ASTNode *, int);
void  node_asm                 (ASTNode *);
void  node_rawasm              (ASTNode *);
void  node_boolean             (ASTNode *, int);
void  node_break               (void);
void  node_cart_hint           (ASTNode *, int);
void  node_comment_block       (ASTNode *);
void  node_comment_line        (ASTNode *);
void  node_concat              (ASTNode *, int);
void  node_div                 (ASTNode *, int);
void  node_do_block            (ASTNode *);
void  node_floordiv            (ASTNode *, int);
void  node_for_numeric         (ASTNode *);
void  node_for_generic         (ASTNode *);
void  node_function_call       (ASTNode *, int);
void  node_function_def        (ASTNode *);
void  node_function_pointer    (ASTNode *, int);
void  node_identifier          (ASTNode *, int);
void  node_if                  (ASTNode *);
void  node_mod                 (ASTNode *, int);
void  node_mul                 (ASTNode *, int);
void  node_multiple_assignment (ASTNode *);
void  node_nil                 (int);
void  node_number              (ASTNode *, int);
void  node_or                  (ASTNode *, int);
void  node_pow                 (ASTNode *, int);
void  node_relational          (ASTNode *, int);
void  node_repeat              (ASTNode *);
void  node_return              (ASTNode *);
void  node_string              (ASTNode *, int);
void  node_sub                 (ASTNode *, int);
void  node_table_constructor   (ASTNode *, int);
void  node_table_get           (ASTNode *, int);
void  node_table_set           (ASTNode *);
void  node_unary               (ASTNode *, int);
void  node_while               (ASTNode *);

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
int   count_function_locals (ASTNode *);
int   get_expected_arity (ASTNode *);

#endif
