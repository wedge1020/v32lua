#include "v32lua.h"

// ============================================================================
// Shared argument pusher for the string runtime routines, which all take
// their FIRST argument at [BP+2], second at [BP+3], ...
//
// Every multi-argument string intrinsic used to evaluate its arguments into
// registers one after another and only then push them. Pinning a register
// does not protect it from a raw hardware CALL, so any later argument that
// itself CALLs (#s, f(), a .. b, ...) could clobber an earlier one:
// string.sub(s, 2, #s) returned "" because __builtin_len wiped s's register
// (7 of 9 cases in the audit's differential test were wrong).
//
// Now: evaluate strictly left to right, PUSH each value as soon as it is
// computed, NIL-pad up to `slots`, optionally append a NIL terminator, then
// reverse the whole block in place so the first argument ends up at the
// lowest address ([BP+2] in the callee) -- the technique
// emit_string_format_intrinsic() already used.
// Returns the number of words pushed (for the caller's IADD SP, n).
// ============================================================================
static int push_string_args (ASTNode *first, int slots, bool nil_terminator)
{
    ASTNode *a = first;
    int pushed = 0;
    for (int i = 0; i < slots || (slots < 0 && a != NULL); i++) {
        int reg = allocate_register ();
        if (a != NULL) {
            generate_asm (a, reg);
            ensure_in_register (reg);
            a = a->next;
        } else {
            emit_asm ("MOV R%d, BOXED_NIL ; absent optional argument\n", reg);
        }
        emit_asm ("PUSH R%d ; string arg %d\n", reg, i + 1);
        unlock_register (reg);
        pushed++;
    }
    if (nil_terminator) {
        emit_asm ("MOV R0, BOXED_NIL\n");
        emit_asm ("PUSH R0 ; BOXED_NIL terminator\n");
        pushed++;
    }
    if (pushed > 1) {
        int ra = allocate_register ();
        lock_register (ra);
        int rb = allocate_register ();
        for (int i = 0; i < pushed / 2; i++) {
            int j = pushed - 1 - i;
            emit_asm ("MOV R%d, [SP+%d]\n", ra, i);
            emit_asm ("MOV R%d, [SP+%d]\n", rb, j);
            emit_asm ("MOV [SP+%d], R%d\n", i, rb);
            emit_asm ("MOV [SP+%d], R%d\n", j, ra);
        }
        unlock_register (rb);
        unlock_register (ra);
    }
    return pushed;
}

static void call_string_routine (const char *routine, int pushed, int dest_reg)
{
    emit_asm ("CALL %s\n", routine);
    emit_asm ("IADD SP, %d ; Clean up arguments\n", pushed);
    if (dest_reg != 0) {
        emit_asm ("MOV R%d, R0 ; Store result\n", dest_reg);
    }
}

bool emit_string_byte_intrinsic(ASTNode *node, int dest_reg) {
    if (!node->as.call.args_head) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "string.byte() requires at least 1 argument");
        return false;
    }
    emit_asm("    ;; --- Intrinsic: string.byte(s [, i [, j]]) ---\n");
    // [BP+2] = string, [BP+3] = start (nil ok), [BP+4] = end (nil ok)
    int n = push_string_args(node->as.call.args_head, 3, false);
    call_string_routine("__builtin_string_byte", n, dest_reg);
    return true;
}

bool emit_string_char_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- Intrinsic: string.char(b1, b2, ..., bn) ---\n");
    // [BP+2] = first byte ... [BP+2+N] = BOXED_NIL terminator
    int n = push_string_args(node->as.call.args_head, -1, true);
    call_string_routine("__builtin_string_char", n, dest_reg);
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
    emit_asm("    ;; --- Intrinsic: string.sub(s, i [, j]) ---\n");
    // [BP+2] = s, [BP+3] = i, [BP+4] = j (nil -> end of string)
    int n = push_string_args(arg_s, 3, false);
    call_string_routine("__builtin_string_sub", n, dest_reg);
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
    emit_asm("    ;; --- Intrinsic: string.rep(s, n) ---\n");
    int n = push_string_args(arg_s, 2, false);
    call_string_routine("__builtin_string_rep", n, dest_reg);
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
    emit_asm("    ;; --- Intrinsic: string.find(s, pattern) [plain substring only] ---\n");
    int n = push_string_args(arg_s, 2, false);
    call_string_routine("__builtin_string_find", n, dest_reg);
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
    emit_asm("    ;; --- Intrinsic: string.gsub(s, pattern, repl) [plain substitution only] ---\n");
    int n = push_string_args(arg_s, 3, false);
    call_string_routine("__builtin_string_gsub", n, dest_reg);
    return true;
}

// ============================================================================
// tonumber(v) - Converts v to a number, or returns nil if it can't be.
// Already-a-number input is returned unchanged. String input is parsed
// against the SAME numeric-literal grammar the lexer itself accepts
// (decimal with optional fraction, leading-dot decimal, 0x/0X hex
// integer) -- nothing more. No exponent notation (matches the lexer),
// no explicit-base second argument (a separate, deferred feature).
// ============================================================================
bool emit_tonumber_intrinsic(ASTNode *node, int dest_reg) {
    ASTNode *arg = node->as.call.args_head;
    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "tonumber() expects exactly 1 argument (explicit-base form not yet supported)");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: tonumber(value) ---\n");

    int arg_reg = allocate_pinned_register();
    generate_asm(arg, arg_reg);

    emit_asm("    PUSH R%d             ; Arg 1: Value to convert\n", arg_reg);
    emit_asm("    CALL __builtin_string_to_number\n");
    emit_asm("    IADD SP, 1           ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0         ; Store number result (or nil)\n", dest_reg);
    }

    unlock_pinned_register(arg_reg);
    return true;
}
