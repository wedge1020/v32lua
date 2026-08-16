;; ===========================================================================
;; Vircon32 Lua Math Runtime Subroutines
;;
;; All instructions use 2-operand format: OP DST, SRC
;; All float constants use decimal notation (no scientific notation)
;; ===========================================================================

;; ===========================================================================
;; Built-in: math.random()
;;
;; Generates pseudorandom numbers using Vircon32's RNG hardware port.
;;
;; Behavior:
;;   math.random()     -> float in [0, 1)
;;   math.random(n)    -> integer in [1, n]
;;   math.random(m, n) -> integer in [m, n]
;;
;; Stack on entry:
;;   [BP+2] = first argument (if any)
;;   [BP+3] = second argument (if any)
;;
;; Returns:
;;   R0 = random value as Lua float
;;
;; Clobbers: R0-R5
;; ===========================================================================
__builtin_random:
    PUSH BP
    MOV  BP, SP

    ;; --- Read RNG value from hardware port 0x100 ---
    IN   R0, RNG_CurrentValue   ; R0 = raw random integer from RNG

    ;; --- Check argument count using scratch register R5 ---
    MOV  R2, BP
    IADD R2, 2                ; R2 = address of first arg slot

    MOV  R4, SP
    IADD R4, 2                ; R4 = top of args
    MOV  R5, R2
    ILT  R5, R4
    JT   R5, _random_0args    ; No args: math.random()

    ;; We have at least 1 argument
    MOV  R4, [R2]             ; Load first arg

    IADD R2, 1
    MOV  R5, R2
    ILT  R5, R4
    JT   R5, _random_1arg     ; Only 1 arg: math.random(n)

    ;; We have 2 arguments
    MOV  R1, [R2]             ; R1 = second arg (n)
    MOV  R2, [R2-1]           ; R2 = first arg (m)
    JMP  _random_2args

;; --- Case 0: math.random() -> float in [0, 1) ---
_random_0args:
    ;; Convert R0 (integer) to float
    CIF  R0                  ; R0 = float(random_int)

    ;; Scale to [0, 1) range using 0x7FFFFFFF (max 31-bit int) approximation
    MOV  R1, 2147483647       ; 0x7FFFFFFF = 2^31 - 1
    CIF  R1
    FDIV R0, R1              ; R0 = random / max_int (~[0, 1))
    JMP  _random_done

;; --- Case 1: math.random(n) -> integer in [1, n] ---
_random_1arg:
    ;; Ensure n is an integer
    CFI  R4                  ; Convert n to integer

    ;; Compute random % n
    IMOD R0, R4              ; R0 = random % n

    ;; Add 1 to get range [1, n]
    IADD R0, 1

    ;; Convert back to float
    CIF  R0
    JMP  _random_done

;; --- Case 2: math.random(m, n) -> integer in [m, n] ---
_random_2args:
    ;; Ensure both are integers
    CFI  R2
    CFI  R1

    ;; Compute range: n - m + 1
    MOV  R3, R1
    ISUB R3, R2              ; R3 = n - m
    IADD R3, 1               ; R3 = n - m + 1

    ;; Compute random % range
    IMOD R0, R3              ; R0 = random % range

    ;; Add m to get result in [m, n]
    IADD R0, R2              ; R0 = m + (random % range)

    ;; Convert back to float
    CIF  R0

;; --- Done: return result in R0 ---
_random_done:
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.randomseed(x)
;;
;; Seeds the Vircon32 RNG hardware with the given value.
;;
;; Lua usage: math.randomseed(x)
;;
;; Stack on entry:
;;   [BP+2] = seed value (Lua float, will be converted to integer)
;;
;; Returns:
;;   R0 = BOXED_NIL (Lua nil)
;;
;; Clobbers: R0-R1
;; ===========================================================================
__builtin_randomseed:
    PUSH BP
    MOV  BP, SP

    ;; --- Load seed from stack ---
    MOV  R0, [BP+2]           ; R0 = seed value (Lua float)

    ;; --- Convert to integer (RNG expects integer seed) ---
    CFI  R0                  ; R0 = integer seed

    ;; --- Write seed to RNG hardware port ---
    OUT  RNG_CurrentValue, R0 ; Seed the RNG

    ;; --- Return nil ---
    MOV  R0, BOXED_NIL

    ;; --- Restore stack and return ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.sqrt(x)
