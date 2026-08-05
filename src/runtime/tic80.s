;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; SECTION: TIC-80 API LAYER
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_tic80_init (initialize regions, TIC-80 style)
;;
__builtin_tic80_init:
    PUSH  BP
    MOV   BP, SP

    OUT   GPU_SelectedTexture, 0

    MOV   R1, 0
    MOV   R4, R1
_tic80_init_loop:
    MOV   R0, R1

    IEQ   R0, 512
    JT    R0, _tic80_init_done

    MOV   R0, R1

    OUT   GPU_SelectedRegion,  R0
    OUT   GPU_RegionMinX,      R2
    OUT   GPU_RegionMinY,      R3
    OUT   GPU_RegionHotspotX,  R2
    OUT   GPU_RegionHotspotY,  R3
    IADD  R2,                  7
    OUT   GPU_RegionMaxX,      R2
    IADD  R2,                  7
    OUT   GPU_RegionMaxY,      R3

    IADD  R1,                  1 ; advance tile ID
    IADD  R4,                  1

    IADD  R2,                  1 ; advance to next tile
    ISUB  R3,                  7 ; reset to top of current tile row

    MOV   R5,                  R4
    IEQ   R5,                  16
    JF    R5,                  _tic80_init_loop

    MOV   R2,                  0
    IADD  R3,                  8
    MOV   R4,                  0

    JMP   _tic_init_loop

_tic80_init_done:
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_tic80_spr (Multi-Tile Loop & Flip/Rotate/Scale/Colorkey Support)
;;
;; Stack layout relative to BP:
;; [BP+2]: id (Sprite ID 0-511)
;; [BP+3]: x
;; [BP+4]: y
;; [BP+5]: colorkey (Transparent color index, -1 for opaque)
;; [BP+6]: scale (Scale factor, default 1)
;; [BP+7]: flip (0=none, 1=horizontal, 2=vertical, 3=both)
;; [BP+8]: rotate (0=0°, 1=90°, 2=180°, 3=270°)
;; [BP+9]: w (Grid Width as Float)
;; [BP+10]: h (Grid Height as Float)
;;
;; NOTE on Initializing the Vircon32 Regions
;;
;; To guarantee this works flawlessly, the region initialization must
;; define regions 0 through 511 sequentially from left-to-right,
;; top-to-bottom across your main 256x256 TIC-80 sprite sheet (2 banks of 128x128).
;;
;; Width & Height: Every region must be explicitly defined as exactly 8x8
;; pixels.
;;
;; Hot-spot: Every region's hot-spot MUST be configured as (0,0) (the
;; top-left corner). If the hot-spot defaults to the center, the flipped
;; offset math will push the sprites heavily out of alignment.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_tic80_spr:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Set Global Scales & Flip/Rotate Flags ---
    ;; Handle scale (TIC-80 has variable scale, default 1)
    MOV   R1, [BP+6]        ; scale
    CFI   R1                ; Convert float scale to integer
    MOV   R2, R1
    IMUL  R2, 3             ; TIC-80 sprites are 8x8, scale by 3 for Vircon32
    OUT   GPU_DrawingScaleX, R2
    OUT   GPU_DrawingScaleY, R2

    ;; Handle flip (TIC-80 uses combined flip parameter)
    MOV   R1, [BP+7]        ; flip (0-3)
    CFI   R1

    ;; Check for horizontal flip (bit 0)
    MOV   R2, R1
    IAND  R2, 1
    IEQ   R2, 1
    JT    R2, _tic80_spr_flip_x
    MOV   R2, 3.0
    JMP   _tic80_spr_set_scale_x
_tic80_spr_flip_x:
    MOV   R2, -3.0
_tic80_spr_set_scale_x:
    OUT   GPU_DrawingScaleX, R2

    ;; Check for vertical flip (bit 1)
    MOV   R2, R1
    IAND  R2, 2
    IEQ   R2, 2
    JT    R2, _tic80_spr_flip_y
    MOV   R2, 3.0
    JMP   _tic80_spr_set_scale_y
_tic80_spr_flip_y:
    MOV   R2, -3.0
