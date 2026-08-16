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
;; Incoming Stack: [BP+3] = Left_Val (any Lua type), [BP+2] = Right_Val (any Lua type)
;; Returns: R0 = Tagged pointer to newly allocated RAM heap string (0xFFC..)
;; Clobbers: R0-R8
;; ---------------------------------------------------------------------------
__builtin_strcat:
    PUSH BP
    MOV  BP, SP

    ;; === Type-check and coerce LEFT operand if needed ===
    MOV  R1, [BP+3]          ; Load Left value
    MOV  R3, R1
    AND  R3, BOXED_DATA      ; Extract tag
    IEQ  R3, BOXED_ROMSTRING
    JT   R3, __strcat_left_is_string
    IEQ  R3, BOXED_RAMSTRING
    JT   R3, __strcat_left_is_string

    ;; Not a string - coerce it via __builtin_tostring
    PUSH R1
    CALL __builtin_tostring  ; Returns string in R0
    IADD SP, 1
    MOV  R1, R0              ; R1 = string version
    MOV  [BP+3], R1          ; Replace left operand on stack

__strcat_left_is_string:

    ;; === Type-check and coerce RIGHT operand if needed ===
    MOV  R1, [BP+2]          ; Load Right value
    MOV  R3, R1
    AND  R3, BOXED_DATA      ; Extract tag
    IEQ  R3, BOXED_ROMSTRING
    JT   R3, __strcat_right_is_string
    IEQ  R3, BOXED_RAMSTRING
    JT   R3, __strcat_right_is_string

    ;; Not a string - coerce it via __builtin_tostring
    PUSH R1
    CALL __builtin_tostring  ; Returns string in R0
    IADD SP, 1
    MOV  R1, R0              ; R1 = string version
    MOV  [BP+2], R1          ; Replace right operand on stack

__strcat_right_is_string:

    ;; === Original string concatenation logic continues ===
    MOV  R0, [BP+3]          ; Load Left tagged pointer
    CALL __unbox_string      ; R0 = raw hardware address (ROM or RAM)
    MOV  R7, R0              ; Cache unboxed Left pointer in R7
    MOV  R1, R7              ; R1 = Reading pointer
    MOV  R2, 0               ; R2 = Left length counter

__strcat_len_left:
    MOV  R3, [R1]            ; Read ASCII character
    IEQ  R3, 0
    JT   R3, __strcat_len_right_check
    IADD R1, 1
    IADD R2, 1
    JMP  __strcat_len_left

    ;; --- 2. Unbox and Calculate Length of Right String ---
__strcat_len_right_check:
    MOV  R0, [BP+2]          ; Load Right tagged pointer
    CALL __unbox_string
    MOV  R8, R0              ; Cache unboxed Right pointer in R8
    MOV  R1, R8
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
    MOV  R0, [HEAP_POINTER]  ; R0 = New string base (raw pointer)
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
    MOV  R3, [R1]           ; Load left char
    MOV  R4, [R2]           ; Load right char

    ; Check for end of left string
    MOV  R5, R3             ; Use R5 as temp to preserve R3
    IEQ  R5, 0
    JT   R5, __strcmp_check_right_end

    ; Check for end of right string
    MOV  R5, R4             ; Use R5 as temp to preserve R4
    IEQ  R5, 0
    JT   R5, __strcmp_diff  ; Left not at end, right at end → unequal

    ; Characters differ?
    MOV  R5, R3             ; Use R5 as temp
    INE  R5, R4             ; R5 = 1 if R3 != R4, else 0
    JT   R5, __strcmp_diff

    ; Characters equal, advance both pointers
    IADD R1, 1
    IADD R2, 1
    JMP  __strcmp_loop

__strcmp_check_right_end:
    MOV  R5, R4
    IEQ  R5, 0
    JT   R5, __strcmp_equal
    JMP  __strcmp_diff

__strcmp_diff:
    MOV  R0, R3
    ISUB R0, R4        ; R0 = R3 - R4
    MOV  SP, BP
    POP  BP
    RET

__strcmp_equal:
    MOV  R0, 0
    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Universal Equality (==): Returns raw integer 1 (true) or 0 (false) in R0
