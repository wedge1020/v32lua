;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; SECTION: PICO-8 API LAYER
;;
;; Audited + rewritten 2026-09 against the real Vircon32 CPU/GPU semantics
;; (official emulator source, headless test harness). See the per-routine
;; headers for what changed and why.
;;
;; CONVENTIONS used throughout this file:
;;   - Every routine saves every register it touches except R0 (the return
;;     value) -- intrinsic call sites evaluate arguments into registers and
;;     cannot be assumed to have spilled everything live.
;;   - State that must survive a CALL into user Lua code (foreach's callback,
;;     all()'s element reads) lives in [BP-n] frame slots, never registers.
;;   - Integer-vs-float: Lua numbers arrive as float32 words; every
;;     coordinate/index is FLR'd (PICO-8 floors) then CFI'd before integer
;;     use. CFI alone truncates toward zero, which is wrong for negatives.
;;
;; RAM (allocated by the compiler, see emit.c -- NOT heap-allocated, so the
;; map and flags exist before any top-level cart code runs):
;;   PICO8_CAMERA_X/Y   camera offset, floats (subtracted pre-scale)
;;   PICO8_PEN          current draw color, raw int 0-15
;;   PICO8_MAP_RAM      2048 words: 128x64 cells, 4 per word, cell x at
;;                      byte (x % 4) -- same layout as __pico8_map_rom
;;   PICO8_FLAGS_RAM    256 words: sprite flag byte per sprite (fget/fset)
;;   PICO8_FRAME_STEP   (define) 1 with _update60, 2 with _update (30 fps)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

%define PICO8_MAP_WIDTH         128
%define PICO8_MAP_HEIGHT        64
%define PICO8_MAP_WORDS         2048   ; 128*64 cells / 4 cells per word

;; Display scale: 128x128 PICO-8 canvas -> 352x352 on the 640x360 screen.
;; The GPU projection is a plain glOrtho(0,640,360,0): (0,0) is the screen's
;; top-left, so centering is (640-352)/2 = 144 and (360-352)/2 = 4. (This
;; was 464 -- a value "measured" while every sprite region still had its
;; hotspot at texture (0,0), which displaced each region by its own atlas
;; position and made the whole canvas look shifted.)
%define PICO8_SCALE             2.75
%define PICO8_TILE_PX           22.0   ; 8 * PICO8_SCALE
%define PICO8_OFFSET_X          144
%define PICO8_OFFSET_Y          4

;; Swatch bank: 16 solid-color 3x3 cells (1px gaps) on row y=128..130
;; of texture 0 (VTEX is 128x132). Regions 256-271 -- must match
;; PICO8_SWATCH_REGION_BASE in pico8_assets.h.
%define PICO8_SWATCH_REGION_BASE 256
%define PICO8_DEFAULT_PEN        6

;; Real PICO-8 palette, 0xAABBGGRR. Keep in lockstep with pico8_palette[]
;; in pico8_assets.c (which bakes the atlas + swatch colors).
__pico8_palette:
    integer 0xFF000000  ; 0  black #000000
    integer 0xFF532B1D  ; 1  dark-blue #1D2B53
    integer 0xFF53257E  ; 2  dark-purple #7E2553
    integer 0xFF518700  ; 3  dark-green #008751
    integer 0xFF3652AB  ; 4  brown #AB5236
    integer 0xFF4F575F  ; 5  dark-grey #5F574F
    integer 0xFFC7C3C2  ; 6  light-grey #C2C3C7
    integer 0xFFE8F1FF  ; 7  white #FFF1E8
    integer 0xFF4D00FF  ; 8  red #FF004D
    integer 0xFF00A3FF  ; 9  orange #FFA300
    integer 0xFF27ECFF  ; 10 yellow #FFEC27
    integer 0xFF36E400  ; 11 green #00E436
    integer 0xFFFFAD29  ; 12 blue #29ADFF
    integer 0xFF9C7683  ; 13 lavender #83769C
    integer 0xFFA877FF  ; 14 pink #FF77A8
    integer 0xFFAACCFF  ; 15 light-peach #FFCCAA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_pico8_init -- GPU regions + draw state + map/flags RAM
;;
;; Called from __global_scope_initialization BEFORE any top-level cart code
;; (previously it ran after it, so a top-level mset()/mget() touched a map
;; buffer that did not exist yet).
;;
;; Sprite regions 0-255: 16x16 grid of 8x8 cells on texture 0, hotspot at
;; each region's OWN top-left (MinX, MinY). The GPU draws a region at
;; DrawingPoint + (Min - Hotspot) * scale; the old code set every hotspot
;; to texture (0,0), which displaced sprite n by (n%16*8, n/16*8) source
;; pixels -- up to 330 screen px at 2.75x.
;;
;; Map/flags: previously __builtin_pico8_init_map malloc'd a buffer and
;; copied 128*64 = 8192 WORDS from a one-word ROM placeholder (reading
;; straight off the end of the cartridge ROM on small carts -> hardware
;; error at boot; copying runtime code into the map on larger ones), while
;; its zero-fill fallback wrote 65536 words into a 16384-word buffer.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_init:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4

    OUT   GPU_SelectedTexture, 0

    MOV   R1, 0             ; region id
    MOV   R2, 0             ; x in texture
    MOV   R3, 0             ; y in texture

_pico8_init_loop:
    MOV   R0, R1
    IEQ   R0, 256
    JT    R0, _pico8_init_swatches

    OUT   GPU_SelectedRegion, R1
    OUT   GPU_RegionMinX, R2
    OUT   GPU_RegionMinY, R3
    OUT   GPU_RegionHotspotX, R2     ; hotspot = region's own top-left
    OUT   GPU_RegionHotspotY, R3
    MOV   R4, R2
    IADD  R4, 7
    OUT   GPU_RegionMaxX, R4
    MOV   R4, R3
    IADD  R4, 7
    OUT   GPU_RegionMaxY, R4

    IADD  R1, 1
    IADD  R2, 8
    MOV   R0, R2
    IEQ   R0, 128
    JF    R0, _pico8_init_loop
    MOV   R2, 0
    IADD  R3, 8
    JMP   _pico8_init_loop

_pico8_init_swatches:
    MOV   R1, PICO8_SWATCH_REGION_BASE
    MOV   R2, 0

_pico8_init_swatch_loop:
    MOV   R0, R2
    IEQ   R0, 16
    JT    R0, _pico8_init_state

    OUT   GPU_SelectedRegion, R1
    MOV   R3, R2
    IMUL  R3, 4                   ; x = color * 4  (3px cell + 1px gap)
    OUT   GPU_RegionMinX, R3
    MOV   R4, 128
    OUT   GPU_RegionMinY, R4
    OUT   GPU_RegionHotspotX, R3
    OUT   GPU_RegionHotspotY, R4
    MOV   R4, R3
    IADD  R4, 2
    OUT   GPU_RegionMaxX, R4
    MOV   R4, 130
    OUT   GPU_RegionMaxY, R4

    IADD  R1, 1
    IADD  R2, 1
    JMP   _pico8_init_swatch_loop

_pico8_init_state:
    ;; PICO-8 seeds its RNG randomly at boot; Vircon32's RNG always boots
    ;; with seed 1, so every run of a cart would roll identical numbers.
    ;; Seed from the clock (date*86400-ish mix + time), forced non-zero.
    IN    R0, TIM_CurrentDate
    IMUL  R0, 86413
    IN    R1, TIM_CurrentTime
    IADD  R0, R1
    AND   R0, 0x7FFFFFFF
    OR    R0, 1
    OUT   RNG_CurrentValue, R0

    MOV   R0, 0
    MOV   [PICO8_CAMERA_X], R0
    MOV   [PICO8_CAMERA_Y], R0
    MOV   R0, PICO8_DEFAULT_PEN
    MOV   [PICO8_PEN], R0
    MOV   R0, 0xFFFFFFFF
    OUT   GPU_MultiplyColor, R0
    OUT   GPU_ActiveBlending, GPUBlendingMode_Alpha

    CALL  __builtin_pico8_reload

    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __pico8_to_int (internal): R1 = Lua number word -> R1 = flr() as int.
;; nil (or any NaN-boxed word) -> 0, so optional arguments default to 0.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__pico8_to_int:
    PUSH  R2
    MOV   R2, R1
    AND   R2, NAN_VALUE
    IEQ   R2, NAN_VALUE          ; exponent all ones -> boxed value / NaN
    JT    R2, _pico8_to_int_zero
    FLR   R1
    CFI   R1
    POP   R2
    RET
_pico8_to_int_zero:
    MOV   R1, 0
    POP   R2
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __pico8_map_addr (internal): R1 = x, R2 = y (ints) ->
;;   R0 = 1 if in range else 0; when in range: R1 = word address in
;;   PICO8_MAP_RAM, R2 = bit shift of the cell's byte (0/8/16/24).
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__pico8_map_addr:
    MOV   R0, R1
    ILT   R0, 0
    JT    R0, _pico8_map_addr_out
    MOV   R0, R1
    IGE   R0, PICO8_MAP_WIDTH
    JT    R0, _pico8_map_addr_out
    MOV   R0, R2
    ILT   R0, 0
    JT    R0, _pico8_map_addr_out
    MOV   R0, R2
    IGE   R0, PICO8_MAP_HEIGHT
    JT    R0, _pico8_map_addr_out

    IMUL  R2, PICO8_MAP_WIDTH
    IADD  R2, R1                 ; cell index
    MOV   R1, R2
    SHL   R1, -2                 ; word index
    IADD  R1, PICO8_MAP_RAM
    AND   R2, 3
    SHL   R2, 3                  ; byte shift
    MOV   R0, 1
    RET
_pico8_map_addr_out:
    MOV   R0, 0
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_mget(x, y): [BP+2]=x [BP+3]=y -> R0 = tile id (float)
;; Out-of-range cells read as 0, like PICO-8. (Old version: tested the
;; buffer pointer with a destructive IEQ on the pointer register itself,
;; then used the 0/1 result as the buffer base -- reading RAM near address
;; 0 -- and left its result in R5, never R0.)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_mget:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3

    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    MOV   R2, R1                 ; y
    MOV   R1, [BP+2]
    CALL  __pico8_to_int         ; x
    CALL  __pico8_map_addr
    JF    R0, _pico8_mget_zero

    MOV   R3, [R1]
    ISGN  R2
    SHL   R3, R2                 ; logical right shift by byte offset
    AND   R3, 0xFF
    MOV   R0, R3
    CIF   R0
    JMP   _pico8_mget_done

_pico8_mget_zero:
    MOV   R0, 0                  ; 0.0
_pico8_mget_done:
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_mset(x, y, v): [BP+2]=x [BP+3]=y [BP+4]=v -> R0 = nil
;; Stores the low byte of flr(v), like PICO-8. Out-of-range: no-op.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_mset:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5

    MOV   R1, [BP+4]
    CALL  __pico8_to_int
    AND   R1, 0xFF
    MOV   R4, R1                 ; value byte
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    MOV   R2, R1                 ; y
    MOV   R1, [BP+2]
    CALL  __pico8_to_int         ; x
    CALL  __pico8_map_addr
    JF    R0, _pico8_mset_done

    MOV   R3, [R1]               ; current word
    MOV   R5, 0xFF
    SHL   R5, R2
    NOT   R5
    AND   R3, R5                 ; clear the cell's byte
    SHL   R4, R2
    OR    R3, R4
    MOV   [R1], R3

_pico8_mset_done:
    MOV   R0, BOXED_NIL
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
;; __builtin_pico8_map(celx, cely, sx, sy, celw, celh, layer)
;; [BP+2]=celx [BP+3]=cely [BP+4]=sx [BP+5]=sy [BP+6]=celw [BP+7]=celh
;; [BP+8]=layer. Any argument may be nil: defaults 0,0,0,0,128,32,0.
;;
;; Per PICO-8: tile 0 is never drawn; cells outside the map read as 0; a
;; non-zero layer draws only tiles whose sprite flags share a bit with it.
;; (Old version: clamped celx/cely so the whole block fit instead of
;; treating outside cells as empty, drew tile 0, ignored layer, and read
;; the map through the same destroyed-pointer bug as mget.)
;;
;; Loop state lives in frame slots -- __builtin_pico8_spr is called per
;; tile. [BP-1]=row [BP-2]=col [BP-3]=celx [BP-4]=cely [BP-5]=celw
;; [BP-6]=celh [BP-7]=layer
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_map:
    ;; Only the cells that can land on the 128x128 screen are visited, and
    ;; each is drawn inline (one region draw, no spr() call): at 2.75x a map
    ;; cell is exactly 22 screen px, so cell (c, r) sits at X0 + 22c, Y0 + 22r.
    ;; Frame: [BP-1]=row [BP-2]=col [BP-3]=celx [BP-4]=cely [BP-5]=col_end
    ;;        [BP-6]=row_end [BP-7]=layer [BP-8]=X0 [BP-9]=Y0 [BP-10]=col_start
    PUSH  BP
    MOV   BP, SP
    ISUB  SP, 10
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4

    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    MOV   [BP-3], R1
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    MOV   [BP-4], R1

    MOV   R1, [BP+6]             ; celw (nil -> 128)
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JF    R2, _pico8_map_have_w
    MOV   R1, 128.0
_pico8_map_have_w:
    CALL  __pico8_to_int
    MOV   [BP-5], R1

    MOV   R1, [BP+7]             ; celh (nil -> 32)
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JF    R2, _pico8_map_have_h
    MOV   R1, 32.0
_pico8_map_have_h:
    CALL  __pico8_to_int
    MOV   [BP-6], R1

    MOV   R1, [BP+8]
    CALL  __pico8_to_int
    MOV   [BP-7], R1

    ;; --- x: sx - cam_x (float), X0 = round(that * SCALE) + OFFSET_X ---
    MOV   R1, [BP+4]
    CALL  __pico8_to_int
    CIF   R1
    MOV   R2, [PICO8_CAMERA_X]
    FSUB  R1, R2                 ; R1 = screen x of cell column 0 (pico8 px)
    MOV   R2, R1
    FMUL  R2, PICO8_SCALE
    FADD  R2, 0.5
    FLR   R2
    CFI   R2
    IADD  R2, PICO8_OFFSET_X
    MOV   [BP-8], R2
    ;; first visible column: (-8 - x0) / 8 rounded up, clamped to 0
    MOV   R2, -7.0
    FSUB  R2, R1
    FDIV  R2, 8.0
    CEIL  R2
    CFI   R2
    MOV   R3, R2
    ILT   R3, 0
    JF    R3, _pico8_map_cs_ok
    MOV   R2, 0
_pico8_map_cs_ok:
    MOV   [BP-10], R2
    ;; one past the last visible column: (128 - x0) / 8 rounded up
    MOV   R2, 128.0
    FSUB  R2, R1
    FDIV  R2, 8.0
    CEIL  R2
    CFI   R2
    MOV   R3, [BP-5]
    IMIN  R2, R3
    MOV   [BP-5], R2

    ;; --- y: same ---
    MOV   R1, [BP+5]
    CALL  __pico8_to_int
    CIF   R1
    MOV   R2, [PICO8_CAMERA_Y]
    FSUB  R1, R2
    MOV   R2, R1
    FMUL  R2, PICO8_SCALE
    FADD  R2, 0.5
    FLR   R2
    CFI   R2
    IADD  R2, PICO8_OFFSET_Y
    MOV   [BP-9], R2
    MOV   R2, -7.0
    FSUB  R2, R1
    FDIV  R2, 8.0
    CEIL  R2
    CFI   R2
    MOV   R3, R2
    ILT   R3, 0
    JF    R3, _pico8_map_rs_ok
    MOV   R2, 0
_pico8_map_rs_ok:
    MOV   [BP-1], R2             ; row = first visible row
    MOV   R2, 128.0
    FSUB  R2, R1
    FDIV  R2, 8.0
    CEIL  R2
    CFI   R2
    MOV   R3, [BP-6]
    IMIN  R2, R3
    MOV   [BP-6], R2

    OUT   GPU_SelectedTexture, 0
    MOV   R1, PICO8_SCALE
    OUT   GPU_DrawingScaleX, R1
    OUT   GPU_DrawingScaleY, R1

_pico8_map_row:
    MOV   R1, [BP-1]
    MOV   R2, [BP-6]
    ILT   R1, R2
    JF    R1, _pico8_map_done
    ;; screen y of this row
    MOV   R1, [BP-1]
    IMUL  R1, 22
    MOV   R2, [BP-9]
    IADD  R1, R2
    OUT   GPU_DrawingPointY, R1
    MOV   R1, [BP-10]
    MOV   [BP-2], R1             ; col = first visible column

_pico8_map_col:
    MOV   R1, [BP-2]
    MOV   R2, [BP-5]
    ILT   R1, R2
    JF    R1, _pico8_map_next_row

    ;; tile = map[celx+col][cely+row]
    MOV   R1, [BP-3]
    MOV   R2, [BP-2]
    IADD  R1, R2
    MOV   R2, [BP-4]
    MOV   R3, [BP-1]
    IADD  R2, R3
    CALL  __pico8_map_addr
    JF    R0, _pico8_map_next_col
    MOV   R3, [R1]
    ISGN  R2
    SHL   R3, R2
    AND   R3, 0xFF               ; R3 = tile id
    MOV   R0, R3
    IEQ   R0, 0
    JT    R0, _pico8_map_next_col   ; tile 0 is never drawn

    ;; layer filter: (flags[tile] & layer) != 0, when layer != 0
    MOV   R1, [BP-7]
    MOV   R0, R1
    IEQ   R0, 0
    JT    R0, _pico8_map_draw
    MOV   R2, R3
    IADD  R2, PICO8_FLAGS_RAM
    MOV   R2, [R2]
    AND   R2, R1
    IEQ   R2, 0
    JT    R2, _pico8_map_next_col

_pico8_map_draw:
    OUT   GPU_SelectedRegion, R3
    MOV   R1, [BP-2]
    IMUL  R1, 22
    MOV   R2, [BP-8]
    IADD  R1, R2
    OUT   GPU_DrawingPointX, R1
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed

_pico8_map_next_col:
    MOV   R1, [BP-2]
    IADD  R1, 1
    MOV   [BP-2], R1
    JMP   _pico8_map_col

_pico8_map_next_row:
    MOV   R1, [BP-1]
    IADD  R1, 1
    MOV   [BP-1], R1
    JMP   _pico8_map_row

_pico8_map_done:
    MOV   R0, BOXED_NIL
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_pico8_spr(n, x, y, w, h, flip_x, flip_y)
;; [BP+2]=n [BP+3]=x [BP+4]=y [BP+5]=w [BP+6]=h [BP+7]=flip_x [BP+8]=flip_y
;;
;; Draws the w x h block of 8x8 sprites starting at n (row stride 16).
;; Flip flags use Lua truthiness (anything but nil/false), not just the
;; literal `true`.
;;
;; FLIPPING: a negative GPU scale mirrors the region around the drawing
;; point, so a flipped tile spans [pt - 22, pt]. The flipped tile that
;; belongs in destination column c' therefore needs pt = base + (c'+1)*22
;; = base + (w - col)*22. The old code used (w - 1 - col), which drew
;; every flipped sprite one full tile (22 px) left of where it belongs.
;;
;; Frame slots: [BP-1]=n [BP-2]=w [BP-3]=h [BP-4]=base_x [BP-5]=base_y
;;              [BP-6]=flip_x(0/1) [BP-7]=flip_y(0/1) [BP-8]=row [BP-9]=col
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_pico8_spr:
    PUSH  BP
    MOV   BP, SP
    ISUB  SP, 9
    PUSH  R1
    PUSH  R2
    PUSH  R3

    OUT   GPU_SelectedTexture, 0

    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    MOV   [BP-1], R1

    MOV   R1, [BP+5]             ; w (nil -> 1)
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JF    R2, _pico8_spr_have_w
    MOV   R1, 1.0
_pico8_spr_have_w:
    CALL  __pico8_to_int
    MOV   [BP-2], R1

    MOV   R1, [BP+6]             ; h (nil -> 1)
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JF    R2, _pico8_spr_have_h
    MOV   R1, 1.0
_pico8_spr_have_h:
    CALL  __pico8_to_int
    MOV   [BP-3], R1

    ;; base x/y in screen px: round((v - cam) * SCALE) + OFFSET
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    CIF   R1
    MOV   R2, [PICO8_CAMERA_X]
    FSUB  R1, R2
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    FLR   R1
    CFI   R1
    IADD  R1, PICO8_OFFSET_X
    MOV   [BP-4], R1

    MOV   R1, [BP+4]
    CALL  __pico8_to_int
    CIF   R1
    MOV   R2, [PICO8_CAMERA_Y]
    FSUB  R1, R2
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    FLR   R1
    CFI   R1
    IADD  R1, PICO8_OFFSET_Y
    MOV   [BP-5], R1

    ;; flips (truthy test) and matching scale signs
    MOV   R1, [BP+7]
    CALL  __pico8_truthy
    MOV   [BP-6], R0
    MOV   R2, PICO8_SCALE
    JF    R0, _pico8_spr_sx
    FSGN  R2
_pico8_spr_sx:
    OUT   GPU_DrawingScaleX, R2

    MOV   R1, [BP+8]
    CALL  __pico8_truthy
    MOV   [BP-7], R0
    MOV   R2, PICO8_SCALE
    JF    R0, _pico8_spr_sy
    FSGN  R2
_pico8_spr_sy:
    OUT   GPU_DrawingScaleY, R2

    MOV   R1, 0
    MOV   [BP-8], R1             ; row

_pico8_spr_row:
    MOV   R1, [BP-8]
    MOV   R2, [BP-3]
    ILT   R1, R2
    JF    R1, _pico8_spr_done
    MOV   R1, 0
    MOV   [BP-9], R1             ; col

_pico8_spr_col:
    MOV   R1, [BP-9]
    MOV   R2, [BP-2]
    ILT   R1, R2
    JF    R1, _pico8_spr_next_row

    ;; region = n + row*16 + col; skip anything outside 0..255 (256+ are
    ;; the swatch regions, not sprites)
    MOV   R1, [BP-8]
    IMUL  R1, 16
    MOV   R2, [BP-9]
    IADD  R1, R2
    MOV   R2, [BP-1]
    IADD  R1, R2
    MOV   R2, R1
    ILT   R2, 0
    JT    R2, _pico8_spr_next_col
    MOV   R2, R1
    IGT   R2, 255
    JT    R2, _pico8_spr_next_col
    OUT   GPU_SelectedRegion, R1

    ;; x: base + col*22, or base + (w - col)*22 when flipped
    MOV   R1, [BP-9]
    MOV   R2, [BP-6]
    JF    R2, _pico8_spr_x_plain
    MOV   R2, [BP-2]
    ISUB  R2, R1
    MOV   R1, R2
_pico8_spr_x_plain:
    CIF   R1
    FMUL  R1, PICO8_TILE_PX
    FADD  R1, 0.5
    FLR   R1
    CFI   R1
    MOV   R2, [BP-4]
    IADD  R1, R2
    OUT   GPU_DrawingPointX, R1

    MOV   R1, [BP-8]
    MOV   R2, [BP-7]
    JF    R2, _pico8_spr_y_plain
    MOV   R2, [BP-3]
    ISUB  R2, R1
    MOV   R1, R2
_pico8_spr_y_plain:
    CIF   R1
    FMUL  R1, PICO8_TILE_PX
    FADD  R1, 0.5
    FLR   R1
    CFI   R1
    MOV   R2, [BP-5]
    IADD  R1, R2
    OUT   GPU_DrawingPointY, R1

    OUT   GPU_Command, GPUCommand_DrawRegionZoomed

