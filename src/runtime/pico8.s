;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; SECTION: PICO-8 API LAYER
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_spr (Multi-Tile Loop & Flip Support)
;;
;; Stack layout relative to BP:
;; [BP+2]: n (Region ID)
;; [BP+3]: x
;; [BP+4]: y
;; [BP+5]: w (Scale X / Grid Width as Float)
;; [BP+6]: h (Scale Y / Grid Height as Float)
;; [BP+7]: flip_x (Boolean)
;; [BP+8]: flip_y (Boolean)
;;
;; NOTE on Initializing the Vircon32 Regions
;;
;; To  guarantee this  works flawlessly,  the region  initialization must
;; define  regions   0  through  255  sequentially   from  left-to-right,
;; top-to-bottom across your main 128x128 PICO-8 texture.
;;
;; Width & Height: Every region must be explicitly defined as exactly 8x8
;; pixels.
;;
;; Hot-spot: Every  region's hot-spot  MUST be  configured as  (0,0) (the
;; top-left corner). If the hot-spot  defaults to the center, the flipped
;; offset  math (w  - col)  *  8 will  push  the sprites  heavily out  of
;; alignment.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_spr:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Set Global Scales & Flip Flags ---
    MOV   R1, 3.0
    MOV   R2, [BP+7]        ; flip_x
    INE   R2, BOXED_TRUE
    JT    R2, _pico8_spr_set_scale_x
    MOV   R1, -3.0
_pico8_spr_set_scale_x:
    OUT   GPU_DrawingScaleX, R1

    MOV   R1, 3.0
    MOV   R2, [BP+8]        ; flip_y
    INE   R2, BOXED_TRUE
    JT    R2, _pico8_spr_set_scale_y
    MOV   R1, -3.0

_pico8_spr_set_scale_y:
    OUT   GPU_DrawingScaleY, R1

    ;; --- 2. Prepare Loop Limits & Convert ALL Floats to Integers ---
    MOV   R1, [BP+5]
    MOV   R5, R1            ; R5 = w
    CFI   R5                ; Convert float 'w' to integer limit (cols)
    MOV   R1, [BP+6]
    MOV   R6, R1            ; R6 = h
    CFI   R6                ; Convert float 'h' to integer limit (rows)

    MOV   R7, [BP+2]        ; R7 = Base sprite 'n'
    CFI   R7                ; [FIX 1] Convert float 'n' to integer!
    MOV   R8, [BP+3]        ; R8 = Base 'x'
    CFI   R8                ; [FIX 1] Convert float 'x' to integer!
    MOV   R9, [BP+4]        ; R9 = Base 'y'
    CFI   R9                ; [FIX 1] Convert float 'y' to integer!

    ;; Initialize Row Counter
    MOV   R4, 0             ; R4 = row

_pico8_spr_row_loop_start:
    MOV   R1, R4            ; preserve R4 from destructive comparison
    IGE   R1, R6
    JT    R1, _pico8_spr_end_spr      ; If row >= h, we are done

    ;; Initialize Col Counter
    MOV   R3, 0             ; R3 = col

_pico8_spr_col_loop_start:
    MOV   R1, R3            ; preserve R3 from destructive comparison
    IGE   R1, R5            ; (If col >= w, move to next row)
    JT    R1, _pico8_spr_row_loop_end

    ;; --- 3. Calculate Target Region ID ---
    ;; region = n + col + (row * 16)
    MOV   R1, R4
    IMUL  R1, 16
    IADD  R1, R3
    IADD  R1, R7
    OUT   GPU_SelectedRegion, R1

    ;; --- 4. Calculate X Coordinate ---
    MOV   R1, [BP+7]        ; check flip_x
    IEQ   R1, BOXED_TRUE
    JT    R1, _pico8_spr_calc_flip_x

    ;; Normal X = base_x + (col * 8)
    MOV   R1, R3
    IMUL  R1, 8
    IADD  R1, R8
    JMP   _pico8_spr_set_x

_pico8_spr_calc_flip_x:
    ;; [FIX 3] Flipped X = base_x + (w - 1 - col) * 8
    MOV   R1, R5
    ISUB  R1, 1             ; Subtract 1 for zero-indexed grid mirroring
    ISUB  R1, R3
    IMUL  R1, 8
    IADD  R1, R8

_pico8_spr_set_x:
    OUT   GPU_DrawingPointX, R1

    ;; --- 5. Calculate Y Coordinate ---
    MOV   R1, [BP+8]        ; check flip_y
    IEQ   R1, BOXED_TRUE
    JT    R1, _pico8_spr_calc_flip_y

    ;; Normal Y = base_y + (row * 8)
    MOV   R1, R4
    IMUL  R1, 8
    IADD  R1, R9
    JMP   _pico8_spr_set_y

