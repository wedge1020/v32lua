;; ---------------------------------------------------------------------------
;; Built-in: Unpack a Vircon32 TIM_CurrentDate value into (year, month, day)
;;
;; Incoming Stack: [BP+2] = RAW packed date value, exactly as read from the
;;                 TIM_CurrentDate hardware port via `IN`. This must be the
;;                 UNCONVERTED 32-bit integer -- do NOT run it through CIF
;;                 before pushing it here, since CIF would reinterpret the
;;                 packed bit pattern as a float and destroy it. Format (per
;;                 Vircon32 System Specification Part 7, section 1.2.1):
;;                     bits 31-16: CurrentYear      (0-65535)
;;                     bits 15-0 : ElapsedYearDays  (0 = Jan 1st, counting up;
;;                                 max 364, or 365 in a leap year)
;;
;; Returns (as genuine Lua numbers, already CIF-converted), in the standard
;; 3-value multi-return registers:
;;   R0 = year   (e.g. 2026.0)
;;   R2 = month  (1.0 = January ... 12.0 = December)
;;   R3 = day    (1-based day within the month)
;;
;; Leap years use the standard Gregorian rule (divisible by 4, except
;; centuries unless divisible by 400) -- the spec confirms ElapsedYearDays'
;; upper bound extends to 365 "if the present year is considered a leap
;; year" but doesn't itself define the rule, so this is the one sane,
;; universal reading of it.
;;
;; Registers: R0-R9 used freely as scratch (R14/BP, R15/SP preserved), same
;; convention as __builtin_ftoa.
;; ---------------------------------------------------------------------------
__builtin_unpack_date:
    PUSH BP
    MOV  BP, SP

    MOV  R0, [BP+2]          ; R0 = raw packed date
    MOV  R1, R0
    IDIV R1, 65536           ; R1 = CurrentYear
    MOV  R2, R0
    IMOD R2, 65536           ; R2 = ElapsedYearDays -- remaining days to place

    ;; --- Determine leap year: (year%4==0 && year%100!=0) || (year%400==0) ---
    MOV  R3, R1
    IMOD R3, 4
    IEQ  R3, 0
    JF   R3, __unpack_date_not_leap     ; not divisible by 4 -> not leap

    MOV  R3, R1
    IMOD R3, 100
    IEQ  R3, 0
    JF   R3, __unpack_date_is_leap      ; divisible by 4, not by 100 -> leap

    MOV  R3, R1
    IMOD R3, 400
    IEQ  R3, 0
    JT   R3, __unpack_date_is_leap      ; divisible by 400 -> leap
    JMP  __unpack_date_not_leap         ; divisible by 100, not 400 -> not leap

__unpack_date_is_leap:
    MOV  R9, 1
    JMP  __unpack_date_have_leap_flag
__unpack_date_not_leap:
    MOV  R9, 0
__unpack_date_have_leap_flag:

    MOV  R4, 1                ; R4 = month, starting at January

    ;; --- January (31) ---
    MOV  R5, 31
    MOV  R6, R2
    ILT  R6, R5
    JT   R6, __unpack_date_found
    ISUB R2, R5
    IADD R4, 1

    ;; --- February (28, or 29 in a leap year) ---
    MOV  R5, 28
    JF   R9, __unpack_date_feb_len_set
    MOV  R5, 29
__unpack_date_feb_len_set:
    MOV  R6, R2
    ILT  R6, R5
    JT   R6, __unpack_date_found
    ISUB R2, R5
    IADD R4, 1

    ;; --- March (31) ---
    MOV  R5, 31
    MOV  R6, R2
    ILT  R6, R5
    JT   R6, __unpack_date_found
    ISUB R2, R5
    IADD R4, 1

    ;; --- April (30) ---
    MOV  R5, 30
    MOV  R6, R2
    ILT  R6, R5
    JT   R6, __unpack_date_found
    ISUB R2, R5
    IADD R4, 1

    ;; --- May (31) ---
    MOV  R5, 31
    MOV  R6, R2
    ILT  R6, R5
    JT   R6, __unpack_date_found
    ISUB R2, R5
    IADD R4, 1

    ;; --- June (30) ---
    MOV  R5, 30
    MOV  R6, R2
    ILT  R6, R5
    JT   R6, __unpack_date_found
    ISUB R2, R5
    IADD R4, 1

    ;; --- July (31) ---
    MOV  R5, 31
    MOV  R6, R2
    ILT  R6, R5
    JT   R6, __unpack_date_found
    ISUB R2, R5
    IADD R4, 1

    ;; --- August (31) ---
    MOV  R5, 31
    MOV  R6, R2
    ILT  R6, R5
    JT   R6, __unpack_date_found
    ISUB R2, R5
    IADD R4, 1

    ;; --- September (30) ---
    MOV  R5, 30
    MOV  R6, R2
    ILT  R6, R5
    JT   R6, __unpack_date_found
    ISUB R2, R5
    IADD R4, 1

    ;; --- October (31) ---
    MOV  R5, 31
    MOV  R6, R2
    ILT  R6, R5
    JT   R6, __unpack_date_found
    ISUB R2, R5
    IADD R4, 1

    ;; --- November (30) ---
    MOV  R5, 30
    MOV  R6, R2
    ILT  R6, R5
    JT   R6, __unpack_date_found
    ISUB R2, R5
    IADD R4, 1

    ;; --- December (31): whatever's left belongs here -- falls straight ---
    ;; --- into __unpack_date_found without needing its own check.       ---

