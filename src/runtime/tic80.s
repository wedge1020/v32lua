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
_tic80_init_textures_done:
    ;; Initialize map buffer after textures
    CALL  __builtin_tic80_init_map

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
;; [BP+3]:  x         (Screen X position in TIC-80 pixels)
;; [BP+4]:  y         (Screen Y position in TIC-80 pixels)
;; [BP+5]:  colorkey  (Transparent color index: 16=opaque, 0-15=transparent)
;; [BP+6]:  scale     (TIC-80 scale: 1.0 = 2.625 on Vircon32)
;; [BP+7]:  flip      (0=none, 1=horizontal, 2=vertical, 3=both)
;; [BP+8]:  rotate    (0=0°, 1=90°, 2=180°, 3=270°) - IGNORED
;; [BP+9]:  w         (Grid Width in sprites)
;; [BP+10]: h         (Grid Height in sprites)
;;
;; Texture mapping:
;;   colorkey = 16   -> texture 16 (all opaque)
;;   colorkey = 0-15 -> texture 0-15 (that palette color transparent)
;;
;; FIXES APPLIED:
;;   - Base x/y positions are now scaled by 2.625 and rounded
;;   - All coordinate calculations use rounding (FADD 0.5) before CFI
;;     to eliminate sub-pixel gaps that caused thin black grid lines
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_tic80_spr:
    PUSH  BP
    MOV   BP, SP

    ;; --- Handle colorkey texture selection ---
    MOV   R1, [BP+5]        ; colorkey parameter
    CFI   R1
    OUT   GPU_SelectedTexture, R1

    ;; --- Calculate final scale ---
    MOV   R1, [BP+6]        ; tic80_scale (float)
    MOV   R2, 2.625
    FMUL  R1, R2
    MOV   R12, R1           ; X scale
    MOV   R13, R1           ; Y scale

    ;; --- Pre-calculate scaled offset (8 * scale) ---
    MOV   R1, 8.0
    FMUL  R1, R12
    MOV   R10, R1           ; R10 = 8 * scale

    ;; --- Apply flip ---
    MOV   R2, [BP+7]
    CFI   R2
    AND   R3, R2
    AND   R3, 1
    IEQ   R3, 1
    JF    R3, _tic80_spr_no_flip_x
    FSGN  R12
_tic80_spr_no_flip_x:
    OUT   GPU_DrawingScaleX, R12

    AND   R3, R2
    AND   R3, 2
    IEQ   R3, 2
    JF    R3, _tic80_spr_no_flip_y
    FSGN  R13
_tic80_spr_no_flip_y:
    OUT   GPU_DrawingScaleY, R13

    ;; --- Prepare Loop Limits ---
    MOV   R5, [BP+9]        ; w
    CFI   R5
    MOV   R6, [BP+10]       ; h
    CFI   R6
    MOV   R7, [BP+2]        ; id
    CFI   R7

    ;; --- FIX: Base x/y are ALREADY scaled (from caller).
    ;;         Only ensure they are integers, NO additional scaling.
    MOV   R8, [BP+3]        ; x (Vircon32 pixels)
    FMUL  R8, 2.625         ; multiply by x axis screen factor
    FADD  R8, 0.5
    CFI   R8                ; Convert to integer (no scaling)

    MOV   R9, [BP+4]        ; y (Vircon32 pixels)
    FMUL  R9, 2.625         ; multiply by y axis screen factor
    FADD  R9, 0.5
    CFI   R9                ; Convert to integer (no scaling)

    MOV   R4, 0             ; row counter

_tic80_spr_row_loop_start:
    MOV   R1, R4
    IGE   R1, R6
    JT    R1, _tic80_spr_end
    MOV   R3, 0             ; col counter

