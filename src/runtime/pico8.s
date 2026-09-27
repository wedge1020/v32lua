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
    JT    R0, _pico8_init_panels

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

_pico8_init_panels:
    ;; side panels (pico8_bezel.c): regions 272 (left) / 273 (right), 48x120
    MOV   R1, 272
    OUT   GPU_SelectedRegion, R1
    MOV   R3, 132
    OUT   GPU_RegionMinX, 0
    OUT   GPU_RegionHotspotX, 0
    OUT   GPU_RegionMaxX, 47
    OUT   GPU_RegionMinY, R3
    OUT   GPU_RegionHotspotY, R3
    MOV   R4, 251
    OUT   GPU_RegionMaxY, R4
    MOV   R1, 273
    OUT   GPU_SelectedRegion, R1
    OUT   GPU_RegionMinX, 48
    OUT   GPU_RegionHotspotX, 48
    OUT   GPU_RegionMaxX, 95
    OUT   GPU_RegionMinY, R3
    OUT   GPU_RegionHotspotY, R3
    OUT   GPU_RegionMaxY, R4

    ;; P8SCII glyphs 128-153: regions 274-299, 7x5, 16 per row of 6 pixels
    ;; at texture row 252 (PICO8_GLYPH_Y, pico8_bezel.c)
    MOV   R1, 0
_pico8_init_glyph_loop:
    MOV   R0, R1
    ILT   R0, 26
    JF    R0, _pico8_init_state
    MOV   R0, R1
    IADD  R0, 274
    OUT   GPU_SelectedRegion, R0
    MOV   R2, R1
    AND   R2, 15
    SHL   R2, 3                   ; x = (n % 16) * 8
    MOV   R3, R1
    SHL   R3, -4
    IMUL  R3, 6
    IADD  R3, 252                 ; y = 252 + (n / 16) * 6
    OUT   GPU_RegionMinX, R2
    OUT   GPU_RegionHotspotX, R2
    OUT   GPU_RegionMinY, R3
    OUT   GPU_RegionHotspotY, R3
    IADD  R2, 6
    OUT   GPU_RegionMaxX, R2
    IADD  R3, 4
    OUT   GPU_RegionMaxY, R3
    IADD  R1, 1
    JMP   _pico8_init_glyph_loop

_pico8_init_state:
    ;; custom side-panel art (--bezel, pico8_bezel.c): its own texture,
    ;; region 0 = left panel, 1 = right panel, each PANEL_W x PANEL_H
    MOV   R0, PICO8_BEZEL
    IEQ   R0, 2
    JF    R0, _pico8_init_rng
    MOV   R0, PICO8_BEZEL_TEXTURE
    OUT   GPU_SelectedTexture, R0
    MOV   R1, 0
    MOV   R2, PICO8_BEZEL_PW
    MOV   R3, PICO8_BEZEL_PH
    ISUB  R3, 1
_pico8_init_bezel_loop:
    OUT   GPU_SelectedRegion, R1
    MOV   R0, R1
    IMUL  R0, R2
    OUT   GPU_RegionMinX, R0
    OUT   GPU_RegionHotspotX, R0
    IADD  R0, R2
    ISUB  R0, 1
    OUT   GPU_RegionMaxX, R0
    OUT   GPU_RegionMinY, 0
    OUT   GPU_RegionHotspotY, 0
    OUT   GPU_RegionMaxY, R3
    IADD  R1, 1
    MOV   R0, R1
    ILT   R0, 2
    JT    R0, _pico8_init_bezel_loop
    OUT   GPU_SelectedTexture, 0

_pico8_init_rng:
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
    MOV   R0, 1                          ; treat Start as held until first released
    MOV   [PICO8_START_PREV], R0
    MOV   R0, 0
    MOV   [PICO8_TICKS], R0                ; time() = 0 until the first frame
    MOV   [PICO8_RAM_PTR], R0              ; peek/poke RAM: created on first use
    MOV   [PICO8_CARTDATA], R0             ; no cartdata() yet
    MOV   [PICO8_MENU_HOOK], R0            ; no menuitem() yet: plain pause

    CALL  __builtin_pico8_reload
    CALL  __pico8_audio_init
    CALL  __shapes_init                  ; circle atlas regions, if any
    OUT   GPU_SelectedTexture, 0

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
    ;; The visible range is clipped to the map once, so the cell loop keeps
    ;; the cell index, screen x and count in registers with no bounds
    ;; checks, reads each map word (4 cells) once, and steps over a word of
    ;; 4 empty cells in one go: ~12 cycles per cell, ~16 per drawn one,
    ;; ~16 per 4 empty cells (was ~70 per cell).
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

    ;; --- clip the visible range to the map itself, so the cell loop
    ;;     needs no bounds checks: 0 <= celx+col < 128, 0 <= cely+row < 64
    MOV   R1, [BP-3]
    ISGN  R1                     ; first column inside the map: -celx
    MOV   R2, [BP-10]
    IMAX  R2, R1
    MOV   [BP-10], R2
    MOV   R1, PICO8_MAP_WIDTH
    MOV   R2, [BP-3]
    ISUB  R1, R2                 ; one past the last: 128 - celx
    MOV   R2, [BP-5]
    IMIN  R2, R1
    MOV   [BP-5], R2
    MOV   R1, [BP-4]
    ISGN  R1
    MOV   R2, [BP-1]
    IMAX  R2, R1
    MOV   [BP-1], R2
    MOV   R1, PICO8_MAP_HEIGHT
    MOV   R2, [BP-4]
    ISUB  R1, R2
    MOV   R2, [BP-6]
    IMIN  R2, R1
    MOV   [BP-6], R2

    OUT   GPU_SelectedTexture, 0
    MOV   R1, PICO8_SCALE
    OUT   GPU_DrawingScaleX, R1
    OUT   GPU_DrawingScaleY, R1

    PUSH  R5
    PUSH  R6
    PUSH  R7
    PUSH  R8
    MOV   R8, [BP-7]             ; layer (0: no filter)

    ;; cells per row; nothing to draw when the column range is empty
    MOV   R3, [BP-5]
    MOV   R1, [BP-10]
    ISUB  R3, R1
    MOV   R1, R3
    ILT   R1, 1
    JT    R1, _pico8_map_rows_done
    MOV   [BP-5], R3             ; [BP-5] = cells per row from here on

_pico8_map_row:
    MOV   R1, [BP-1]
    MOV   R2, [BP-6]
    ILT   R1, R2
    JF    R1, _pico8_map_rows_done
    ;; screen y of this row
    MOV   R1, [BP-1]
    IMUL  R1, 22
    MOV   R2, [BP-9]
    IADD  R1, R2
    OUT   GPU_DrawingPointY, R1
    ;; R5 = cell index of the first visible cell, R6 = its screen x,
    ;; R7 = cells left in the row, R4 = the map word holding the current
    ;; cell, shifted so that cell is its low byte
    MOV   R5, [BP-4]
    MOV   R1, [BP-1]
    IADD  R5, R1
    IMUL  R5, PICO8_MAP_WIDTH
    MOV   R1, [BP-3]
    IADD  R5, R1
    MOV   R1, [BP-10]
    IADD  R5, R1
    MOV   R6, R1
    IMUL  R6, 22
    MOV   R1, [BP-8]
    IADD  R6, R1
    MOV   R7, [BP-5]
    MOV   R4, R5
    SHL   R4, -2
    IADD  R4, PICO8_MAP_RAM
    MOV   R4, [R4]
    MOV   R2, R5
    AND   R2, 3
    SHL   R2, 3
    ISGN  R2
    SHL   R4, R2
    JMP   _pico8_map_cell

_pico8_map_col:
    ;; at a word boundary: load the next 4 cells; skip all 4 at once when
    ;; they are empty (tile 0) and the row has 4 left
    MOV   R2, R5
    AND   R2, 3
    JT    R2, _pico8_map_cell
    MOV   R4, R5
    SHL   R4, -2
    IADD  R4, PICO8_MAP_RAM
    MOV   R4, [R4]
    JT    R4, _pico8_map_cell
    MOV   R2, R7
    ILT   R2, 4
    JT    R2, _pico8_map_cell
    IADD  R5, 4
    IADD  R6, 88
    ISUB  R7, 4
    JT    R7, _pico8_map_col
    JMP   _pico8_map_row_end

_pico8_map_cell:
    MOV   R1, R4
    AND   R1, 0xFF               ; R1 = tile id
    SHL   R4, -8
    JF    R1, _pico8_map_next_col   ; tile 0 is never drawn
    JF    R8, _pico8_map_draw
    ;; layer filter: (flags[tile] & layer) != 0
    MOV   R2, R1
    IADD  R2, PICO8_FLAGS_RAM
    MOV   R2, [R2]
    AND   R2, R8
    JF    R2, _pico8_map_next_col
_pico8_map_draw:
    OUT   GPU_SelectedRegion, R1
    OUT   GPU_DrawingPointX, R6
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
_pico8_map_next_col:
    IADD  R5, 1
    IADD  R6, 22
    ISUB  R7, 1
    JT    R7, _pico8_map_col

_pico8_map_row_end:
    MOV   R1, [BP-1]
    IADD  R1, 1
    MOV   [BP-1], R1
    JMP   _pico8_map_row

_pico8_map_rows_done:
    POP   R8
    POP   R7
    POP   R6
    POP   R5

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

    ;; --- fast path: one 8x8 sprite (w and h nil or 1), the usual call.
    ;;     Same placement as the general loop below, without the frame
    ;;     slots, the row/column loop and the truthy() calls.
    MOV   R1, [BP+5]
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JT    R2, _pico8_spr_f_w
    IEQ   R1, 0x3F800000         ; 1.0
    JF    R1, _pico8_spr_general
_pico8_spr_f_w:
    MOV   R1, [BP+6]
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JT    R2, _pico8_spr_f_h
    IEQ   R1, 0x3F800000         ; 1.0
    JF    R1, _pico8_spr_general
_pico8_spr_f_h:
    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    MOV   R2, R1
    ILT   R2, 0
    JT    R2, _pico8_spr_done
    MOV   R2, R1
    IGT   R2, 255
    JT    R2, _pico8_spr_done
    OUT   GPU_SelectedRegion, R1

    ;; x: round((x - cam_x) * SCALE) + OFFSET_X, + 22 and a mirrored scale
    ;; when flip_x is truthy
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
    MOV   R3, PICO8_SCALE
    MOV   R2, [BP+7]
    IEQ   R2, BOXED_NIL
    JT    R2, _pico8_spr_f_x
    MOV   R2, [BP+7]
    IEQ   R2, BOXED_FALSE
    JT    R2, _pico8_spr_f_x
    FSGN  R3
    IADD  R1, 22
_pico8_spr_f_x:
    OUT   GPU_DrawingScaleX, R3
    OUT   GPU_DrawingPointX, R1

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
    MOV   R3, PICO8_SCALE
    MOV   R2, [BP+8]
    IEQ   R2, BOXED_NIL
    JT    R2, _pico8_spr_f_y
    MOV   R2, [BP+8]
    IEQ   R2, BOXED_FALSE
    JT    R2, _pico8_spr_f_y
    FSGN  R3
    IADD  R1, 22
_pico8_spr_f_y:
    OUT   GPU_DrawingScaleY, R3
    OUT   GPU_DrawingPointY, R1
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    JMP   _pico8_spr_done

_pico8_spr_general:
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
    IEQ   R4, BOXED_NIL          ; all(nil): no elements, as in PICO-8
    JT    R4, _pico8_all_nil
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

_pico8_all_nil:
    MOV   R3, [BP+3]
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
;; add(t, v [, i]) as PICO-8: add(nil, v) does nothing and returns nil.
;; [SP+3] = t, [SP+2] = i, [SP+1] = v (the table.insert arguments)
__pico8_add:
    MOV   R0, [SP+3]
    IEQ   R0, BOXED_NIL
    JF    R0, __builtin_table_insert
    MOV   R0, BOXED_NIL
    RET

__builtin_pico8_foreach:
    ;; foreach(nil, f): nothing, as in PICO-8
    MOV   R0, [SP+2]
    IEQ   R0, BOXED_NIL
    JF    R0, __builtin_pico8_foreach_t
    MOV   R0, BOXED_NIL
    RET
