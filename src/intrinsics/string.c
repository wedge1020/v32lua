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

    // ============================================================
    // PHASE 1: Evaluate all arguments into registers first
    // This ensures we don't lose track of register allocations
    // ============================================================
    int str_reg = allocate_pinned_register();
    generate_asm(arg, str_reg);

    int start_reg = 0;
    bool has_start = false;
    arg = arg->next;
    if (arg) {
        start_reg = allocate_pinned_register();
        generate_asm(arg, start_reg);
        has_start = true;

        int end_reg = 0;
        bool has_end = false;
        arg = arg->next;
        if (arg) {
            end_reg = allocate_pinned_register();
            generate_asm(arg, end_reg);
            has_end = true;
        }

        // =========================================================
        // PHASE 2: Push arguments in REVERSE order
        //
        // VIRCON32 STACK BEHAVIOR: PUSH decrements SP *before* storing
        // So pushing A, B, C results in stack: [SP] = C, [SP+1] = B, [SP+2] = A
        //
        // Runtime __builtin_string_byte expects:
        //   [BP+2] = string (first argument)
        //   [BP+3] = start index (second argument)
        //   [BP+4] = end index (third argument)
        //
        // To achieve this, we push in reverse: end, start, string
        // This way after CALL: [BP+2] = string, [BP+3] = start, [BP+4] = end
        // =========================================================
        if (has_end) {
            emit_asm("PUSH R%d             ; Arg 3: End index\n", end_reg);
            unlock_pinned_register(end_reg);
        } else {
            // No end index provided - use nil
            emit_asm("MOV R0, BOXED_NIL\n");
            emit_asm("PUSH R0             ; No end index (nil)\n");
        }

        emit_asm("PUSH R%d             ; Arg 2: Start index\n", start_reg);
        unlock_pinned_register(start_reg);
    } else {
        // No start or end indices - both default to nil
        emit_asm("MOV R0, BOXED_NIL\n");
        emit_asm("PUSH R0             ; No end index (nil)\n");
        emit_asm("PUSH R0             ; No start index (nil)\n");
    }

    // Push string LAST so it ends up at [BP+2] after CALL
    emit_asm("PUSH R%d             ; Arg 1: String\n", str_reg);

    // =========================================================
    // PHASE 3: Call runtime and clean up
    // =========================================================
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

    // ============================================================
    // PHASE 1: Evaluate all arguments into registers first
    // We need to hold all registers until we push in reverse order
    // ============================================================
    arg = node->as.call.args_head;
    int *arg_regs = malloc(arg_count * sizeof(int));
    for (int i = 0; i < arg_count && arg; i++) {
        arg_regs[i] = allocate_pinned_register();
        generate_asm(arg, arg_regs[i]);
        arg = arg->next;
    }

    // ============================================================
    // PHASE 2: Push arguments in REVERSE order
    //
    // Runtime __builtin_string_char expects:
    //   [BP+2] = first byte argument
    //   [BP+3] = second byte argument
    //   ...
    //   [BP+2+N] = BOXED_NIL (terminator)
    //
    // It scans forward from [BP+2] until it hits NIL.
    //
    // To achieve this with downward-growing stack:
    // Push NIL first, then argN, argN-1, ..., arg1
    // This results in stack: arg1, arg2, ..., argN, NIL
    // After CALL: [BP+2] = arg1, [BP+3] = arg2, ..., [BP+2+N] = NIL
    // ============================================================
    emit_asm("MOV R0, BOXED_NIL\n");
    emit_asm("PUSH R0             ; BOXED_NIL terminator\n");

    // Push arguments from last to first
    for (int i = arg_count - 1; i >= 0; i--) {
        emit_asm("PUSH R%d             ; Byte value\n", arg_regs[i]);
        unlock_pinned_register(arg_regs[i]);
    }
    free(arg_regs);

    // ============================================================
    // PHASE 3: Call runtime and clean up
    // ============================================================
    emit_asm("CALL __builtin_string_char\n");
    emit_asm("IADD SP, %d           ; Clean up %d arguments\n", arg_count + 1, arg_count + 1);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }

    return true;
}

