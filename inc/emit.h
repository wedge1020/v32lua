#ifndef __EMIT_H
#define __EMIT_H

void  emit_cart_xml (const char *);
void  emit_string_data_section (void);
void  emit_variable_map (void);
void  emit_runtime_library (void);
void  emit_asm (const char *, ...);
void  emit_truthy_jump (int, const char *);
void  emit_falsy_jump (int, const char *);

#endif