__builtin_pico8_foreach_t:
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
    MOV   R13, 1                 ; argument count (variadic ABI)
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
    ;; count(nil) is 0, as in PICO-8
    MOV   R0, [SP+1]
    IEQ   R0, BOXED_NIL
    JF    R0, __builtin_pico8_count_t
    MOV   R0, 0.0
    RET
__builtin_pico8_count_t:
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
    ;; del(nil, v): nothing, as in PICO-8
    MOV   R0, [SP+2]
    IEQ   R0, BOXED_NIL
    JF    R0, __builtin_pico8_del_t
    MOV   R0, BOXED_NIL
    RET
__builtin_pico8_del_t:
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
;; [BP+2]=x [BP+3]=y [BP+4]=r (nil -> 4) [BP+5]=col. Returns nil.
;;
;; The pixels are the midpoint circle PICO-8 draws (as in zepto8: err
;; starts at 0, x steps when err >= r - 1; circfill fills the same rows'
;; spans). Radius 0-SHAPES_MAX_R: ONE draw of the pre-rendered shape
;; (shapes.c), tinted with the multiply color. Larger: the first octant is
;; walked -- one point per row, (X, K) from (r, 0) -- and each run of rows
;; with the same X becomes rectangles: with its 7 mirror images for circ(),
;; as 4 row spans for circfill(). (The old code drew 8 single pixels / 4
;; spans per step: ~5.7 r / ~2.8 r draws, against ~2.3 r / ~1.2 r now.)
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
    PUSH  R12
    PUSH  R0                      ; [BP-13]: the current run's X

    MOV   R1, [BP+5]
    CALL  __pico8_pen
    MOV   R12, R1                 ; color
    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    MOV   R8, R1                  ; cx
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    MOV   R9, R1                  ; cy
    MOV   R1, [BP+4]
    MOV   R0, R1
    IEQ   R0, BOXED_NIL
    JF    R0, _pico8_circ_have_r
    MOV   R1, 4.0                 ; PICO-8 default radius
_pico8_circ_have_r:
    CALL  __pico8_to_int
    MOV   R10, R1                 ; r
    MOV   R0, R10
    ILT   R0, 0
    JT    R0, _pico8_circ_done
    MOV   R0, SHAPES_TEXTURE
    ILT   R0, 0
    JT    R0, _pico8_circ_steps
    MOV   R4, PICO8_SCALE                ; draw scale
    MOV   R3, R10                 ; the shape's radius
    MOV   R0, R10
    IGT   R0, SHAPES_MAX_R
    JF    R0, _pico8_circ_atlas
    ;; --fast-circles: a filled circle beyond the atlas is its largest disc,
    ;; scaled to cover the 2r + 1 pixels (outlines are always drawn exactly)
    MOV   R0, SHAPES_FAST
    JF    R0, _pico8_circ_steps
    JF    R11, _pico8_circ_steps
    MOV   R3, SHAPES_MAX_R
    MOV   R0, R10
    SHL   R0, 1
    IADD  R0, 1
    CIF   R0
    FMUL  R4, R0
    MOV   R0, SHAPES_MAX_R
    SHL   R0, 1
    IADD  R0, 1
    CIF   R0
    FDIV  R4, R0
_pico8_circ_atlas:

    ;; --- one draw from the shape atlas ---
    MOV   R1, __pico8_palette
    IADD  R1, R12
    MOV   R1, [R1]
    CALL  __pico8_tint
    MOV   R6, R0                  ; multiply color to restore
    IN    R7, GPU_SelectedTexture
    OUT   GPU_SelectedTexture, SHAPES_TEXTURE
    MOV   R1, R3
    JT    R11, _pico8_circ_region
    IADD  R1, SHAPES_MAX_R
    IADD  R1, 1                   ; outlines follow the filled shapes
_pico8_circ_region:
    OUT   GPU_SelectedRegion, R1
    OUT   GPU_DrawingScaleX, R4
    OUT   GPU_DrawingScaleY, R4
    ;; top-left pixel on the canvas (camera applied), PICO-8 pixels
    MOV   R2, R8
    ISUB  R2, R10
    CIF   R2
    MOV   R0, [PICO8_CAMERA_X]
    FSUB  R2, R0                  ; R2 = fx
    MOV   R5, R9
    ISUB  R5, R10
    CIF   R5
    MOV   R0, [PICO8_CAMERA_Y]
    FSUB  R5, R0                  ; R5 = fy
    MOV   R0, R3
    IEQ   R0, R10
    JF    R0, _pico8_circ_place   ; --fast-circles' scaled disc: unclipped

    ;; The GPU charges a draw's whole size against its per-frame pixel
    ;; budget (9 screens), on screen or not, and drops every later draw
    ;; once that's spent (froggo's circle wipe: 270 radius-20 discs, 21
    ;; screens). So: nothing off the 128x128 canvas, and a circle crossing
    ;; an edge is drawn through a trimmed copy of its region (4095).
    MOV   R0, R10
    SHL   R0, 1
    IADD  R0, 1
    CIF   R0                      ; R0 = d (size in pixels)
    MOV   R3, R2
    FADD  R3, R0
    FLE   R3, 0.0
    JT    R3, _pico8_circ_off     ; left of the canvas
    MOV   R3, R5
    FADD  R3, R0
    FLE   R3, 0.0
    JT    R3, _pico8_circ_off     ; above it
    MOV   R3, R2
    FGE   R3, 128.0
    JT    R3, _pico8_circ_off     ; right of it
    MOV   R3, R5
    FGE   R3, 128.0
    JT    R3, _pico8_circ_off     ; below it
    MOV   R3, R2
    FLT   R3, 0.0
    JT    R3, _pico8_circ_clip
    MOV   R3, R5
    FLT   R3, 0.0
    JT    R3, _pico8_circ_clip
    MOV   R3, R2
    FADD  R3, R0
    FGT   R3, 128.0
    JT    R3, _pico8_circ_clip
    MOV   R3, R5
    FADD  R3, R0
    FGT   R3, 128.0
    JF    R3, _pico8_circ_place   ; fully on the canvas: the shape's own region

_pico8_circ_clip:
    ;; --- x: columns fx + k, k = 0 .. 2r ---
    IN    R12, GPU_RegionMinX
    MOV   R3, 128.0
    FSUB  R3, R2
    FSGN  R3
    FLR   R3
    FSGN  R3                      ; ceil(128 - fx): columns left of x = 128
    CFI   R3
    ISUB  R3, 1
    MOV   R0, R10
    SHL   R0, 1
    IMIN  R3, R0
    IADD  R3, R12                 ; MaxX
    MOV   R0, R2
    FSGN  R0
    FLR   R0
    CFI   R0                      ; floor(-fx): columns left of x = 0
    MOV   R4, 0
    IMAX  R0, R4
    AND   R0, 0xFFFFFFFC          ; whole multiples of 4 (4 * 2.75 = 11
                                  ; screen pixels): the pixel grid stays put
    IADD  R12, R0
    CIF   R0
    FADD  R2, R0                  ; fx of the first column kept
    OUT   GPU_SelectedRegion, 4095
    OUT   GPU_RegionMinX, R12
    OUT   GPU_RegionHotspotX, R12
    OUT   GPU_RegionMaxX, R3
    ;; --- y, the same ---
    OUT   GPU_SelectedRegion, R1
    IN    R12, GPU_RegionMinY
    MOV   R3, 128.0
    FSUB  R3, R5
    FSGN  R3
    FLR   R3
    FSGN  R3
    CFI   R3
    ISUB  R3, 1
    MOV   R0, R10
    SHL   R0, 1
    IMIN  R3, R0
    IADD  R3, R12                 ; MaxY
    MOV   R0, R5
    FSGN  R0
    FLR   R0
    CFI   R0
    MOV   R4, 0
    IMAX  R0, R4
    AND   R0, 0xFFFFFFFC
    IADD  R12, R0
    CIF   R0
    FADD  R5, R0
    OUT   GPU_SelectedRegion, 4095
    OUT   GPU_RegionMinY, R12
    OUT   GPU_RegionHotspotY, R12
    OUT   GPU_RegionMaxY, R3

_pico8_circ_place:
    FMUL  R2, PICO8_SCALE         ; placed as __pico8_fill does
    FADD  R2, 0.5
    FLR   R2
    CFI   R2
    IADD  R2, PICO8_OFFSET_X
    OUT   GPU_DrawingPointX, R2
    FMUL  R5, PICO8_SCALE
    FADD  R5, 0.5
    FLR   R5
    CFI   R5
    IADD  R5, PICO8_OFFSET_Y
    OUT   GPU_DrawingPointY, R5
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
_pico8_circ_off:
    OUT   GPU_SelectedTexture, R7
    OUT   GPU_MultiplyColor, R6
    JMP   _pico8_circ_done

_pico8_circ_steps:
    MOV   R0, [PICO8_CAMERA_X]    ; center in screen coordinates
    CFI   R0
    ISUB  R8, R0
    MOV   R0, [PICO8_CAMERA_Y]
    CFI   R0
    ISUB  R9, R0
    OUT   GPU_SelectedTexture, 0  ; the color's swatch, once per circle
    MOV   R0, R12
    IADD  R0, PICO8_SWATCH_REGION_BASE
    OUT   GPU_SelectedRegion, R0
    ;; R2 = X, R3 = K, R6 = err, R7 = first row of the current run
    MOV   R2, R10
    MOV   R3, 0
    MOV   R6, 0
    MOV   R7, 0
_pico8_circ_loop:
    MOV   [BP-13], R2
    IADD  R3, 1                   ; K++; X-- when err >= r - 1
    MOV   R0, R10
    ISUB  R0, 1
    MOV   R1, R6
    ILT   R1, R0
    JF    R1, _pico8_circ_x
    MOV   R0, R3
    SHL   R0, 1
    IADD  R0, 1
    IADD  R6, R0
    JMP   _pico8_circ_next
_pico8_circ_x:
    ISUB  R2, 1
    MOV   R0, R3
    ISUB  R0, R2
    SHL   R0, 1
    IADD  R0, 1
    IADD  R6, R0
_pico8_circ_next:
    MOV   R0, R2                  ; left the octant (X < K): last run
    ILT   R0, R3
    JT    R0, _pico8_circ_last
    MOV   R0, [BP-13]
    IEQ   R0, R2
    JT    R0, _pico8_circ_loop    ; same X: the run goes on
    PUSH  R2
    PUSH  R3
    MOV   R1, [BP-13]
    MOV   R2, R7
    ISUB  R3, 1
    CALL  __pico8_circ_run
    POP   R3
    POP   R2
    MOV   R7, R3
    JMP   _pico8_circ_loop
_pico8_circ_last:
    MOV   R1, [BP-13]
    MOV   R2, R7
    ISUB  R3, 1
    CALL  __pico8_circ_run

_pico8_circ_done:
    POP   R12                     ; (scratch slot)
    POP   R12
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
    MOV   R0, BOXED_NIL
    MOV   SP, BP
    POP   BP
    RET

;; __pico8_circ_rect (internal): a rectangle of the circle fallback -- R1 = x,
;; R2 = y (screen coordinates: the camera is already applied), R3 = w,
;; R4 = h (integers, >= 1) -- with texture 0 and the color's swatch region
;; already selected. Same placement as __pico8_fill. Clobbers R0 only.
__pico8_circ_rect:
    MOV   R0, R3
    CIF   R0
    FMUL  R0, PICO8_SCALE
    FDIV  R0, 3.0
    OUT   GPU_DrawingScaleX, R0
    MOV   R0, R4
    CIF   R0
    FMUL  R0, PICO8_SCALE
    FDIV  R0, 3.0
    OUT   GPU_DrawingScaleY, R0
    MOV   R0, R1
    CIF   R0
    FMUL  R0, PICO8_SCALE
    FADD  R0, 0.5
    FLR   R0
    CFI   R0
    IADD  R0, PICO8_OFFSET_X
    OUT   GPU_DrawingPointX, R0
    MOV   R0, R2
    CIF   R0
    FMUL  R0, PICO8_SCALE
    FADD  R0, 0.5
    FLR   R0
    CFI   R0
    IADD  R0, PICO8_OFFSET_Y
    OUT   GPU_DrawingPointY, R0
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    RET

