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
    MOV   R1, [BP+3]          ; Load Left value
    MOV   R3, R1
    AND   R3, BOXED_DATA      ; Extract tag
    IEQ   R3, BOXED_ROMSTRING
    JT    R3, __strcat_left_is_string
    IEQ   R3, BOXED_RAMSTRING
    JF    R3, __strcat_left_coerce

    ;; FIXED: tag matched RAMSTRING -- confirm payload >= 4 before
    ;; accepting it as a real string. nil/true/false fall through to the
    ;; coercion path below, which is where they belong.
    MOV   R3, R1
    AND   R3, BOXED_PAYLOAD
    ILT   R3, 4
    JT    R3, __strcat_left_coerce
    JMP   __strcat_left_is_string

__strcat_left_coerce:
    ;; Not a string - coerce it via the "A" scratch-buffer tostring
    ;; variant (was __builtin_tostring). (comment and code below this
    ;; point unchanged from the original -- this label is new, added
    ;; only so both the "tag never matched" and "tag matched but payload
    ;; < 4" cases can reach the same coercion code.)
    PUSH  R1
    CALL  __builtin_tostring_scratch_a  ; Returns string in R0
    IADD  SP, 1
    MOV   R1, R0              ; R1 = string version
    MOV   [BP+3], R1          ; Replace left operand on stack

__strcat_left_is_string:

    ;; === Type-check and coerce RIGHT operand if needed ===
    MOV   R1, [BP+2]          ; Load Right value
    MOV   R3, R1
    AND   R3, BOXED_DATA      ; Extract tag
    IEQ   R3, BOXED_ROMSTRING
    JT    R3, __strcat_right_is_string
    IEQ   R3, BOXED_RAMSTRING
    JF    R3, __strcat_right_coerce

    ;; FIXED: same payload check for the right operand.
    MOV   R3, R1
    AND   R3, BOXED_PAYLOAD
    ILT   R3, 4
    JT    R3, __strcat_right_coerce
    JMP   __strcat_right_is_string

__strcat_right_coerce:
    ;; Not a string - coerce it via the "B" scratch-buffer tostring
    ;; variant. (comment and code below this point unchanged -- see the
    ;; original's note on why RIGHT specifically uses the independent "B"
    ;; buffer.)
    PUSH  R1
    CALL  __builtin_tostring_scratch_b  ; Returns string in R0
    IADD  SP, 1
    MOV   R1, R0              ; R1 = string version
    MOV   [BP+2], R1          ; Replace right operand on stack

__strcat_right_is_string:

    ;; === Original string concatenation logic continues, unchanged ===
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
    MOV   R1, [BP+3]
    MOV   R3, R1
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_ROMSTRING
    JT    R3, __eq_left_valid

    MOV   R3, R1
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_RAMSTRING
    JF    R3, __eq_return_false

    ;; FIXED: tag matches RAMSTRING, but nil/true/false/tombstone share
    ;; that tag with payload < 4 -- only payload >= 4 is a real RAM string.
    MOV   R3, R1
    AND   R3, BOXED_PAYLOAD
    ILT   R3, 4
    JT    R3, __eq_return_false

__eq_left_valid:
    ;; Validate RIGHT Operand is a String
    MOV   R3, R2
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_ROMSTRING
    JT    R3, __eq_right_valid

    MOV   R3, R2
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_RAMSTRING
    JF    R3, __eq_return_false

    ;; FIXED: same payload check for the right operand.
    MOV   R3, R2
    AND   R3, BOXED_PAYLOAD
    ILT   R3, 4
    JT    R3, __eq_return_false

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
;; Universal Relational Comparison (<, <=, >, >=)
;; Incoming Stack: [BP+3] = Left_Val (boxed), [BP+2] = Right_Val (boxed)
;; Returns: R0 = raw integer -1 (Left < Right), 0 (Left == Right), 1 (Left > Right)
;; Handles: numeric comparison (raw IEEE 754 floats) and lexicographic
;;          string comparison. Traps the CPU on mismatched/uncomparable types
;;          (e.g. number vs string, table vs number).
;; Clobbers: R0-R6
;; ---------------------------------------------------------------------------
__builtin_relcmp:
    PUSH BP
    MOV  BP, SP

    MOV  R1, [BP+3]            ; Left
    MOV  R2, [BP+2]            ; Right

    ;; --- Is Left a number? A boxed/tagged value has ALL exponent bits set
    ;; (the quiet-NaN pattern); a finite float never does. Mask out just the
    ;; exponent field (no sign bit!) and compare against that exact pattern -
    ;; same test used by __builtin_type elsewhere in this runtime.
    MOV  R3, R1
    AND  R3, NAN_VALUE          ; 0x7F800000 - isolate exponent bits only
    IEQ  R3, NAN_VALUE          ; R3 = 1 if Left is NaN-tagged (boxed)
    JT   R3, __relcmp_check_left_string

    ;; --- Left is a number: Right must also be a number ---
    MOV  R3, R2
    AND  R3, NAN_VALUE
    IEQ  R3, NAN_VALUE
    JT   R3, __relcmp_error     ; number vs tagged value -> uncomparable

    ;; --- Both operands are raw floats: compare numerically ---
    MOV  R4, R1                 ; preserve Left (FLT overwrites its dest reg)
    FLT  R1, R2                 ; R1 = (Left < Right) ? 1 : 0
    JT   R1, __relcmp_less

    MOV  R1, R4                 ; restore Left
    FGT  R1, R2                 ; R1 = (Left > Right) ? 1 : 0
    JT   R1, __relcmp_greater

    JMP  __relcmp_equal

    ;; --- Left is tagged: it must be a String for a valid comparison ---
__relcmp_check_left_string:
    MOV   R3, R1
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_ROMSTRING
    JT    R3, __relcmp_check_right_string
 
    MOV   R3, R1
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_RAMSTRING
    JF    R3, __relcmp_error
 
    ;; FIXED: payload >= 4 check, same rationale as __builtin_eq above.
    MOV   R3, R1
    AND   R3, BOXED_PAYLOAD
    ILT   R3, 4
    JT    R3, __relcmp_error
 
__relcmp_check_right_string:
    MOV   R3, R2
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_ROMSTRING
    JT    R3, __relcmp_strings
 
    MOV   R3, R2
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_RAMSTRING
    JF    R3, __relcmp_error
 
    ;; FIXED: same payload check for the right operand.
    MOV   R3, R2
    AND   R3, BOXED_PAYLOAD
    ILT   R3, 4
    JT    R3, __relcmp_error
 
__relcmp_strings:
    ;; --- Both operands are Strings: unbox and compare lexicographically ---
    MOV  R0, R1
    CALL __unbox_string
    PUSH R0                     ; Save unboxed Left pointer

    MOV  R0, R2
    CALL __unbox_string
    MOV  R2, R0                 ; R2 = unboxed Right pointer
    POP  R1                     ; R1 = unboxed Left pointer

__relcmp_strloop:
    MOV  R3, [R1]                ; Left char
    MOV  R4, [R2]                ; Right char

    MOV  R5, R3                  ; scratch: has Left hit NUL?
    IEQ  R5, 0
    JT   R5, __relcmp_check_right_end

    MOV  R5, R4                  ; scratch: has Right hit NUL?
    IEQ  R5, 0
    JT   R5, __relcmp_greater    ; Left longer than Right -> Left > Right

    MOV  R5, R3                  ; scratch: do characters differ?
    INE  R5, R4
    JT   R5, __relcmp_strdiff

    IADD R1, 1
    IADD R2, 1
    JMP  __relcmp_strloop

__relcmp_check_right_end:
    MOV  R5, R4
    IEQ  R5, 0
    JT   R5, __relcmp_equal      ; both hit NUL together -> equal strings
    JMP  __relcmp_less           ; Left shorter than Right -> Left < Right

__relcmp_strdiff:
    MOV  R5, R3
    ILT  R5, R4                  ; R5 = (LeftChar < RightChar) ? 1 : 0
    JT   R5, __relcmp_less
    JMP  __relcmp_greater

__relcmp_less:
    MOV  R0, -1
    MOV  SP, BP
    POP  BP
    RET

__relcmp_greater:
    MOV  R0, 1
    MOV  SP, BP
    POP  BP
    RET

__relcmp_equal:
    MOV  R0, 0
    MOV  SP, BP
    POP  BP
    RET

__relcmp_error:
    ;; Operands are of incompatible/non-comparable types (e.g. nil vs
    ;; number, table vs number, nil vs string). Rather than halting the
    ;; whole VM over one bad comparison, ordering operators on
    ;; non-comparable operands simply evaluate to false -- return a
    ;; sentinel that can never equal -1, 0, or 1 so <, <=, >, and >= all
    ;; consistently come out false at the call site.
    MOV  R0, 2
    MOV  SP, BP
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
;; Built-in: tostring() -- converts any Lua value to a string.
;;
;; This is the normal, persistent variant: a float argument gets a FRESH,
;; permanent heap allocation via __builtin_ftoa -- correct and necessary
;; here, since tostring()'s return value genuinely becomes a Lua string
;; the program may keep, store, or pass around indefinitely.
;;
;; Where the resulting string is instead immediately consumed (copied
;; elsewhere, or displayed) and never needed again, use
;; __builtin_tostring_scratch_a or _scratch_b below instead.
;;
;; Incoming Stack: [BP+2] = value to convert
;; Returns: R0 = Tagged (boxed) string
;; ---------------------------------------------------------------------------
__builtin_tostring:
    PUSH  BP
    MOV   BP, SP
    MOV   R5, 0                ; mode 0: normal malloc'd, persistent buffer
    JMP   __tostring_shared_body

;; ---------------------------------------------------------------------------
;; Built-in: tostring(), SHARED SCRATCH variant "A".
;;
;; Use instead of __builtin_tostring wherever the resulting string is
;; immediately consumed and never needs to survive as an independent Lua
;; value. Non-float results (nil, true/false, pass-through strings,
;; table/function name constants) are already ROM constants or
;; pass-throughs with no allocation at all, so this only actually changes
;; behavior for the float case -- see __builtin_ftoa_scratch_a for the
;; full rationale. Used by print()'s implicit coercion and
;; __builtin_strcat's LEFT-operand coercion.
;; ---------------------------------------------------------------------------
__builtin_tostring_scratch_a:
    PUSH  BP
    MOV   BP, SP
    MOV   R5, 1                ; mode 1: shared scratch buffer A
    JMP   __tostring_shared_body

;; ---------------------------------------------------------------------------
;; Built-in: tostring(), SHARED SCRATCH variant "B" -- second independent
;; buffer, used only by __builtin_strcat's RIGHT-operand coercion. See
;; __builtin_ftoa_scratch_b for why a second buffer is needed.
;; ---------------------------------------------------------------------------
__builtin_tostring_scratch_b:
    PUSH  BP
    MOV   BP, SP
    MOV   R5, 2                ; mode 2: shared scratch buffer B
    ;; falls straight through into the shared body below

;; ===========================================================================
;; Shared dispatch body -- reached from all three entry points above.
;; R5 holds the mode (0/1/2) selected by whichever entry point was called.
;; None of the primitive/string/table/function checks below touch R1, R3,
;; R4, or R6 in a way that matters across this call, and NONE of them
;; touch R5 at all, so the mode flag survives intact all the way down to
;; the float branch at the bottom, where it's finally read.
;; ===========================================================================
__tostring_shared_body:
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

    ;; --- Fall through: it's a float. Dispatch to the correct ftoa ---
    ;; --- variant based on the mode this entry point selected.     ---
    MOV   R6, R5
    IEQ   R6, 1
    JT    R6, __tostring_use_scratch_a
    MOV   R6, R5
    IEQ   R6, 2
    JT    R6, __tostring_use_scratch_b

    ;; mode 0: normal malloc'd, persistent buffer
    PUSH  R1
    MOV   R0, -1
    PUSH  R0             ; default precision (6 digits, or omitted if whole)
    CALL  __builtin_ftoa
    IADD  SP, 2
    JMP   __tostring_float_done

__tostring_use_scratch_a:
    PUSH  R1
    MOV   R0, -1
    PUSH  R0
    CALL  __builtin_ftoa_scratch_a
    IADD  SP, 2
    JMP   __tostring_float_done

__tostring_use_scratch_b:
    PUSH  R1
    MOV   R0, -1
    PUSH  R0
    CALL  __builtin_ftoa_scratch_b
    IADD  SP, 2
    ;; falls straight through

__tostring_float_done:
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
    OR    R0, BOXED_ROMSTRING       ; FIXED: was BOXED_FUNCTION
    MOV   SP, BP                 ; Restore stack
    POP   BP
    RET                           ; Return to caller

__tostring_done:
    MOV   SP, BP
    POP   BP
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
;;
;; This allocates a FRESH, permanent 48-word heap block on every call --
;; correct and necessary when the resulting string genuinely becomes a
;; Lua value the program may keep (e.g. tostring()'s return value). Where
;; the result is instead immediately copied elsewhere or displayed and
;; never needed again, use __builtin_ftoa_scratch_a or _scratch_b below
;; instead -- see their own header comments for the rationale.
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
    JMP  __ftoa_shared_body

;; ---------------------------------------------------------------------------
;; Built-in: Float to ASCII, SHARED SCRATCH variant "A".
;;
;; Use instead of __builtin_ftoa wherever the resulting string is
;; immediately consumed (copied elsewhere, or displayed) and never needs
;; to survive as an independent, addressable Lua value in its own right.
;; Currently used by: string.format()'s numeric specifiers, print()'s
;; implicit number-to-string coercion, and __builtin_strcat's LEFT-operand
;; coercion. Each of these only ever needs ONE buffer alive at a time --
;; every result is fully copied out or displayed before the next coercion
;; can happen -- so sharing this one buffer across all three is safe.
;;
;; Costs exactly one 48-word allocation for the ENTIRE run of the cart --
;; made once, on the first call, and reused forever after -- instead of a
;; fresh 48-word block that becomes permanently unreachable garbage on
;; every single call. This runtime has no garbage collector, so that
;; memory could never be reclaimed any other way: a HUD that calls
;; string.format() or print() with a number once per frame (completely
;; ordinary for a TIC-80 cart) would otherwise exhaust available RAM
;; within minutes of continuous play.
;;
;; Incoming Stack / Returns / Registers: identical to __builtin_ftoa,
;; EXCEPT the returned pointer is the SAME shared buffer every time -- the
;; caller must finish using it (copy it out, or display it) before this
;; routine (or its indirect callers, e.g. __builtin_tostring_scratch_a) is
;; called again.
;; ---------------------------------------------------------------------------
__builtin_ftoa_scratch_a:
    PUSH BP
    MOV  BP, SP

    MOV  R0, [FTOA_SCRATCH_PTR_A]
    IEQ  R0, 0
    JF   R0, __ftoa_scratch_a_have_buffer

    ;; First call ever: allocate the shared buffer once, exactly as
    ;; __builtin_ftoa does, and cache its address for every future call.
    MOV  R0, 48
    PUSH R0
    CALL __malloc
    IADD SP, 1

    MOV  R4, R0
    IEQ  R4, 0
    JT   R4, __oom_handler

    MOV  [FTOA_SCRATCH_PTR_A], R0

__ftoa_scratch_a_have_buffer:
    MOV  R2, [FTOA_SCRATCH_PTR_A]
    JMP  __ftoa_shared_body

;; ---------------------------------------------------------------------------
;; Built-in: Float to ASCII, SHARED SCRATCH variant "B" -- a SECOND,
;; independent scratch buffer.
;;
;; Exists only because __builtin_strcat needs two coerced operands to
;; remain valid simultaneously: strcat measures BOTH operand lengths
;; before allocating its own final buffer, so if both sides need
;; coercing, the left-coerced string (built via scratch buffer "A") must
;; remain valid while the right side is being coerced too -- reusing
;; buffer "A" for the right side as well would silently overwrite the
;; left operand's still-needed content. Used ONLY by __builtin_strcat's
;; RIGHT-operand coercion.
;;
;; Otherwise identical in every respect to __builtin_ftoa_scratch_a.
;; ---------------------------------------------------------------------------
__builtin_ftoa_scratch_b:
    PUSH BP
    MOV  BP, SP

    MOV  R0, [FTOA_SCRATCH_PTR_B]
    IEQ  R0, 0
    JF   R0, __ftoa_scratch_b_have_buffer

    MOV  R0, 48
    PUSH R0
    CALL __malloc
    IADD SP, 1

    MOV  R4, R0
    IEQ  R4, 0
    JT   R4, __oom_handler

    MOV  [FTOA_SCRATCH_PTR_B], R0

__ftoa_scratch_b_have_buffer:
    MOV  R2, [FTOA_SCRATCH_PTR_B]
    ;; falls straight through into the shared body below

;; ===========================================================================
;; Shared conversion body -- reached from all three entry points above via
;; JMP/fallthrough, each having set R2 to that variant's buffer base
;; pointer first. Everything from here down is UNCHANGED from the
;; original __builtin_ftoa's own conversion algorithm.
;; ===========================================================================
__ftoa_shared_body:
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
;;
;; Incoming Stack: [BP+2] = string, [BP+3] = optional start index (1-based),
;;                 [BP+4] = optional end index
;; Returns: R0 = byte value (as boxed float), or BOXED_NIL on error
;; Clobbers: R0-R5
;; ===========================================================================
__builtin_string_byte:
    PUSH  BP
    MOV   BP, SP

    ;; --- Step 1: Load and unbox the string ---
    MOV   R0, [BP+2]          ; Load string argument
    CALL  __unbox_string      ; R0 = raw memory address (ROM or RAM)
    MOV   R1, R0              ; R1 = unboxed string pointer (preserve)

    ;; --- Step 2: Handle optional start index (defaults to 1 = index 0) ---
    MOV   R2, [BP+3]          ; Load start index argument
    IEQ   R2, BOXED_NIL      ; Check if start index is NIL
    JT    R2, __string_byte_default_start

    ;; Start index provided - the IEQ above destructively overwrote R2 with
    ;; its own 0/1 result, so reload the real argument before converting it.
    MOV   R2, [BP+3]
    CFI   R2                 ; Convert float to integer
    ISUB  R2, 1              ; Convert to 0-based index
    JMP   __string_byte_check_end

__string_byte_default_start:
    MOV   R2, 0              ; Default: start at first character (0-based)

    ;; --- Step 3: Handle optional end index (defaults to start index) ---
__string_byte_check_end:
    MOV   R3, [BP+4]          ; Load end index argument
    IEQ   R3, BOXED_NIL
    JT    R3, __string_byte_default_end

    ;; Same fix: reload R3 before converting, IEQ above clobbered it.
    MOV   R3, [BP+4]
    CFI   R3
    ISUB  R3, 1
    JMP   __string_byte_validate

__string_byte_default_end:
    MOV   R3, R2              ; Default: end = start (single byte)

    ;; --- Step 4: Validate indices are within string bounds ---
__string_byte_validate:
    ;; FIXED: __builtin_string_len clobbers R0-R2 internally (its loop
    ;; uses R2 as scratch, and its terminating destructive IEQ always
    ;; leaves R2 == 1 on exit -- see the header comment on this patch).
    ;; R1, R2, AND R3 all need to be preserved across this call -- pushing
    ;; an argument copy does NOT count as preserving it, since it's never
    ;; popped back. R3 happened to survive before this fix only because
    ;; __builtin_string_len's current implementation doesn't happen to
    ;; touch it -- that's an accident of the callee's implementation, not
    ;; a guarantee, so it's preserved explicitly now too rather than left
    ;; implicit.
    PUSH  R1                  ; preserve string pointer across the CALL below
    PUSH  R2                  ; preserve start index across the CALL below
    PUSH  R3                  ; preserve end index across the CALL below
    PUSH  R1                  ; Arg 1 for __builtin_string_len
    CALL  __builtin_string_len
    IADD  SP, 1               ; Clean up the length-call's own argument
    MOV   R4, R0              ; R4 = length as float
    CFI   R4                  ; Convert float length to integer for comparisons
    POP   R3                  ; restore end index
    POP   R2                  ; restore start index
    POP   R1                  ; restore string pointer

    ;; Validate: start >= 0 AND start < length. Use a scratch register (R5)
    ;; for these comparisons -- R2/R3 are still needed below at Step 5 to
    ;; compute the byte address, and ILT/IGE destructively overwrite their
    ;; left operand with the 0/1 boolean result.
    MOV   R5, R2
    ILT   R5, 0
    JT    R5, __string_byte_error
    MOV   R5, R2
    IGE   R5, R4
    JT    R5, __string_byte_error

    ;; Validate: end >= start AND end < length
    MOV   R5, R3
    ILT   R5, R2
    JT    R5, __string_byte_error
    MOV   R5, R3
    IGE   R5, R4
    JT    R5, __string_byte_error

    ;; --- Step 5: Return byte at validated position ---
    IADD  R1, R2              ; R1 = string pointer + start offset
    MOV   R0, [R1]            ; Load byte from string memory
    CIF   R0                  ; Convert to Lua float
    JMP   __string_byte_done

    ;; --- Error handling ---
__string_byte_error:
    MOV   R0, BOXED_NIL      ; Return nil on any error

__string_byte_done:
    MOV   SP, BP
    POP   BP
    RET

;; ===========================================================================
;; Built-in: string.char(b1, b2, ..., bn)
;; Creates a new string from byte values
;;
;; Incoming Stack: [BP+2] = first byte, [BP+3] = second byte, ...
;;                 Arguments MUST be terminated by BOXED_NIL
;; Returns: R0 = new string (boxed as RAM string)
;; Clobbers: R0-R6
;; ===========================================================================
__builtin_string_char:
    PUSH  BP
    MOV   BP, SP

    ;; --- Step 1: Count arguments by scanning for BOXED_NIL terminator ---
    MOV   R1, BP               ; R1 = base pointer to stack frame
    IADD  R1, 2               ; R1 = pointer to first argument ([BP+2])
    MOV   R2, 0               ; R2 = argument counter

__string_char_count_loop:
    MOV   R3, [R1]            ; Load current argument from stack
    MOV   R6, R3               ; scratch copy -- IEQ is destructive (this
                                ; loop doesn't reuse R3 afterward, but keep
                                ; the same safe idiom as the copy loop below)
    IEQ   R6, BOXED_NIL       ; Check if this is the terminator
    JT    R6, __string_char_count_done
    IADD  R2, 1               ; Increment argument counter
    IADD  R1, 1               ; Move pointer to next stack word
    JMP   __string_char_count_loop

__string_char_count_done:
    ;; --- Step 2: Allocate memory (R2 bytes + 1 for null terminator) ---
    ;; Note: __malloc expects size in WORDS, but R2 is in bytes.
    ;; For now we assume bytes == words (simplification for single-byte chars)
    IADD  R2, 1               ; +1 for null terminator byte
    PUSH  R2
    CALL  __malloc
    IADD  SP, 1
    MOV   R4, R0              ; R4 = heap pointer (preserve for return)

    ;; FIXED: use a scratch register (R3) for the OOM check instead of
    ;; testing R4 directly. R4 must survive intact -- Step 3 immediately
    ;; below reads it via "MOV R5, R4" to set up the write cursor. R3 is
    ;; free here: its value from the count loop above is no longer
    ;; needed, and the copy loop below reassigns it fresh from [R1] before
    ;; ever reading it again.
    MOV   R3, R4
    IEQ   R3, 0
    JT    R3, __string_char_oom

    ;; --- Step 3: Copy byte values from stack to heap ---
    MOV   R1, BP               ; Reset R1 to base pointer
    IADD  R1, 2               ; R1 = pointer to first argument ([BP+2])
    MOV   R5, R4              ; R5 = current write position in heap

__string_char_copy_loop:
    MOV   R3, [R1]            ; Load current argument
    ;; Use a scratch register (R6) for the nil-check instead of testing R3
    ;; directly -- IEQ is destructive, and CFI below needs R3 to still
    ;; hold the REAL argument value, not the check's own result.
    MOV   R6, R3               ; scratch copy for the nil-check
    IEQ   R6, BOXED_NIL       ; Check for terminator
    JT    R6, __string_char_copy_done

    ;; Convert Lua float byte to integer and store
    CFI   R3                  ; Convert float to integer (byte value) --
                                ; R3 is untouched by the check above, so
                                ; this now converts the real argument.
    MOV   [R5], R3            ; Store byte at current heap position
    IADD  R5, 1               ; Advance write pointer (by 1 word)
    IADD  R1, 1               ; Advance read pointer to next argument
    JMP   __string_char_copy_loop

__string_char_copy_done:
    ;; --- Step 4: Null-terminate the new string ---
    MOV   R3, 0
    MOV   [R5], R3            ; Write null terminator byte

    ;; --- Step 5: Box as RAM string and return ---
    MOV   R0, R4              ; Return heap pointer
    OR    R0, BOXED_RAMSTRING ; Tag as RAM string

    MOV   SP, BP
    POP   BP
    RET

__string_char_oom:
    MOV   R0, BOXED_NIL      ; Return nil on allocation failure
    MOV   SP, BP
    POP   BP
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
    CALL __builtin_ftoa_scratch_a  ; was __builtin_ftoa -- result is fully
                                     ; copied out by __string_format_copy_string
                                     ; below and never touched again, so it
                                     ; never needs its own permanent allocation
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
    CALL __builtin_ftoa_scratch_a  ; was __builtin_ftoa
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
    CALL __builtin_ftoa_scratch_a  ; was __builtin_ftoa
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
    CALL __builtin_ftoa_scratch_a  ; was __builtin_ftoa
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

;; ===========================================================================
;; Built-in: string.sub(s, i [, j])
;; Incoming Stack: [BP+2] = string, [BP+3] = start index i (1-based Lua
;;                 float, may be negative -- negative counts from the end),
;;                 [BP+4] = end index j (same rules), or BOXED_NIL to
;;                 default to the end of the string (Lua's j = -1).
;; Returns: R0 = new string (boxed RAM string). Out-of-range indices are
;;          clamped, not errors, matching Lua semantics. i > j (after
;;          normalization) returns an empty string.
;; Clobbers: R0-R8
;; ===========================================================================
__builtin_string_sub:
    PUSH  BP
    MOV   BP, SP

    ;; --- Step 1: Unbox string, compute length ---
    MOV   R0, [BP+2]
    CALL  __unbox_string
    MOV   R1, R0               ; R1 = unboxed string pointer (persist)

    PUSH  R1
    PUSH  R1                   ; Arg 1 for __builtin_string_len
    CALL  __builtin_string_len
    IADD  SP, 1
    MOV   R4, R0
    CFI   R4                   ; R4 = length (integer)
    POP   R1                   ; restore string pointer

    ;; --- Step 2: Load & normalize start index i (required, 1-based) ---
    MOV   R6, [BP+3]
    CFI   R6                   ; R6 = i (raw integer, may be negative or 0)

    MOV   R5, R6
    ILT   R5, 0
    JF    R5, __string_sub_i_norm_done
    MOV   R5, R4
    IADD  R5, R6
    IADD  R5, 1
    MOV   R6, R5
__string_sub_i_norm_done:
    MOV   R5, R6
    ILT   R5, 1
    JF    R5, __string_sub_j_load
    MOV   R6, 1

    ;; --- Step 3: Load & normalize end index j (optional, defaults to len) ---
__string_sub_j_load:
    MOV   R7, [BP+4]
    MOV   R5, R7
    IEQ   R5, BOXED_NIL
    JT    R5, __string_sub_j_default

    MOV   R7, [BP+4]            ; reload -- IEQ above only clobbered R5
    CFI   R7

    MOV   R5, R7
    ILT   R5, 0
    JF    R5, __string_sub_j_clamp
    MOV   R5, R4
    IADD  R5, R7
    IADD  R5, 1
    MOV   R7, R5
    JMP   __string_sub_j_clamp

__string_sub_j_default:
    MOV   R7, R4

__string_sub_j_clamp:
    MOV   R5, R7
    IGT   R5, R4
    JF    R5, __string_sub_range_check
    MOV   R7, R4

    ;; --- Step 4: If i > j after normalization, result is empty ---
__string_sub_range_check:
    MOV   R5, R6
    IGT   R5, R7
    JT    R5, __string_sub_empty

    ;; --- Step 5: Allocate result buffer and copy [i-1, j-1] inclusive ---
    MOV   R8, R7
    ISUB  R8, R6
    IADD  R8, 1                 ; R8 = count of chars to copy = j - i + 1
    MOV   R2, R8
    IADD  R2, 1                 ; +1 for null terminator

    ;; __malloc clobbers R0-R3 and R6. R1 (string pointer) and R6 (start
    ;; index) are both read again after this call, so both are preserved.
    PUSH  R1
    PUSH  R6
    PUSH  R2
    CALL  __malloc
    IADD  SP, 1
    MOV   R3, R0                 ; R3 = destination heap pointer
    POP   R6                     ; restore start index
    POP   R1                     ; restore string pointer

    ;; OOM check via scratch register R2 -- R2 is free here (its only
    ;; earlier use was as the malloc size argument, already consumed by
    ;; the call above). R3 must stay untouched: "MOV R5, R3" below needs
    ;; the real heap pointer, not a 0/1 comparison result.
    MOV   R2, R3
    IEQ   R2, 0
    JT    R2, __string_sub_oom

    MOV   R2, R1                 ; R2 = read pointer = string base + (i-1)
    IADD  R2, R6
    ISUB  R2, 1

    MOV   R5, R3                 ; R5 = write pointer

__string_sub_copy_loop:
    MOV   R6, R8                 ; scratch copy -- IEQ is destructive
    IEQ   R6, 0
    JT    R6, __string_sub_copy_done
    MOV   R6, [R2]
    MOV   [R5], R6
    IADD  R2, 1
    IADD  R5, 1
    ISUB  R8, 1
    JMP   __string_sub_copy_loop

__string_sub_copy_done:
    MOV   R6, 0
    MOV   [R5], R6                ; null terminator
    MOV   R0, R3
    OR    R0, BOXED_RAMSTRING
    JMP   __string_sub_done

__string_sub_empty:
    ;; No registers need to survive the CALL itself, but R3 (the heap
    ;; pointer) IS needed after the OOM check below -- same fix applies.
    MOV   R3, 1
    PUSH  R3
    CALL  __malloc
    IADD  SP, 1
    MOV   R3, R0

    MOV   R2, R3
    IEQ   R2, 0
    JT    R2, __string_sub_oom

    MOV   R6, 0
    MOV   [R3], R6
    MOV   R0, R3
    OR    R0, BOXED_RAMSTRING
    JMP   __string_sub_done

__string_sub_oom:
    MOV   R0, BOXED_NIL

__string_sub_done:
    MOV   SP, BP
    POP   BP
    RET


;; ===========================================================================
;; Built-in: string.upper(s)
;; Incoming Stack: [BP+2] = string
;; Returns: R0 = new string (boxed RAM string), same length as input, with
;;          ASCII 'a'-'z' converted to 'A'-'Z'. Non-letter bytes pass
;;          through unchanged.
;; Clobbers: R0-R6
;; ===========================================================================
__builtin_string_upper:
    PUSH  BP
    MOV   BP, SP

    MOV   R0, [BP+2]
    CALL  __unbox_string
    MOV   R1, R0                ; R1 = source string pointer (persist)

    PUSH  R1
    PUSH  R1
    CALL  __builtin_string_len
    IADD  SP, 1
    MOV   R4, R0
    CFI   R4
    POP   R1

    MOV   R2, R4
    IADD  R2, 1

    ;; __malloc clobbers R0-R3 and R6. R1 (source pointer) is read again
    ;; after this call, so it's preserved.
    PUSH  R1
    PUSH  R2
    CALL  __malloc
    IADD  SP, 1
    MOV   R3, R0                 ; R3 = destination heap pointer
    POP   R1                     ; restore source pointer

    ;; OOM check via scratch register R6 -- R6 is unused until inside the
    ;; loop below, so it's free here. R3 must stay untouched: "MOV R5, R3"
    ;; below needs the real heap pointer.
    MOV   R6, R3
    IEQ   R6, 0
    JT    R6, __string_upper_oom

    MOV   R2, R1                 ; R2 = read pointer
    MOV   R5, R3                 ; R5 = write pointer

__string_upper_loop:
    MOV   R0, [R2]
    MOV   R6, R0
    IEQ   R6, 0
    JT    R6, __string_upper_done_copy

    MOV   R6, R0
    ILT   R6, 97
    JT    R6, __string_upper_write
    MOV   R6, R0
    IGT   R6, 122
    JT    R6, __string_upper_write

    ISUB  R0, 32

__string_upper_write:
    MOV   [R5], R0
    IADD  R2, 1
    IADD  R5, 1
    JMP   __string_upper_loop

__string_upper_done_copy:
    MOV   R0, 0
    MOV   [R5], R0
    MOV   R0, R3
    OR    R0, BOXED_RAMSTRING
    JMP   __string_upper_finish

__string_upper_oom:
    MOV   R0, BOXED_NIL

__string_upper_finish:
    MOV   SP, BP
    POP   BP
    RET


;; ===========================================================================
;; Built-in: string.lower(s)
;; Incoming Stack: [BP+2] = string
;; Returns: R0 = new string (boxed RAM string), same length as input, with
;;          ASCII 'A'-'Z' converted to 'a'-'z'. Non-letter bytes pass
;;          through unchanged.
;; Clobbers: R0-R6
;; ===========================================================================
__builtin_string_lower:
    PUSH  BP
    MOV   BP, SP

    MOV   R0, [BP+2]
    CALL  __unbox_string
    MOV   R1, R0

    PUSH  R1
    PUSH  R1
    CALL  __builtin_string_len
    IADD  SP, 1
    MOV   R4, R0
    CFI   R4
    POP   R1

    MOV   R2, R4
    IADD  R2, 1

    PUSH  R1
    PUSH  R2
    CALL  __malloc
    IADD  SP, 1
    MOV   R3, R0
    POP   R1

    ;; Same fix as string.upper -- scratch register R6 for the OOM check.
    MOV   R6, R3
    IEQ   R6, 0
    JT    R6, __string_lower_oom

    MOV   R2, R1
    MOV   R5, R3

__string_lower_loop:
    MOV   R0, [R2]
    MOV   R6, R0
    IEQ   R6, 0
    JT    R6, __string_lower_done_copy

    MOV   R6, R0
    ILT   R6, 65
    JT    R6, __string_lower_write
    MOV   R6, R0
    IGT   R6, 90
    JT    R6, __string_lower_write

    IADD  R0, 32

__string_lower_write:
    MOV   [R5], R0
    IADD  R2, 1
    IADD  R5, 1
    JMP   __string_lower_loop

__string_lower_done_copy:
    MOV   R0, 0
    MOV   [R5], R0
    MOV   R0, R3
    OR    R0, BOXED_RAMSTRING
    JMP   __string_lower_finish

__string_lower_oom:
    MOV   R0, BOXED_NIL

__string_lower_finish:
    MOV   SP, BP
    POP   BP
    RET


;; ===========================================================================
;; Built-in: string.rep(s, n)
;; Incoming Stack: [BP+2] = string, [BP+3] = repeat count n (Lua float)
;; Returns: R0 = new string (boxed RAM string) = s repeated n times.
;;          n <= 0, or an empty source string, both yield "".
;; Clobbers: R0-R7
;; ===========================================================================
__builtin_string_rep:
    PUSH  BP
    MOV   BP, SP

    MOV   R0, [BP+2]
    CALL  __unbox_string
    MOV   R1, R0                ; R1 = source string pointer (persist)

    PUSH  R1
    PUSH  R1
    CALL  __builtin_string_len
    IADD  SP, 1
    MOV   R4, R0
    CFI   R4
    POP   R1

    MOV   R6, [BP+3]
    CFI   R6

    MOV   R5, R6
    IGT   R5, 0
    JF    R5, __string_rep_empty
    MOV   R5, R4
    IEQ   R5, 0
    JT    R5, __string_rep_empty

    MOV   R7, R4
    IMUL  R7, R6

    MOV   R2, R7
    IADD  R2, 1

    ;; __malloc clobbers R0-R3 and R6. Both R1 (source pointer) and R6
    ;; (repeat count n) are read again after this call, so both are
    ;; preserved.
    PUSH  R1
    PUSH  R6
    PUSH  R2
    CALL  __malloc
    IADD  SP, 1
    MOV   R3, R0                 ; R3 = destination heap pointer
    POP   R6                     ; restore repeat count
    POP   R1                     ; restore source pointer

    ;; OOM check via scratch register R2 -- free here (its only earlier
    ;; use was as the malloc size argument, already consumed). R3 must
    ;; stay untouched: "MOV R5, R3" below needs the real heap pointer.
    MOV   R2, R3
    IEQ   R2, 0
    JT    R2, __string_rep_oom

    MOV   R5, R3                 ; R5 = write pointer

__string_rep_outer_loop:
    MOV   R2, R6                 ; scratch copy of remaining repeat count
    IEQ   R2, 0
    JT    R2, __string_rep_done_copy

    MOV   R0, R1                 ; R0 = read pointer, reset to source start

;; Register note: R6 is NOT available as scratch here -- it holds the
;; remaining repeat count (n) and is live across every inner-loop
;; iteration, read again at __string_rep_inner_done ("ISUB R6, 1"). R4 is
;; used instead: it held the source string length earlier in the routine
;; (for the total-length multiply, before the __malloc call) and is never
;; read again after that, so it's genuinely free here.

__string_rep_inner_loop:
    MOV   R2, [R0]
    ;; FIXED: scratch copy (R4) for the nil-check, instead of testing R2
    ;; directly. R4 is free here (only used earlier for source length,
    ;; already consumed by the total-length calculation before the
    ;; __malloc call). R6 is NOT available -- it holds the repeat count,
    ;; live across every iteration of this loop.
    MOV   R4, R2
    IEQ   R4, 0
    JT    R4, __string_rep_inner_done
    MOV   [R5], R2
    IADD  R0, 1
    IADD  R5, 1
    JMP   __string_rep_inner_loop

__string_rep_inner_done:
    ISUB  R6, 1
    JMP   __string_rep_outer_loop

__string_rep_done_copy:
    MOV   R2, 0
    MOV   [R5], R2                ; null terminator
    MOV   R0, R3
    OR    R0, BOXED_RAMSTRING
    JMP   __string_rep_finish

__string_rep_empty:
    ;; R3 (heap pointer) is needed after the OOM check below.
    MOV   R3, 1
    PUSH  R3
    CALL  __malloc
    IADD  SP, 1
    MOV   R3, R0

    MOV   R2, R3
    IEQ   R2, 0
    JT    R2, __string_rep_oom

    MOV   R2, 0
    MOV   [R3], R2
    MOV   R0, R3
    OR    R0, BOXED_RAMSTRING
    JMP   __string_rep_finish

__string_rep_oom:
    MOV   R0, BOXED_NIL

__string_rep_finish:
    MOV   SP, BP
    POP   BP
    RET


;; ===========================================================================
;; Built-in: string.reverse(s)
;; Incoming Stack: [BP+2] = string
;; Returns: R0 = new string (boxed RAM string) with byte order reversed.
;; Clobbers: R0-R6
;; ===========================================================================
__builtin_string_reverse:
    PUSH  BP
    MOV   BP, SP

    MOV   R0, [BP+2]
    CALL  __unbox_string
    MOV   R1, R0                ; R1 = source string pointer (persist)

    PUSH  R1
    PUSH  R1
    CALL  __builtin_string_len
    IADD  SP, 1
    MOV   R4, R0
    CFI   R4
    POP   R1

    MOV   R2, R4
    IADD  R2, 1

    ;; __malloc clobbers R0-R3 and R6. R1 (source pointer) is read again
    ;; after this call, so it's preserved. R4 (length) is also read
    ;; again, but R4 is NOT in __malloc's clobber set, so it needs no
    ;; protection.
    PUSH  R1
    PUSH  R2
    CALL  __malloc
    IADD  SP, 1
    MOV   R3, R0                 ; R3 = destination heap pointer
    POP   R1                     ; restore source pointer

    ;; OOM check via scratch register R2 -- free here (reassigned fresh
    ;; immediately after anyway, on the very next line that matters). R3
    ;; must stay untouched: "MOV R6, R3" below needs the real heap
    ;; pointer.
    MOV   R2, R3
    IEQ   R2, 0
    JT    R2, __string_reverse_oom

    ;; write destination front-to-back from source back-to-front:
    ;; dest[k] = src[len-1-k]
    MOV   R5, R1
    IADD  R5, R4
    ISUB  R5, 1                  ; R5 = pointer to LAST char of source
    MOV   R6, R3                 ; R6 = write pointer (dest, forward)
    MOV   R2, R4                 ; R2 = remaining count

__string_reverse_loop:
    MOV   R0, R2
    IEQ   R0, 0
    JT    R0, __string_reverse_done_copy

    MOV   R0, [R5]
    MOV   [R6], R0
    ISUB  R5, 1
    IADD  R6, 1
    ISUB  R2, 1
    JMP   __string_reverse_loop

__string_reverse_done_copy:
    MOV   R0, 0
    MOV   [R6], R0                ; null terminator
    MOV   R0, R3
    OR    R0, BOXED_RAMSTRING
    JMP   __string_reverse_finish

__string_reverse_oom:
    MOV   R0, BOXED_NIL

__string_reverse_finish:
    MOV   SP, BP
    POP   BP
    RET


;; ===========================================================================
;; Built-in: string.find(s, pattern) -- PLAIN SUBSTRING SEARCH ONLY
;; No Lua pattern-matching support (no magic characters interpreted; the
;; second argument is always a literal substring). No init/plain-flag
;; arguments. Only the start index is returned (no end index, no captures)
;; -- real Lua's find() returns two values here.
;; Incoming Stack: [BP+2] = string s, [BP+3] = substring to find
;; Returns: R0 = 1-based start index of the first match (as a Lua float),
;;          or BOXED_NIL if not found. An empty needle matches at index 1.
;; Clobbers: R0-R9
;; ===========================================================================
__builtin_string_find:
    PUSH  BP
    MOV   BP, SP

    ;; Haystack pointer stored directly in R5 (not R1) -- __unbox_string's
    ;; own first instruction is "MOV R1, R0", so it would clobber R1 on
    ;; the second call below if the haystack pointer were stored there.
    ;; R5 is untouched by __unbox_string.
    MOV   R0, [BP+2]
    CALL  __unbox_string
    MOV   R5, R0                 ; R5 = haystack pointer (persist)

    MOV   R0, [BP+3]
    CALL  __unbox_string
    MOV   R2, R0                 ; R2 = needle pointer

    ;; Empty needle matches at position 1. (This IEQ is a fresh
    ;; loop-terminator check on a just-loaded byte, not an OOM check on a
    ;; value that needs to survive -- no bug here.)
    MOV   R3, [R2]
    IEQ   R3, 0
    JT    R3, __string_find_match_at_start

    MOV   R8, 1                  ; R8 = 1-based index of R5 within haystack

__string_find_outer:
    MOV   R3, [R5]
    IEQ   R3, 0
    JT    R3, __string_find_not_found

    MOV   R6, R5                 ; R6 = inner haystack cursor
    MOV   R7, R2                 ; R7 = inner needle cursor

__string_find_inner:
    MOV   R3, [R7]
    MOV   R9, R3
    IEQ   R9, 0
    JT    R9, __string_find_matched

    MOV   R4, [R6]
    MOV   R9, R4
    IEQ   R9, 0
    JT    R9, __string_find_advance_outer

    MOV   R9, R3
    INE   R9, R4
    JT    R9, __string_find_advance_outer

    IADD  R6, 1
    IADD  R7, 1
    JMP   __string_find_inner

__string_find_advance_outer:
    IADD  R5, 1
    IADD  R8, 1
    JMP   __string_find_outer

__string_find_matched:
    MOV   R0, R8
    CIF   R0
    JMP   __string_find_done

__string_find_match_at_start:
    MOV   R0, 1
    CIF   R0
    JMP   __string_find_done

__string_find_not_found:
    MOV   R0, BOXED_NIL

__string_find_done:
    MOV   SP, BP
    POP   BP
    RET


;; ===========================================================================
;; Built-in: string.gsub(s, pattern, repl) -- PLAIN SUBSTITUTION ONLY
;; No Lua pattern-matching support. No init/n-limit arguments. Only the
;; resulting string is returned (real Lua's gsub also returns a
;; substitution count as a second value). An empty pattern is treated as
;; "no matches" (s returned unchanged) rather than Lua's zero-width
;; match-between-every-character semantics, to avoid an infinite loop.
;; Incoming Stack: [BP+2] = string s, [BP+3] = pattern, [BP+4] = repl
;; Returns: R0 = new string (boxed RAM string)
;; Clobbers: R0-R13
;;
;; Register map (held constant across both passes):
;;   R7  = s pointer (unboxed)          R3 = len(s)
;;   R8  = pattern pointer (unboxed)    R4 = len(pattern)
;;   R9  = repl pointer (unboxed)       R5 = len(repl)
;;   R6  = match count (Pass 1) / free scratch after Pass 1's use is done
;;   R13 = destination heap pointer
;; Everything else (R0-R2, R10-R12) is scratch, reused freely.
;; ===========================================================================
__builtin_string_gsub:
    PUSH  BP
    MOV   BP, SP

    MOV   R0, [BP+2]
    CALL  __unbox_string
    MOV   R7, R0                 ; R7 = s pointer (persist)

    MOV   R0, [BP+3]
    CALL  __unbox_string
    MOV   R8, R0                 ; R8 = pattern pointer (persist)

    MOV   R0, [BP+4]
    CALL  __unbox_string
    MOV   R9, R0                 ; R9 = repl pointer (persist)

    PUSH  R7
    CALL  __builtin_string_len
    IADD  SP, 1
    MOV   R3, R0
    CFI   R3                     ; R3 = len(s)

    PUSH  R8
    CALL  __builtin_string_len
    IADD  SP, 1
    MOV   R4, R0
    CFI   R4                     ; R4 = len(pattern)

    MOV   R1, R4
    IEQ   R1, 0
    JT    R1, __string_gsub_no_match_copy

    PUSH  R9
    CALL  __builtin_string_len
    IADD  SP, 1
    MOV   R5, R0
    CFI   R5                     ; R5 = len(repl)

    ;; --- Pass 1: count non-overlapping matches ---
    MOV   R0, R7
    MOV   R6, 0                  ; R6 = match count

__string_gsub_count_loop:
    MOV   R1, [R0]
    IEQ   R1, 0
    JT    R1, __string_gsub_count_done

    MOV   R10, R0
    MOV   R11, R8

__string_gsub_count_inner:
    MOV   R1, [R11]
    MOV   R2, R1
    IEQ   R2, 0
    JT    R2, __string_gsub_count_hit

    MOV   R12, [R10]
    MOV   R2, R12
    IEQ   R2, 0
    JT    R2, __string_gsub_count_advance

    MOV   R2, R1
    INE   R2, R12
    JT    R2, __string_gsub_count_advance

    IADD  R10, 1
    IADD  R11, 1
    JMP   __string_gsub_count_inner

__string_gsub_count_hit:
    IADD  R6, 1
    IADD  R0, R4
    JMP   __string_gsub_count_loop

__string_gsub_count_advance:
    IADD  R0, 1
    JMP   __string_gsub_count_loop

__string_gsub_count_done:
    MOV   R1, R6
    IEQ   R1, 0
    JT    R1, __string_gsub_no_match_copy

    MOV   R1, R5
    ISUB  R1, R4
    IMUL  R1, R6
    MOV   R2, R3
    IADD  R2, R1
    IADD  R2, 1
    PUSH  R2
    CALL  __malloc
    IADD  SP, 1
    MOV   R13, R0                ; R13 = destination heap pointer (persist)

    ;; FIXED: OOM check via scratch register R6 -- Pass 1's use of R6 (the
    ;; match count) is over by this point, and nothing in Pass 2 below
    ;; reads it, so it's free. R13 must stay untouched: "MOV R12, R13"
    ;; below needs the real heap pointer.
    MOV   R6, R13
    IEQ   R6, 0
    JT    R6, __string_gsub_oom

    ;; --- Pass 2: copy, substituting each match ---
    MOV   R0, R7
    MOV   R12, R13

__string_gsub_copy_loop:
    MOV   R1, [R0]
    IEQ   R1, 0
    JT    R1, __string_gsub_copy_done

    MOV   R10, R0
    MOV   R11, R8

__string_gsub_copy_inner:
    MOV   R1, [R11]
    MOV   R2, R1
    IEQ   R2, 0
    JT    R2, __string_gsub_copy_hit

    MOV   R1, [R10]
    MOV   R2, R1
    IEQ   R2, 0
    JT    R2, __string_gsub_copy_advance

    MOV   R2, [R11]
    INE   R2, R1
    JT    R2, __string_gsub_copy_advance

    IADD  R10, 1
    IADD  R11, 1
    JMP   __string_gsub_copy_inner

__string_gsub_copy_hit:
    MOV   R10, R9

;; Register note: R2 is free here -- by the time this loop runs, the
;; matching-inner-loop code that also uses R2 as scratch has already
;; exited (this label is only reached via that loop's own JT branch), and
;; nothing in this loop or after it depends on R2's prior value.

__string_gsub_copy_write_repl:
    MOV   R1, [R10]
    ;; FIXED: scratch copy (R2) for the nil-check, instead of testing R1
    ;; directly. R2 is free here -- see note above.
    MOV   R2, R1
    IEQ   R2, 0
    JT    R2, __string_gsub_copy_hit_done
    MOV   [R12], R1
    IADD  R10, 1
    IADD  R12, 1
    JMP   __string_gsub_copy_write_repl
__string_gsub_copy_hit_done:
    IADD  R0, R4
    JMP   __string_gsub_copy_loop

__string_gsub_copy_advance:
    MOV   R1, [R0]
    MOV   [R12], R1
    IADD  R0, 1
    IADD  R12, 1
    JMP   __string_gsub_copy_loop

__string_gsub_copy_done:
    MOV   R1, 0
    MOV   [R12], R1
    MOV   R0, R13
    OR    R0, BOXED_RAMSTRING
    JMP   __string_gsub_finish

__string_gsub_no_match_copy:
    MOV   R0, [BP+2]
    CALL  __unbox_string
    MOV   R7, R0

    PUSH  R7
    CALL  __builtin_string_len
    IADD  SP, 1
    MOV   R3, R0
    CFI   R3

    MOV   R1, R3
    IADD  R1, 1
    PUSH  R1
    CALL  __malloc
    IADD  SP, 1
    MOV   R13, R0

    ;; FIXED: OOM check via scratch register R6 -- free in this path too
    ;; (nothing here uses R6 at all). R13 must stay untouched: "MOV R12,
    ;; R13" below needs the real heap pointer.
    MOV   R6, R13
    IEQ   R6, 0
    JT    R6, __string_gsub_oom

    MOV   R0, R7
    MOV   R12, R13
__string_gsub_plain_copy_loop:
    MOV   R1, [R0]
    MOV   [R12], R1
    IEQ   R1, 0
    JT    R1, __string_gsub_plain_copy_done
    IADD  R0, 1
    IADD  R12, 1
    JMP   __string_gsub_plain_copy_loop
__string_gsub_plain_copy_done:
    MOV   R0, R13
    OR    R0, BOXED_RAMSTRING
    JMP   __string_gsub_finish

__string_gsub_oom:
    MOV   R0, BOXED_NIL

__string_gsub_finish:
    MOV   SP, BP
    POP   BP
    RET

