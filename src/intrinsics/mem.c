#include "v32lua.h"

// ============================================================================
// intrinsics_vircon32_memcard.c
//
// Native Vircon32 persistent memory card: memcard.load()/save()/title()/
// load_table(), plus memcard[position] as bracket-index sugar for
// load/save.
//
//   memcard.save(value, position)   -> value   (raw write, exactly 1 word)
//   memcard.save(value)             -> value   (auto-append; see below)
//   memcard.load(position)          -> value   (raw read, exactly 1 word)
//   memcard.load()                  -> value   (position 0, unchanged)
//   memcard.load_table(position)    -> table or nil  (see below)
//   memcard.title(str)              -> nil     (sets the 16-word title)
//   memcard[position]                  == memcard.load(position)
//   memcard[position] = value          == memcard.save(value, position)
//
// ADDRESSING: this VM is word-addressed throughout -- "[Rd+N]" always
// steps by whole words per unit of N, the same convention __builtin_
// vircon32_btnp's prev-state table uses (see vircon32.s). POSITION follows
// that convention too: position 0 is VIRCON32_MEMCARD_DATA_BASE (the first
// word past the 20-word title block), each +1 is the next word, and
// -1..-20 reach back into the title/metadata region -- reachable, but only
// by consciously going negative.
//
// TWO DIFFERENT SAVE FORMS, on purpose:
//
// - memcard.save(value, position) / memcard[position] = value -- the
//   low-level primitive. Writes exactly the raw boxed VALUE to exactly one
//   word, no tag, no bookkeeping. Same address either time you write the
//   same position; you are fully responsible for knowing what you put
//   where. This is what memcard[pos] always compiles to.
//
// - memcard.save(value) -- no position -- auto-appends through a
//   PERSISTENT ON-CARD cursor stored at VIRCON32_MEMCARD_CURSOR_ADDR (the
//   memcard's own last title word, NOT Vircon32 RAM, so it survives a
//   reboot: repeated no-position saves keep extending a log instead of
//   overwriting position 0 every run). This form is type-aware:
//     - a real Lua string is written as [TAG_STRING][length][char words...]
//     - a TABLE is written as [TAG_TABLE][pair_count][k1][v1]...[kN][vN]
//       -- see "TABLES" below
//     - everything else (number/boolean/nil/function) is written as
//       [TAG_SCALAR][raw value]
//   Entirely handled by __builtin_vircon32_memcard_append in vircon32.s;
//   see that routine for the exact tag layout. The cursor itself is
//   readable at any time as memcard.load(-1) / memcard[-1] -- no separate
//   "how much have I saved" accessor was added, since that position
//   already does the job.
//
// memcard.load()/memcard.load(position) do NOT understand the
// [tag][...] layout the auto-append form writes -- both always do a raw
// single-word read, same as before. Reading back a scalar or string entry
// means reading its tag word yourself (memcard.load(N)) and branching on
// it, or simply knowing what you wrote there. Tying memcard.load()'s
// no-position case to "read the next tagged entry" was considered and
// deliberately left out of this pass -- flagged for confirmation before
// building it, since it's a real design fork (sequential-read cursor vs.
// today's fixed "position 0" default) rather than a small addition.
//
// TABLES: memcard.save(a_table) (the no-position auto-append form ONLY --
// memcard.save(a_table, position) still writes a single raw pointer word,
// same as any other scalar) writes a RAW DUMP of the table's hash-bucket
// storage: [TAG_TABLE][pair_count][key][value]... one pair per stored
// entry, walking every bucket in the chain. This is the "dump a struct to
// a file" approach, not a general recursive serializer -- a key or value
// that is itself a table/string/function is written as its raw pointer,
// one level only, with the same within-this-run-only caveat as everything
// else here (see the safety note below). Nothing about the array part is
// involved: this compiler's array-part fast path is currently unreachable
// in practice (see __builtin_table_set_reallocate's TODO in vircon32.s --
// capacity is always 0), so EVERY table, array-shaped or not, already
// lives entirely in the hash-bucket chain this walks. There is no
// "simpler" array case to special-case today.
//
// memcard.load_table(position) is the matching reconstruction: validates
// the tag, then rebuilds a fresh table via __builtin_table_new plus one
// __builtin_table_set per stored pair. POSITION is required -- there's no
// sensible "position 0" default for something whose size in words isn't
// known until the entry itself is read. Returns nil if the tag at
// POSITION isn't TAG_TABLE, rather than misinterpreting unrelated data as
// a pair count and garbage keys/values.
//
// SAFETY NOTE this compiler does NOT enforce: a number, boolean, or nil
// round-trips correctly forever -- that bit pattern means the same thing
// on any run. A real Lua string or table saved through the auto-append
// form (memcard.save(value) with no position) round-trips correctly too --
// a string's actual characters are copied, and a table's actual key/value
// PAIRS are copied, restorable with memcard.load_table(). A table, string
// (when raw-saved via the explicit-position form, bypassing the auto-
// append form's real handling), or function value -- including any such
// value found as a KEY or VALUE inside a saved table, since those are not
// recursively unpacked -- round-trips fine WITHIN the same run (its
// pointer is still valid) but is meaningless after a fresh boot reads it
// back from a real memcard, since heap/ROM layout is not guaranteed to
// match between runs. Stick to numbers/booleans/nil (or real strings/
// tables of such, via the auto-append form) for anything meant to survive
// a save/reload.
// ============================================================================

