;; ===========================================================================
;; SECTION: STRING OPERATIONS
;; ===========================================================================

;; ===========================================================================
;; Internal Helper: __unbox_string
;; Input:  R0 = NaN-boxed String (RAM or ROM)
;; Output: R0 = Raw Vircon32 Memory Address (Page bit applied if in ROM)
;; Clobbers: R1
;; ===========================================================================
__unbox_string:
    MOV R1, R0
    AND R1, BOXED_CATEGORY      ; Check Bit 31 (1 = RAM, 0 = ROM) String
    AND R0, BOXED_PAYLOAD       ; Strip the entire NaN tag (22-bit offset)

    INE R1, 0                   ; If Bit 31 is non-zero, it is a RAM string
    JT  R1, __unbox_string_end  ; Jump to end (RAM starts at 0x00000000)

    ;; It is a ROM string: Apply Vircon32 Cartridge Page Bit (Bit 29)
    OR  R0, V32_CART_PAGE

__unbox_string_end:
    RET

;; ---------------------------------------------------------------------------
;; Built-in: Tag-Aware String Concatenation with Auto-Coercion
;; Incoming Stack: [BP+3] = Left_Val, [BP+2] = Right_Val
;; Returns: R0 = Tagged pointer to newly allocated RAM heap string
;; ---------------------------------------------------------------------------
__builtin_strcat:
    PUSH BP
    MOV  BP, SP

    ;; --- Coerce Left Operand to String if Needed ---
    MOV  R0, [BP+3]          ; Load Left value
    MOV  R1, R0
    AND  R1, BOXED_DATA      ; Extract type tag
    IEQ  R1, BOXED_ROMSTRING
    JT   R1, __strcat_left_is_string
    IEQ  R1, BOXED_RAMSTRING
    JT   R1, __strcat_left_is_string
    ;; Not a string - coerce via __builtin_tostring
    PUSH R0
    CALL __builtin_tostring  ; Returns tagged string in R0
    IADD SP, 1
    CALL __unbox_string      ; R0 = raw unboxed pointer
    MOV  R7, R0              ; Cache unboxed left pointer
    JMP  __strcat_calc_left_len

__strcat_left_is_string:
    CALL __unbox_string      ; R0 = raw unboxed pointer
    MOV  R7, R0              ; Cache unboxed left pointer

__strcat_calc_left_len:
    MOV  R1, R7              ; R1 = Reading pointer
    MOV  R2, 0               ; R2 = Left length counter
__strcat_len_left:
    MOV  R3, [R1]            ; Read ASCII character
    IEQ  R3, 0
    JT   R3, __strcat_right_prep
    IADD R1, 1
    IADD R2, 1
    JMP  __strcat_len_left

    ;; --- Coerce Right Operand to String if Needed ---
__strcat_right_prep:
    MOV  R0, [BP+2]          ; Load Right value
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, BOXED_ROMSTRING
    JT   R1, __strcat_right_is_string
    IEQ  R1, BOXED_RAMSTRING
    JT   R1, __strcat_right_is_string
    ;; Not a string - coerce it
    PUSH R0
    CALL __builtin_tostring
    IADD SP, 1
    CALL __unbox_string
    MOV  R8, R0              ; Cache unboxed right pointer
    JMP  __strcat_calc_right_len

__strcat_right_is_string:
    CALL __unbox_string
    MOV  R8, R0              ; Cache unboxed right pointer

__strcat_calc_right_len:
    MOV  R1, R8              ; R1 = Reading pointer
    MOV  R4, 0               ; R4 = Right length counter
__strcat_len_right:
    MOV  R3, [R1]
    IEQ  R3, 0
    JT   R3, __strcat_alloc
    IADD R1, 1
    IADD R4, 1
    JMP  __strcat_len_right

    ;; --- 3. Allocate Memory on Heap ---