_pico8_spr_next_col:
    MOV   R1, [BP-9]
    IADD  R1, 1
    MOV   [BP-9], R1
    JMP   _pico8_spr_col

_pico8_spr_next_row:
    MOV   R1, [BP-8]
    IADD  R1, 1
    MOV   [BP-8], R1
    JMP   _pico8_spr_row

_pico8_spr_done:
    MOV   R0, BOXED_NIL
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __pico8_truthy (internal): R1 = word -> R0 = 1 unless nil/false
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__pico8_truthy:
    MOV   R0, R1
    IEQ   R0, BOXED_NIL
    JT    R0, _pico8_truthy_no
    MOV   R0, R1
    IEQ   R0, BOXED_FALSE
    JT    R0, _pico8_truthy_no
    MOV   R0, 1
    RET
_pico8_truthy_no:
    MOV   R0, 0
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Buttons. PICO-8 ids: 0 left, 1 right, 2 up, 3 down, 4 O, 5 X.
;; O -> Vircon32 A, X -> Vircon32 B.
;;
;; __pico8_button_frames (internal): R1 = button id (int), gamepad already
;; selected -> R0 = raw port value (>0: frames held, <=0: released), or
;; 0 for an invalid id.
;;
;; (The old btn() mapped 0/1/2/3 to up/down/left/right -- every direction
;; wrong. The old btnp() compared the raw FLOAT id against integers, so
;; only button 0 ever matched, and read its gamepad from the wrong stack
;; slot.)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__pico8_button_frames:
    MOV   R0, R1
    IEQ   R0, 0
    JT    R0, _pico8_bf_left
    MOV   R0, R1
    IEQ   R0, 1
    JT    R0, _pico8_bf_right
    MOV   R0, R1
    IEQ   R0, 2
    JT    R0, _pico8_bf_up
    MOV   R0, R1
    IEQ   R0, 3
    JT    R0, _pico8_bf_down
    MOV   R0, R1
    IEQ   R0, 4
    JT    R0, _pico8_bf_o
    MOV   R0, R1
    IEQ   R0, 5
    JT    R0, _pico8_bf_x
    MOV   R0, 0
    RET
_pico8_bf_left:
    IN    R0, INP_GamepadLeft
    RET
_pico8_bf_right:
    IN    R0, INP_GamepadRight
    RET
_pico8_bf_up:
    IN    R0, INP_GamepadUp
    RET
_pico8_bf_down:
    IN    R0, INP_GamepadDown
    RET
_pico8_bf_o:
    IN    R0, INP_GamepadButtonA
    RET
_pico8_bf_x:
    IN    R0, INP_GamepadButtonB
    RET

;; __pico8_button_test (internal): R1 = id, R2 = mode (0 btn, 1 btnp)
;;   -> R0 = 1/0. btnp: true on the first PICO-8 frame of a press, then
;;   again at PICO-8 frame 15 of the hold and every 4 frames after.
;;   Hardware counts VIRCON32 frames held; one PICO-8 frame is
;;   PICO8_FRAME_STEP of those (2 at 30 fps), so k = ceil(held / step).
;;   Comparing the raw count to 1 would miss any press that started on
;;   the frame _update() skips at 30 fps.
__pico8_button_test:
    PUSH  R3
    CALL  __pico8_button_frames
    MOV   R3, R0                 ; held frames
    MOV   R0, R3
    ILT   R0, 1
    JT    R0, _pico8_bt_false
    MOV   R0, R2
    IEQ   R0, 0
    JT    R0, _pico8_bt_true     ; btn: any positive count

    IADD  R3, PICO8_FRAME_STEP
    ISUB  R3, 1
    IDIV  R3, PICO8_FRAME_STEP   ; k = PICO-8 frames held
    MOV   R0, R3
    IEQ   R0, 1
    JT    R0, _pico8_bt_true
    MOV   R0, R3
    ILT   R0, 15
    JT    R0, _pico8_bt_false
    ISUB  R3, 15
    IMOD  R3, 4
    IEQ   R3, 0
    JT    R3, _pico8_bt_true
_pico8_bt_false:
    MOV   R0, 0
    POP   R3
    RET
_pico8_bt_true:
    MOV   R0, 1
    POP   R3
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_btn(i, p) / __builtin_pico8_btnp(i, p)
;; [BP+2] = i (nil -> bitfield of buttons 0-5), [BP+3] = p (nil -> 0)
;; Returns boolean, or a number (bitfield) when i is nil.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_btn:
    PUSH  BP
    MOV   BP, SP
    PUSH  R2
    MOV   R2, 0
    JMP   __pico8_btn_common

__builtin_pico8_btnp:
    PUSH  BP
    MOV   BP, SP
    PUSH  R2
    MOV   R2, 1

__pico8_btn_common:
    PUSH  R1
    PUSH  R3
    PUSH  R4

    MOV   R1, [BP+3]
    CALL  __pico8_to_int         ; nil -> player 0
    OUT   INP_SelectedGamepad, R1

    MOV   R1, [BP+2]
    MOV   R0, R1
    IEQ   R0, BOXED_NIL
    JT    R0, _pico8_btn_bitfield

    CALL  __pico8_to_int
    CALL  __pico8_button_test
    JF    R0, _pico8_btn_false
    MOV   R0, BOXED_TRUE
    JMP   _pico8_btn_done
_pico8_btn_false:
    MOV   R0, BOXED_FALSE
    JMP   _pico8_btn_done

_pico8_btn_bitfield:
    MOV   R3, 0                  ; result bits
    MOV   R4, 5                  ; button id, counting down
_pico8_btn_bits_loop:
    MOV   R1, R4
    CALL  __pico8_button_test
    SHL   R3, 1
    OR    R3, R0
    ISUB  R4, 1
    MOV   R0, R4
    IGE   R0, 0
    JT    R0, _pico8_btn_bits_loop
    MOV   R0, R3
    CIF   R0

_pico8_btn_done:
    POP   R4
    POP   R3
    POP   R1
    POP   R2
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_pico8_all_step(t, i, prev) -- one step of PICO-8's all()
;; [BP+2] = t, [BP+3] = i (RAW int, 1-based), [BP+4] = prev (boxed)
;; Returns R0 = next element (nil when done), R2 = new i (raw int).
;;
;; PICO-8's own definition, which is what makes deleting the CURRENT
;; element inside the loop safe (the element after it slides into slot i,
;; so i must not advance):
;;     if c[i] == prev then i += 1 end
;;     while c[i] == nil and i <= #c do i += 1 end
;;     prev = c[i]; return prev
;; The prev comparison is identity (bitwise) -- same as Lua == for the
;; tables PICO-8 carts put in object lists.
;;
;; Shared by foreach() and by the compiler's `for v in all(t)` lowering
;; (see node_for_generic), neither of which allocates anything per loop.
;; Frame slots: [BP-1] = #t, [BP-2] = i
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_all_step:
    ;; [BP+2] = t, [BP+3] = i (raw int), [BP+4] = prev.
    ;; Returns R0 = element (nil when done), R2 = its index.
    ;; Elements in the array part are read directly (R5 = capacity,
    ;; R6 = data); anything else goes through __table_rawget_int.
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R3
    PUSH  R4
    PUSH  R5
    PUSH  R6

    MOV   R1, [BP+2]
    MOV   R4, R1
    AND   R4, BOXED_DATA
    IEQ   R4, BOXED_TABLE
    JF    R4, __runtime_error_not_table
    AND   R1, BOXED_PAYLOAD      ; raw header
    MOV   R4, [R1+1]             ; n = #t
    MOV   R5, [R1]
    AND   R5, TABLE_ARRAYSIZE    ; array capacity
    MOV   R6, [R1+2]
    ISUB  R6, 1                  ; data - 1: t[i] at [R6 + i]
    MOV   R3, [BP+3]             ; i

    ;; if t[i] == prev then i += 1 (the current element survived)
    MOV   R0, R3
    ILT   R0, 1
    JT    R0, _pico8_all_cur_slow
    MOV   R0, R3
    IGT   R0, R5
    JT    R0, _pico8_all_cur_slow
    MOV   R0, R6
    IADD  R0, R3
    MOV   R0, [R0]
    JMP   _pico8_all_cur