_tic80_spr_col_loop_start:
    MOV   R1, R3
    IGE   R1, R5
    JT    R1, _tic80_spr_row_loop_end

    ;; --- Select region ---
    MOV   R1, R4
    IMUL  R1, 16
    IADD  R1, R3
    IADD  R1, R7
    OUT   GPU_SelectedRegion, R1

    ;; --- Calculate X (with rounding) ---
    MOV   R1, [BP+7]
    CFI   R1
    AND   R11, R1
    AND   R11, 1
    IEQ   R11, 1
    JT    R11, _tic80_spr_calc_flip_x

    ;; Normal X = base_x + (col * 8 * scale)
    MOV   R1, R3
    CIF   R1
    FMUL  R1, R10           ; col * 8 * scale
    FADD  R1, 0.5           ; Round to nearest pixel
    CFI   R1
    IADD  R1, R8            ; Add base X
    JMP   _tic80_spr_set_x

_tic80_spr_calc_flip_x:
    MOV   R1, R5
    ISUB  R1, 1
    ISUB  R1, R3
    CIF   R1
    FMUL  R1, R10
    FADD  R1, 0.5           ; Round to nearest pixel
    CFI   R1
    IADD  R1, R8

_tic80_spr_set_x:
    OUT   GPU_DrawingPointX, R1

    ;; --- Calculate Y (with rounding) ---
    MOV   R1, [BP+7]
    CFI   R1
    AND   R11, R1
    AND   R11, 2
    IEQ   R11, 2
    JT    R11, _tic80_spr_calc_flip_y

    ;; Normal Y = base_y + (row * 8 * scale)
    MOV   R1, R4
    CIF   R1
    FMUL  R1, R10
    FADD  R1, 0.5           ; Round to nearest pixel
    CFI   R1
    IADD  R1, R9
    JMP   _tic80_spr_set_y

_tic80_spr_calc_flip_y:
    MOV   R1, R6
    ISUB  R1, 1
    ISUB  R1, R4
    CIF   R1
    FMUL  R1, R10
    FADD  R1, 0.5           ; Round to nearest pixel
    CFI   R1
    IADD  R1, R9

_tic80_spr_set_y:
    OUT   GPU_DrawingPointY, R1

    ;; --- Draw ---
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed

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

    ;; --- isolate gamepad #, distill R2 to the button 0-7 id on gamepad
    MOV   R3, R2
    IDIV  R3, 8  ; R3 will contain gamepad id
    OUT   INP_SelectedGamepad, R3
    IMOD  R2, 8  ; R2 now just contains button id on gamepad (0-7)

    ;; If invalid button ID (gamepad id > 3), return false
    IGT   R3, 3
    JT    R3, _tic80_btn_false

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

    JMP   _tic80_btn_false ; in the unlikely event we reach this, return false

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

    ;; --- 1. Evaluate Button ID ---
    MOV   R2, [BP+2]
    CFI   R2

    ;; --- isolate gamepad #, distill R2 to the button 0-7 id on gamepad
    MOV   R3, R2
    IDIV  R3, 8  ; R3 will contain gamepad id
    OUT   INP_SelectedGamepad, R3
    IMOD  R2, 8  ; R2 now just contains button id on gamepad (0-7)

    ;; If invalid button ID (gamepad id > 3), return false
    IGT   R3, 3
    JT    R3, _tic80_btnp_false

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

;; ===========================================================================
;; TIC-80 MAP CONSTANTS
;; ===========================================================================

;; TIC-80 MAP CONSTANTS
%define TIC80_MAP_MAX_WIDTH     240
%define TIC80_MAP_MAX_HEIGHT    136
%define TIC80_MAP_MAX_CELLS     32640   ; 240*136

;; Default map dimensions (can be changed at runtime)
%define TIC80_MAP_ACTUAL_WIDTH  240
%define TIC80_MAP_ACTUAL_HEIGHT 136

;; Buffer size in words (64KB = 16384 words)
%define TIC80_MAP_BUFFER_WORDS  16384

;; ============================================================================
;; TIC-80 Map Initialization with Static Data
;; Allocates map buffer and copies parsed map data (if available)
;; ============================================================================

