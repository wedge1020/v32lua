;; ===========================================================================
;; Built-in: next(t, [k]) - Table iterator for pairs()
;;
;; Incoming Stack: [BP+3] = Tagged Table Pointer, [BP+2] = Key (or NIL)
;; Returns: R0 = next key (boxed), pushes next value on stack
;;          If no more elements, returns BOXED_NIL
;; Register Usage: R1-R8
;; ===========================================================================
__builtin_next:
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
    MOV  R1, [BP+3]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+2]          ; R2 = Current Key (or NIL for first call)

    ;; --- Validate table ---
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_TABLE
    JF   R3, __next_error_not_table

    ;; --- Unbox table pointer ---
    AND  R1, BOXED_PAYLOAD   ; R1 = raw table header address

    ;; --- Check if key is NIL (first iteration) ---
    MOV  R3, R2
    IEQ  R3, BOXED_NIL
    JT   R3, __next_first_key

    ;; --- Key is not NIL: find NEXT key after R2 ---
    ;; Use table_get to find the next key
    ;; For now, we'll do a linear scan through all keys
    MOV  R4, [R1+1]          ; R4 = array length
    CFI  R4                 ; Convert to integer

    ;; Check if we should start from array part
    MOV  R5, R2
    CFI  R5
    ILT  R5, 1
    JT   R5, __next_check_hash

    ;; We're in numeric range - find next numeric key
    IADD R5, 1               ; Next index
    ILE  R5, R4
    JT   R5, __next_array_found

    ;; Fall through to hash check
    JMP  __next_check_hash

__next_first_key:
    ;; First call: return first array element or first hash key
    MOV  R4, [R1+1]          ; R4 = array length
    CFI  R4
    IGT  R4, 0
    JT   R4, __next_array_first

    ;; No array elements, check hash
    JMP  __next_check_hash_first

__next_array_first:
    MOV  R5, 1               ; Start at index 1
__next_array_found:
    ;; Get value at index R5
    MOV  R6, [R1+2]          ; R6 = Array Data Pointer
    ISUB R7, R5, 1           ; Convert to 0-based
    IADD R6, R7
    MOV  R0, [R6]            ; Value

    ;; Push value on stack
    PUSH R0

    ;; Return key (R5) as boxed float
    MOV  R0, R5
    CIF  R0
    JMP  __next_done

__next_check_hash_first:
    MOV  R5, 0               ; Signal first hash key
    JMP  __next_scan_hash

__next_check_hash:
    ;; Find next key in hash table after R2
    ;; This is a simplified implementation
    MOV  R6, [R1+3]          ; R6 = Base Hash Data Pointer
    IEQ  R6, 0
    JT   R6, __next_done_nil  ; No hash table

    MOV  R7, R6              ; R7 = running pointer
    IADD R7, 2               ; Skip to first key

    MOV  R8, 0               ; R8 = found flag
__next_scan_hash:
    MOV  R9, [R6]            ; R9 = PairCount
    IEQ  R9, 0
    JT   R9, __next_hash_done

    MOV  R4, 0               ; Counter
__next_scan_loop:
    MOV  R3, [R7]            ; R3 = current key
    IEQ  R3, 0
    JT   R3, __next_hash_done_inner

    ;; Check if this is the key we're looking for (for non-first calls)
    MOV  R5, R2
    IEQ  R5, BOXED_NIL
    JF   R5, __next_check_match

    ;; First call: return first key
    MOV  R8, 1               ; Found
    JMP  __next_hash_found

__next_check_match:
    IEQ  R3, R5
    JF   R3, __next_not_match
    MOV  R8, 1               ; Found next key
    JMP  __next_hash_found_next
__next_not_match:
    IADD R7, 2               ; Skip to next key
    IADD R4, 1
    JMP  __next_scan_loop

__next_hash_found_next:
    IADD R7, 2               ; Skip to next key
    IADD R4, 1
    JMP  __next_scan_loop

__next_hash_found:
    ;; R3 = key, R7 points to key, next value is at R7+1
    IADD R7, 1
    MOV  R0, [R7]            ; Value
    PUSH R0

    MOV  R0, R3
    CIF  R0
    JMP  __next_done

__next_hash_done_inner:
    IADD R6, 16              ; Move to next bucket (16 words = header + 7 pairs)
    MOV  R7, R6
    IADD R7, 2
    JMP  __next_scan_hash

__next_hash_done:
    ;; No more hash keys
    ;; If we were looking for next after a key, check if we've checked all
    MOV  R5, R2
    IEQ  R5, BOXED_NIL
    JT   R5, __next_done_nil

    ;; We've exhausted hash, try array from start
    MOV  R4, [R1+1]
    CFI  R4
    IGT  R4, 0
    JF   R4, __next_done_nil

    MOV  R5, 1
    JMP  __next_array_found

__next_done_nil:
    MOV  R0, BOXED_NIL

__next_done:
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

__next_error_not_table:
    JMP __next_error_not_table
    HLT

;; ===========================================================================
;; Built-in: ipairs_iter(t, index) - Numeric iterator for ipairs()
;;
;; Incoming Stack: [BP+3] = Tagged Table Pointer, [BP+2] = Current Index
;; Returns: R0 = next index (boxed), pushes value on stack
;;          Returns BOXED_NIL when index > array length
;; Register Usage: R1-R5
;; ===========================================================================
__builtin_ipairs_iter:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5

    ;; --- Load arguments ---
    MOV  R1, [BP+3]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+2]          ; R2 = Current Index

    ;; --- Validate table ---
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_TABLE
    JF   R3, __ipairs_iter_error

    ;; --- Unbox table pointer ---
    AND  R1, BOXED_PAYLOAD   ; R1 = raw table header address

    ;; --- Get array length ---
    MOV  R3, [R1+1]          ; R3 = array length (as float)
    CIF  R3                 ; Ensure it's a float
    CFI  R3                 ; Convert to integer

    ;; --- Check if current index is valid ---
    MOV  R4, R2
    CFI  R4                 ; Convert index to integer

    ;; If index is NIL (shouldn't happen for ipairs, but handle it)
    MOV  R5, R2
    IEQ  R5, BOXED_NIL
    JT   R5, __ipairs_iter_start

    ;; Normal case: increment index
    IADD R4, 1               ; Next index

    ;; Check if next index exceeds array length
    IGT  R4, R3
    JT   R4, __ipairs_iter_done_nil

    JMP  __ipairs_iter_get_value

__ipairs_iter_start:
    ;; First call: start at index 1
    MOV  R4, 1
    IGT  R4, R3
    JT   R4, __ipairs_iter_done_nil

__ipairs_iter_get_value:
    ;; Get value at index R4 from array
    MOV  R5, [R1+2]          ; R5 = Array Data Pointer
    IEQ  R5, 0
    JT   R5, __ipairs_iter_done_nil  ; No array allocated

    ;; Calculate address: array_ptr + (index - 1)
    MOV  R2, R4
    ISUB R2, 1
    IADD R5, R2

    ;; Load value
    MOV  R0, [R5]
    PUSH R0                  ; Push value on stack

    ;; Return next index as boxed float
    MOV  R0, R4
    CIF  R0
    JMP  __ipairs_iter_done

__ipairs_iter_done_nil:
    MOV  R0, BOXED_NIL

__ipairs_iter_done:
    ;; --- Callee-Restore ---
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

__ipairs_iter_error:
    JMP __ipairs_iter_error
    HLT