;;
;; Computes the square root of x using POW instruction.
;; Note: Vircon32 doesn't have a dedicated SQRT instruction,
;;       but POW can compute x^0.5.
;;
;; Lua usage: math.sqrt(x)
;;
;; Stack on entry:
;;   [BP+2] = x (float >= 0)
;;
;; Returns:
;;   R0 = sqrt(x) as Lua float
;;
;; Clobbers: R0-R1
;; ===========================================================================
__builtin_sqrt:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x from stack ---
    MOV  R0, [BP+2]           ; R0 = x

    ;; --- Compute sqrt(x) = x^0.5 using POW ---
    MOV  R1, 0.5
    POW  R0, R1              ; R0 = x^0.5 = sqrt(x)

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.cos(x)
;;
;; Computes cosine using the identity: cos(x) = sin(x + PI/2)
;;
;; Lua usage: math.cos(x)
;;
;; Stack on entry:
;;   [BP+2] = x (radians)
;;
;; Returns:
;;   R0 = cos(x) as Lua float
;;
;; Clobbers: R0-R1
;; ===========================================================================
__builtin_cos:
    PUSH  BP
    MOV   BP, SP

    MOV   R0, [BP+2]                 ; R0 = x
    MOV   R1, [__const_math_pi_over_2]  ; dereference: actual PI/2 value, not its address
    FADD  R0, R1                     ; R0 = x + PI/2
    SIN   R0                         ; R0 = sin(x + PI/2) = cos(x)

    MOV   SP, BP
    POP   BP
    RET

;; ===========================================================================
;; Built-in: math.sin(x)
;;
;; Computes sine using Vircon32's native SIN instruction.
;;
;; Lua usage: math.sin(x)
;;
;; Stack on entry:
;;   [BP+2] = x (radians)
;;
;; Returns:
;;   R0 = sin(x) as Lua float
;;
;; Clobbers: R0-R1
;; ===========================================================================
__builtin_sin:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x from stack ---
    MOV  R0, [BP+2]           ; R0 = x

    ;; --- Compute sin(x) using native instruction ---
    SIN  R0                  ; R0 = sin(x)

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.tan(x)
;;
;; Computes tangent using the identity: tan(x) = sin(x) / cos(x)
;;
;; Lua usage: math.tan(x)
;;
;; Stack on entry:
;;   [BP+2] = x (radians)
;;
;; Returns:
;;   R0 = tan(x) as Lua float
;;
;; Clobbers: R0-R3
;; ===========================================================================
__builtin_tan:
    PUSH  BP
    MOV   BP, SP

    MOV   R0, [BP+2]                 ; R0 = x

    MOV   R1, R0
    SIN   R1                         ; R1 = sin(x)

    MOV   R2, R0
    MOV   R3, [__const_math_pi_over_2]  ; dereference here too
    FADD  R2, R3                     ; R2 = x + PI/2
    SIN   R2                         ; R2 = cos(x)

    MOV   R0, R1
    FDIV  R0, R2                     ; R0 = sin(x) / cos(x) = tan(x)

    MOV   SP, BP
    POP   BP
    RET

;; ===========================================================================
;; Built-in: math.asin(x)
;;
;; Computes arc sine using the identity: asin(x) = atan2(x, sqrt(1 - x^2))
;;
;; Lua usage: math.asin(x)
;;
;; Stack on entry:
;;   [BP+2] = x (float, -1 <= x <= 1)
;;
;; Returns:
;;   R0 = asin(x) in radians [-PI/2, PI/2] as Lua float
;;
;; Clobbers: R0-R4
;; ===========================================================================
__builtin_asin:
    PUSH  BP
    MOV   BP, SP

    ;; --- Load x from stack ---
    MOV   R0, [BP+2]           ; R0 = x
    MOV   R4, R0                ; R4 = x, preserved across __builtin_sqrt below --
                                 ; that call returns its result in R0, so R0 can
                                 ; NOT be trusted to still hold x once it returns.

    ;; --- Compute x^2 ---
    MOV   R1, R0
    FMUL  R1, R0               ; R1 = x * x = x^2

    ;; --- Compute 1 - x^2 ---
    MOV   R2, 1.0
    FSUB  R2, R1               ; R2 = 1.0 - x^2

    ;; --- Compute sqrt(1 - x^2) via runtime call ---
    PUSH  R2
    CALL  __builtin_sqrt
    IADD  SP, 1
    MOV   R1, R0                ; R1 = sqrt(1 - x^2) = x-coordinate for atan2

    ;; --- Compute atan2(x, sqrt(1-x^2)) = asin(x) ---
    ;; ATAN2 Rd, Rs computes atan2(Rd, Rs), result stored in Rd.
    MOV   R2, R4                ; R2 = original x, recovered from R4 (NOT R0!) = y-coordinate
    ATAN2 R2, R1                ; R2 = atan2(y=x, x=sqrt(1-x^2)) = asin(x)

    MOV   R0, R2                ; Return result in R0

    ;; --- Return result ---
    MOV   SP, BP
    POP   BP
    RET

