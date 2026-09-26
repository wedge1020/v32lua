;; ===========================================================================
;; SECTION: TABLE OPERATIONS
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; Core Memory Allocator: Creates a new Table struct on the heap
;; Returns: R0 = Tagged Table Pointer (0x7F80....)
;; Register Usage: R1 (Callee-Saved for the CALLER's benefit -- separate from
;;                 the R2/R3/R6 save below, which only protects values across
;;                 the internal CALL __malloc)
;; ---------------------------------------------------------------------------
;; __table_key_streq (internal): R4 = stored key, R2 = search key
;;   -> R4 = 1 if BOTH are strings with equal contents, else 0.
;;   Preserves every other register.
;; Table keys used to be compared bitwise only, i.e. strings by ADDRESS:
;; t["ab"] = 1; t["a" .. "b"] read nil, and t["q" .. 1] = 5 twice created two
;; entries. Only literals worked, because equal literals share one ROM label.
;; Called only after the bitwise compare failed; the tag pre-check keeps
;; numeric / table / boolean keys off the slow path.
;; ---------------------------------------------------------------------------
__table_key_streq:
    PUSH R0
    MOV  R0, R2
    AND  R0, 0x7FC00000
    IEQ  R0, 0x7FC00000          ; search key string-tagged (ROM or RAM)?
    JF   R0, __table_key_streq_no
    MOV  R0, R4
    AND  R0, 0x7FC00000
    IEQ  R0, 0x7FC00000          ; stored key string-tagged?
    JF   R0, __table_key_streq_no
    ;; nil/false/true share the RAM-string tag with payload < 4
    MOV  R0, R2
    AND  R0, BOXED_PAYLOAD
    ILT  R0, 4
    JT   R0, __table_key_streq_no
    MOV  R0, R4
    AND  R0, BOXED_PAYLOAD
    ILT  R0, 4
    JT   R0, __table_key_streq_no

    ;; Inline char-by-char compare (one char per word, NUL-terminated). Most
    ;; mismatching keys differ in the first character, so this exits almost
    ;; immediately -- a full __builtin_eq per non-matching key made field
    ;; lookups in celeste's object tables ~40% slower overall.
    PUSH R1
    PUSH R2
    PUSH R3
    MOV  R0, R2
    CALL __unbox_string          ; R0 = address (uses R1)
    MOV  R2, R0
    MOV  R0, R4
    CALL __unbox_string
    MOV  R4, R0                  ; R4 = stored key address, R2 = search key address
__table_key_streq_loop:
    MOV  R0, [R2]
    MOV  R1, [R4]
    MOV  R3, R0
    IEQ  R3, R1
    JF   R3, __table_key_streq_diff
    IEQ  R0, 0                   ; both hit NUL together -> equal
    JT   R0, __table_key_streq_same
    IADD R2, 1
    IADD R4, 1
    JMP  __table_key_streq_loop
__table_key_streq_same:
    MOV  R4, 1
    JMP  __table_key_streq_out
__table_key_streq_diff:
    MOV  R4, 0
__table_key_streq_out:
    POP  R3
    POP  R2
    POP  R1
    POP  R0
    RET
__table_key_streq_no:
    MOV  R4, 0
    POP  R0
    RET

;; ---------------------------------------------------------------------------
__builtin_table_new:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: preserve R1 for the CALLER ---
    ;; R1 is an ordinary general-purpose register the compiler can hand out
    ;; for any live value, so a caller can easily have something live in R1
    ;; across a `{}` table-constructor call (e.g. an earlier argument already
    ;; evaluated into R1 before a later argument is a table literal). This
    ;; function uses R1 as scratch below for the OOM check / header init
    ;; without ever saving it -- silently destroying that caller value.
    PUSH R1

    ;; Save registers clobbered by __malloc
    PUSH  R2
    PUSH  R3
    PUSH  R6

    MOV  R0, 4
    PUSH R0
    CALL __malloc
    IADD SP, 1

    ;; Restore registers
    POP   R6
    POP   R3
    POP   R2

    MOV  R1, R0
    IEQ  R1, 0
    JT   R1, __oom_handler   ; Fatal path -- halts the CPU, never returns, so
                              ; no need to restore R1 before jumping here.

    ;; Initialize table header
    MOV  R1, 0
    MOV  [R0], R1            ; Word 0: flags = nil
    MOV  [R0+1], R1          ; Word 1: length = 0
    MOV  [R0+2], R1          ; Word 2: array pointer = null
    MOV  [R0+3], R1          ; Word 3: hash pointer = null

    OR   R0, BOXED_TABLE

    ;; --- Callee-Restore ---
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Table Read Indexer: t[k] -> Returns Value in R0 (or Nil if not found)
;; Incoming Stack: [BP+3] = Tagged Table Pointer, [BP+2] = Key
;; Register Usage: R1-R7 (Audited: reduced from 9 registers down to 7!)
;; ---------------------------------------------------------------------------
__builtin_table_get:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save (only R1-R5 are used here; helpers save their own) ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5

    MOV  R1, [BP+3]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+2]          ; R2 = Search Key

    MOV  R4, R1
    AND  R4, BOXED_DATA
    IEQ  R4, BOXED_TABLE
    JF   R4, __table_get_non_table ; strings resolve methods; else trap
    AND  R1, BOXED_PAYLOAD   ; R1 = raw header address

    ;; --- Array part: whole-number key in 1..capacity -> O(1) read ---
    MOV  R3, R2
    AND  R3, NAN_VALUE
    IEQ  R3, NAN_VALUE       ; boxed (not a number)?
    JT   R3, __builtin_table_get_hash
    MOV  R3, R2
    CFI  R3                  ; R3 = (int) key
    MOV  R4, R3
    CIF  R4
    INE  R4, R2              ; fractional?
    JT   R4, __builtin_table_get_hash_num
    MOV  R4, R3
    ILT  R4, 1
    JT   R4, __builtin_table_get_hash_num
    MOV  R5, [R1]
    AND  R5, TABLE_ARRAYSIZE ; capacity
    MOV  R4, R3
    IGT  R4, R5
    JT   R4, __builtin_table_get_hash
    MOV  R5, [R1+2]          ; array data
    IADD R5, R3
    ISUB R5, 1
    MOV  R0, [R5]
    JMP  __builtin_table_get_done

__builtin_table_get_hash_num:
    ;; -0 and 0 are the same key
    MOV  R4, R2
    IEQ  R4, 0x80000000
    JF   R4, __builtin_table_get_hash
    MOV  R2, 0
__builtin_table_get_hash:
    MOV  R5, [R1+3]          ; hash block
    MOV  R4, R5
    IEQ  R4, 0
    JT   R4, __builtin_table_get_not_found
    CALL __table_hash_find   ; R0 = slot address or 0
    MOV  R4, R0
    IEQ  R4, 0
    JT   R4, __builtin_table_get_not_found
    MOV  R0, [R0+1]
    JMP  __builtin_table_get_done

;; --- Indexing a non-table: Lua strings index the string library --------
;; `s:sub(1, 2)` compiles to get(s, "sub") + call(self = s). Strings have
;; no metatable here, so this resolves the name directly to a wrapper with
;; the normal Lua function ABI (see __strmeth_* in string.s). Anything else
;; (or an unknown name on a string) is still the not-a-table runtime error.
__table_get_non_table:
    MOV  R4, R1
    AND  R4, BOXED_DATA
    IEQ  R4, BOXED_ROMSTRING
    JT   R4, __table_get_string_method
    MOV  R4, R1
    AND  R4, BOXED_DATA
    IEQ  R4, BOXED_RAMSTRING
    JF   R4, __runtime_error_not_table
    MOV  R4, R1
    AND  R4, BOXED_PAYLOAD
    ILT  R4, 4                   ; nil/false/true share the RAM-string tag
    JT   R4, __runtime_error_not_table
__table_get_string_method:
    PUSH R2
    CALL __builtin_string_method_lookup
    IADD SP, 1
    MOV  R4, R0
    IEQ  R4, BOXED_NIL
    JT   R4, __runtime_error_not_table
    JMP  __builtin_table_get_done

__builtin_table_get_not_found:
    MOV  R0, BOXED_NIL

__builtin_table_get_done:
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1
    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; __builtin_table_getk(t, k): t[k] for a string-LITERAL k (the compiler
;; emits this for t.field / t["field"]). Pushed like table_get (table,
;; then key); no BP frame. A literal's hash sits in the word before it, so
;; the lookup is: read hash, probe. A hit on a bitwise-equal key or an
;; empty slot settles it here; anything unusual (not a table, no hash
;; part, a non-literal string key in the probe path that might be equal by
;; content) defers to the general __builtin_table_get.
;; ---------------------------------------------------------------------------
__builtin_table_getk:
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    MOV  R1, [SP+7]          ; table (SP: 5 saved regs + return address)
    MOV  R2, R1
    AND  R2, BOXED_DATA
    IEQ  R2, BOXED_TABLE
    JF   R2, __table_getk_slow
    AND  R1, BOXED_PAYLOAD
    MOV  R1, [R1+3]          ; hash block
    MOV  R2, R1
    IEQ  R2, 0
    JT   R2, __table_getk_nil
    MOV  R3, [SP+6]          ; key (pooled literal)
    MOV  R2, R3
    AND  R2, BOXED_PAYLOAD
    OR   R2, V32_CART_PAGE
    ISUB R2, 1
    MOV  R2, [R2]            ; its precomputed hash
    MOV  R4, [R1]
    ISUB R4, 1               ; mask
    AND  R2, R4
    ;; R1 = block, R2 = slot index, R3 = key, R4 = mask; R0 = slot - 2