_pico8_spr_calc_flip_y:
    ;; [FIX 3] Flipped Y = base_y + (h - 1 - row) * 8
    MOV   R1, R6
    ISUB  R1, 1             ; Subtract 1 for zero-indexed grid mirroring
    ISUB  R1, R4
    IMUL  R1, 8
    IADD  R1, R9

_pico8_spr_set_y:
    OUT   GPU_DrawingPointY, R1

    ;; --- 6. Issue Draw Command ---
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed

    ;; --- 7. Inner Loop Iteration ---
    IADD  R3, 1             ; col++
    JMP   _pico8_spr_col_loop_start

_pico8_spr_row_loop_end:
    ;; --- 8. Outer Loop Iteration ---
    IADD  R4, 1             ; row++
    JMP   _pico8_spr_row_loop_start

_pico8_spr_end_spr:
    ;; --- 9. Cleanup ---
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_btn: approximating the PICO-8 'btn()' function
;;
;; Stack layout relative to BP:
;; [BP+2]: i (Button ID 0-5)
;; [BP+3]: p (Player ID 0-3)
;;
;; Returns BOXED_TRUE or BOXED_FALSE in R0
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_btn:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Select Gamepad ---
    MOV   R1, [BP+3]
    CFI   R1
    ;; (Optional: FTOI R1, R1 if your numbers are floats)
    OUT   INP_SelectedGamepad, R1

    ;; --- 2. Evaluate Button ID ---
    MOV   R2, [BP+2]
    CFI   R2 ; convert button ID to int

    ;; Compare and jump to specific hardware port read
    MOV   R1, R2
    IEQ   R1, 0
    JT    R1, _pico8_btn_up
    MOV   R1, R2
    IEQ   R1, 1
    JT    R1, _pico8_btn_down
    MOV   R1, R2
    IEQ   R1, 2
    JT    R1, _pico8_btn_left
    MOV   R1, R2
    IEQ   R1, 3
    JT    R1, _pico8_btn_right
    MOV   R1, R2
    IEQ   R1, 4
    JT    R1, _pico8_btn_a
    MOV   R1, R2
    IEQ   R1, 5
    JT    R1, _pico8_btn_b

    ;; If invalid button ID, return false
    JMP   _pico8_btn_false

_pico8_btn_left:
    IN    R2, INP_GamepadLeft
    JMP   _pico8_btn_eval
_pico8_btn_right:
    IN    R2, INP_GamepadRight
    JMP   _pico8_btn_eval
_pico8_btn_up:
    IN    R2, INP_GamepadUp
    JMP   _pico8_btn_eval
_pico8_btn_down:
    IN    R2, INP_GamepadDown
    JMP   _pico8_btn_eval
_pico8_btn_a:
    IN    R2, INP_GamepadButtonA
    JMP   _pico8_btn_eval
_pico8_btn_b:
    IN    R2, INP_GamepadButtonB

_pico8_btn_eval:
    ;; Vircon32 returns 1 for pressed, 0 for not pressed
    IGE   R2, 1
    JT    R2, _pico8_btn_true

_pico8_btn_false:
    MOV   R0, BOXED_FALSE
    JMP   _pico8_btn_end

_pico8_btn_true:
    MOV   R0, BOXED_TRUE

_pico8_btn_end:
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_btnp: approximating the PICO-8 'btnp()' function
;;
;; Stack layout relative to BP:
;; [BP+2]: i (Button ID 0-5)
;; [BP+3]: p (Player ID 0-3)
;;
;; Returns BOXED_TRUE or BOXED_FALSE in R0
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_btnp:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Select Gamepad ---
    MOV   R1, [BP+3]
    OUT   INP_SelectedGamepad, R1

    ;; --- 2. Evaluate Button ID ---
    MOV   R2, [BP+2]

    ;; Compare and jump to specific hardware port read
    MOV   R1, R2
    IEQ   R1, 0
    JT    R1, _pico8_btnp_left
    MOV   R1, R2
    IEQ   R1, 1
    JT    R1, _pico8_btnp_right
    MOV   R1, R2
    IEQ   R1, 2
    JT    R1, _pico8_btnp_up
    MOV   R1, R2
    IEQ   R1, 3
    JT    R1, _pico8_btnp_down
    MOV   R1, R2
    IEQ   R1, 4
    JT    R1, _pico8_btnp_a
    MOV   R1, R2
    IEQ   R1, 5
    JT    R1, _pico8_btnp_b

    JMP   _pico8_btnp_false

