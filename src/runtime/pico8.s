;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; SECTION: PICO-8 API LAYER
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ===========================================================================
;; PICO-8 CONSTANTS
;; ===========================================================================
;; Map dimensions (PICO-8 default: 128x32 cells, but can support up to 128x64)
%define PICO8_MAP_MAX_WIDTH     128
%define PICO8_MAP_MAX_HEIGHT    64
%define PICO8_MAP_MAX_CELLS     8192   ; 128*64
%define PICO8_MAP_ACTUAL_WIDTH  128
%define PICO8_MAP_ACTUAL_HEIGHT 128

;; Display scale: 128x128 PICO-8 canvas -> 640x360 Vircon32 screen.
;; 2.75 is chosen deliberately over a more "exact" ratio (640/128=5.0
;; would overflow; other in-between values produced the same 1px
;; sub-pixel seam issue seen on TIC-80's non-clean scale factors) --
;; 128*2.75=352, a clean integer, avoids that. Centered on a 640x360
;; screen: (640-352)/2=144 would be the naive top-left-origin center,
;; but measured against the real GPU coordinate origin the correct
;; offset is 464 horizontally; vertically (360-352)/2=4 does match.
%define PICO8_SCALE             2.75
%define PICO8_OFFSET_X          464
%define PICO8_OFFSET_Y          4

;; Buffer size in words (64KB = 16384 words)
%define PICO8_MAP_BUFFER_WORDS  16384

;; Swatch bank: 16 solid-color 3x3 cells (1px gaps) on row y=128..130
;; of texture 0, which the VTEX generator extends to 128x132. Regions
;; 256-271 -- must match PICO8_SWATCH_REGION_BASE in pico8_assets.h.
%define PICO8_SWATCH_REGION_BASE 256

;; PICO-8 uses the same default palette as TIC-80
__pico8_palette:
    integer 0xFF2C1C1A  ; 0
    integer 0xFF5D275D  ; 1
    integer 0xFF533EB1  ; 2
    integer 0xFF577DEF  ; 3
    integer 0xFF75CDFF  ; 4
    integer 0xFF70F0A7  ; 5
    integer 0xFF64B738  ; 6
    integer 0xFF797125  ; 7
    integer 0xFF6F3629  ; 8
    integer 0xFFC95D3B  ; 9
    integer 0xFFF6A641  ; 10
    integer 0xFFF7EF73  ; 11
    integer 0xFFF4F4F4  ; 12
    integer 0xFFC2B094  ; 13
    integer 0xFF866C56  ; 14
    integer 0xFF573C33  ; 15

;; Static map data (populated by compiler if PICO-8 cartridge has map)
__pico8_map_static_width:
    integer 128

__pico8_map_static_height:
    integer 64

__pico8_map_static_data:
    integer 0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_pico8_init (initialize 256 regions of 8x8 pixels for texture 0)
;;
;; Creates 256 regions (0-255) arranged in a 16-column × 16-row grid
;; Each region is exactly 8×8 pixels with hotspot at TOP-LEFT (0,0)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_init:
    PUSH  BP
    MOV   BP, SP

    ;; Save callee-saved registers
    PUSH  R13
    PUSH  R14

    ;; Select texture 0 (PICO-8 uses single texture)
    MOV   R13, 0
    OUT   GPU_SelectedTexture, R13

    ;; Initialize all 256 regions for texture 0
    MOV   R1, 0             ; R1 = region ID (0 to 255)
    MOV   R2, 0             ; R2 = x position in texture (0 to 127)
    MOV   R3, 0             ; R3 = y position in texture (0 to 127)

_pico8_init_loop:
    ;; Exit when all 256 regions are initialized
    MOV   R0, R1
    IEQ   R0, 256
    JT    R0, _pico8_init_swatches   ; exit INTO the swatch registration
    JT    R0, _pico8_init_map

    ;; Select current region
    OUT   GPU_SelectedRegion, R1

    ;; Set region bounds: 8x8 pixels
    OUT   GPU_RegionMinX, R2
    OUT   GPU_RegionMinY, R3

    ;; Hotspot at TOP-LEFT of region in TEXTURE coordinates (0,0)
    MOV   R14, 0
    OUT   GPU_RegionHotspotX, R14
    OUT   GPU_RegionHotspotY, R14

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
    JF    R0, _pico8_init_loop

    ;; Wrap to next row: reset x to 0, advance y by 8 pixels
    MOV   R2, 0
    IADD  R3, 8
    JMP   _pico8_init_loop

_pico8_init_swatches:
    ;; Register the 16 solid-color palette swatches (regions 256-271)
    ;; on texture 0. Mirrors the TIC-80 swatch bank geometry: 3x3 cells,
    ;; 1px gaps, row at y=128..130, hotspot top-left.
    MOV   R1, PICO8_SWATCH_REGION_BASE   ; region id (256)
    MOV   R2, 0                          ; color index / column counter

_pico8_init_swatch_loop:
    MOV   R0, R2                  ; destructive test on a copy
    IEQ   R0, 16
    JT    R0, _pico8_init_swatch_done

    OUT   GPU_SelectedRegion, R1

    MOV   R3, R2
    IMUL  R3, 4                   ; x = color * 4  (3px cell + 1px gap)
    OUT   GPU_RegionMinX, R3
    MOV   R4, 128
    OUT   GPU_RegionMinY, R4      ; swatch row

    OUT   GPU_RegionHotspotX, R3
    OUT   GPU_RegionHotspotY, R4  ; top-left (line() relies on this)

    MOV   R4, R3
    IADD  R4, 2                   ; MaxX = MinX + 2 (3px wide)
    OUT   GPU_RegionMaxX, R4
    MOV   R4, 130
    OUT   GPU_RegionMaxY, R4      ; MinY + 2 (3px tall)

    IADD  R1, 1
    IADD  R2, 1
    JMP   _pico8_init_swatch_loop

_pico8_init_swatch_done:
_pico8_init_map:
    ;; Initialize map buffer after texture regions
    CALL  __builtin_pico8_init_map

    ;; Restore callee-saved registers
    POP   R14
    POP   R13

    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_pico8_init_map: Allocate and initialize PICO-8 map buffer
;;
;; Allocates 64KB map buffer and copies static map data if available
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_init_map:
    PUSH  BP
    MOV   BP, SP

    ;; Allocate map buffer (64KB)
    MOV   R0, PICO8_MAP_BUFFER_WORDS
    PUSH  R0
    CALL  __malloc
    IADD  SP, 1

    ;; Store pointer globally
    MOV   R1, var_PICO8_MAP_BUFFER_PTR
    MOV   [R1], R0
    MOV   R12, R0            ; R12 = buffer

    ;; Check for static map data (width > 0?)
    MOV   R1, __pico8_map_static_width
    MOV   R1, [R1]
    IEQ   R1, 0
    JT    R1, _pico8_init_map_zero_fill

    ;; Copy loop
    MOV   R2, 0                ; byte index
    MOV   R3, __pico8_map_static_width
    MOV   R3, [R3]
    MOV   R6, __pico8_map_static_height
    MOV   R6, [R6]
    IMUL  R3, R6              ; R3 = total bytes
    MOV   R7, __pico8_map_static_data

_pico8_init_map_copy_loop:
    MOV   R8, R2
    ILT   R8, R3
    JT    R8, _pico8_copy_continue
    JMP   _pico8_init_map_done

_pico8_copy_continue:
    MOV   R8, R7
    IADD  R8, R2
    MOV   R8, [R8]

    MOV   R1, R12
    IADD  R1, R2
    MOV   [R1], R8

    IADD  R2, 1
    JMP   _pico8_init_map_copy_loop

    ;; Zero-fill fallback
_pico8_init_map_zero_fill:
    MOV   R2, 0
    MOV   R3, PICO8_MAP_BUFFER_WORDS
    SHL   R3, 2              ; bytes = words * 4

_pico8_init_map_zero_loop:
    MOV   R8, R2
    ILT   R8, R3
    JT    R8, _pico8_zero_continue
    JMP   _pico8_init_map_done

_pico8_zero_continue:
    MOV   R8, 0
    MOV   R1, R12
    IADD  R1, R2
    MOV   [R1], R8

    IADD  R2, 1
    JMP   _pico8_init_map_zero_loop

_pico8_init_map_done:
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_pico8_cls: Clear screen to color
;;
;; Stack: [BP+2] = color (palette index 0-15 or 32-bit RGBA value)
;; Uses: R1-R4
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_cls:
    PUSH  BP
    MOV   BP, SP

    MOV   R1, [BP+2]        ; Load color argument

    ;; If color is a small integer (0-15), map to PICO-8 palette
    MOV   R2, R1
    CFI   R2                ; Convert to integer in R2

    ;; Check if 0 <= R2 < 16 (palette index range)
    ILT   R2, 0
    JT    R2, _pico8_cls_use_direct
    IGE   R2, 16
    JT    R2, _pico8_cls_use_direct

    ;; Palette lookup: R2 is valid index 0-15
    ;; Each palette entry is 4 bytes, so offset = R2 * 4
    SHL   R2, 2            ; R2 = R2 * 4
    MOV   R3, __pico8_palette
    IADD  R3, R2
    MOV   R1, [R3]        ; Load 32-bit color from palette

_pico8_cls_use_direct:
    ;; R1 now contains the 32-bit RGBA color
    OUT   GPU_ClearColor, R1
    OUT   GPU_Command, GPUCommand_ClearScreen

    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_pico8_mget: Get map cell value
;;
;; Stack: [BP+2] = x, [BP+3] = y
;; Returns: sprite ID (0-255) or NIL if out of bounds
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_mget:
    PUSH  BP
    MOV   BP, SP

    ;; Load buffer pointer
    MOV   R1, var_PICO8_MAP_BUFFER_PTR
    MOV   R12, [R1]
    IEQ   R12, 0
    JT    R12, _pico8_mget_invalid

    ;; Load arguments
    MOV   R1, [BP+2]        ; x
    MOV   R2, [BP+3]        ; y
    CFI   R1
    CFI   R2

    ;; Bounds check: x
    ILT   R1, 0
    JT    R1, _pico8_mget_invalid
    IGE   R1, PICO8_MAP_ACTUAL_WIDTH
    JT    R1, _pico8_mget_invalid

    ;; Bounds check: y
    ILT   R2, 0
    JT    R2, _pico8_mget_invalid
    IGE   R2, PICO8_MAP_ACTUAL_HEIGHT
    JT    R2, _pico8_mget_invalid

    ;; Calculate byte index: index = y * width + x
    MOV   R3, PICO8_MAP_ACTUAL_WIDTH
    IMUL  R2, R3            ; R2 = y * width
    IADD  R1, R2            ; R1 = byte index (0-65535)

    ;; Calculate word address and byte offset
    MOV   R3, R1
    SHL   R3, -2           ; R3 = word index (byte_index / 4)
    AND   R1, 3            ; R1 = byte offset within word (0-3)

    ;; Load word from buffer
    MOV   R4, R12
    IADD  R4, R3
    MOV   R5, [R4]         ; R5 = word containing our byte

    ;; Extract the byte
    SHL   R1, 3            ; R1 = bit shift (0, 8, 16, 24)
    MOV   R6, 0xFF
    SHL   R6, R1           ; R6 = byte mask
    AND   R5, R6           ; R5 = isolated byte
    ISGN  R1
    SHL   R5, R1           ; Shift right to extract byte value

    ;; Return as boxed Lua number
    CIF   R5
    JMP   _pico8_mget_done

_pico8_mget_invalid:
    MOV   R0, BOXED_NIL

_pico8_mget_done:
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_pico8_mset: Set map cell value
;;
;; Stack: [BP+2] = x, [BP+3] = y, [BP+4] = value (0-255)
;; Returns: value (boxed)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_mset:
    PUSH  BP
    MOV   BP, SP

    ;; Load buffer pointer
    MOV   R1, var_PICO8_MAP_BUFFER_PTR
    MOV   R12, [R1]
    IEQ   R12, 0
    JT    R12, _pico8_mset_done

    ;; Load arguments
    MOV   R1, [BP+2]        ; x
    MOV   R2, [BP+3]        ; y
    MOV   R3, [BP+4]        ; value
    CFI   R1
    CFI   R2
    CFI   R3

    ;; Bounds check: x
    ILT   R1, 0
    JT    R1, _pico8_mset_done
    IGE   R1, PICO8_MAP_ACTUAL_WIDTH
    JT    R1, _pico8_mset_done

    ;; Bounds check: y
    ILT   R2, 0
    JT    R2, _pico8_mset_done
    IGE   R2, PICO8_MAP_ACTUAL_HEIGHT
    JT    R2, _pico8_mset_done

    ;; Clamp value to 0-255 (PICO-8 sprite IDs)
    ILT   R3, 0
    JT    R3, _pico8_mset_clamp_zero
    IGT   R3, 255
    JT    R3, _pico8_mset_clamp_max
    JMP   _pico8_mset_store

_pico8_mset_clamp_zero:
    MOV   R3, 0
    JMP   _pico8_mset_store

_pico8_mset_clamp_max:
    MOV   R3, 255

_pico8_mset_store:
    ;; Calculate byte index
    MOV   R4, PICO8_MAP_ACTUAL_WIDTH
    IMUL  R2, R4            ; R2 = y * width
    IADD  R1, R2            ; R1 = byte index

    ;; Calculate word address and byte offset
    MOV   R4, R1
    SHL   R4, -2           ; R4 = word index
    AND   R1, 3            ; R1 = byte offset (0-3)

    ;; Load current word
    MOV   R5, R12
    IADD  R5, R4
    MOV   R6, [R5]         ; R6 = current word

    ;; Clear the target byte
    MOV   R7, 0xFF
    SHL   R7, R1           ; R7 = byte mask
    NOT   R7               ; R7 = inverted mask
    AND   R6, R7           ; Clear target byte

    ;; Set the target byte
    SHL   R3, R1           ; Shift value to correct position
    OR    R6, R3           ; Set the byte

    ;; Store back to buffer
    MOV   R5, R12
    IADD  R5, R4
    MOV   [R5], R6

    ;; Return the value (boxed)
    CIF   R3

_pico8_mset_done:
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_pico8_map: Draw map region to screen
;;
;; Real PICO-8 signature: map(celx, cely, sx, sy, celw, celh, [layer])
;; Stack: [BP+2]=celx, [BP+3]=cely, [BP+4]=sx, [BP+5]=sy,
;;        [BP+6]=celw, [BP+7]=celh, [BP+8]=layer (optional, default 0)
;;
;; Loaded into the SAME registers this routine already used under the
;; old argument order (R1/R2 = screen position, R5/R6 = map-cell
;; offset, R3/R4 = dimensions), so only the "Load arguments" block
;; below differs from before -- the clamp/lookup logic is unchanged.
;;
;; Note: PICO-8 map uses sprite IDs 0-255 (vs TIC-80's 0-511)
;;
;; TODO: real PICO-8's [layer] argument only draws tiles whose sprite
;; flags match the given bitmask. Not implemented -- every tile in the
;; requested region is drawn regardless of layer/flags. PICO-8 also has
;; no fget()/fset() at all yet on this API surface (only TIC-80 does),
;; which would need to exist first.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_map:
    PUSH  BP
    MOV   BP, SP

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

    MOV   R1, var_PICO8_MAP_BUFFER_PTR
    MOV   R12, [R1]
    IEQ   R12, 0
    JT    R12, _pico8_map_done

    ;; Load arguments
    MOV   R1, [BP+4]        ; sx (screen X, raw PICO-8 pixels)
    MOV   R2, [BP+5]        ; sy (screen Y, raw PICO-8 pixels)
    MOV   R3, [BP+6]        ; celw
    MOV   R4, [BP+7]        ; celh
    MOV   R5, [BP+2]        ; celx (map cell offset X)
    MOV   R6, [BP+3]        ; cely (map cell offset Y)
    MOV   R13, [BP+8]       ; layer (optional, default 0; unused for now)
    CFI   R1
    CFI   R2
    CFI   R3
    CFI   R4
    CFI   R5
    CFI   R6
    CFI   R13

    ;; Validate dimensions
    ILT   R3, 1
    JT    R3, _pico8_map_done
    ILT   R4, 1
    JT    R4, _pico8_map_done

    ;; Clamp celx
    MOV   R7, R5
    ILT   R7, 0
    JT    R7, _pico8_map_sx_zero
    MOV   R8, PICO8_MAP_ACTUAL_WIDTH
    ISUB  R8, R3
    IGT   R7, R8
    JT    R7, _pico8_map_sx_max
    JMP   _pico8_map_check_sy

_pico8_map_sx_zero:
    MOV   R5, 0
    JMP   _pico8_map_check_sy

_pico8_map_sx_max:
    MOV   R5, R8

    ;; Clamp cely
_pico8_map_check_sy:
    MOV   R7, R6
    ILT   R7, 0
    JT    R7, _pico8_map_sy_zero
    MOV   R8, PICO8_MAP_ACTUAL_HEIGHT
    ISUB  R8, R4
    IGT   R7, R8
    JT    R7, _pico8_map_sy_max
    JMP   _pico8_map_row_loop_start

_pico8_map_sy_zero:
    MOV   R6, 0
    JMP   _pico8_map_row_loop_start

_pico8_map_sy_max:
    MOV   R6, R8

_pico8_map_row_loop_start:
    MOV   R9, 0
    ; (fallthrough retained from original structure)

    MOV   R7, R9
    IGE   R7, R4
    JT    R7, _pico8_map_done

    MOV   R10, 0
_pico8_map_col_loop_start:
    MOV   R7, R10
    IGE   R7, R3
    JT    R7, _pico8_map_row_loop_next

    MOV   R7, R5
    IADD  R7, R10           ; celx + col
    MOV   R8, R6
    IADD  R8, R9            ; cely + row

    MOV   R11, PICO8_MAP_ACTUAL_WIDTH
    IMUL  R8, R11
    IADD  R7, R8

    MOV   R8, R7
    SHL   R8, -2
    AND   R7, 3

    MOV   R11, R12
    IADD  R11, R8
    MOV   R11, [R11]

    SHL   R7, 3
    ISGN  R7
    SHL   R11, R7
    AND   R11, 0xFF        ; R11 = sprite ID

    ;; Calculate RAW screen position (still PICO-8 pixel space --
    ;; __builtin_pico8_spr applies PICO8_SCALE + centering itself).
    MOV   R7, R10
    IMUL  R7, 8
    IADD  R7, R1           ; sx + col*8
    MOV   R8, R9
    IMUL  R8, 8
    IADD  R8, R2           ; sy + row*8

    CIF   R7                ; -> float x, for __builtin_pico8_spr
    CIF   R8                ; -> float y, for __builtin_pico8_spr

    ;; Draw this tile using __builtin_pico8_spr's REAL 7-argument
    ;; signature (n, x, y, w, h, flip_x, flip_y). The previous version
    ;; pushed 9 arguments -- a stale layout from before spr()'s
    ;; signature was finalized -- and built them by clobbering R10, the
    ;; live COLUMN LOOP COUNTER, as scratch. R0 is genuinely free here.
    MOV   R0, BOXED_FALSE
    PUSH  R0                ; flip_y = false
    PUSH  R0                ; flip_x = false
    MOV   R0, 1.0
    PUSH  R0                ; h = 1
    PUSH  R0                ; w = 1
    PUSH  R8                ; y
    PUSH  R7                ; x
    MOV   R0, R11
    CIF   R0                ; sprite id as float
    PUSH  R0                ; n

    CALL  __builtin_pico8_spr
    IADD  SP, 7

    IADD  R10, 1
    JMP   _pico8_map_col_loop_start

_pico8_map_row_loop_next:
    IADD  R9, 1
    JMP   _pico8_map_row_loop_start

_pico8_map_done:
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

    ;; --- Callee-Save ---
    ;; This routine is called both directly (compiler-emitted spr()
    ;; intrinsic) and from inside __builtin_pico8_map()'s per-tile draw
    ;; loop, which keeps live state (loop counters, base position) in
    ;; registers across the CALL. This routine uses R1-R10 internally,
    ;; so all of them must be preserved -- their absence here previously
    ;; corrupted map()'s row/col counters on every tile it drew.
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

    ;; --- 1. Set Global Scales & Flip Flags ---
    ;; Uniform PICO8_SCALE: 128 PICO-8 px * 2.75 = 352px square, centered
    ;; via PICO8_OFFSET_X/Y below.
    MOV   R1, PICO8_SCALE
    MOV   R2, [BP+7]        ; flip_x
    IEQ   R2, BOXED_TRUE
    JF    R2, _pico8_spr_set_scale_x
    FSGN  R1
_pico8_spr_set_scale_x:
    OUT   GPU_DrawingScaleX, R1

    MOV   R1, PICO8_SCALE
    MOV   R2, [BP+8]        ; flip_y
    IEQ   R2, BOXED_TRUE
    JF    R2, _pico8_spr_set_scale_y
    FSGN  R1
_pico8_spr_set_scale_y:
    OUT   GPU_DrawingScaleY, R1

    ;; --- 2. Prepare Loop Limits ---
    MOV   R1, [BP+5]
    MOV   R5, R1            ; R5 = w
    CFI   R5                ; Convert float 'w' to integer limit (cols)
    MOV   R1, [BP+6]
    MOV   R6, R1            ; R6 = h
    CFI   R6                ; Convert float 'h' to integer limit (rows)

    MOV   R7, [BP+2]        ; R7 = Base sprite 'n'
    CFI   R7                ; Convert float 'n' to integer

    ;; --- 3. Scale + Center Base X/Y (camera offset applied first) ---
    ;; Base position arrives in raw PICO-8 pixel space (0..127-ish);
    ;; subtract the PICO-8 camera (also PICO-8 pixel space, so it must
    ;; happen BEFORE the 2.75x scale), then scale, round, and add the
    ;; fixed centering offset so the 352x352 canvas lands centered.
    ;; Round-before-truncate (FADD 0.5 -> CFI) matches the TIC-80 fix for
    ;; sub-pixel seams from an un-rounded scale multiply.
    MOV   R1, [BP+3]        ; base x (raw PICO-8 pixels)
    MOV   R2, [PICO8_CAMERA_X]
    FSUB  R1, R2            ; x - cam_x   (camera is pre-scale on purpose:
                            ;              celeste's ±2 shake = ±2 PICO-8 px)
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    CFI   R1
    IADD  R1, PICO8_OFFSET_X
    MOV   R8, R1            ; R8 = base X, Vircon32 screen pixels

    MOV   R1, [BP+4]        ; base y (raw PICO-8 pixels)
    MOV   R2, [PICO8_CAMERA_Y]
    FSUB  R1, R2            ; y - cam_y
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    CFI   R1
    IADD  R1, PICO8_OFFSET_Y
    MOV   R9, R1            ; R9 = base Y, Vircon32 screen pixels

    ;; --- Pre-calculate scaled per-tile offset (8 * scale) ---
    MOV   R1, 8.0
    FMUL  R1, PICO8_SCALE
    MOV   R10, R1           ; R10 = 8 * scale (Vircon32 pixels per tile)

    MOV   R4, 0             ; R4 = row

_pico8_spr_row_loop_start:
    MOV   R1, R4
    IGE   R1, R6
    JT    R1, _pico8_spr_end_spr

    MOV   R3, 0             ; R3 = col

_pico8_spr_col_loop_start:
    MOV   R1, R3
    IGE   R1, R5
    JT    R1, _pico8_spr_row_loop_end

    ;; --- 4. Calculate Target Region ID ---
    MOV   R1, R4
    IMUL  R1, 16
    IADD  R1, R3
    IADD  R1, R7
    OUT   GPU_SelectedRegion, R1

    ;; --- 5. Calculate X Coordinate (with rounding) ---
    MOV   R1, [BP+7]        ; check flip_x
    IEQ   R1, BOXED_TRUE
    JT    R1, _pico8_spr_calc_flip_x

    MOV   R1, R3
    CIF   R1
    FMUL  R1, R10
    FADD  R1, 0.5
    CFI   R1
    IADD  R1, R8
    JMP   _pico8_spr_set_x

_pico8_spr_calc_flip_x:
    MOV   R1, R5
    ISUB  R1, 1
    ISUB  R1, R3
    CIF   R1
    FMUL  R1, R10
    FADD  R1, 0.5
    CFI   R1
    IADD  R1, R8

_pico8_spr_set_x:
    OUT   GPU_DrawingPointX, R1

    ;; --- 6. Calculate Y Coordinate (with rounding) ---
    MOV   R1, [BP+8]        ; check flip_y
    IEQ   R1, BOXED_TRUE
    JT    R1, _pico8_spr_calc_flip_y

    MOV   R1, R4
    CIF   R1
    FMUL  R1, R10
    FADD  R1, 0.5
    CFI   R1
    IADD  R1, R9
    JMP   _pico8_spr_set_y

_pico8_spr_calc_flip_y:
    MOV   R1, R6
    ISUB  R1, 1
    ISUB  R1, R4
    CIF   R1
    FMUL  R1, R10
    FADD  R1, 0.5
    CFI   R1
    IADD  R1, R9

_pico8_spr_set_y:
    OUT   GPU_DrawingPointY, R1

    ;; --- 7. Issue Draw Command ---
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed

    IADD  R3, 1
    JMP   _pico8_spr_col_loop_start

_pico8_spr_row_loop_end:
    IADD  R4, 1
    JMP   _pico8_spr_row_loop_start

_pico8_spr_end_spr:
    ;; --- 8. Callee-Restore ---
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

;; ---------------------------------------------------------------------------
;; PICO-8 foreach(t, f): calls f(v) for every value in t's sequence part
;; (1..#t), in order. Discards f's return value; never stops early.
;;
;; Incoming Stack (pushed t, f in that order):
;;   [BP+3] = t (boxed table pointer)
;;   [BP+2] = f (boxed function)
;; Returns: R0 = BOXED_NIL (foreach() returns nothing in PICO-8)
;;
;; Loop state (n, i, f) lives in stack slots, not registers -- the same
;; defensive choice __builtin_table_sort makes for its comparator call,
;; since f is arbitrary user Lua code that can clobber any register
;; with no obligation to preserve it.
;; ---------------------------------------------------------------------------
__builtin_pico8_foreach:
    PUSH BP
    MOV  BP, SP
    ISUB SP, 3   ; [BP-1]=n  [BP-2]=i  [BP-3]=f (boxed)

    PUSH R1
    PUSH R2

    ;; --- Validate table ---
    MOV  R1, [BP+3]
    MOV  R2, R1
    AND  R2, BOXED_DATA
    IEQ  R2, BOXED_TABLE
    JF   R2, __runtime_error_not_table

    MOV  R1, [BP+2]
    MOV  [BP-3], R1          ; save callback function

    ;; --- n = #t ---
    MOV  R1, [BP+3]
    PUSH R1
    CALL __builtin_len
    IADD SP, 1
    MOV  R1, R0
    CFI  R1
    MOV  [BP-1], R1          ; n

    MOV  R1, 1
    MOV  [BP-2], R1           ; i = 1

__foreach_loop:
    MOV  R1, [BP-2]
    MOV  R2, [BP-1]
    IGT  R1, R2
    JT   R1, __foreach_done   ; i > n?

    ;; --- v = t[i] ---
    MOV  R1, [BP-2]
    CIF  R1
    MOV  R2, [BP+3]
    PUSH R2
    PUSH R1
    CALL __builtin_table_get
    IADD SP, 2

    ;; --- f(v) -- single argument, result discarded ---
    PUSH R0                   ; param 1 = v
    MOV  R0, [BP-3]
    CALL __builtin_exec
    IADD SP, 1

    MOV  R1, [BP-2]
    IADD R1, 1
    MOV  [BP-2], R1           ; i = i + 1
    JMP  __foreach_loop

__foreach_done:
    MOV  R0, BOXED_NIL

    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; ============================================================================
;; __builtin_pico8_sfx: PICO-8 sfx(n [, channel]) with a DYNAMIC n
;; ============================================================================
;; Stack layout relative to BP:
;; [BP+2]: n         (Lua float -- raw PICO-8 sfx index; <0 means "stop")
;; [BP+3]: channel   (Lua float 0-15, or BOXED_NIL -> auto/all)
;; [BP+4]: base_id   (RAW HARDWARE INTEGER, NOT a Lua float -- this is
;;                    pico8_tone_base_id, the resource id the compiler
;;                    assigned placeholder tone 0. Tones 1-7 are
;;                    base_id+1 .. base_id+7, contiguous, since the whole
;;                    bank is registered in one shot -- see
;;                    register_pico8_tone_bank() in pico8.c. Pushed bare,
;;                    never boxed: nothing but this one routine ever reads
;;                    it, same convention as VIRCON32_SFX_CURSOR below.)
;;
;; Only reached for a compile-time-UNKNOWN n -- emit_pico8_sfx_intrinsic()
;; in pico8.c folds every literal n straight into a static
;; emit_vircon32_sfx_play_intrinsic() call, no CALL at all. This routine
;; exists purely so celeste.lua's `psfx` wrapper (sfx(num), where num is a
;; parameter, not a literal) has somewhere to resolve the PICO-8 index ->
;; placeholder-tone mapping at runtime. Its channel handling and channel-
;; ownership bookkeeping mirror __builtin_vircon32_sfx_play exactly (see
;; that routine's own comments for the rationale); only the sound-id
;; resolution step is different.
;;
;; n < 0 is PICO-8's "stop" form (sfx(-1 [, channel])). PICO-8 requires an
;; explicit channel to stop just one; a bare sfx(-1) with no channel here
;; is a deliberate no-op -- the all-sfx-channels form is sfx.stop() itself,
;; reachable directly and not through this dynamic path.
;; ============================================================================
__builtin_pico8_sfx:
    PUSH  BP
    MOV   BP, SP

    MOV   R1, [BP+2]
    CFI   R1                      ; raw PICO-8 index as a hardware integer

    MOV   R2, R1
    ILT   R2, 0
    JT    R2, _pico8_sfx_stop_form

    ;; --- Non-negative index: map into the placeholder tone bank ---
    AND   R1, 7                   ; wrap into PICO8_TONE_COUNT (8) entries
    MOV   R2, [BP+4]              ; base_id (raw integer, see header note)
    IADD  R1, R2                  ; R1 = resolved placeholder tone id

    ;; --- Resolve the channel (identical to __builtin_vircon32_sfx_play) ---
    MOV   R2, [BP+3]
    MOV   R3, R2
    IEQ   R3, BOXED_NIL
    JT    R3, _pico8_sfx_auto_channel

    CFI   R2
    MOV   R3, R2
    ILT   R3, 0
    JT    R3, _pico8_sfx_clamp_low
    MOV   R3, R2
    IGT   R3, 15
    JF    R3, _pico8_sfx_channel_ready
    MOV   R2, 15
    JMP   _pico8_sfx_channel_ready

_pico8_sfx_clamp_low:
    MOV   R2, 0
    JMP   _pico8_sfx_channel_ready

_pico8_sfx_auto_channel:
    MOV   R2, [VIRCON32_SFX_CURSOR]
    MOV   R3, R2
    IADD  R3, 1
    MOV   R4, R3
    IGT   R4, 15
    JF    R4, _pico8_sfx_store_cursor
    MOV   R3, 1

_pico8_sfx_store_cursor:
    MOV   [VIRCON32_SFX_CURSOR], R3

_pico8_sfx_channel_ready:
    OUT   SPU_SelectedChannel, R2

    ;; --- Stop, THEN assign (a sound only assigns to a stopped channel) ---
    OUT   SPU_Command, SPUCommand_StopSelectedChannel
    OUT   SPU_ChannelAssignedSound, R1

    ;; --- Track channel ownership: claim for sfx, release from music ---
    MOV   R3, 1
    SHL   R3, R2                        ; R3 = 1 << channel
    MOV   R4, [VIRCON32_SFX_CHANNEL_MASK]
    OR    R4, R3
    MOV   [VIRCON32_SFX_CHANNEL_MASK], R4

    MOV   R4, R3
    NOT   R4                            ; R4 = ~(1 << channel)
    MOV   R3, [VIRCON32_MUSIC_CHANNEL_MASK]
    AND   R3, R4
    MOV   [VIRCON32_MUSIC_CHANNEL_MASK], R3

    ;; --- Volume/speed: no arguments to carry them on this call shape ---
    OUT   SPU_ChannelVolume, 1.0
    OUT   SPU_ChannelSpeed, 1.0

    ;; --- Start, then clear the loop flag the command just set ---
    OUT   SPU_Command, SPUCommand_PlaySelectedChannel
    OUT   SPU_ChannelLoopEnabled, 0

    MOV   R0, R2
    CIF   R0
    JMP   _pico8_sfx_done

_pico8_sfx_stop_form:
    MOV   R2, [BP+3]
    MOV   R3, R2
    IEQ   R3, BOXED_NIL
    JT    R3, _pico8_sfx_stop_done

    CFI   R2
    MOV   R3, R2
    ILT   R3, 0
    JT    R3, _pico8_sfx_stop_clamp_low
    MOV   R3, R2
    IGT   R3, 15
    JF    R3, _pico8_sfx_stop_channel_ready
    MOV   R2, 15
    JMP   _pico8_sfx_stop_channel_ready

_pico8_sfx_stop_clamp_low:
    MOV   R2, 0

_pico8_sfx_stop_channel_ready:
    OUT   SPU_SelectedChannel, R2
    OUT   SPU_Command, SPUCommand_StopSelectedChannel

_pico8_sfx_stop_done:
    MOV   R0, BOXED_NIL

_pico8_sfx_done:
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_pico8_count: PICO-8 count(t)
;;
;; Stack layout relative to BP:
;; [BP+2]: t (boxed table pointer)
;;
;; Returns: R0 = number of non-nil elements, as a boxed float
;;
;; Counts BOTH table parts (this is what separates count() from #t):
;;   - array part: elements [array_ptr .. array_ptr+length), counting
;;     words != BOXED_NIL (holes inside the tracked contiguous range
;;     are stored as BOXED_NIL words and skipped -- celeste's got_fruit
;;     depends on this).
;;   - hash part: the bucket chain rooted at Word 3, counting each
;;     stored (key, value) pair whose value word != BOXED_NIL.
;;
;; CODING RULES OBEYED HERE:
;;   - Vircon32 compares are DESTRUCTIVE: "IEQ Ra, Rb" overwrites Ra
;;     with the boolean result. R2 is the designated compare scratch:
;;     every destructive test loads a COPY into R2 first, so no live
;;     value is ever the destination. R2 holds nothing that survives
;;     past a single test.
;;   - Addressing has NO reg+reg form ([R1+R2] is illegal; only
;;     [R1+constant]). Both loops therefore walk with RUNNING
;;     POINTERS (incremented in place) against a precomputed END
;;     pointer, instead of indexing a base by a loop counter.
;;   - Two-operand arithmetic only: IADD R4, R3 computes R4 = R4 + R3.
;;
;; Register Usage: R1-R7 (all callee-saved)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_count:
    PUSH  BP
    MOV   BP, SP

    ;; --- Callee-Save ---
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    PUSH  R6
    PUSH  R7

    ;; --- 1. Validate + unbox table ---
    MOV   R1, [BP+2]              ; R1 = tagged table pointer
    MOV   R2, R1                  ; copy for the tag test (destructive!)
    AND   R2, BOXED_DATA
    IEQ   R2, BOXED_TABLE
    JF    R2, __runtime_error_not_table
    AND   R1, BOXED_PAYLOAD       ; R1 = raw table header

    MOV   R7, 0                   ; R7 = running count (raw integer)

    ;; --- 2. Array part: walk [array_ptr, array_ptr + length) ---
    MOV   R3, [R1+2]              ; R3 = array data pointer (Word 2)
    MOV   R2, R3                  ; test on scratch
    IEQ   R2, 0
    JT    R2, _pico8_count_hash   ; no array -> hash part only

    MOV   R4, [R1+1]              ; R4 = tracked contiguous length (Word 1)
    IADD  R4, R3                  ; R4 = end pointer = length + array base
    ;; (two-operand add: R4 = R4 + R3)

_pico8_count_array_loop:
    MOV   R2, R3                  ; test on scratch -- R3 (walker) survives
    IEQ   R2, R4
    JT    R2, _pico8_count_hash   ; walker reached end -> done with array

    MOV   R5, [R3]                ; R5 = current element (boxed word)
    MOV   R2, R5                  ; copy for the nil test (destructive!)
    IEQ   R2, BOXED_NIL
    JT    R2, _pico8_count_array_next
    IADD  R7, 1                   ; non-nil -> count it

_pico8_count_array_next:
    IADD  R3, 1                   ; advance walker (in place, no reg+reg)
    JMP   _pico8_count_array_loop

    ;; --- 3. Hash part: bucket chain walk ---
    ;; Bucket layout: Word 0 = PairCount, Word 1 = NextBucketPtr,
    ;; then PairCount (key, value) word pairs starting at offset 2.
_pico8_count_hash:
    MOV   R3, [R1+3]              ; R3 = base hash pointer (Word 3)
    MOV   R2, R3
    IEQ   R2, 0
    JT    R2, _pico8_count_done

_pico8_count_bucket_loop:
    MOV   R5, [R3]                ; R5 = PairCount of current bucket
    MOV   R4, R3
    IADD  R4, 2                   ; R4 = pairs walker -> &Key0
    MOV   R6, R5
    IMUL  R6, 2                   ; R6 = byte-ish span of pairs (in words)
    IADD  R6, R4                  ; R6 = pairs end pointer

_pico8_count_pair_loop:
    MOV   R2, R4                  ; test on scratch -- R4 (walker) survives
    IEQ   R2, R6
    JT    R2, _pico8_count_next_bucket

    MOV   R5, [R4+1]              ; R5 = value word of this pair
    MOV   R2, R5                  ; copy for the nil test (destructive!)
    IEQ   R2, BOXED_NIL
    JT    R2, _pico8_count_pair_next
    IADD  R7, 1                   ; non-nil -> count it

_pico8_count_pair_next:
    IADD  R4, 2                   ; advance to next (key, value) pair
    JMP   _pico8_count_pair_loop

_pico8_count_next_bucket:
    MOV   R6, [R3+1]              ; R6 = NextBucketPtr
    MOV   R2, R6                  ; test on scratch -- R6 survives only
    IEQ   R2, 0                   ; until the move below; fine either way
    JT    R2, _pico8_count_done   ; end of chain
    MOV   R3, R6                  ; step to next bucket
    JMP   _pico8_count_bucket_loop

_pico8_count_done:
    MOV   R0, R7
    CIF   R0                      ; count as boxed float

    ;; --- Callee-Restore ---
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
;; __builtin_pico8_del: PICO-8 del(t, v)
;;
;; Stack layout relative to BP:
;; [BP+3]: t (boxed table pointer)
;; [BP+2]: v (boxed value to remove)
;;
;; Returns: R0 = the removed value, or BOXED_NIL if not found
;;
;; Finds the first sequence index i in 1..#t whose element is equal to
;; v, then removes it via __builtin_table_remove(t, i), which performs
;; the shift-down (array path or hash path, whichever backs the table).
;; Composing those two routines instead of walking raw memory is the
;; point: the same logical sequence can live in the array part, the
;; hash buckets, or both, and table_remove already copes with each.
;;
;; Equality is a BITWISE word compare (IEQ) on the boxed values --
;; exact for pointers, booleans, nil, and same-representation numbers.
;; It does NOT compare string CONTENTS; del(t, "a") will not match a
;; RAM string with equal text stored at a different address. celeste's
;; call sites (del(objects, obj), del(dead_particles, p)) only ever
;; pass table pointers, which compare exactly.
;;
;; CODING RULES OBEYED HERE:
;;   - R2 is the DEDICATED compare scratch: every destructive test
;;     (IEQ/ILT) targets R2 after a copy, never a live source.
;;   - No [Rx+Ry] addressing (none is needed -- no raw memory walks).
;;   - State that must survive the nested table_get/table_remove CALLs
;;     lives ONLY in R1-R7 (both callees save exactly R1-R7; R8+ is
;;     not safe across a CALL).
;;
;; Register Usage: R1-R7 (all callee-saved by this routine too)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_del:
    PUSH  BP
    MOV   BP, SP

    ;; --- Callee-Save ---
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    PUSH  R6
    PUSH  R7

    MOV   R1, [BP+3]              ; R1 = tagged table pointer (kept tagged:
                                  ;        it is re-pushed for each sub-CALL)
    MOV   R6, [BP+2]              ; R6 = v (boxed), survives all sub-CALLs

    ;; --- 1. Validate + unbox header just to read Word 1 ---
    MOV   R2, R1                  ; scratch copy for tag test
    AND   R2, BOXED_DATA
    IEQ   R2, BOXED_TABLE
    JF    R2, __runtime_error_not_table
    MOV   R2, R1                  ; scratch copy for unbox
    AND   R2, BOXED_PAYLOAD
    MOV   R4, [R2+1]              ; R4 = tracked length (Word 1), raw int

    MOV   R3, 1                   ; R3 = i (raw int), 1-based scan index

_pico8_del_scan_loop:
    MOV   R2, R3                  ; scratch: i > length?  (R3 survives)
    IGT   R2, R4
    JT    R2, _pico8_del_not_found

    ;; --- 2. element = table_get(t, i) ---
    MOV   R5, R3
    CIF   R5                      ; R5 = i as float word (table_get key form)
    PUSH  R5
    PUSH  R1                      ; ABI: [BP+3]=table, [BP+2]=key
    CALL  __builtin_table_get
    IADD  SP, 2
    MOV   R7, R0                  ; R7 = element (boxed); get saves R1-R7,
                                  ;      so R1/R3/R4/R5/R6 all intact here

    ;; --- 3. element == v ? (full == semantics, string content included) ---
    PUSH  R6                      ; v  ([BP+2])
    PUSH  R7                      ; element ([BP+3])
    CALL  __builtin_eq            ; R0 = raw 1 (equal) or 0 (not equal)
    IADD  SP, 2
    MOV   R2, R0                  ; raw boolean to scratch
    IEQ   R2, 1                   ; still destructive, still on R2
    JF    R2, _pico8_del_next

    ;; --- 3. element == v ? (bitwise, on scratch) ---
    ;MOV   R2, R7                  ; scratch copy -- R7 survives for the
    ;IEQ   R2, R6                  ;        return value if it matches
    ;JF    R2, _pico8_del_next

    ;; --- 4. Found: table_remove(t, i), propagate its return value ---
    PUSH  R5                      ; position (same float word as above)
    PUSH  R1
    CALL  __builtin_table_remove  ; R0 = removed value
    IADD  SP, 2
    JMP   _pico8_del_done         ; skip callee-restore-local epilogue math

_pico8_del_next:
    IADD  R3, 1
    JMP   _pico8_del_scan_loop

_pico8_del_not_found:
    MOV   R0, BOXED_NIL

_pico8_del_done:
    ;; --- Callee-Restore ---
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
;; __builtin_pico8_camera: PICO-8 camera([x, y])
;;
;; Stack: [BP+2] = x (boxed float or BOXED_NIL), [BP+3] = y (same)
;; Stores the draw offset into PICO8_CAMERA_X / PICO8_CAMERA_Y.
;; NIL (or absent) arguments are treated as 0 -- so camera() with no
;; arguments resets the camera to (0,0), and camera(10) moves x only.
;;
;; The stored value is the SUBTRAHEND: primitives compute
;;   screen = draw_pos - camera
;; so a camera of (-2..2) (celeste's shake) wobbles drawing by +2..-2.
;;
;; Returns BOXED_NIL (PICO-8's previous-offset return value is not
;; provided; celeste ignores the return of every camera() call).
;;
;; R2 is the dedicated destructive-compare scratch throughout.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_camera:
    PUSH  BP
    MOV   BP, SP

    ;; --- x ---
    MOV   R1, [BP+2]
    MOV   R2, R1                  ; scratch copy (destructive test next)
    IEQ   R2, BOXED_NIL
    JF    R2, _pico8_camera_x_set
    MOV   R1, 0                   ; nil -> float 0.0 (all-zero word)
_pico8_camera_x_set:
    MOV   [PICO8_CAMERA_X], R1

    ;; --- y ---
    MOV   R1, [BP+3]
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JF    R2, _pico8_camera_y_set
    MOV   R1, 0
_pico8_camera_y_set:
    MOV   [PICO8_CAMERA_Y], R1

    MOV   R0, BOXED_NIL
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __pico8_draw_swatch (internal helper -- not Lua-callable)
;; In: R1=x R2=y R3=w R4=h (PICO-8 pixels, top-left, w/h >= 1, floats),
;;     R5=color (0-15)
;; Destroys R1-R4. Draws a solid rect via swatch region (256+color)
;; on texture 0, scaled by PICO8_SCALE, centered via PICO8_OFFSET_X/Y.
;;
;; THE CAMERA HOOK: x/y have the camera subtracted here, BEFORE the
;; scale multiply -- same rule as __builtin_pico8_spr. Every filled
;; primitive below routes its coordinates through this one helper, so
;; this is the only place (besides spr/line/print) camera math exists.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__pico8_draw_swatch:
    MOV   R8, R5
    IADD  R8, 256                 ; swatch region = 256 + color
    OUT   GPU_SelectedRegion, R8

    MOV   R8, R3
    FMUL  R8, PICO8_SCALE
    FDIV  R8, 3.0                 ; source cell is 8x8
    OUT   GPU_DrawingScaleX, R8

    MOV   R8, R4
    FMUL  R8, PICO8_SCALE
    FDIV  R8, 3.0
    OUT   GPU_DrawingScaleY, R8

    MOV   R8, [PICO8_CAMERA_X]    ; camera: pre-scale, like spr()
    FSUB  R1, R8
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    CFI   R1
    IADD  R1, PICO8_OFFSET_X
    OUT   GPU_DrawingPointX, R1

    MOV   R8, [PICO8_CAMERA_Y]
    FSUB  R2, R8
    FMUL  R2, PICO8_SCALE
    FADD  R2, 0.5
    CFI   R2
    IADD  R2, PICO8_OFFSET_Y
    OUT   GPU_DrawingPointY, R2

    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_rectfill: rectfill(x0, y0, x1, y1 [, color])
;; Stack: [BP+2]=x0 [BP+3]=y0 [BP+4]=x1 [BP+5]=y1 [BP+6]=color
;; Returns: R0 = color (boxed)
;; Corner order doesn't matter (normalized via FMIN/FMAX). Camera
;; subtracts from both corners -> pure translation, size preserved.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_rectfill:
    PUSH  BP
    MOV   BP, SP
    PUSH  R6
    PUSH  R7
    PUSH  R8
    PUSH  R9

    MOV   R6, [PICO8_CAMERA_X]    ; cam_x, reused for both corners
    MOV   R7, [PICO8_CAMERA_Y]

    ;; left = min(x0,x1) - cam_x ; right = max(x0,x1) - cam_x
    MOV   R1, [BP+2]              ; x0
    MOV   R2, [BP+4]              ; x1
    MOV   R3, R1
    MOV   R4, R2
    FMIN  R1, R2                  ; left
    FMAX  R3, R4                  ; right
    FSUB  R3, R1
    FADD  R3, 1.0                 ; w  (camera cancels in the difference)
    MOV   R8, R3

    MOV   R1, [BP+3]              ; y0
    MOV   R2, [BP+5]              ; y1
    MOV   R3, R1
    MOV   R4, R2
    FMIN  R1, R2                  ; top
    FMAX  R3, R4                  ; bottom
    FSUB  R3, R1
    FADD  R3, 1.0                 ; h

    MOV   R2, R1                  ; swatch ABI: R1=x R2=y R3=w R4=h R5=col
    MOV   R4, R3
    MOV   R3, R8
    MOV   R5, [BP+6]
    CFI   R5
    AND   R5, 15
    CALL  __pico8_draw_swatch     ; camera applied inside, once

    MOV   R0, [BP+6]
    CIF   R0

    POP   R9
    POP   R8
    POP   R7
    POP   R6
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_circfill: circfill(x, y, r, color)
;; Stack: [BP+2]=x [BP+3]=y [BP+4]=r [BP+5]=color
;; Returns: R0 = color (boxed)
;; Midpoint circle via horizontal spans; each span is one swatch call.
;; Camera applies to (x,y) only -- inside __pico8_draw_swatch -- since
;; the radius is a size, not a position.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_circfill:
    PUSH  BP
    MOV   BP, SP
    PUSH  R6                 ; err
    PUSH  R7                 ; py
    PUSH  R8                 ; cx (int)
    PUSH  R9                 ; cy (int)
    PUSH  R10                ; color
    PUSH  R11                ; px (starts at r)

    MOV   R8, [BP+2]
    CFI   R8
    MOV   R9, [BP+3]
    CFI   R9
    MOV   R11, [BP+4]
    CFI   R11
    MOV   R10, [BP+5]
    CFI   R10
    AND   R10, 15

    MOV   R7, 0
    MOV   R6, 0

_pico8_circfill_loop:
    MOV   R1, R11            ; px >= py? (destructive -- copy, R11 survives)
    IGE   R1, R7
    JF    R1, _pico8_circfill_done

    ;; span A: row cy+py, from cx-px to cx+px  (width 2*px+1)
    MOV   R1, R8
    ISUB  R1, R11
    MOV   R2, R9
    IADD  R2, R7
    MOV   R3, R11
    IADD  R3, R11
    IADD  R3, 1
    MOV   R4, 1.0
    MOV   R5, R10
    CALL  __pico8_draw_swatch

    ;; span B: row cy+px, from cx-py to cx+py  (width 2*py+1)
    MOV   R1, R8
    ISUB  R1, R7
    MOV   R2, R9
    IADD  R2, R11
    MOV   R3, R7
    IADD  R3, R7
    IADD  R3, 1
    MOV   R4, 1.0
    MOV   R5, R10
    CALL  __pico8_draw_swatch

    ;; span C: row cy-py, from cx-px to cx+px
    MOV   R1, R8
    ISUB  R1, R11
    MOV   R2, R9
    ISUB  R2, R7
    MOV   R3, R11
    IADD  R3, R11
    IADD  R3, 1
    MOV   R4, 1.0
    MOV   R5, R10
    CALL  __pico8_draw_swatch

    ;; span D: row cy-px, from cx-py to cx+py
    MOV   R1, R8
    ISUB  R1, R7
    MOV   R2, R9
    ISUB  R2, R11
    MOV   R3, R7
    IADD  R3, R7
    IADD  R3, 1
    MOV   R4, 1.0
    MOV   R5, R10
    CALL  __pico8_draw_swatch

    ;; midpoint decision variable
    IADD  R7, 1
    MOV   R1, R7
    IMUL  R1, 2
    IADD  R1, 1
    IADD  R6, R1
    MOV   R1, R6
    ISUB  R1, R11             ; err - px
    ISUB  R1, R11             ; err - px - px
    IGE   R1, 0               ; destructive on the copy only
    JF    R1, _pico8_circfill_loop
    ISUB  R11, 1
    MOV   R1, R11
    IMUL  R1, 2
    IADD  R6, R1
    IADD  R6, 1
    JMP   _pico8_circfill_loop

_pico8_circfill_done:
    MOV   R0, [BP+5]
    CIF   R0

    POP   R11
    POP   R10
    POP   R9
    POP   R8
    POP   R7
    POP   R6
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_line: line(x0, y0, x1, y1, color)
;; Stack: [BP+2]=x0 [BP+3]=y0 [BP+4]=x1 [BP+5]=y1 [BP+6]=color
;; Returns: R0 = color (boxed)
;; One rotozoomed swatch stretch: length = |P1-P0|, angle = atan2(dy,dx).
;; Camera translation cancels in dx/dy, so length/angle are camera-free;
;; only the anchor (x0,y0) is camera-adjusted (pre-scale, like spr()).
;; NOTE: swatch hotspot is (0,0) top-left, so the line pivots at its
;; corner -- a fixed ~0.5 PICO-8 px perpendicular offset. Cosmetic only.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_line:
    PUSH  BP
    MOV   BP, SP
    PUSH  R6
    PUSH  R7
    PUSH  R8
    PUSH  R9
    PUSH  R10
    PUSH  R11

    MOV   R8, [BP+4]
    MOV   R2, [BP+2]
    FSUB  R8, R2              ; dx = x1 - x0
    MOV   R9, [BP+5]
    MOV   R2, [BP+3]
    FSUB  R9, R2              ; dy = y1 - y0

    ;; dx = x1-x0, dy = y1-y0

    MOV   R10, R8
    FMUL  R10, R8
    MOV   R11, R9
    FMUL  R11, R9
    FADD  R10, R11
    MOV   R11, 0.5
    POW   R10, R11            ; R10 = length (PICO-8 px)

    ATAN2 R9, R8              ; R9 = angle (radians), destructive

    MOV   R1, R10
    FMUL  R1, PICO8_SCALE
    FDIV  R1, 3.0             ; stretch swatch along local X by length
    OUT   GPU_DrawingScaleX, R1

    MOV   R1, PICO8_SCALE
    FDIV  R1, 3.0             ; 1 PICO-8 px thick
    OUT   GPU_DrawingScaleY, R1

    OUT   GPU_DrawingAngle, R9

    ;; anchor (x0,y0) -- the ONLY camera-adjusted point
    MOV   R1, [BP+2]
    MOV   R2, [PICO8_CAMERA_X]
    FSUB  R1, R2
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    CFI   R1
    IADD  R1, PICO8_OFFSET_X
    OUT   GPU_DrawingPointX, R1

    MOV   R1, [BP+3]
    MOV   R2, [PICO8_CAMERA_Y]
    FSUB  R1, R2
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    CFI   R1
    IADD  R1, PICO8_OFFSET_Y
    OUT   GPU_DrawingPointY, R1

    MOV   R1, [BP+6]
    CFI   R1
    AND   R1, 15
    IADD  R1, 256
    OUT   GPU_SelectedRegion, R1
    OUT   GPU_Command, GPUCommand_DrawRegionRotozoomed

    MOV   R0, [BP+6]
    CIF   R0

    POP   R11
    POP   R10
    POP   R9
    POP   R8
    POP   R7
    POP   R6
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_print: print(str, x, y [, color])
;; Stack: [BP+2]=str [BP+3]=x [BP+4]=y [BP+5]=color (optional)
;; Returns: R0 = str (boxed), passthrough like PICO-8
;;
;; Converts PICO-8 screen coords -> Vircon32 screen coords (camera,
;; PICO8_SCALE, centering), then delegates to __builtin_print.
;;
;; KNOWN LIMITATIONS (documented, deliberate):
;;   - color is accepted and ignored: __builtin_print renders with the
;;     BIOS font, which has no color parameter. Celeste's colored
;;     prints (scores, titles) will render in the BIOS font color.
;;     Faithful color needs a custom 4x5-pixel PICO-8 font texture
;;     with per-color variants -- same registration pattern as the
;;     pico8 tone bank, left as future work.
;;   - BIOS glyphs are ~8x16 Vircon32 px vs PICO-8's 4x5 (11x14 after
;;     2.75x scale) -- text renders slightly wide/short relative to
;;     sprites. Same custom-font fix covers this.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_print:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2

    ;; x' = (x - cam_x) * SCALE + OFFSET_X   (integer, for __builtin_print)
    MOV   R1, [BP+3]
    MOV   R2, [PICO8_CAMERA_X]
    FSUB  R1, R2
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    CFI   R1
    IADD  R1, PICO8_OFFSET_X
    PUSH  R1                  ; park converted x

    MOV   R1, [BP+4]
    MOV   R2, [PICO8_CAMERA_Y]
    FSUB  R1, R2
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    CFI   R1
    IADD  R1, PICO8_OFFSET_Y
    MOV   R2, R1
    POP   R1                  ; R1 = x', R2 = y'

    ;; __builtin_print ABI: [BP+4]=x, [BP+3]=y, [BP+2]=value
    PUSH  R2                  ; y
    PUSH  R1                  ; x
    MOV   R1, [BP+2]
    PUSH  R1                  ; str
    CALL  __builtin_print
    IADD  SP, 3

    MOV   R0, [BP+2]          ; return the string, passthrough

    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