// Clamps the hardware address already sitting in `addr_reg` to
// [VIRCON32_MEMCARD_BASE, VIRCON32_MEMCARD_END], in place. Shared by the
// dynamic-position paths of save/load below -- a position computed at
// runtime (not a compile-time literal) needs this since it can't be range-
// checked ahead of time the way a literal position can.
void emit_vircon32_memcard_clamp_addr (int addr_reg)
{
    int         lbl = get_next_label();
    const char *ctx = get_current_function_name();

    char lo_ok[192], hi_ok[192];
    snprintf(lo_ok, sizeof(lo_ok), "__%s_memcard_addr_lo_ok_%d", ctx, lbl);
    snprintf(hi_ok, sizeof(hi_ok), "__%s_memcard_addr_hi_ok_%d", ctx, lbl);

    int scratch = allocate_register();

    emit_asm("MOV  R%d, R%d", scratch, addr_reg);
    emit_asm("ILT  R%d, VIRCON32_MEMCARD_BASE", scratch);
    emit_asm("JF   R%d, %s", scratch, lo_ok);
    emit_asm("MOV  R%d, VIRCON32_MEMCARD_BASE ; clamp low", addr_reg);
    emit_asm("%s:", lo_ok);

    emit_asm("MOV  R%d, R%d", scratch, addr_reg);
    emit_asm("IGT  R%d, VIRCON32_MEMCARD_END", scratch);
    emit_asm("JF   R%d, %s", scratch, hi_ok);
    emit_asm("MOV  R%d, VIRCON32_MEMCARD_END ; clamp high", addr_reg);
    emit_asm("%s:", hi_ok);

    unlock_register(scratch);
}