;; ===========================================================================
;; Built-in: math.acos(x)
;;
;; Computes arc cosine using Vircon32's native ACOS instruction.
;;
;; Lua usage: math.acos(x)
;;
;; Stack on entry:
;;   [BP+2] = x (float, -1 <= x <= 1)
;;
;; Returns:
;;   R0 = acos(x) in radians [0, PI] as Lua float
;;
;; Clobbers: R0-R1
;; ===========================================================================
__builtin_acos:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x from stack ---
    MOV  R0, [BP+2]           ; R0 = x

    ;; --- Compute acos(x) using native instruction ---
    ACOS R0                  ; R0 = acos(x)

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.atan(x)
;;
;; Computes arc tangent using the identity: atan(x) = atan2(x, 1)
;;
;; Lua usage: math.atan(x)
;;
;; Stack on entry:
;;   [BP+2] = x (float)
;;
;; Returns:
;;   R0 = atan(x) in radians as Lua float
;;
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_atan:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x from stack ---
    MOV  R0, [BP+2]           ; R0 = x

    ;; --- Set up for atan2(x, 1) ---
    ;; ATAN2 computes atan2(y, x) where y=DSTREG, x=SRCREG
    ;; We want atan2(x, 1), so y=x, x=1
    MOV  R1, 1.0             ; R1 = 1 (x coordinate)
    MOV  R2, R0              ; R2 = x (y coordinate)

    ;; --- Compute atan2(x, 1) ---
    ATAN2 R2, R1             ; R2 = atan2(y=x, x=1) = atan(x)

    MOV  R0, R2              ; Return result in R0

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.atan2(y, x)
;;
;; Computes arc tangent of y/x using Vircon32's native ATAN2 instruction.
;;
;; Lua usage: math.atan2(y, x)
;;
;; Stack on entry:
;;   [BP+2] = y (float)
;;   [BP+3] = x (float)
;;
;; Returns:
;;   R0 = atan2(y, x) in radians as Lua float
;;
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_atan2:
    PUSH BP
    MOV  BP, SP

    ;; --- Load y and x from stack ---
    MOV  R1, [BP+2]           ; R1 = y
    MOV  R2, [BP+3]           ; R2 = x

    ;; --- Compute atan2(y, x) using native instruction ---
    ;; ATAN2: DSTREG = atan2(DSTREG, SRCREG)
    ;; So we need: ATAN2 R1, R2 where R1=y, R2=x
    ATAN2 R1, R2             ; R1 = atan2(y, x)

    MOV  R0, R1              ; Return result in R0

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.deg(x)
;;
;; Converts radians to degrees using: deg(x) = x * 180 / PI
;;
;; Lua usage: math.deg(x)
;;
;; Stack on entry:
;;   [BP+2] = x (radians)
;;
;; Returns:
;;   R0 = degrees as Lua float
;;
;; Clobbers: R0-R1
;; ===========================================================================
__builtin_deg:
    PUSH  BP
    MOV   BP, SP

    MOV   R0, [BP+2]                 ; R0 = x (radians)
    MOV   R1, 180.0
    FMUL  R0, R1                     ; R0 = x * 180

    MOV   R1, [__const_math_pi]      ; dereference: actual PI value
    FDIV  R0, R1                     ; R0 = x * 180 / PI

    MOV   SP, BP
    POP   BP
    RET