;; Incoming Stack: [BP+3] = Left_Val, [BP+2] = Right_Val
;; Handles: bitwise-identical values (fast path), string comparisons, and
;;         numeric comparisons (raw IEEE 754 floats in NaN-boxing scheme)
;; ---------------------------------------------------------------------------
__builtin_eq:
    PUSH BP
    MOV  BP, SP

    MOV  R1, [BP+3]
    MOV  R2, [BP+2]

    ;; Fast-path: If bitwise identical, they are strictly equal
    IEQ  R1, R2
    JT   R1, __eq_return_true

    ;; --- Check if both operands are raw numbers (not tagged) ---
    ;; In NaN-boxing: numbers are raw floats, other types have BOXED_DATA tag
    MOV  R1, [BP+3]
    MOV  R3, R1
    AND  R3, BOXED_DATA
    INE  R3, 0               ; Non-zero = tagged (not a number)
    JF   R3, __eq_check_right_number

    ;; Left is tagged, so not a number - check if it's a string
    JMP  __eq_check_left_string

__eq_check_right_number:
    MOV  R3, R2
    AND  R3, BOXED_DATA
    INE  R3, 0               ; Non-zero = tagged (not a number)
    JF   R3, __eq_both_numbers

    ;; Right is tagged, left is not - different types, not equal
    JMP  __eq_return_false

__eq_both_numbers:
    ;; Both operands are raw floats - use float equality
    FEQ  R1, R2
    JT   R1, __eq_return_true
    JMP  __eq_return_false

;; --- String comparison path ---
__eq_check_left_string:
    ;; Validate LEFT Operand is a String (Tag 0x7FC0... or 0xFFC0... with
    ;; payload >= 4)
    MOV  R1, [BP+3]
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_ROMSTRING
    JT   R3, __eq_left_valid

    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_RAMSTRING
    JF   R3, __eq_return_false

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
    MOV  R3, [R1]
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
;; Runtime Built-in: __builtin_string_len
;; ABI: Arg 1 at [BP+2] (Stack Parameter), Caller cleans up.
;; Returns: R0 = Length of string as a Lua Float.
;; ===========================================================================
__builtin_string_len:
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
__string_len_loop:
    MOV  R2, [R0]               ; Read character from address
    IEQ  R2, 0                  ; Is it null terminator?
    JT   R2, __string_len_done
    IADD R0, 1                  ; Advance pointer
    IADD R1, 1                  ; Increment counter
    JMP  __string_len_loop

__string_len_done:
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
    PUSH  BP
    MOV   BP, SP

    MOV   R1, [BP+2]          ; Load argument

    ;; === PRIMITIVE CHECKS FIRST (exact value matches) ===
    MOV   R6, R1
    IEQ   R6, BOXED_NIL
    JT    R6, __tostring_nil
    MOV   R6, R1
    IEQ   R6, BOXED_FALSE
    JT    R6, __tostring_false
    MOV   R6, R1
    IEQ   R6, BOXED_TRUE
    JT    R6, __tostring_true

    ;; === STRING CHECKS ===
    ;; Pass through ROM Strings unchanged
    MOV   R3, R1
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_ROMSTRING
    JT    R3, __tostring_passthrough

    ;; RAM strings: MUST have tag=BOXED_RAMSTRING AND payload >= 4
    MOV   R3, R1
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_RAMSTRING
    JF    R3, __tostring_check_other  ; Not RAM string → check other types

    MOV   R4, R1
    AND   R4, BOXED_PAYLOAD
    ILT   R4, 4
    JT    R4, __tostring_check_other  ; Payload < 4 → not a valid RAM string
    JMP   __tostring_passthrough      ; Valid RAM string → pass through

__tostring_check_other:
    ;; Check for Table
    MOV   R3, R1
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_TABLE
    JT    R3, __tostring_table

    ;; Check for Function
    MOV   R3, R1
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_FUNCTION
    JT    R3, __tostring_function

    ;; Fall through: It's a float
    PUSH  R1
    MOV   R0, -1
    PUSH  R0             ; default precision (6 digits, or omitted if whole)
    CALL  __builtin_ftoa
    IADD  SP, 2
    OR    R0, BOXED_RAMSTRING
    JMP   __tostring_done

__tostring_nil:
    MOV   R0, __const_str_nil
    OR    R0, BOXED_ROMSTRING
    JMP   __tostring_done

