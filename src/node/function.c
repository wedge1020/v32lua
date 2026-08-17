#include "v32lua.h"

void  node_function_def (ASTNode *node)
{
    const char *func_name = node->as.function_def.name;

    mark_global_as_function (node);

    // Nested/local functions are compiled inline, in the middle of the
    // enclosing function's code. Unlike top-level functions (only ever
    // reached via CALL), straight-line execution would otherwise fall
    // directly into the body and hit its RET without ever having been
    // CALLed, popping garbage off the stack as a "return address."
    // Guard it with a jump around the whole definition. Top-level scope
    // has an empty context stack, so this only fires for nested defs.
    bool is_nested_def = (context_stack_head != NULL);
    if (is_nested_def) {
        emit_asm("JMP __%s_skip\n", func_name);
    }

    // ===== Register local function names =====
    /*
    bool is_local_func = false;
    if (node->next != NULL && node->next->type == NODE_MULTIPLE_ASSIGNMENT) {
        is_local_func = node->next->as.mult_assign.is_local;
    }

    if (is_local_func) {
        SymbolNode *sym = register_local(func_name);
        sym->is_function = 1;
        int count = 0;
        ASTNode *p = node->as.function_def.params;
        while (p != NULL) {
            count++;
            p = p->next;
        }
        sym->arity = count;

        // ===== INITIALIZE LOCAL FUNCTION VARIABLE =====
        char access_str[128];
        get_variable_access_string(func_name, access_str);
        emit_asm("MOV R0, __function_%s\n", func_name);
        emit_asm("OR R0, BOXED_FUNCTION\n");
        emit_asm("MOV %s, R0\n", access_str);
    }*/

    push_function_context (func_name, node);

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

    // ============================================================
    // PARAMETER TRAVERSAL:
    // Arity is already safely stored on the symbol from Stage 4!
    // We only need to map parameters to stack offsets [BP + 2], etc.
    // ============================================================
    int param_offset = 2;
    int is_variadic = 0;
    ASTNode *p = node->as.function_def.params;
    while (p != NULL) {
        if (p->type == NODE_IDENTIFIER) {
            // Skip "..." - it's a variadic marker, not a real parameter
            if (strcmp(p->as.id.name, "...") == 0) {
                is_variadic = 1;
            } else {
                register_parameter(p->as.id.name, param_offset++);
            }
        }
        p = p->next;
    }

    // Mark function symbol as variadic
    SymbolNode *sym = resolve_symbol(func_name);
    if (sym) {
        sym->is_variadic = is_variadic;
        sym->arity = is_variadic ? -1 : (param_offset - 2);
    }

    // For variadic functions: reserve space for argument count at [BP-2]
    if (is_variadic) {
        emit_asm ("    ; --- Variadic function: reserve space for arg count ---\n");
        emit_asm ("ISUB SP, 1 ; Space for argument count at [BP-2]\n");
    }
    // =============================================================

    generate_block(node->as.function_def.body);
    pop_scope();

    // --- Function Epilogue ---
    emit_asm ("__%s_return:\n", func_name);
    emit_asm ("MOV SP, BP\n");
    emit_asm ("POP BP\n");
    emit_asm ("RET\n");
    emit_asm ("\n");

    pop_function_context();

    if (is_nested_def) {
        emit_asm("__%s_skip:\n", func_name);
    }
}