__unpack_date_found:
    ;; R2 = 0-based day-of-month remaining, R4 = month number
    IADD R2, 1                ; R2 = 1-based day of month

    ;; --- Convert all 3 results to genuine Lua numbers ---
    CIF  R1                    ; year
    CIF  R4                    ; month
    CIF  R2                    ; day

    ;; --- Place into the standard multi-return registers (R0/R2/R3) ---
    ;; ORDER MATTERS: copy day out of R2 BEFORE R2 gets overwritten with
    ;; the month value below.
    MOV  R0, R1                 ; return value 1: year
    MOV  R3, R2                 ; return value 3: day
    MOV  R2, R4                 ; return value 2: month

    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Built-in: Write a non-negative integer as zero-padded decimal ASCII.
;;
;; Incoming Stack: [BP+4] = value      (raw int, >= 0)
;;                 [BP+3] = min_width  (raw int -- minimum digit count; the
;;                          value's OWN digit count is used instead whenever
;;                          it's larger, exactly like printf's "%0*d" --
;;                          this never truncates)
;;                 [BP+2] = destination (raw address to write the first
;;                          digit at)
;; Returns: R0 = new write pointer, i.e. destination + digits written --
;;          the natural place for a subsequent write to continue from.
;; Registers: R0-R13 scratch (R14/BP, R15/SP preserved).
;; ---------------------------------------------------------------------------
__builtin_write_padded_int:
    PUSH BP
    MOV  BP, SP

    MOV  R7, [BP+4]           ; R7 = value (destroyed by the digit loop below)
    MOV  R8, [BP+3]           ; R8 = min_width
    MOV  R9, [BP+2]           ; R9 = write head
    MOV  R6, R9               ; R6 = start of this number's digit span (for reversal)
    MOV  R1, 0                ; R1 = digits written so far

    ;; --- Write digits LSB-first (reversed after) -- always writes at ---
    ;; --- least 1 digit, so value == 0 correctly produces "0".        ---
__padded_digit_loop:
    MOV  R5, R7
    IMOD R5, 10
    IADD R5, 48                ; ASCII digit
    MOV  [R9], R5
    IADD R9, 1
    IADD R1, 1
    IDIV R7, 10
    MOV  R5, R7
    INE  R5, 0
    JT   R5, __padded_digit_loop

    ;; --- Pad with zeros (written here, on the right, since ---
    ;; --- everything gets reversed next) until min_width is met. ---
__padded_pad_loop:
    MOV  R5, R1
    IGE  R5, R8
    JT   R5, __padded_reverse
    MOV  R5, 48                ; ASCII '0'
    MOV  [R9], R5
    IADD R9, 1
    IADD R1, 1
    JMP  __padded_pad_loop

    ;; --- Reverse the whole span in place: R6 = start, R9-1 = end ---
__padded_reverse:
    MOV  R10, R6
    MOV  R11, R9
    ISUB R11, 1
__padded_reverse_loop:
    MOV  R5, R10
    IGE  R5, R11
    JT   R5, __padded_done
    MOV  R12, [R10]
    MOV  R13, [R11]
    MOV  [R10], R13
    MOV  [R11], R12
    IADD R10, 1
    ISUB R11, 1
    JMP  __padded_reverse_loop

__padded_done:
    MOV  R0, R9                ; return new write head
    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Built-in: Format (year, month, day) as a "YYYY-MM-DD" string.
;;
;; Incoming Stack: [BP+4] = year  (raw int)
;;                 [BP+3] = month (raw int, 1-12)
;;                 [BP+2] = day   (raw int, 1-31)
;; Returns: R0 = boxed RAM string ("YYYY-MM-DD", BOXED_RAMSTRING-tagged)
;; ---------------------------------------------------------------------------
__builtin_format_date_string:
    PUSH BP
    MOV  BP, SP

    ;; --- Allocate the buffer: "YYYY-MM-DD" = 10 chars + null = 11 words ---
    MOV  R0, 11
    PUSH R0
    CALL __malloc
    IADD SP, 1

    MOV  R4, R0
    IEQ  R4, 0
    JT   R4, __oom_handler

    PUSH R0                     ; spill the STRING BASE pointer -- must
                                 ; survive every CALL below

    ;; --- Write year, zero-padded to 4 digits ---
    MOV  R1, [BP+4]              ; year
    PUSH R1                      ; value       -> callee [BP+4]
    MOV  R3, 4
    PUSH R3                      ; min_width=4 -> callee [BP+3]
    PUSH R0                      ; destination -> callee [BP+2] (start of buffer)
    CALL __builtin_write_padded_int
    IADD SP, 3
                                  ; R0 = write head after year

    MOV  R5, 45                  ; ASCII '-'
    MOV  [R0], R5
    IADD R0, 1

    ;; --- Write month, zero-padded to 2 digits ---
    MOV  R1, [BP+3]               ; month
    PUSH R1
    MOV  R3, 2
    PUSH R3
    PUSH R0
    CALL __builtin_write_padded_int
    IADD SP, 3

    MOV  R5, 45                   ; ASCII '-'
    MOV  [R0], R5
    IADD R0, 1

    ;; --- Write day, zero-padded to 2 digits ---
    MOV  R1, [BP+2]                ; day
    PUSH R1
    MOV  R3, 2
    PUSH R3
    PUSH R0
    CALL __builtin_write_padded_int
    IADD SP, 3

    MOV  R5, 0                     ; null terminator
    MOV  [R0], R5

    POP  R0                        ; restore STRING BASE pointer
    OR   R0, BOXED_RAMSTRING       ; box the BASE pointer (not the write head)

    MOV  SP, BP
    POP  BP
    RET