// ============================================================================
// Shared write: memcard.save(VALUE [, POSITION]) and memcard[POS] = VALUE
// both funnel through here. Returns VALUE in dest_reg (if dest_reg != 0),
// matching the "returns what you gave/used" convention play()/sfx.play()
// established elsewhere in this file. pos_node == NULL means "no position
// argument at all" -- auto-append, NOT position 0 (see the header comment
// block above).
// ============================================================================
bool emit_vircon32_memcard_write (ASTNode *val_node, ASTNode *pos_node, int dest_reg, int line_number)
{
    if (val_node == NULL) {
        compiler_error(ERR_SEMANTIC, line_number,
                       "memcard.save() requires a value argument: memcard.save(value [, position])");
        return false;
    }

    runtime_req.needs_vircon32 = true;

    // ------------------------------------------------------------------
    // NO POSITION AT ALL: auto-append via the persistent on-card cursor
    // (VIRCON32_MEMCARD_CURSOR_ADDR, the last title word). Always a CALL
    // -- the cursor is a runtime, cross-session quantity, never known at
    // compile time, and __builtin_vircon32_memcard_append also handles
    // string values (tagged, length-prefixed) so this is the one save
    // path that isn't limited to a single raw word. Only reachable via
    // memcard.save(value) -- memcard[pos] = value always has an explicit
    // pos_node, since Lua's bracket syntax has no "no index" form.
    // ------------------------------------------------------------------
    if (pos_node == NULL) {
        emit_asm("    ;; --- Vircon32 memcard.save() Intrinsic (auto-append) ---");

        int val_reg = allocate_register();
        generate_asm(val_node, val_reg);
        emit_asm("PUSH R%d ; Arg 1: value", val_reg);
        unlock_register(val_reg);

        emit_asm("CALL __builtin_vircon32_memcard_append");
        emit_asm("IADD SP, 1 ; Clean up memcard.save() arguments");

        if (dest_reg != 0) {
            emit_asm("MOV  R%d, R0 ; memcard.save() returns the value", dest_reg);
        }
        return true;
    }

    // ------------------------------------------------------------------
    // EXPLICIT POSITION: unchanged raw single-word semantics -- exactly
    // one word written at VIRCON32_MEMCARD_DATA_BASE + position, no type
    // tag, no cursor involvement. This is the low-level direct-addressing
    // form; memcard[pos] = value always lands here.
    // ------------------------------------------------------------------
    double pos_val = 0;
    bool   pos_literal = spu_static_number(pos_node, &pos_val);

    // ------------------------------------------------------------------
    // STATIC PATH: position known at compile time -- the address is a
    // plain constant, staged into a register with one MOV, no runtime
    // arithmetic or clamping needed.
    // ------------------------------------------------------------------
    if (pos_literal) {
        long address = (long) VIRCON32_MEMCARD_DATA_BASE + (long) pos_val;
        if (pos_val != (double) (long) pos_val ||
            address < VIRCON32_MEMCARD_BASE || address > VIRCON32_MEMCARD_END) {
            compiler_error(ERR_SEMANTIC, line_number,
                           "memcard position must be a whole number in %d..%ld (got %g)",
                           -VIRCON32_MEMCARD_TITLE_WORDS,
                           (long) (VIRCON32_MEMCARD_END - VIRCON32_MEMCARD_DATA_BASE), pos_val);
            return false;
        }

        int val_reg = allocate_register();
        register_pinned[val_reg] = 1;
        generate_asm(val_node, val_reg);

        int addr_reg = allocate_register();
        emit_asm("    ;; --- Vircon32 memcard.save() Intrinsic (static fold) ---");
        emit_asm("MOV  R%d, 0x%lX ; memcard address", addr_reg, address);
        emit_asm("MOV  [R%d], R%d ; memcard write", addr_reg, val_reg);
        unlock_register(addr_reg);

        if (dest_reg != 0 && dest_reg != val_reg) {
            emit_asm("MOV  R%d, R%d ; memcard.save() returns the value", dest_reg, val_reg);
        }
        register_pinned[val_reg] = 0;
        unlock_register(val_reg);
        return true;
    }

    // ------------------------------------------------------------------
    // DYNAMIC PATH: position is a runtime expression. Computing and
    // clamping the address is cheap (a handful of instructions), so this
    // is inlined rather than sent through a CALL.
    // ------------------------------------------------------------------
    emit_asm("    ;; --- Vircon32 memcard.save() Intrinsic ---");

    int val_reg = allocate_register();
    register_pinned[val_reg] = 1;
    generate_asm(val_node, val_reg);

    int addr_reg = allocate_register();
    register_pinned[addr_reg] = 1;
    generate_asm(pos_node, addr_reg);
    emit_asm("CFI  R%d ; Lua float position -> hardware integer", addr_reg);
    emit_asm("IADD R%d, VIRCON32_MEMCARD_DATA_BASE", addr_reg);

    emit_vircon32_memcard_clamp_addr(addr_reg);

    emit_asm("MOV  [R%d], R%d ; memcard write", addr_reg, val_reg);
    register_pinned[addr_reg] = 0;
    unlock_register(addr_reg);

    if (dest_reg != 0 && dest_reg != val_reg) {
        emit_asm("MOV  R%d, R%d ; memcard.save() returns the value", dest_reg, val_reg);
    }
    register_pinned[val_reg] = 0;
    unlock_register(val_reg);
    return true;
}