;; __pico8_circ_run (internal): one run of first-octant points -- column
;; R1 = X, rows R2 = k1 .. R3 = k2 (relative to the center R8, R9) --
;; drawn with its 7 mirror images (R11 = 0) or as the 4 row spans it
;; bounds (R11 = 1), in color R12. Preserves R1-R13.
__pico8_circ_run:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1                      ; [BP-1] X
    PUSH  R2                      ; [BP-2] k1
    PUSH  R3                      ; [BP-3] k2
    PUSH  R4
    PUSH  R5
    PUSH  R6
    PUSH  R7
    MOV   R5, R12
    MOV   R7, [BP-1]              ; X
    MOV   R6, [BP-3]
    MOV   R0, [BP-2]
    ISUB  R6, R0
    IADD  R6, 1                   ; h = k2 - k1 + 1
    JT    R11, _pico8_run_filled

    MOV   R3, 1                   ; columns cx +- X
    MOV   R4, R6
    MOV   R1, R8
    IADD  R1, R7
    MOV   R2, R9
    MOV   R0, [BP-2]
    IADD  R2, R0
    CALL  __pico8_circ_rect
    MOV   R1, R8
    ISUB  R1, R7
    CALL  __pico8_circ_rect
    MOV   R2, R9
    MOV   R0, [BP-3]
    ISUB  R2, R0
    CALL  __pico8_circ_rect
    MOV   R1, R8
    IADD  R1, R7
    CALL  __pico8_circ_rect
    MOV   R3, R6                  ; rows cy +- X
    MOV   R4, 1
    MOV   R1, R8
    MOV   R0, [BP-2]
    IADD  R1, R0
    MOV   R2, R9
    IADD  R2, R7
    CALL  __pico8_circ_rect
    MOV   R2, R9
    ISUB  R2, R7
    CALL  __pico8_circ_rect
    MOV   R1, R8
    MOV   R0, [BP-3]
    ISUB  R1, R0
    CALL  __pico8_circ_rect
    MOV   R2, R9
    IADD  R2, R7
    CALL  __pico8_circ_rect
    JMP   _pico8_run_done

_pico8_run_filled:
    MOV   R1, R8                  ; rows cy + k1..k2 and cy - k2..k1, width 2X + 1
    ISUB  R1, R7
    MOV   R3, R7
    SHL   R3, 1
    IADD  R3, 1
    MOV   R4, R6
    MOV   R2, R9
    MOV   R0, [BP-2]
    IADD  R2, R0
    CALL  __pico8_circ_rect
    MOV   R2, R9
    MOV   R0, [BP-3]
    ISUB  R2, R0
    CALL  __pico8_circ_rect
    MOV   R0, [BP-3]              ; rows cy +- X, width 2 k2 + 1
    MOV   R1, R8
    ISUB  R1, R0
    MOV   R3, R0
    SHL   R3, 1
    IADD  R3, 1
    MOV   R4, 1
    MOV   R2, R9
    IADD  R2, R7
    CALL  __pico8_circ_rect
    MOV   R2, R9
    ISUB  R2, R7
    CALL  __pico8_circ_rect

_pico8_run_done:
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

;; __pico8_tint (internal): R1 = color (0xAABBGGRR) -> GPU_MultiplyColor =
;; that color times the current multiply color (per channel), so a shape
;; drawn white comes out in the color. R0 = the previous multiply color.
;; Preserves R1-R13.
__pico8_tint:
    IN    R0, GPU_MultiplyColor
    PUSH  R0
    IEQ   R0, 0xFFFFFFFF
    JF    R0, _pico8_tint_mix
    OUT   GPU_MultiplyColor, R1
    POP   R0
    RET
_pico8_tint_mix:
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    IN    R2, GPU_MultiplyColor
    MOV   R5, 0
    MOV   R4, 0
_pico8_tint_channel:
    MOV   R3, R4
    ISGN  R3
    MOV   R0, R1
    SHL   R0, R3
    AND   R0, 255
    PUSH  R0
    MOV   R0, R2
    SHL   R0, R3
    AND   R0, 255
    POP   R3
    IMUL  R0, R3
    IADD  R0, 127
    IDIV  R0, 255
    SHL   R0, R4
    OR    R5, R0
    IADD  R4, 8
    MOV   R0, R4
    ILT   R0, 32
    JT    R0, _pico8_tint_channel
    OUT   GPU_MultiplyColor, R5
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R0
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

    ;; angle = atan2(dy, dx) -- but ATAN2 with both operands zero is a
    ;; Vircon32 hardware error, and line(x, y, x, y) (one pixel) is common
    MOV   R1, R3
    FEQ   R1, 0.0
    MOV   R2, R4
    FEQ   R2, 0.0
    AND   R1, R2
    JF    R1, _pico8_line_angle
    MOV   R4, 0.0                 ; zero length: any angle, the 1-pixel swatch
    JMP   _pico8_line_have_angle
_pico8_line_angle:
    ATAN2 R4, R3
_pico8_line_have_angle:
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
    ;; screen memory (0x6000-0x7FFF) follows, if peek/poke RAM exists
    MOV   R0, [PICO8_RAM_PTR]
    JF    R0, _pico8_cls_draw
    PUSH  R11
    PUSH  R12
    PUSH  R13
    MOV   R13, R0
    IADD  R13, 0x6000
    MOV   R12, R1
    SHL   R12, 4
    OR    R12, R1                 ; both pixels of each byte
    MOV   R11, 0x2000
    SETS
    POP   R13
    POP   R12
    POP   R11
_pico8_cls_draw:
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
    PUSH  R4
    PUSH  R5
    PUSH  R6

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

    ;; the text: any value as tostring() shows it
    MOV   R2, R1                  ; y
    PUSH  R2
    PUSH  R3
    MOV   R0, [BP+2]
    PUSH  R0
    CALL  __builtin_tostring_scratch_a
    IADD  SP, 1
    CALL  __unbox_string          ; R0 = characters (clobbers R1)
    POP   R1                      ; x
    POP   R2                      ; y
    MOV   R3, R0
    CALL  __pico8_print_text

    MOV   R1, 0xFFFFFFFF
    OUT   GPU_MultiplyColor, R1
    MOV   R0, BOXED_NIL
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
;; __pico8_print_text (internal): R1 = x, R2 = y (screen pixels), R3 =
;; address of the characters (one per word, 0-terminated). ASCII is drawn
;; in the BIOS font (10 px per character); P8SCII glyphs 128-153 as their
;; 7x5 icons at the canvas scale, two characters wide like PICO-8's wide
;; glyphs; "\n" starts a new line 6 PICO-8 pixels down (at the first x).
;; Uses the multiply color the caller set. Preserves R1-R13.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__pico8_print_text:
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    PUSH  R6
    IN    R0, GPU_SelectedTexture
    PUSH  R0
    IN    R0, GPU_SelectedRegion
    PUSH  R0
    MOV   R5, R1                  ; x at the start of a line
    MOV   R6, 0                   ; lines down
    OUT   GPU_SelectedTexture, -1 ; BIOS font
_pico8_text_loop:
    MOV   R4, [R3]
    MOV   R0, R4
    IEQ   R0, 0
    JT    R0, _pico8_text_done
    MOV   R0, R4
    IEQ   R0, 10
    JT    R0, _pico8_text_newline
    MOV   R0, R4
    ILT   R0, 128
    JT    R0, _pico8_text_ascii
    MOV   R0, R4
    ISUB  R0, 128
    ILT   R0, 26
    JF    R0, _pico8_text_wide    ; other bytes: an empty wide cell
    OUT   GPU_SelectedTexture, 0
    MOV   R0, R4
    IADD  R0, 146                 ; region 274 + (code - 128)
    OUT   GPU_SelectedRegion, R0
    MOV   R0, PICO8_SCALE
    OUT   GPU_DrawingScaleX, R0
    OUT   GPU_DrawingScaleY, R0
    OUT   GPU_DrawingPointX, R1
    MOV   R0, R2
    IADD  R0, 3                   ; centred in the 20-pixel line
    OUT   GPU_DrawingPointY, R0
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    OUT   GPU_SelectedTexture, -1
_pico8_text_wide:
    IADD  R1, 20
    JMP   _pico8_text_next
_pico8_text_ascii:
    OUT   GPU_SelectedRegion, R4
    OUT   GPU_DrawingPointX, R1
    OUT   GPU_DrawingPointY, R2
    OUT   GPU_Command, GPUCommand_DrawRegion
    IADD  R1, 10
    JMP   _pico8_text_next
_pico8_text_newline:
    MOV   R0, R6                  ; y -= this line's offset, then the next
    IMUL  R0, 33
    SHL   R0, -1
    ISUB  R2, R0
    IADD  R6, 1
    MOV   R0, R6
    IMUL  R0, 33                  ; 6 PICO-8 px = 16.5 screen px per line
    SHL   R0, -1
    IADD  R2, R0
    MOV   R1, R5
_pico8_text_next:
    IADD  R3, 1
    JMP   _pico8_text_loop
_pico8_text_done:
    POP   R0
    OUT   GPU_SelectedRegion, R0
    POP   R0
    OUT   GPU_SelectedTexture, R0
    POP   R6
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
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

    ;; left + right: 144 x 360 -- the side panels (48x120 at 3x), or black
    OUT   GPU_DrawingPointY, 0
    OUT   GPU_DrawingPointX, 0
    MOV   R1, PICO8_BEZEL
    JF    R1, _pico8_present_black
    IEQ   R1, 2
    JT    R1, _pico8_present_custom
    MOV   R1, 272
    OUT   GPU_SelectedRegion, R1
    MOV   R1, 3.0
    OUT   GPU_DrawingScaleX, R1
    OUT   GPU_DrawingScaleY, R1
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    MOV   R1, 273
    OUT   GPU_SelectedRegion, R1
    OUT   GPU_DrawingPointX, 496          ; 144 + 352
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    MOV   R1, PICO8_SWATCH_REGION_BASE
    OUT   GPU_SelectedRegion, R1          ; color 0 swatch for the bars below
    JMP   _pico8_present_bars
_pico8_present_custom:
    ;; custom art (--bezel): black first when the art has transparent pixels
    ;; (the panels also hide anything drawn off the canvas)
    MOV   R1, PICO8_BEZEL_ALPHA
    JF    R1, _pico8_present_custom_art
    MOV   R1, 48.0
    OUT   GPU_DrawingScaleX, R1
    MOV   R1, 120.0
    OUT   GPU_DrawingScaleY, R1
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    OUT   GPU_DrawingPointX, 496
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    OUT   GPU_DrawingPointX, 0
_pico8_present_custom_art:
    MOV   R1, PICO8_BEZEL_TEXTURE
    OUT   GPU_SelectedTexture, R1
    OUT   GPU_SelectedRegion, 0
    MOV   R1, PICO8_BEZEL_SCALE
    OUT   GPU_DrawingScaleX, R1
    OUT   GPU_DrawingScaleY, R1
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    OUT   GPU_SelectedRegion, 1
    OUT   GPU_DrawingPointX, 496
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    OUT   GPU_SelectedTexture, 0
    MOV   R1, PICO8_SWATCH_REGION_BASE
    OUT   GPU_SelectedRegion, R1
    JMP   _pico8_present_bars
_pico8_present_black:
    MOV   R1, 48.0                        ; 144 / 3
    OUT   GPU_DrawingScaleX, R1
    MOV   R1, 120.0                       ; 360 / 3
    OUT   GPU_DrawingScaleY, R1
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    OUT   GPU_DrawingPointX, 496          ; 144 + 352
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
_pico8_present_bars:

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
;; PICO-8 SOUND (cart __sfx__/__music__ data; see pico8_audio.c)
;;
;; The cart's 64 SFX are sounds PICO8_SFX_BASE + n, recorded at
;; PICO8_AUDIO_RATE Hz and played at channel speed PICO8_AUDIO_SPEED. SPU channels 0-3 play music (one per
;; PICO-8 music channel), 4-7 play sfx() (PICO-8 channel c -> 4 + c).
;; Music is sequenced here, pattern by pattern, from __pico8_patterns
;; (6 words per pattern: ch0..ch3 sound id or -1, length in frames, next
;; pattern or -1); __builtin_pico8_music_tick runs after every WAIT of the
;; PICO-8 main loop and starts the next pattern on the frame the current
;; one ends. (The SPU mixes a frame's audio at the end of the frame, and
;; every pattern lasts a whole number of frames, so patterns join without
;; a gap.) A tick that ran long starts the pattern late but at the right
;; position, so the song never drifts.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; __pico8_audio_init (internal): music off; each SFX sound gets its loop
;; points from __pico8_sfx_loops (3 words per SFX: loops, start, end).
__pico8_audio_init:
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    MOV   R0, -1
    MOV   [PICO8_MUSIC_PATTERN], R0
    MOV   R0, 0
    MOV   [PICO8_SFX_NEXT], R0
    MOV   R1, PICO8_SFX_BASE
    MOV   R0, R1
    ILT   R0, 0
    JT    R0, _pico8_audio_init_done   ; the cart plays no synthesized sound
    MOV   R2, __pico8_sfx_loops
    MOV   R3, 0
