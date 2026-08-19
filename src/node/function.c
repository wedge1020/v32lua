#include "v32lua.h"

void  node_function_def (ASTNode *node)
{
    const char *func_name = node->as.function_def.name;

    mark_global_as_function (node);

    bool is_nested_def = (context_stack_head != NULL);
    if (is_nested_def) {
        emit_asm("JMP __%s_skip\n", func_name);
    }

    int saved_base_spill_frame_offset = base_spill_frame_offset;
    int saved_spill_slot_for_reg[NUM_GPRS];
    int saved_register_use_distance[NUM_GPRS];
    memcpy(saved_spill_slot_for_reg, spill_slot_for_reg, sizeof(saved_spill_slot_for_reg));
    memcpy(saved_register_use_distance, register_use_distance, sizeof(saved_register_use_distance));

    push_function_context (func_name, node);

    if (g_debug_mode) {
        snprintf(g_current_label, sizeof(g_current_label), "func_%s", func_name);
    }

    emit_asm("__function_%s:\n", func_name);

    int num_locals = count_function_locals(node->as.function_def.body);
    emit_asm("PUSH BP\n");
    emit_asm("MOV BP, SP\n");

    reset_spill_slots(-(num_locals + 1));
    int total_stack = num_locals + NUM_GPRS;
    if (total_stack > 0) {
        emit_asm("ISUB SP, %d ; Reserve stack for locals + spills\n", total_stack);
    }

    // --- Default implicit return value(s): nil until overwritten ---
    {
        SymbolNode *self_sym          = resolve_symbol(func_name);
        int         self_return_count = (self_sym != NULL) ? self_sym->return_count : 1;
        if (self_return_count > 3) self_return_count = 3;
        if (self_return_count < 1) self_return_count = 1;

        emit_asm("    ; --- Default implicit return value(s): nil until overwritten ---\n");
        if (self_return_count >= 1) emit_asm("MOV R0, BOXED_NIL\n");
        if (self_return_count >= 2) emit_asm("MOV R2, BOXED_NIL\n");
        if (self_return_count >= 3) emit_asm("MOV R3, BOXED_NIL\n");
    }

    push_function_scope();

    int param_offset  = 2;
    int upvalue_count = name_list_length(node->as.function_def.upvalues);

    for (NameList *up = node->as.function_def.upvalues; up != NULL; up = up->next) {
        register_upvalue(up->name, param_offset++);
    }

    // -------------------------------------------------------------------
    // FIX (variadic parameter offset bug): pre-scan for a trailing "..."
    // marker BEFORE assigning any fixed-parameter offsets. node_function_
    // call() always pushes the caller-supplied TOTAL argument count as
    // the very last word before CALL for any variadic target (see its
    // STEP 3.5) -- since PUSH decrements SP before storing, the LAST
    // word pushed ends up at the LOWEST offset, i.e. exactly
    // [BP + 2 + upvalue_count] -- the slot the old code assigned to the
    // FIRST fixed parameter. Every fixed parameter was therefore read
    // one slot too early in any variadic function -- e.g. reading the
    // caller's pushed arg-count (a raw integer like 4) back as if it
    // were the value of the first real parameter.
    //
    // Reserving this slot up front (without registering a symbol for it)
    // shifts every real fixed parameter's offset out by exactly one,
    // matching where node_function_call() actually put them.
    // -------------------------------------------------------------------
    bool has_dots_marker = false;
    for (ASTNode *pp = node->as.function_def.params; pp != NULL; pp = pp->next) {
        if (pp->type == NODE_IDENTIFIER && strcmp(pp->as.id.name, "...") == 0) {
            has_dots_marker = true;
            break;
        }
    }

    int vararg_count_offset = -1;
    if (has_dots_marker) {
        vararg_count_offset = param_offset; // this slot will hold the runtime arg count
        param_offset++;
    }

    int is_variadic = 0;
    int fixed_param_count = 0;
    ASTNode *p = node->as.function_def.params;
    while (p != NULL) {
        if (p->type == NODE_IDENTIFIER) {
            if (strcmp(p->as.id.name, "...") == 0) {
                is_variadic = 1;
            } else {
                fixed_param_count++;
                SymbolNode *param_sym = register_parameter(p->as.id.name, param_offset++);

                if (param_sym->is_boxed) {
                    int tmp_reg = allocate_register();
                    char raw_access[256];
                    get_variable_access_string(param_sym->name, raw_access);
                    emit_asm("MOV R%d, %s ; load raw incoming value for '%s'\n",
                             tmp_reg, raw_access, param_sym->name);
                    emit_initialize_local(param_sym, tmp_reg);
                    unlock_register(tmp_reg);
                }
            }
        }
        p = p->next;
    }

    // Record variadic-access info for this function so a nested `{...}`
    // table constructor (see node_table_constructor()) can find the
    // runtime arg count and the first actual vararg value on the stack.
    if (context_stack_head != NULL) {
        context_stack_head->vararg_count_offset = vararg_count_offset;
        context_stack_head->vararg_first_offset = param_offset; // right after the last fixed param
        context_stack_head->fixed_param_count   = fixed_param_count;
    }

    int explicit_param_count = fixed_param_count;

    SymbolNode *sym = resolve_symbol(func_name);
    if (sym) {
        sym->is_variadic = is_variadic;
        sym->arity = is_variadic ? -1 : explicit_param_count;
    }

    // NOTE: the old unconditional "ISUB SP, 1 ; Space for argument count
    // at [BP-2]" local-slot reservation has been removed. The runtime
    // arg count already lives on the stack at [BP + vararg_count_offset]
    // -- a slot the CALLER pushed, not something this function needs to
    // allocate or copy into a local of its own. That old slot was never
    // actually populated with the count in the first place; it was dead,
    // uninitialized stack space.

    generate_block(node->as.function_def.body);
    pop_scope();

    emit_asm ("__%s_return:\n", func_name);
    emit_asm ("MOV SP, BP\n");
    emit_asm ("POP BP\n");

    int closure_upvalue_count = name_list_length(node->as.function_def.upvalues);
    if (closure_upvalue_count > 0) {
        emit_asm ("MOV R7, [SP] ; peek return address (don't consume it yet)\n");
        emit_asm ("IADD SP, %d ; discard return address slot + %d upvalue word%s\n",
                  1 + closure_upvalue_count, closure_upvalue_count,
                  closure_upvalue_count == 1 ? "" : "s");
        emit_asm ("JMP R7 ; manual return, stack now balanced\n");
    } else {
        emit_asm ("RET\n");
    }
    emit_asm ("\n");

    pop_function_context();

    base_spill_frame_offset = saved_base_spill_frame_offset;
    memcpy(spill_slot_for_reg, saved_spill_slot_for_reg, sizeof(spill_slot_for_reg));
    memcpy(register_use_distance, saved_register_use_distance, sizeof(register_use_distance));

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
    bool        is_named_target        = (node -> as.call.target -> type == NODE_IDENTIFIER);

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
            is_named_target = true;  // resolved to a real dotted name, e.g. a.b.c
        }
    }

    // ✅ FALLBACK: Try intrinsics again if symbol not found
    if (!target_sym && !is_dynamic_table_call) {
        if (try_emit_call_intrinsic(node, dest_reg)) {
            return; // Intrinsic caught on fallback
        }

        // Only a hard error if the target was SUPPOSED to have a name (a bare
        // identifier or a resolvable dotted path) and simply isn't declared.
        // If the target is an arbitrary expression instead -- a function
        // literal, an IIFE, the result of another call -- there's no name to
        // look up in the first place. That's a normal dynamic call; fall
        // through to the generic "evaluate target, then CALL __builtin_exec"
        // path further down, which already handles it correctly.
        if (is_named_target) {
            compiler_error(ERR_SEMANTIC, node->line_number,
                "Undeclared function: '%s'", func_name ? func_name : "<unknown>");
            return;
        }
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
        // table_reg must survive the entire argument-evaluation window
        // (STEP 2) so it can be pushed as 'self' at STEP 3 -- exactly the
        // same requirement target_reg has for the function pointer itself.
        // It's pinned + locked here for the same reason target_reg is:
        // pinning is what actually stops allocate_register() from handing
        // this same physical register number to an unrelated value (like
        // an argument) while table_reg is spilled and waiting to be
        // reloaded. A plain allocate_register() + spill_register() here
        // previously let exactly that collision happen.
        table_reg = allocate_pinned_register();
        lock_register(table_reg);
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

        // Spill table_reg but NOT target_reg (target is still locked).
        // force_spill_register() is required here (not plain
        // spill_register()) because table_reg is now pinned -- plain
        // spill_register() bails out immediately for pinned registers and
        // would silently emit nothing, leaving stale data in the spill
        // slot. force_spill_register() spills unconditionally without
        // touching the pinned flag, so table_reg's register number
        // remains reserved (allocate_register() skips all pinned
        // registers in every phase) for the whole argument-evaluation
        // window, and the ensure_in_register(table_reg) at STEP 3 below
        // reloads it correctly.
        force_spill_register(table_reg);
    }
    else
    {
        // Direct function call: foo() or module.func()
        if (!is_c_call) {
            // Standard Lua function - resolve target directly into locked register
            generate_asm(node->as.call.target, target_reg);
        }
        // For C calls, target_reg is unused (we call by name)
    }

    // -------------------------------------------------------------------------
    // STEP 1.75: Protect target_reg across argument evaluation
    // -------------------------------------------------------------------------
    // Any argument expression below may itself be (or contain) a nested
    // function call -- e.g. `add_one(add_one(add_one(5)))`. Each nested call
    // emits its own "CALL __builtin_exec", which tail-jumps into a
    // separately-compiled Lua function body free to clobber target_reg's
    // physical register number as its own internal scratch space.
    //
    // target_reg comes from allocate_pinned_register() (STEP 1), so it IS
    // pinned -- plain spill_register() bails out immediately for pinned
    // registers (that's the whole point of pinning) and would silently emit
    // nothing here. force_spill_register() is the existing escape hatch for
    // exactly this situation: it spills unconditionally without touching the
    // pinned flag, and the pre-existing ensure_in_register(target_reg) at
    // STEP 4 reloads it correctly afterward, the same as it already does for
    // ordinary spills.
    // -------------------------------------------------------------------------
    if (!is_c_call) {
        force_spill_register(target_reg);
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
        unlock_pinned_register(table_reg); // No longer needed -- also clears the pin
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

void node_function_pointer (ASTNode *node, int dest_reg)
{
    if (node->as.func_ptr.func_def) {
        generate_asm(node->as.func_ptr.func_def, 0);
    }
    emit_load_function_value(node->as.func_ptr.func_def, node->as.func_ptr.mangled_name, dest_reg);
}