bool emit_tostring_intrinsic(ASTNode *node, int dest_reg) {
    // Validate exactly 1 argument
    ASTNode *arg = node->as.call.args_head;
    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "tostring() expects exactly 1 argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: tostring(value) ---\n");

    // Evaluate argument into a pinned register
    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);

    // Push argument onto stack for __builtin_tostring
    emit_asm("    PUSH R%d             ; Arg 1: Value to convert\n", arg_reg);

    // Call the runtime routine
    emit_asm("    CALL __builtin_tostring\n");
    emit_asm("    IADD SP, 1           ; Clean up 1 argument\n");

    // Store result if needed
    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0         ; Store string result\n", dest_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}

/**
 * Emits assembly for the string.format() intrinsic.
 * Supports Lua 5.1 format specifiers.
 */
bool emit_string_format_intrinsic(ASTNode *node, int dest_reg) {
    ASTNode *arg = node->as.call.args_head;
    if (!arg) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "string.format() requires at least 1 argument (format string)");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: string.format(format, ...) ---\n");

    int fmt_reg = allocate_pinned_register();
    generate_asm(arg, fmt_reg);
    emit_asm("PUSH R%d             ; Arg 1: Format string\n", fmt_reg);

    // Push format arguments (left-to-right evaluation, matching Lua semantics)
    arg = arg->next;
    int arg_count = 0;
    while (arg) {
        int arg_reg = allocate_pinned_register();
        generate_asm(arg, arg_reg);
        emit_asm("PUSH R%d             ; Format arg %d\n", arg_reg, arg_count + 1);
        unlock_pinned_register(arg_reg);
        arg = arg->next;
        arg_count++;
    }

    // Push terminator (ONLY ONCE)
    emit_asm("MOV R0, BOXED_NIL\n");
    emit_asm("PUSH R0             ; BOXED_NIL terminator\n");

    // --- Reverse the pushed block -----------------------------------
    // __builtin_string_format expects [BP+2]=format string, [BP+3]=first
    // format arg, [BP+4]=second, etc. We just pushed (format, arg1, ...,
    // argN, NIL) in that natural left-to-right order, which -- since the
    // LAST-pushed item always ends up at the LOWEST stack offset on this
    // CPU -- puts the format string at the HIGHEST offset instead of the
    // lowest. Reversing via direct indexed swaps (rather than re-pushing)
    // doesn't touch argument evaluation, so evaluation order and any
    // argument side effects are unaffected; this only reorders
    // already-computed values sitting on the stack.
    int total = arg_count + 2;  // format string + args + terminator
    for (int i = 0; i < total / 2; i++) {
        int j = total - 1 - i;
        emit_asm("MOV R0, [SP+%d]\n", i);
        emit_asm("MOV R1, [SP+%d]\n", j);
        emit_asm("MOV [SP+%d], R1\n", i);
        emit_asm("MOV [SP+%d], R0\n", j);
    }

    emit_asm("CALL __builtin_string_format\n");
    emit_asm("IADD SP, %d           ; Clean up arguments\n", arg_count + 2);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }

    unlock_pinned_register(fmt_reg);
    return true;
}

// string.len(s)
bool emit_string_len_intrinsic(ASTNode *node, int dest_reg) {
    ASTNode *arg = node->as.call.args_head;
    if (!arg) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "string.len() requires 1 argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: string.len(s) ---\n");

    int str_reg = allocate_pinned_register();
    generate_asm(arg, str_reg);

    emit_asm("PUSH R%d             ; Arg 1: string\n", str_reg);
    emit_asm("CALL __builtin_string_len\n");
    emit_asm("IADD SP, 1           ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }

    unlock_pinned_register(str_reg);
    return true;
}

bool emit_string_sub_intrinsic(ASTNode *node, int dest_reg) {
    ASTNode *arg_s = node->as.call.args_head;
    if (!arg_s || !arg_s->next) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "string.sub() requires at least 2 arguments (s, i)");
        return false;
    }
    ASTNode *arg_i = arg_s->next;
    ASTNode *arg_j = arg_i->next;  // optional -- defaults to end of string

    emit_asm("    ;; --- Intrinsic: string.sub(s, i [, j]) ---\n");

    int str_reg = allocate_pinned_register();
    generate_asm(arg_s, str_reg);

    int i_reg = allocate_pinned_register();
    generate_asm(arg_i, i_reg);

    int j_reg = 0;
    bool has_j = false;
    if (arg_j) {
        j_reg = allocate_pinned_register();
        generate_asm(arg_j, j_reg);
        has_j = true;
    }

    // Push in reverse: j, i, s -> after CALL: [BP+2]=s [BP+3]=i [BP+4]=j
    if (has_j) {
        emit_asm("PUSH R%d             ; Arg 3: j (end index)\n", j_reg);
        unlock_pinned_register(j_reg);
    } else {
        emit_asm("MOV R0, BOXED_NIL\n");
        emit_asm("PUSH R0             ; No j provided -- runtime defaults to end of string\n");
    }

    emit_asm("PUSH R%d             ; Arg 2: i (start index)\n", i_reg);
    unlock_pinned_register(i_reg);
    emit_asm("PUSH R%d             ; Arg 1: string\n", str_reg);
    unlock_pinned_register(str_reg);

    emit_asm("CALL __builtin_string_sub\n");
    emit_asm("IADD SP, 3           ; Clean up 3 arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }
    return true;
}

// string.upper(s)
bool emit_string_upper_intrinsic(ASTNode *node, int dest_reg) {
    ASTNode *arg = node->as.call.args_head;
    if (!arg) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "string.upper() requires 1 argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: string.upper(s) ---\n");

    int str_reg = allocate_pinned_register();
    generate_asm(arg, str_reg);

    emit_asm("PUSH R%d             ; Arg 1: string\n", str_reg);
    emit_asm("CALL __builtin_string_upper\n");
    emit_asm("IADD SP, 1           ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }

    unlock_pinned_register(str_reg);
    return true;
}

// string.lower(s)
bool emit_string_lower_intrinsic(ASTNode *node, int dest_reg) {
    ASTNode *arg = node->as.call.args_head;
    if (!arg) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "string.lower() requires 1 argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: string.lower(s) ---\n");

    int str_reg = allocate_pinned_register();
    generate_asm(arg, str_reg);

    emit_asm("PUSH R%d             ; Arg 1: string\n", str_reg);
    emit_asm("CALL __builtin_string_lower\n");
    emit_asm("IADD SP, 1           ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }

    unlock_pinned_register(str_reg);
    return true;
}

// string.rep(s, n)
bool emit_string_rep_intrinsic(ASTNode *node, int dest_reg) {
    ASTNode *arg_s = node->as.call.args_head;
    if (!arg_s || !arg_s->next) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "string.rep() requires 2 arguments (s, n)");
        return false;
    }
    ASTNode *arg_n = arg_s->next;

    emit_asm("    ;; --- Intrinsic: string.rep(s, n) ---\n");

    int str_reg = allocate_pinned_register();
    generate_asm(arg_s, str_reg);

    int n_reg = allocate_pinned_register();
    generate_asm(arg_n, n_reg);

    // Push in reverse: n, s -> after CALL: [BP+2]=s [BP+3]=n
    emit_asm("PUSH R%d             ; Arg 2: n\n", n_reg);
    unlock_pinned_register(n_reg);
    emit_asm("PUSH R%d             ; Arg 1: string\n", str_reg);
    unlock_pinned_register(str_reg);

    emit_asm("CALL __builtin_string_rep\n");
    emit_asm("IADD SP, 2           ; Clean up 2 arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }
    return true;
}

// string.reverse(s)
bool emit_string_reverse_intrinsic(ASTNode *node, int dest_reg) {
    ASTNode *arg = node->as.call.args_head;
    if (!arg) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "string.reverse() requires 1 argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: string.reverse(s) ---\n");

    int str_reg = allocate_pinned_register();
    generate_asm(arg, str_reg);

    emit_asm("PUSH R%d             ; Arg 1: string\n", str_reg);
    emit_asm("CALL __builtin_string_reverse\n");
    emit_asm("IADD SP, 1           ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }

    unlock_pinned_register(str_reg);
    return true;
}