_pico8_btnp_left:
    IN    R2, INP_GamepadLeft
    JMP   _pico8_btnp_eval
_pico8_btnp_right:
    IN    R2, INP_GamepadRight
    JMP   _pico8_btnp_eval
_pico8_btnp_up:
    IN    R2, INP_GamepadUp
    JMP   _pico8_btnp_eval
_pico8_btnp_down:
    IN    R2, INP_GamepadDown
    JMP   _pico8_btnp_eval
_pico8_btnp_a:
    IN    R2, INP_GamepadButtonA
    JMP   _pico8_btnp_eval
_pico8_btnp_b:
    IN    R2, INP_GamepadButtonB

_pico8_btnp_eval:
    ;; R2 now contains Frames Held (>0) or Frames Released (<=0)

    ;; Condition A: Is button not pressed?
    MOV   R1, R2
    ILT   R1, 1
    JT    R1, _pico8_btnp_false   ; If < 1, return false

    ;; Condition B: Initial Press (Frame 1)
    MOV   R1, R2
    IEQ   R1, 1
    JT    R1, _pico8_btnp_true    ; If exactly 1, return true

    ;; Condition C: Delay Phase (Frames 2-14)
    MOV   R1, R2
    ILT   R1, 15
    JT    R1, _pico8_btnp_false   ; If < 15 (and > 1), return false

    ;; Condition D: Autorepeat Phase (Frames 15+)
    ;; Logic: (FramesHeld - 15) % 4 == 0
    MOV   R1, R2
    ISUB  R1, 15            ; Shift down by 15 frames
    IMOD  R1, 4             ; Modulo 4
    IEQ   R1, 0             ; Is remainder 0?
    JT    R1, _pico8_btnp_true    ; If yes, return true

_pico8_btnp_false:
    MOV   R0, BOXED_FALSE
    JMP   _pico8_btnp_end

_pico8_btnp_true:
    MOV   R0, BOXED_TRUE

_pico8_btnp_end:
    MOV   SP, BP
    POP   BP
    RET

;; ---------------------------------------------------------------------------
;; PICO-8 add(): Adds value to table at position (default: append)
;;
;; Incoming Stack: [BP+4] = index/NIL, [BP+3] = value, [BP+2] = table
;; Returns: R0 = inserted value
;; Register Usage: R7-R9 for arguments, R1-R6 callee-saved
;; ---------------------------------------------------------------------------
__builtin_pico8_add:
    PUSH BP
    MOV  BP, SP

    ;; --- Push callee-saved registers FIRST ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6

    ;; --- Now load arguments into non-callee-saved registers ---
    MOV  R7, [BP+4]          ; R7 = index (or NIL)
    MOV  R8, [BP+3]          ; R8 = value
    MOV  R9, [BP+2]          ; R9 = table

    ;; --- Save original index in R6 for later length-update check ---
    MOV  R6, R7              ; R6 = original index (NIL or explicit)

    ;; --- Unbox table and get current length ---
    MOV  R4, R9
    AND  R4, BOXED_PAYLOAD   ; R4 = raw table header address
    MOV  R5, [R4+1]          ; R5 = current array length (integer)

    ;; --- Handle default index (NIL = length + 1) ---
    MOV  R4, R6              ; Check original index
    IEQ  R4, BOXED_NIL
    JT   R4, _pico8_add_use_length_plus_1
    MOV  R7, R6              ; Use provided index (already float via compiler)
    JMP  _pico8_add_prepare_call

_pico8_add_use_length_plus_1:
    MOV  R7, R5
    IADD R7, 1              ; R7 = length + 1 (as integer)
    CIF  R7                  ; Convert integer to float representation

_pico8_add_prepare_call:
    ;; --- Call __builtin_table_set(table, index, value) ---
    PUSH R9                  ; table
    PUSH R7                  ; index (float)
    PUSH R8                  ; value
    CALL __builtin_table_set
    IADD SP, 3

    ;; --- Update length ONLY if original index was NIL (append case) ---
    MOV  R4, R6
    IEQ  R4, BOXED_NIL
    JF   R4, _pico8_add_return

    ;; --- Update table length in header (stored as integer) ---
    MOV  R4, R9              ; R9 has the tagged header address
    AND  R4, BOXED_PAYLOAD   ; R4 = raw table header address

    IADD R5, 1
    MOV  [R4+1], R5

_pico8_add_return:
    ;; --- Return the inserted value ---
    MOV  R0, R8

    ;; --- Callee-Restore ---
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET
