#include "v32lua.h"

// ============================================================================
// PICO-8 memory and time intrinsics
// ----------------------------------------------------------------------------
// peek/peek2/peek4, poke/poke2/poke4, memcpy, memset, reload, cstore,
// sget/sset, cartdata/dget/dset on the emulated 64 KB RAM (see the memory
// section of runtime/pico8.s), and time()/t().
//
// The first memory function a program uses sets pico8_uses_memory, which
// makes pico8_assets.c put the cart's sprite sheet and sound data in ROM
// in PICO-8's memory layout (what peek() and reload() read).
// ============================================================================
bool pico8_uses_memory = false;

// Pushes `count` call arguments right to left. A missing argument is
// fills[i] (a literal operand, e.g. "0.0" or "BOXED_NIL"); fills may be
// NULL, meaning nil for every missing one.
static void push_args (ASTNode *node, int count, const char *const *fills)
{
    ASTNode *args[8] = { NULL };
    int n = 0;
    for (ASTNode *a = node->as.call.args_head; a != NULL && n < 8; a = a->next) args[n++] = a;

    for (int i = count - 1; i >= 0; i--) {
        int reg = allocate_register ();
        register_pinned[reg] = 1;
        if (i < n && args[i] != NULL) {
            generate_asm (args[i], reg);
            ensure_in_register (reg);
        } else {
            emit_asm ("MOV R%d, %s\n", reg, (fills && fills[i]) ? fills[i] : "BOXED_NIL");
        }
        emit_asm ("PUSH R%d ; arg %d\n", reg, i + 1);
        register_pinned[reg] = 0;
        unlock_register (reg);
    }
}

// Pushes a raw integer (not a Lua value).
static void push_int (int value, const char *what)
{
    int reg = allocate_register ();
    emit_asm ("MOV R%d, %d\n", reg, value);
    emit_asm ("PUSH R%d ; %s\n", reg, what);
    unlock_register (reg);
}

static int count_args (ASTNode *node)
{
    int n = 0;
    for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next) n++;
    return n;
}

// Evaluates every argument for its side effects only.
static void discard_args (ASTNode *node)
{
    for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next) {
        if (a->type == NODE_NUMBER || a->type == NODE_STRING || a->type == NODE_IDENTIFIER) continue;
        int reg = allocate_register ();
        generate_asm (a, reg);
        unlock_register (reg);
    }
}

static void finish_call (const char *routine, int pushed, int dest_reg)
{
    emit_asm ("CALL %s\n", routine);
    if (pushed > 0) emit_asm ("IADD SP, %d\n", pushed);
    if (dest_reg != 0) emit_asm ("MOV R%d, R0\n", dest_reg);
}

// FNV-1a of a cartdata() id, never 0 (a blank memory card reads 0).
static uint32_t cartdata_hash (const char *s)
{
    uint32_t h = 2166136261u;
    for (; *s; s++) { h ^= (uint8_t) *s; h *= 16777619u; }
    return h | 1u;
}

// peek(a, n) / peek2(a, n) / peek4(a, n) -- several values -- become
// __p8_peekn(a, n, width) (pico8_prelude.c) as they are parsed: a call's
// value count is settled before code generation, so the renaming cannot
// wait until then. Only when the prelude provides the helper, i.e. the
// program doesn't define that peek itself.
void pico8_parse_rewrite_peek (ASTNode *call)
{
    if (call->as.call.target == NULL || call->as.call.target->type != NODE_IDENTIFIER) return;
    const char *name = call->as.call.target->as.id.name;
    int width = 0;
    if      (strcmp (name, "peek")  == 0) width = 1;
    else if (strcmp (name, "peek2") == 0) width = 2;
    else if (strcmp (name, "peek4") == 0) width = 4;
    if (width == 0 || !pico8_prelude_builtin (name)) return;

    ASTNode *second = call->as.call.args_head ? call->as.call.args_head->next : NULL;
    if (second == NULL) return;
    if (second->type == NODE_NUMBER && second->as.number.val == 1.0 && second->next == NULL) return;
    second->next = NULL;
    ASTNode *w = make_node (NODE_NUMBER);
    w->as.number.val = width;
    second->next = w;
    call->as.call.target = make_node_ident ("__p8_peekn");
}

