;; ===========================================================================
;; SECTION: FUNCTION TRAMPOLINE
;; ===========================================================================

; ============================================================================
; __builtin_exec: Safely validates and executes a boxed function pointer (R0)
; ============================================================================
__builtin_exec:
    ; 1. Isolate and validate the NaN-box tag bits
    MOV R1, R0
    AND R1, BOXED_DATA          ; Isolate upper tag bits (adjust if your tag mask differs)
    IEQ R1, BOXED_FUNCTION          ; Is this tagged as a boxed function pointer?
    JT  R1, __exec_valid            ; If valid, jump to unboxing and execution

    ; 2. Tag validation failed! We attempted to call nil, a number, or a table.
    JMP __runtime_error_not_callable

__exec_valid:
    ; 3. Unbox the address and restore the Vircon32 memory page bit
    AND R0, BOXED_PAYLOAD          ; Strip NaN-box tag bits
    OR  R0, V32_CART_PAGE          ; Restore Vircon32 code memory page bit
    
    ; 4. The Tail-Call Jump!
    ; We do NOT use CALL R0 here. Because the original call site executed 
    ; "CALL __builtin_exec", the return address to the script is already on the 
    ; stack. By jumping directly to R0, the target function executes and its own 
    ; "RET" instruction will cleanly return straight to the original caller!
    JMP R0

; ==============================================================================
; Runtime Panic Handler
; ==============================================================================
__runtime_error_not_callable:
    ; Clear screen to dark red to signal a hardware/runtime panic
    MOV R0, 0xFF800000 
    OUT GPU_ClearColor, R0
    OUT GPU_Command, GPUCommand_ClearScreen
    
    ; Prepare screen coordinates for error text (e.g., X=20, Y=20)
    MOV   R0, 20                ; X coordinate
    PUSH  R0
    MOV   R0, 20                ; Y coordinate
    PUSH  R0

    ; Print base error message
    MOV   R0, __const_str_err_call_nil  ; Load base error string address
    PUSH  R0
    CALL __builtin_print        ; Call your runtime's internal print routine
    JMP __panic_halt
    
__panic_halt:
    WAIT                        ; Yield CPU frame to prevent runaway execution
    JMP __panic_halt            ; Trap CPU in an infinite loop