__builtin_tic80_init_map:
    PUSH  BP
    MOV   BP, SP

    ;; Allocate map buffer (64KB)
    MOV   R0, TIC80_MAP_BUFFER_WORDS
    PUSH  R0
    CALL  __malloc
    IADD  SP, 1

    ;; Store pointer globally
    MOV   R1,   var_TIC80_MAP_BUFFER_PTR
    MOV   [R1], R0
    MOV   R12,  R0            ; R12 = buffer

    ;; Initialize RAM variables with actual cartridge dimensions from ROM
    MOV   R1, __tic80_map_static_width
    MOV   R1, [R1]              ; Load static width (240) from ROM
    MOV   R2, var_TIC80_MAP_WIDTH    ; RAM address 2
    MOV   [R2], R1              ; Store width in RAM

    MOV   R1, __tic80_map_static_height
    MOV   R1, [R1]             ; Load static height (17) from ROM
    MOV   R2, var_TIC80_MAP_HEIGHT   ; RAM address 3
    MOV   [R2], R1              ; Store height in RAM

    ;; Check for static map data (width > 0?)
    MOV   R1, var_TIC80_MAP_WIDTH
    MOV   R1, [R1]
    IEQ   R1, 0
    JT    R1, _tic80_init_map_zero_fill

    ;; Copy loop
    MOV   R2, 0                ; byte index
    MOV   R3, var_TIC80_MAP_WIDTH
    MOV   R3, [R3]
    MOV   R6, var_TIC80_MAP_HEIGHT
    MOV   R6, [R6]
    IMUL  R3, R6              ; R3 = total bytes
    MOV   R7, __tic80_map_static_data

_tic80_init_map_copy_loop:
    MOV   R8, R2
    ILT   R8, R3
    JT    R8, _tic80_copy_continue
    JMP   _tic80_init_map_done

_tic80_copy_continue:
    MOV   R8, R7
    IADD  R8, R2
    MOV   R8, [R8]

    MOV   R1, R12
    IADD  R1, R2
    MOV   [R1], R8

    IADD  R2, 1
    JMP   _tic80_init_map_copy_loop

    ;; Zero-fill fallback
_tic80_init_map_zero_fill:
    MOV   R2, 0
    MOV   R3, TIC80_MAP_BUFFER_WORDS
    SHL   R3, 2              ; bytes = words * 4

_tic80_init_map_zero_loop:
    MOV   R8, R2
    ILT   R8, R3
    JT    R8, _tic80_zero_continue
    JMP   _tic80_init_map_done

_tic80_zero_continue:
    MOV   R8, 0
    MOV   R1, R12
    IADD  R1, R2
    MOV   [R1], R8

    IADD  R2, 1
    JMP   _tic80_init_map_zero_loop

_tic80_init_map_done:
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_tic80_mget: Get Tile from TIC-80 Map
;;
;; Stack: [BP+2] = x
;;        [BP+3] = y
;; Returns: R0 = tile index at (x,y) as boxed Lua number,
;;               ... or BOXED_NIL if out of bounds
;;
;; Reads a single tile from the map buffer using actual cartridge dimensions
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_tic80_mget:
    PUSH  BP
    MOV   BP, SP

    ;; Load buffer pointer
    MOV   R1,  var_TIC80_MAP_BUFFER_PTR
    MOV   R12, [R1]
    IEQ   R12, 0
    JT    R12, _tic80_mget_invalid

    ;; Load arguments
    MOV   R1, [BP+2]        ; x
    MOV   R2, [BP+3]        ; y

    ;; Snap to integer tile coordinates
    FADD  R1, 0.5
    CFI   R1                ; R1 = round(x)
    FADD  R2, 0.5
    CFI   R2                ; R2 = round(y)

    ;; Snap to 0.1-pixel grid, then round to integer
;   FMUL  R1, 10.0          ; x * 10 (float)
;   FADD  R1, 0.5           ; + 0.5 (float)
;   CFI   R1                ; → integer (round(x*10))
;   IDIV  R1, 10            ; integer division: round(x*10) / 10

    ;; Snap to 0.1-pixel grid, then round to integer
;   FMUL  R2, 10.0          ; y * 10 (float)
;   FADD  R2, 0.5           ; + 0.5 (float)
;   CFI   R2                ; → integer (round(y*10))
;   IDIV  R2, 10            ; integer division: round(y*10) / 10

    ;; Load ACTUAL map dimensions for bounds checking
    MOV   R3, var_TIC80_MAP_WIDTH
    MOV   R3, [R3]          ; R3 = actual width
    MOV   R4, var_TIC80_MAP_HEIGHT
    MOV   R4, [R4]          ; R4 = actual height

    ;; Bounds check: x
    MOV   R5, R1
    ILT   R5, 0
    JT    R5, _tic80_mget_invalid
    MOV   R5, R1
    IGE   R5, R3
    JT    R5, _tic80_mget_invalid

    ;; Bounds check: y
    MOV   R5, R2
    ILT   R5, 0
    JT    R5, _tic80_mget_invalid
    MOV   R5, R2
    IGE   R5, R4
    JT    R5, _tic80_mget_invalid

    ;; Calculate byte index: index = y * width + x
    MOV   R5, R3
    IMUL  R2, R5            ; R2 = y * width
    IADD  R1, R2            ; R1 = byte index

    ;; Load tile index directly (each word = one byte)
    MOV   R12,  var_TIC80_MAP_BUFFER_PTR
    MOV   R12,  [R12]
    MOV   R0,   R12
    IADD  R0,   R1
    MOV   R0,   [R0]          ; R0 = tile index

    ;; Return as boxed Lua number
    CIF   R0
    JMP   _tic80_mget_done

_tic80_mget_invalid:
    MOV   R0, BOXED_NIL

_tic80_mget_done:
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_tic80_mset: Set Tile in TIC-80 Map
;;
;; Stack: [BP+2] = x, [BP+3] = y, [BP+4] = value (tile index 0-255)
;;
;; Writes a tile to the map buffer at (x,y) using actual cartridge dimensions.
;; Clamps value to 0-255 range. Returns the value as boxed Lua number.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_tic80_mset:
    PUSH  BP
    MOV   BP, SP

    ;; Load buffer pointer
    MOV   R1,  var_TIC80_MAP_BUFFER_PTR
    MOV   R12, [R1]
    MOV   R2,  R12
    IEQ   R2,  0
    JT    R2,  _tic80_mset_done

    ;; X: Load coordinate argument
    MOV   R1, [BP+2]        ; x

    ;; Snap to integer tile coordinates
    FADD  R1, 0.5
    CFI   R1                ; R1 = round(x)

    ;; X: Snap to 0.1-pixel grid, then round to integer
;   FMUL  R1, 10.0          ; x * 10 (float)
;   FADD  R1, 0.5           ; + 0.5 (float)
;   CFI   R1                ; → integer (round(x*10))
;   IDIV  R1, 10            ; integer division: round(x*10) / 10

    ;; Y: Load coordinate argument
    MOV   R2, [BP+3]        ; y
    FADD  R2, 0.5
    CFI   R2                ; R2 = round(y)

    ;; Y: Snap to 0.1-pixel grid, then round to integer
;   FMUL  R2, 10.0          ; y * 10 (float)
;   FADD  R2, 0.5           ; + 0.5 (float)
;   CFI   R2                ; → integer (round(y*10))
;   IDIV  R2, 10            ; integer division: round(y*10) / 10

    ;; load value argument
    MOV   R3, [BP+4]        ; value
    CFI   R3

    ;; Load ACTUAL map dimensions for bounds checking
    MOV   R4, var_TIC80_MAP_WIDTH
    MOV   R4, [R4]          ; R4 = actual width
    MOV   R5, var_TIC80_MAP_HEIGHT
    MOV   R5, [R5]          ; R5 = actual height

    ;; Bounds check: x
    MOV   R6, R1
    ILT   R6, 0
    JT    R6, _tic80_mset_done
    MOV   R6, R1
    IGE   R6, R4
    JT    R6, _tic80_mset_done

    ;; Bounds check: y
    MOV   R6, R2
    ILT   R6, 0
    JT    R6, _tic80_mset_done
    MOV   R6, R2
    IGE   R6, R5
    JT    R6, _tic80_mset_done

    ;; Clamp value to 0-255 (TIC-80 uses 0-511 but 256 is enough for most cases)
    MOV   R6, R3
    ILT   R6, 0
    JT    R6, _tic80_mset_clamp_zero
    MOV   R6, R3
    IGT   R6, 255
    JT    R6, _tic80_mset_clamp_max
    JMP   _tic80_mset_store

_tic80_mset_clamp_zero:
    MOV   R3, 0
    JMP   _tic80_mset_store

_tic80_mset_clamp_max:
    MOV   R3, 255

_tic80_mset_store:
    ;; Calculate byte index: index = y * width + x
    MOV   R6, R4
    IMUL  R2, R6            ; R2 = y * width
    IADD  R1, R2            ; R1 = byte index

    ;; Store tile index directly (each word = one byte)
    MOV   R2, R12
    IADD  R2, R1
    MOV   [R2], R3          ; Store tile index

    ;; Return the value (boxed)
    CIF   R3
    MOV   R0, R3

_tic80_mset_done:
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_tic80_map: Draw TIC-80 Map Region to Screen
;;
;; Stack: [BP+2] = x (screen X)
;;        [BP+3] = y (screen Y)
;;        [BP+4] = w (width in tiles)
;;        [BP+5] = h (height in tiles)
;;        [BP+6] = sx (source X in map)
;;        [BP+7] = sy (source Y in map)
;;        [BP+8] = color_key (transparent color)
;;
;; Renders a w × h tile region from the map buffer to the screen at (x,y).
;; Uses actual cartridge map dimensions from RAM (var_TIC80_MAP_WIDTH/HEIGHT)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_tic80_map:
    PUSH  BP
    MOV   BP, SP

    ;; Save callee-saved registers
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    PUSH  R6
    PUSH  R7
    PUSH  R8
    PUSH  R9
    PUSH  R10
    PUSH  R11
    PUSH  R12
    PUSH  R13

    ;; Load buffer pointer
    MOV   R1,  var_TIC80_MAP_BUFFER_PTR
    MOV   R12, [R1]
    IEQ   R12, 0
    JT    R12, _tic80_map_done
    MOV   R12, [R1]         ; restore R12 after destructive comparison

    ;; Load arguments
    MOV   R5, [BP+2]        ; sx (source X in map)  <-- Was R1
    MOV   R6, [BP+3]        ; sy (source Y in map)  <-- Was R2
    MOV   R1, [BP+6]        ; x (screen X)          <-- Was R5
    MOV   R2, [BP+7]        ; y (screen Y)          <-- Was R6
    ;MOV   R1, [BP+2]        ; x
    ;MOV   R2, [BP+3]        ; y
    MOV   R3, [BP+4]        ; w
    MOV   R4, [BP+5]        ; h
    ;MOV   R5, [BP+6]        ; sx
    ;MOV   R6, [BP+7]        ; sy
    CFI   R1
    CFI   R2
    CFI   R3
    CFI   R4
    CFI   R5
    CFI   R6

    ;; Load ACTUAL map dimensions
    MOV   R7, var_TIC80_MAP_WIDTH
    MOV   R7, [R7]          ; R7 = actual width
    MOV   R8, var_TIC80_MAP_HEIGHT
    MOV   R8, [R8]          ; R8 = actual height

    ;; Validate dimensions
    MOV   R11, R3
    ILT   R11, 1
    JT    R11, _tic80_map_done
    MOV   R11, R4
    ILT   R11, 1
    JT    R11, _tic80_map_done

    ;; Clamp sx: 0 <= sx <= width - w
    MOV   R11, R5
    ILT   R11, 0
    JT    R11, _tic80_map_sx_zero
    MOV   R9,  R7
    ISUB  R9,  R3
    MOV   R11, R5
    IGT   R11, R9
    JT    R11, _tic80_map_sx_max
    JMP   _tic80_map_check_sy