_pico8_audio_init_loop:
    MOV   R0, R3
    IEQ   R0, 64
    JT    R0, _pico8_audio_init_done
    MOV   R4, R1
    IADD  R4, R3
    OUT   SPU_SelectedSound, R4
    MOV   R0, [R2]
    OUT   SPU_SoundPlayWithLoop, R0
    JF    R0, _pico8_audio_init_next
    MOV   R0, [R2+1]
    OUT   SPU_SoundLoopStart, R0
    MOV   R0, [R2+2]
    OUT   SPU_SoundLoopEnd, R0
_pico8_audio_init_next:
    IADD  R2, 3
    IADD  R3, 1
    JMP   _pico8_audio_init_loop
_pico8_audio_init_done:
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    RET

;; __pico8_play_channel (internal): R1 = SPU channel, R2 = sound id (-1:
;; stop the channel), R3 = start position in samples. Clobbers R0.
__pico8_play_channel:
    OUT   SPU_SelectedChannel, R1
    MOV   R0, R2
    ILT   R0, 0
    JT    R0, _pico8_play_channel_stop
    OUT   SPU_ChannelAssignedSound, R2
    OUT   SPU_ChannelVolume, 1.0
    OUT   SPU_ChannelSpeed, PICO8_AUDIO_SPEED ; sounds are PICO8_AUDIO_RATE Hz
    OUT   SPU_Command, SPUCommand_PlaySelectedChannel
    MOV   R0, R3
    IEQ   R0, 0
    JT    R0, _pico8_play_channel_done
    OUT   SPU_ChannelPosition, R3         ; (play rewinds, so set it after)
_pico8_play_channel_done:
    RET
_pico8_play_channel_stop:
    OUT   SPU_Command, SPUCommand_StopSelectedChannel
    RET

;; __pico8_music_start (internal): R1 = pattern, R3 = frames late.
;; Starts the pattern's four channels; sets PICO8_MUSIC_PATTERN.
;; Clobbers R0-R3, R5.
__pico8_music_start:
    MOV   [PICO8_MUSIC_PATTERN], R1
    MOV   R5, R1
    IMUL  R5, 6
    MOV   R0, __pico8_patterns
    IADD  R5, R0                          ; R5 = pattern entry
    IMUL  R3, PICO8_AUDIO_RATE
    IDIV  R3, 60                          ; frames late -> samples
    MOV   R1, 0
    MOV   R2, [R5]
    CALL  __pico8_play_channel
    MOV   R1, 1
    MOV   R2, [R5+1]
    CALL  __pico8_play_channel
    MOV   R1, 2
    MOV   R2, [R5+2]
    CALL  __pico8_play_channel
    MOV   R1, 3
    MOV   R2, [R5+3]
    CALL  __pico8_play_channel
    RET

;; __pico8_music_stop (internal): stops channels 0-3; music off.
__pico8_music_stop:
    PUSH  R1
    PUSH  R2
    MOV   R0, -1
    MOV   [PICO8_MUSIC_PATTERN], R0
    MOV   R2, -1
    MOV   R1, 0
    CALL  __pico8_play_channel
    MOV   R1, 1
    CALL  __pico8_play_channel
    MOV   R1, 2
    CALL  __pico8_play_channel
    MOV   R1, 3
    CALL  __pico8_play_channel
    POP   R2
    POP   R1
    RET

;; __builtin_pico8_music(n): [BP+2] = n. Starts the song at pattern n now;
;; n < 0, n > 63 or an empty pattern stops the music. (fade_len and
;; channel_mask are not supported.)
__builtin_pico8_music:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    MOV   R0, PICO8_SFX_BASE
    ILT   R0, 0
    JT    R0, _pico8_music_done
    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    MOV   R0, R1
    ILT   R0, 0
    JT    R0, _pico8_music_stop
    MOV   R0, R1
    IGT   R0, 63
    JT    R0, _pico8_music_stop
    MOV   R4, R1
    IMUL  R4, 6
    MOV   R0, __pico8_patterns
    IADD  R4, R0
    MOV   R4, [R4+4]                      ; length in frames
    MOV   R0, R4
    IEQ   R0, 0
    JT    R0, _pico8_music_stop           ; empty pattern
    MOV   R3, 0
    CALL  __pico8_music_start
    IN    R0, TIM_FrameCounter
    IADD  R0, R4
    MOV   [PICO8_MUSIC_END], R0
    JMP   _pico8_music_done
_pico8_music_stop:
    CALL  __pico8_music_stop
_pico8_music_done:
    MOV   R0, BOXED_NIL
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; __builtin_pico8_music_tick: called by the PICO-8 main loop after every
;; WAIT. When the current pattern's last frame has passed, starts the next
;; one (late by however many frames the loop missed). Preserves registers.
__builtin_pico8_music_tick:
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    MOV   R1, [PICO8_MUSIC_PATTERN]
    MOV   R0, R1
    ILT   R0, 0
    JT    R0, _pico8_music_tick_done      ; no music
    IN    R3, TIM_FrameCounter
    MOV   R2, [PICO8_MUSIC_END]
    MOV   R0, R3
    ILT   R0, R2
    JT    R0, _pico8_music_tick_done      ; pattern still playing
    ISUB  R3, R2                          ; frames late
    IMUL  R1, 6
    MOV   R0, __pico8_patterns
    IADD  R1, R0
    MOV   R1, [R1+5]                      ; next pattern
    MOV   R0, R1
    ILT   R0, 0
    JT    R0, _pico8_music_tick_stop
    MOV   R4, R1
    IMUL  R4, 6
    MOV   R0, __pico8_patterns
    IADD  R4, R0
    MOV   R4, [R4+4]                      ; its length
    MOV   R0, R4
    IEQ   R0, 0
    JT    R0, _pico8_music_tick_stop
    CALL  __pico8_music_start
    MOV   R0, [PICO8_MUSIC_END]
    IADD  R0, R4
    MOV   [PICO8_MUSIC_END], R0
    JMP   _pico8_music_tick_done
_pico8_music_tick_stop:
    CALL  __pico8_music_stop
_pico8_music_tick_done:
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    RET

;; __builtin_pico8_sfx(n, channel): [BP+2] = n, [BP+3] = channel (nil or
;; -1: any free sfx channel). n = -1 stops (that channel, or all sfx
;; channels); n = -2 lets a looping sfx finish (loop released).
__builtin_pico8_sfx:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    MOV   R0, PICO8_SFX_BASE
    ILT   R0, 0
    JT    R0, _pico8_sfx_done
    ;; R4 = PICO-8 channel 0..3, or -1 for "any"
    MOV   R4, -1
    MOV   R1, [BP+3]
    MOV   R0, R1
    AND   R0, NAN_VALUE
    IEQ   R0, NAN_VALUE
    JT    R0, _pico8_sfx_have_channel     ; nil / not a number
    CALL  __pico8_to_int
    MOV   R0, R1
    ILT   R0, 0
    JT    R0, _pico8_sfx_have_channel
    MOV   R0, R1
    IGT   R0, 3
    JT    R0, _pico8_sfx_have_channel
    MOV   R4, R1
_pico8_sfx_have_channel:
    MOV   R1, [BP+2]
    CALL  __pico8_to_int                  ; R1 = n
    MOV   R0, R1
    IEQ   R0, -1
    JT    R0, _pico8_sfx_stop
    MOV   R0, R1
    IEQ   R0, -2
    JT    R0, _pico8_sfx_release
    MOV   R0, R1
    ILT   R0, 0
    JT    R0, _pico8_sfx_done
    MOV   R0, R1
    IGT   R0, 63
    JT    R0, _pico8_sfx_done
    MOV   R2, R1
    IADD  R2, PICO8_SFX_BASE              ; R2 = sound id
    MOV   R1, R4
    ILT   R1, 0
    JF    R1, _pico8_sfx_explicit
    ;; any channel: the first of 4..7 not playing, else round robin
    MOV   R1, 4
_pico8_sfx_scan:
    MOV   R0, R1
    IEQ   R0, 8
    JT    R0, _pico8_sfx_round_robin
    OUT   SPU_SelectedChannel, R1
    IN    R0, SPU_ChannelState
    IEQ   R0, 0x42                        ; SPUChannelState_Playing
    JF    R0, _pico8_sfx_play
    IADD  R1, 1
    JMP   _pico8_sfx_scan
_pico8_sfx_round_robin:
    MOV   R1, [PICO8_SFX_NEXT]
    MOV   R0, R1
    IADD  R0, 1
    AND   R0, 3
    MOV   [PICO8_SFX_NEXT], R0
    IADD  R1, 4
    JMP   _pico8_sfx_play
_pico8_sfx_explicit:
    MOV   R1, R4
    IADD  R1, 4
_pico8_sfx_play:
    MOV   R3, 0
    CALL  __pico8_play_channel
    JMP   _pico8_sfx_done
_pico8_sfx_stop:
    MOV   R2, -1
    MOV   R3, 0
    MOV   R1, R4
    ILT   R1, 0
    JF    R1, _pico8_sfx_stop_one
    MOV   R1, 4
    CALL  __pico8_play_channel
    MOV   R1, 5
    CALL  __pico8_play_channel
    MOV   R1, 6
    CALL  __pico8_play_channel
    MOV   R1, 7
    CALL  __pico8_play_channel
    JMP   _pico8_sfx_done
_pico8_sfx_stop_one:
    MOV   R1, R4
    IADD  R1, 4
    CALL  __pico8_play_channel
    JMP   _pico8_sfx_done
_pico8_sfx_release:
    MOV   R1, R4
    ILT   R1, 0
    JT    R1, _pico8_sfx_done
    MOV   R1, R4
    IADD  R1, 4
    OUT   SPU_SelectedChannel, R1
    OUT   SPU_ChannelLoopEnabled, 0
_pico8_sfx_done:
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_flip -- PICO-8 flip(): present what has been drawn (mask
;; the margins, as after _draw()) and wait one PICO-8 frame: PICO8_FRAME_STEP
;; hardware frames, keeping music sequencing on time. R0 = nil.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_flip:
    PUSH  R1
    CALL  __builtin_pico8_present
    CALL  __builtin_pico8_pause_check
    MOV   R1, [PICO8_TICKS]              ; one more PICO-8 frame for time()
    IADD  R1, 1
    MOV   [PICO8_TICKS], R1
    MOV   R1, PICO8_FRAME_STEP
_pico8_flip_wait:
    WAIT
    PUSH  R1
    CALL  __builtin_pico8_music_tick
    POP   R1
    ISUB  R1, 1
    MOV   R0, R1
    IGT   R0, 0
    JT    R0, _pico8_flip_wait
    MOV   R0, BOXED_NIL
    POP   R1
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_pause_check: the TIC-80 layer's pause, for PICO-8 carts.
;; Called once per PICO-8 tick (and by flip()). If gamepad 1's Start went
;; down since the last check: pause every SPU channel, darken the last frame
;; with a translucent black overlay, print "- PAUSED -", and wait (drawing
;; nothing, so the darkened frame stays up) until Start is pressed again.
;; Then resume the channels and push the music sequencer's pattern-end frame
;; forward by the time spent paused. The cart's own code does not run while
;; paused. Preserves all registers except R0.
;;
;; Start is edge-detected against PICO8_START_PREV (held at the previous
;; check), not by the port reading exactly 1: a tick is 2 frames at 30 fps,
;; so a press seen first on the frame between two checks was missed.
;; Every piece of GPU state this touches -- including what __builtin_print
;; changes -- is saved on the stack and restored: keeping the multiply color
;; in a register across the print CALL restored it as 0x000000AC (alpha 0),
;; so nothing the cart drew after unpausing was visible.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_pause_check:
    PUSH  R1
    IN    R1, INP_SelectedGamepad
    PUSH  R1
    CALL  __pico8_start_edge
    JT    R0, _pico8_pause_enter
    POP   R1
    OUT   INP_SelectedGamepad, R1
    POP   R1
    RET