__tostring_false:
    MOV   R0, __const_str_false
    OR    R0, BOXED_ROMSTRING
    JMP   __tostring_done

__tostring_true:
    MOV   R0, __const_str_true
    OR    R0, BOXED_ROMSTRING
    JMP   __tostring_done

__tostring_passthrough:
    MOV   R0, R1
    MOV   SP, BP
    POP   BP
    RET

__tostring_table:
    MOV   R0, __const_str_table  ; Load result directly
    OR    R0, BOXED_ROMSTRING
    MOV   SP, BP                 ; Restore stack
    POP   BP
    RET                           ; Return to caller

__tostring_function:
    MOV   R0, __const_str_function  ; Load result directly
    OR    R0, BOXED_FUNCTION
    MOV   SP, BP                 ; Restore stack
    POP   BP
    RET                           ; Return to caller

__tostring_done:
    MOV   SP, BP
    POP   BP
    RET

__string_format_table_address:
    PUSH BP
    MOV  BP, SP

    MOV  R0, __const_str_table
    OR   R0, BOXED_ROMSTRING      ; Box raw pointer as a valid Lua String

    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Built-in: Float to ASCII (Full Floating Point Support)
;; Incoming Stack: [BP+3] = Raw IEEE754 Float (value to convert)
;;                 [BP+2] = Precision (raw hardware integer). Pass -1 for
;;                          "default" behavior (existing tostring() behavior):
;;                          6 fractional digits, but the decimal point and all
;;                          fractional digits are omitted entirely when the
;;                          value is a whole number. Pass 0..N for an explicit
;;                          precision (printf "%.Nf" semantics): the value is
;;                          ROUNDED (not truncated) to N fractional digits,
;;                          the decimal point + digits are always printed
;;                          unless N==0, and rounding correctly carries into
;;                          the integer part (e.g. ftoa(9.999, 2) -> "10.00").
;;                          Precision is clamped to a max of 17.
;; Returns: R0 = Raw Heap Pointer to null-terminated ASCII string
;; Registers: R0-R13 (R14/BP and R15/SP preserved)
;; ---------------------------------------------------------------------------
__builtin_ftoa:
    PUSH BP
    MOV  BP, SP

    ;; --- Allocate buffer ---
    ;; 48 words: sign + integer digits + '.' + up to 17 (clamped) frac digits
    ;; + null, with headroom. (Was 32; bumped since precision can now be large.)
    MOV  R0, 48
    PUSH R0
    CALL __malloc
    IADD SP, 1

    MOV  R4, R0
    IEQ  R4, 0
    JT   R4, __oom_handler

    MOV  R2, R0                 ; R2 = locked-in base pointer
    MOV  R9, R2                 ; R9 = write head

    MOV  R3, [BP+3]             ; R3 = value
    MOV  R8, [BP+2]             ; R8 = requested precision (-1 = default)

    ;; --- Clamp precision to 17 so a pathological caller can't overflow the buffer ---
    MOV  R4, R8
    INE  R4, -1
    JF   R4, __ftoa_precision_clamped   ; precision == -1 -> nothing to clamp
    MOV  R4, R8
    IGT  R4, 17
    JF   R4, __ftoa_precision_clamped   ; precision <= 17 -> nothing to clamp
    MOV  R8, 17
__ftoa_precision_clamped:

    ;; --- Sign ---
    MOV  R4, R3
    FLT  R4, 0.0
    JF   R4, __ftoa_positive
    MOV  R5, 45                 ; ASCII '-'
    MOV  [R9], R5
    IADD R9, 1
    FABS R3
    JMP  __ftoa_extract_int
__ftoa_positive:
__ftoa_extract_int:
    MOV  R4, R3
    CFI  R4                     ; truncate toward zero
    MOV  R7, R4                 ; R7 = integer part (may still be bumped by rounding)

    MOV  R6, R3
    CFI  R6
    CIF  R6
    MOV  R5, R3
    FSUB R5, R6                 ; R5 = fractional part (0 <= R5 < 1)

    ;; --- Decide effective precision ---
    MOV  R12, R8                ; R12 = effective precision digit count
    MOV  R4, R8
    INE  R4, -1
    JT   R4, __ftoa_precision_explicit

    ;; --- Default mode: 6 digits, but omit '.' entirely if negligible ---
    MOV  R12, 6
    MOV  R6, R5
    MOV  R4, 0.000001
    FLT  R6, R4
    JF   R6, __ftoa_scale_and_round     ; fraction not negligible -> format it
    JMP  __ftoa_write_int_only           ; whole number in default mode -> skip '.'