_tic80_spr_set_scale_y:
    OUT   GPU_DrawingScaleY, R2

    ;; Handle rotation (TIC-80 rotate parameter)
    ;; For now, we'll ignore rotation as Vircon32 GPU may not support it
    ;; In a full implementation, you'd need to handle 90° rotations

    ;; --- 2. Prepare Loop Limits & Convert ALL Floats to Integers ---
    MOV   R1, [BP+9]
    MOV   R5, R1            ; R5 = w
    CFI   R5                ; Convert float 'w' to integer limit (cols)
    MOV   R1, [BP+10]
    MOV   R6, R1            ; R6 = h
    CFI   R6                ; Convert float 'h' to integer limit (rows)

    MOV   R7, [BP+2]        ; R7 = Base sprite 'id'
    CFI   R7                ; Convert float 'id' to integer!
    MOV   R8, [BP+3]        ; R8 = Base 'x'
    CFI   R8                ; Convert float 'x' to integer!
    MOV   R9, [BP+4]        ; R9 = Base 'y'
    CFI   R9                ; Convert float 'y' to integer!

    ;; Initialize Row Counter
    MOV   R4, 0             ; R4 = row

_tic80_spr_row_loop_start:
    MOV   R1, R4            ; preserve R4 from destructive comparison
    IGE   R1, R6
    JT    R1, _tic80_spr_end_spr      ; If row >= h, we are done

    ;; Initialize Col Counter
    MOV   R3, 0             ; R3 = col

_tic80_spr_col_loop_start:
    MOV   R1, R3            ; preserve R3 from destructive comparison
    IGE   R1, R5            ; (If col >= w, move to next row)
    JT    R1, _tic80_spr_row_loop_end

    ;; --- 3. Calculate Target Region ID ---
    ;; region = id + col + (row * 32)  ; TIC-80 has 256 sprites (32 per row in 256x256 sheet)
    MOV   R1, R4
    IMUL  R1, 32
    IADD  R1, R3
    IADD  R1, R7
    OUT   GPU_SelectedRegion, R1

    ;; --- 4. Calculate X Coordinate ---
    ;; Handle flip for X coordinate
    MOV   R1, [BP+7]        ; check flip parameter
    CFI   R1
    IAND  R1, 1             ; Check horizontal flip bit
    IEQ   R1, 1
    JT    R1, _tic80_spr_calc_flip_x

    ;; Normal X = base_x + (col * 8 * scale)
    MOV   R1, R3
    IMUL  R1, 8
    MOV   R2, [BP+6]        ; scale
    CFI   R2
    IMUL  R1, R2
    IADD  R1, R8
    JMP   _tic80_spr_set_x

_tic80_spr_calc_flip_x:
    ;; Flipped X = base_x + (w - 1 - col) * 8 * scale
    MOV   R1, R5
    ISUB  R1, 1             ; Subtract 1 for zero-indexed grid mirroring
    ISUB  R1, R3
    IMUL  R1, 8
    MOV   R2, [BP+6]        ; scale
    CFI   R2
    IMUL  R1, R2
    IADD  R1, R8

_tic80_spr_set_x:
    OUT   GPU_DrawingPointX, R1

    ;; --- 5. Calculate Y Coordinate ---
    MOV   R1, [BP+7]        ; check flip parameter
    CFI   R1
    IAND  R1, 2             ; Check vertical flip bit (bit 1)
    IEQ   R1, 2
    JT    R1, _tic80_spr_calc_flip_y

    ;; Normal Y = base_y + (row * 8 * scale)
    MOV   R1, R4
    IMUL  R1, 8
    MOV   R2, [BP+6]        ; scale
    CFI   R2
    IMUL  R1, R2
    IADD  R1, R9
    JMP   _tic80_spr_set_y

_tic80_spr_calc_flip_y:
    ;; Flipped Y = base_y + (h - 1 - row) * 8 * scale
    MOV   R1, R6
    ISUB  R1, 1             ; Subtract 1 for zero-indexed grid mirroring
    ISUB  R1, R4
    IMUL  R1, 8
    MOV   R2, [BP+6]        ; scale
    CFI   R2
    IMUL  R1, R2
    IADD  R1, R9

_tic80_spr_set_y:
    OUT   GPU_DrawingPointY, R1

    ;; --- 6. Issue Draw Command ---
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed

    ;; --- 7. Inner Loop Iteration ---
    IADD  R3, 1             ; col++
    JMP   _tic80_spr_col_loop_start

_tic80_spr_row_loop_end:
    ;; --- 8. Outer Loop Iteration ---
    IADD  R4, 1             ; row++
    JMP   _tic80_spr_row_loop_start