// Returns true if the call was emitted. peek(a, n) -- several values -- is
// not emitted here: the call is redirected to the prelude's __p8_peekn()
// and false is returned, so it is compiled as an ordinary call.
bool emit_pico8_memory_intrinsic (ASTNode *node, const char *func_name, int dest_reg)
{
    int argc = count_args (node);
    int width = 0;

    if      (strcmp (func_name, "peek")  == 0) width = 1;
    else if (strcmp (func_name, "peek2") == 0) width = 2;
    else if (strcmp (func_name, "peek4") == 0) width = 4;
    if (width != 0) {
        pico8_uses_memory = true;
        ASTNode *second = node->as.call.args_head ? node->as.call.args_head->next : NULL;
        bool single = (second == NULL) ||
                      (second->type == NODE_NUMBER && second->as.number.val == 1.0 && second->next == NULL);
        if (!single) {
            // peek(a, n): n values -> __p8_peekn(a, n, width)
            second->next = NULL;
            ASTNode *w = make_node (NODE_NUMBER);
            w->as.number.val = width;
            second->next = w;
            node->as.call.target = make_node_ident ("__p8_peekn");
            return false;
        }
        emit_asm ("    ;; --- PICO-8 %s() ---\n", func_name);
        push_args (node, 1, NULL);
        push_int (width, "width");
        finish_call ("__builtin_pico8_peek", 2, dest_reg);
        return true;
    }

    if      (strcmp (func_name, "poke")  == 0) width = 1;
    else if (strcmp (func_name, "poke2") == 0) width = 2;
    else if (strcmp (func_name, "poke4") == 0) width = 4;
    if (width != 0) {
        pico8_uses_memory = true;
        emit_asm ("    ;; --- PICO-8 %s() ---\n", func_name);
        // poke(a, v1, v2, ...): the values, right to left, then the address
        int values = argc > 1 ? argc - 1 : 1;
        ASTNode **args = malloc (sizeof (ASTNode *) * (size_t) (argc > 0 ? argc : 1));
        if (args == NULL) {
            compiler_error (ERR_INTERNAL, node->line_number, "out of memory");
            return false;
        }
        int n = 0;
        for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next) args[n++] = a;
        for (int i = values; i >= 0; i--) {
            int reg = allocate_register ();
            register_pinned[reg] = 1;
            if (i < n) {
                generate_asm (args[i], reg);
                ensure_in_register (reg);
            } else {
                emit_asm ("MOV R%d, 0.0\n", reg);   // poke(a): writes 0
            }
            emit_asm ("PUSH R%d ; %s\n", reg, i == 0 ? "address" : "value");
            register_pinned[reg] = 0;
            unlock_register (reg);
        }
        free (args);
        push_int (values, "count");
        push_int (width, "width");
        finish_call ("__builtin_pico8_poke", values + 3, dest_reg);
        return true;
    }

    if (strcmp (func_name, "memcpy") == 0 || strcmp (func_name, "memset") == 0) {
        if (argc < 3) {
            compiler_error (ERR_SEMANTIC, node->line_number,
                            "%s() needs 3 arguments (dest, %s, length)", func_name,
                            func_name[3] == 'c' ? "src" : "value");
            return false;
        }
        pico8_uses_memory = true;
        emit_asm ("    ;; --- PICO-8 %s() ---\n", func_name);
        push_args (node, 3, NULL);
        finish_call (func_name[3] == 'c' ? "__builtin_pico8_memcpy" : "__builtin_pico8_memset",
                     3, dest_reg);
        return true;
    }

    if (strcmp (func_name, "reload") == 0) {
        emit_asm ("    ;; --- PICO-8 reload() ---\n");
        if (argc >= 4) {
            compiler_warning (ERR_SEMANTIC, node->line_number,
                "reload() from another cart file is not supported; the call does nothing");
            discard_args (node);
            if (dest_reg != 0) emit_asm ("MOV R%d, BOXED_NIL\n", dest_reg);
            return true;
        }
        if (argc == 0) {
            finish_call ("__builtin_pico8_reload_all", 0, dest_reg);
            return true;
        }
        // reload(dest [, src [, length]]): src 0, length 0x4300 by default
        static const char *const fills[3] = { "0.0", "0.0", "17152.0" };
        pico8_uses_memory = true;
        push_args (node, 3, fills);
        finish_call ("__builtin_pico8_reload_range", 3, dest_reg);
        return true;
    }

    if (strcmp (func_name, "cstore") == 0) {
        static bool warned = false;
        if (!warned) {
            compiler_warning (ERR_SEMANTIC, node->line_number,
                "cstore() cannot write to the cartridge on Vircon32; the call does nothing");
            warned = true;
        }
        discard_args (node);
        if (dest_reg != 0) emit_asm ("MOV R%d, BOXED_NIL\n", dest_reg);
        return true;
    }

    if (strcmp (func_name, "sget") == 0 || strcmp (func_name, "sset") == 0) {
        bool set = func_name[0] == 's' && func_name[1] == 's';
        pico8_uses_memory = true;
        emit_asm ("    ;; --- PICO-8 %s() ---\n", func_name);
        push_args (node, set ? 3 : 2, NULL);
        finish_call (set ? "__builtin_pico8_sset" : "__builtin_pico8_sget", set ? 3 : 2, dest_reg);
        return true;
    }

    if (strcmp (func_name, "cartdata") == 0) {
        uint32_t hash;
        ASTNode *id = node->as.call.args_head;
        if (id != NULL && id->type == NODE_STRING) {
            hash = cartdata_hash (id->as.string_val.value);
        } else {
            compiler_warning (ERR_SEMANTIC, node->line_number,
                "cartdata(): the id should be a string literal; saves from every "
                "non-literal id share one slot set");
            discard_args (node);
            hash = cartdata_hash ("");
        }
        pico8_uses_memory = true;
        emit_asm ("    ;; --- PICO-8 cartdata() ---\n");
        int reg = allocate_register ();
        emit_asm ("MOV R%d, 0x%08X\n", reg, hash);
        emit_asm ("PUSH R%d ; id hash\n", reg);
        unlock_register (reg);
        finish_call ("__builtin_pico8_cartdata", 1, dest_reg);
        return true;
    }

    if (strcmp (func_name, "dget") == 0 || strcmp (func_name, "dset") == 0) {
        bool set = func_name[1] == 's';
        pico8_uses_memory = true;
        emit_asm ("    ;; --- PICO-8 %s() ---\n", func_name);
        push_args (node, set ? 2 : 1, NULL);
        finish_call (set ? "__builtin_pico8_dset" : "__builtin_pico8_dget", set ? 2 : 1, dest_reg);
        return true;
    }

    return false;
}

// time() / t(): seconds since the cart started, counted in PICO-8 frames
// (30 per second, 60 with _update60), so it stands still while paused.
bool emit_pico8_time_intrinsic (ASTNode *node, int dest_reg)
{
    discard_args (node);
    if (dest_reg == 0) return true;
    emit_asm ("    ;; --- PICO-8 time() ---\n");
    emit_asm ("MOV R%d, [PICO8_TICKS]\n", dest_reg);
    emit_asm ("CIF R%d\n", dest_reg);
    emit_asm ("FDIV R%d, %d.0 ; PICO-8 frames per second\n", dest_reg,
              60 / (pico8_frame_step > 0 ? pico8_frame_step : 2));
    return true;
}