__strcat_alloc:
    MOV  R0, [HEAP_POINTER]
    MOV  R5, R0              ; R5 = Write head

    MOV  R6, R0
    IADD R6, R2
    IADD R6, R4
    IADD R6, 1
    MOV  [HEAP_POINTER], R6

    ;; --- 4. Copy Left String to Heap ---
    MOV  R1, R7
__strcat_copy_left:
    MOV  R3, [R1]
    MOV  R6, R3
    IEQ  R6, 0
    JT   R6, __strcat_copy_right_check
    MOV  [R5], R3
    IADD R1, 1
    IADD R5, 1
    JMP  __strcat_copy_left

    ;; --- 5. Copy Right String to Heap ---
__strcat_copy_right_check:
    MOV  R1, R8
__strcat_copy_right:
    MOV  R3, [R1]
    MOV  R6, R3
    IEQ  R6, 0
    JT   R6, __strcat_finish
    MOV  [R5], R3
    IADD R1, 1
    IADD R5, 1
    JMP  __strcat_copy_right

    ;; --- 6. Null-Terminate, BOX as RAM String, and Return ---
__strcat_finish:
    MOV  R3, 0
    MOV  [R5], R3            ; Write Null terminator

    OR   R0, BOXED_RAMSTRING ; BOX: R0 = new string base

    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Built-in: Lexicographical String Comparison (strcmp)
;; Incoming: R1 = Unboxed string (left), R2 = Unboxed string (right)
;; Returns: R0 = Raw integer (-1 if Left < Right
;;                             0 if Equal
;;                             1 if Left > Right)
;; ---------------------------------------------------------------------------
__builtin_strcmp:
    ;; Unbox Left Operand into R1
    MOV  R0, R1
    CALL __unbox_string
    PUSH R0                  ; Save unboxed Left pointer on stack safely

    ;; Unbox Right Operand into R2
    MOV  R0, R2
    CALL __unbox_string
    MOV  R2, R0              ; R2 = Unboxed Right pointer
    POP  R1                  ; R1 = Unboxed Left pointer

__strcmp_loop:
    MOV  R3, [R1]
    MOV  R4, [R2]

    ;; If characters differ, return difference (R3 - R4)
    INE  R3, R4
    JT   R3, __strcmp_diff

    ;; If end of string reached, strings are equal (return 0)
    IEQ  R3, 0
    JT   R3, __strcmp_equal

    IADD R1, 1
    IADD R2, 1
    JMP  __strcmp_loop

__strcmp_diff:
    ISUB R3, R4
    MOV  R0, R3              ; Return <0 if Left < Right, >0 if Left > Right
    RET

__strcmp_equal:
    MOV  R0, 0
    RET

;; ---------------------------------------------------------------------------
;; Universal Equality (==): Returns raw integer 1 (true) or 0 (false) in R0
;; Incoming Stack: [BP+3] = Left_Val, [BP+2] = Right_Val
;; ---------------------------------------------------------------------------
__builtin_eq:
    PUSH BP
    MOV  BP, SP

    MOV  R1, [BP+3]
    MOV  R2, [BP+2]

    ;; Fast-path: If bitwise identical, they are strictly equal
    IEQ  R1, R2
    JT   R1, __eq_return_true

    ;; Validate LEFT Operand is a String (Tag 0x7FC0... or 0xFFC0... with
    ;; payload >= 4)

    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_ROMSTRING
    JT   R3, __eq_left_valid

    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_RAMSTRING
    JF   R3, __eq_return_false

    MOV  R3, R1
    AND  R3, BOXED_PAYLOAD
    ILT  R3, 4
    JT   R3, __eq_return_false

__eq_left_valid:
    ;; Validate RIGHT Operand is a String
    MOV  R3, R2
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_ROMSTRING
    JT   R3, __eq_right_valid

    MOV  R3, R2
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_RAMSTRING
    JF   R3, __eq_return_false

    MOV  R3, R2
    AND  R3, BOXED_PAYLOAD
    ILT  R3, 4
    JT   R3, __eq_return_false