_tic80_map_sx_zero:
    MOV   R5, 0
    JMP   _tic80_map_check_sy

_tic80_map_sx_max:
    MOV   R5, R9

_tic80_map_check_sy:
    MOV   R11, R6
    ILT   R11, 0
    JT    R11, _tic80_map_sy_zero
    MOV   R9,  R8
    ISUB  R9,  R4
    MOV   R11, R6
    IGT   R11, R9
    JT    R11, _tic80_map_sy_max
    JMP   _tic80_map_row_loop_prestart

_tic80_map_sy_zero:
    MOV   R6, 0
    JMP   _tic80_map_row_loop_start

_tic80_map_sy_max:
    MOV   R6, R9

    ;; Save width in R11 for byte index calculation
    MOV   R11, R7

    ;; Outer loop: rows (R9)
_tic80_map_row_loop_prestart:
    MOV   R9, 0
_tic80_map_row_loop_start:
    MOV   R7, R9           ; Use R7 as scratch for condition check
    IGE   R7, R4
    JT    R7, _tic80_map_done

    ;; Inner loop: columns (R10)
    MOV   R10, 0
_tic80_map_col_loop_start:
    MOV   R7, R10          ; Use R7 as scratch for condition check
    IGE   R7, R3
    JT    R7, _tic80_map_row_loop_next

    ;; Calculate map cell position: (sx + col, sy + row)
    MOV   R7, R5
    IADD  R7, R10          ; R7 = sx + col
    MOV   R8, R6
    IADD  R8, R9           ; R8 = sy + row

    ;; Calculate byte index: (sy+row) * width + (sx+col)
    MOV   R11, var_TIC80_MAP_WIDTH
    MOV   R11, [R11]       ; R7 = actual width
    IMUL  R8, R11          ; R8 = (sy+row) * width (R11 is safely preserved)
    IADD  R7, R8           ; R7 = byte index

    ;; Load tile index directly
    MOV   R8, R12          ; R12 is value at var_TIC80_MAP_BUFFER_PTR
    IADD  R8, R7           ; 
    MOV   R7, [R8]         ; R7 = tile index (Leaves R10 untouched!)

    PUSH  R1               ; x save
    PUSH  R2               ; y save
    PUSH  R3               ; w save
    PUSH  R4               ; h save
    PUSH  R5               ; sx save
    PUSH  R6               ; sy save
    PUSH  R7
    PUSH  R8
    PUSH  R9
    PUSH  R10              ; column index save
    PUSH  R11
    PUSH  R12
    PUSH  R13              ; color_key save
    
    ;; Push arguments for __builtin_tic80_spr (in reverse order)
    MOV   R0, 1.0
    PUSH  R0               ; h = 1.0
    PUSH  R0               ; w = 1.0
    MOV   R0, 0
    PUSH  R0               ; rotate = 0
    PUSH  R0               ; flip = 0
    MOV   R0, 1.0
    PUSH  R0               ; scale = 1.0

    MOV   R0, [BP+8]       ; color_key
    PUSH  R0               ; color_key (safely preserved!)
    
    ;; Calculate screen Y position: y + row*8
    MOV   R0, R9           ; R0 = row
    IMUL  R0, 8
    IADD  R0, R2           ; R0 = screen_y + row*8
    CIF   R0
    PUSH  R0               ; y

    MOV   R0, R10          ; R0 = col (loop counter)
    IMUL  R0, 8            ; R0 = col * 8
    IADD  R0, R1           ; R0 = x + col * 8 (screen coordinate)
    CIF   R0
    PUSH  R0               ; x
    
    MOV   R0, R7
    CIF   R0
    PUSH  R0               ; id

    CALL  __builtin_tic80_spr

    IADD  SP, 9

    POP   R13              ; color_key restore
    POP   R12
    POP   R11
    POP   R10              ; column index restore
    POP   R9
    POP   R8
    POP   R7
    POP   R6               ; sy restore
    POP   R5               ; sx restore
    POP   R4               ; h restore
    POP   R3               ; w restore
    POP   R2               ; y restore
    POP   R1               ; x restore

    ;; Next column
    IADD  R10, 1           ; R10 has been clobbered by __builtin_tic80_spr
    JMP   _tic80_map_col_loop_start

