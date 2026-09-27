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

    ; 2. Not a function: a table whose metatable has __call is callable --
    ;    __call(t, ...). Anything else is the runtime error.
    MOV R1, R0
    AND R1, BOXED_DATA
    IEQ R1, BOXED_TABLE
    JF  R1, __runtime_error_not_callable
    PUSH R0
    MOV R1, __mm_str_call
    OR  R1, BOXED_ROMSTRING
    CALL __table_metamethod          ; R0 = __call, or nil
    MOV R1, R0
    AND R1, BOXED_DATA
    IEQ R1, BOXED_FUNCTION
    JF  R1, __exec_call_not_callable
    ;; The table becomes the first argument: it takes the return address's
    ;; slot (right above the caller's arguments); the return address goes
    ;; on a small side stack and the callee returns through
    ;; __exec_call_return, which drops the table and goes back -- so the
    ;; caller's own argument clean-up stays balanced.
    MOV R2, R0                       ; R2 = __call
    POP R0                           ; R0 = the table
    POP R1                           ; R1 = caller's return address
    PUSH R0                          ; the table: argument 1
    MOV R0, [META_CALL_DEPTH]
    MOV R3, R0
    IGE R3, META_CALL_STACK_SIZE
    JT  R3, __runtime_error_not_callable   ; nested too deep
    IADD R0, META_CALL_STACK
    MOV [R0], R1
    MOV R0, [META_CALL_DEPTH]
    IADD R0, 1
    MOV [META_CALL_DEPTH], R0
    MOV R1, __exec_call_return
    PUSH R1
    IADD R13, 1                      ; one more argument (variadic ABI)
    MOV R0, R2
    JMP __exec_valid
__exec_call_not_callable:
    POP R0
    JMP __runtime_error_not_callable

;; A __call handler returns here: SP -> the table argument. Keeps R0, R2,
;; R3 (the return values).
__exec_call_return:
    IADD SP, 1
    MOV R1, [META_CALL_DEPTH]
    ISUB R1, 1
    MOV [META_CALL_DEPTH], R1
    IADD R1, META_CALL_STACK
    MOV R1, [R1]
    JMP R1

__exec_valid:
    ;; One return value unless the callee says otherwise: a compiled Lua
    ;; function stores its real count on return (node_return()); runtime
    ;; routines reached through here don't, and leave R2/R3 as scratch.
    MOV R1, 1
    MOV [RET_COUNT], R1
    MOV R2, R0
    AND R2, BOXED_CLOSURE_FLAG
    JT  R2, __exec_closure

    ; --- plain function: unchanged fast path ---
    AND R0, BOXED_PAYLOAD
    OR  R0, V32_CART_PAGE
    JMP R0

; ----------------------------------------------------------------------------
; Closure case: R0's payload is a RAM address of a closure record:
;   [0] code address (needs V32_CART_PAGE OR'd back in, same as plain funcs)
;   [1] upvalue count
;   [2..] boxed-upvalue pointers, in the order the callee expects them
;
; We push the upvalues onto the stack right here, in the caller's frame,
; BEFORE the tail-jump -- so from the target function's own prologue
; (PUSH BP; MOV BP,SP) they look exactly like ordinary trailing hidden
; parameters, indistinguishable from what a direct call would have pushed.
; ----------------------------------------------------------------------------
__exec_closure:
    MOV R1, R0
    AND R1, CLOSURE_ADDR_MASK        ; R1 = closure record address

    ; "CALL __builtin_exec" already pushed a return address before we got
    ; here. Pushing upvalues now would land them ON TOP of it instead of
    ; below it -- the callee's prologue would then see the return address
    ; at [BP+2] (where it expects its first upvalue) and the upvalue at
    ; [BP+1] (where it expects the return address), and the callee's own
    ; RET would pop a box pointer and jump to it as code. Pull the return
    ; address off first, push the upvalues underneath where it was, then
    ; push it back on top -- reproducing exactly the frame a direct call
    ; with pre-pushed upvalue arguments would produce.
    POP  R5                          ; R5 = return address

    MOV R2, [R1+1]                   ; R2 = upvalue count
    MOV R3, R1
    IADD R3, 2                       ; R3 = base of upvalue pointer array
    IADD R3, R2
    ISUB R3, 1                       ; R3 = address of the LAST upvalue slot

__exec_push_upvalue_loop:
    JF   R2, __exec_push_done   ; Jump if R2 == 0 (exit when no more upvalues)
    MOV  R4, [R3]
    PUSH R4
    ISUB R3, 1
    ISUB R2, 1
    JMP  __exec_push_upvalue_loop

__exec_push_done:
    PUSH R5                          ; return address back on top, above the upvalues

    MOV  R0, [R1]                    ; R0 = code address
    OR   R0, V32_CART_PAGE
    JMP  R0

; ==============================================================================
; Runtime Panic Handler
; ==============================================================================
__runtime_error_not_callable:
    PUSH BP
    MOV  BP, SP
    ISUB SP, 1
    MOV  [BP-1], R0                ; __builtin_exec leaves it here untouched

    MOV  R0, 0xFF000080            ; A=FF, B=00, G=00, R=80 (see hex_to_v32_color)
    OUT  GPU_ClearColor, R0
    OUT  GPU_Command, GPUCommand_ClearScreen

    MOV   R0, 20
    PUSH  R0
    MOV   R0, 0
    PUSH  R0
    MOV   R0, __const_str_panic_banner
    OR    R0, BOXED_ROMSTRING
    PUSH  R0
    CALL __builtin_print

    MOV   R0, 20
    PUSH  R0
    MOV   R0, 20
    PUSH  R0
    MOV   R0, __const_str_err_call_nil
    OR    R0, BOXED_ROMSTRING
    PUSH  R0
    CALL __builtin_print

    MOV   R0, 20
    PUSH  R0
    MOV   R0, 40
    PUSH  R0
    MOV   R0, [BP-1]
    PUSH  R0
    CALL __builtin_print

    JMP __panic_halt

__panic_halt:
    WAIT                        ; Yield CPU frame to prevent runaway execution
    JMP __panic_halt            ; Trap CPU in an infinite loop

;; ---------------------------------------------------------------------------
;; __panic_print_uint: allocation-free decimal printer for panic diagnostics.
;;
;; Panic handlers can't safely route a diagnostic number through the normal
;; print()/tostring()/ftoa() pipeline: __builtin_ftoa_scratch_a allocates its
;; 48-word scratch buffer lazily, on its very first call in the whole cart's
;; run. If that first call happens to land here -- because the OOM panic IS
;; the first thing that ever needed to print a number -- __malloc fails (the
;; heap is, after all, exactly why we're here), which re-enters
;; __oom_handler and loops forever instead of ever showing the value. This
;; touches no heap at all.
;;
;; Incoming Stack: [BP+4] = X, [BP+3] = Y, [BP+2] = non-negative raw integer
;; Clobbers: R0-R6
;; ---------------------------------------------------------------------------
__panic_print_uint:
    PUSH BP
    MOV  BP, SP
    ISUB SP, 12                  ; up to 11 digits + null, built right-to-left

    MOV  R1, [BP+2]
    MOV  R2, BP
    ISUB R2, 1
    MOV  R3, 0
    MOV  [R2], R3                ; null terminator

    MOV  R3, R1
    IEQ  R3, 0
    JF   R3, __panic_uint_extract
    ISUB R2, 1
    MOV  R3, 48                  ; '0'
    MOV  [R2], R3
    JMP  __panic_uint_done

__panic_uint_extract:
    MOV  R3, R1
    IEQ  R3, 0
    JT   R3, __panic_uint_done

    MOV  R3, R1
    MOV  R4, 10
    IMOD R3, R4
    MOV  R4, 10
    IDIV R1, R4
    IADD R3, 48                  ; digit -> ASCII

    ISUB R2, 1
    MOV  [R2], R3
    JMP  __panic_uint_extract

__panic_uint_done:
    MOV  R1, [BP+4]               ; X
    MOV  R3, [BP+3]               ; Y

    PUSH R2                       ; raw string pointer
    PUSH R3                       ; Y
    PUSH R1                       ; X
    CALL __bios_print_text

    MOV  SP, BP
    POP  BP
    RET


;; ===========================================================================
;; __builtin_cart_restart: TIC-80 reset() / PICO-8 run() -- start the cart
;; over, as the BIOS hands it over: hardware back to its defaults, a black
;; screen, the next frame, then the cart's first instruction with a fresh
;; stack. Global/heap/layer state is re-created by the cart's own start-up
;; code (which already assumes nothing about RAM -- the BIOS leaves it dirty).
;; Never returns.
;; ===========================================================================
__builtin_cart_restart:
    OUT   GPU_SelectedTexture, -1
    OUT   GPU_SelectedRegion, 0
    OUT   SPU_SelectedSound, -1
    OUT   SPU_SelectedChannel, 0
    OUT   INP_SelectedGamepad, 0
    OUT   SPU_Command, SPUCommand_StopAllChannels
    OUT   GPU_MultiplyColor, 0xFFFFFFFF
    OUT   GPU_ActiveBlending, GPUBlendingMode_Alpha
    OUT   GPU_ClearColor, 0xFF000000
    OUT   GPU_Command, GPUCommand_ClearScreen
    WAIT
    MOV   SP, 0x003FFFFF                ; where the BIOS starts the stack
    MOV   BP, SP
    JMP   V32_CART_PAGE                 ; the cart's first instruction
