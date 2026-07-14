#ifndef __EMIT_H
#define __EMIT_H

// Declare the external symbol created by runtime_embed.S
extern const char runtime_asm_start[];

void  emit_cart_xml (const char *, int);
void  emit_interpolated_asm (const char *);
void  emit_string_data_section (void);
int   emit_variable_map (void);
void  emit_runtime_library (void);
void  emit_asm (const char *, ...);
void  emit_truthy_jump (int, const char *);
void  emit_falsy_jump (int, const char *);

#endif