_tic80_spr_end_spr:
    ;; --- 9. Cleanup ---
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_btn: approximating the TIC-80 'btn()' function
;;
;; Stack layout relative to BP:
;; [BP+2]: id (Button ID 0-31)
;;
;; Returns BOXED_TRUE or BOXED_FALSE in R0
;;
;; TIC-80 Button Mapping (first 8 match PICO-8 for compatibility):
;; 0 = Up, 1 = Down, 2 = Left, 3 = Right, 4 = A, 5 = B, 6 = X, 7 = Y
;; 8-31 = Additional TIC-80 buttons
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_tic80_btn:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Get Button ID ---
    MOV   R2, [BP+2]
    CFI   R2 ; convert button ID to int

    ;; Compare and jump to specific hardware port read
    ;; TIC-80 uses a unified button mapping, but we'll map to Vircon32 gamepad
    MOV   R1, R2
    IEQ   R1, 0
    JT    R1, _tic80_btn_up
    MOV   R1, R2
    IEQ   R1, 1
    JT    R1, _tic80_btn_down
    MOV   R1, R2
    IEQ   R1, 2
    JT    R1, _tic80_btn_left
    MOV   R1, R2
    IEQ   R1, 3
    JT    R1, _tic80_btn_right
    MOV   R1, R2
    IEQ   R1, 4
    JT    R1, _tic80_btn_a
    MOV   R1, R2
    IEQ   R1, 5
    JT    R1, _tic80_btn_b
    MOV   R1, R2
    IEQ   R1, 6
    JT    R1, _tic80_btn_x
    MOV   R1, R2
    IEQ   R1, 7
    JT    R1, _tic80_btn_y

    ;; If invalid button ID (8-31 not mapped to Vircon32), return false
    JMP   _tic80_btn_false

_tic80_btn_up:
    IN    R2, INP_GamepadUp
    JMP   _tic80_btn_eval
_tic80_btn_down:
    IN    R2, INP_GamepadDown
    JMP   _tic80_btn_eval
_tic80_btn_left:
    IN    R2, INP_GamepadLeft
    JMP   _tic80_btn_eval
_tic80_btn_right:
    IN    R2, INP_GamepadRight
    JMP   _tic80_btn_eval
_tic80_btn_a:
    IN    R2, INP_GamepadButtonA
    JMP   _tic80_btn_eval
_tic80_btn_b:
    IN    R2, INP_GamepadButtonB
    JMP   _tic80_btn_eval
_tic80_btn_x:
    IN    R2, INP_GamepadButtonX
    JMP   _tic80_btn_eval
_tic80_btn_y:
    IN    R2, INP_GamepadButtonY

_tic80_btn_eval:
    ;; Vircon32 returns 1 for pressed, 0 for not pressed
    IGE   R2, 1
    JT    R2, _tic80_btn_true

_tic80_btn_false:
    MOV   R0, BOXED_FALSE
    JMP   _tic80_btn_end

_tic80_btn_true:
    MOV   R0, BOXED_TRUE

_tic80_btn_end:
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_btnp: approximating the TIC-80 'btnp()' function
;;
;; Stack layout relative to BP:
;; [BP+2]: id (Button ID 0-31)
;; [BP+3]: hold (Frames to hold before autorepeat, -1 for default)
;; [BP+4]: period (Frames between autorepeat, -1 for default)
;;
;; Returns BOXED_TRUE or BOXED_FALSE in R0
;;
;; TIC-80 btnp behavior:
;; - Returns true only if button was pressed since last frame
;; - With hold/period: returns true after 'hold' frames, then every 'period' frames
;; - Default TIC-80 behavior: hold=6, period=4 (different from PICO-8's 15,4)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_tic80_btnp:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Select Gamepad (TIC-80 doesn't have player parameter, use player 0) ---
    MOV   R1, 0
    OUT   INP_SelectedGamepad, R1

    ;; --- 2. Evaluate Button ID ---
    MOV   R2, [BP+2]
    CFI   R2

    ;; Compare and jump to specific hardware port read
    MOV   R1, R2
    IEQ   R1, 0
    JT    R1, _tic80_btnp_up
    MOV   R1, R2
    IEQ   R1, 1
    JT    R1, _tic80_btnp_down
    MOV   R1, R2
    IEQ   R1, 2
    JT    R1, _tic80_btnp_left
    MOV   R1, R2
    IEQ   R1, 3
    JT    R1, _tic80_btnp_right
    MOV   R1, R2
    IEQ   R1, 4
    JT    R1, _tic80_btnp_a
    MOV   R1, R2
    IEQ   R1, 5
    JT    R1, _tic80_btnp_b
    MOV   R1, R2
    IEQ   R1, 6
    JT    R1, _tic80_btnp_x
    MOV   R1, R2
    IEQ   R1, 7
    JT    R1, _tic80_btnp_y

    JMP   _tic80_btnp_false

_tic80_btnp_up:
    IN    R2, INP_GamepadUp
    JMP   _tic80_btnp_eval
_tic80_btnp_down:
    IN    R2, INP_GamepadDown
    JMP   _tic80_btnp_eval