__table_getk_probe:
    MOV  R0, R2
    SHL  R0, 1
    IADD R0, R1
    MOV  R5, [R0+2]          ; stored key
    IEQ  R5, R3
    JT   R5, __table_getk_hit
    MOV  R5, [R0+2]
    IEQ  R5, BOXED_NIL
    JT   R5, __table_getk_nil ; empty slot: absent
    MOV  R5, [R0+2]
    AND  R5, BOXED_DATA
    IEQ  R5, BOXED_ROMSTRING
    JF   R5, __table_getk_not_rom
    ;; a ROM string: another pooled literal is a different string; a ROM
    ;; string from outside the pool (type() names, ...) may be equal by
    ;; content -> general routine
    MOV  R5, [R0+2]
    AND  R5, BOXED_PAYLOAD
    OR   R5, V32_CART_PAGE
    MOV  R0, __string_pool_start
    IGT  R0, R5
    JT   R0, __table_getk_slow
    MOV  R0, __string_pool_end
    IGT  R0, R5
    JF   R0, __table_getk_slow
__table_getk_next:
    IADD R2, 1
    AND  R2, R4
    JMP  __table_getk_probe
__table_getk_not_rom:
    ;; tables, functions, numbers, booleans: a different key. A run-time
    ;; string (RAM, payload >= 4) may be equal by content -> general routine
    MOV  R5, [R0+2]
    AND  R5, BOXED_DATA
    IEQ  R5, BOXED_RAMSTRING
    JF   R5, __table_getk_next
    MOV  R5, [R0+2]
    AND  R5, BOXED_PAYLOAD
    ILT  R5, 4
    JT   R5, __table_getk_next
    JMP  __table_getk_slow
__table_getk_hit:
    MOV  R0, [R0+3]
    JMP  __table_getk_done
__table_getk_nil:
    MOV  R0, BOXED_NIL
__table_getk_done:
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1
    RET
__table_getk_slow:
    MOV  R0, [SP+7]
    PUSH R0
    MOV  R0, [SP+7]          ; key (one more word on the stack now)
    PUSH R0
    CALL __builtin_table_get
    IADD SP, 2
    JMP  __table_getk_done

;; __table_rawget_int (internal): R1 = raw table header, R3 = integer key
;;   -> R0 = t[key]. Array part read directly; otherwise the general get.
;;   Preserves everything else.
__table_rawget_int:
    PUSH R2
    MOV  R0, R3
    ILT  R0, 1
    JT   R0, __table_rawget_int_slow
    MOV  R0, [R1]
    AND  R0, TABLE_ARRAYSIZE
    MOV  R2, R3
    IGT  R2, R0
    JT   R2, __table_rawget_int_slow
    MOV  R0, [R1+2]
    IADD R0, R3
    ISUB R0, 1
    MOV  R0, [R0]
    POP  R2
    RET
__table_rawget_int_slow:
    MOV  R0, R1
    OR   R0, BOXED_TABLE
    PUSH R0
    MOV  R0, R3
    CIF  R0
    PUSH R0
    CALL __builtin_table_get
    IADD SP, 2
    POP  R2
    RET

;; ===========================================================================
;; TABLE STORAGE (2026-09 rewrite)
;; ---------------------------------------------------------------------------
;; Header (4 words): [0] array capacity (low 16 bits), [1] length (the
;; border # reports), [2] array data pointer, [3] hash block pointer.
;;
;; ARRAY PART: keys 1..capacity live in a plain word array (nil = absent):
;; O(1) reads/writes. It grows by doubling (min 8) when a key lands at most
;; 2x past the current capacity -- i.e. arrays built by appending, or
;; filled in any order from 1 -- and any of the new range's keys already
;; in the hash part are moved into it, so a key is never in both parts.
;;
;; HASH PART: open addressing, linear probing, power-of-two capacity, kept
;; at most 1/2 full. Block: [0] capacity, [1] used slots, then capacity
;; (key, value) pairs; an empty slot's key is BOXED_NIL (nil is never a
;; key). Deleting stores a nil value and leaves the key in place (keeps
;; probe chains intact); growing drops those.
;;
;; STRING KEYS hash by CONTENT (FNV-1a over the characters), so a string
;; built at runtime finds the same slot as the literal. String literals
;; carry their hash precomputed by the compiler in the word just before
;; them (the __string_pool_start..__string_pool_end block), so the usual
;; `obj.field` lookup never touches the characters at all.
;; ===========================================================================

;; __table_hash: R0 = key -> R0 = 32-bit hash. Preserves every other register.
__table_hash:
    PUSH R1
    PUSH R2
    MOV  R1, R0
    AND  R1, 0x7FC00000
    IEQ  R1, 0x7FC00000      ; string-tagged (or nil/false/true)?
    JF   R1, __table_hash_scalar
    MOV  R1, R0
    AND  R1, BOXED_PAYLOAD
    ILT  R1, 4               ; nil/false/true
    JT   R1, __table_hash_scalar
    MOV  R1, R0
    AND  R1, BOXED_CATEGORY
    JT   R1, __table_hash_content      ; RAM string
    ;; ROM string: a pooled literal has its hash stored just before it
    MOV  R1, R0
    AND  R1, BOXED_PAYLOAD
    OR   R1, V32_CART_PAGE   ; R1 = ROM address
    MOV  R2, __string_pool_start
    IGT  R2, R1
    JT   R2, __table_hash_content
    MOV  R2, __string_pool_end
    IGT  R2, R1
    JF   R2, __table_hash_content
    ISUB R1, 1
    MOV  R0, [R1]
    POP  R2
    POP  R1
    RET
__table_hash_content:
    PUSH R3
    CALL __unbox_string      ; R0 = address (uses R1)
    MOV  R1, R0
    MOV  R0, 0x811C9DC5      ; FNV-1a offset basis
__table_hash_content_loop:
    MOV  R2, [R1]
    MOV  R3, R2
    IEQ  R3, 0
    JT   R3, __table_hash_content_done
    AND  R2, 0xFF
    XOR  R0, R2
    IMUL R0, 16777619        ; FNV prime (32-bit wraparound)
    IADD R1, 1
    JMP  __table_hash_content_loop
__table_hash_content_done:
    POP  R3
    POP  R2
    POP  R1
    RET
__table_hash_scalar:
    IMUL R0, 0x9E3779B1      ; Fibonacci hashing of the key bits
    MOV  R1, R0
    SHL  R1, -16             ; (negative count = logical right shift)
    XOR  R0, R1
    POP  R2
    POP  R1
    RET

;; __table_hash_find: R5 = hash block, R2 = key (not nil)
;;   -> R0 = address of the key's slot, or 0 if absent;
;;      R3 = the empty slot the probe stopped at (insertion point).
;;   Preserves everything else.
__table_hash_find:
    PUSH R4
    PUSH R6
    PUSH R7
    MOV  R0, R2
    CALL __table_hash
    MOV  R7, [R5]
    ISUB R7, 1               ; R7 = capacity - 1 (mask)
    AND  R0, R7              ; R0 = slot index
__table_hash_find_loop:
    MOV  R3, R0
    SHL  R3, 1
    IADD R3, R5
    IADD R3, 2               ; R3 = slot address
    MOV  R4, [R3]
    MOV  R6, R4
    IEQ  R6, BOXED_NIL
    JT   R6, __table_hash_find_absent
    MOV  R6, R4
    IEQ  R6, R2
    JT   R6, __table_hash_find_hit
    CALL __table_key_streq   ; equal-content strings at different addresses
    JT   R4, __table_hash_find_hit
    IADD R0, 1
    AND  R0, R7
    JMP  __table_hash_find_loop
__table_hash_find_hit:
    MOV  R0, R3
    JMP  __table_hash_find_out
__table_hash_find_absent:
    MOV  R0, 0
__table_hash_find_out:
    POP  R7
    POP  R6
    POP  R4
    RET

;; __table_hash_new: R0 = capacity (power of two) -> R0 = new empty block.
;; Preserves everything else.
__table_hash_new:
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R6
    MOV  R1, R0
    MOV  R2, R0
    SHL  R2, 1
    IADD R2, 2
    PUSH R1                  ; __malloc clobbers R1-R3, R6
    PUSH R2
    CALL __malloc
    IADD SP, 1
    POP  R1
    MOV  R2, R0
    IEQ  R2, 0
    JT   R2, __oom_handler
    MOV  [R0], R1            ; capacity
    MOV  R2, 0
    MOV  [R0+1], R2          ; used
    MOV  R2, R0
    IADD R2, 2
    MOV  R3, BOXED_NIL
__table_hash_new_fill:
    MOV  R6, R1
    IEQ  R6, 0
    JT   R6, __table_hash_new_done
    MOV  [R2], R3
    IADD R2, 2
    ISUB R1, 1
    JMP  __table_hash_new_fill
__table_hash_new_done:
    POP  R6
    POP  R3
    POP  R2
    POP  R1
    RET

;; __table_hash_grow: R1 = raw table header. Replaces its hash block with
;; one of twice the capacity, re-inserting every live entry (nil-valued
;; ones are dropped). Preserves everything.
__table_hash_grow:
    PUSH R0
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8
    MOV  R6, [R1+3]          ; old block
    MOV  R7, [R6]            ; old capacity
    MOV  R0, R7
    SHL  R0, 1
    CALL __table_hash_new
    MOV  R5, R0              ; new block
    MOV  [R1+3], R5
    IADD R6, 2               ; old slot pointer
