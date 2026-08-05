/* =============================================================
   Modular Runtime Embedding
   Each section is null-terminated and independently addressable
   ============================================================= */

#ifdef __APPLE__
    .const
#else
    .section .rodata
#endif

/* --- Memory (always included) --- */
.global runtime_memory_start
runtime_memory_start:
    .incbin "runtime/memory.s"
    .byte 0
.global runtime_memory_end
runtime_memory_end:

/* --- Exec --- */
.global runtime_exec_start
runtime_exec_start:
    .incbin "runtime/exec.s"
    .byte 0
.global runtime_exec_end
runtime_exec_end:

/* --- Tables --- */
.global runtime_table_start
runtime_table_start:
    .incbin "runtime/table.s"
    .byte 0
.global runtime_table_end
runtime_table_end:

/* --- Strings --- */
.global runtime_string_start
runtime_string_start:
    .incbin "runtime/string.s"
    .byte 0
.global runtime_string_end
runtime_string_end:

/* --- Printing --- */
.global runtime_print_start
runtime_print_start:
    .incbin "runtime/print.s"
    .byte 0
.global runtime_print_end
runtime_print_end:

/* --- PICO-8 API (all-or-nothing) --- */
.global runtime_pico8_start
runtime_pico8_start:
    .incbin "runtime/pico8.s"
    .byte 0
.global runtime_pico8_end
runtime_pico8_end:

/* --- TIC-80 API (all-or-nothing) --- */
.global runtime_tic80_start
runtime_tic80_start:
    .incbin "runtime/tic80.s"
    .byte 0
.global runtime_tic80_end
runtime_tic80_end:

/* --- constants (footer) --- */
.global runtime_constant_start
runtime_constant_start:
    .incbin "runtime/constant.s"
    .byte 0
.global runtime_constant_end
runtime_constant_end:
