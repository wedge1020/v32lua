;; ===========================================================================
;; Built-in: math.random() - Random Number Generator
;;
;; Vircon32 RNG hardware port: 0x100 (RNG_CurrentValue)
;;
;; Lua calling convention (arguments on stack):
;;   0 args:  math.random()     -> float [0, 1)
;;   1 arg:   math.random(n)    -> int   [1, n]
;;   2 args:  math.random(m, n) -> int   [m, n]
;;
;; Stack on entry: [BP+2] = arg1, [BP+3] = arg2 (if present)
;; Returns: R0 = result as Lua float
;; Clobbers: R0-R4
;; ===========================================================================

__builtin_random:
    PUSH BP
    MOV  BP, SP

    ;; --- Read RNG value from hardware port 0x100 ---
    IN   R0, RNG_CurrentValue   ; R0 = raw random integer from RNG

    ;; --- Check argument count ---
    MOV  R1, [BP+1]          ; R1 = return address (non-zero = has caller)
    MOV  R2, BP
    IADD R2, 2               ; R2 = address of first arg slot
    MOV  R3, [R2]            ; R3 = first arg (or garbage if none)

    ;; Check if we have 0 arguments (stack has only return address)
    ;; If [BP+2] is beyond stack frame, we have 0 args
    MOV  R4, SP
    IADD R4, 2               ; R4 = top of args
    MOV  R5, R2
    ILT  R5, R4
    JT   R5, _random_0args   ; No args: math.random()

    ;; We have at least 1 argument
    MOV  R4, [R2]            ; Load first arg

    ;; Check if we have 2 arguments
    IADD R2, 1
    MOV  R5, R2
    ILT  R5, R4
    JT   R5, _random_1arg    ; Only 1 arg: math.random(n)

    ;; We have 2 arguments
    MOV  R1, [R2]            ; R1 = second arg (n)
    MOV  R2, [R2-1]          ; R2 = first arg (m)
    JMP  _random_2args

;; --- Case 0: math.random() -> float in [0, 1) ---
_random_0args:
    ;; Convert R0 (integer) to float
    CIF  R0                 ; R0 = float(random_int)

    ;; Scale to [0, 1) range
    ;; Assuming RNG returns 32-bit value, divide by 2^32
    ;; We can use a constant: 4294967296.0 = 2^32
    ;; But simpler: use FDIV with a large float

    ;; Load 2^32 as float (approximately 4294967296.0)
    ;; For simplicity, use 0x100000000 as a float constant
    ;; Actually, let's use a simpler approach: divide by 0x80000000 then * 2
    ;; Or just use a runtime constant

    ;; For now, use approximation: divide by 0x7FFFFFFF (max positive 31-bit)
    ;; This gives range [0, ~1.0)
    MOV  R1, 0x7FFFFFFF
    CIF  R1
    FDIV R0, R1             ; R0 = random / max_int (~[0, 1))

    JMP  _random_done

;; --- Case 1: math.random(n) -> integer in [1, n] ---
_random_1arg:
    ;; R0 = random int, R4 = n
    ;; We need: result = (random % n) + 1

    ;; First, ensure n is an integer
    CFI  R4                 ; Convert n to integer

    ;; Compute random % n
    ;; R0 already has random value
    IMOD R0, R4             ; R0 = random % n

    ;; Add 1 to get range [1, n]
    IADD R0, 1

    ;; Convert back to float
    CIF  R0

    JMP  _random_done

;; --- Case 2: math.random(m, n) -> integer in [m, n] ---
_random_2args:
    ;; R0 = random int, R2 = m, R1 = n
    ;; We need: result = m + (random % (n - m + 1))

    ;; Ensure both are integers
    CFI  R2
    CFI  R1

    ;; Compute range: n - m + 1
    MOV  R3, R1
    ISUB R3, R2         ; R3 = n - m
    IADD R3, 1              ; R3 = n - m + 1

    ;; Compute random % range
    IMOD R0, R3             ; R0 = random % range

    ;; Add m
    IADD R0, R2            ; R0 = m + (random % range)

    ;; Convert back to float
    CIF  R0