__table_hash_grow_loop:
    MOV  R8, R7
    IEQ  R8, 0
    JT   R8, __table_hash_grow_done
    MOV  R2, [R6]
    MOV  R8, R2
    IEQ  R8, BOXED_NIL
    JT   R8, __table_hash_grow_next
    MOV  R4, [R6+1]
    MOV  R8, R4
    IEQ  R8, BOXED_NIL
    JT   R8, __table_hash_grow_next
    CALL __table_hash_find   ; R3 = empty slot (keys are unique)
    MOV  [R3], R2
    MOV  [R3+1], R4
    MOV  R8, [R5+1]
    IADD R8, 1
    MOV  [R5+1], R8
__table_hash_grow_next:
    IADD R6, 2
    ISUB R7, 1
    JMP  __table_hash_grow_loop
__table_hash_grow_done:
    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R0
    RET

;; __table_hash_store: R1 = raw header, R2 = key (not nil), R3 = value.
;; Preserves everything.
__table_hash_store:
    PUSH R0
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    MOV  R6, R3              ; R6 = value
    MOV  R5, [R1+3]
    MOV  R4, R5
    INE  R4, 0
    JT   R4, __table_hash_store_have
    MOV  R4, R6
    IEQ  R4, BOXED_NIL       ; deleting from an empty hash: nothing to do
    JT   R4, __table_hash_store_done
    MOV  R0, 8
    CALL __table_hash_new
    MOV  R5, R0
    MOV  [R1+3], R5
__table_hash_store_have:
    CALL __table_hash_find
    MOV  R4, R0
    IEQ  R4, 0
    JT   R4, __table_hash_store_insert
    MOV  [R0+1], R6          ; existing key: overwrite (nil = delete)
    JMP  __table_hash_store_done
__table_hash_store_insert:
    MOV  R4, R6
    IEQ  R4, BOXED_NIL       ; absent key set to nil: nothing to do
    JT   R4, __table_hash_store_done
    ;; keep the block at most 1/2 full: (used + 1) * 2 > capacity -> grow.
    ;; (3/4 made linear-probe chains long: a lookup of an absent field,
    ;; e.g. `o.solid_obj` on objects without one, averaged ~8 probes.)
    MOV  R4, [R5+1]
    IADD R4, 1
    SHL  R4, 1
    MOV  R0, [R5]
    IGT  R4, R0
    JF   R4, __table_hash_store_put
    CALL __table_hash_grow
    MOV  R5, [R1+3]
    CALL __table_hash_find   ; new insertion slot in R3
__table_hash_store_put:
    MOV  [R3], R2
    MOV  [R3+1], R6
    MOV  R4, [R5+1]
    IADD R4, 1
    MOV  [R5+1], R4
__table_hash_store_done:
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R0
    RET

;; __table_array_grow: R1 = raw header, R4 = key that must fit (int >= 1).
;; New capacity = max(8, 2 * capacity), doubled until it covers R4. Copies
;; the old array, nil-fills the rest, then moves any of the new range's
;; keys out of the hash part. Preserves everything.
__table_array_grow:
    PUSH R0
    PUSH R2
    PUSH R3
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8
    MOV  R5, [R1]
    AND  R5, TABLE_ARRAYSIZE ; R5 = old capacity
    MOV  R6, R5
    SHL  R6, 1
    MOV  R7, R6
    ILT  R7, 8
    JF   R7, __table_array_grow_cap
    MOV  R6, 8
__table_array_grow_cap:
    MOV  R7, R6
    ILT  R7, R4
    JF   R7, __table_array_grow_alloc
    SHL  R6, 1
    JMP  __table_array_grow_cap
__table_array_grow_alloc:
    PUSH R1                  ; __malloc clobbers R1-R3, R6
    PUSH R6
    PUSH R6
    CALL __malloc
    IADD SP, 1
    POP  R6
    POP  R1
    MOV  R7, R0
    IEQ  R7, 0
    JT   R7, __oom_handler
    ;; copy old contents, nil-fill the rest
    MOV  R2, [R1+2]          ; old data (may be 0 when capacity 0)
    MOV  R3, 0
__table_array_grow_copy:
    MOV  R7, R3
    IGE  R7, R6
    JT   R7, __table_array_grow_copied
    MOV  R8, BOXED_NIL
    MOV  R7, R3
    ILT  R7, R5
    JF   R7, __table_array_grow_put
    MOV  R8, R2
    IADD R8, R3
    MOV  R8, [R8]
__table_array_grow_put:
    MOV  R7, R0
    IADD R7, R3
    MOV  [R7], R8
    IADD R3, 1
    JMP  __table_array_grow_copy
__table_array_grow_copied:
    MOV  [R1+2], R0
    MOV  R7, [R1]
    AND  R7, 0xFFFF0000
    OR   R7, R6
    MOV  [R1], R7
    ;; migrate keys old_capacity+1 .. new_capacity out of the hash part
    MOV  R8, [R1+3]
    MOV  R7, R8
    IEQ  R7, 0
    JT   R7, __table_array_grow_done
    MOV  R3, R5              ; R3 = index - 1
__table_array_grow_migrate:
    MOV  R7, R3
    IGE  R7, R6
    JT   R7, __table_array_grow_done
    PUSH R3
    PUSH R5
    MOV  R2, R3
    IADD R2, 1
    CIF  R2                  ; key as a Lua number
    MOV  R5, R8
    CALL __table_hash_find
    MOV  R7, R0
    POP  R5
    POP  R3
    IEQ  R7, 0
    JT   R7, __table_array_grow_migrate_next
    MOV  R2, [R0+1]          ; value
    MOV  R7, BOXED_NIL
    MOV  [R0+1], R7          ; delete from hash
    MOV  R7, [R1+2]
    IADD R7, R3
    MOV  [R7], R2
__table_array_grow_migrate_next:
    IADD R3, 1
    JMP  __table_array_grow_migrate
__table_array_grow_done:
    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R3
    POP  R2
    POP  R0
    RET

;; ---------------------------------------------------------------------------
;; Table Write Indexer: t[k] = v
;; Incoming Stack: [BP+4] = Table Pointer, [BP+3] = Key, [BP+2] = Value
;; Preserves R1-R8.
;; ---------------------------------------------------------------------------
__builtin_table_set:
    PUSH BP
    MOV  BP, SP
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8

    MOV  R1, [BP+4]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+3]          ; R2 = Key
    MOV  R3, [BP+2]          ; R3 = Value
    MOV  R4, R1
    AND  R4, BOXED_DATA
    IEQ  R4, BOXED_TABLE
    JF   R4, __runtime_error_not_table
    AND  R1, BOXED_PAYLOAD

    ;; nil key: nothing can be stored (Lua raises an error; ignored here)
    MOV  R4, R2
    IEQ  R4, BOXED_NIL
    JT   R4, __builtin_table_set_done

    ;; --- whole-number key >= 1? ---
    MOV  R4, R2
    AND  R4, NAN_VALUE
    IEQ  R4, NAN_VALUE
    JT   R4, __builtin_table_set_hash
    MOV  R4, R2
    CFI  R4                  ; R4 = (int) key
    MOV  R5, R4
    CIF  R5
    INE  R5, R2
    JT   R5, __builtin_table_set_hash_num
    MOV  R5, R4
    ILT  R5, 1
    JT   R5, __builtin_table_set_hash_num

    MOV  R5, [R1]
    AND  R5, TABLE_ARRAYSIZE ; capacity
    MOV  R6, R4
    IGT  R6, R5
    JF   R6, __builtin_table_set_array
    ;; beyond capacity: grow the array if the key is within 2x of it
    ;; (min 8) and a real value is being stored; otherwise hash it
    MOV  R6, R3
    IEQ  R6, BOXED_NIL
    JT   R6, __builtin_table_set_hash
    MOV  R6, R5
    SHL  R6, 1
    MOV  R7, R6
    ILT  R7, 8
    JF   R7, __builtin_table_set_grow_limit
    MOV  R6, 8
__builtin_table_set_grow_limit:
    MOV  R7, R4
    IGT  R7, R6
    JT   R7, __builtin_table_set_hash
    CALL __table_array_grow