// ============================================================================
// Shared read: memcard.load([POSITION]) and memcard[POS] both funnel
// through here. pos_node == NULL means "position 0" -- UNLIKE save(),
// load()'s no-position default was deliberately left unchanged rather
// than tied to the auto-append cursor; see the header comment block
// above. dest_reg == 0 means the result is discarded (a memcard read has
// no side effect worth keeping on its own, so nothing is emitted then).
// ============================================================================
bool emit_vircon32_memcard_read (ASTNode *pos_node, int dest_reg, int line_number)
{
    runtime_req.needs_vircon32 = true;

    double pos_val = 0;
    bool   pos_literal = (pos_node == NULL) || spu_static_number(pos_node, &pos_val);

    if (pos_literal) {
        long address = (long) VIRCON32_MEMCARD_DATA_BASE + (long) pos_val;
        if (pos_val != (double) (long) pos_val ||
            address < VIRCON32_MEMCARD_BASE || address > VIRCON32_MEMCARD_END) {
            compiler_error(ERR_SEMANTIC, line_number,
                           "memcard position must be a whole number in %d..%ld (got %g)",
                           -VIRCON32_MEMCARD_TITLE_WORDS,
                           (long) (VIRCON32_MEMCARD_END - VIRCON32_MEMCARD_DATA_BASE), pos_val);
            return false;
        }

        if (dest_reg == 0) {
            return true;
        }

        int addr_reg = allocate_register();
        emit_asm("    ;; --- Vircon32 memcard.load() Intrinsic (static fold) ---");
        emit_asm("MOV  R%d, 0x%lX ; memcard address", addr_reg, address);
        emit_asm("MOV  R%d, [R%d] ; memcard read", dest_reg, addr_reg);
        unlock_register(addr_reg);
        return true;
    }

    if (dest_reg == 0) {
        return true;
    }

    emit_asm("    ;; --- Vircon32 memcard.load() Intrinsic ---");

    int addr_reg = allocate_register();
    generate_asm(pos_node, addr_reg);
    emit_asm("CFI  R%d ; Lua float position -> hardware integer", addr_reg);
    emit_asm("IADD R%d, VIRCON32_MEMCARD_DATA_BASE", addr_reg);

    emit_vircon32_memcard_clamp_addr(addr_reg);

    emit_asm("MOV  R%d, [R%d] ; memcard read", dest_reg, addr_reg);
    unlock_register(addr_reg);
    return true;
}

// ============================================================================
// memcard.save(VALUE [, POSITION]) -> VALUE     (dotted-call form)
// ============================================================================
bool emit_vircon32_memcard_save_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg_val = node->as.call.args_head;
    ASTNode *arg_pos = (arg_val != NULL) ? arg_val->next : NULL;

    if (arg_pos != NULL && arg_pos->next != NULL) {
        compiler_warning(ERR_SEMANTIC, node->line_number,
                         "memcard.save() takes at most 2 arguments (value, position); extra arguments ignored");
    }

    return emit_vircon32_memcard_write(arg_val, arg_pos, dest_reg, node->line_number);
}

// ============================================================================
// memcard.load([POSITION]) -> VALUE     (dotted-call form)
// ============================================================================
bool emit_vircon32_memcard_load_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg_pos = node->as.call.args_head;

    if (arg_pos != NULL && arg_pos->next != NULL) {
        compiler_warning(ERR_SEMANTIC, node->line_number,
                         "memcard.load() takes at most 1 argument (position); extra arguments ignored");
    }

    return emit_vircon32_memcard_read(arg_pos, dest_reg, node->line_number);
}

// ============================================================================
// memcard.load_table(POSITION) -> table or nil
//
// Reconstructs a table previously written by memcard.save(a_table) -- the
// no-position auto-append form is the ONLY save path that ever produces a
// TAG_TABLE entry; memcard.save(a_table, position) (explicit position)
// always writes a single raw pointer word instead, same as any other
// scalar (see the safety note in the header comment block above).
//
// POSITION is REQUIRED, unlike memcard.load(). There's no sensible
// "position 0" default for something that consumes a variable number of
// words depending on what's stored there -- unlike a scalar/string read,
// this can't be answered without first reading the entry itself.
//
// This is a RAW DUMP restore, not a general deserializer: it walks
// __builtin_vircon32_memcard_load_table's [TAG_TABLE][pair_count][k][v]...
// layout (see vircon32.s) and rebuilds a table via __builtin_table_new +
// repeated __builtin_table_set calls, one per pair. Each restored key/
// value is used exactly as stored -- a nested table/string/function
// pointer is restored as a pointer, not recursively reconstructed, with
// the same within-this-run-only caveat as everywhere else in this file.
//
// Validates the tag word at POSITION before trusting anything after it;
// if it isn't TAG_TABLE, returns nil rather than misreading unrelated
// data as pair count and garbage keys/values.
// ============================================================================
bool emit_vircon32_memcard_load_table_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg_pos = node->as.call.args_head;

    if (arg_pos == NULL) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                       "memcard.load_table() requires a position argument: memcard.load_table(position)");
        return false;
    }
    if (arg_pos->next != NULL) {
        compiler_warning(ERR_SEMANTIC, node->line_number,
                         "memcard.load_table() takes exactly 1 argument; extra arguments ignored");
    }

    runtime_req.needs_vircon32 = true;
    runtime_req.needs_tables   = true;   // reconstructing a table needs the table runtime linked in

    emit_asm("    ;; --- Vircon32 memcard.load_table() Intrinsic ---");

    int pos_reg = allocate_register();
    generate_asm(arg_pos, pos_reg);
    emit_asm("PUSH R%d ; Arg 1: position", pos_reg);
    unlock_register(pos_reg);

    emit_asm("CALL __builtin_vircon32_memcard_load_table");
    emit_asm("IADD SP, 1 ; Clean up memcard.load_table() arguments");

    if (dest_reg != 0) {
        emit_asm("MOV  R%d, R0 ; memcard.load_table() returns the reconstructed table (or nil)", dest_reg);
    }

    return true;
}

