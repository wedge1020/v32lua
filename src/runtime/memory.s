;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Vircon32 NaN-Boxed Routines for Lua Runtime Environment (runtime.s)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ===========================================================================
;; SECTION: DEFINES
;; ===========================================================================
;;  V32_CART_PAGE   0x20000000
;;  NAN_VALUE       0x7F800000
;;  BOXED_CATEGORY  0x80000000 // sign bit used for RAM (1) vs ROM (0)
;;  BOXED_TYPE      0x00400000 // TABLE/FUNCTION (0) vs STRING (1)
;;  BOXED_DATA      0xFFC00000 // common bitmask to indicate boxed data
;;  BOXED_FUNCTION  0x7F800000 // bitmask for boxed lua function (ROM)
;;  BOXED_ROMSTRING 0x7FC00000 // bitmank for boxed lua string literal (ROM)
;;  BOXED_TABLE     0xFF800000 // bitmask for boxed lua table (RAM)
;;  BOXED_RAMSTRING 0xFFC00000 // starts at offset 4 (includes nil/false/true)
;;  BOXED_NIL       0xFFC00000
;;  BOXED_FALSE     0xFFC00001
;;  BOXED_BOOLEAN   0xFFC00001 // mathing our way to true/false
;;  BOXED_TRUE      0xFFC00002
;;  BOXED_TOMBSTONE 0xFFC00003 // future feature
;;  BOXED_PAYLOAD   0x003FFFFF
;;  TABLE_ARRAYSIZE 0x0000FFFF

;; ===========================================================================
;; SECTION: MEMORY MANAGEMENT & ERROR HANDLING
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; Memory Allocator: Carves out raw word blocks from HEAP_POINTER
;; Incoming Stack: [BP+2] = Number of words requested
;; Returns: R0 = Raw pointer to allocated memory (or 0 if Out-Of-Memory)
;; ---------------------------------------------------------------------------
__malloc:
    PUSH BP
    MOV  BP, SP
    
    MOV  R1, [BP+2]          ; R1 = Requested size in words
    MOV  R0, [HEAP_POINTER]  ; R0 = Address of new allocation block
    
    ;; Calculate potential new heap top
    MOV  R2, R0
    IADD R2, R1              ; R2 = Potential new HEAP_POINTER
    
    ;; Stack Collision Check: SP grows down, Heap grows up!
    ;; We maintain a 1024-word safety buffer between Heap and Stack.
    MOV  R3, SP
    ISUB R3, 1024            ; R3 = Lowest safe memory address for stack
    MOV  R6, R2
    IGE  R6, R3              ; Will the new heap top collide with the stack?
    JT   R6, __malloc_oom    ; If Heap >= SafeBoundary, allocation fails!
    
    ;; Success: Commit new heap top and return base address in R0
    MOV  [HEAP_POINTER], R2
    JMP  __malloc_done
    
__malloc_oom:
    MOV  R0, 0               ; Return 0 to signal Out-Of-Memory to caller
    
__malloc_done:
    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Out-Of-Memory Handler: Safely halts execution when memory is exhausted
;; ---------------------------------------------------------------------------
__oom_handler:
    ;; Note: If you implement an error print routine later, call it here!
    HLT                      ; Halt Vircon32 CPU instantly to prevent data corruption
    JMP  __oom_handler       ; Infinite loop safeguard in case CPU resumes

;; ---------------------------------------------------------------------------
;; Built-in: Unary Minus (-x) -> Flips IEEE-754 Sign Bit 
;; Incoming Stack: [BP+2] = Tagged Value (Expected Float) 
;; Returns: R0 = Negated Float 
;; ---------------------------------------------------------------------------
__builtin_unm:
    PUSH BP 
    MOV  BP, SP 

    MOV  R1, [BP+2]          ; R1 = Value to negate 
    XOR  R1, 0x80000000      ; Instantly changes positive <-> negative 
    MOV  R0, R1 
    
    MOV  SP, BP 
    POP  BP 
    RET 

;; ---------------------------------------------------------------------------
;; Length Operator Dispatch (#): Returns length as IEEE 754 Float in R0
;; Incoming Stack: [BP+2] = Target Value
;; Handles: strings, tables, and returns 0 for other types
;; ---------------------------------------------------------------------------
__builtin_len:
    PUSH BP
    MOV  BP, SP

    MOV  R0, [BP+2]            ; Load argument

    ;; --- Type check: Is it a TABLE? ---
    MOV  R1, R0
    AND  R1, BOXED_DATA        ; Extract tag bits
    IEQ  R1, BOXED_TABLE
    JT   R1, __builtin_len_table

    ;; --- Type check: Is it a STRING (ROM or RAM)? ---
    MOV  R1, R0
    AND  R1, BOXED_DATA        ; Extract tag bits
    IEQ  R1, BOXED_ROMSTRING
    JT   R1, __builtin_len_string

    MOV  R1, R0
    AND  R1, BOXED_DATA        ; Extract tag bits
    IEQ  R1, BOXED_RAMSTRING
    JT   R1, __builtin_len_string

    ;; --- Default: Not a string or table (number, boolean, nil, function) ---
    MOV  R0, 0                 ; Return 0 as integer
    CIF  R0                    ; Convert to float
    JMP  __builtin_len_done

__builtin_len_string:
    PUSH R0                    ; need to repush the boxed pointer
    CALL __builtin_string_len  ; String length handler
    JMP  __builtin_len_done

__builtin_len_table:
    PUSH R0                    ; need to repush the boxed pointer
    CALL __builtin_table_len   ; Table length handler
    ; R0 already contains float result from __builtin_table_len

__builtin_len_done:
    MOV  SP, BP
    POP  BP
    RET

__builtin_type:
    PUSH BP
    MOV  BP, SP

    MOV  R0, [BP+2]          ; Load argument into R0

    ;; --- Check exact values for primitives FIRST ---
    MOV  R1, R0
    IEQ  R1, BOXED_NIL
    JT   R1, __type_nil

    MOV  R1, R0
    IEQ  R1, BOXED_FALSE
    JT   R1, __type_boolean

    MOV  R1, R0
    IEQ  R1, BOXED_TRUE
    JT   R1, __type_boolean

    ;; --- Check for number (unboxed float) ---
    MOV  R1, R0
    AND  R1, 0x7F800000      ; NaN/boxed tag mask
    IEQ  R1, 0
    JT   R1, __type_number

    ;; --- Check for ROM string ---
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, BOXED_ROMSTRING
    JT   R1, __type_string

    ;; --- Check for RAM string: tag 0xFFC00000 AND payload >= 4 ---
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, 0xFFC00000      ; Same tag as NIL, but we already ruled out exact NIL
    JF   R1, __type_check_table
    MOV  R1, R0
    AND  R1, BOXED_PAYLOAD   ; Extract lower 22 bits
    IGE  R1, 4               ; RAM strings start at payload 4
    JT   R1, __type_string

__type_check_table:
    ;; --- Check for table ---
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, BOXED_TABLE
    JT   R1, __type_table

    ;; --- Check for function ---
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, BOXED_FUNCTION
    JT   R1, __type_function

    ;; --- Fallthrough: unknown ---
    MOV  R0, __const_str_nil
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_nil:
    MOV  R0, __const_str_nil
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_boolean:
    MOV  R0, __const_str_boolean
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_number:
    MOV  R0, __const_str_number
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_string:
    MOV  R0, __const_str_string
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_table:
    MOV  R0, __const_str_table
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_function:
    MOV  R0, __const_str_function
    OR   R0, BOXED_ROMSTRING

__type_done:
    MOV  SP, BP
    POP  BP
    RET