__builtin_table_set_array:
    MOV  R6, [R1+2]
    IADD R6, R4
    ISUB R6, 1
    MOV  [R6], R3
    ;; --- keep the border (#t) in step ---
    MOV  R7, [R1+1]          ; length
    MOV  R6, R3
    IEQ  R6, BOXED_NIL
    JT   R6, __builtin_table_set_array_nil
    MOV  R6, R7
    IADD R6, 1
    IEQ  R6, R4              ; appended right after the border?
    JF   R6, __builtin_table_set_done
    ;; extend over any values already stored beyond it
    MOV  R5, [R1]
    AND  R5, TABLE_ARRAYSIZE
    MOV  R8, [R1+2]
__builtin_table_set_extend:
    MOV  R6, R4
    IGE  R6, R5
    JT   R6, __builtin_table_set_extend_hash
    MOV  R6, R8
    IADD R6, R4
    MOV  R6, [R6]            ; slot for key R4 + 1
    IEQ  R6, BOXED_NIL
    JT   R6, __builtin_table_set_extended
    IADD R4, 1
    JMP  __builtin_table_set_extend
__builtin_table_set_extend_hash:
    ;; the border reached the end of the array part: if the hash part holds
    ;; key capacity+1, pull that range into the array and keep going
    MOV  R6, [R1+3]
    MOV  R7, R6
    IEQ  R7, 0
    JT   R7, __builtin_table_set_extended
    PUSH R2
    PUSH R5
    MOV  R2, R4
    IADD R2, 1
    CIF  R2
    MOV  R5, R6
    CALL __table_hash_find
    POP  R5
    POP  R2
    MOV  R7, R0
    IEQ  R7, 0
    JT   R7, __builtin_table_set_extended
    MOV  R7, [R0+1]
    IEQ  R7, BOXED_NIL
    JT   R7, __builtin_table_set_extended
    PUSH R4
    IADD R4, 1
    CALL __table_array_grow   ; migrates capacity+1 .. new capacity
    POP  R4
    MOV  R5, [R1]
    AND  R5, TABLE_ARRAYSIZE
    MOV  R8, [R1+2]
    JMP  __builtin_table_set_extend
__builtin_table_set_extended:
    MOV  [R1+1], R4
    JMP  __builtin_table_set_done
__builtin_table_set_array_nil:
    ;; clearing a slot inside the border moves the border below it
    MOV  R6, R4
    IGT  R6, R7
    JT   R6, __builtin_table_set_done
    ISUB R4, 1
    MOV  [R1+1], R4
    JMP  __builtin_table_set_done

__builtin_table_set_hash_num:
    MOV  R4, R2
    IEQ  R4, 0x80000000      ; -0 is the same key as 0
    JF   R4, __builtin_table_set_hash
    MOV  R2, 0
__builtin_table_set_hash:
    CALL __table_hash_store

__builtin_table_set_done:
    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1
    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Table Set With Shift: Inserts value at position, shifting elements to make
;;                       room.
;;
;; Incoming Stack: [BP+5] = Tagged Table Pointer, [BP+4] = Position (1-based),
;;                 [BP+3] = Value to insert, [BP+2] = Current array length
;; Register Usage: R1-R13
;; Returns: R0 = inserted value
;; ---------------------------------------------------------------------------
__builtin_table_set_with_shift:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: Preserve working registers ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12
    PUSH R13

    ;; --- Load arguments ---
    MOV  R1, [BP+5]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+4]          ; R2 = Insertion position (1-based)
    MOV  R3, [BP+3]          ; R3 = Value to insert (return this)
    MOV  R4, [BP+2]          ; R4 = Current array length

    ;; --- Unbox table to get raw address ---
    MOV  R5, R1
    AND  R5, BOXED_PAYLOAD   ; R5 = Raw table header address

    ;; --- Get array pointer from table header ---
    MOV  R6, [R5+2]          ; R6 = Array data pointer (Word 2)

    ;; --- FIX: Allocate array if it doesn't exist ---
    MOV  R7, R6
    IEQ  R7, 0
    JT    R7, __set_with_shift_allocate_array
    JMP   __set_with_shift_get_capacity

__set_with_shift_allocate_array:
    ;; Allocate initial array (start with capacity of 8)
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6

    MOV  R0, 8
    PUSH R0
    CALL __malloc
    IADD SP, 1

    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  R6, R0              ; R6 = New array pointer
    MOV  R7, R0
    IEQ  R7, 0
    JT    R7, __oom_handler

    ;; Store new array pointer in table header
    MOV  [R5+2], R6

    ;; Set initial capacity to 8 in flags
    MOV  R7, [R5]
    MOV  R8, TABLE_ARRAYSIZE
    NOT  R8
    AND  R7, R8              ; Clear old capacity
    OR   R7, 8               ; Set capacity to 8
    MOV  [R5], R7

    ;; Fall through to get capacity

__set_with_shift_get_capacity:
    ;; --- Get capacity from flags ---
    MOV  R7, [R5]            ; R7 = Flags/array capacity (Word 0)
    AND  R7, TABLE_ARRAYSIZE  ; Extract capacity from lower bits

    ;; --- Check if we need to reallocate ---
    IGT  R2, R7
    JT   R2, __set_with_shift_reallocate
    JMP  __set_with_shift_check_shifting

__set_with_shift_reallocate:
    ;; --- Calculate new capacity (double current, or position+1, whichever is larger) ---
    MOV  R8, R7
    IADD R8, R7              ; R8 = 2 * current capacity

    MOV  R9, R2
    IADD R9, 1               ; R9 = position + 1 (minimum needed)

    IGT  R8, R9
    JT   R8, __set_with_shift_use_doubled
    MOV  R8, R9              ; Use position+1 if doubling isn't enough

__set_with_shift_use_doubled:
    ;; --- Allocate new array ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7

    MOV  R0, R8
    PUSH R0
    CALL __malloc
    IADD SP, 1

    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  R8, R0              ; R8 = New array pointer
    MOV  R9, R0
    IEQ  R9, 0
    JT   R9, __oom_handler

    ;; --- Copy existing elements to new array ---
    MOV  R9, 0               ; R9 = Source index counter
    MOV  R10, 0              ; R10 = Destination index counter

__set_with_shift_copy_loop:
    IGE  R9, R4
    JT   R9, __set_with_shift_copy_done

    MOV  R11, R6
    IADD R11, R9

    MOV  R12, R8
    IADD R12, R10

    MOV  R13, [R11]
    MOV  [R12], R13

    IADD R9, 1
    IADD R10, 1
    JMP  __set_with_shift_copy_loop

__set_with_shift_copy_done:
    ;; --- Update table header with new array pointer ---
    MOV  [R5+2], R8

    ;; --- Update capacity in flags: clear old capacity, set new ---
    MOV  R6, [R5]            ; Get current flags
    MOV  R7, TABLE_ARRAYSIZE
    NOT  R7                  ; Invert mask to clear capacity bits
    AND  R6, R7              ; Clear old capacity
    OR   R6, R8              ; Set new capacity
    MOV  [R5], R6

    ;; --- Update R6 to point to new array for shifting ---
    MOV  R6, R8

__set_with_shift_check_shifting:
    ;; --- Check if we need to shift elements ---
    MOV  R8, R4
    IADD R8, 1
    IEQ  R2, R8
    JT   R2, __set_with_shift_no_shift

    ;; --- Shift elements from position to end one slot to the right ---
    MOV  R8, R4              ; R8 = Current length (last valid index)
    MOV  R9, R2              ; R9 = Insertion position

__set_with_shift_loop:
    IGE  R9, R8
    JT   R9, __set_with_shift_store

    MOV  R10, R6
    IADD R10, R8

    MOV  R11, R6
    IADD R11, R8
    IADD R11, 1

    MOV  R12, [R10]
    MOV  [R11], R12

    ISUB R8, 1
    JMP  __set_with_shift_loop

__set_with_shift_no_shift:
    JMP  __set_with_shift_store

__set_with_shift_store:
    ;; --- Store the new value at the insertion position ---
    MOV  R8, R6
    IADD R8, R2
    ISUB R8, 1

    MOV  [R8], R3

    ;; --- Update array length in table header ---
    IADD R4, 1
    MOV  [R5+1], R4

    ;; --- Return the inserted value ---
    MOV  R0, R3

__set_with_shift_done:
    ;; --- Callee-Restore: Pop all working registers ---
    POP  R13
    POP  R12
    POP  R11
    POP  R10
    POP  R9
    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Table Insert: table.insert(t, [pos], value)
;; Inserts a value at a specific 1-based position, shifting existing
;; elements up by one. With no position (BOXED_NIL), appends at the end.
;; Negative positions count backward from the end: resolved = length + pos + 1
;; (this is a v32lua extension, not standard Lua -- e.g.
;; table.insert(t, -1, x) inserts immediately before the current last
;; element, per this project's test suite).
;;
;; Incoming Stack: [BP+4] = Tagged Table Pointer, [BP+3] = Position (1-based
;;                 float, negative float, or BOXED_NIL for append),
;;                 [BP+2] = Value to insert
;; Register Usage: R1-R8
;; Returns: R0 = inserted value (for pico8 add() compatibility)
;;
;; IMPLEMENTATION NOTE: this is implemented entirely in terms of
;; __builtin_table_get / __builtin_table_set rather than raw array-pointer
;; arithmetic. Real contiguous-array storage doesn't exist yet in this
;; runtime (table capacity is always 0 -- see __builtin_table_set's
;; __builtin_table_set_reallocate TODO), so every table here is actually
;; backed by the hash association list. The previous version of this
;; function assumed a working raw array and wrote directly through the
;; (always-null) array pointer -- on top of never converting the boxed
;; float position to a raw integer, and corrupting the position on the
;; default-append path. Routing every read/write through
;; table_get/table_set fixes all of that at once, and gets negative
;; positions and correct length bookkeeping for free (the shift loop's
;; first table_set naturally lands on key == length + 1, which
;; __builtin_table_set already bumps the tracked length for). It'll also
;; automatically become real O(1) array shifting for free whenever array
;; allocation is implemented, with zero changes needed here.
;; ---------------------------------------------------------------------------
__builtin_table_insert:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: Preserve all 8 working registers ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8

    ;; --- Load arguments from caller's stack frame ---
    MOV  R1, [BP+4]          ; R1 = Tagged Table Pointer (kept BOXED -- table_get/table_set want it boxed)
    MOV  R2, [BP+3]          ; R2 = Position (boxed float, negative float, or BOXED_NIL)
    MOV  R3, [BP+2]          ; R3 = Value to insert (boxed; preserved for the final store + return)

    ;; --- Validate table type, and get the raw header address just to
    ;;     read the current contiguous length directly (Word 1) ---
    MOV  R4, R1
    AND  R4, BOXED_DATA
    IEQ  R4, BOXED_TABLE
    JF   R4, __runtime_error_not_table
    MOV  R5, R1
    AND  R5, BOXED_PAYLOAD   ; R5 = raw table header address

    MOV  R6, [R5+1]          ; R6 = current contiguous length

    ;; --- Resolve the insertion position into R7 (a raw integer) ---
    MOV  R4, R2
    IEQ  R4, BOXED_NIL
    JT   R4, __insert_default_append

    ;; Position given: convert boxed float -> raw integer.
    MOV  R7, R2
    CFI  R7                  ; R7 = integer position (may be negative)

    MOV  R4, R7
    ILT  R4, 0                ; negative position?
    JF   R4, __insert_position_resolved

    ;; Negative position: count backward from the end (v32lua extension).
    ;; resolved = length + position + 1
    MOV  R4, R6
    IADD R4, R7
    IADD R4, 1
    MOV  R7, R4
    JMP  __insert_position_resolved

__insert_default_append:
    MOV  R7, R6
    IADD R7, 1                ; resolved = length + 1

__insert_position_resolved:
    ;; Clamp: never let the resolved position fall below 1. Guards against
    ;; pathological / wildly out-of-range negative input producing a
    ;; degenerate shift loop. (Real Lua would raise an error for an
    ;; out-of-bounds position; this runtime doesn't have error-raising
    ;; infrastructure for library calls yet, so clamping is the safe,
    ;; cheap guard for now.)
    MOV  R4, R7
    ILT  R4, 1
    JF   R4, __insert_shift_init
    MOV  R7, 1

__insert_shift_init:
    MOV  R8, R6                ; R8 = shift cursor, starts at current length

    ;; --- Shift elements from length down to position (descending) ---
    ;; Each step: t[cursor + 1] = t[cursor]. Going from the top down avoids
    ;; overwriting a value before it's been read. The very first shift (if
    ;; any) writes to key == length + 1, which naturally makes
    ;; __builtin_table_set bump the tracked length by one as a side
    ;; effect -- exactly the length update this insert needs, for free.