__ftoa_precision_explicit:
    MOV  R4, R12
    IEQ  R4, 0
    JF   R4, __ftoa_scale_and_round
    ;; precision == 0: round to nearest integer, no '.' at all (printf %.0f)
    MOV  R6, R5
    MOV  R4, 0.5
    FLT  R6, R4
    JT   R6, __ftoa_write_int_only       ; frac < 0.5, no rounding needed
    IADD R7, 1                            ; round the integer part up
    JMP  __ftoa_write_int_only

    ;; ==========================================================
    ;; Scale fraction by 10^precision and round-half-up
    ;; ==========================================================
__ftoa_scale_and_round:
    MOV  R6, 1.0                ; R6 = running power-of-ten (float)
    MOV  R13, 1                  ; R13 = running power-of-ten (integer)
    MOV  R4, R12                 ; R4 = countdown
__ftoa_pow10_loop:
    MOV  R11, R4                 ; compare a COPY -- IEQ is destructive and R4 must survive
    IEQ  R11, 0
    JT   R11, __ftoa_pow10_done
    MOV  R10, 10.0
    FMUL R6, R10
    MOV  R10, 10
    IMUL R13, R10
    IADD R4, -1
    JMP  __ftoa_pow10_loop
__ftoa_pow10_done:

    MOV  R4, R5
    FMUL R4, R6                  ; R4 = frac * 10^precision
    MOV  R10, 0.5
    FADD R4, R10                 ; round-half-up
    CFI  R4                      ; R4 = rounded fractional digits (integer)

    ;; --- Carry: rounding pushed the fraction up to a whole unit ---
    MOV  R6, R4
    IGE  R6, R13
    JF   R6, __ftoa_push_frac
    IADD R7, 1                   ; carry into the integer part
    MOV  R4, 0                   ; fractional digits reset to zero
__ftoa_push_frac:
    PUSH R4                      ; save rounded fractional digits across int-write
    PUSH R12                     ; save precision digit count across int-write
    MOV  R4, 1
    PUSH R4                      ; has_fraction = 1
    JMP  __ftoa_write_int_common

__ftoa_write_int_only:
    MOV  R4, 0
    PUSH R4                      ; dummy fractional digits (unused)
    PUSH R4                      ; dummy precision (unused)
    PUSH R4                      ; has_fraction = 0
    JMP  __ftoa_write_int_common

    ;; ==========================================================
    ;; Shared: write integer digits (destroys R7; R4/R5/R6/R10-R13 free
    ;; to use as scratch here, since the real fraction data is on the stack)
    ;; ==========================================================
__ftoa_write_int_common:
    MOV  R6, R7
    INE  R6, 0
    JT   R6, __ftoa_int_nonzero

    MOV  R6, 48                  ; ASCII '0'
    MOV  [R9], R6
    IADD R9, 1
    JMP  __ftoa_int_digits_done

__ftoa_int_nonzero:
    MOV  R6, R9                  ; R6 = start of integer digits (for reversal)
__ftoa_int_loop:
    MOV  R5, R7
    INE  R5, 0
    JF   R5, __ftoa_reverse_int

    MOV  R5, R7
    IMOD R5, 10
    IADD R5, 48
    MOV  [R9], R5
    IADD R9, 1
    IDIV R7, 10
    JMP  __ftoa_int_loop

__ftoa_reverse_int:
    MOV  R10, R6
    MOV  R11, R9
    ISUB R11, 1
__ftoa_reverse_int_loop:
    MOV  R5, R10
    IGE  R5, R11
    JT   R5, __ftoa_int_digits_done

    MOV  R12, [R10]
    MOV  R13, [R11]
    MOV  [R10], R13
    MOV  [R11], R12

    IADD R10, 1
    ISUB R11, 1
    JMP  __ftoa_reverse_int_loop