__eq_right_valid:
    ;; Unbox both validated string pointers!
    MOV  R0, R1
    CALL __unbox_string
    PUSH R0                  ; Save unboxed Left pointer

    MOV  R0, R2
    CALL __unbox_string
    MOV  R2, R0              ; R2 = Unboxed Right pointer
    POP  R1                  ; R1 = Unboxed Left pointer

__eq_strcmp_loop:
    MOV  R3, [R1]
    MOV  R4, [R2]

    ;; Compare current characters
    INE  R3, R4
    JT   R3, __eq_return_false   ; Characters differ -> strings not equal

    ;; Check for null terminator (0x00)
    IEQ  R3, 0
    JT   R3, __eq_return_true    ; Both hit null terminator: strings equal!

    ;; Advance pointers to next character
    IADD R1, 1
    IADD R2, 1
    JMP  __eq_strcmp_loop

__eq_return_true:
    MOV  R0, BOXED_TRUE          ; Return boxed Boolean True
    MOV  SP, BP                  ; Stack Restore
    POP  BP
    RET

__eq_return_false:
    MOV  R0, BOXED_FALSE         ; Return boxed Boolean False
    MOV  SP, BP                  ; Stack Restore
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Length Operator Dispatch (#): Returns length as an IEEE 754 Float in R0 
;; Incoming Stack: [BP+2] = Target Value 
;; ---------------------------------------------------------------------------
;; ===========================================================================
;; Runtime Built-in: __builtin_len
;; ABI: Arg 1 at [BP+2] (Stack Parameter), Caller cleans up.
;; Returns: R0 = Length of string as a Lua Float.
;; ===========================================================================
__builtin_len:
    PUSH BP
    MOV  BP, SP

    ;; 1. Fetch argument from caller's stack frame
    ;; [BP+0] is old BP, [BP+1] is Return Address, [BP+2] is Arg 1
    MOV  R0, [BP+2]

    ;; 2. Unbox to get raw hardware address
    ;; (handles RAM vs ROM automatically)
    CALL __unbox_string

    ;; 3. Calculate string length
    MOV  R1, 0                  ; R1 = Character counter
__len_loop:
    MOV  R2, [R0]               ; Read character from address
    IEQ  R2, 0                  ; Is it null terminator?
    JT   R2, __len_done
    IADD R0, 1                  ; Advance pointer
    IADD R1, 1                  ; Increment counter
    JMP  __len_loop

__len_done:
    ;; 4. Convert integer count in R1 to a Vircon32 Float in R0
    MOV  R0, R1
    CIF  R0                     ; Cast Integer to Float (Standard Lua number)

    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Universal Type Serializer: Converts any tagged value to a String pointer 
;; Incoming Stack: [BP+2] = Target Value 
;; ---------------------------------------------------------------------------
__builtin_tostring:
    PUSH BP
    MOV  BP, SP
    
    MOV  R1, [BP+2]          ; Load argument from Base Pointer

    MOV  R3, R1
    AND  R3, BOXED_DATA

    ;; Pass through ROM Strings unchanged
    IEQ  R3, BOXED_ROMSTRING
    JT   R3, __tostring_passthrough

    MOV  R3, R1
    AND  R3, BOXED_DATA

    ;; Check for RAM Strings
    IEQ  R3, BOXED_RAMSTRING
    JF   R3, __tostring_check_primitives

    MOV  R4, R1
    AND  R4, BOXED_PAYLOAD
    IGE  R4, 4
    JT   R4, __tostring_passthrough  ; It is a RAM String: return unchanged!

__tostring_check_primitives:
    ;; Check for nil/false/true
    MOV  R6, R1
    IEQ  R6, BOXED_NIL
    JT   R6, __tostring_nil
    MOV  R6, R1
    IEQ  R6, BOXED_FALSE
    JT   R6, __tostring_false
    MOV  R6, R1
    IEQ  R6, BOXED_TRUE
    JT   R6, __tostring_true

    ;; Check for Table/Function (optional - remove if you don't need them)
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_TABLE
    JT   R3, __tostring_table

    MOV  R3, R1                 ; this was missing, adding
    AND  R3, BOXED_DATA         ; this was missing, adding
    IEQ  R3, BOXED_FUNCTION
    JT   R3, __tostring_function

    ;; Fall through: It's a float
    PUSH R1
    CALL __builtin_ftoa
    IADD SP, 1
    OR   R0, BOXED_RAMSTRING
    JMP  __tostring_done

__tostring_nil:
    MOV  R0, __const_str_nil ; Load address of static "nil" string 
    OR   R0, BOXED_ROMSTRING      ; Box as String 
    JMP  __tostring_done

__tostring_false:
    MOV  R0, __const_str_false ; Load address of static "false" string 
    OR   R0, BOXED_ROMSTRING      ; Box as String 
    JMP  __tostring_done

__tostring_true:
    MOV  R0, __const_str_true ; Load address of static "true" string 
    OR   R0, BOXED_ROMSTRING      ; Box as String 
    JMP  __tostring_done

__tostring_passthrough:
    MOV  R0, R1                  ; Return string pointer exactly as received
    MOV  SP, BP
    POP  BP
    RET

__tostring_table:
    MOV  SP, BP
    POP  BP
    JMP  __format_table_address 

__tostring_function:
    MOV  SP, BP
    POP  BP
    JMP  __format_function_address 
    
__tostring_done:
    MOV  SP, BP
    POP  BP
    RET

__format_table_address:
    PUSH BP
    MOV  BP, SP

    MOV  R0, __const_str_table
    OR   R0, BOXED_ROMSTRING      ; Box raw pointer as a valid Lua String

    MOV  SP, BP
    POP  BP
    RET

__format_function_address:
    PUSH BP
    MOV  BP, SP

    MOV  R0, __const_str_function
    OR   R0, BOXED_ROMSTRING      ; Box raw pointer as a valid Lua String

    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Built-in: Float to ASCII (Full Floating Point Support)
;; Incoming Stack: [BP+2] = Raw IEEE754 Float
;; Returns: R0 = Raw Heap Pointer to null-terminated ASCII string
;; Registers: R0-R13 (R14/BP and R15/SP preserved)
;; ---------------------------------------------------------------------------
__builtin_ftoa:
    PUSH BP
    MOV  BP, SP

    ;; --- Allocate buffer (32 bytes for integer + fractional + null) ---
    MOV  R0, 32
    PUSH R0
    CALL __malloc
    IADD SP, 1

    ;; 1. Trap OOM to prevent HEAP_POINTER corruption at address 0
    MOV  R4, R0
    IEQ  R4, 0
    JT   R4, __oom_handler

    ;; R2 is unused in this routine- use it to lock in the base pointer
    MOV  R2, R0
    MOV  R9, R2              ; R9 = write head

    ;; --- Unbox the float value first ---
    MOV  R3, [BP+2]          ; R3 = value from stack

    ;; --- Handle sign ---
    MOV  R4, R3              ; Copy to R4 for sign check
    FLT  R4, 0.0
    JF   R4, __ftoa_positive

    ;; Negative: write '-' and use absolute value
    MOV  R5, 45              ; ASCII '-'
    MOV  [R9], R5
    IADD R9, 1
    FABS R3                  ; R3 = |float value|
    JMP  __ftoa_extract_int

__ftoa_positive:
    ;; --- Extract integer part ---
__ftoa_extract_int:
    MOV  R4, R3              ; Copy float to R4
    CFI  R4                  ; Convert to integer (truncates toward zero)
    MOV  R7, R4              ; Use R7 for integer value

    ;; Check if integer part is zero
    MOV  R5, R7
    INE  R5, 0
    JT   R5, __ftoa_write_int_digits

    ;; Integer part is zero: write single '0'
    MOV  R5, 48              ; ASCII '0'
    MOV  [R9], R5
    IADD R9, 1
    MOV  R6, R9              ; R6 = start of integer digits (points to '0')
    JMP  __ftoa_check_fraction

__ftoa_write_int_digits:
    MOV  R6, R9              ; R6 = start of integer digits (for reversal)

    ;; Extract digits in reverse order (LSB first)
__ftoa_int_loop:
    MOV  R5, R7              ; Copy current integer value
    INE  R5, 0
    JF   R5, __ftoa_reverse_int

    ;; Get next digit (LSB)
    MOV  R5, R7
    IMOD R5, 10
    IADD R5, 48              ; Convert to ASCII
    MOV  [R9], R5
    IADD R9, 1

    ;; Divide by 10 for next iteration
    IDIV R7, 10              ; R7 is consumed here
    JMP  __ftoa_int_loop

    ;; Reverse integer digits (they were written LSB first)
__ftoa_reverse_int:
    MOV  R10, R6             ; R10 = start of digits
    MOV  R11, R9
    ISUB R11, 1              ; R11 = end of digits
__ftoa_reverse_int_loop:
    ;; 3. Protect R10 from destructive comparison!
    MOV  R4, R10
    IGE  R4, R11
    JT   R4, __ftoa_check_fraction

    ;; Swap [R10] and [R11]
    MOV  R12, [R10]
    MOV  R13, [R11]
    MOV  [R10], R13
    MOV  [R11], R12

    IADD R10, 1
    ISUB R11, 1
    JMP  __ftoa_reverse_int_loop

__ftoa_check_fraction:
    ;; --- Check if there's a fractional part ---
    MOV  R5, R3              ; Original float

    ;; 4. R7 was destroyed by the division loop!
    ;; Re-extract the integer safely from the original float.
    MOV  R6, R3
    CFI  R6                  ; Convert to int
    CIF  R6                  ; Cast back to float
    FSUB R5, R6              ; R5 = precise fractional part

    ;; If fractional part is very small, we're done
    MOV  R4, R5              ; ← Backup fractional part to R4
    MOV  R6, 0.000001
    FLT  R4, R6
    JT   R4, __ftoa_done

    ;; Write decimal point
    MOV  R6, 46              ; ASCII '.'
    MOV  [R9], R6
    IADD R9, 1

    ;; Scale fractional part to integer (6 decimal places)
    MOV  R6, 1000000.0
    FMUL R5, R6              ; R5 = fractional * 1,000,000
    CFI  R5                  ; Convert to integer

    ;; Save start of fractional digits for reversal
    MOV  R1, R9              ; R1 = start of fractional digits

    ;; Extract fractional digits (LSB first, will reverse later)
    MOV  R6, 6               ; Counter for 6 digits
__ftoa_extract_frac:
    MOV  R12, R5
    IMOD R12, 10
    IADD R12, 48
    MOV  [R9], R12
    IADD R9, 1

    IDIV R5, 10
    ISUB R6, 1
    MOV  R4, R6
    IGT  R4, 0
    JT   R4, __ftoa_extract_frac

    ;; Reverse fractional digits
    MOV  R10, R1             ; R10 = start of fractional digits
    MOV  R11, R9
    ISUB R11, 1
__ftoa_reverse_frac_loop:
    ;; 5. Protect R10 from destructive comparison again!
    MOV  R4, R10
    IGE  R4, R11
    JT   R4, __ftoa_done

    ;; Swap [R10] and [R11]
    MOV  R12, [R10]
    MOV  R13, [R11]
    MOV  [R10], R13
    MOV  [R11], R12

    IADD R10, 1
    ISUB R11, 1
    JMP  __ftoa_reverse_frac_loop

    ;; --- Null-terminate and return ---
__ftoa_done:
    MOV  R10, 0
    MOV  [R9], R10           ; Null terminator

    ;; Return the securely preserved base pointer
    MOV  R0, R2
    MOV  SP, BP
    POP  BP
    RET

