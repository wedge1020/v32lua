#ifndef __EMIT_H
#define __EMIT_H

// Declare all embedded symbols
extern const char runtime_memory_start[];
extern const char runtime_exec_start[];
extern const char runtime_table_start[];
extern const char runtime_math_start[];
extern const char runtime_string_start[];
extern const char runtime_print_start[];
extern const char runtime_iters_start[];
extern const char runtime_vircon32_start[];
extern const char runtime_pico8_start[];
extern const char runtime_tic80_start[];
extern const char runtime_constant_start[];

void  emit_cart_xml (const char *, int);
void  emit_interpolated_asm (const char *);
void  emit_string_data_section (void);
int   emit_variable_map (void);
void  emit_runtime_library (void);
void  emit_asm (const char *, ...);
void  emit_truthy_jump (int, const char *);
void  emit_falsy_jump (int, const char *);
void  emit_get_gamepad_inputs_intrinsic (int);
void  emit_tic80_map_data (FILE *);
void  emit_cart_title_label (const char *);

#endif
