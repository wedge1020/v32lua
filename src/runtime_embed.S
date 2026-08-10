/* =============================================================
   Modular Runtime Embedding for v32lua
   Each section is null-terminated and independently addressable.
   On macOS, symbols are prefixed with underscore per ABI convention.
   ============================================================= */

#ifdef __APPLE__
    .const
#else
    .section .rodata
#endif

/* --- Memory (always included) --- */
#ifdef __APPLE__
    .global _runtime_memory_start
    _runtime_memory_start:
#else
    .global runtime_memory_start
    runtime_memory_start:
#endif
    .incbin "runtime/memory.s"
    .byte 0
#ifdef __APPLE__
    .global _runtime_memory_end
    _runtime_memory_end:
#else
    .global runtime_memory_end
    runtime_memory_end:
#endif

/* --- Exec --- */
#ifdef __APPLE__
    .global _runtime_exec_start
    _runtime_exec_start:
#else
    .global runtime_exec_start
    runtime_exec_start:
#endif
    .incbin "runtime/exec.s"
    .byte 0
#ifdef __APPLE__
    .global _runtime_exec_end
    _runtime_exec_end:
#else
    .global runtime_exec_end
    runtime_exec_end:
#endif

/* --- Tables --- */
#ifdef __APPLE__
    .global _runtime_table_start
    _runtime_table_start:
#else
    .global runtime_table_start
    runtime_table_start:
#endif
    .incbin "runtime/table.s"
    .byte 0
#ifdef __APPLE__
    .global _runtime_table_end
    _runtime_table_end:
#else
    .global runtime_table_end
    runtime_table_end:
#endif

/* --- Math Library Routines --- */
#ifdef __APPLE__
    .global _runtime_math_start
    _runtime_math_start:
#else
    .global runtime_math_start
    runtime_math_start:
#endif
    .incbin "runtime/math.s"
    .byte 0
#ifdef __APPLE__
    .global _runtime_math_end
    _runtime_math_end:
#else
    .global runtime_math_end
    runtime_math_end:
#endif

/* --- Strings --- */
#ifdef __APPLE__
    .global _runtime_string_start
    _runtime_string_start:
#else
    .global runtime_string_start
    runtime_string_start:
#endif
    .incbin "runtime/string.s"
    .byte 0
#ifdef __APPLE__
    .global _runtime_string_end
    _runtime_string_end:
#else
    .global runtime_string_end
    runtime_string_end:
#endif

/* --- Printing --- */
#ifdef __APPLE__
    .global _runtime_print_start
    _runtime_print_start:
#else
    .global runtime_print_start
    runtime_print_start:
#endif
    .incbin "runtime/print.s"
    .byte 0
#ifdef __APPLE__
    .global _runtime_print_end
    _runtime_print_end:
#else
    .global runtime_print_end
    runtime_print_end:
#endif

/* --- PICO-8 API (all-or-nothing) --- */
#ifdef __APPLE__
    .global _runtime_pico8_start
    _runtime_pico8_start:
#else
    .global runtime_pico8_start
    runtime_pico8_start:
#endif
    .incbin "runtime/pico8.s"
    .byte 0
#ifdef __APPLE__
    .global _runtime_pico8_end
    _runtime_pico8_end:
#else
    .global runtime_pico8_end
    runtime_pico8_end:
#endif

/* --- TIC-80 API (all-or-nothing) --- */
#ifdef __APPLE__
    .global _runtime_tic80_start
    _runtime_tic80_start:
#else
    .global runtime_tic80_start
    runtime_tic80_start:
#endif
    .incbin "runtime/tic80.s"
    .byte 0
#ifdef __APPLE__
    .global _runtime_tic80_end
    _runtime_tic80_end:
#else
    .global runtime_tic80_end
    runtime_tic80_end:
#endif

/* --- Constants (footer) --- */
#ifdef __APPLE__
    .global _runtime_constant_start
    _runtime_constant_start:
#else
    .global runtime_constant_start
    runtime_constant_start:
#endif
    .incbin "runtime/constant.s"
    .byte 0
#ifdef __APPLE__
    .global _runtime_constant_end
    _runtime_constant_end:
#else
    .global runtime_constant_end
    runtime_constant_end:
#endif