__insert_shift_loop:
    MOV  R4, R8
    ILT  R4, R7                ; cursor < position? shifting is done
    JT   R4, __insert_store_value

    ;; --- fetch t[cursor] ---
    MOV  R4, R8
    CIF  R4                    ; R4 = boxed float source key
    PUSH R1                    ; table pointer
    PUSH R4                    ; key = cursor
    CALL __builtin_table_get
    IADD SP, 2
    MOV  R5, R0                ; R5 = fetched value (boxed)

    ;; --- store into t[cursor + 1] ---
    MOV  R6, R8
    IADD R6, 1
    CIF  R6                    ; R6 = boxed float destination key

    PUSH R1                    ; table pointer
    PUSH R6                    ; key = cursor + 1
    PUSH R5                    ; value = fetched
    CALL __builtin_table_set
    IADD SP, 3

    ISUB R8, 1
    JMP  __insert_shift_loop

__insert_store_value:
    ;; --- Store the new value at the resolved position ---
    MOV  R4, R7
    CIF  R4                    ; R4 = boxed float position key

    PUSH R1                    ; table pointer
    PUSH R4                    ; key = position
    PUSH R3                    ; value to insert
    CALL __builtin_table_set
    IADD SP, 3

    ;; --- Return the inserted value (for add() compatibility) ---
    MOV  R0, R3

__insert_done:
    ;; --- Callee-Restore: Pop working registers in reverse order (LIFO) ---
    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; __builtin_table_len: Get length of table array part
__builtin_table_len:
    PUSH BP
    MOV  BP, SP
    MOV  R0, [BP+2]    ; Table pointer
    CALL __unbox_table   ; R0 = raw table header address

    ;; --- VALIDATION: Use R1 and R2 (scratch) to preserve R0 ---
    MOV  R1, R0          ; Copy for null check
    IEQ  R1, 0
    JT   R1, __table_len_invalid

    MOV  R2, R0          ; Copy for ROM check (R0 still intact!)
    IGE  R2, 0x20000000
    JT   R2, __table_len_invalid

    MOV  R0, [R0+1]     ; Read array length from header word 1
    CIF  R0             ; Convert to float
    MOV  SP, BP
    POP  BP
    RET

__table_len_invalid:
    MOV  R0, 0
    CIF  R0
    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Unbox Table Pointer: Converts a tagged Table pointer to raw RAM address
;;
;; Input:  R0 = Tagged Table Pointer (0xFF8xxxxx)
;; Output: R0 = Raw RAM address (unboxed)
;; Clobbers: R0 only
;; ---------------------------------------------------------------------------
__unbox_table:
    ;; Strip the BOXED_TABLE tag (0xFF800000) from the upper bits
    ;; to get the raw heap address
    AND  R0, BOXED_PAYLOAD

    ;; Verify the result is a valid pointer (optional safety check)
    ;; IEQ  R2, R0
    ;; JT   R2, __unbox_table_valid
    ;; MOV  R0, 0  ; Return 0 for invalid (shouldn't happen in practice)
__unbox_table_valid:
    RET

;; ---------------------------------------------------------------------------
;; Runtime Panic Handlers for Table Errors
;; ---------------------------------------------------------------------------
__runtime_error_not_table:
    PUSH BP
    MOV  BP, SP
    ISUB SP, 1
    MOV  [BP-1], R1                ; the value that wasn't a table

    MOV  R0, 0xFF000080
    OUT  GPU_ClearColor, R0
    OUT  GPU_Command, GPUCommand_ClearScreen

    MOV  R0, 20
    PUSH R0
    MOV  R0, 0
    PUSH R0
    MOV  R0, __const_str_panic_banner
    OR   R0, BOXED_ROMSTRING
    PUSH R0
    CALL __builtin_print

    MOV  R0, 20
    PUSH R0
    MOV  R0, 20
    PUSH R0
    MOV  R0, __const_str_err_not_table
    OR   R0, BOXED_ROMSTRING
    PUSH R0
    CALL __builtin_print

    MOV  R0, 20
    PUSH R0
    MOV  R0, 40
    PUSH R0
    MOV  R0, [BP-1]
    PUSH R0
    CALL __builtin_print

    JMP __panic_halt

__runtime_error_hash_overflow:
    ;; Trap CPU if hash part exceeds 7 pairs (until dynamic rehashing
    ;; is implemented)
    HLT
    JMP __runtime_error_hash_overflow

;; ===========================================================================
;; LUA TABLE LIBRARY IMPLEMENTATION FOR V32LUA
;; ===========================================================================
;;
;; This file implements the standard Lua table library functions for the v32lua
;; compiler targeting the Vircon32 fantasy console.
;;
;; Implemented functions:
;; - table.insert(t, [pos], value)  - Already exists as __builtin_table_insert
;; - table.remove(t, [pos])          - Remove element at position
;; - table.sort(t, [comp])          - Sort table elements in-place
;; - table.concat(t, [sep], [i], [j]) - Concatenate array elements
;; - table.move(a1, f, e, t, [a2])  - Move elements between tables
;; - table.pack(...)                - Pack arguments into table with .n field
;; - table.unpack(t, [i], [j])      - Unpack table elements as multiple returns
;;
;; ===========================================================================

;; ===========================================================================
;; SECTION: TABLE REMOVE
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; table.remove(t, [pos]) - Removes and returns element at position pos
;; If pos is nil or > length, removes and returns last element
;; Shifts elements left to fill the gap
;;
;; Incoming Stack: [BP+3] = Tagged Table Pointer, [BP+2] = Position (optional)
;; Returns: R0 = removed value
;; Register Usage: R1-R8
;; ---------------------------------------------------------------------------
__builtin_table_remove:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: Preserve 8 working registers ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11

    ;; --- Load arguments ---
    MOV  R1, [BP+3]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+2]          ; R2 = Position (may be NIL)

    ;; --- Validate table ---
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_TABLE
    JF   R3, __runtime_error_not_table

    ;; --- Unbox table pointer ---
    AND  R1, BOXED_PAYLOAD   ; R1 = raw table header address

    ;; --- Get current length ---
    MOV  R3, [R1+1]          ; R3 = current array length

    ;; --- Handle default position (NIL or > length = remove last) ---
    MOV  R4, R2
    IEQ  R4, BOXED_NIL
    JT   R4, __table_remove_last

    ;; Convert position to integer if it's a float
    MOV  R4, R2
    AND  R4, NAN_VALUE
    IEQ  R4, NAN_VALUE
    JT   R4, __table_remove_check_position

    ;; It's a float, convert to integer
    MOV  R4, R2
    CFI  R4
    MOV  R5, R4
    CIF  R5
    INE  R5, R2
    JT   R5, __table_remove_invalid_position

__table_remove_check_position:
    ;; --- Resolve negative positions: count backward from the end,
    ;; matching table.insert's convention (resolved = length + pos + 1).
    ;; e.g. table.remove(t, -1) removes the last element. Previously any
    ;; position < 1 -- including legitimate negative ones -- fell straight
    ;; into the "invalid position" bailout below without ever being
    ;; resolved, so table.remove(t, -1) always returned nil without
    ;; touching the table.
    MOV  R8, R4
    ILT  R8, 0
    JF   R8, __table_remove_bounds_check
    MOV  R8, R3
    IADD R8, R4
    IADD R8, 1
    MOV  R4, R8

__table_remove_bounds_check:
    ;; R4 now contains integer position (use R8 for comparisons)
    MOV  R8, R4
    ILT  R8, 1
    JT   R8, __table_remove_invalid_position
    MOV  R8, R4
    IGT  R8, R3
    JT   R8, __table_remove_last
    JMP  __table_remove_at_position

__table_remove_last:
    MOV  R4, R3              ; Position = length (last element)

