;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; SECTION: TIC-80 API LAYER
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_tic80_init (initialize 512 regions of 8x8 pixels for ALL 17 textures)
;;
;; Creates 512 regions (0-511) arranged in a 16-column × 32-row grid
;; Each region is exactly 8×8 pixels with hotspot at TOP-LEFT (texture coords)
;;
;; This must be called for EACH texture (0-16) since regions are per-texture
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_tic80_init:
    PUSH  BP
    MOV   BP, SP

    ;; Save callee-saved registers we'll use
    PUSH  R13

    ;; Outer loop: iterate through all 17 textures (0-16)
    ;; Using R13 for texture index (R14=BP, R15=SP are reserved)
    MOV   R13, 0             ; R13 = current texture index

_tic80_init_texture_loop:
    ;; Exit when all 17 textures are initialized
    MOV   R0, R13
    IEQ   R0, 17
    JT    R0, _tic80_init_done

    ;; Select current texture
    OUT   GPU_SelectedTexture, R13

    ;; Inner loop: initialize all 512 regions for this texture
    MOV   R1, 0             ; R1 = region ID (0 to 511)
    MOV   R2, 0             ; R2 = x position in texture (0 to 127)
    MOV   R3, 0             ; R3 = y position in texture (0 to 255)

_tic80_init_loop:
    ;; Exit when all 512 regions are initialized for this texture
    MOV   R0, R1
    IEQ   R0, 512
    JT    R0, _tic80_init_next_texture

    ;; Select current region
    OUT   GPU_SelectedRegion, R1

    ;; Set region bounds: 8x8 pixels
    OUT   GPU_RegionMinX, R2
    OUT   GPU_RegionMinY, R3

    ;; Hotspot at TOP-LEFT of region in TEXTURE coordinates
    OUT   GPU_RegionHotspotX, R2
    OUT   GPU_RegionHotspotY, R3

    ;; MaxX = MinX + 7, MaxY = MinY + 7 (8 pixels total)
    MOV   R4, R2
    IADD  R4, 7
    OUT   GPU_RegionMaxX, R4

    MOV   R4, R3
    IADD  R4, 7
    OUT   GPU_RegionMaxY, R4

    ;; Advance to next region
    IADD  R1, 1
    IADD  R2, 8              ; Move x by 8 pixels (next column)

    ;; Check if x reached 128 (16 regions × 8 pixels = 128)
    MOV   R0, R2
    IEQ   R0, 128
    JF    R0, _tic80_init_loop

    ;; Wrap to next row: reset x to 0, advance y by 8 pixels
    MOV   R2, 0
    IADD  R3, 8
    JMP   _tic80_init_loop

_tic80_init_next_texture:
    ;; Move to next texture
    IADD  R13, 1
    JMP   _tic80_init_texture_loop

_tic80_init_done:
    ;; Restore callee-saved register
    POP   R13

    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_tic80_spr (Multi-Tile Loop & Flip/Rotate/Scale Support)
;;
;; Stack layout relative to BP:
;; [BP+2]:  id        (Sprite ID 0-511)
;; [BP+3]:  x         (Screen X position)
;; [BP+4]:  y         (Screen Y position)
;; [BP+5]:  colorkey  (Transparent color index: 16=opaque, 0-15=transparent)
;; [BP+6]:  scale     (TIC-80 scale: 1.0 = 2.64 on Vircon32)
;; [BP+7]:  flip      (0=none, 1=horizontal, 2=vertical, 3=both)
;; [BP+8]:  rotate    (0=0°, 1=90°, 2=180°, 3=270°) - IGNORED
;; [BP+9]:  w         (Grid Width in sprites)
;; [BP+10]: h         (Grid Height in sprites)
;;
;; Texture mapping:
;;   colorkey = -1  -> texture 16 (all opaque)
;;   colorkey = 0-15 -> texture 0-15 (that palette color transparent)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_tic80_spr:
    PUSH  BP
    MOV   BP, SP

    ;; --- Handle colorkey texture selection ---
    MOV   R1, [BP+5]        ; colorkey parameter
    CFI   R1                ; Convert to integer

    ;; Map colorkey to texture:
    ;;   0-15 -> 0-15 (that color transparent)
    ;;   16 -> (opaque)
_tic80_spr_texture_mapped:
    ;; R1 now contains the texture index (0-16)
    OUT   GPU_SelectedTexture, R1

    ;; No tinting for TIC-80 sprites
    OUT   GPU_MultiplyColor, 0xFFFFFFFF

    ;; --- 1. Calculate final scale as float ---
    MOV   R1, [BP+6]        ; tic80_scale (float)
    MOV   R2, 2.64
    FMUL  R1, R2            ; R1 = tic80_scale * 2.64
    MOV   R12, R1           ; Save X scale in R12
    MOV   R13, R1           ; Copy to R13 for Y scale

    ;; --- NEW: Pre-calculate scaled offset (8 * scale) ---
    MOV   R1, 8.0
    FMUL  R1, R12           ; R1 = 8 * scale
    MOV   R10, R1           ; Save in R10

    ;; --- 1b. Apply flip by negating scale ---
    MOV   R2, [BP+7]        ; flip (0-3)
    CFI   R2

    ;; Horizontal flip (bit 0): negate X scale
    AND   R3, R2
    AND   R3, 1
    IEQ   R3, 1
    JF    R3, _tic80_spr_no_flip_x
    FSGN  R12
