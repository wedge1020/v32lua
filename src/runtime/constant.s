;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; SECTION: ROM DATA & STRING CONSTANTS
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__const_str_nil:
    string "nil"

__const_str_false:
    string "false"

__const_str_true:
    string "true"

__const_str_table:
    string "table"

__const_str_function:
    string "function"

__const_str_err_call_nil:
    string "RUNTIME ERROR: ATTEMPT TO CALL NIL"

__const_str_pause:
    string "PAUSED"

;; ===========================================================================
;; Math Constants for Lua Library
;; ===========================================================================

;; ===========================================================================
;; Mathematical constants used by various math functions.
;; Each constant is defined as a float value for use in computations.
;; ===========================================================================
__const_math_pi:
    float 3.141592653589793   ; PI constant
__const_math_e:
    float 2.718281828459045   ; Euler's number (e)
__const_math_pi_over_2:
    float 1.570796326794897   ; PI/2 (90 degrees in radians)
__const_math_sqrt2_over_2:
    float 0.707106781186547   ; sqrt(2)/2

;; For math.huge: use maximum representable float value
;; IEEE 754 single precision max: approximately 3.4028235e+38
;; Represented as decimal: 340282356791093500000000000000000000000.0 is too large
;; Using a practical large value that fits in 32-bit float:
__const_math_huge:
    float 3402823466385288.0   ; Maximum finite single-precision float