// ============================================================================
// memcard.title(STR) -> nil
//
// Writes STR's characters into the memcard's title region, one word per
// character -- matching this VM's own internal string representation, NOT
// a packed byte string. Only the first VIRCON32_MEMCARD_TITLE_DISPLAY_WORDS
// (16) of the 20-word title block are available for this -- the last 4
// are reserved (word -1 is the auto-append cursor; see
// VIRCON32_MEMCARD_CURSOR_ADDR in v32lua.h). Truncated to 16 characters if
// longer; padded with 0-words if shorter, and the reserved words are never
// touched. Always a CALL: STR's length isn't known at compile time unless
// it's a literal, and even then sharing the runtime copy loop is simpler
// than unrolling it per call site.
// ============================================================================
bool emit_vircon32_memcard_title_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *arg_str = node->as.call.args_head;

    if (arg_str == NULL) {
        compiler_error(ERR_SEMANTIC, node->line_number,
                       "memcard.title() requires a string argument: memcard.title(\"...\")");
        return false;
    }
    if (arg_str->next != NULL) {
        compiler_warning(ERR_SEMANTIC, node->line_number,
                         "memcard.title() takes exactly 1 argument; extra arguments ignored");
    }

    if (arg_str->type == NODE_STRING &&
        (int) strlen(arg_str->as.string_val.value) > VIRCON32_MEMCARD_TITLE_DISPLAY_WORDS) {
        compiler_warning(ERR_SEMANTIC, node->line_number,
                         "memcard.title(): \"%s\" is longer than %d characters and will be truncated",
                         arg_str->as.string_val.value, VIRCON32_MEMCARD_TITLE_DISPLAY_WORDS);
    }

    runtime_req.needs_vircon32 = true;

    emit_asm("    ;; --- Vircon32 memcard.title() Intrinsic ---");

    int str_reg = allocate_register();
    generate_asm(arg_str, str_reg);
    emit_asm("PUSH R%d ; Arg 1: title string", str_reg);
    unlock_register(str_reg);

    emit_asm("CALL __builtin_vircon32_memcard_title");
    emit_asm("IADD SP, 1 ; Clean up memcard.title() arguments");

    if (dest_reg != 0) {
        emit_asm("MOV  R%d, BOXED_NIL ; return nil", dest_reg);
    }

    return true;
}

// ============================================================================
// Dispatch for the memcard.* surface. Called from try_emit_call_intrinsic()
// once func_name has been resolved. Returns 1 if handled.
// ============================================================================
int try_emit_memcard_namespace_intrinsic (ASTNode *node, int dest_reg, const char *func_name)
{
    // Native Vircon32 only. PICO-8 has dget()/dset(), TIC-80 has pmem() --
    // and TIC-80's pmem() already claims the raw MEMCARD address range
    // directly (see __builtin_tic80_pmem in vircon32.s), with no title
    // offset. Letting memcard.* run alongside either would let a program
    // silently corrupt that data (memcard.save() at a small position
    // overlaps pmem()'s low addresses).
    if (runtime_req.needs_pico8 || runtime_req.needs_tic80) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "'%s' is the native Vircon32 memory card API and is not available under "
            "the pico8/tic80 API modes", func_name);
        return 0;
    }

    if (strcmp(func_name, "memcard.load")  == 0) return emit_vircon32_memcard_load_intrinsic(node, dest_reg);
    if (strcmp(func_name, "memcard.save")  == 0) return emit_vircon32_memcard_save_intrinsic(node, dest_reg);
    if (strcmp(func_name, "memcard.title") == 0) return emit_vircon32_memcard_title_intrinsic(node, dest_reg);
    if (strcmp(func_name, "memcard.load_table") == 0) return emit_vircon32_memcard_load_table_intrinsic(node, dest_reg);

    // Same reasoning as the sound API's equivalent fallback: an
    // unrecognized dotted call otherwise skips the "Undeclared function"
    // check and miscompiles into a dynamic lookup against a table that
    // does not exist.
    compiler_error(ERR_SEMANTIC, node->line_number,
        "Unknown memcard function '%s'", func_name);
    return 0;
}