_tic80_spr_no_flip_x:
    OUT   GPU_DrawingScaleX, R12

    ;; Vertical flip (bit 1): negate Y scale
    AND   R3, R2
    AND   R3, 2
    IEQ   R3, 2
    JF    R3, _tic80_spr_no_flip_y
    FSGN  R13
_tic80_spr_no_flip_y:
    OUT   GPU_DrawingScaleY, R13

    ;; --- 2. Prepare Loop Limits ---
    MOV   R1, [BP+9]        ; w
    MOV   R5, R1
    CFI   R5

    MOV   R1, [BP+10]       ; h
    MOV   R6, R1
    CFI   R6

    MOV   R7, [BP+2]        ; id
    CFI   R7

    MOV   R8, [BP+3]        ; x
    CFI   R8

    MOV   R9, [BP+4]        ; y
    CFI   R9

    ;; Initialize Row Counter
    MOV   R4, 0             ; R4 = row

_tic80_spr_row_loop_start:
    MOV   R1, R4
    IGE   R1, R6
    JT    R1, _tic80_spr_end

    MOV   R3, 0             ; R3 = col

_tic80_spr_col_loop_start:
    MOV   R1, R3
    IGE   R1, R5
    JT    R1, _tic80_spr_row_loop_end

    ;; --- 3. Calculate Target Region ID ---
    MOV   R1, R4
    IMUL  R1, 16
    IADD  R1, R3
    IADD  R1, R7
    OUT   GPU_SelectedRegion, R1

    ;; --- 4. Calculate X Coordinate ---
    MOV   R1, [BP+7]        ; flip
    CFI   R1
    AND   R11, R1
    AND   R11, 1
    IEQ   R11, 1
    JT    R11, _tic80_spr_calc_flip_x

    ;; Normal X = base_x + (col * scaled_offset)
    MOV   R1, R3
    CIF   R1
    FMUL  R1, R10
    CFI   R1
    IADD  R1, R8
    JMP   _tic80_spr_set_x

_tic80_spr_calc_flip_x:
    MOV   R1, R5
    ISUB  R1, 1
    ISUB  R1, R3
    CIF   R1
    FMUL  R1, R10
    CFI   R1
    IADD  R1, R8

_tic80_spr_set_x:
    OUT   GPU_DrawingPointX, R1

    ;; --- 5. Calculate Y Coordinate ---
    MOV   R1, [BP+7]        ; flip
    CFI   R1
    AND   R11, R1
    AND   R11, 2
    IEQ   R11, 2
    JT    R11, _tic80_spr_calc_flip_y

    ;; Normal Y = base_y + (row * scaled_offset)
    MOV   R1, R4
    CIF   R1
    FMUL  R1, R10
    CFI   R1
    IADD  R1, R9
    JMP   _tic80_spr_set_y

_tic80_spr_calc_flip_y:
    MOV   R1, R6
    ISUB  R1, 1
    ISUB  R1, R4
    CIF   R1
    FMUL  R1, R10
    CFI   R1
    IADD  R1, R9

_tic80_spr_set_y:
    OUT   GPU_DrawingPointY, R1

    ;; --- 6. Issue Draw Command ---
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed

    ;; --- 7. Loop ---
    IADD  R3, 1
    JMP   _tic80_spr_col_loop_start

_tic80_spr_row_loop_end:
    IADD  R4, 1
    JMP   _tic80_spr_row_loop_start

_tic80_spr_end:
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_tic80_cls: Clear screen to color
;;
;; Stack: [BP+2] = color (palette index 0-15 or 32-bit RGBA value)
;; Uses: R1-R4
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_tic80_cls:
    PUSH  BP
    MOV   BP, SP

    MOV   R1, [BP+2]        ; Load color argument

    ;; If color is a small integer (0-15), map to palette
    MOV   R2, R1
    CFI   R2                ; Convert to integer in R2

    ;; Check if 0 <= R2 < 16 (palette index range)
    ILT   R2, 0
    JT    R2, _tic80_cls_use_direct
    IGE   R2, 16
    JT    R2, _tic80_cls_use_direct

    ;; Palette lookup: R2 is valid index 0-15
    ;; Each palette entry is 4 bytes, so offset = R2 * 4
    SHL   R2, 2            ; R2 = R2 * 4
    MOV   R3, __tic80_palette
    IADD  R3, R2
    MOV   R1, [R3]        ; Load 32-bit color from palette

_tic80_cls_use_direct:
    ;; R1 now contains the 32-bit RGBA color
    OUT   GPU_ClearColor, R1
    OUT   GPU_Command, GPUCommand_ClearScreen

    MOV   SP, BP
    POP   BP
    RET