_pico8_all_cur_slow:
    CALL  __table_rawget_int
_pico8_all_cur:
    MOV   R2, [BP+4]
    IEQ   R0, R2
    JF    R0, _pico8_all_skip
    IADD  R3, 1

_pico8_all_skip:
    ;; while i <= n and t[i] == nil do i += 1
    MOV   R2, R3
    IGT   R2, R4
    JT    R2, _pico8_all_end
    MOV   R0, R3
    ILT   R0, 1
    JT    R0, _pico8_all_next_slow
    MOV   R0, R3
    IGT   R0, R5
    JT    R0, _pico8_all_next_slow
    MOV   R0, R6
    IADD  R0, R3
    MOV   R0, [R0]
    JMP   _pico8_all_next
_pico8_all_next_slow:
    CALL  __table_rawget_int
_pico8_all_next:
    MOV   R2, R0
    IEQ   R2, BOXED_NIL
    JF    R2, _pico8_all_found
    IADD  R3, 1
    JMP   _pico8_all_skip

_pico8_all_end:
    MOV   R0, BOXED_NIL
_pico8_all_found:
    MOV   R2, R3
    POP   R6
    POP   R5
    POP   R4
    POP   R3
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_foreach(t, f): [BP+3] = t, [BP+2] = f
;; Calls f(v) for each element exactly as `for v in all(t) do f(v) end`,
;; so a callback may del() the element it was handed (celeste does this
;; constantly: objects destroy themselves from inside foreach). The old
;; version captured #t once and walked 1..n, so every deletion skipped the
;; next object and then handed the callback nil at the end.
;; Frame slots: [BP-1] = i (raw), [BP-2] = prev
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_foreach:
    PUSH  BP
    MOV   BP, SP
    ISUB  SP, 2
    PUSH  R1
    PUSH  R2

    MOV   R1, [BP+3]
    MOV   R2, R1
    AND   R2, BOXED_DATA
    IEQ   R2, BOXED_TABLE
    JF    R2, __runtime_error_not_table

    MOV   R1, 1
    MOV   [BP-1], R1
    MOV   R1, BOXED_NIL
    MOV   [BP-2], R1

_pico8_foreach_loop:
    MOV   R1, [BP-2]
    PUSH  R1                     ; prev -> [BP+4]
    MOV   R1, [BP-1]
    PUSH  R1                     ; i    -> [BP+3]
    MOV   R1, [BP+3]
    PUSH  R1                     ; t    -> [BP+2]
    CALL  __builtin_pico8_all_step
    IADD  SP, 3
    MOV   R1, R0
    IEQ   R1, BOXED_NIL
    JT    R1, _pico8_foreach_done
    MOV   [BP-1], R2
    MOV   [BP-2], R0

    PUSH  R0                     ; f(v)
    MOV   R0, [BP+2]
    CALL  __builtin_exec
    IADD  SP, 1
    JMP   _pico8_foreach_loop

_pico8_foreach_done:
    MOV   R0, BOXED_NIL
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_pico8_count(t): [BP+2] = t -> R0 = #t (PICO-8 0.2+:
;; count(tbl) is the table's length), read from the table header.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_count:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    PUSH  R6
    PUSH  R7

    MOV   R1, [BP+2]
    MOV   R2, R1
    AND   R2, BOXED_DATA
    IEQ   R2, BOXED_TABLE
    JF    R2, __runtime_error_not_table
    AND   R1, BOXED_PAYLOAD       ; raw table header

    ;; PICO-8 0.2+: count(t) is #t. The table keeps that length (the
    ;; border) in its header, so this is O(1); it used to walk every slot,
    ;; and celeste calls count(objects) once per collision check.
    MOV   R7, [R1+1]
    JMP   _pico8_count_done

_pico8_count_done:
    MOV   R0, R7
    CIF   R0
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
;; __builtin_pico8_del(t, v): [BP+3] = t, [BP+2] = v
;; Removes the first element of t's sequence (1..#t) equal to v (full ==
;; semantics via __builtin_eq, so string contents compare), shifting the
;; rest down. Returns the removed value, or nil.
;;
;; The old version pushed both sub-calls' arguments in the wrong order --
;; __builtin_table_get / __builtin_table_remove take the TABLE at [BP+3]
;; and the key at [BP+2] -- so every del() trapped "not a table". It also
;; bounded its scan by the header's array-part length rather than #t.
;; Frame slots: [BP-1] = i (raw), [BP-2] = n
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_del:
    PUSH  BP
    MOV   BP, SP
    ISUB  SP, 2
    PUSH  R1
    PUSH  R2

    MOV   R1, [BP+3]
    MOV   R2, R1
    AND   R2, BOXED_DATA
    IEQ   R2, BOXED_TABLE
    JF    R2, __runtime_error_not_table

    PUSH  R1
    CALL  __builtin_len
    IADD  SP, 1
    CFI   R0
    MOV   [BP-2], R0
    MOV   R1, 1
    MOV   [BP-1], R1

_pico8_del_scan:
    MOV   R1, [BP-1]
    MOV   R2, [BP-2]
    IGT   R1, R2
    JT    R1, _pico8_del_not_found

    MOV   R1, [BP+3]
    PUSH  R1                      ; [BP+3] = table
    MOV   R1, [BP-1]
    CIF   R1
    PUSH  R1                      ; [BP+2] = key
    CALL  __builtin_table_get
    IADD  SP, 2

    PUSH  R0                      ; left  -> [BP+3]
    MOV   R1, [BP+2]
    PUSH  R1                      ; right -> [BP+2]
    CALL  __builtin_eq            ; BOXED_TRUE / BOXED_FALSE (NOT raw 1/0)
    IADD  SP, 2
    IEQ   R0, BOXED_TRUE
    JT    R0, _pico8_del_found

    MOV   R1, [BP-1]
    IADD  R1, 1
    MOV   [BP-1], R1
    JMP   _pico8_del_scan

_pico8_del_found:
    MOV   R1, [BP+3]
    PUSH  R1                      ; [BP+3] = table
    MOV   R1, [BP-1]
    CIF   R1
    PUSH  R1                      ; [BP+2] = position
    CALL  __builtin_table_remove  ; R0 = removed value
    IADD  SP, 2
    JMP   _pico8_del_done

_pico8_del_not_found:
    MOV   R0, BOXED_NIL
_pico8_del_done:
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_camera([x, y]): [BP+2] = x, [BP+3] = y (nil -> 0)
;; Stores the draw offset (the SUBTRAHEND: screen = pos - camera). PICO-8
;; floors camera coordinates; so does this.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_camera:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1

    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    CIF   R1
    MOV   [PICO8_CAMERA_X], R1
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    CIF   R1
    MOV   [PICO8_CAMERA_Y], R1

    MOV   R0, BOXED_NIL
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __pico8_pen (internal): R1 = color argument word ->
;;   R1 = color index 0-15. nil -> current pen; otherwise flr(c) & 15, which
;;   also BECOMES the current pen (PICO-8: a color argument sets the pen).
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__pico8_pen:
    PUSH  R0
    MOV   R0, R1
    IEQ   R0, BOXED_NIL
    JT    R0, _pico8_pen_current
    CALL  __pico8_to_int
    AND   R1, 15
    MOV   [PICO8_PEN], R1
    POP   R0
    RET