__ftoa_int_digits_done:

    ;; --- Restore the fraction data, decide whether it's needed ---
    POP  R6                      ; has_fraction flag
    POP  R12                     ; precision digit count
    POP  R4                      ; rounded fractional digits
    INE  R6, 0
    JF   R6, __ftoa_done         ; has_fraction == 0 -> done, no '.' at all

    ;; --- Write decimal point ---
    MOV  R6, 46                  ; ASCII '.'
    MOV  [R9], R6
    IADD R9, 1

    ;; --- Write exactly R12 fractional digits (LSB-first, then reverse) ---
    MOV  R1, R9                  ; R1 = start of fractional digits (for reversal)
    MOV  R6, R12                 ; R6 = digit countdown
__ftoa_extract_frac:
    MOV  R11, R6                 ; compare a COPY -- IEQ is destructive and R6 must survive
    IEQ  R11, 0
    JT   R11, __ftoa_reverse_frac

    MOV  R10, R4
    IMOD R10, 10
    IADD R10, 48
    MOV  [R9], R10
    IADD R9, 1
    IDIV R4, 10
    ISUB R6, 1
    JMP  __ftoa_extract_frac

__ftoa_reverse_frac:
    MOV  R10, R1
    MOV  R11, R9
    ISUB R11, 1
__ftoa_reverse_frac_loop:
    MOV  R5, R10
    IGE  R5, R11
    JT   R5, __ftoa_done

    MOV  R12, [R10]
    MOV  R13, [R11]
    MOV  [R10], R13
    MOV  [R11], R12

    IADD R10, 1
    ISUB R11, 1
    JMP  __ftoa_reverse_frac_loop

__ftoa_done:
    MOV  R10, 0
    MOV  [R9], R10               ; null terminator
    MOV  R0, R2                  ; return base pointer
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: string.byte(s [, i [, j]])
;; Returns byte values from string as Lua numbers
;; Incoming Stack: [BP+2] = string, [BP+3] = optional start index (1-based), [BP+4] = optional end index
;; Returns: R0 = byte value (as boxed float), or multiple values on stack
;; ===========================================================================
__builtin_string_byte:
    PUSH BP
    MOV  BP, SP

    ;; Load and unbox string
    MOV  R0, [BP+2]
    CALL __unbox_string
    MOV  R1, R0              ; R1 = unboxed string pointer

    ;; Default start index = 1 (Lua is 1-based)
    MOV  R2, [BP+3]          ; Check if start index provided
    IEQ  R2, BOXED_NIL
    JT   R2, __string_byte_default_start
    ;; Convert from Lua float to integer index
    CFI  R2                 ; Convert Float to Integer
    IADD R2, -1            ; Convert to 0-based
    JMP  __string_byte_check_end

__string_byte_default_start:
    MOV  R2, 0              ; Start at index 0 (first character)

__string_byte_check_end:
    ;; Default end index = start index (single byte)
    MOV  R3, [BP+4]          ; Check if end index provided
    IEQ  R3, BOXED_NIL
    JT   R3, __string_byte_default_end
    CFI  R3
    IADD R3, -1
    JMP  __string_byte_validate

__string_byte_default_end:
    MOV  R3, R2              ; Default: same as start

__string_byte_validate:
    ;; Validate indices are within bounds
    ;; Get string length
    MOV  R0, R1
    CALL __builtin_string_len
    CIF  R0                 ; Already a float
    MOV  R4, R0            ; R4 = length as float
    CFI  R4                 ; Convert to integer

    ;; Check start >= 0 and start < length
    ILT  R2, 0
    JT   R2, __string_byte_error
    IGE  R2, R4
    JT   R2, __string_byte_error

    ;; Check end >= start and end < length
    ILT  R3, R2
    JT   R3, __string_byte_error
    IGE  R3, R4
    JT   R3, __string_byte_error

    ;; Return byte at position R2
    IADD R1, R2            ; Point to character
    MOV  R0, [R1]          ; Load byte
    CIF  R0               ; Convert to Lua number (float)

    MOV  SP, BP
    POP  BP
    RET