__table_remove_at_position:
    MOV  R6, R4
    ILT  R6, 1                ; empty table: nothing to remove
    JT   R6, __table_remove_not_found
    ;; --- Get array data pointer ---
    MOV  R5, [R1+2]          ; R5 = array data pointer

    ;; --- Whole range 1..length in the array part? Then shift in place ---
    MOV  R6, R5
    IEQ  R6, 0
    JT   R6, __table_remove_hash_path
    MOV  R6, [R1]
    AND  R6, TABLE_ARRAYSIZE
    ILT  R6, R3               ; capacity < length: part of it is hashed
    JT   R6, __table_remove_hash_path   ; No array (the common case: __builtin_table_set's
                                     ; reallocation path is currently a stub, so array-
                                     ; backed tables never actually exist) -> use the
                                     ; hash-backed slow path instead of silently no-op'ing.

    ;; --- Calculate address of element to remove ---
    MOV  R6, R5
    IADD R6, R4
    ISUB R6, 1               ; Address = array_ptr + (position - 1)

    ;; --- Save the value to return ---
    MOV  R7, [R6]            ; R7 = value to return

    ;; --- Shift elements left to fill the gap ---
    MOV  R8, R4              ; R8 = position to remove

__table_remove_shift_loop:
    MOV  R9, R8
    ILT  R9, R3
    JF   R9, __table_remove_update_length

    MOV  R9, R5
    IADD R9, R8              ; element R8+1 (0-based R8) ...

    MOV  R10, R5
    IADD R10, R8
    ISUB R10, 1              ; ... moves down to element R8

    MOV  R11, [R9]
    MOV  [R10], R11

    IADD R8, 1
    JMP  __table_remove_shift_loop

__table_remove_update_length:
    ;; clear the vacated last slot, then shrink the border
    MOV  R9, R5
    IADD R9, R3
    ISUB R9, 1
    MOV  R10, BOXED_NIL
    MOV  [R9], R10
    ISUB R3, 1
    MOV  [R1+1], R3

    MOV  R0, R7
    JMP  __table_remove_done

;; ---------------------------------------------------------------------------
;; HASH PATH: element lives in the hash bucket, not the (currently always-
;; empty) contiguous array. Shift down via table_get/table_set instead of
;; touching array memory directly. NOTE: table_get only callee-saves R1-R7,
;; so every value that must survive a sub-CALL here is kept in R1-R7 -- R8+
;; is NOT safe to hold state in across these calls.
;; ---------------------------------------------------------------------------
__table_remove_hash_path:
    ;; value_to_return = get(table, position)
    MOV  R5, R4
    CIF  R5                   ; R5 = float(position)
    MOV  R6, R1
    OR   R6, BOXED_TABLE      ; R6 = re-tagged table pointer
    PUSH R6
    PUSH R5
    CALL __builtin_table_get
    IADD SP, 2
    MOV  R7, R0               ; R7 = value to return (preserved: within R1-R7)

    MOV  R2, R4                ; R2 = shift index i, starting at position
__table_remove_hash_shift_loop:
    MOV  R5, R2
    ILT  R5, R3                ; i < length ?
    JF   R5, __table_remove_hash_shift_done

    ;; tmp = get(table, i+1)
    MOV  R5, R2
    IADD R5, 1
    CIF  R5
    MOV  R6, R1
    OR   R6, BOXED_TABLE
    PUSH R6
    PUSH R5
    CALL __builtin_table_get
    IADD SP, 2
    MOV  R5, R0                ; R5 = fetched value

    ;; set(table, i, tmp)
    MOV  R6, R1
    OR   R6, BOXED_TABLE
    MOV  R0, R2
    CIF  R0                    ; R0 = float(i)
    PUSH R6
    PUSH R0
    PUSH R5
    CALL __builtin_table_set
    IADD SP, 3

    IADD R2, 1
    JMP  __table_remove_hash_shift_loop

__table_remove_hash_shift_done:
    ;; --- FIX: clear the now-vacated slot ---
    ;; The shift loop above only ever OVERWRITES each slot with the NEXT
    ;; slot's value -- it never actually deletes anything -- so the very
    ;; last slot (at the OLD length's key, still held in R3 here) keeps a
    ;; live, non-nil duplicate forever. Any subsequent `t[k]` read past
    ;; the new (shrunk) length incorrectly still finds that duplicate
    ;; instead of nil, since the hash-fallback read path scans for the
    ;; key directly and never consults the tracked length at all. This is
    ;; exactly what makes the extremely common
    ;; `while t[1] ~= nil do table.remove(t, 1) end` idiom loop forever --
    ;; index 1 never actually becomes nil no matter how many elements are
    ;; removed.
    ;;
    ;; Storing BOXED_NIL at the vacated key matches this runtime's
    ;; established "nil-valued hash entry == absent" convention (see
    ;; __builtin_next's own doc comment). This single table_set call also
    ;; replaces the old manual "ISUB R3,1; MOV [R1+1],R3" entirely:
    ;; __builtin_table_set's own nil-handling logic
    ;; (__builtin_table_set_hash_maybe_shrink) already clamps the tracked
    ;; length down to (key - 1) whenever a nil is stored at a key within
    ;; the current length -- which the key we're storing here (the OLD
    ;; length, unchanged since before this loop) always is. Letting it
    ;; do that bookkeeping itself avoids two separate, easy-to-desync
    ;; length writes.
    MOV  R5, R3
    CIF  R5                    ; R5 = float(old length) -- the vacated key
    MOV  R6, R1
    OR   R6, BOXED_TABLE
    MOV  R0, BOXED_NIL
    PUSH R6
    PUSH R5
    PUSH R0
    CALL __builtin_table_set   ; also shrinks tracked length to (old_length - 1)
    IADD SP, 3

    MOV  R0, R7
    JMP  __table_remove_done

__table_remove_not_found:
    MOV  R0, BOXED_NIL
    JMP  __table_remove_done

__table_remove_invalid_position:
    MOV  R0, BOXED_NIL

__table_remove_done:
    ;; --- Callee-Restore ---
    POP  R11
    POP  R10
    POP  R9
    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; table.sort(t, [comp]) - Sorts table elements in-place (bubble sort).
;; Ascending by default, or via a custom comp(a, b) function that returns
;; true when a should sort before b.
;;
;; Incoming Stack (pushed t, comp in that order):
;;   [BP+3] = t (boxed table pointer)
;;   [BP+2] = comp (boxed function, or BOXED_NIL for default ascending order)
;; Returns: R0 = BOXED_NIL (table.sort returns nothing in real Lua)
;;
;; REPLACES the previous version, which (a) never used its comp argument
;; at all, and (b) walked the table's "array part" directly via raw
;; pointer arithmetic on header word 2, which is NEVER actually allocated
;; by this runtime (same discovery as the table.move/table.concat
;; rewrites) -- so the old bubble sort's very first check, "is the array
;; pointer null?", was always true for every real table, and it silently
;; did nothing, for anything, ever.
;;
;; This version goes entirely through __builtin_len / __builtin_table_get
;; / __builtin_table_set, and invokes a user comparator via __builtin_exec
;; when provided -- the same mechanism generic-for uses for iterator
;; functions. NOTE: Lua function calls push arguments RIGHT-TO-LEFT
;; (param 1 ends up at [BP+2] inside the callee), the OPPOSITE convention
;; from this runtime's own internal builtins (which push left-to-right) --
;; see the comparator-invocation block below.
;;
;; Default comparator uses __builtin_relcmp -- the same three-way compare
;; the < operator is built on -- which already correctly handles both
;; numbers and strings, unlike the old stub's raw FLT-on-NaN-boxed-values
;; approach (undefined/always-false for any two strings).
;;
;; Incomparable-type pairs (e.g. sorting a table with a mix of numbers and
;; non-numbers) make __builtin_relcmp return its error sentinel, which
;; this treats as "not less than" -- the pair is simply never swapped
;; relative to each other, rather than raising an error. Matches this
;; runtime's existing permissive style elsewhere (no hard error on
;; incomparable relational operands), NOT real Lua's behavior (which
;; raises "attempt to compare" errors). Worth knowing if a test ever
;; deliberately sorts mixed types.
;; ---------------------------------------------------------------------------
__builtin_table_sort:
    PUSH BP
    MOV  BP, SP
    ISUB SP, 7   ; [BP-1]=n  [BP-2]=i  [BP-3]=j  [BP-4]=comp (boxed)
                 ; [BP-5]=t[j+1]  [BP-6]=t[j+2]  [BP-7]=should_swap

    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4

    ;; --- Validate table ---
    MOV  R1, [BP+3]
    MOV  R2, R1
    AND  R2, BOXED_DATA
    IEQ  R2, BOXED_TABLE
    JF   R2, __runtime_error_not_table

    MOV  R1, [BP+2]
    MOV  [BP-4], R1          ; save comparator (boxed function, or nil)

    ;; --- n = #t ---
    MOV  R1, [BP+3]
    PUSH R1
    CALL __builtin_len
    IADD SP, 1
    MOV  R1, R0
    CFI  R1
    MOV  [BP-1], R1          ; n

    MOV  R1, [BP-1]
    ILT  R1, 2
    JT   R1, __sort_done      ; fewer than 2 elements -- nothing to sort

    MOV  R1, 0
    MOV  [BP-2], R1           ; i = 0

__sort_outer_loop:
    MOV  R1, [BP-2]
    MOV  R2, [BP-1]
    ISUB R2, 1
    IGE  R1, R2
    JT   R1, __sort_done      ; i >= n-1?

    MOV  R1, 0
    MOV  [BP-3], R1           ; j = 0