_pico8_pen_current:
    MOV   R1, [PICO8_PEN]
    POP   R0
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __pico8_fill (internal): solid rectangle in PICO-8 pixel space
;; In: R1 = x, R2 = y, R3 = w, R4 = h (INTEGER PICO-8 px, w/h >= 1),
;;     R5 = color (0-15). Camera, scale and centering applied here.
;; Preserves everything but R0.
;;
;; Stretches the 3x3 swatch region (256 + color) to w x h. Integer inputs
;; on purpose: the old float-input helper was fed raw integers by
;; circfill(), so every circle span was drawn at scale ~0 at the origin.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__pico8_fill:
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4

    OUT   GPU_SelectedTexture, 0
    MOV   R0, R5
    IADD  R0, PICO8_SWATCH_REGION_BASE
    OUT   GPU_SelectedRegion, R0

    CIF   R3
    FMUL  R3, PICO8_SCALE
    FDIV  R3, 3.0                 ; swatch cell is 3x3 px
    OUT   GPU_DrawingScaleX, R3
    CIF   R4
    FMUL  R4, PICO8_SCALE
    FDIV  R4, 3.0
    OUT   GPU_DrawingScaleY, R4

    CIF   R1
    MOV   R0, [PICO8_CAMERA_X]
    FSUB  R1, R0
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    FLR   R1
    CFI   R1
    IADD  R1, PICO8_OFFSET_X
    OUT   GPU_DrawingPointX, R1

    CIF   R2
    MOV   R0, [PICO8_CAMERA_Y]
    FSUB  R2, R0
    FMUL  R2, PICO8_SCALE
    FADD  R2, 0.5
    FLR   R2
    CFI   R2
    IADD  R2, PICO8_OFFSET_Y
    OUT   GPU_DrawingPointY, R2

    OUT   GPU_Command, GPUCommand_DrawRegionZoomed

    POP   R4
    POP   R3
    POP   R2
    POP   R1
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __pico8_rect_args (internal): reads corners [BP+2..5] + color [BP+6] of
;; the CALLER's frame -> R1 = left, R2 = top, R3 = w, R4 = h (ints), R5 = col
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__pico8_rect_args:
    MOV   R1, [BP+6]
    CALL  __pico8_pen
    MOV   R5, R1
    MOV   R1, [BP+4]
    CALL  __pico8_to_int
    MOV   R3, R1                  ; x1
    MOV   R1, [BP+5]
    CALL  __pico8_to_int
    MOV   R4, R1                  ; y1
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    MOV   R2, R1                  ; y0
    MOV   R1, [BP+2]
    CALL  __pico8_to_int          ; x0
    MOV   R0, R1
    IMIN  R1, R3                  ; left
    IMAX  R3, R0                  ; right
    ISUB  R3, R1
    IADD  R3, 1                   ; w
    MOV   R0, R2
    IMIN  R2, R4                  ; top
    IMAX  R4, R0                  ; bottom
    ISUB  R4, R2
    IADD  R4, 1                   ; h
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; rectfill(x0, y0, x1, y1 [, col]) / rect(...) -- corners in any order
;; [BP+2]=x0 [BP+3]=y0 [BP+4]=x1 [BP+5]=y1 [BP+6]=col. Return nil.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_rectfill:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    CALL  __pico8_rect_args
    CALL  __pico8_fill
    MOV   R0, BOXED_NIL
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

__builtin_pico8_rect:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    PUSH  R6
    PUSH  R7
    CALL  __pico8_rect_args
    MOV   R6, R3                  ; w
    MOV   R7, R4                  ; h

    ;; (__pico8_fill clobbers R0 -- never keep a value in R0 across it)
    MOV   R4, 1
    CALL  __pico8_fill            ; top edge    (x, y, w, 1)
    PUSH  R2
    IADD  R2, R7
    ISUB  R2, 1
    CALL  __pico8_fill            ; bottom edge (x, y+h-1, w, 1)
    POP   R2
    MOV   R3, 1
    MOV   R4, R7
    CALL  __pico8_fill            ; left edge   (x, y, 1, h)
    IADD  R1, R6
    ISUB  R1, 1
    CALL  __pico8_fill            ; right edge  (x+w-1, y, 1, h)

    MOV   R0, BOXED_NIL
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
;; pset(x, y [, col]): [BP+2]=x [BP+3]=y [BP+4]=col
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_pset:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    MOV   R1, [BP+4]
    CALL  __pico8_pen
    MOV   R5, R1
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    MOV   R2, R1
    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    MOV   R3, 1
    MOV   R4, 1
    CALL  __pico8_fill
    MOV   R0, BOXED_NIL
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; circfill(x, y, r [, col]) / circ(x, y, r [, col])
;; [BP+2]=x [BP+3]=y [BP+4]=r [BP+5]=col
;; Midpoint circle. circfill draws 4 horizontal spans per step; circ plots
;; the 8 symmetric points. R6 = err, R7 = py, R8 = cx, R9 = cy, R10 = px.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_circfill:
    PUSH  BP
    MOV   BP, SP
    PUSH  R11
    MOV   R11, 1                  ; mode: filled
    JMP   __pico8_circ_common

__builtin_pico8_circ:
    PUSH  BP
    MOV   BP, SP
    PUSH  R11
    MOV   R11, 0                  ; mode: outline

__pico8_circ_common:
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

    MOV   R1, [BP+5]
    CALL  __pico8_pen
    MOV   R5, R1
    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    MOV   R8, R1
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    MOV   R9, R1
    MOV   R1, [BP+4]
    MOV   R0, R1
    IEQ   R0, BOXED_NIL
    JF    R0, _pico8_circ_have_r
    MOV   R1, 4.0                 ; PICO-8 default radius
_pico8_circ_have_r:
    CALL  __pico8_to_int
    MOV   R10, R1
    MOV   R0, R10
    ILT   R0, 0
    JT    R0, _pico8_circ_done

    MOV   R7, 0
    MOV   R6, 0

_pico8_circ_loop:
    MOV   R0, R10
    IGE   R0, R7
    JF    R0, _pico8_circ_done

    JF    R11, _pico8_circ_points

    ;; filled: spans at rows cy+-py (width 2px+1) and cy+-px (width 2py+1)
    MOV   R4, 1
    MOV   R1, R8
    ISUB  R1, R10
    MOV   R3, R10
    IADD  R3, R10
    IADD  R3, 1
    MOV   R2, R9
    IADD  R2, R7
    CALL  __pico8_fill
    MOV   R2, R9
    ISUB  R2, R7
    CALL  __pico8_fill
    MOV   R1, R8
    ISUB  R1, R7
    MOV   R3, R7
    IADD  R3, R7
    IADD  R3, 1
    MOV   R2, R9
    IADD  R2, R10
    CALL  __pico8_fill
    MOV   R2, R9
    ISUB  R2, R10
    CALL  __pico8_fill
    JMP   _pico8_circ_step

_pico8_circ_points:
    MOV   R3, 1
    MOV   R4, 1
    ;; (cx+-px, cy+-py)
    MOV   R1, R8
    IADD  R1, R10
    MOV   R2, R9
    IADD  R2, R7
    CALL  __pico8_fill
    MOV   R2, R9
    ISUB  R2, R7
    CALL  __pico8_fill
    MOV   R1, R8
    ISUB  R1, R10
    CALL  __pico8_fill
    MOV   R2, R9
    IADD  R2, R7
    CALL  __pico8_fill
    ;; (cx+-py, cy+-px)
    MOV   R1, R8
    IADD  R1, R7
    MOV   R2, R9
    IADD  R2, R10
    CALL  __pico8_fill
    MOV   R2, R9
    ISUB  R2, R10
    CALL  __pico8_fill
    MOV   R1, R8
    ISUB  R1, R7
    CALL  __pico8_fill
    MOV   R2, R9
    IADD  R2, R10
    CALL  __pico8_fill

_pico8_circ_step:
    IADD  R7, 1
    MOV   R0, R7
    IMUL  R0, 2
    IADD  R0, 1
    IADD  R6, R0
    MOV   R0, R6
    ISUB  R0, R10
    ISUB  R0, R10
    IGE   R0, 0
    JF    R0, _pico8_circ_loop
    ISUB  R10, 1
    MOV   R0, R10
    IMUL  R0, 2
    ISUB  R6, R0
    IADD  R6, 1
    JMP   _pico8_circ_loop