__string_byte_error:
    MOV  R0, BOXED_NIL      ; Return nil on error
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: string.char(b1, b2, ..., bn)
;; Creates a string from byte values
;; Incoming Stack: [BP+2] = first byte, [BP+3] = second byte, ... terminated by BOXED_NIL
;; Returns: R0 = new string (boxed as RAM string)
;; Clobbers: R0-R5
;; ===========================================================================
__builtin_string_char:
    PUSH BP
    MOV  BP, SP

    ;; --- STEP 1: Count arguments by scanning for BOXED_NIL terminator ---
    MOV  R1, BP              ; R1 = base pointer to stack frame
    IADD R1, 2              ; R1 = pointer to first argument ([BP+2])
    MOV  R2, 0              ; R2 = argument counter

__string_char_count_loop:
    MOV  R3, [R1]           ; Load current argument
    IEQ  R3, BOXED_NIL      ; Check for terminator
    JT   R3, __string_char_count_done
    IADD R2, 1              ; Increment counter
    IADD R1, 1              ; Move to next argument
    JMP  __string_char_count_loop

__string_char_count_done:
    ;; R2 now contains the number of arguments
    ;; Allocate memory: R2 bytes + 1 for null terminator
    IADD R2, 1              ; +1 for null terminator
    PUSH R2
    CALL __malloc
    IADD SP, 1
    MOV  R4, R0            ; R4 = heap pointer (save in R4)

    ;; Check for OOM
    IEQ  R4, 0
    JT   R4, __string_char_oom

    ;; --- STEP 2: Copy bytes from stack to heap ---
    MOV  R1, BP              ; Reset R1 to base pointer
    IADD R1, 2              ; R1 = pointer to first argument
    MOV  R5, R4            ; R5 = current write position in heap

__string_char_copy_loop:
    MOV  R3, [R1]           ; Load current argument
    IEQ  R3, BOXED_NIL      ; Check for terminator
    JT   R3, __string_char_copy_done

    ;; Convert Lua number to integer byte
    CFI  R3                 ; Convert Float to Integer
    MOV  [R5], R3           ; Store byte at current position
    IADD R5, 1              ; Advance write pointer
    IADD R1, 1              ; Advance read pointer (to next stack arg)
    JMP  __string_char_copy_loop

__string_char_copy_done:
    ;; Null-terminate the string
    MOV  R3, 0
    MOV  [R5], R3

    ;; Box as RAM string and return
    MOV  R0, R4
    OR   R0, BOXED_RAMSTRING

    MOV  SP, BP
    POP  BP
    RET

__string_char_oom:
    MOV  R0, BOXED_NIL      ; Return nil on OOM
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: string.format(s, ...)
;; Incoming Stack: [BP+2] = format string, [BP+3...] = args, BOXED_NIL terminated
;; Returns: R0 = formatted string (boxed RAM string)
;; ===========================================================================
__builtin_string_format:
    PUSH BP
    MOV  BP, SP

    ;; Load and unbox format string
    MOV  R0, [BP+2]
    CALL __unbox_string
    MOV  R1, R0              ; R1 = format string pointer

    ;; Calculate format length for buffer estimation
    MOV  R2, 0
__string_format_calc_len:
    MOV  R4, R1               ; Compute address: R1 + R2
    IADD R4, R2
    MOV  R3, [R4]            ; Load character at calculated address
    IEQ  R3, 0
    JT   R3, __string_format_len_done
    IADD R2, 1
    JMP  __string_format_calc_len
__string_format_len_done:
    MOV  R0, R2
    IADD R0, R2
    IADD R0, R2            ; *3 for expansion
    IADD R0, 64           ; + safety margin

    PUSH R0
    CALL __malloc
    IADD SP, 1
    MOV  R4, R0            ; R4 = result buffer
    MOV  R3, R4             ; scratch copy -- IEQ is destructive, R4 must survive
    IEQ  R3, 0
    JT   R3, __string_format_oom

    MOV  R5, R4            ; R5 = write pointer
    MOV  R0, [BP+2]         ; FIX: was "MOV R1, [BP+2]" -- __unbox_string reads R0
    CALL __unbox_string
    MOV  R1, R0            ; R1 = format string

    MOV  R6, BP
    IADD R6, 3            ; R6 = arg pointer

__string_format_loop:
    MOV  R3, [R1]
    MOV  R2, R3
    IEQ  R2, 0
    JT   R2, __string_format_done

    MOV  R2, R3
    IEQ  R2, 37           ; '%'
    JF   R2, __string_format_copy_char

    IADD R1, 1
    MOV  R3, [R1]
    MOV  R2, R3
    IEQ  R2, 37
    JT   R2, __string_format_literal_percent

    ;; --- Skip width digits (parsed, but padding is not implemented) ---