__sort_inner_loop:
    MOV  R1, [BP-3]
    MOV  R2, [BP-1]
    ISUB R2, 1
    MOV  R3, [BP-2]
    ISUB R2, R3
    IGE  R1, R2
    JT   R1, __sort_inner_done   ; j >= n-1-i?

    ;; --- Fetch t[j+1] ---
    MOV  R1, [BP-3]
    IADD R1, 1
    CIF  R1
    MOV  R2, [BP+3]
    PUSH R2
    PUSH R1
    CALL __builtin_table_get
    IADD SP, 2
    MOV  [BP-5], R0            ; t[j+1]

    ;; --- Fetch t[j+2] ---
    MOV  R1, [BP-3]
    IADD R1, 2
    CIF  R1
    MOV  R2, [BP+3]
    PUSH R2
    PUSH R1
    CALL __builtin_table_get
    IADD SP, 2
    MOV  [BP-6], R0            ; t[j+2]

    ;; --- should_swap: does t[j+2] belong before t[j+1]? ---
    MOV  R1, [BP-4]
    IEQ  R1, BOXED_NIL
    JF   R1, __sort_use_comp

    ;; --- Default: __builtin_relcmp(t[j+2], t[j+1]) == -1 ---
    ;; (relcmp pushes left-to-right: Left pushed first, Right pushed last)
    MOV  R1, [BP-6]             ; Left = t[j+2]
    MOV  R2, [BP-5]             ; Right = t[j+1]
    PUSH R1
    PUSH R2
    CALL __builtin_relcmp
    IADD SP, 2
    IEQ  R0, -1
    MOV  [BP-7], R0
    JMP  __sort_check_swap

__sort_use_comp:
    ;; --- Custom: comp(t[j+2], t[j+1]) -- Lua calls push RIGHT-TO-LEFT, ---
    ;; --- so param 2 (b) is pushed first, param 1 (a) pushed last. ---
    MOV  R1, [BP-6]              ; a = t[j+2] (param 1)
    MOV  R2, [BP-5]              ; b = t[j+1] (param 2)
    PUSH R2                      ; param 2 pushed first
    PUSH R1                      ; param 1 pushed last
    MOV  R0, [BP-4]
    CALL __builtin_exec
    IADD SP, 2
    IEQ  R0, BOXED_TRUE
    MOV  [BP-7], R0

__sort_check_swap:
    MOV  R1, [BP-7]
    IEQ  R1, 0
    JT   R1, __sort_no_swap

    ;; --- Swap: t[j+1] = old t[j+2], t[j+2] = old t[j+1] ---
    MOV  R1, [BP-3]
    IADD R1, 1
    CIF  R1
    MOV  R2, [BP+3]
    MOV  R3, [BP-6]
    PUSH R2
    PUSH R1
    PUSH R3
    CALL __builtin_table_set
    IADD SP, 3

    MOV  R1, [BP-3]
    IADD R1, 2
    CIF  R1
    MOV  R2, [BP+3]
    MOV  R3, [BP-5]
    PUSH R2
    PUSH R1
    PUSH R3
    CALL __builtin_table_set
    IADD SP, 3

__sort_no_swap:
    MOV  R1, [BP-3]
    IADD R1, 1
    MOV  [BP-3], R1
    JMP  __sort_inner_loop

__sort_inner_done:
    MOV  R1, [BP-2]
    IADD R1, 1
    MOV  [BP-2], R1
    JMP  __sort_outer_loop

__sort_done:
    MOV  R0, BOXED_NIL

    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; __concat_make_empty_string: allocate a fresh zero-length RAM string.
;; Output: R0 = boxed empty string. Clobbers: R0, R1, R2 only.
;; ---------------------------------------------------------------------------
__concat_make_empty_string:
    MOV  R1, [HEAP_POINTER]   ; R1 = base address for this new string
    MOV  R2, 0
    MOV  [R1], R2             ; write null terminator
    MOV  R0, R1
    IADD R0, 1
    MOV  [HEAP_POINTER], R0   ; bump heap pointer past the 1 byte used
    MOV  R0, R1
    OR   R0, BOXED_RAMSTRING  ; box the STRING BASE (not the bumped pointer)
    RET

;; ---------------------------------------------------------------------------
;; table.concat(t, [sep], [i], [j]) - Concatenates array elements into a string
;;
;; Incoming Stack (pushed t, sep, i, j in that order):
;;   [BP+5] = t (boxed table pointer)
;;   [BP+4] = sep (boxed string, or BOXED_NIL for "no separator")
;;   [BP+3] = i (boxed float, or BOXED_NIL for "default 1")
;;   [BP+2] = j (boxed float, or BOXED_NIL for "default #t")
;; Returns: R0 = boxed result string
;;
;; REPLACES the previous stub, which ignored the separator entirely,
;; returned the first element raw/unstringified instead of concatenating,
;; and returned BOXED_NIL instead of "" for an empty range.
;;
;; STACK-OFFSET NOTE: the previous version of this routine documented and
;; read from [BP+6]..[BP+3], one slot higher across the board than every
;; other proven N-argument builtin in this file ([BP+(N+1)]..[BP+2] --
;; see table_get, table_insert). That looks like an authoring bug in the
;; abandoned stub. This rewrite uses the established convention instead:
;; [BP+5]..[BP+2] for 4 arguments, matching emit_table_concat_intrinsic's
;; push order (t, sep, i, j).
;; ---------------------------------------------------------------------------
__builtin_table_concat:
    PUSH BP
    MOV  BP, SP
    ISUB SP, 6   ; [BP-1]=i  [BP-2]=j  [BP-3]=accumulator  [BP-4]=loop idx
                 ; [BP-5]=resolved sep  [BP-6]=first-element flag

    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8

    ;; --- Validate table type up front ---
    MOV  R1, [BP+5]
    MOV  R2, R1
    AND  R2, BOXED_DATA
    IEQ  R2, BOXED_TABLE
    JF   R2, __runtime_error_not_table

    ;; --- Resolve j: default to #t if nil ---
    MOV  R1, [BP+2]
    MOV  R2, R1
    IEQ  R2, BOXED_NIL
    JF   R2, __concat_j_given
    MOV  R3, [BP+5]        ; table pointer (still boxed -- __builtin_len wants it boxed)
    PUSH R3
    CALL __builtin_len      ; R0 = float length
    IADD SP, 1
    MOV  R1, R0
__concat_j_given:
    CFI  R1
    MOV  [BP-2], R1

    ;; --- Resolve i: default to 1 if nil ---
    MOV  R1, [BP+3]
    MOV  R2, R1
    IEQ  R2, BOXED_NIL
    JF   R2, __concat_i_given
    MOV  R1, 1.0
__concat_i_given:
    CFI  R1
    MOV  [BP-1], R1

    ;; --- Resolve sep: default to a fresh empty string if nil ---
    MOV  R1, [BP+4]
    MOV  R2, R1
    IEQ  R2, BOXED_NIL
    JF   R2, __concat_sep_given
    CALL __concat_make_empty_string
    MOV  R1, R0
__concat_sep_given:
    MOV  [BP-5], R1

    ;; --- Seed accumulator with a fresh empty string, first-flag = true ---
    CALL __concat_make_empty_string
    MOV  [BP-3], R0
    MOV  R1, 1
    MOV  [BP-6], R1

    MOV  R1, [BP-1]
    MOV  [BP-4], R1      ; loop index = i

__concat_loop:
    MOV  R1, [BP-4]
    MOV  R2, [BP-2]
    IGT  R1, R2
    JT   R1, __concat_done

    ;; --- If not the first element, append the separator first ---
    MOV  R1, [BP-6]
    IEQ  R1, 1
    JT   R1, __concat_skip_sep

    MOV  R3, [BP-3]       ; accumulator
    PUSH R3
    MOV  R4, [BP-5]       ; separator
    PUSH R4
    CALL __builtin_strcat
    IADD SP, 2
    MOV  [BP-3], R0       ; accumulator = accumulator .. sep

__concat_skip_sep:
    ;; --- Fetch element and append it ---
    MOV  R5, [BP-4]        ; raw int loop index
    MOV  R6, R5
    CIF  R6                ; boxed float key
    MOV  R7, [BP+5]        ; table pointer
    PUSH R7
    PUSH R6
    CALL __builtin_table_get
    IADD SP, 2
    MOV  R8, R0            ; R8 = element value (any type; strcat coerces)

    MOV  R3, [BP-3]        ; accumulator
    PUSH R3
    PUSH R8
    CALL __builtin_strcat
    IADD SP, 2
    MOV  [BP-3], R0        ; accumulator = accumulator .. tostring(element)

    ;; --- Clear the first-flag, advance loop index ---
    MOV  R1, 0
    MOV  [BP-6], R1
    MOV  R1, [BP-4]
    IADD R1, 1
    MOV  [BP-4], R1
    JMP  __concat_loop

__concat_done:
    MOV  R0, [BP-3]         ; R0 = final accumulator string

    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; table.move(a1, f, e, t, [a2]) - Copies elements a1[f..e] to a2 starting at t