_tic80_btnp_left:
    IN    R2, INP_GamepadLeft
    JMP   _tic80_btnp_eval
_tic80_btnp_right:
    IN    R2, INP_GamepadRight
    JMP   _tic80_btnp_eval
_tic80_btnp_a:
    IN    R2, INP_GamepadButtonA
    JMP   _tic80_btnp_eval
_tic80_btnp_b:
    IN    R2, INP_GamepadButtonB
    JMP   _tic80_btnp_eval
_tic80_btnp_x:
    IN    R2, INP_GamepadButtonX
    JMP   _tic80_btnp_eval
_tic80_btnp_y:
    IN    R2, INP_GamepadButtonY

_tic80_btnp_eval:
    ;; R2 now contains Frames Held (>0) or Frames Released (<=0)

    ;; Load hold and period parameters (with defaults)
    MOV   R3, [BP+3]        ; hold parameter
    CFI   R3
    ;; If hold is -1, use TIC-80 default of 6
    IEQ   R3, -1
    JT    R3, _tic80_btnp_use_default_hold
    JMP   _tic80_btnp_check_hold
_tic80_btnp_use_default_hold:
    MOV   R3, 6             ; TIC-80 default hold frames

_tic80_btnp_check_hold:
    MOV   R4, [BP+4]        ; period parameter
    CFI   R4
    ;; If period is -1, use TIC-80 default of 4
    IEQ   R4, -1
    JT    R4, _tic80_btnp_use_default_period
    JMP   _tic80_btnp_check_period
_tic80_btnp_use_default_period:
    MOV   R4, 4             ; TIC-80 default period frames

_tic80_btnp_check_period:
    ;; Condition A: Is button not pressed?
    MOV   R1, R2
    ILT   R1, 1
    JT    R1, _tic80_btnp_false   ; If < 1, return false

    ;; Condition B: Initial Press (Frame 1)
    MOV   R1, R2
    IEQ   R1, 1
    JT    R1, _tic80_btnp_true    ; If exactly 1, return true

    ;; Condition C: Hold Phase (Frames 2 to hold-1)
    MOV   R1, R2
    ILT   R1, R3            ; Compare with hold parameter
    JT    R1, _tic80_btnp_false   ; If < hold (and > 1), return false

    ;; Condition D: Autorepeat Phase (Frames >= hold)
    ;; Logic: (FramesHeld - hold) % period == 0
    MOV   R1, R2
    ISUB  R1, R3            ; Subtract hold frames
    IMOD  R1, R4            ; Modulo period
    IEQ   R1, 0             ; Is remainder 0?
    JT    R1, _tic80_btnp_true    ; If yes, return true

_tic80_btnp_false:
    MOV   R0, BOXED_FALSE
    JMP   _tic80_btnp_end

_tic80_btnp_true:
    MOV   R0, BOXED_TRUE

_tic80_btnp_end:
    MOV   SP, BP
    POP   BP
    RET

;; ---------------------------------------------------------------------------
;; TIC-80 add(): Adds value to table at position (default: append)
;;
;; Incoming Stack: [BP+4] = index/NIL, [BP+3] = value, [BP+2] = table
;; Returns: R0 = inserted value
;; Register Usage: R7-R9 for arguments, R1-R6 callee-saved
;;
;; Note: TIC-80 uses standard Lua table.insert(), but we maintain PICO-8
;;       compatibility with the add() function behavior
;; ---------------------------------------------------------------------------
__builtin_tic80_add:
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
    JT   R4, _tic80_add_use_length_plus_1
    MOV  R7, R6              ; Use provided index (already float via compiler)
    JMP  _tic80_add_prepare_call

_tic80_add_use_length_plus_1:
    MOV  R7, R5
    IADD R7, 1              ; R7 = length + 1 (as integer)
    CIF  R7                  ; Convert integer to float representation

_tic80_add_prepare_call:
    ;; --- Call __builtin_table_set(table, index, value) ---
    PUSH R9                  ; table
    PUSH R7                  ; index (float)
    PUSH R8                  ; value
    CALL __builtin_table_set
    IADD SP, 3

    ;; --- Update length ONLY if original index was NIL (append case) ---
    MOV  R4, R6
    IEQ  R4, BOXED_NIL
    JF   R4, _tic80_add_return

    ;; --- Update table length in header (stored as integer) ---
    MOV  R4, R9              ; R9 has the tagged header address
    AND  R4, BOXED_PAYLOAD   ; R4 = raw table header address

    IADD R5, 1
    MOV  [R4+1], R5

_tic80_add_return:
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