;; __pico8_start_edge (internal): R0 = 1 if gamepad 1's Start is down now
;; and wasn't at the previous call. Updates PICO8_START_PREV. Clobbers R1.
__pico8_start_edge:
    OUT   INP_SelectedGamepad, 0
    IN    R0, INP_GamepadButtonStart
    IGT   R0, 0                          ; 1 while held
    MOV   R1, [PICO8_START_PREV]
    MOV   [PICO8_START_PREV], R0
    JF    R0, _pico8_start_edge_done
    MOV   R0, R1
    IEQ   R0, 0                          ; held now, not before
_pico8_start_edge_done:
    RET

_pico8_pause_enter:
    PUSH  R2
    IN    R0, TIM_FrameCounter
    PUSH  R0                             ; [SP] = frame the pause began
    OUT   SPU_Command, SPUCommand_PauseAllChannels

    ;; save the GPU state (restored after the overlay and the text)
    IN    R0, GPU_SelectedTexture
    PUSH  R0
    IN    R0, GPU_SelectedRegion
    PUSH  R0
    IN    R0, GPU_DrawingPointX
    PUSH  R0
    IN    R0, GPU_DrawingPointY
    PUSH  R0
    IN    R0, GPU_DrawingScaleX
    PUSH  R0
    IN    R0, GPU_DrawingScaleY
    PUSH  R0
    IN    R0, GPU_MultiplyColor
    PUSH  R0

    ;; darken: the black swatch stretched over the whole screen at ~60%
    OUT   GPU_SelectedTexture, 0
    MOV   R0, PICO8_SWATCH_REGION_BASE   ; color 0 = black
    OUT   GPU_SelectedRegion, R0
    OUT   GPU_DrawingPointX, 0
    OUT   GPU_DrawingPointY, 0
    MOV   R0, 214.0                      ; 3px swatch * 214 >= 640
    OUT   GPU_DrawingScaleX, R0
    MOV   R0, 120.0                      ; 3px * 120 = 360
    OUT   GPU_DrawingScaleY, R0
    MOV   R0, 0x99FFFFFF                 ; alpha 0x99
    OUT   GPU_MultiplyColor, R0
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    MOV   R0, 0xFFFFFFFF
    OUT   GPU_MultiplyColor, R0
    MOV   R0, [PICO8_MENU_HOOK]
    JT    R0, _pico8_pause_menu
    MOV   R0, 270
    PUSH  R0
    MOV   R0, 172
    PUSH  R0
    MOV   R0, __const_str_pause
    OR    R0, BOXED_ROMSTRING
    PUSH  R0
    CALL  __builtin_print
    IADD  SP, 3
    JMP   _pico8_pause_restore

    ;; menuitem() entries: the prelude's __p8_pausemenu (Lua) draws the menu
    ;; and runs it -- its own frames, input, the items' callbacks -- until
    ;; "continue"/Start. A Lua call may use every register: all saved.
_pico8_pause_menu:
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
    MOV   R13, 0                         ; no arguments (variadic ABI)
    CALL  __builtin_exec
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
    MOV   R0, 1
    MOV   [PICO8_START_PREV], R0         ; the Start that closed it is held

_pico8_pause_restore:
    POP   R0
    OUT   GPU_MultiplyColor, R0
    POP   R0
    OUT   GPU_DrawingScaleY, R0
    POP   R0
    OUT   GPU_DrawingScaleX, R0
    POP   R0
    OUT   GPU_DrawingPointY, R0
    POP   R0
    OUT   GPU_DrawingPointX, R0
    POP   R0
    OUT   GPU_SelectedRegion, R0
    POP   R0
    OUT   GPU_SelectedTexture, R0

    MOV   R0, [PICO8_MENU_HOOK]
    JT    R0, _pico8_pause_done          ; the menu already waited
_pico8_pause_wait:
    WAIT
    CALL  __pico8_start_edge
    JF    R0, _pico8_pause_wait
_pico8_pause_done:

    OUT   SPU_Command, SPUCommand_ResumeAllChannels
    IN    R0, TIM_FrameCounter
    POP   R2                             ; frame the pause began
    ISUB  R0, R2                         ; frames spent paused
    MOV   R2, [PICO8_MUSIC_END]
    IADD  R2, R0
    MOV   [PICO8_MUSIC_END], R2
    POP   R2
    POP   R1                             ; caller's selected gamepad
    OUT   INP_SelectedGamepad, R1
    POP   R1
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; PICO-8 MEMORY: peek/poke (8, 16 and 32 bits), memcpy, memset, reload,
;; sget/sset, cartdata/dget/dset.
;;
;; PICO-8's 64 KB address space is emulated as 65536 words, one byte per
;; word, created on first use and filled from the cart ROM image
;; (__pico8_rom_gfx / __pico8_rom_snd / map / flags, see pico8_assets.c).
;;   0x0000-0x0FFF  sprites 0-127                       storage (cart data)
;;   0x1000-0x1FFF  sprites 128-255 = map rows 32-63   live: the map buffer
;;   0x2000-0x2FFF  map rows 0-31                       live: the map buffer
;;   0x3000-0x30FF  sprite flags                        live: fget()/fset()
;;   0x3100-0x42FF  music, sfx                          storage (cart data)
;;   0x4300-0x5DFF  general use, custom font            storage
;;   0x5E00-0x5EFF  cartdata (dget/dset)                storage; after
;;                  cartdata(), written through to the memory card
;;   0x5F00-0x5F3F  draw state                          storage, except
;;                  0x5F25 pen and 0x5F28-0x5F2B camera x/y (live)
;;   0x5F4C-0x5F4F  buttons, players 0-3                live (read only)
;;   0x6000-0x7FFF  screen                              writes are drawn
;;   0x8000-0xFFFF  upper memory                        storage
;; Sprites and sound are rendered at compile time, so writing the sprite
;; sheet or the music/sfx data changes nothing seen or heard, and reading
;; the screen returns what was written to screen memory, not what spr() or
;; rect() drew (there is no GPU read-back).
;;
;; Addresses are taken modulo 0x10000 like PICO-8's 16-bit addresses (so
;; the 16.16 literal -32768 and 0x8000 are the same address). peek2/poke2
;; are signed 16-bit, peek4/poke4 the raw 16.16 fixed-point bits.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Draw state defaults (0x5F00-0x5F3F): draw palette (color 0 transparent),
;; screen palette, clip rect 0,0,128,128, pen 6.
__pico8_drawstate_rom:
    integer 0x10, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
    integer 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
    integer 0, 0, 128, 128, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    integer 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

;; __pico8_ram (internal): R0 = base of the emulated RAM, created and
;; filled on first use. Preserves R1-R13.
__pico8_ram:
    MOV   R0, [PICO8_RAM_PTR]
    PUSH  R1
    MOV   R1, R0
    IEQ   R1, 0
    JT    R1, _pico8_ram_create
    POP   R1
    RET
_pico8_ram_create:
    PUSH  R2
    PUSH  R3
    PUSH  R6
    PUSH  R11
    PUSH  R12
    PUSH  R13
    MOV   R0, 65536
    PUSH  R0
    CALL  __malloc                ; clobbers R0-R3, R6
    IADD  SP, 1
    MOV   [PICO8_RAM_PTR], R0
    MOV   R13, R0                 ; zero-fill: SETS writes R12 to [R13], R11 times
    MOV   R12, 0
    MOV   R11, 65536
    SETS
    MOV   R1, 0                   ; sprite sheet, from the cart
_pico8_ram_gfx:
    CALL  __pico8_cart_rd
    MOV   R2, [PICO8_RAM_PTR]
    IADD  R2, R1
    MOV   [R2], R0
    IADD  R1, 1
    MOV   R2, R1
    ILT   R2, 0x1000
    JT    R2, _pico8_ram_gfx
    MOV   R1, 0x3100              ; music and sfx, from the cart
_pico8_ram_snd:
    CALL  __pico8_cart_rd
    MOV   R2, [PICO8_RAM_PTR]
    IADD  R2, R1
    MOV   [R2], R0
    IADD  R1, 1
    MOV   R2, R1
    ILT   R2, 0x4300
    JT    R2, _pico8_ram_snd
    MOV   R13, [PICO8_RAM_PTR]    ; draw state defaults
    IADD  R13, 0x5F00
    MOV   R12, __pico8_drawstate_rom
    MOV   R11, 64
    MOVS
    POP   R13
    POP   R12
    POP   R11
    POP   R6
    POP   R3
    POP   R2
    POP   R1
    MOV   R0, [PICO8_RAM_PTR]
    RET

;; __pico8_map_cell_index (internal): R1 = address in 0x1000-0x2FFF ->
;; R1 = map cell index (y * 128 + x). Clobbers R0.
__pico8_map_cell_index:
    MOV   R0, R1
    IGE   R0, 0x2000
    JT    R0, _pico8_mci_upper
    ISUB  R1, 0x1000              ; 0x1000-0x1FFF: rows 32-63
    IADD  R1, 4096
    RET
_pico8_mci_upper:
    ISUB  R1, 0x2000              ; 0x2000-0x2FFF: rows 0-31
    RET

;; __pico8_byte_of (internal): R2 = base of data packed 4 bytes per word
;; (low byte first), R1 = byte index -> R0 = byte. Clobbers R1, R2.
__pico8_byte_of:
    MOV   R0, R1
    SHL   R0, -2
    IADD  R2, R0
    MOV   R0, [R2]
    AND   R1, 3
    SHL   R1, 3
    ISGN  R1
    SHL   R0, R1
    AND   R0, 255
    RET

;; __pico8_cart_rd (internal): R1 = address -> R0 = the byte the CART holds
;; there (what reload() copies from; 0 above 0x42FF). Preserves R1-R13.
__pico8_cart_rd:
    PUSH  R1
    PUSH  R2
    MOV   R0, R1
    ILT   R0, 0
    JT    R0, _pico8_cart_zero
    MOV   R0, R1
    ILT   R0, 0x1000
    JT    R0, _pico8_cart_gfx
    MOV   R0, R1
    ILT   R0, 0x3000
    JT    R0, _pico8_cart_map
    MOV   R0, R1
    ILT   R0, 0x3100
    JT    R0, _pico8_cart_flags
    MOV   R0, R1
    ILT   R0, 0x4300
    JT    R0, _pico8_cart_snd
_pico8_cart_zero:
    MOV   R0, 0
    JMP   _pico8_cart_done
_pico8_cart_gfx:
    MOV   R2, __pico8_rom_gfx
    CALL  __pico8_byte_of
    JMP   _pico8_cart_done
_pico8_cart_map:
    CALL  __pico8_map_cell_index
    MOV   R2, __pico8_map_rom
    CALL  __pico8_byte_of
    JMP   _pico8_cart_done
_pico8_cart_flags:
    ISUB  R1, 0x3000
    MOV   R2, __pico8_flags_rom
    IADD  R2, R1
    MOV   R0, [R2]
    AND   R0, 255
    JMP   _pico8_cart_done
_pico8_cart_snd:
    ISUB  R1, 0x3100
    MOV   R2, __pico8_rom_snd
    CALL  __pico8_byte_of
_pico8_cart_done:
    POP   R2
    POP   R1
    RET

