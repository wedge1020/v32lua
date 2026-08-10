#include "v32lua.h"

bool emit_string_byte_intrinsic(ASTNode *node, int dest_reg) {
    // Validate we have at least 1 argument (the string)
    ASTNode *arg = node->as.call.args_head;
    if (!arg) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "string.byte() requires at least 1 argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: string.byte(s [, i [, j]]) ---\n");

    // Evaluate string argument
    int str_reg = allocate_pinned_register();
    generate_asm(arg, str_reg);

    // Push string onto stack
    emit_asm("PUSH R%d             ; Arg 1: String\n", str_reg);

    // Handle optional start index (arg 2)
    arg = arg->next;
    if (arg) {
        int idx_reg = allocate_pinned_register();
        generate_asm(arg, idx_reg);
        emit_asm("PUSH R%d             ; Arg 2: Start index\n", idx_reg);
        unlock_pinned_register(idx_reg);

        // Handle optional end index (arg 3)
        arg = arg->next;
        if (arg) {
            idx_reg = allocate_pinned_register();
            generate_asm(arg, idx_reg);
            emit_asm("PUSH R%d             ; Arg 3: End index\n", idx_reg);
            unlock_pinned_register(idx_reg);
        } else {
            emit_asm("PUSH R0             ; No end index (nil)\n");
            emit_asm("MOV R0, BOXED_NIL\n");
            emit_asm("PUSH R0\n");
        }
    } else {
        // Default: no indices provided
        emit_asm("PUSH R0             ; No start index (nil)\n");
        emit_asm("MOV R0, BOXED_NIL\n");
        emit_asm("PUSH R0\n");
        emit_asm("PUSH R0             ; No end index (nil)\n");
    }

    // Call runtime routine
    emit_asm("CALL __builtin_string_byte\n");
    emit_asm("IADD SP, 3           ; Clean up 3 arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }

    unlock_pinned_register(str_reg);
    return true;
}

bool emit_string_char_intrinsic(ASTNode *node, int dest_reg) {
    // Count arguments
    ASTNode *arg = node->as.call.args_head;
    int arg_count = 0;
    while (arg) {
        arg_count++;
        arg = arg->next;
    }

    emit_asm("    ;; --- Intrinsic: string.char(b1, b2, ..., bn) ---\n");

    // Push all arguments onto stack (right-to-left for C ABI)
    arg = node->as.call.args_head;
    while (arg) {
        int arg_reg = allocate_pinned_register();
        generate_asm(arg, arg_reg);
        emit_asm("PUSH R%d             ; Byte value\n", arg_reg);
        unlock_pinned_register(arg_reg);
        arg = arg->next;
    }

    // Call runtime routine
    emit_asm("CALL __builtin_string_char\n");
    emit_asm("IADD SP, %d           ; Clean up %d arguments\n", arg_count, arg_count);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }

    return true;
}