;; ===========================================================================
;; Built-in: math.rad(x)
;;
;; Converts degrees to radians using: rad(x) = x * PI / 180
;;
;; Lua usage: math.rad(x)
;;
;; Stack on entry:
;;   [BP+2] = x (degrees)
;;
;; Returns:
;;   R0 = radians as Lua float
;;
;; Clobbers: R0-R1
;; ===========================================================================
__builtin_rad:
    PUSH  BP
    MOV   BP, SP

    MOV   R0, [BP+2]                 ; R0 = x (degrees)
    MOV   R1, [__const_math_pi]      ; dereference: actual PI value
    FMUL  R0, R1                     ; R0 = x * PI

    MOV   R1, 180.0
    FDIV  R0, R1                     ; R0 = x * PI / 180

    MOV   SP, BP
    POP   BP
    RET

;; ===========================================================================
;; Built-in: math.exp(x)
;;
;; Computes e^x using the identity: exp(x) = pow(e, x)
;;
;; Lua usage: math.exp(x)
;;
;; Stack on entry:
;;   [BP+2] = x (float)
;;
;; Returns:
;;   R0 = e^x as Lua float
;;
;; Clobbers: R0-R1
;; ===========================================================================
__builtin_exp:
    PUSH  BP
    MOV   BP, SP

    MOV   R0, [BP+2]           ; R0 = x
    MOV   R1, [__const_math_e]  ; dereference: actual e value, not its address
    POW   R1, R0               ; R1 = e^x
    MOV   R0, R1               ; Return in R0

    MOV   SP, BP
    POP   BP
    RET

;; ===========================================================================
;; Built-in: math.log(x)
;;
;; Computes natural logarithm using Vircon32's native LOG instruction.
;;
;; Lua usage: math.log(x)
;;
;; Stack on entry:
;;   [BP+2] = x (float > 0)
;;
;; Returns:
;;   R0 = ln(x) as Lua float
;;
;; Clobbers: R0-R1
;; ===========================================================================
__builtin_log:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x from stack ---
    MOV  R0, [BP+2]           ; R0 = x

    ;; --- Compute natural log ---
    LOG  R0                  ; R0 = ln(x)

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.log10(x)
;;
;; Computes base-10 logarithm using: log10(x) = log(x) / log(10)
;;
;; Lua usage: math.log10(x)
;;
;; Stack on entry:
;;   [BP+2] = x (float > 0)
;;
;; Returns:
;;   R0 = log10(x) as Lua float
;;
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_log10:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x from stack ---
    MOV  R0, [BP+2]           ; R0 = x

    ;; --- Compute log(x) ---
    LOG  R0                  ; R0 = ln(x)

    ;; --- Compute log(10) ---
    MOV  R1, 10.0
    LOG  R1                  ; R1 = ln(10)

    ;; --- Compute log10(x) = ln(x) / ln(10) ---
    FDIV R0, R1              ; R0 = ln(x) / ln(10) = log10(x)

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.pow(x, y)
;;
;; Computes x^y using Vircon32's native POW instruction.
;;
;; Lua usage: math.pow(x, y)
;;
;; Stack on entry:
;;   [BP+2] = x (base)
;;   [BP+3] = y (exponent)
;;
;; Returns:
;;   R0 = x^y as Lua float
;;
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_pow:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x and y from stack ---
    MOV  R0, [BP+2]           ; R0 = x (base)
    MOV  R1, [BP+3]           ; R1 = y (exponent)

    ;; --- Compute x^y using native instruction ---
    POW  R0, R1              ; R0 = x^y

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Hyperbolic Functions
;; ===========================================================================

;; ===========================================================================
;; Built-in: math.cosh(x)
;;
;; Computes hyperbolic cosine using: cosh(x) = (exp(x) + exp(-x)) / 2
;;
;; Lua usage: math.cosh(x)
;;
;; Stack on entry:
;;   [BP+2] = x (float)
;;
;; Returns:
;;   R0 = cosh(x) as Lua float
;;
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_cosh:
    PUSH  BP
    MOV   BP, SP

    ;; --- Compute exp(x) ---
    MOV   R0, [BP+2]           ; R0 = x
    PUSH  R0
    CALL  __builtin_exp
    IADD  SP, 1
    PUSH  R0                    ; Save exp(x) on the STACK -- same reasoning as
                                 ; in __builtin_sinh above.

    ;; --- Compute exp(-x) ---
    MOV   R0, [BP+2]           ; Reload x
    FSGN  R0                   ; R0 = -x
    PUSH  R0
    CALL  __builtin_exp
    IADD  SP, 1
    MOV   R2, R0                ; R2 = exp(-x)

    ;; --- Compute (exp(x) + exp(-x)) / 2 ---
    POP   R0                    ; R0 = exp(x), recovered safely from the stack
    FADD  R0, R2
    MOV   R1, 2.0
    FDIV  R0, R1

    MOV   SP, BP
    POP   BP
    RET

