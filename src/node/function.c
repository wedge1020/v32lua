#include "v32lua.h"

void  node_function_def (ASTNode *node)
{
    const char *func_name = node->as.function_def.name;
    push_function_context(func_name);

    if (g_debug_mode) {
        snprintf(g_current_label, sizeof(g_current_label), "func_%s", func_name);
    }

    emit_asm("__function_%s:\n", func_name);

    // --- OPTIMIZATION: Check eligibility for Frame Pointer Omission ---
    int num_locals = count_function_locals(node->as.function_def.body);
    emit_asm("PUSH BP\n");
    emit_asm("MOV BP, SP\n");

    reset_spill_slots(-(num_locals + 1));
    int total_stack = num_locals + NUM_GPRS;
    if (total_stack > 0) {
        emit_asm("ISUB SP, %d ; Reserve stack for locals + spills\n", total_stack);
    }

    // ✅ CRITICAL FIX: Initialize spill slots AFTER local variables
    //reset_spill_slots(-(num_locals + NUM_GPRS));  // ✅ Initialize spill slots AFTER locals
    push_scope();

    // =============================================================
    // PARAMETER TRAVERSAL:
    // Arity is already safely stored on the symbol from Stage 4!
    // We only need to map parameters to stack offsets [BP + 2], etc.
    // =============================================================
    int param_offset = 2;
    ASTNode *p = node->as.function_def.params;
    while (p != NULL) {
        if (p->type == NODE_IDENTIFIER) {
            register_parameter(p->as.id.name, param_offset++);
        }
        p = p->next;
    }
    // =============================================================

    generate_block(node->as.function_def.body);
    pop_scope();

    // --- Function Epilogue ---
    emit_asm("__%s_return:\n", func_name);
    emit_asm("MOV SP, BP\n");
    emit_asm("POP BP\n");
    emit_asm("RET\n");
    emit_asm("\n");

    pop_function_context();
}