_pico8_circ_done:
    MOV   R0, BOXED_NIL
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
    POP   R11
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; line(x0, y0, x1, y1 [, col]): [BP+2..5] corners, [BP+6] col
;; One rotozoomed swatch: length |P1-P0| + 1 px (PICO-8 lines include both
;; endpoints, so a zero-length line is a single pixel -- the old version
;; drew nothing for it), angle atan2(dy, dx), anchored at (x0, y0).
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_line:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4

    OUT   GPU_SelectedTexture, 0
    MOV   R1, [BP+6]
    CALL  __pico8_pen
    IADD  R1, PICO8_SWATCH_REGION_BASE
    OUT   GPU_SelectedRegion, R1

    MOV   R1, [BP+4]
    CALL  __pico8_to_int
    MOV   R3, R1
    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    ISUB  R3, R1
    CIF   R3                      ; dx
    MOV   R1, [BP+5]
    CALL  __pico8_to_int
    MOV   R4, R1
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    ISUB  R4, R1
    CIF   R4                      ; dy

    MOV   R1, R3
    FMUL  R1, R3
    MOV   R2, R4
    FMUL  R2, R4
    FADD  R1, R2
    MOV   R2, 0.5
    POW   R1, R2
    FADD  R1, 1.0                 ; length incl. both endpoints
    FMUL  R1, PICO8_SCALE
    FDIV  R1, 3.0
    OUT   GPU_DrawingScaleX, R1
    MOV   R1, PICO8_SCALE
    FDIV  R1, 3.0                 ; 1 PICO-8 px thick
    OUT   GPU_DrawingScaleY, R1

    ATAN2 R4, R3                  ; angle = atan2(dy, dx)
    OUT   GPU_DrawingAngle, R4

    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    CIF   R1
    MOV   R2, [PICO8_CAMERA_X]
    FSUB  R1, R2
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    FLR   R1
    CFI   R1
    IADD  R1, PICO8_OFFSET_X
    OUT   GPU_DrawingPointX, R1

    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    CIF   R1
    MOV   R2, [PICO8_CAMERA_Y]
    FSUB  R1, R2
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    FLR   R1
    CFI   R1
    IADD  R1, PICO8_OFFSET_Y
    OUT   GPU_DrawingPointY, R1

    OUT   GPU_Command, GPUCommand_DrawRegionRotozoomed

    MOV   R0, BOXED_NIL
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; cls([col]): [BP+2] = col (nil -> 0). Palette index, flr'd, & 15.
;; (The old version also took "a raw 32-bit color" for values >= 16, but
;; CFI of such a word is undefined, so that path never worked.)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_cls:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1

    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    AND   R1, 15
    MOV   R0, __pico8_palette
    IADD  R1, R0
    MOV   R1, [R1]
    OUT   GPU_ClearColor, R1
    OUT   GPU_Command, GPUCommand_ClearScreen

    MOV   R0, BOXED_NIL
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; color([col]): sets the pen (nil -> 6). Returns nil.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_color:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    MOV   R1, [BP+2]
    MOV   R0, R1
    IEQ   R0, BOXED_NIL
    JF    R0, _pico8_color_set
    MOV   R1, 6.0
_pico8_color_set:
    CALL  __pico8_pen
    MOV   R0, BOXED_NIL
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; fget(n [, f]): [BP+2] = n, [BP+3] = f
;;   f nil -> flag byte as a number; else -> boolean (bit f set).
;; fset(n, [f,] v): [BP+2] = n, [BP+3] = f or v, [BP+4] = v or nil
;;   2-arg form sets the whole byte; 3-arg form sets bit f to truthy(v).
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_fget:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2

    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    AND   R1, 255
    IADD  R1, PICO8_FLAGS_RAM
    MOV   R2, [R1]                ; flag byte

    MOV   R1, [BP+3]
    MOV   R0, R1
    IEQ   R0, BOXED_NIL
    JF    R0, _pico8_fget_bit
    MOV   R0, R2
    CIF   R0
    JMP   _pico8_fget_done

_pico8_fget_bit:
    CALL  __pico8_to_int
    AND   R1, 7
    ISGN  R1
    SHL   R2, R1                  ; >> f
    AND   R2, 1
    MOV   R0, BOXED_FALSE
    JF    R2, _pico8_fget_done
    MOV   R0, BOXED_TRUE
_pico8_fget_done:
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

__builtin_pico8_fset:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4

    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    AND   R1, 255
    IADD  R1, PICO8_FLAGS_RAM
    MOV   R4, R1                  ; flag word address

    MOV   R1, [BP+4]
    MOV   R0, R1
    IEQ   R0, BOXED_NIL
    JF    R0, _pico8_fset_bit

    ;; fset(n, v): whole byte
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    AND   R1, 255
    MOV   [R4], R1
    JMP   _pico8_fset_done

_pico8_fset_bit:
    CALL  __pico8_truthy          ; R0 = truthy(v)
    MOV   R3, R0
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    AND   R1, 7
    MOV   R2, 1
    SHL   R2, R1                  ; bit mask
    MOV   R1, [R4]
    JF    R3, _pico8_fset_clear
    OR    R1, R2
    JMP   _pico8_fset_store
_pico8_fset_clear:
    NOT   R2
    AND   R1, R2
_pico8_fset_store:
    MOV   [R4], R1