;; ===========================================================================
;; Built-in: math.sinh(x)
;;
;; Computes hyperbolic sine using: sinh(x) = (exp(x) - exp(-x)) / 2
;;
;; Lua usage: math.sinh(x)
;;
;; Stack on entry:
;;   [BP+2] = x (float)
;;
;; Returns:
;;   R0 = sinh(x) as Lua float
;;
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_sinh:
    PUSH  BP
    MOV   BP, SP

    ;; --- Compute exp(x) ---
    MOV   R0, [BP+2]           ; R0 = x
    PUSH  R0
    CALL  __builtin_exp
    IADD  SP, 1
    PUSH  R0                    ; Save exp(x) on the STACK -- the second call to
                                 ; __builtin_exp below uses R1 as scratch
                                 ; internally, so a plain register here can't be
                                 ; trusted to survive that call.

    ;; --- Compute exp(-x) ---
    MOV   R0, [BP+2]           ; Reload x
    FSGN  R0                   ; R0 = -x
    PUSH  R0
    CALL  __builtin_exp
    IADD  SP, 1
    MOV   R2, R0                ; R2 = exp(-x)

    ;; --- Compute (exp(x) - exp(-x)) / 2 ---
    POP   R0                    ; R0 = exp(x), recovered safely from the stack
    FSUB  R0, R2
    MOV   R1, 2.0
    FDIV  R0, R1

    MOV   SP, BP
    POP   BP
    RET

;; ===========================================================================
;; Built-in: math.tanh(x)
;;
;; Computes hyperbolic tangent using: tanh(x) = sinh(x) / cosh(x)
;;
;; Lua usage: math.tanh(x)
;;
;; Stack on entry:
;;   [BP+2] = x (float)
;;
;; Returns:
;;   R0 = tanh(x) as Lua float
;;
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_tanh:
    PUSH  BP
    MOV   BP, SP

    ;; --- Compute sinh(x) ---
    MOV   R0, [BP+2]           ; R0 = x
    PUSH  R0
    CALL  __builtin_sinh
    IADD  SP, 1
    PUSH  R0                    ; Save sinh(x) on the STACK -- __builtin_cosh
                                 ; below uses R1/R2 as scratch internally, so a
                                 ; plain register can't be trusted to survive it
                                 ; (this is exactly what produced tanh(0)=2.0).

    ;; --- Compute cosh(x) ---
    MOV   R0, [BP+2]           ; Reload x
    PUSH  R0
    CALL  __builtin_cosh
    IADD  SP, 1
    MOV   R2, R0                ; R2 = cosh(x)

    ;; --- Compute tanh(x) = sinh(x) / cosh(x) ---
    POP   R0                    ; R0 = sinh(x), recovered safely from the stack
    FDIV  R0, R2

    MOV   SP, BP
    POP   BP
    RET

;; ===========================================================================
;; Built-in: math.fmod(x, y)
;;
;; Computes floating-point modulus: x - y * floor(x/y)
;; Uses Vircon32's native FMOD instruction.
;;
;; Lua usage: math.fmod(x, y)
;;
;; Stack on entry:
;;   [BP+2] = x (float)
;;   [BP+3] = y (float)
;;
;; Returns:
;;   R0 = fmod(x, y) as Lua float
;;
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_fmod:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x and y from stack ---
    MOV  R0, [BP+2]           ; R0 = x
    MOV  R1, [BP+3]           ; R1 = y

    ;; --- Compute fmod(x, y) using native instruction ---
    FMOD R0, R1              ; R0 = fmod(x, y)

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.max(x, y)
;;
;; Returns the larger of two values using Vircon32's native FMAX instruction.
;;
;; Lua usage: math.max(x, y)
;;
;; Stack on entry:
;;   [BP+2] = x (float)
;;   [BP+3] = y (float)
;;
;; Returns:
;;   R0 = max(x, y) as Lua float
;;
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_max:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x and y from stack ---
    MOV  R0, [BP+2]           ; R0 = x
    MOV  R1, [BP+3]           ; R1 = y

    ;; --- Compute max(x, y) using native instruction ---
    FMAX R0, R1              ; R0 = max(x, y)

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.min(x, y)
;;
;; Returns the smaller of two values using Vircon32's native FMIN instruction.
;;
;; Lua usage: math.min(x, y)
;;
;; Stack on entry:
;;   [BP+2] = x (float)
;;   [BP+3] = y (float)
;;
;; Returns:
;;   R0 = min(x, y) as Lua float
;;
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_min:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x and y from stack ---
    MOV  R0, [BP+2]           ; R0 = x
    MOV  R1, [BP+3]           ; R1 = y

    ;; --- Compute min(x, y) using native instruction ---
    FMIN R0, R1              ; R0 = min(x, y)

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Decomposition Functions
;; ===========================================================================