void  node_function_call (ASTNode *node, int  dest_reg)
{
    // =========================================================================
    // FUNCTION CALL: f(x, y, z) or obj:method(a, b)
    //
    // Strategy:
    //   1. Try hardware/builtin intrinsic first (fast path)
    //   2. Resolve target function (direct or method call)
    //   3. Evaluate and push arguments right-to-left (C ABI convention)
    //   4. Push implicit 'self' for method calls (last, so it's at [BP+2])
    //   5. Execute call and handle return value
    //
    // Registers used:
    //   - target_reg: Function pointer (PINNED during arg evaluation)
    //   - table_reg: Table for method calls (spilled after lookup)
    //   - arg_reg: Temporary for each argument evaluation
    //   - pad_reg: For padding missing arguments
    // =========================================================================

    // -------------------------------------------------------------------------
    // STEP 0: Hardware & Builtin Intrinsic Fast Path
    // -------------------------------------------------------------------------
    // Check if this call can be handled as a compile-time intrinsic
    if (try_emit_call_intrinsic(node, dest_reg)) {
        return; // Intrinsic handled - skip standard call generation
    }

    // -------------------------------------------------------------------------
    // STEP 0.5: FFI Integration - Check for C Native Functions
    // -------------------------------------------------------------------------
    SymbolNode *target_sym = NULL;

    // Resolve the target symbol
    if (node->as.call.target->type == NODE_IDENTIFIER) {
        // Direct function call: foo()
        target_sym = resolve_symbol(node->as.call.target->as.id.name);
    } else {
        // Method or table call: obj:method() or obj.method()
        char path_buf[256] = {0};
        if (resolve_static_path(node->as.call.target, path_buf)) {
            target_sym = resolve_symbol(path_buf);
            if (!target_sym) {
                // Try mangled lookup: convert '.' and ':' to '_'
                for (int i = 0; path_buf[i] != '\0'; i++) {
                    if (path_buf[i] == '.' || path_buf[i] == ':') {
                        path_buf[i] = '_';
                    }
                }
                target_sym = resolve_symbol(path_buf);
            }
        }
    }

    // Determine if this is a C ABI call (FFI)
    bool is_c_call = (target_sym != NULL && target_sym->is_c_native == 1);

    // -------------------------------------------------------------------------
    // STEP 1: Allocate and Pin Target Register
    // -------------------------------------------------------------------------
    int total_arg_count = 0;
    int target_reg = allocate_pinned_register();
    int table_reg = -1; // Only used for method calls

    // ✅ Mark as live for the duration of call setup
    mark_register_live(target_reg, 10);

    // -------------------------------------------------------------------------
    // STEP 1.5: Resolve Target Function Pointer & Cache 'self'
    // -------------------------------------------------------------------------
    if (node->as.call.is_method_call) {
        // Method call: obj:method() - need to resolve method and cache 'self'
        emit_asm("    ; --- Method call: resolve target and cache 'self' ---\n");

        ASTNode *table_get_node = node->as.call.target;
        table_reg = allocate_pinned_register();
        int key_reg = allocate_pinned_register();

        // ✅ Short-lived registers for lookup
        mark_register_live(table_reg, 5);
        mark_register_live(key_reg, 2);

        // Evaluate table expression (the object)
        generate_asm(table_get_node->as.table_get.table_expr, table_reg);

        // Evaluate method key
        generate_asm(table_get_node->as.table_get.key, key_reg);

        // Ensure both are in registers (may have been spilled)
        ensure_in_register(table_reg);
        ensure_in_register(key_reg);

        // Try hardware intrinsic for table get first
        if (!try_emit_table_get_intrinsic(
                table_get_node->as.table_get.table_expr,
                table_get_node->as.table_get.key,
                target_reg)) {
            // Fallback: Runtime table lookup
            emit_asm("PUSH R%d ; Arg1: Table pointer for method lookup\n", table_reg);
            emit_asm("PUSH R%d ; Arg2: Method key\n", key_reg);
            emit_asm("CALL __builtin_table_get\n");
            emit_asm("IADD SP, 2 ; Clean up lookup arguments\n");
            emit_asm("MOV R%d, R0 ; Store retrieved method pointer\n", target_reg);
        }

        // Clean up key register
        unlock_pinned_register(key_reg);

        // 🟡 Spill table_reg and target_reg to free registers for argument eval
        //    But keep them PINNED so they won't be reused
        spill_register(table_reg);
        spill_register(target_reg);
    } else {
        // Direct function call: foo() or module.func()
        if (!is_c_call) {
            // Standard Lua function - resolve target
            generate_asm(node->as.call.target, target_reg);
            // ✅ Spill it now so it doesn't block register allocation
            spill_register(target_reg);
        }
        // For C calls, target_reg is unused (we call by name)
    }

    // -------------------------------------------------------------------------
    // STEP 2: Evaluate & Push Explicit Arguments (Right-to-Left)
    // -------------------------------------------------------------------------
    // Count explicit arguments
    int explicit_arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL) {
        explicit_arg_count++;
        curr = curr->next;
    }

    // --- Handle Missing Arguments (Arity Padding) ---
    int actual_passed_count = explicit_arg_count +
                            (node->as.call.is_method_call ? 1 : 0);
    int expected_arity = get_expected_arity(node->as.call.target);

    if (expected_arity > actual_passed_count) {
        int missing_args = expected_arity - actual_passed_count;
        emit_asm("    ; --- Padding %d omitted arguments ---\n",
                 missing_args, is_c_call ? "with 0 (C ABI)" : "with Nil");

        // Allocate register for padding value
        int pad_reg = allocate_pinned_register();

        // ✅ Short-lived: only used for padding
        mark_register_live(pad_reg, missing_args + 1);

        if (is_c_call) {
            emit_asm("MOV R%d, 0 ; C ABI default value\n", pad_reg);
        } else {
            emit_asm("MOV R%d, BOXED_NIL ; Lua Nil for missing args\n", pad_reg);
        }

        ensure_in_register(pad_reg);

        // Push padding values (rightmost args first)
        for (int i = 0; i < missing_args; i++) {
            emit_asm("PUSH R%d ; Pad omitted argument\n", pad_reg);
            total_arg_count++;
        }

        unlock_pinned_register(pad_reg);
    }

    // --- Push Explicit Arguments (Right-to-Left for C ABI) ---
    if (explicit_arg_count > 0) {
        // Allocate array for reverse traversal
        ASTNode **arg_array = (ASTNode **)malloc(sizeof(ASTNode *) * explicit_arg_count);
        if (arg_array == NULL) {
            compiler_error(ERR_INTERNAL, -1, "Out of memory for arg buffer");
        }

        // Collect arguments
        curr = node->as.call.args_head;
        for (int i = 0; i < explicit_arg_count; i++) {
            arg_array[i] = curr;
            curr = curr->next;
        }

        emit_asm("    ; --- Pushing explicit arguments Right-to-Left ---\n");

        // Push in reverse order: Arg N, Arg N-1, ..., Arg 1
        for (int i = explicit_arg_count - 1; i >= 0; i--) {
            int arg_reg = allocate_pinned_register();
            // ✅ Short-lived: used for one argument evaluation
            mark_register_live(arg_reg, 2);

            // Evaluate argument into register
            generate_asm(arg_array[i], arg_reg);

            // For C ABI, unbox the Lua value
            if (is_c_call) {
                emit_asm("    ; --- Unbox for C ABI ---\n");
                emit_asm("AND R%d, BOXED_PAYLOAD ; Strip NaN tag bits\n", arg_reg);
            }

            // Ensure register is loaded (may have been spilled by nested calls)
            ensure_in_register(arg_reg);

            // Push onto stack
            emit_asm("PUSH R%d\n", arg_reg);
            unlock_pinned_register(arg_reg);
            total_arg_count++;
        }

        free(arg_array);
    }

    // -------------------------------------------------------------------------
    // STEP 3: Push Implicit 'self' for Method Calls (LAST)
    // -------------------------------------------------------------------------
    if (node->as.call.is_method_call) {
        emit_asm("    ; --- Pushing implicit 'self' (Top of arg stack) ---\n");

        // ✅ Ensure table_reg is loaded from its spill slot
        ensure_in_register(table_reg);

        emit_asm("PUSH R%d ; Arg 1: self\n", table_reg);
        unlock_pinned_register(table_reg); // No longer needed
        total_arg_count++;
    }

    // -------------------------------------------------------------------------
    // STEP 4: Execute Call & Clean Up Stack
    // -------------------------------------------------------------------------
    if (is_c_call) {
        // --- Direct C ABI Call ---
        // For C calls, target_reg is unused (we call by symbol name)
        unlock_pinned_register(target_reg);
        register_pinned[target_reg] = 0; // Clear pin

        emit_asm("    ; --- Direct C ABI Call ---\n");
        emit_asm("CALL _%s ; Call C symbol directly\n", target_sym->name);

        // Caller cleanup for C ABI
        if (total_arg_count > 0) {
            emit_asm("IADD SP, %d ; C ABI caller cleanup\n", total_arg_count);
        }

        // Box return value back to Lua representation
        if (dest_reg != 0) {
            emit_asm("    ; --- Box C return value ---\n");
            emit_asm("MOV R%d, R0\n", dest_reg);
            emit_asm("OR R%d, 0x7FF00000 ; Apply Lua Number tag\n", dest_reg);
        }
    } else {
        // --- Lua Function Call (via __builtin_exec) ---

        // ✅ Reload target_reg if it was spilled during argument evaluation
        if (target_reg != 0) {
            ensure_in_register(target_reg);
            emit_asm("MOV R0, R%d ; Prepare boxed target for validation\n", target_reg);
        }

        unlock_pinned_register(target_reg);

        // Call the Lua function executor (handles tag validation & tail-call)
        emit_asm("CALL __builtin_exec ; Validate and execute\n");

        // Clean up arguments from stack
        if (total_arg_count > 0) {
            emit_asm("IADD SP, %d ; Clean up call arguments\n", total_arg_count);
        }

        // Store return value if caller needs it
        if (dest_reg != 0) {
            emit_asm("MOV R%d, R0 ; Store return value\n", dest_reg);
        }
    }
}

void  node_function_pointer (ASTNode *node, int  dest_reg)
{
    emit_asm ("    ;; Load and box address of the mangled function\n");
    emit_asm ("MOV R%d, __function_%s\n", dest_reg, node -> as.func_ptr.mangled_name);
    // AUDITED: Apply Function NaN tag (Bit 31=1, Bit 22=0)
    emit_asm ("OR R%d, BOXED_FUNCTION ; Box as Function\n", dest_reg);
}