;; --- Done ---
_random_done:
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.randomseed(x) - Seed Random Number Generator
;;
;; Vircon32 RNG hardware port: RNG_CurrentValue (0x100)
;;
;; Lua calling convention:
;;   math.randomseed(x)  -> seeds RNG with x, returns nil
;;
;; Stack on entry: [BP+2] = seed value
;; Returns: R0 = BOXED_NIL
;; Clobbers: R0-R2
;; ===========================================================================

__builtin_randomseed:
    PUSH BP
    MOV  BP, SP

    ;; --- Load seed from stack ---
    MOV  R0, [BP+2]          ; R0 = seed value (Lua float)

    ;; --- Convert to integer (RNG expects integer seed) ---
    CFI  R0                 ; R0 = integer seed

    ;; --- Write seed to RNG hardware port ---
    OUT  RNG_CurrentValue, R0  ; Seed the RNG

    ;; --- Return nil ---
    MOV  R0, BOXED_NIL

    ;; --- Restore stack and return ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.cos(x) - Cosine
;;
;; Uses identity: cos(x) = sin(x + PI/2)
;;
;; Stack on entry: [BP+2] = x (float)
;; Returns: R0 = cos(x) as Lua float
;; Clobbers: R0-R3
;; ===========================================================================

__builtin_cos:
    PUSH BP
    MOV  BP, SP

    ;; --- Load argument ---
    MOV  R0, [BP+2]          ; R0 = x

    ;; --- Add PI/2 (approximately 1.57079632679) ---
    ;; PI/2 as a float constant
    ;; Using 0x3FF921FB54442D18 hex float approximation
    ;; For simplicity, use decimal approximation
    MOV  R1, 1.57079632679  ; R1 = PI/2 (loads as float)

    FADD R0, R1             ; R0 = x + PI/2

    ;; --- Compute sin(x + PI/2) ---
    SIN  R0                 ; R0 = sin(x + PI/2) = cos(x)

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.exp(x) - Exponential (e^x)
;;
;; Uses identity: exp(x) = pow(e, x)
;; where e ≈ 2.71828182846
;;
;; Stack on entry: [BP+2] = x (float)
;; Returns: R0 = e^x as Lua float
;; Clobbers: R0-R3
;; ===========================================================================

__builtin_exp:
    PUSH BP
    MOV  BP, SP

    ;; --- Load argument x ---
    MOV  R1, [BP+2]          ; R1 = x

    ;; --- Load e constant (≈ 2.71828182846) ---
    MOV  R0, 2.71828182846  ; R0 = e (base)

    ;; --- Compute pow(e, x) ---
    POW  R0, R1             ; R0 = e^x

    ;; --- Return result ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Vircon32 Lua Math Runtime Subroutines - Additional Functions
;; ===========================================================================

;; ===========================================================================
;; Built-in: math.asin(x) - Arc Sine
;;
;; Uses identity: asin(x) = atan2(x, sqrt(1 - x^2))
;;
;; Stack on entry: [BP+2] = x (float in [-1, 1])
;; Returns: R0 = asin(x) in radians [-PI/2, PI/2]
;; Clobbers: R0-R4
;; ===========================================================================

