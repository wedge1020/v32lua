#include "v32lua.h"

// ============================================================================
// --- Static Helper Functions for Complex Calls ---
// ============================================================================

void emit_print_intrinsic(ASTNode *node)
{
    // 1. Extract the 3 positional arguments from the argument linked list
    ASTNode *arg_x   = node->as.call.args_head;
    ASTNode *arg_y   = (arg_x != NULL) ? arg_x->next : NULL;
    ASTNode *arg_val = (arg_y != NULL) ? arg_y->next : NULL;

    // Basic semantic validation to protect against malformed user scripts
    if (arg_x == NULL || arg_y == NULL || arg_val == NULL) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                       "print() intrinsic requires 3 arguments: print(x, y, value)");
    }

    // 2. Allocate registers and evaluate each argument expression
    int reg_x = allocate_pinned_register();
    int reg_y = allocate_pinned_register();
    int reg_val = allocate_pinned_register();

    // Evaluate coordinates first
    generate_asm(arg_x, reg_x);
    generate_asm(arg_y, reg_y);

    // Save coordinates on stack before evaluating value (which may call strcat)
    emit_asm("PUSH R%d ; Save X coordinate\n", reg_x);
    emit_asm("PUSH R%d ; Save Y coordinate\n", reg_y);

    // Now evaluate value - this may call __builtin_strcat which clobbers registers
    generate_asm(arg_val, reg_val);

    // Restore coordinates from stack
    emit_asm("POP R%d ; Restore Y coordinate\n", reg_y);
    emit_asm("POP R%d ; Restore X coordinate\n", reg_x);

    emit_asm("    ;; --- Intrinsic: print(x, y, value) ---\n");

    // 3. Convert text coordinates from Lua Floats to Hardware Integers
    emit_asm("CFI R%d ; Convert X to hardware integer\n", reg_x);
    emit_asm("CFI R%d ; Convert Y to hardware integer\n", reg_y);

    // 4. Push arguments to the stack (Left-to-Right layout)
    emit_asm("PUSH R%d ; Push X coordinate\n", reg_x);
    emit_asm("PUSH R%d ; Push Y coordinate\n", reg_y);
    emit_asm("PUSH R%d ; Push raw value to convert\n", reg_val);

    // 5. Coerce the value to a string pointer
    emit_asm("CALL __builtin_tostring\n");
    emit_asm("MOV  [SP], R0 ; Overwrite raw value with the string pointer\n");

    // 6. Fire the printing routine and tear down the stack frame
    emit_asm("CALL __builtin_print\n");
    emit_asm("IADD SP, 3 ; Clean up x, y, and string from the stack\n");

    // 7. Unlock registers back to the compiler pool
    unlock_pinned_register(reg_val);
    unlock_pinned_register(reg_y);
    unlock_pinned_register(reg_x);
}

// Returns true if the node was successfully intercepted and processed as a printf intrinsic.
bool emit_printf_intrinsic(ASTNode *node, int dest_reg)
{
    // 1. Validate that this is a function call node[cite: 8]
    if (node == NULL || node->type != NODE_FUNCTION_CALL) {
        return false;
    }

    // 2. Verify the target is specifically an identifier named "printf"[cite: 8]
    if (node->as.call.target == NULL ||
        node->as.call.target->type != NODE_IDENTIFIER ||
        strcmp(node->as.call.target->as.id.name, "printf") != 0)
    {
        return false;
    }

    emit_asm("    ;; --- Intrinsic: printf ---");

    // 3. Count the provided explicit arguments[cite: 8]
    int explicit_arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL) {
        explicit_arg_count++;
        curr = curr->next;
    }

    if (explicit_arg_count > 0) {
        // 4. Buffer arguments into an array for Right-to-Left traversal (Standard C ABI)[cite: 8]
        ASTNode **arg_array = (ASTNode **)malloc(sizeof(ASTNode *) * explicit_arg_count);
        if (arg_array == NULL) {
            compiler_error(ERR_INTERNAL, -1, "Out of memory allocating printf argument buffer");
        }

        curr = node->as.call.args_head;
        for (int i = 0; i < explicit_arg_count; i++) {
            arg_array[i] = curr;
            curr = curr->next;
        }

        emit_asm("    ; --- Pushing printf arguments Right-to-Left ---");

        // 5. Evaluate and push arguments in reverse order[cite: 8]
        for (int i = explicit_arg_count - 1; i >= 0; i--) {
            int arg_reg = allocate_register();

            // Generate assembly for the argument and leave the result in arg_reg[cite: 8]
            generate_asm(arg_array[i], arg_reg);

            emit_asm("PUSH R%d ; Push argument", arg_reg);
            unlock_register(arg_reg);
        }

        free(arg_array);
    }

    // 6. Invoke the runtime library's variadic builtin routine[cite: 8]
    emit_asm("CALL __builtin_printf");

    // 7. Clean up the stack frame (Caller cleanup)[cite: 8]
    if (explicit_arg_count > 0) {
        emit_asm("IADD SP, %d ; Clean up printf arguments", explicit_arg_count);
    }

    // 8. Capture the return value if the expression requires it[cite: 8]
    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0 ; Store return value", dest_reg);
    }

    return true;
}
