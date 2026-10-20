;; ===========================================================================
;; Built-in: next(table, key) - Stateless iterator used by pairs()
;;
;; Incoming Stack (post-FIX-3): [BP+2] = Tagged Table Pointer (state, now
;; the first formal parameter to match how ordinary Lua functions receive
;; their parameters -- see node_for_generic()'s FIX 3 comment in v32lua.c),
;; [BP+3] = Current Key (or NIL for first call).
;; Returns: R0 = key, R2 = value (or R0 = NIL when exhausted)
;; ===========================================================================
__builtin_next:
    ;; Order: the array part (keys 1..capacity with a value), then the hash
    ;; part's slots in slot order. See "TABLE STORAGE" in table.s.
    PUSH BP
    MOV  BP, SP
    PUSH R1
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8

    MOV  R1, [BP+2]          ; R1 = Tagged Table Pointer (state)
    MOV  R2, [BP+3]          ; R2 = Current Key (or NIL for first call)
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_TABLE
    JF   R3, __next_error_not_table
    AND  R1, BOXED_PAYLOAD

    MOV  R7, [R1]
    AND  R7, TABLE_ARRAYSIZE ; R7 = array capacity
    MOV  R6, 0               ; R6 = array index to resume at (0-based)
    MOV  R3, R2
    IEQ  R3, BOXED_NIL
    JT   R3, __next_array
    ;; a whole-number key inside the array part?
    MOV  R3, R2
    AND  R3, NAN_VALUE
    IEQ  R3, NAN_VALUE
    JT   R3, __next_from_hash
    MOV  R3, R2
    CFI  R3
    MOV  R4, R3
    CIF  R4
    INE  R4, R2
    JT   R4, __next_from_hash
    MOV  R4, R3
    ILT  R4, 1
    JT   R4, __next_from_hash
    MOV  R4, R3
    IGT  R4, R7
    JT   R4, __next_from_hash
    MOV  R6, R3              ; resume after key k -> index k

__next_array:
    MOV  R8, [R1+2]
__next_array_loop:
    MOV  R3, R6
    IGE  R3, R7
    JT   R3, __next_hash_start
    MOV  R3, R8
    IADD R3, R6
    MOV  R2, [R3]
    MOV  R3, R2
    IEQ  R3, BOXED_NIL
    JF   R3, __next_array_hit
    IADD R6, 1
    JMP  __next_array_loop
__next_array_hit:
    MOV  R0, R6
    IADD R0, 1
    CIF  R0                  ; key = index + 1 (value already in R2)
    JMP  __next_done

__next_from_hash:
    MOV  R5, [R1+3]
    MOV  R3, R5
    IEQ  R3, 0
    JT   R3, __next_done_nil
    MOV  R3, R2
    IEQ  R3, 0x80000000      ; -0 == 0
    JF   R3, __next_find
    MOV  R2, 0
__next_find:
    CALL __table_hash_find   ; R0 = slot address of the current key, or 0
    MOV  R3, R0
    IEQ  R3, 0
    JT   R3, __next_done_nil
    ISUB R0, R5
    ISUB R0, 2
    SHL  R0, -1
    MOV  R6, R0
    IADD R6, 1               ; resume at the following slot
    JMP  __next_hash_loop_init

__next_hash_start:
    MOV  R6, 0
__next_hash_loop_init:
    MOV  R5, [R1+3]
    MOV  R3, R5
    IEQ  R3, 0
    JT   R3, __next_done_nil
    MOV  R7, [R5]            ; hash capacity
__next_hash_loop:
    MOV  R3, R6
    IGE  R3, R7
    JT   R3, __next_done_nil
    MOV  R4, R6
    SHL  R4, 1
    IADD R4, R5
    IADD R4, 2               ; slot address
    MOV  R0, [R4]
    MOV  R3, R0
    IEQ  R3, BOXED_NIL
    JT   R3, __next_hash_next
    MOV  R2, [R4+1]
    MOV  R3, R2
    IEQ  R3, BOXED_NIL
    JF   R3, __next_done       ; live entry: R0 = key, R2 = value
__next_hash_next:
    IADD R6, 1
    JMP  __next_hash_loop

__next_done_nil:
    MOV  R0, BOXED_NIL

__next_done:
    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R1
    MOV  SP, BP
    POP  BP
    RET

__next_error_not_table:
    HLT
    JMP __next_error_not_table

;; ===========================================================================
;; Built-in: ipairs_iter(t, index) - Numeric iterator for ipairs()
;;
;; Incoming Stack (post-FIX-3): [BP+2] = Tagged Table Pointer (state, now
;; the first formal parameter, matching node_for_generic()'s FIX 3),
;; [BP+3] = Current Index.
;; Returns: R0 = next index (boxed float, or BOXED_NIL when done),
;;          R2 = value at that index (2-value return via R0/R2, matching
;;          this compiler's standard multi-return convention -- see
;;          node_return() in v32lua.c)
;; Register Usage: R1-R7
;;
;; IMPLEMENTATION NOTE: fetches the value via __builtin_table_get rather
;; than reading through the table's array-data-pointer header field
;; directly. That field is always null in this runtime (real array
;; allocation is still a __builtin_table_set_reallocate TODO), so the
;; previous direct-array-read version returned garbage for every table
;; with a nonzero tracked length.
;; ===========================================================================
__builtin_ipairs_iter:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save ---
    PUSH R1
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7

    ;; --- Load arguments ---
    MOV  R1, [BP+2]          ; R1 = Tagged Table Pointer (kept BOXED for table_get)
    MOV  R2, [BP+3]          ; R2 = Current Index (boxed float, or NIL for first call)

    ;; --- Validate table ---
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_TABLE
    JF   R3, __ipairs_iter_error

    MOV  R4, R1
    AND  R4, BOXED_PAYLOAD   ; R4 = raw table header address (R1 stays boxed)

    ;; --- Get tracked contiguous array length (Word 1) ---
    MOV  R5, [R4+1]

    ;; --- Compute next index into R6 ---
    MOV  R6, R2
    IEQ  R6, BOXED_NIL
    JT   R6, __ipairs_iter_start

    MOV  R6, R2
    CFI  R6
    IADD R6, 1                ; Next index

    JMP  __ipairs_iter_check_bounds

__ipairs_iter_start:
    MOV  R6, 1                ; First call: start at index 1

__ipairs_iter_check_bounds:
    MOV  R7, R6
    IGT  R7, R5
    JT   R7, __ipairs_iter_done_nil   ; Next index exceeds length -> done

    ;; --- Fetch value at index R6 via __builtin_table_get ---
    MOV  R7, R6
    CIF  R7                   ; R7 = boxed float key
    PUSH R1                   ; Arg1: Table Pointer (boxed)
    PUSH R7                   ; Arg2: Key
    CALL __builtin_table_get
    IADD SP, 2

    MOV  R2, R0                ; R2 = fetched value (2nd return value)
    MOV  R0, R6
    CIF  R0                    ; R0 = next index as boxed float (1st return value)
    JMP  __ipairs_iter_done

__ipairs_iter_done_nil:
    MOV  R0, BOXED_NIL

__ipairs_iter_done:
    ;; --- Callee-Restore ---
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

__ipairs_iter_error:
    HLT
    JMP __ipairs_iter_error