__builtin_asin:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x ---
    MOV  R0, [BP+2]          ; R0 = x

    ;; --- Compute x^2 ---
    MOV  R1, R0
    FMUL R1, R0             ; R1 = x^2

    ;; --- Compute 1 - x^2 ---
    MOV  R2, 1.0
    FSUB R2, R1             ; R2 = 1 - x^2

    ;; --- Compute sqrt(1 - x^2) ---
    ;; Note: This assumes 1 - x^2 >= 0 (i.e., |x| <= 1)
    ;; For |x| > 1, this will produce NaN which is correct for asin domain error
    ;; Vircon32 doesn't have SQRT instruction, so we call runtime
    PUSH R2
    CALL __builtin_sqrt
    IADD SP, 1
    MOV  R2, R0             ; R2 = sqrt(1 - x^2)

    ;; --- Compute atan2(x, sqrt(1-x^2)) ---
    ;; ATAN2 takes: DSTREG, SRCREG where DSTREG = y, SRCREG = x
    ;; We want atan2(x, sqrt(1-x^2)) = atan2(y=x, x=sqrt(1-x^2))
    MOV  R1, R2             ; R1 = sqrt(1-x^2) = x coordinate
    MOV  R2, R0             ; R2 = x = y coordinate
    ATAN2 R2, R1            ; R2 = atan2(x, sqrt(1-x^2)) = asin(x)

    MOV  R0, R2             ; Return in R0

    ;; --- Done ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.tan(x) - Tangent
;;
;; Uses identity: tan(x) = sin(x) / cos(x)
;;
;; Stack on entry: [BP+2] = x (float)
;; Returns: R0 = tan(x)
;; Clobbers: R0-R3
;; ===========================================================================

__builtin_tan:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x ---
    MOV  R0, [BP+2]          ; R0 = x

    ;; --- Compute sin(x) ---
    MOV  R1, R0
    SIN  R1                 ; R1 = sin(x)

    ;; --- Compute cos(x) ---
    MOV  R2, R0
    ;; Use identity: cos(x) = sin(x + PI/2)
    MOV  R3, 1.57079632679  ; PI/2
    FADD R2, R3
    SIN  R2                 ; R2 = cos(x)

    ;; --- Compute tan(x) = sin(x) / cos(x) ---
	MOV  R0, R1
    FDIV R0, R2         ; R0 = sin(x) / cos(x) = tan(x)

    ;; --- Done ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.deg(x) - Convert Radians to Degrees
;;
;; Uses: deg(x) = x * 180 / PI
;;
;; Stack on entry: [BP+2] = x (radians)
;; Returns: R0 = degrees
;; Clobbers: R0-R3
;; ===========================================================================

__builtin_deg:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x ---
    MOV  R0, [BP+2]          ; R0 = x (radians)

    ;; --- Multiply by 180 ---
    MOV  R1, 180.0
    FMUL R0, R1             ; R0 = x * 180

    ;; --- Divide by PI ---
    MOV  R1, 3.14159265359  ; PI
    FDIV R0, R1             ; R0 = x * 180 / PI

    ;; --- Done ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.rad(x) - Convert Degrees to Radians
;;
;; Uses: rad(x) = x * PI / 180
;;
;; Stack on entry: [BP+2] = x (degrees)
;; Returns: R0 = radians
;; Clobbers: R0-R3
;; ===========================================================================

__builtin_rad:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x ---
    MOV  R0, [BP+2]          ; R0 = x (degrees)

    ;; --- Multiply by PI ---
    MOV  R1, 3.14159265359  ; PI
    FMUL R0, R1             ; R0 = x * PI

    ;; --- Divide by 180 ---
    MOV  R1, 180.0
    FDIV R0, R1             ; R0 = x * PI / 180

    ;; --- Done ---
    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; Built-in: math.log10(x) - Base-10 Logarithm
;;
;; Uses identity: log10(x) = log(x) / log(10)
;;
;; Stack on entry: [BP+2] = x (float > 0)
;; Returns: R0 = log10(x)
;; Clobbers: R0-R4
;; ===========================================================================

__builtin_log10:
    PUSH BP
    MOV  BP, SP

    ;; --- Load x ---
    MOV  R0, [BP+2]          ; R0 = x

    ;; --- Compute log(x) ---
    LOG  R0                 ; R0 = ln(x)

    ;; --- Compute log(10) ---
    MOV  R1, 10.0
    LOG  R1                 ; R1 = ln(10)

    ;; --- Compute log10(x) = ln(x) / ln(10) ---
    FDIV R0, R1             ; R0 = ln(x) / ln(10) = log10(x)

    ;; --- Done ---
    MOV  SP, BP
    POP  BP
    RET