// string.find(s, pattern) -- PLAIN SUBSTRING SEARCH ONLY.
//
// Real Lua's string.find(s, pattern [, init [, plain]]) interprets
// `pattern` as a Lua pattern (magic characters like %a, *, ^, $, etc.)
// unless the 4th `plain` argument is truthy, and returns TWO values
// (start, end) plus any captures. This implementation always behaves as
// if plain=true and pattern has no magic characters, doesn't support
// `init`, and only returns the start index as a single value (no end
// index, no captures). Full pattern support (needed for a correct find,
// match, and gmatch) is deliberately out of scope here -- see
// AUDIT_string_functionality.md and 13_string_match_gmatch.lua.
bool emit_string_find_intrinsic(ASTNode *node, int dest_reg) {
    ASTNode *arg_s = node->as.call.args_head;
    if (!arg_s || !arg_s->next) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "string.find() requires at least 2 arguments (s, pattern)");
        return false;
    }
    ASTNode *arg_pat = arg_s->next;

    emit_asm("    ;; --- Intrinsic: string.find(s, pattern) [plain substring only] ---\n");

    int str_reg = allocate_pinned_register();
    generate_asm(arg_s, str_reg);

    int pat_reg = allocate_pinned_register();
    generate_asm(arg_pat, pat_reg);

    // Push in reverse: pattern, s -> after CALL: [BP+2]=s [BP+3]=pattern
    emit_asm("PUSH R%d             ; Arg 2: pattern (plain substring)\n", pat_reg);
    unlock_pinned_register(pat_reg);
    emit_asm("PUSH R%d             ; Arg 1: string\n", str_reg);
    unlock_pinned_register(str_reg);

    emit_asm("CALL __builtin_string_find\n");
    emit_asm("IADD SP, 2           ; Clean up 2 arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }
    return true;
}

// string.gsub(s, pattern, repl) -- PLAIN SUBSTITUTION ONLY.
//
// Same plain-substring limitation as string.find() above: `pattern` is
// always treated as a literal substring, never a Lua pattern. Real Lua's
// gsub also accepts an optional 4th `n` argument capping the number of
// replacements, and returns TWO values (result, count) -- neither is
// supported here; this always replaces every non-overlapping occurrence
// and returns only the resulting string.
bool emit_string_gsub_intrinsic(ASTNode *node, int dest_reg) {
    ASTNode *arg_s = node->as.call.args_head;
    if (!arg_s || !arg_s->next || !arg_s->next->next) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "string.gsub() requires 3 arguments (s, pattern, repl)");
        return false;
    }
    ASTNode *arg_pat  = arg_s->next;
    ASTNode *arg_repl = arg_pat->next;

    emit_asm("    ;; --- Intrinsic: string.gsub(s, pattern, repl) [plain substitution only] ---\n");

    int str_reg = allocate_pinned_register();
    generate_asm(arg_s, str_reg);

    int pat_reg = allocate_pinned_register();
    generate_asm(arg_pat, pat_reg);

    int repl_reg = allocate_pinned_register();
    generate_asm(arg_repl, repl_reg);

    // Push in reverse: repl, pattern, s -> after CALL: [BP+2]=s [BP+3]=pattern [BP+4]=repl
    emit_asm("PUSH R%d             ; Arg 3: repl\n", repl_reg);
    unlock_pinned_register(repl_reg);
    emit_asm("PUSH R%d             ; Arg 2: pattern (plain substring)\n", pat_reg);
    unlock_pinned_register(pat_reg);
    emit_asm("PUSH R%d             ; Arg 1: string\n", str_reg);
    unlock_pinned_register(str_reg);

    emit_asm("CALL __builtin_string_gsub\n");
    emit_asm("IADD SP, 3           ; Clean up 3 arguments\n");

    if (dest_reg != 0) {
        emit_asm("MOV R%d, R0         ; Store result\n", dest_reg);
    }
    return true;
}