// ============================================================================
// FUNCTION CALL: f(x, y, z) or obj:method(a, b)
//
// Strategy:
//   1. Try hardware/builtin intrinsic first (fast path)
//   2. Resolve target function (direct or method call)
//   3. Evaluate and push arguments right-to-left (C ABI convention)
//   4. Push implicit 'self' for method calls (last, so it's at [BP+2])
//   5. Execute call and handle return value
//
// REGISTER FIX: Changed from allocate_pinned_register() to allocate_register()
// + lock_register(). This prevents target_reg from blocking ALL register
// allocation during argument evaluation, which was causing register exhaustion
// in nested calls (e.g., format_result() inside ipairs loops).
//
// The target register is still protected (locked), but can be spilled if
// absolutely necessary, unlike pinned registers which can NEVER be spilled.
//
// Registers used:
//   - target_reg: Function pointer (LOCKED - won't be reused for args)
//   - table_reg: Table for method calls (spilled after lookup)
//   - arg_reg: Temporary for each argument evaluation
//   - pad_reg: For padding missing arguments
// ============================================================================
void  node_function_call (ASTNode *node, int  dest_reg)
{
    // -------------------------------------------------------------------------
    // STEP 0: Hardware & Builtin Intrinsic Fast Path
    // -------------------------------------------------------------------------
    if (try_emit_call_intrinsic (node, dest_reg))
    {
        return; // Intrinsic handled - skip standard call generation
    }

    // -------------------------------------------------------------------------
    // STEP 0.5: Resolve Target Symbol
    // -------------------------------------------------------------------------
    SymbolNode *target_sym             = NULL;
    const char *func_name              = NULL;
    bool        is_dynamic_table_call  = (node -> as.call.target -> type == NODE_TABLE_GET);

    if (g_verbose_debug)
    {
        fprintf (stderr, "[debug] node_function_call() Function call: ");
        if (node -> as.call.target -> type == NODE_IDENTIFIER)
        {
            fprintf (stderr, "identifier '%s'\n", node -> as.call.target -> as.id.name);
        }
        else
        {
            fprintf (stderr, "complex target (type=%d)\n", node -> as.call.target -> type);
        }
    }

    if (node->as.call.target->type == NODE_IDENTIFIER) {
        func_name = node->as.call.target->as.id.name;
        target_sym = resolve_symbol(func_name);
    } else {
        char path_buf[256] = {0};
        if (resolve_static_path(node->as.call.target, path_buf)) {
            func_name = path_buf;
            target_sym = resolve_symbol(func_name);
        }
    }

    // ✅ FALLBACK: Try intrinsics again if symbol not found
    if (!target_sym && !is_dynamic_table_call) {
        if (try_emit_call_intrinsic(node, dest_reg)) {
            return; // Intrinsic caught on fallback
        }
        compiler_error(ERR_SEMANTIC, node->line_number,
            "Undeclared function: '%s'", func_name ? func_name : "<unknown>");
        return;
    }

    // -------------------------------------------------------------------------
    // STEP 0.75: Full Symbol Resolution for FFI (REST OF YOUR EXISTING CODE)
    // -------------------------------------------------------------------------
    target_sym = NULL;

    // Resolve the target symbol
    if (node->as.call.target->type == NODE_IDENTIFIER) {
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

    bool is_c_call = (target_sym != NULL && target_sym->is_c_native == 1);

    // -------------------------------------------------------------------------
    // STEP 1: Allocate and Resolve Target Function Pointer
    // -------------------------------------------------------------------------
    // REGISTER FIX: Use allocate_register() + lock_register() instead of
    // allocate_pinned_register(). This allows the allocator to spill this
    // register if absolutely necessary during argument evaluation, while still
    // preventing normal reuse. Pinned registers can NEVER be spilled, which
    // was causing the exhaustion issue.
    // -------------------------------------------------------------------------
    int total_arg_count = 0;
    int target_reg = allocate_pinned_register();  // NOT pinned - allows emergency spilling
    lock_register(target_reg);             // Still protected from normal reuse
    int table_reg = -1; // Only used for method calls

    // -------------------------------------------------------------------------
    // STEP 1.5: Resolve Target Function Pointer & Cache 'self'
    // -------------------------------------------------------------------------
    if (node->as.call.is_method_call) {
        emit_asm("    ; --- Method call: resolve target and cache 'self' ---\n");

        ASTNode *table_get_node = node->as.call.target;
        table_reg = allocate_register();
        int key_reg = allocate_register();

        // Short-lived registers for lookup
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
        unlock_register(key_reg);

        // Spill table_reg but NOT target_reg (target is still locked)
        // Method lookup is done, but we still need the method pointer in target_reg
        spill_register(table_reg);
    } else {
        // Direct function call: foo() or module.func()
        if (!is_c_call) {
            // Standard Lua function - resolve target directly into locked register
            generate_asm(node->as.call.target, target_reg);
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

        int pad_reg = allocate_register();
        mark_register_live(pad_reg, missing_args + 1);

        if (is_c_call) {
            emit_asm("MOV R%d, 0 ; C ABI default value\n", pad_reg);
        } else {
            emit_asm("MOV R%d, BOXED_NIL ; Lua Nil for missing args\n", pad_reg);
        }

        ensure_in_register(pad_reg);

        for (int i = 0; i < missing_args; i++) {
            emit_asm("PUSH R%d ; Pad omitted argument\n", pad_reg);
            total_arg_count++;
        }

        unlock_register(pad_reg);
    }

    // --- Push Explicit Arguments (Right-to-Left for C ABI) ---
    if (explicit_arg_count > 0) {
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

        // REGISTER FIX: Because target_reg is only LOCKED (not pinned),
        // argument evaluation can now reuse other registers or even spill
        // target_reg if absolutely necessary. This prevents exhaustion.
        for (int i = explicit_arg_count - 1; i >= 0; i--) {
            int arg_reg = allocate_register();
            mark_register_live(arg_reg, 2);

            generate_asm(arg_array[i], arg_reg);

            if (is_c_call) {
                emit_asm("    ; --- Unbox for C ABI ---\n");
                emit_asm("AND R%d, BOXED_PAYLOAD ; Strip NaN tag bits\n", arg_reg);
            }

            ensure_in_register(arg_reg);
            emit_asm("PUSH R%d\n", arg_reg);
            unlock_register(arg_reg);
            total_arg_count++;
        }

        free(arg_array);
    }

    // -------------------------------------------------------------------------
    // STEP 3: Push Implicit 'self' for Method Calls (LAST)
    // -------------------------------------------------------------------------
    if (node->as.call.is_method_call) {
        emit_asm("    ; --- Pushing implicit 'self' (Top of arg stack) ---\n");

        // Ensure table_reg is loaded from its spill slot
        ensure_in_register(table_reg);

        emit_asm("PUSH R%d ; Arg 1: self\n", table_reg);
        unlock_register(table_reg); // No longer needed
        total_arg_count++;
    }

    // -------------------------------------------------------------------------
    // STEP 3.5: Push Argument Count for Variadic Functions
    // -------------------------------------------------------------------------
    if (target_sym && target_sym->is_variadic) {
        emit_asm("    ; --- Variadic call: push argument count ---\n");
        int arg_count_reg = allocate_register();
        emit_asm("MOV R%d, %d ; Load total argument count\n", arg_count_reg, total_arg_count);
        emit_asm("PUSH R%d ; Push arg count for variadic function\n", arg_count_reg);
        unlock_register(arg_count_reg);
        total_arg_count++; // Account for the arg count itself
    }

    // -------------------------------------------------------------------------
    // STEP 4: Execute Call & Clean Up Stack
    // -------------------------------------------------------------------------
    if (is_c_call) {
        // --- Direct C ABI Call ---
        // Unlock target_reg before cleanup (no longer needed)
        unlock_pinned_register(target_reg);

        emit_asm("    ; --- Direct C ABI Call ---\n");
        emit_asm("CALL _%s ; Call C symbol directly\n", target_sym->name);

        if (total_arg_count > 0) {
            emit_asm("IADD SP, %d ; C ABI caller cleanup\n", total_arg_count);
        }

        if (dest_reg != 0) {
            emit_asm("    ; --- Box C return value ---\n");
            emit_asm("MOV R%d, R0\n", dest_reg);
            emit_asm("OR R%d, 0x7FF00000 ; Apply Lua Number tag\n", dest_reg);
        }
    } else {
        // --- Lua Function Call (via __builtin_exec trampoline) ---
        // Argument evaluation above may have needed target_reg's register
        // number for something else, in which case allocate_register()
        // correctly spilled target_reg's value to preserve it. Reload it
        // now if that happened -- a no-op if it's still in-register.
        ensure_in_register (target_reg);

        // Move target to R0 for __builtin_exec (validation & execution)
        emit_asm("MOV R0, R%d ; Prepare boxed target for validation\n", target_reg);

        // Unlock target_reg now that we've moved its value to R0
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

void node_function_pointer(ASTNode *node, int dest_reg) {
    if (node->as.func_ptr.func_def) {
        generate_asm(node->as.func_ptr.func_def, 0);
    }
    //emit_asm("MOV R%d, [func_%s]\n", dest_reg, node->as.func_ptr.mangled_name);
    emit_asm ("    ;; Load and box address of the mangled function\n");
    emit_asm ("MOV R%d, __function_%s\n", dest_reg, node -> as.func_ptr.mangled_name);
    // AUDITED: Apply Function NaN tag (Bit 31=1, Bit 22=0)
    emit_asm ("OR R%d, BOXED_FUNCTION ; Box as Function\n", dest_reg);
}