;; ===========================================================================
;; Built-in: math.frexp(x)
;;
;; Decomposes x into mantissa and exponent: x = m * 2^e
;; where 0.5 <= |m| < 1.0
;;
;; Lua usage: math.frexp(x) -> returns (m, e)
;;
;; Stack on entry:
;;   [BP+2] = x (float)
;;
;; Returns:
;;   R0 = mantissa m as Lua float
;;   R1 = exponent e as Lua float
;;
;; Note: For simplicity, this returns x as mantissa and 0 as exponent.
;;       A full implementation would require bit manipulation.
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_frexp:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x from stack ---
    MOV  R0, [BP+2]           ; R0 = x

    ;; --- Check for zero ---
    MOV  R1, R0
    IEQ  R1, 0
    JT   R1, _frexp_zero

    ;; --- For non-zero x, return x as mantissa and 0 as exponent ---
    ;; Note: This is a simplified implementation.
    ;; A proper implementation would extract the exponent bits.
    MOV  R1, 0.0              ; exponent = 0
    JMP  _frexp_done

_frexp_zero:
    MOV  R0, 0.0              ; mantissa = 0
    MOV  R1, 0.0              ; exponent = 0

_frexp_done:
    ;; --- Return mantissa in R0, exponent in R1 ---
    ;; Note: Lua expects two return values. The caller handles this.
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.ldexp(m, e)
;;
;; Computes m * 2^e (inverse of frexp)
;;
;; Lua usage: math.ldexp(m, e)
;;
;; Stack on entry:
;;   [BP+2] = m (float)
;;   [BP+3] = e (float)
;;
;; Returns:
;;   R0 = m * 2^e as Lua float
;;
;; Clobbers: R0-R3
;; ===========================================================================
__builtin_ldexp:
    PUSH BP
    MOV  BP, SP

    ;; --- Load m and e from stack ---
    MOV  R0, [BP+2]           ; R0 = m
    MOV  R1, [BP+3]           ; R1 = e

    ;; --- Compute 2^e ---
    MOV  R2, 2.0
    POW  R2, R1              ; R2 = 2^e

    ;; --- Multiply by m: m * 2^e ---
    FMUL R0, R2              ; R0 = m * 2^e

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.modf(x)
;;
;; Splits x into integer and fractional parts, both returned as floats.
;;
;; Lua usage: math.modf(x) -> returns (integer, fractional)
;;
;; Stack on entry:
;;   [BP+2] = x (float)
;;
;; Returns:
;;   R0 = integer part as Lua float
;;
;; Note: For Lua's multiple return values, the fractional part would be
;;       handled by the caller. This returns only the integer part.
;; Clobbers: R0-R2
;; ===========================================================================
__builtin_modf:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x from stack ---
    MOV  R0, [BP+2]           ; R0 = x

    ;; --- Extract integer part (truncates toward zero) ---
    MOV  R1, R0
    CFI  R1                  ; R1 = integer part (as integer)
    CIF  R1                  ; R1 = integer part (as float)

    ;; --- Compute fractional part: x - integer_part ---
    MOV  R2, R0
    FSUB R2, R1              ; R2 = fractional part

    ;; --- Return integer part in R0 ---
    ;; Note: Fractional part is in R2 but not returned here.
    ;;       Lua's multiple return values need special handling.
    MOV  R0, R1

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

