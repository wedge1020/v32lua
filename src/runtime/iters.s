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

    ;; --- Validate table ---
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_TABLE
    JF   R3, __next_error_not_table
    AND  R1, BOXED_PAYLOAD   ; R1 = raw table header address (unboxed for good)

    MOV  R6, [R1+3]          ; R6 = Base Hash Data Pointer
    MOV  R3, R6               ; Test on scratch R3 to preserve R6 pointer
                              ; (IEQ is destructive -- overwrites its first
                              ; operand with the 0/1 result. The original
                              ; code tested R6 directly here, which is
                              ; exactly the class of bug __builtin_table_get
                              ; and __builtin_table_set's equivalent checks
                              ; already guard against with a scratch
                              ; register -- this was the one spot in
                              ; __builtin_next that didn't get the same
                              ; treatment.)
    IEQ  R3, 0
    JT   R3, __next_done_nil  ; No hash storage at all -> table is empty

    ;; --- R8 = "still searching for R2" flag ---
    ;; If R2 is NIL, we want the very first live entry -- we're already
    ;; "past" the search key. Otherwise we must scan until we see R2
    ;; itself before considering anything a candidate.
    MOV  R8, R2
    IEQ  R8, BOXED_NIL
    JT   R8, __next_seeking_done
    MOV  R8, 1
    JMP  __next_scan_bucket
__next_seeking_done:
    MOV  R8, 0

__next_scan_bucket:
    MOV  R4, [R6]              ; R4 = PairCount in this bucket
    MOV  R7, R6
    IADD R7, 2                 ; R7 = running pointer to Key0

__next_scan_pair:
    MOV  R3, R4
    IEQ  R3, 0
    JT   R3, __next_next_bucket   ; No more pairs in this bucket

    MOV  R5, [R7]               ; R5 = stored key at this slot

    MOV  R3, R8
    IEQ  R3, 0
    JT   R3, __next_have_target  ; not seeking anymore -> this slot is a candidate

    ;; Still seeking: is this slot the key we're looking for?
    MOV  R3, R5
    IEQ  R3, R2
    JF   R3, __next_advance_pair
    MOV  R8, 0                  ; Found it -- next live slot is our candidate
    JMP  __next_advance_pair

__next_have_target:
    ;; This slot is a candidate. Skip it if its value is nil (deleted key).
    MOV  R3, [R7+1]
    IEQ  R3, BOXED_NIL
    JT   R3, __next_advance_pair

    ;; Live entry -- this is the result.
    MOV  R0, R5                 ; R0 = key
    MOV  R2, [R7+1]             ; R2 = value
    JMP  __next_done

__next_advance_pair:
    IADD R7, 2
    ISUB R4, 1
    JMP  __next_scan_pair

__next_next_bucket:
    MOV  R3, [R6+1]              ; R3 = NextBucketPtr
    IEQ  R3, 0
    JT   R3, __next_done_nil     ; End of chain, nothing left
    MOV  R6, R3
    JMP  __next_scan_bucket

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