__string_format_skip_width:
    MOV  R2, R3
    ISUB R2, 48
    ILT  R2, 0
    JT   R2, __string_format_check_dot
    MOV  R2, R3
    ISUB R2, 48
    IGT  R2, 9
    JT   R2, __string_format_check_dot
    IADD R1, 1
    MOV  R3, [R1]
    JMP  __string_format_skip_width

    ;; --- Optional ".NN" precision ---
__string_format_check_dot:
    MOV  R12, -1                ; R12 = parsed precision; -1 means "unspecified"
    MOV  R2, R3
    IEQ  R2, 46                 ; '.'
    JF   R2, __string_format_dispatch_specifier

    IADD R1, 1
    MOV  R3, [R1]
    MOV  R12, 0
__string_format_precision_digits:
    MOV  R2, R3
    ISUB R2, 48
    ILT  R2, 0
    JT   R2, __string_format_dispatch_specifier
    MOV  R2, R3
    ISUB R2, 48
    IGT  R2, 9
    JT   R2, __string_format_dispatch_specifier

    MOV  R2, 10
    IMUL R12, R2
    MOV  R2, R3
    ISUB R2, 48
    IADD R12, R2

    IADD R1, 1
    MOV  R3, [R1]
    JMP  __string_format_precision_digits

    ;; --- Now that we're at a real specifier char, consume the argument ---
__string_format_dispatch_specifier:
    MOV  R0, [R6]
    IADD R6, 1

    MOV  R2, R3
    IEQ  R2, 100          ; 'd'
    JT   R2, __string_format_handle_di
    MOV  R2, R3
    IEQ  R2, 105          ; 'i'
    JT   R2, __string_format_handle_di
    MOV  R2, R3
    IEQ  R2, 117          ; 'u'
    JT   R2, __string_format_handle_u
    MOV  R2, R3
    IEQ  R2, 102          ; 'f'
    JT   R2, __string_format_handle_f
    MOV  R2, R3
    IEQ  R2, 101          ; 'e'
    JT   R2, __string_format_handle_efg
    MOV  R2, R3
    IEQ  R2, 69           ; 'E'
    JT   R2, __string_format_handle_efg
    MOV  R2, R3
    IEQ  R2, 103          ; 'g'
    JT   R2, __string_format_handle_efg
    MOV  R2, R3
    IEQ  R2, 71           ; 'G'
    JT   R2, __string_format_handle_efg
    MOV  R2, R3
    IEQ  R2, 115          ; 's'
    JT   R2, __string_format_handle_s
    MOV  R2, R3
    IEQ  R2, 99           ; 'c'
    JT   R2, __string_format_handle_c
    MOV  R2, R3
    IEQ  R2, 113          ; 'q'
    JT   R2, __string_format_handle_q
    JMP  __string_format_write_char

__string_format_literal_percent:
    MOV  R3, 37
    JMP  __string_format_copy_char   ; FIX: was "JMP write_char", which skipped
                                       ; the actual write -- "%%" wrote nothing.