;; __pico8_rd (internal): R1 = address (0-0xFFFF) -> R0 = byte.
;; Preserves R1-R13.
__pico8_rd:
    PUSH  R1
    PUSH  R2
    MOV   R0, R1
    ILT   R0, 0x1000
    JT    R0, _pico8_rd_ram
    MOV   R0, R1
    ILT   R0, 0x3000
    JT    R0, _pico8_rd_map
    MOV   R0, R1
    ILT   R0, 0x3100
    JT    R0, _pico8_rd_flags
    MOV   R0, R1
    IEQ   R0, 0x5F25
    JT    R0, _pico8_rd_pen
    MOV   R0, R1
    ILT   R0, 0x5F28
    JT    R0, _pico8_rd_ram
    MOV   R0, R1
    ILT   R0, 0x5F2C
    JT    R0, _pico8_rd_camera
    MOV   R0, R1
    ILT   R0, 0x5F4C
    JT    R0, _pico8_rd_ram
    MOV   R0, R1
    ILT   R0, 0x5F50
    JT    R0, _pico8_rd_buttons
_pico8_rd_ram:
    CALL  __pico8_ram
    IADD  R0, R1
    MOV   R0, [R0]
    JMP   _pico8_rd_done
_pico8_rd_map:
    CALL  __pico8_map_cell_index
    MOV   R2, PICO8_MAP_RAM
    CALL  __pico8_byte_of
    JMP   _pico8_rd_done
_pico8_rd_flags:
    ISUB  R1, 0x3000
    MOV   R2, PICO8_FLAGS_RAM
    IADD  R2, R1
    MOV   R0, [R2]
    AND   R0, 255
    JMP   _pico8_rd_done
_pico8_rd_pen:
    CALL  __pico8_ram
    IADD  R0, R1
    MOV   R0, [R0]
    AND   R0, 0xF0                ; the high nibble is kept as written
    MOV   R2, [PICO8_PEN]
    OR    R0, R2
    JMP   _pico8_rd_done
_pico8_rd_camera:
    ;; 0x5F28/29 = camera x, 0x5F2A/2B = camera y (signed 16-bit, low first)
    ISUB  R1, 0x5F28
    MOV   R2, R1
    AND   R2, 1
    SHL   R2, 3                   ; bit position of the byte
    SHL   R1, -1                  ; 0 = x, 1 = y
    MOV   R0, [PICO8_CAMERA_X]
    JF    R1, _pico8_rd_cam_have
    MOV   R0, [PICO8_CAMERA_Y]
_pico8_rd_cam_have:
    CFI   R0                      ; camera() stores whole numbers
    ISGN  R2
    SHL   R0, R2
    AND   R0, 255
    JMP   _pico8_rd_done
_pico8_rd_buttons:
    ;; bit b = btn(b, player)
    ISUB  R1, 0x5F4C
    CIF   R1
    PUSH  R1                      ; p
    MOV   R0, BOXED_NIL
    PUSH  R0                      ; i = nil: bitfield
    CALL  __builtin_pico8_btn
    IADD  SP, 2
    CFI   R0
    AND   R0, 255
_pico8_rd_done:
    POP   R2
    POP   R1
    RET

;; __pico8_fill_screen (internal): __pico8_fill in screen coordinates
;; (no camera). Same registers as __pico8_fill.
__pico8_fill_screen:
    MOV   R0, [PICO8_CAMERA_X]
    PUSH  R0
    MOV   R0, [PICO8_CAMERA_Y]
    PUSH  R0
    MOV   R0, 0
    MOV   [PICO8_CAMERA_X], R0
    MOV   [PICO8_CAMERA_Y], R0
    CALL  __pico8_fill
    POP   R0
    MOV   [PICO8_CAMERA_Y], R0
    POP   R0
    MOV   [PICO8_CAMERA_X], R0
    RET

;; __pico8_wr (internal): R1 = address (0-0xFFFF), R2 = byte (0-255).
;; Preserves R0-R13.
__pico8_wr:
    PUSH  R0
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    CALL  __pico8_ram             ; the RAM image always holds the byte
    IADD  R0, R1
    MOV   [R0], R2
    MOV   R0, R1
    ILT   R0, 0x1000
    JT    R0, _pico8_wr_done
    MOV   R0, R1
    ILT   R0, 0x3000
    JT    R0, _pico8_wr_map
    MOV   R0, R1
    ILT   R0, 0x3100
    JT    R0, _pico8_wr_flags
    MOV   R0, R1
    ILT   R0, 0x5E00
    JT    R0, _pico8_wr_done
    MOV   R0, R1
    ILT   R0, 0x5F00
    JT    R0, _pico8_wr_cartdata
    MOV   R0, R1
    IEQ   R0, 0x5F25
    JT    R0, _pico8_wr_pen
    MOV   R0, R1
    ILT   R0, 0x5F28
    JT    R0, _pico8_wr_done
    MOV   R0, R1
    ILT   R0, 0x5F2C
    JT    R0, _pico8_wr_camera
    MOV   R0, R1
    ILT   R0, 0x6000
    JT    R0, _pico8_wr_done
    MOV   R0, R1
    ILT   R0, 0x8000
    JT    R0, _pico8_wr_screen
    JMP   _pico8_wr_done

_pico8_wr_map:
    CALL  __pico8_map_cell_index
    MOV   R3, R1
    SHL   R3, -2
    IADD  R3, PICO8_MAP_RAM
    AND   R1, 3
    SHL   R1, 3
    MOV   R4, 255
    SHL   R4, R1
    NOT   R4
    MOV   R0, [R3]
    AND   R0, R4
    SHL   R2, R1
    OR    R0, R2
    MOV   [R3], R0
    JMP   _pico8_wr_done

_pico8_wr_flags:
    ISUB  R1, 0x3000
    IADD  R1, PICO8_FLAGS_RAM
    MOV   [R1], R2
    JMP   _pico8_wr_done

_pico8_wr_pen:
    AND   R2, 15
    MOV   [PICO8_PEN], R2
    JMP   _pico8_wr_done

_pico8_wr_camera:
    ISUB  R1, 0x5F28
    MOV   R3, R1
    AND   R3, 1
    SHL   R3, 3                   ; bit position of the byte
    SHL   R1, -1                  ; 0 = x, 1 = y
    MOV   R0, [PICO8_CAMERA_X]
    JF    R1, _pico8_wr_cam_have
    MOV   R0, [PICO8_CAMERA_Y]
_pico8_wr_cam_have:
    CFI   R0
    AND   R0, 0xFFFF
    MOV   R4, 255
    SHL   R4, R3
    NOT   R4
    AND   R0, R4
    SHL   R2, R3
    OR    R0, R2
    MOV   R4, R0                  ; sign-extend the 16-bit value
    IGE   R4, 0x8000
    JF    R4, _pico8_wr_cam_pos
    ISUB  R0, 0x10000
_pico8_wr_cam_pos:
    CIF   R0
    JT    R1, _pico8_wr_cam_y
    MOV   [PICO8_CAMERA_X], R0
    JMP   _pico8_wr_done
_pico8_wr_cam_y:
    MOV   [PICO8_CAMERA_Y], R0
    JMP   _pico8_wr_done

_pico8_wr_cartdata:
    ;; after cartdata(), the 32-bit slot this byte belongs to goes to the
    ;; memory card too (card word DATA_BASE + 1 + slot)
    MOV   R0, [PICO8_CARTDATA]
    JF    R0, _pico8_wr_done
    IN    R0, MEM_Connected
    JF    R0, _pico8_wr_done
    ISUB  R1, 0x5E00
    SHL   R1, -2                  ; slot 0-63
    MOV   R3, R1
    SHL   R3, 2
    IADD  R3, 0x5E00
    CALL  __pico8_ram
    IADD  R3, R0                  ; the slot's 4 bytes
    MOV   R2, [R3]
    MOV   R4, [R3+1]
    SHL   R4, 8
    OR    R2, R4
    MOV   R4, [R3+2]
    SHL   R4, 16
    OR    R2, R4
    MOV   R4, [R3+3]
    SHL   R4, 24
    OR    R2, R4
    IADD  R1, VIRCON32_MEMCARD_DATA_BASE
    MOV   [R1+1], R2
    JMP   _pico8_wr_done

_pico8_wr_screen:
    ;; 64 bytes per row, 2 pixels per byte (low nibble = left pixel);
    ;; drawn in screen coordinates. One draw when both pixels match.
    ISUB  R1, 0x6000
    MOV   R5, R2                  ; byte
    MOV   R2, R1
    SHL   R2, -6                  ; y
    AND   R1, 63
    SHL   R1, 1                   ; x
    MOV   R4, 1                   ; h
    MOV   R3, R5
    SHL   R3, -4                  ; right pixel
    AND   R5, 15                  ; left pixel
    MOV   R0, R3
    IEQ   R0, R5
    JF    R0, _pico8_wr_screen_two
    MOV   R3, 2
    CALL  __pico8_fill_screen
    JMP   _pico8_wr_done
_pico8_wr_screen_two:
    PUSH  R3
    MOV   R3, 1
    CALL  __pico8_fill_screen
    POP   R5
    IADD  R1, 1
    CALL  __pico8_fill_screen

_pico8_wr_done:
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    POP   R0
    RET

;; __pico8_addr (internal): R1 = Lua number -> R1 = flr(n) mod 0x10000,
;; as an integer 0-0xFFFF (anything else -> 0). Also how byte and 16-bit
;; values are reduced before storing. Preserves R0, R2-R13.
__pico8_addr:
    PUSH  R2
    MOV   R2, R1
    AND   R2, NAN_VALUE
    IEQ   R2, NAN_VALUE
    JT    R2, _pico8_addr_zero
    FLR   R1
    MOV   R2, R1
    FDIV  R2, 65536.0
    FLR   R2
    FMUL  R2, 65536.0
    FSUB  R1, R2                  ; 0 <= n < 65536, exact
    CFI   R1
    AND   R1, 0xFFFF
    POP   R2
    RET
_pico8_addr_zero:
    MOV   R1, 0
    POP   R2
    RET

;; __pico8_fix32 (internal): R1 = Lua number -> R1 = the 32 bits of its
;; 16.16 fixed-point form, flr(n * 65536) mod 2^32. Preserves R0, R2-R13.
__pico8_fix32:
    PUSH  R2
    MOV   R2, R1
    AND   R2, NAN_VALUE
    IEQ   R2, NAN_VALUE
    JT    R2, _pico8_fix32_zero
    FMUL  R1, 65536.0
    FLR   R1
    MOV   R2, R1
    FDIV  R2, 4294967296.0
    FLR   R2
    FMUL  R2, 4294967296.0
    FSUB  R1, R2                  ; 0 <= n < 2^32
    MOV   R2, R1
    FGE   R2, 2147483648.0
    JF    R2, _pico8_fix32_ok
    FSUB  R1, 4294967296.0        ; into CFI's range
_pico8_fix32_ok:
    CFI   R1
    POP   R2
    RET
_pico8_fix32_zero:
    MOV   R1, 0
    POP   R2
    RET

;; __pico8_peek_w (internal): R1 = address (int), R2 = width (1, 2, 4)
;; -> R0 = Lua number. Preserves R1-R13.
__pico8_peek_w:
    PUSH  R1
    PUSH  R3
    PUSH  R4
    MOV   R3, 0                   ; value
    MOV   R4, 0                   ; bit position
_pico8_peek_w_byte:
    CALL  __pico8_rd
    SHL   R0, R4
    OR    R3, R0
    IADD  R1, 1
    AND   R1, 0xFFFF
    IADD  R4, 8
    MOV   R0, R2
    SHL   R0, 3
    IGT   R0, R4
    JT    R0, _pico8_peek_w_byte
    MOV   R0, R2
    IEQ   R0, 2
    JF    R0, _pico8_peek_w_not2
    MOV   R0, R3                  ; peek2: signed 16-bit
    IGE   R0, 0x8000
    JF    R0, _pico8_peek_w_not2
    ISUB  R3, 0x10000
_pico8_peek_w_not2:
    MOV   R0, R3
    CIF   R0
    MOV   R3, R2
    IEQ   R3, 4
    JF    R3, _pico8_peek_w_done
    FDIV  R0, 65536.0             ; peek4: 16.16
_pico8_peek_w_done:
    POP   R4
    POP   R3
    POP   R1
    RET

;; __pico8_poke_w (internal): R1 = address (int), R2 = width (1, 2, 4),
;; R3 = Lua number. Preserves R0-R13.
__pico8_poke_w:
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    MOV   R5, R2                  ; width = bytes to write
    PUSH  R1
    MOV   R1, R3
    MOV   R0, R5
    IEQ   R0, 4
    JT    R0, _pico8_poke_w_fix
    CALL  __pico8_addr            ; flr(v) mod 0x10000
    JMP   _pico8_poke_w_have
