/* runtime_embed.S */
#ifdef __APPLE__
.const
#else
.section .rodata
#endif

/* Handle Apple/macOS symbol naming conventions automatically */
#ifdef __APPLE__
    .global _runtime_asm_start
    _runtime_asm_start:
        .incbin "runtime.s"
        .byte 0    /* Null terminator so C treats it as a valid string */

    .global _runtime_asm_end
    _runtime_asm_end:
#else
    .global runtime_asm_start
    runtime_asm_start:
        .incbin "runtime.s"
        .byte 0    /* Null terminator so C treats it as a valid string */

    .global runtime_asm_end
    runtime_asm_end:
#endif