__string_format_handle_di:
    MOV  R2, R0
    IEQ  R2, BOXED_NIL
    JT   R2, __string_format_arg_nil
    PUSH R1                     ; save loop state: ftoa clobbers R1/R4/R5/R6 internally
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R0                     ; value (kept as float -- no CFI: %d no longer
                                  ; feeds raw integer bits into ftoa's float ops)
    MOV  R2, 0
    PUSH R2                     ; force precision 0: round to integer, no '.'
    CALL __builtin_ftoa
    IADD SP, 2
    POP  R6
    POP  R5
    POP  R4
    POP  R1
    MOV  R7, R0
    JMP  __string_format_copy_string

__string_format_handle_u:
    MOV  R2, R0
    IEQ  R2, BOXED_NIL
    JT   R2, __string_format_arg_nil
    PUSH R1
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R0
    MOV  R2, 0
    PUSH R2
    CALL __builtin_ftoa
    IADD SP, 2
    POP  R6
    POP  R5
    POP  R4
    POP  R1
    MOV  R7, R0
    JMP  __string_format_copy_string

__string_format_handle_f:
    MOV  R2, R0
    IEQ  R2, BOXED_NIL
    JT   R2, __string_format_arg_nil
    PUSH R1
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R0                     ; value
    PUSH R12                    ; precision parsed from the format string (-1 if none)
    CALL __builtin_ftoa
    IADD SP, 2
    POP  R6
    POP  R5
    POP  R4
    POP  R1
    MOV  R7, R0
    JMP  __string_format_copy_string

__string_format_handle_efg:
    ;; NOTE: still fixed-point via ftoa, same as before this fix -- true
    ;; scientific notation / shortest-representation formatting for %e/%g is
    ;; not implemented. This fix only makes it respect precision like %f now
    ;; does; it does not add exponent formatting.
    MOV  R2, R0
    IEQ  R2, BOXED_NIL
    JT   R2, __string_format_arg_nil
    PUSH R1
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R0
    PUSH R12
    CALL __builtin_ftoa
    IADD SP, 2
    POP  R6
    POP  R5
    POP  R4
    POP  R1
    MOV  R7, R0
    JMP  __string_format_copy_string

__string_format_handle_s:
    MOV  R2, R0
    IEQ  R2, BOXED_NIL
    JT   R2, __string_format_arg_nil
    PUSH R1                     ; save loop state: __unbox_string clobbers R1
    CALL __unbox_string
    POP  R1
    MOV  R7, R0
    JMP  __string_format_copy_string

__string_format_handle_c:
    MOV  R2, R0
    IEQ  R2, BOXED_NIL
    JT   R2, __string_format_arg_nil
    CFI  R0
    AND  R0, 255
    MOV  [R5], R0
    IADD R5, 1
    IADD R1, 1
    JMP  __string_format_loop

__string_format_handle_q:
    MOV  R2, R0
    IEQ  R2, BOXED_NIL
    JT   R2, __string_format_arg_nil
    PUSH R1                     ; save loop state: __unbox_string clobbers R1
    CALL __unbox_string
    POP  R1
    MOV  R7, R0
    MOV  R3, 34
    MOV  [R5], R3
    IADD R5, 1
    CALL __string_format_copy_string_inner
    MOV  R3, 34
    MOV  [R5], R3
    IADD R5, 1
    IADD R1, 1
    JMP  __string_format_loop

__string_format_arg_nil:
    MOV  R3, 110
    MOV  [R5], R3
    IADD R5, 1
    MOV  R3, 105
    MOV  [R5], R3
    IADD R5, 1
    MOV  R3, 108
    MOV  [R5], R3
    IADD R5, 1
    IADD R1, 1
    JMP  __string_format_loop

    ;; --- Used by %d/%i/%u/%f/%e/%g/%s: copies a C string from R7, then
    ;;     resumes the outer format loop at the next format-string char ---
__string_format_copy_string:
    MOV  R3, [R7]
    MOV  R2, R3
    IEQ  R2, 0
    JT   R2, __string_format_after_copy
    MOV  [R5], R3
    IADD R5, 1
    IADD R7, 1
    JMP  __string_format_copy_string
__string_format_after_copy:
    IADD R1, 1
    JMP  __string_format_loop

    ;; --- Used by %q only: same copy, but returns to its caller (via RET)
    ;;     instead of resuming the outer loop, since %q still has a closing
    ;;     quote to write first ---
__string_format_copy_string_inner:
    MOV  R3, [R7]
    MOV  R2, R3
    IEQ  R2, 0
    JT   R2, __string_format_copy_string_inner_done
    MOV  [R5], R3
    IADD R5, 1
    IADD R7, 1
    JMP  __string_format_copy_string_inner
__string_format_copy_string_inner_done:
    RET

__string_format_copy_char:
    MOV  [R5], R3
    IADD R5, 1
__string_format_write_char:
    IADD R1, 1
    JMP  __string_format_loop

__string_format_done:
    MOV  R3, 0
    MOV  [R5], R3
    MOV  R0, R4
    OR   R0, BOXED_RAMSTRING
    MOV  SP, BP
    POP  BP
    RET

__string_format_oom:
    MOV  R0, BOXED_NIL
    MOV  SP, BP
    POP  BP
    RET

