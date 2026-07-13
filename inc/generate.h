#ifndef __GENERATE_H
#define __GENERATE_H

extern char  last_emitted_inst[32];
extern char  last_emitted_dest[128];
extern char  last_emitted_src[128];

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