;; If a2 is nil, a1 is used as destination (move within the same table).
;;
;; Incoming Stack (pushed a1, f, e, t, a2 in that order):
;;   [BP+6] = a1 (source table, boxed)
;;   [BP+5] = f  (start index, boxed float)
;;   [BP+4] = e  (end index, boxed float)
;;   [BP+3] = t  (destination start index, boxed float)
;;   [BP+2] = a2 (destination table, boxed, or BOXED_NIL for "same as a1")
;; Returns: R0 = boxed destination table
;;
;; REPLACES the previous version, which read/wrote the table's "array
;; part" directly via raw pointer arithmetic on header word 2. That array
;; part is NEVER actually allocated by this runtime for any table --
;; __builtin_table_set's own comments confirm array capacity is always 0
;; and every write goes through the hash-bucket fallback instead. The old
;; version's destination-resize path was a TODO stub that silently wrote
;; past a pointer that's always null -- a real heap-corruption risk the
;; moment the array part ever did get allocated.
;;
;; This version goes entirely through __builtin_table_get /
;; __builtin_table_set instead -- the same primitives table.concat and
;; every passing tables/ test already rely on. No fixed capacity to
;; overflow, since the hash-bucket fallback grows dynamically.
;;
;; Overlap safety: copies BACKWARD (highest index first) whenever a1 == a2
;; (by boxed-pointer equality, which also naturally covers "a2 omitted")
;; and t > f; forward otherwise. Matches real Lua's overlap handling.
;; ---------------------------------------------------------------------------
__builtin_table_move:
    PUSH BP
    MOV  BP, SP
    ISUB SP, 6   ; [BP-1]=f  [BP-2]=e  [BP-3]=t  [BP-4]=count
                 ; [BP-5]=resolved a2 (boxed)  [BP-6]=loop counter

    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8

    ;; --- Validate a1 ---
    MOV  R1, [BP+6]
    MOV  R2, R1
    AND  R2, BOXED_DATA
    IEQ  R2, BOXED_TABLE
    JF   R2, __runtime_error_not_table

    ;; --- Resolve a2: default to a1 if nil ---
    MOV  R1, [BP+2]
    MOV  R2, R1
    IEQ  R2, BOXED_NIL
    JF   R2, __move_a2_given
    MOV  R1, [BP+6]           ; a2 = a1
    JMP  __move_a2_resolved
__move_a2_given:
    MOV  R2, R1
    AND  R2, BOXED_DATA
    IEQ  R2, BOXED_TABLE
    JF   R2, __runtime_error_not_table
__move_a2_resolved:
    MOV  [BP-5], R1            ; resolved a2 (boxed)

    ;; --- Convert f, e, t to raw ints ---
    MOV  R1, [BP+5]
    CFI  R1
    MOV  [BP-1], R1            ; f

    MOV  R1, [BP+4]
    CFI  R1
    MOV  [BP-2], R1            ; e

    MOV  R1, [BP+3]
    CFI  R1
    MOV  [BP-3], R1            ; t

    ;; --- count = e - f + 1 ---
    MOV  R1, [BP-2]
    MOV  R2, [BP-1]
    ISUB R1, R2
    IADD R1, 1
    MOV  [BP-4], R1            ; count (may be < 1 -- empty range, no-op)

    MOV  R1, [BP-4]
    ILT  R1, 1
    JT   R1, __move_done       ; count < 1 -> nothing to copy

    ;; --- Choose direction: backward only if a1 == a2 (resolved) AND t > f ---
    MOV  R1, [BP+6]
    MOV  R2, [BP-5]
    IEQ  R1, R2
    JF   R1, __move_forward_init

    MOV  R1, [BP-3]
    MOV  R2, [BP-1]
    IGT  R1, R2
    JT   R1, __move_backward_init
    JMP  __move_forward_init

__move_forward_init:
    MOV  R1, 0
    MOV  [BP-6], R1             ; counter = 0
    JMP  __move_forward_loop

__move_forward_loop:
    MOV  R1, [BP-6]
    MOV  R2, [BP-4]
    IGE  R1, R2                  ; counter >= count?
    JT   R1, __move_done

    MOV  R3, [BP-1]              ; source index = f + counter
    MOV  R4, [BP-6]
    IADD R3, R4
    CIF  R3

    MOV  R5, [BP+6]
    PUSH R5
    PUSH R3
    CALL __builtin_table_get
    IADD SP, 2
    MOV  R6, R0                  ; R6 = fetched value

    MOV  R3, [BP-3]              ; dest index = t + counter
    MOV  R4, [BP-6]
    IADD R3, R4
    CIF  R3

    MOV  R5, [BP-5]
    PUSH R5
    PUSH R3
    PUSH R6
    CALL __builtin_table_set
    IADD SP, 3

    MOV  R1, [BP-6]
    IADD R1, 1
    MOV  [BP-6], R1
    JMP  __move_forward_loop

__move_backward_init:
    MOV  R1, [BP-4]
    ISUB R1, 1
    MOV  [BP-6], R1              ; counter = count - 1
    JMP  __move_backward_loop

__move_backward_loop:
    MOV  R1, [BP-6]
    ILT  R1, 0                    ; counter < 0?
    JT   R1, __move_done

    MOV  R3, [BP-1]
    MOV  R4, [BP-6]
    IADD R3, R4
    CIF  R3

    MOV  R5, [BP+6]
    PUSH R5
    PUSH R3
    CALL __builtin_table_get
    IADD SP, 2
    MOV  R6, R0

    MOV  R3, [BP-3]
    MOV  R4, [BP-6]
    IADD R3, R4
    CIF  R3

    MOV  R5, [BP-5]
    PUSH R5
    PUSH R3
    PUSH R6
    CALL __builtin_table_set
    IADD SP, 3

    MOV  R1, [BP-6]
    ISUB R1, 1
    MOV  [BP-6], R1
    JMP  __move_backward_loop

__move_done:
    MOV  R0, [BP-5]               ; R0 = resolved a2 (already boxed)

    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; SECTION: TABLE PACK
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; table.pack(...) - Packs all arguments into a new table with .n field
;;
;; This is implemented in C as it needs variable argument handling
;; Assembly version would need stack manipulation
;;
;; For now, this is a placeholder. The actual implementation should be in C
;; to handle the variable arguments properly.
;;
;; Returns: R0 = new table with .n field
;; ---------------------------------------------------------------------------
__builtin_table_pack:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: Preserve working registers ---
    PUSH R1
    PUSH R2
    PUSH R3

    ;; --- Create new table ---
    CALL __builtin_table_new
    MOV  R1, R0              ; R1 = new table

    ;; --- TODO: This needs to be implemented in C to access variable arguments ---
    ;; For now, return empty table

    ;; --- Callee-Restore ---
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; SECTION: TABLE UNPACK
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; table.unpack(t, [i], [j]) - Returns elements from table as multiple values
;;
;; Incoming Stack: [BP+4] = Tagged Table Pointer
;;                 [BP+3] = Start index (optional, may be NIL)
;;                 [BP+2] = End index (optional, may be NIL)
;; Returns: Multiple values on stack (Lua convention)
;; Register Usage: R1-R8
;; ---------------------------------------------------------------------------
__builtin_table_unpack:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: Preserve 8 working registers ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8

    ;; --- Load arguments ---
    MOV  R1, [BP+4]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+3]          ; R2 = Start index (may be NIL)
    MOV  R3, [BP+2]          ; R3 = End index (may be NIL)

    ;; --- Validate table ---
    MOV  R4, R1
    AND  R4, BOXED_DATA
    IEQ  R4, BOXED_TABLE
    JF   R4, __runtime_error_not_table

    ;; --- Unbox table pointer ---
    AND  R1, BOXED_PAYLOAD   ; R1 = raw table header address

    ;; --- Get array info ---
    MOV  R4, [R1+1]          ; R4 = array length
    MOV  R5, [R1+2]          ; R5 = array data pointer

    ;; --- Set default start index = 1 ---
    MOV  R6, R2
    IEQ  R6, BOXED_NIL
    JT   R6, __table_unpack_start_default

    CFI  R6
    JMP  __table_unpack_start_set

__table_unpack_start_default:
    MOV  R6, 1

__table_unpack_start_set:
    ;; --- Set default end index = length ---
    MOV  R7, R3
    IEQ  R7, BOXED_NIL
    JT   R7, __table_unpack_end_default

    CFI  R7
    JMP  __table_unpack_end_set

__table_unpack_end_default:
    MOV  R7, R4

__table_unpack_end_set:
    ;; --- Validate indices (use R8 for comparison results) ---
    MOV  R8, R6
    ILT  R8, 1
    JT   R8, __table_unpack_invalid_range
    MOV  R8, R4
    IGT  R8, R6
    JT   R8, __table_unpack_invalid_range
    MOV  R8, R7
    ILT  R8, R6
    JT   R8, __table_unpack_invalid_range
    MOV  R8, R4
    IGT  R8, R7
    JT   R8, __table_unpack_end_adjust
    JMP  __table_unpack_validate_done

__table_unpack_end_adjust:
    MOV  R7, R4

__table_unpack_validate_done:
    ;; --- Calculate number of elements to return ---
    MOV  R8, R7
    ISUB R8, R6
    IADD R8, 1              ; R8 = number of elements to return

    ;; --- For now, return first element (simplified) ---
    ;; TODO: Implement proper multiple return values
    MOV  R9, R5
    IADD R9, R6
    ISUB R9, 1
    MOV  R0, [R9]
    JMP  __table_unpack_done

__table_unpack_invalid_range:
    MOV  R0, BOXED_NIL

__table_unpack_done:
    ;; --- Callee-Restore ---
    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; SECTION: UTILITY FUNCTIONS
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; Helper: Validate and unbox table pointer
;; Input: R0 = Tagged table pointer
;; Output: R0 = Raw table pointer, or jump to error (R1 = original tagged
;;         value, for __runtime_error_not_table's second print line)
;; Clobbers: R1, R2
;; ---------------------------------------------------------------------------
__unbox_table_validated:
    MOV  R2, R0
    AND  R2, BOXED_DATA
    IEQ  R2, BOXED_TABLE
    JT   R2, __unbox_table_ok
    MOV  R1, R0                  ; every OTHER not_table call site already
    JMP  __runtime_error_not_table ; leaves the offending value in R1
__unbox_table_ok:
    AND  R0, BOXED_PAYLOAD
    RET