_tic80_map_row_loop_next:
    IADD  R9, 1
    JMP   _tic80_map_row_loop_start

_tic80_map_done:
    ;; Restore registers
    POP   R13
    POP   R12
    POP   R11
    POP   R10
    POP   R9
    POP   R8
    POP   R7
    POP   R6
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1

    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_tic80_pmem: Access TIC-80 Persistent Memory (mapped to Vircon32 MEMCARD)
;;
;; TIC-80 pmem() signature:
;;   pmem(index)          -> returns byte value at index (read)
;;   pmem(index, value)  -> writes byte value at index (write)
;;
;; Stack layout:
;;   [BP+2] = index (0-65535 for TIC-80's 64KB)
;;   [BP+3] = value (optional, for write)
;;
;; Returns: R0 = byte value (for read), or the value written (for write)
;;
;; Maps TIC-80's 64KB persistent memory to first 64KB of Vircon32 MEMCARD
;; MEMCARD base: 0x30000000, size: 1MB (0x100000 bytes)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_tic80_pmem:
    PUSH  BP
    MOV   BP, SP

    ;; Check if this is a write operation (2 arguments)
    ;; Stack has: [BP+0]=return addr, [BP+1]=old BP, [BP+2]=index, [BP+3]=value
    MOV   R1, [BP+3]        ; Load potential value argument
    MOV   R2, BOXED_NIL
    IEQ   R1, R2
    JT    R1, _tic80_pmem_read

    ;; === WRITE OPERATION ===
    ;; Convert index to integer
    MOV   R1, [BP+2]        ; index
    CFI   R1                ; R1 = integer index

    ;; Bounds check: 0 <= index < 65536 (TIC-80 pmem limit)
	MOV   R2, R1
    ILT   R2, 0
    JT    R2, _tic80_pmem_invalid
	MOV   R2, R1
    IGE   R2, 65536
    JT    R2, _tic80_pmem_invalid

    ;; Convert value to integer (byte)
    MOV   R2, [BP+3]        ; value
    CFI   R2
    AND   R2, 0xFF         ; Clamp to byte (0-255)

    ;; Calculate MEMCARD address: 0x30000000 + index
    MOV   R3, 0x30000000
    IADD  R3, R1           ; R3 = MEMCARD address

    ;; Write byte to MEMCARD
    MOV   [R3], R2

    ;; Return the value written (as boxed Lua number)
    CIF   R2
    MOV   R0, R2
    JMP   _tic80_pmem_done

_tic80_pmem_read:
    ;; === READ OPERATION ===
    MOV   R1, [BP+2]        ; index
    CFI   R1                ; R1 = integer index

    ;; Bounds check
	MOV   R0, R1
    ILT   R0, 0
    JT    R0, _tic80_pmem_invalid
	MOV   R0, R1
    IGE   R0, 65536
    JT    R0, _tic80_pmem_invalid

    ;; Calculate MEMCARD address
    MOV   R3, 0x30000000
    IADD  R3, R1

    ;; Read byte from MEMCARD
    MOV   R0, [R3]
    AND   R0, 0xFF         ; Ensure byte value

    ;; Return as boxed Lua number
    CIF   R0
    JMP   _tic80_pmem_done

_tic80_pmem_invalid:
    MOV   R0, BOXED_NIL     ; Return nil for out-of-bounds

_tic80_pmem_done:
    MOV   SP, BP
    POP   BP
    RET