_pico8_poke_w_fix:
    CALL  __pico8_fix32
_pico8_poke_w_have:
    MOV   R4, R1                  ; bits to store, low byte first
    POP   R1
_pico8_poke_w_byte:
    MOV   R2, R4
    AND   R2, 255
    CALL  __pico8_wr
    SHL   R4, -8
    IADD  R1, 1
    AND   R1, 0xFFFF
    ISUB  R5, 1
    MOV   R2, R5
    IGT   R2, 0
    JT    R2, _pico8_poke_w_byte
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_peek: [BP+2] = width (raw int 1/2/4), [BP+3] = address
;; -> R0 = value
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_peek:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    MOV   R1, [BP+3]
    CALL  __pico8_addr
    MOV   R2, [BP+2]
    CALL  __pico8_peek_w
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_poke: [BP+2] = width (raw int), [BP+3] = count (raw int,
;; >= 1), [BP+4] = address, [BP+5 ...] = the values, written one after
;; another (poke(a, v1, v2, ...)). R0 = nil.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_poke:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    MOV   R1, [BP+4]
    CALL  __pico8_addr
    MOV   R2, [BP+2]              ; width
    MOV   R4, [BP+3]              ; values left
    MOV   R5, BP
    IADD  R5, 5                   ; -> first value
_pico8_poke_next:
    MOV   R0, R4
    IGT   R0, 0
    JF    R0, _pico8_poke_done
    MOV   R3, [R5]
    CALL  __pico8_poke_w
    IADD  R1, R2
    AND   R1, 0xFFFF
    IADD  R5, 1
    ISUB  R4, 1
    JMP   _pico8_poke_next
_pico8_poke_done:
    MOV   R0, BOXED_NIL
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; __pico8_count (internal): R1 = Lua number -> R1 = flr(n) as an int,
;; clamped to 0-0x10000 (a byte count). Preserves R0, R2-R13.
__pico8_count:
    PUSH  R2
    MOV   R2, R1
    AND   R2, NAN_VALUE
    IEQ   R2, NAN_VALUE
    JT    R2, _pico8_count_zero
    MOV   R2, R1
    FLT   R2, 1.0
    JT    R2, _pico8_count_zero
    MOV   R2, R1
    FGT   R2, 65536.0
    JF    R2, _pico8_count_ok
    MOV   R1, 65536.0
_pico8_count_ok:
    FLR   R1
    CFI   R1
    POP   R2
    RET
_pico8_count_zero:
    MOV   R1, 0
    POP   R2
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_memcpy: [BP+2] = dest, [BP+3] = src, [BP+4] = length
;; Overlapping ranges are copied as by memmove, like PICO-8. R0 = nil.
;; __builtin_pico8_reload_range: reload(dest, src, length): the same, but
;; reading the cart's own data (as it was before any poke/mset/fset).
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_reload_range:
    PUSH  BP
    MOV   BP, SP
    PUSH  R6
    MOV   R6, 1                   ; source: the cart
    JMP   _pico8_copy_common
__builtin_pico8_memcpy:
    PUSH  BP
    MOV   BP, SP
    PUSH  R6
    MOV   R6, 0                   ; source: RAM
_pico8_copy_common:
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    MOV   R1, [BP+4]
    CALL  __pico8_count
    MOV   R5, R1                  ; bytes left
    MOV   R1, [BP+2]
    CALL  __pico8_addr
    MOV   R3, R1                  ; dest
    MOV   R1, [BP+3]
    CALL  __pico8_addr
    MOV   R4, R1                  ; src
    MOV   R2, 1                   ; step
    JT    R6, _pico8_copy_loop    ; (the cart is never the destination)
    MOV   R0, R3                  ; dest after src: copy from the end
    IGT   R0, R4
    JF    R0, _pico8_copy_loop
    IADD  R3, R5
    ISUB  R3, 1
    IADD  R4, R5
    ISUB  R4, 1
    MOV   R2, -1
_pico8_copy_loop:
    MOV   R0, R5
    IGT   R0, 0
    JF    R0, _pico8_copy_done
    AND   R3, 0xFFFF
    AND   R4, 0xFFFF
    MOV   R1, R4
    JT    R6, _pico8_copy_from_cart
    CALL  __pico8_rd
    JMP   _pico8_copy_put
_pico8_copy_from_cart:
    CALL  __pico8_cart_rd
_pico8_copy_put:
    MOV   R1, R3
    PUSH  R2
    MOV   R2, R0
    CALL  __pico8_wr
    POP   R2
    IADD  R3, R2
    IADD  R4, R2
    ISUB  R5, 1
    JMP   _pico8_copy_loop
_pico8_copy_done:
    MOV   R0, BOXED_NIL
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    POP   R6
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; __builtin_pico8_memset: [BP+2] = dest, [BP+3] = value, [BP+4] = length
;; R0 = nil. Filling screen memory with a byte whose two pixels match (the
;; memset(0x6000, 0, 0x2000) idiom) is drawn as at most 3 rectangles
;; instead of one draw per byte.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_memset:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    PUSH  R6
    PUSH  R7
    MOV   R1, [BP+4]
    CALL  __pico8_count
    MOV   R5, R1                  ; length
    MOV   R1, [BP+3]
    CALL  __pico8_addr
    AND   R1, 255
    MOV   R2, R1                  ; byte
    MOV   R1, [BP+2]
    CALL  __pico8_addr
    MOV   R3, R1                  ; dest
    ;; fast screen path: both nibbles equal and no wrap past 0xFFFF
    MOV   R6, 0
    MOV   R0, R2
    SHL   R0, -4
    MOV   R4, R2
    AND   R4, 15
    IEQ   R0, R4
    JF    R0, _pico8_memset_loop
    MOV   R0, R3
    IADD  R0, R5
    ILE   R0, 0x10000
    JF    R0, _pico8_memset_loop
    MOV   R6, 1
_pico8_memset_loop:
    MOV   R0, R5
    IGT   R0, 0
    JF    R0, _pico8_memset_draw
    AND   R3, 0xFFFF
    MOV   R1, R3
    JF    R6, _pico8_memset_wr
    MOV   R0, R1                  ; screen byte on the fast path: store only
    ILT   R0, 0x6000
    JT    R0, _pico8_memset_wr
    MOV   R0, R1
    IGE   R0, 0x8000
    JT    R0, _pico8_memset_wr
    CALL  __pico8_ram
    IADD  R0, R1
    MOV   [R0], R2
    JMP   _pico8_memset_next
_pico8_memset_wr:
    CALL  __pico8_wr
_pico8_memset_next:
    IADD  R3, 1
    ISUB  R5, 1
    JMP   _pico8_memset_loop

_pico8_memset_draw:
    JF    R6, _pico8_memset_done
    ;; screen part of [dest, dest + length): byte offsets s..e (relative
    ;; to 0x6000), drawn as a partial first row, whole rows, a partial last
    ;; row
    MOV   R1, [BP+2]
    CALL  __pico8_addr
    MOV   R6, R1                  ; s
    MOV   R1, [BP+4]
    CALL  __pico8_count
    MOV   R7, R6
    IADD  R7, R1                  ; e
    IMAX  R6, 0x6000
    IMIN  R7, 0x8000
    ISUB  R6, 0x6000
    ISUB  R7, 0x6000
    MOV   R0, R6
    ILT   R0, R7
    JF    R0, _pico8_memset_done
    MOV   R5, R2
    AND   R5, 15                  ; color
    MOV   R4, 1                   ; h
    MOV   R0, R6
    AND   R0, 63
    JF    R0, _pico8_memset_rows  ; s starts a row
    MOV   R1, R6                  ; partial first row: s .. min(e, row end)
    AND   R1, 63
    SHL   R1, 1
    MOV   R2, R6
    SHL   R2, -6
    MOV   R3, R6
    OR    R3, 63
    IADD  R3, 1                   ; row end
    IMIN  R3, R7
    MOV   R0, R3
    ISUB  R3, R6
    SHL   R3, 1                   ; w
    MOV   R6, R0
    CALL  __pico8_fill_screen
_pico8_memset_rows:
    MOV   R3, R7
    ISUB  R3, R6
    SHL   R3, -6                  ; whole rows
    JF    R3, _pico8_memset_last
    MOV   R4, R3
    MOV   R1, 0
    MOV   R2, R6
    SHL   R2, -6
    SHL   R3, 6
    IADD  R6, R3
    MOV   R3, 128
    CALL  __pico8_fill_screen
    MOV   R4, 1
_pico8_memset_last:
    MOV   R3, R7
    ISUB  R3, R6
    JF    R3, _pico8_memset_done
    SHL   R3, 1
    MOV   R1, 0
    MOV   R2, R6
    SHL   R2, -6
    CALL  __pico8_fill_screen
_pico8_memset_done:
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
;; __builtin_pico8_reload_all: reload() with no arguments -- the map and
;; flags (always), and the sprite sheet and sound data of the emulated RAM
;; if it exists. R0 = nil.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_reload_all:
    PUSH  R1
    PUSH  R2
    CALL  __builtin_pico8_reload
    MOV   R0, [PICO8_RAM_PTR]
    JF    R0, _pico8_reload_all_done
    MOV   R1, 0
_pico8_reload_all_gfx:
    CALL  __pico8_cart_rd
    MOV   R2, [PICO8_RAM_PTR]
    IADD  R2, R1
    MOV   [R2], R0
    IADD  R1, 1
    MOV   R2, R1
    ILT   R2, 0x1000
    JT    R2, _pico8_reload_all_gfx
    MOV   R1, 0x3100
_pico8_reload_all_snd:
    CALL  __pico8_cart_rd
    MOV   R2, [PICO8_RAM_PTR]
    IADD  R2, R1
    MOV   [R2], R0
    IADD  R1, 1
    MOV   R2, R1
    ILT   R2, 0x4300
    JT    R2, _pico8_reload_all_snd
_pico8_reload_all_done:
    MOV   R0, BOXED_NIL
    POP   R2
    POP   R1
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; sget(x, y): [BP+2] = x, [BP+3] = y -> sprite sheet pixel (0 off-sheet)
;; sset(x, y [, c]): [BP+4] = c (nil -> the pen). R0 = nil.
;; The sheet is read from / written to memory 0x0000-0x1FFF; drawing uses
;; the sheet as it was compiled, so sset() is not seen by spr().
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_sget:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    CALL  __pico8_sheet_addr
    JF    R0, _pico8_sget_done    ; R0 = 0.0 off-sheet
    CALL  __pico8_rd
    JF    R3, _pico8_sget_lo
    SHL   R0, -4
_pico8_sget_lo:
    AND   R0, 15
    CIF   R0
_pico8_sget_done:
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

__builtin_pico8_sset:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    CALL  __pico8_sheet_addr
    JF    R0, _pico8_sset_done
    MOV   R2, [BP+4]
    MOV   R4, R2
    IEQ   R4, BOXED_NIL
    JF    R4, _pico8_sset_col
    MOV   R2, [PICO8_PEN]
    JMP   _pico8_sset_have
_pico8_sset_col:
    PUSH  R1
    MOV   R1, R2
    CALL  __pico8_to_int
    MOV   R2, R1
    POP   R1
_pico8_sset_have:
    AND   R2, 15
    CALL  __pico8_rd
    JT    R3, _pico8_sset_hi
    AND   R0, 0xF0
    OR    R0, R2
    JMP   _pico8_sset_put
_pico8_sset_hi:
    AND   R0, 0x0F
    SHL   R2, 4
    OR    R0, R2
_pico8_sset_put:
    MOV   R2, R0
    CALL  __pico8_wr