_pico8_fset_done:
    MOV   R0, BOXED_NIL
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; print(str [, x, y [, col]]): [BP+2]=str [BP+3]=x [BP+4]=y [BP+5]=col
;; Converts PICO-8 coordinates (camera, scale, centering) and delegates to
;; __builtin_print. The BIOS font is white, so the color is applied as a
;; GPU multiply color and restored afterwards (it used to be ignored).
;; Glyphs are the BIOS font's, not PICO-8's 3x5 font.
;; Returns nil.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_print:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3

    MOV   R1, [BP+5]
    CALL  __pico8_pen
    MOV   R0, __pico8_palette
    IADD  R1, R0
    MOV   R1, [R1]
    OUT   GPU_MultiplyColor, R1

    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    CIF   R1
    MOV   R2, [PICO8_CAMERA_X]
    FSUB  R1, R2
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    FLR   R1
    CFI   R1
    IADD  R1, PICO8_OFFSET_X
    MOV   R3, R1

    MOV   R1, [BP+4]
    CALL  __pico8_to_int
    CIF   R1
    MOV   R2, [PICO8_CAMERA_Y]
    FSUB  R1, R2
    FMUL  R1, PICO8_SCALE
    FADD  R1, 0.5
    FLR   R1
    CFI   R1
    IADD  R1, PICO8_OFFSET_Y

    ;; __builtin_print ABI: [BP+4] = x, [BP+3] = y, [BP+2] = value
    PUSH  R3
    PUSH  R1
    MOV   R1, [BP+2]
    PUSH  R1
    CALL  __builtin_print
    IADD  SP, 3

    MOV   R1, 0xFFFFFFFF
    OUT   GPU_MultiplyColor, R1
    MOV   R0, BOXED_NIL
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_present -- called after every _draw()
;; PICO-8 clips all drawing to its 128x128 screen; the Vircon32 GPU has no
;; clip rectangle, so anything drawn off-canvas (celeste's clouds and
;; particles routinely are) showed up in the margins around the centered
;; 352x352 canvas. Mask the margins with the (always opaque) black swatch.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_present:
    PUSH  R1
    OUT   GPU_SelectedTexture, 0
    MOV   R1, PICO8_SWATCH_REGION_BASE
    OUT   GPU_SelectedRegion, R1          ; color 0 swatch (3x3)

    ;; left + right bars: 144 x 360
    MOV   R1, 48.0                        ; 144 / 3
    OUT   GPU_DrawingScaleX, R1
    MOV   R1, 120.0                       ; 360 / 3
    OUT   GPU_DrawingScaleY, R1
    OUT   GPU_DrawingPointY, 0
    OUT   GPU_DrawingPointX, 0
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    OUT   GPU_DrawingPointX, 496          ; 144 + 352
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed

    ;; top + bottom bars: 352 x 4 over the canvas columns
    MOV   R1, 117.33333                   ; 352 / 3
    OUT   GPU_DrawingScaleX, R1
    MOV   R1, 1.3333334                   ; 4 / 3
    OUT   GPU_DrawingScaleY, R1
    OUT   GPU_DrawingPointX, 144
    OUT   GPU_DrawingPointY, 0
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    OUT   GPU_DrawingPointY, 356          ; 4 + 352
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    POP   R1
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_music(n): music() with a computed pattern number.
;; [BP+2] = n. Looks n up in __pico8_music_table (4 words per pattern:
;; sound id or -1, loop start, loop end, loop flag -- emitted by the
;; compiler from the cart's __music__ data) and plays that song on SPU
;; channel 0; n < 0, n > 63 or a pattern that starts no song stops it.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_music:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    MOV   R2, R1
    ILT   R2, 0
    JT    R2, _pico8_music_stop
    MOV   R2, R1
    IGT   R2, 63
    JT    R2, _pico8_music_stop
    MOV   R2, R1
    SHL   R2, 2
    MOV   R3, __pico8_music_table
    IADD  R2, R3
    MOV   R3, [R2]
    MOV   R4, R3
    ILT   R4, 0
    JT    R4, _pico8_music_stop
    OUT   SPU_SelectedSound, R3
    MOV   R4, [R2+1]
    OUT   SPU_SoundLoopStart, R4
    MOV   R4, [R2+2]
    OUT   SPU_SoundLoopEnd, R4
    OUT   SPU_SelectedChannel, 0
    OUT   SPU_Command, SPUCommand_StopSelectedChannel
    OUT   SPU_ChannelAssignedSound, R3
    OUT   SPU_ChannelVolume, 1.0
    OUT   SPU_ChannelSpeed, 1.0
    OUT   SPU_Command, SPUCommand_PlaySelectedChannel
    MOV   R4, [R2+3]
    OUT   SPU_ChannelLoopEnabled, R4
    MOV   R4, [VIRCON32_MUSIC_CHANNEL_MASK]
    OR    R4, 1
    MOV   [VIRCON32_MUSIC_CHANNEL_MASK], R4
    MOV   R4, [VIRCON32_SFX_CHANNEL_MASK]
    AND   R4, 0xFFFFFFFE
    MOV   [VIRCON32_SFX_CHANNEL_MASK], R4
    JMP   _pico8_music_done
_pico8_music_stop:
    OUT   SPU_SelectedChannel, 0
    OUT   SPU_Command, SPUCommand_StopSelectedChannel
_pico8_music_done:
    MOV   R0, BOXED_NIL
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_sspr(sx, sy, sw, sh, dx, dy [, dw, dh [, flip_x, flip_y]])
;; [BP+2..11]. Draws a rectangle of the sprite sheet, stretched to dw x dh
;; (default sw x sh), through a scratch GPU region (PICO8_SSPR_REGION)
;; that is redefined on every call.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
%define PICO8_SSPR_REGION 4095
__builtin_pico8_sspr:
    PUSH  BP
    MOV   BP, SP
    ISUB  SP, 6
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4

    OUT   GPU_SelectedTexture, 0
    OUT   GPU_SelectedRegion, PICO8_SSPR_REGION

    MOV   R1, [BP+4]              ; sw
    CALL  __pico8_to_int
    MOV   [BP-1], R1
    MOV   R2, R1
    ILE   R2, 0
    JT    R2, _pico8_sspr_done
    MOV   R1, [BP+5]              ; sh
    CALL  __pico8_to_int
    MOV   [BP-2], R1
    MOV   R2, R1
    ILE   R2, 0
    JT    R2, _pico8_sspr_done

    MOV   R1, [BP+2]              ; sx
    CALL  __pico8_to_int
    OUT   GPU_RegionMinX, R1
    OUT   GPU_RegionHotspotX, R1
    MOV   R2, [BP-1]
    IADD  R1, R2
    ISUB  R1, 1
    OUT   GPU_RegionMaxX, R1
    MOV   R1, [BP+3]              ; sy
    CALL  __pico8_to_int
    OUT   GPU_RegionMinY, R1
    OUT   GPU_RegionHotspotY, R1
    MOV   R2, [BP-2]
    IADD  R1, R2
    ISUB  R1, 1
    OUT   GPU_RegionMaxY, R1

    ;; dw/dh (nil -> sw/sh), as floats in [BP-3]/[BP-4]
    MOV   R1, [BP+8]
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JF    R2, _pico8_sspr_have_dw
    MOV   R1, [BP-1]
    CIF   R1
_pico8_sspr_have_dw:
    MOV   [BP-3], R1
    MOV   R1, [BP+9]
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JF    R2, _pico8_sspr_have_dh
    MOV   R1, [BP-2]
    CIF   R1
_pico8_sspr_have_dh:
    MOV   [BP-4], R1

    ;; x: scale = dw/sw * SCALE; flipped -> negative, drawn from dx + dw
    MOV   R1, [BP+6]
    CALL  __pico8_to_int
    CIF   R1
    MOV   [BP-5], R1              ; dx (float)
    MOV   R2, [BP-3]
    MOV   R3, [BP-1]
    CIF   R3
    FDIV  R2, R3
    FMUL  R2, PICO8_SCALE
    MOV   R3, R1
    MOV   R1, [BP+10]
    CALL  __pico8_truthy
    JF    R0, _pico8_sspr_xs
    FSGN  R2
    MOV   R4, [BP-3]
    FADD  R3, R4
_pico8_sspr_xs:
    OUT   GPU_DrawingScaleX, R2
    MOV   R4, [PICO8_CAMERA_X]
    FSUB  R3, R4
    FMUL  R3, PICO8_SCALE
    FADD  R3, 0.5
    FLR   R3
    CFI   R3
    IADD  R3, PICO8_OFFSET_X
    OUT   GPU_DrawingPointX, R3

    MOV   R1, [BP+7]
    CALL  __pico8_to_int
    CIF   R1
    MOV   R2, [BP-4]
    MOV   R3, [BP-2]
    CIF   R3
    FDIV  R2, R3
    FMUL  R2, PICO8_SCALE
    MOV   R3, R1
    MOV   R1, [BP+11]
    CALL  __pico8_truthy
    JF    R0, _pico8_sspr_ys
    FSGN  R2
    MOV   R4, [BP-4]
    FADD  R3, R4
_pico8_sspr_ys:
    OUT   GPU_DrawingScaleY, R2
    MOV   R4, [PICO8_CAMERA_Y]
    FSUB  R3, R4
    FMUL  R3, PICO8_SCALE
    FADD  R3, 0.5
    FLR   R3
    CFI   R3
    IADD  R3, PICO8_OFFSET_Y
    OUT   GPU_DrawingPointY, R3

    OUT   GPU_Command, GPUCommand_DrawRegionZoomed

_pico8_sspr_done:
    MOV   R0, BOXED_NIL
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_reload: reload() -- restore the map and sprite flags from
;; the cart ROM (undoing mset()/fset()). Also used by __builtin_pico8_init.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_reload:
    PUSH  R1
    PUSH  R2
    PUSH  R3
    ;; map ROM -> RAM (2048 words)
    MOV   R1, __pico8_map_rom
    MOV   R2, PICO8_MAP_RAM
    MOV   R3, PICO8_MAP_WORDS
_pico8_init_map_loop:
    MOV   R0, [R1]
    MOV   [R2], R0
    IADD  R1, 1
    IADD  R2, 1
    ISUB  R3, 1
    MOV   R0, R3
    IGT   R0, 0
    JT    R0, _pico8_init_map_loop

    ;; sprite flags ROM -> RAM (256 words)
    MOV   R1, __pico8_flags_rom
    MOV   R2, PICO8_FLAGS_RAM
    MOV   R3, 256
_pico8_init_flags_loop:
    MOV   R0, [R1]
    MOV   [R2], R0
    IADD  R1, 1
    IADD  R2, 1
    ISUB  R3, 1
    MOV   R0, R3
    IGT   R0, 0
    JT    R0, _pico8_init_flags_loop
    MOV   R0, BOXED_NIL
    POP   R3
    POP   R2
    POP   R1
    RET