_pico8_sset_done:
    MOV   R0, BOXED_NIL
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; __pico8_sheet_addr (internal, uses the caller's frame): [BP+2] = x,
;; [BP+3] = y -> R0 = 1 and R1 = byte address, R3 = 1 for the high nibble;
;; R0 = 0 off the 128x128 sheet. Clobbers R2.
__pico8_sheet_addr:
    MOV   R1, [BP+3]
    CALL  __pico8_to_int
    MOV   R2, R1                  ; y
    MOV   R1, [BP+2]
    CALL  __pico8_to_int          ; x
    MOV   R0, 0
    MOV   R3, R1
    ILT   R3, 0
    JT    R3, _pico8_sheet_off
    MOV   R3, R1
    IGE   R3, 128
    JT    R3, _pico8_sheet_off
    MOV   R3, R2
    ILT   R3, 0
    JT    R3, _pico8_sheet_off
    MOV   R3, R2
    IGE   R3, 128
    JT    R3, _pico8_sheet_off
    MOV   R3, R1
    AND   R3, 1
    SHL   R1, -1
    SHL   R2, 6
    IADD  R1, R2
    MOV   R0, 1
_pico8_sheet_off:
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; cartdata(id): [BP+2] = hash of the id (raw int, computed at compile
;; time). With a memory card: if the card holds this id's data, it is loaded
;; into 0x5E00-0x5EFF and true is returned; otherwise the card's slots are
;; claimed for this id and zeroed, and false is returned. From then on,
;; writes to 0x5E00-0x5EFF (dset, poke) are saved to the card. Without a
;; card, dget/dset still work for the session and false is returned.
;; Card layout: word DATA_BASE = id hash, DATA_BASE + 1 + n = slot n.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_cartdata:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    PUSH  R11
    PUSH  R12
    PUSH  R13
    MOV   R5, BOXED_FALSE
    IN    R0, MEM_Connected
    JF    R0, _pico8_cartdata_done
    MOV   R1, VIRCON32_MEMCARD_DATA_BASE
    MOV   R0, [R1]
    MOV   R2, [BP+2]
    IEQ   R0, R2
    JF    R0, _pico8_cartdata_new
    MOV   R5, BOXED_TRUE
    JMP   _pico8_cartdata_load
_pico8_cartdata_new:
    MOV   [R1], R2                ; claim the slots for this id
    MOV   R13, R1
    IADD  R13, 1
    MOV   R12, 0
    MOV   R11, 64
    SETS
_pico8_cartdata_load:
    CALL  __pico8_ram
    MOV   R3, R0
    IADD  R3, 0x5E00              ; RAM bytes
    IADD  R1, 1                   ; card slots
    MOV   R4, 64
_pico8_cartdata_slot:
    MOV   R2, [R1]
    MOV   R0, R2
    AND   R0, 255
    MOV   [R3], R0
    MOV   R0, R2
    SHL   R0, -8
    AND   R0, 255
    MOV   [R3+1], R0
    MOV   R0, R2
    SHL   R0, -16
    AND   R0, 255
    MOV   [R3+2], R0
    MOV   R0, R2
    SHL   R0, -24
    MOV   [R3+3], R0
    IADD  R1, 1
    IADD  R3, 4
    ISUB  R4, 1
    MOV   R0, R4
    IGT   R0, 0
    JT    R0, _pico8_cartdata_slot
    MOV   R0, 1
    MOV   [PICO8_CARTDATA], R0
_pico8_cartdata_done:
    MOV   R0, R5
    POP   R13
    POP   R12
    POP   R11
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; dget(n): [BP+2] = n -> peek4(0x5E00 + 4 * n) (0 outside 0-63)
;; dset(n, v): [BP+2] = n, [BP+3] = v -> poke4(0x5E00 + 4 * n, v). R0 = nil.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_dget:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    CALL  __pico8_dslot
    JF    R0, _pico8_dget_done    ; R0 = 0.0 outside 0-63
    MOV   R2, 4
    CALL  __pico8_peek_w
_pico8_dget_done:
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

__builtin_pico8_dset:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    CALL  __pico8_dslot
    JF    R0, _pico8_dset_done
    MOV   R2, 4
    MOV   R3, [BP+3]
    CALL  __pico8_poke_w
_pico8_dset_done:
    MOV   R0, BOXED_NIL
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; __pico8_dslot (internal, caller's frame): [BP+2] = n -> R0 = 1 and
;; R1 = 0x5E00 + 4 * flr(n), or R0 = 0 if n is not 0-63.
__pico8_dslot:
    MOV   R1, [BP+2]
    CALL  __pico8_to_int
    MOV   R0, 0
    MOV   R2, R1
    ILT   R2, 0
    JT    R2, _pico8_dslot_done
    MOV   R2, R1
    IGE   R2, 64
    JT    R2, _pico8_dslot_done
    SHL   R1, 2
    IADD  R1, 0x5E00
    MOV   R0, 1
_pico8_dslot_done:
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; atan2(dx, dy): [BP+2] = dx, [BP+3] = dy -> R0 = the direction in turns,
;; 0 <= a < 1, in screen space (y down, angles anticlockwise), as PICO-8:
;; atan2(1, 0) = 0, atan2(0, -1) = 0.25, atan2(-1, 0) = 0.5,
;; atan2(0, 1) = 0.75. With dx = 0 the result is 0.75 if dy > 0 and 0.25
;; otherwise, so atan2(0, 0) = 0.25 -- PICO-8's own rule (z8lua's
;; pico8_atan2), which also keeps both operands of the CPU's ATAN2 from
;; being zero: that raises a Vircon32 hardware error (ArcTangent2Error).
;; A nil / non-number argument counts as 0.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
__builtin_pico8_atan2:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    MOV   R1, [BP+3]              ; dy
    MOV   R0, R1
    AND   R0, NAN_VALUE
    IEQ   R0, NAN_VALUE
    JF    R0, _pico8_atan2_dy
    MOV   R1, 0.0
_pico8_atan2_dy:
    MOV   R2, [BP+2]              ; dx
    MOV   R0, R2
    AND   R0, NAN_VALUE
    IEQ   R0, NAN_VALUE
    JF    R0, _pico8_atan2_dx
    MOV   R2, 0.0
_pico8_atan2_dx:
    MOV   R0, R2
    FEQ   R0, 0.0                 ; (also true for -0.0)
    JF    R0, _pico8_atan2_general
    MOV   R0, 0.25                ; straight up, or dx = dy = 0
    FGT   R1, 0.0
    JF    R1, _pico8_atan2_done
    MOV   R0, 0.75                ; straight down
    JMP   _pico8_atan2_done
_pico8_atan2_general:
    FSGN  R1                      ; screen y points down
    ATAN2 R1, R2                  ; dx != 0 here, so never ATAN2(0, 0)
    FDIV  R1, 6.2831855           ; radians -> turns
    MOV   R0, R1
    FLT   R0, 0.0
    JF    R0, _pico8_atan2_wrapped
    FADD  R1, 1.0
_pico8_atan2_wrapped:
    MOV   R0, R1
    FGE   R0, 1.0                 ; (-tiny + 1 can round up to 1)
    JF    R0, _pico8_atan2_in_range
    MOV   R1, 0.0
_pico8_atan2_in_range:
    FADD  R1, 0.0                 ; -0 -> 0
    MOV   R0, R1
_pico8_atan2_done:
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; ===========================================================================
;; __builtin_pico8_split1(s, sep, conv): split() for a one-character separator
;; on a string, in one pass. The Lua version called sub(s, i, i) for every
;; character, and each sub() measures the whole NUL-terminated string first:
;; quadratic, ~7M cycles for a 2 KB font string (ppwr.p8's poke(0x5600,
;; unpack(split(font)))). Tokens that read as numbers become numbers unless
;; conv is false (PICO-8's split rule, as __p8_conv).
;;   [BP+2] s   [BP+3] sep (1 char)   [BP+4] conv
;; Locals: [BP-1] table  [BP-2] scan  [BP-3] token start  [BP-4] sep char
;;         [BP-5] count  [BP-6] convert?  [BP-7] token end  [BP-8] token value
;; Returns the table in R0; preserves R1-R6.
;; ===========================================================================
__builtin_pico8_split1:
    PUSH  BP
    MOV   BP, SP
    ISUB  SP, 8                   ; [BP-8]: the token's value
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    PUSH  R6

    CALL  __builtin_table_new
    MOV   [BP-1], R0
    MOV   R0, [BP+3]
    CALL  __unbox_string
    MOV   R1, [R0]
    MOV   [BP-4], R1
    MOV   R0, [BP+2]
    CALL  __unbox_string
    MOV   [BP-2], R0
    MOV   [BP-3], R0
    MOV   R1, 0
    MOV   [BP-5], R1
    MOV   R1, [BP+4]
    IEQ   R1, BOXED_FALSE
    XOR   R1, 1                   ; convert unless conv == false
    MOV   [BP-6], R1

_p8split_loop:
    MOV   R1, [BP-2]
    MOV   R2, [R1]
    MOV   R3, R2
    IEQ   R3, 0
    JT    R3, _p8split_last
    MOV   R4, [BP-4]
    IEQ   R2, R4
    JF    R2, _p8split_next
    MOV   [BP-7], R1
    CALL  _p8split_token
    MOV   R1, [BP-2]
    IADD  R1, 1
    MOV   [BP-3], R1
_p8split_next:
    MOV   R1, [BP-2]
    IADD  R1, 1
    MOV   [BP-2], R1
    JMP   _p8split_loop

_p8split_last:
    MOV   [BP-7], R1
    CALL  _p8split_token
    MOV   R0, [BP-1]
    POP   R6
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; one token, [BP-3] .. [BP-7] (exclusive): copied to a new RAM string,
;; converted, stored at t[++count]. Runs in the frame above.
_p8split_token:
    MOV   R1, [BP-7]
    MOV   R2, [BP-3]
    ISUB  R1, R2                  ; length
    IADD  R1, 1
    PUSH  R1
    CALL  __malloc
    IADD  SP, 1
    MOV   R1, R0
    IEQ   R1, 0
    JT    R1, _p8split_token_done ; out of memory: token dropped
    MOV   R2, [BP-3]
    MOV   R3, [BP-7]
    MOV   R4, R0
_p8split_copy:
    MOV   R5, R2
    ILT   R5, R3
    JF    R5, _p8split_copied
    MOV   R5, [R2]
    MOV   [R4], R5
    IADD  R2, 1
    IADD  R4, 1
    JMP   _p8split_copy
_p8split_copied:
    MOV   R5, 0
    MOV   [R4], R5
    OR    R0, BOXED_RAMSTRING
    MOV   [BP-8], R0              ; (string_to_number uses R1-R6 as scratch)
    MOV   R1, [BP-6]
    JF    R1, _p8split_store
    PUSH  R0
    CALL  __builtin_string_to_number
    IADD  SP, 1
    MOV   R1, R0
    IEQ   R1, BOXED_NIL
    JT    R1, _p8split_store
    ;; snap to PICO-8's 16.16 grid, as number literals are (parser.y)
    FMUL  R0, 65536.0
    FADD  R0, 0.5
    FLR   R0
    FDIV  R0, 65536.0
    MOV   [BP-8], R0
_p8split_store:
    MOV   R6, [BP-8]
    MOV   R1, [BP-5]
    IADD  R1, 1
    MOV   [BP-5], R1
    CIF   R1
    MOV   R2, [BP-1]
    PUSH  R2
    PUSH  R1
    PUSH  R6
    CALL  __builtin_table_set
    IADD  SP, 3
_p8split_token_done:
    RET

;; __builtin_pico8_menu_hook(fn): the pause menu to run on Start (see
;; __builtin_pico8_pause_check); nil removes it.
__builtin_pico8_menu_hook:
    PUSH  BP
    MOV   BP, SP
    MOV   R0, [BP+2]
    PUSH  R1
    MOV   R1, R0
    IEQ   R1, BOXED_NIL
    JF    R1, _pico8_menu_hook_set
    MOV   R0, 0
_pico8_menu_hook_set:
    MOV   [PICO8_MENU_HOOK], R0
    POP   R1
    MOV   R0, BOXED_NIL
    MOV   SP, BP
    POP   BP
    RET

;; __builtin_pico8_start_pressed(): true on the first check after Start
;; goes down (the pause's own edge detector), for the pause menu.
__builtin_pico8_start_pressed:
    PUSH  R1
    IN    R1, INP_SelectedGamepad
    PUSH  R1
    CALL  __pico8_start_edge
    POP   R1
    OUT   INP_SelectedGamepad, R1
    POP   R1
    JT    R0, _pico8_start_pressed_yes
    MOV   R0, BOXED_FALSE
    RET
_pico8_start_pressed_yes:
    MOV   R0, BOXED_TRUE
    RET
