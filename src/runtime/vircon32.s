;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Vircon32 Native Runtime Subroutines
;; spr(), btn(), btnp() implementations for v32lua compiler
;;
;; These subroutines are called by the compiler-generated code when
;; neither PICO-8 nor TIC-80 compatibility modes are enabled.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ============================================================================
;; Button State Tracking Memory (for btnp edge detection)
;; ============================================================================
;; We need to track the previous frame's button state for each button on each
;; gamepad to detect edge presses.
;;
;; This CANNOT be a statically-declared data label in this file. Everything
;; assembled from this source -- code and any ".fill"/"integer"-style static
;; data alike -- ends up in the cartridge's ROM image at V32_CART_PAGE
;; (0x20000000+), which is read-only. A previous version of this file
;; declared __vircon32_btn_prev_state as static data right here, which
;; assembled fine but faulted the first time __builtin_vircon32_btnp below
;; tried to write to it at runtime (MOV [Rd], Rs against a ROM address).
;;
;; An earlier fix for that routed this through a lazy __malloc the first
;; time btnp() ran (mirroring __builtin_table_new's lazy-allocate pattern).
;; That's the right shape for something whose size depends on what the Lua
;; program does at runtime -- but this table's size is fixed at compile
;; time (always exactly 44 words, known before a single byte of Lua runs),
;; so heap allocation was solving a problem this doesn't have: it added an
;; OOM path, a register just to hold the pointer, and a pointer indirection
;; that a compile-time-fixed table never needed. This version instead
;; reserves 44 words of RAM directly in the compiler's fixed global layout
;; -- the same mechanism HEAP_POINTER/FTOA_SCRATCH_PTR_A/B already use,
;; just a wider slice of it. That requires two small additions on the
;; compiler side (v32lua.c) -- no malloc/heap involvement at all:
;;
;;   1. Add a global to remember the reserved base address, near
;;      RuntimeRequirements/CompilerConfig (context.h/.c):
;;          int vircon32_btn_prev_state_base = -1; // -1 = not reserved
;;
;;   2. Reserve the 44 words when this mode is active -- in the semantic
;;      analyzer stage, alongside the existing TIC80_MAP_BUFFER_PTR /
;;      PICO8_MAP_BUFFER_PTR reservations (~v32lua.c:11705-11721), BEFORE
;;      register_all_globals_prepass() runs so user globals land after it:
;;          if (runtime_req.needs_vircon32)
;;          {
;;              vircon32_btn_prev_state_base = next_ram_address;
;;              next_ram_address             = next_ram_address + 44;
;;          }
;;
;;   3. Emit its %define -- in emit_variable_map(), right after
;;      FTOA_SCRATCH_PTR_B (~v32lua.c:1890):
;;          if (vircon32_btn_prev_state_base != -1) {
;;              fprintf (out(), "%%define  VIRCON32_BTN_PREV_STATE  0x%.8X\n",
;;                       vircon32_btn_prev_state_base);
;;          }
;;
;;   4. Zero-initialize it at startup -- in generate_global_setup(), right
;;      after the FTOA_SCRATCH_PTR_A/B zero-inits (~v32lua.c:3020). Unlike
;;      those two (which MUST start at exactly 0 because a lazy-allocate
;;      check reads them), this is just for a clean first frame -- a stale
;;      nonzero value here would only cost btnp() one wrong edge on frame
;;      0, never a crash -- so skipping this step is a correctness nicety,
;;      not a safety requirement, if you'd rather not spend the few extra
;;      instructions:
;;          if (vircon32_btn_prev_state_base != -1) {
;;              emit_asm ("MOV R1, VIRCON32_BTN_PREV_STATE ; zero-init btnp() prev-state table\n");
;;              emit_asm ("MOV R2, 44\n");
;;              emit_asm ("MOV R3, 0.0\n");
;;              emit_asm ("__vircon32_btn_prev_state_zero_loop:\n");
;;              emit_asm ("JF R2, __vircon32_btn_prev_state_zero_done\n");
;;              emit_asm ("MOV [R1], R3\n");
;;              emit_asm ("IADD R1, 1\n");
;;              emit_asm ("ISUB R2, 1\n");
;;              emit_asm ("JMP __vircon32_btn_prev_state_zero_loop\n");
;;              emit_asm ("__vircon32_btn_prev_state_zero_done:\n");
;;          }
;;
;; Layout: 44 words (4 gamepads * 11 buttons, one word each) starting at
;; VIRCON32_BTN_PREV_STATE + (gamepad * 11 + button). Each entry stores 1.0
;; if that button was pressed last frame, 0.0 if not (floats, to match
;; Lua's number representation in v32lua).
;;
;; ============================================================================
;; __builtin_vircon32_spr: Sprite drawing -- dispatches, at RUNTIME, to the
;; cheapest GPU draw command the actual scale/angle values allow
;; ============================================================================
;; Stack layout relative to BP:
;; [BP+2]: region_id
;; [BP+3]: x
;; [BP+4]: y
;; [BP+5]: scale_x    (default 1.0)
;; [BP+6]: scale_y    (default 1.0)
;; [BP+7]: angle_deg  (default 0.0, degrees)
;; [BP+8]: color_mult (default 0xFFFFFFFF)
;; [BP+9]: blend_mode (default VIRCON32_BLEND_ALPHA)
;;
;; Vircon32's GPU exposes four region-draw commands, each consulting only
;; the transform state relevant to it:
;;   GPUCommand_DrawRegion            -- position only
;;   GPUCommand_DrawRegionZoomed      -- position + scale
;;   GPUCommand_DrawRegionRotated     -- position + angle
;;   GPUCommand_DrawRegionRotozoomed  -- position + scale + angle
;;
;; The compiler-side emitter (emit_vircon32_spr_intrinsic in v32lua.c) always
;; calls this one routine now, unconditionally pushing all 8 stack args (any
;; not supplied in the Lua call already default to 1.0/1.0/0.0/0xFFFFFFFF/
;; ALPHA there). Rather than a caller having to spell out scale_x/scale_y/
;; angle_deg pushing this call down a fixed, compile-time-chosen path (which
;; used to force the expensive Rotozoomed command even for a literal
;; spr(id, x, y, 1.0, 1.0, 0)), this routine reads the actual runtime values
;; of scale_x/scale_y/angle_deg and picks Plain/Zoomed/Rotated/Rotozoomed
;; every time it runs, based on what they actually equal.
;;
;; color_mult and blend_mode are handled unconditionally, before the
;; scale/angle dispatch: GPU_MultiplyColor and GPU_ActiveBlending are
;; independent, persistent GPU state that (as far as this audit can tell)
;; every DrawRegion* variant consults regardless of which one is used, so
;; they're always set here rather than left as whatever a *previous* draw
;; call happened to leave behind. GPU_DrawingScaleX/Y/Angle, by contrast,
;; are only written in the branches that actually need them -- leaving them
;; stale is fine there, since e.g. DrawRegionRotated is defined to ignore
;; ScaleX/Y entirely; that's the reason the 4 separate commands exist.
;;
;; (The "color/blend apply to every variant" assumption is inferred from the
;; GPU port layout in v32lua.h, not verified against Vircon32 GPU source --
;; worth confirming if you have it handy.)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_vircon32_spr:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Set region ---
    MOV   R1, [BP+2]        ; region_id
    CFI   R1
    OUT   GPU_SelectedRegion, R1

    ;; --- 2. Set position ---
    MOV   R1, [BP+3]        ; x
    CFI   R1
    OUT   GPU_DrawingPointX, R1

    MOV   R1, [BP+4]        ; y
    CFI   R1
    OUT   GPU_DrawingPointY, R1

    ;; --- 3. Set color multiply / blending (applies to every draw variant) ---
    ;; color_mult travels across the calling convention as a Lua float, like
    ;; every other spr() argument (its default push is literally
    ;; "MOV R0, 4294967295.000000"). But GPU_MultiplyColor is a packed RGBA
    ;; INTEGER port, and 4294967295.0 isn't exactly representable in a
    ;; 32-bit float (24-bit mantissa can't hold 2^32-1) -- it rounds up to
    ;; 4294967296.0, whose bit pattern is 0x4F800000, not 0xFFFFFFFF. OUT-ing
    ;; that raw float bit pattern was corrupting the multiply color on every
    ;; single spr() call (including fully-default ones), which is almost
    ;; certainly why nothing was visible. CFI here converts the numeric
    ;; value to its integer bit pattern first, same as blend_mode below --
    ;; CFI on 4294967295.0 wraps to the 2's-complement bits for -1, which
    ;; are bit-for-bit 0xFFFFFFFF, the correct "no change" multiply color.
    MOV   R1, [BP+8]        ; color_mult (RGBA, packed as an int)
    CFI   R1
    OUT   GPU_MultiplyColor, R1

    MOV   R1, [BP+9]        ; blend_mode
    CFI   R1
    OUT   GPU_ActiveBlending, R1

    ;; --- 4. Decide which draw command the runtime values actually need ---
    ;; R2 = scale_x, R3 = scale_y, R4 = angle_deg -- kept live and never
    ;; themselves compared (only disposable copies in R5 are), so all three
    ;; are still available afterward to write out to GPU_DrawingScaleX/Y/
    ;; Angle if a transform turns out to be needed.
    MOV   R2, [BP+5]        ; scale_x
    MOV   R3, [BP+6]        ; scale_y
    MOV   R4, [BP+7]        ; angle_deg

    MOV   R5, R2
    FEQ   R5, 1.0
    JF    R5, _vircon32_spr_scaled        ; scale_x != 1.0 -> scaled
    MOV   R5, R3
    FEQ   R5, 1.0
    JF    R5, _vircon32_spr_scaled        ; scale_y != 1.0 -> scaled
    JMP   _vircon32_spr_check_angle_only  ; scale is default either way

_vircon32_spr_scaled:
    MOV   R5, R4
    FEQ   R5, 0.0
    JT    R5, _vircon32_spr_zoomed_only   ; angle == 0 -> scale only
    JMP   _vircon32_spr_rotozoomed        ; both scale and angle differ

_vircon32_spr_check_angle_only:
    MOV   R5, R4
    FEQ   R5, 0.0
    JT    R5, _vircon32_spr_plain         ; angle == 0 too -> fully default
    ;; falls through: scale is default, angle differs -> rotated only

_vircon32_spr_rotated_only:
    FMUL  R4, 0.017453292519943295 ; degrees -> radians
    OUT   GPU_DrawingAngle, R4
    OUT   GPU_Command, GPUCommand_DrawRegionRotated
    JMP   _vircon32_spr_end

_vircon32_spr_zoomed_only:
    OUT   GPU_DrawingScaleX, R2
    OUT   GPU_DrawingScaleY, R3
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed
    JMP   _vircon32_spr_end

_vircon32_spr_rotozoomed:
    OUT   GPU_DrawingScaleX, R2
    OUT   GPU_DrawingScaleY, R3
    FMUL  R4, 0.017453292519943295 ; degrees -> radians
    OUT   GPU_DrawingAngle, R4
    OUT   GPU_Command, GPUCommand_DrawRegionRotozoomed
    JMP   _vircon32_spr_end

_vircon32_spr_plain:
    OUT   GPU_Command, GPUCommand_DrawRegion

_vircon32_spr_end:
    MOV   SP, BP
    POP   BP
    RET

;; NOTE: __builtin_vircon32_spr_rotozoom used to live here as a separate
;; routine, called only when the compiler saw scale_x/scale_y/angle_deg
;; written out explicitly in the source spr() call. Its logic (set scale,
;; set angle, set color/blend, GPUCommand_DrawRegionRotozoomed) is now the
;; _vircon32_spr_rotozoomed branch inside __builtin_vircon32_spr above --
;; reached by runtime value, not by which arguments were textually present
;; -- so the standalone routine was folded in and removed rather than kept
;; as dead code. emit_vircon32_spr_intrinsic() in v32lua.c must be updated
;; to match (always `CALL __builtin_vircon32_spr`, dropping the
;; needs_rotozoom branch) -- see the accompanying note on that change.

;; ============================================================================
;; __builtin_vircon32_btn: Check if button is currently pressed
;; ============================================================================
;; Stack layout relative to BP:
;; [BP+2]: button_id (0-10)
;; [BP+3]: player (gamepad index 0-3 as float, or BOXED_NIL for current)
;;
;; Returns BOXED_TRUE or BOXED_FALSE in R0
;;
;; Button IDs (Vircon32 IOPorts order):
;;   0 = Left, 1 = Right, 2 = Up, 3 = Down
;;   4 = Start, 5 = A, 6 = B, 7 = X, 8 = Y
;;   9 = L (Left Shoulder), 10 = R (Right Shoulder)
;;
;; NOTE: Vircon32 comparison instructions are strictly 2-operand and
;; DESTRUCTIVE -- "OP Rd, Src" computes (Rd OP Src) and overwrites Rd with
;; the 0/1 boolean result. Any register whose value must survive a compare
;; has to be re-copied into a scratch register before each compare, which is
;; why button_id/player are kept in R1/R2 and only ever compared via a
;; throwaway copy in R2/R3.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_vircon32_btn:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Get button_id and validate range (0-10) ---
    MOV   R1, [BP+2]
    CFI   R1

    ;; Validate: 0 <= button_id <= 10   (R1 preserved via R2/R3 copies)
    MOV   R2, R1
    ILT   R2, 0              ; R2 = (button_id < 0)
    MOV   R3, R1
    IGT   R3, 10             ; R3 = (button_id > 10)
    OR    R2, R3
    JT    R2, _vircon32_btn_invalid

    ;; --- 2. Handle player parameter ---
    ;; If player is BOXED_NIL, use current gamepad (don't write to INP_SelectedGamepad)
    ;; Otherwise, set INP_SelectedGamepad to the specified player
    MOV   R2, [BP+3]
    MOV   R3, R2
    IEQ   R3, BOXED_NIL
    JT    R3, _vircon32_btn_use_current_gamepad

    ;; Player specified - convert to int and set it
    CFI   R2
    OUT   INP_SelectedGamepad, R2
    JMP   _vircon32_btn_check_button

_vircon32_btn_use_current_gamepad:
    ;; Use whatever gamepad is already selected - do nothing

_vircon32_btn_check_button:
    ;; --- 3. Map button_id to IOPort and read state ---
    ;; Chain of copy+compare+branch: comparisons are destructive and
    ;; 2-operand only, so R2 is a disposable scratch copy of R1 each time.

    MOV   R2, R1
    IEQ   R2, 0
    JT    R2, _vircon32_btn_read_left
    MOV   R2, R1
    IEQ   R2, 1
    JT    R2, _vircon32_btn_read_right
    MOV   R2, R1
    IEQ   R2, 2
    JT    R2, _vircon32_btn_read_up
    MOV   R2, R1
    IEQ   R2, 3
    JT    R2, _vircon32_btn_read_down
    MOV   R2, R1
    IEQ   R2, 4
    JT    R2, _vircon32_btn_read_start
    MOV   R2, R1
    IEQ   R2, 5
    JT    R2, _vircon32_btn_read_a
    MOV   R2, R1
    IEQ   R2, 6
    JT    R2, _vircon32_btn_read_b
    MOV   R2, R1
    IEQ   R2, 7
    JT    R2, _vircon32_btn_read_x
    MOV   R2, R1
    IEQ   R2, 8
    JT    R2, _vircon32_btn_read_y
    MOV   R2, R1
    IEQ   R2, 9
    JT    R2, _vircon32_btn_read_l
    MOV   R2, R1
    IEQ   R2, 10
    JT    R2, _vircon32_btn_read_r

    JMP   _vircon32_btn_invalid

_vircon32_btn_read_left:
    IN    R2, INP_GamepadLeft
    JMP   _vircon32_btn_eval
_vircon32_btn_read_right:
    IN    R2, INP_GamepadRight
    JMP   _vircon32_btn_eval
_vircon32_btn_read_up:
    IN    R2, INP_GamepadUp
    JMP   _vircon32_btn_eval
_vircon32_btn_read_down:
    IN    R2, INP_GamepadDown
    JMP   _vircon32_btn_eval
_vircon32_btn_read_start:
    IN    R2, INP_GamepadButtonStart
    JMP   _vircon32_btn_eval
_vircon32_btn_read_a:
    IN    R2, INP_GamepadButtonA
    JMP   _vircon32_btn_eval
_vircon32_btn_read_b:
    IN    R2, INP_GamepadButtonB
    JMP   _vircon32_btn_eval
_vircon32_btn_read_x:
    IN    R2, INP_GamepadButtonX
    JMP   _vircon32_btn_eval
_vircon32_btn_read_y:
    IN    R2, INP_GamepadButtonY
    JMP   _vircon32_btn_eval
_vircon32_btn_read_l:
    IN    R2, INP_GamepadButtonL
    JMP   _vircon32_btn_eval
_vircon32_btn_read_r:
    IN    R2, INP_GamepadButtonR

_vircon32_btn_eval:
    ;; Vircon32 returns >0 for pressed, <=0 for not pressed
    IGE   R2, 1
    JT    R2, _vircon32_btn_true

_vircon32_btn_false:
_vircon32_btn_invalid:
    MOV   R0, BOXED_FALSE
    JMP   _vircon32_btn_end

_vircon32_btn_true:
    MOV   R0, BOXED_TRUE

_vircon32_btn_end:
    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_vircon32_btnp: Check if button was pressed THIS frame (edge)
;; ============================================================================
;; Stack layout relative to BP:
;; [BP+2]: button_id (0-10)
;; [BP+3]: player (gamepad index 0-3 as float, or BOXED_NIL for current)
;;
;; Uses VIRCON32_BTN_PREV_STATE -- a fixed, compiler-reserved 44-word RAM
;; range (see the big comment at the top of this file) -- to track state
;; from the previous frame. Returns true only on the frame transition from
;; NOT pressed to pressed.
;;
;; Returns BOXED_TRUE or BOXED_FALSE in R0
;;
;; NOTE: same 2-operand/destructive-compare constraint as __builtin_vircon32_btn
;; above -- button_id lives in R1, player lives in R4, and every compare goes
;; through a disposable R2/R3/R7 copy so R1/R4 survive to be used afterward
;; as the (player * 11 + button_id) word index into VIRCON32_BTN_PREV_STATE.
;;
;; The player index is also clamped to 0-3 before it's used as an array
;; index -- an out-of-range player (e.g. a caller passing a bad explicit
;; value) would otherwise compute an address outside the 44-word prev-state
;; table and corrupt adjacent heap memory. Adjust/remove this clamp if
;; you'd rather treat an out-of-range player as an error some other way.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_vircon32_btnp:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Get button_id and validate range (0-10) ---
    MOV   R1, [BP+2]
    CFI   R1

    ;; Validate: 0 <= button_id <= 10   (R1 preserved via R2/R3 copies)
    MOV   R2, R1
    ILT   R2, 0
    MOV   R3, R1
    IGT   R3, 10
    OR    R2, R3
    JT    R2, _vircon32_btnp_invalid

    ;; --- 2. Handle player parameter ---
    MOV   R2, [BP+3]
    MOV   R3, R2
    IEQ   R3, BOXED_NIL
    JT    R3, _vircon32_btnp_use_current_gamepad

    ;; Player specified - convert to int, save in R4, and set gamepad
    CFI   R2
    MOV   R4, R2            ; Save player index in R4
    OUT   INP_SelectedGamepad, R2
    JMP   _vircon32_btnp_clamp_player

_vircon32_btnp_use_current_gamepad:
    ;; Use current gamepad - read which one is selected
    IN    R4, INP_SelectedGamepad  ; Get current gamepad index

_vircon32_btnp_clamp_player:
    ;; Clamp R4 to 0-3 so the prev-state index below can never run off
    ;; the end of the 44-word table.
    MOV   R2, R4
    ILT   R2, 0
    JT    R2, _vircon32_btnp_player_low
    MOV   R2, R4
    IGT   R2, 3
    JT    R2, _vircon32_btnp_player_high
    JMP   _vircon32_btnp_read_current

_vircon32_btnp_player_low:
    MOV   R4, 0
    JMP   _vircon32_btnp_read_current

_vircon32_btnp_player_high:
    MOV   R4, 3

_vircon32_btnp_read_current:
    ;; R1 = button_id, R4 = player index

    ;; --- 3. Read current button state ---
    MOV   R2, R1
    IEQ   R2, 0
    JT    R2, _vircon32_btnp_read_current_left
    MOV   R2, R1
    IEQ   R2, 1
    JT    R2, _vircon32_btnp_read_current_right
    MOV   R2, R1
    IEQ   R2, 2
    JT    R2, _vircon32_btnp_read_current_up
    MOV   R2, R1
    IEQ   R2, 3
    JT    R2, _vircon32_btnp_read_current_down
    MOV   R2, R1
    IEQ   R2, 4
    JT    R2, _vircon32_btnp_read_current_start
    MOV   R2, R1
    IEQ   R2, 5
    JT    R2, _vircon32_btnp_read_current_a
    MOV   R2, R1
    IEQ   R2, 6
    JT    R2, _vircon32_btnp_read_current_b
    MOV   R2, R1
    IEQ   R2, 7
    JT    R2, _vircon32_btnp_read_current_x
    MOV   R2, R1
    IEQ   R2, 8
    JT    R2, _vircon32_btnp_read_current_y
    MOV   R2, R1
    IEQ   R2, 9
    JT    R2, _vircon32_btnp_read_current_l
    MOV   R2, R1
    IEQ   R2, 10
    JT    R2, _vircon32_btnp_read_current_r

    JMP   _vircon32_btnp_invalid

_vircon32_btnp_read_current_left:
    IN    R2, INP_GamepadLeft
    JMP   _vircon32_btnp_got_current_state
_vircon32_btnp_read_current_right:
    IN    R2, INP_GamepadRight
    JMP   _vircon32_btnp_got_current_state
_vircon32_btnp_read_current_up:
    IN    R2, INP_GamepadUp
    JMP   _vircon32_btnp_got_current_state
_vircon32_btnp_read_current_down:
    IN    R2, INP_GamepadDown
    JMP   _vircon32_btnp_got_current_state
_vircon32_btnp_read_current_start:
    IN    R2, INP_GamepadButtonStart
    JMP   _vircon32_btnp_got_current_state
_vircon32_btnp_read_current_a:
    IN    R2, INP_GamepadButtonA
    JMP   _vircon32_btnp_got_current_state
_vircon32_btnp_read_current_b:
    IN    R2, INP_GamepadButtonB
    JMP   _vircon32_btnp_got_current_state
_vircon32_btnp_read_current_x:
    IN    R2, INP_GamepadButtonX
    JMP   _vircon32_btnp_got_current_state
_vircon32_btnp_read_current_y:
    IN    R2, INP_GamepadButtonY
    JMP   _vircon32_btnp_got_current_state
_vircon32_btnp_read_current_l:
    IN    R2, INP_GamepadButtonL
    JMP   _vircon32_btnp_got_current_state
_vircon32_btnp_read_current_r:
    IN    R2, INP_GamepadButtonR

_vircon32_btnp_got_current_state:
    ;; R2 = current state (>0 for pressed, <=0 for released)
    ;; R1 = button_id, R4 = player index

    ;; Check if currently pressed
    ILE   R2, 0
    JT    R2, _vircon32_btnp_not_pressed

    ;; Button IS currently pressed - check if it was NOT pressed last frame
    ;; Calculate word index: player * 11 + button_id (one word per entry --
    ;; VIRCON32_BTN_PREV_STATE is a fixed compile-time RAM address, not a
    ;; byte offset, so no *4 here despite each entry being a 4-byte float.
    ;; [Rd+N] addressing throughout this VM's runtime -- see e.g. table
    ;; array/hash access in runtime.s -- already steps by whole words per
    ;; unit of N.)
    MOV   R3, R4
    IMUL  R3, 11           ; player * 11
    IADD  R3, R1           ; + button_id

    ;; Load previous state from memory
    MOV   R5, VIRCON32_BTN_PREV_STATE
    IADD  R5, R3           ; Address of this button's previous state
    MOV   R6, [R5]         ; Load previous state (0.0 or 1.0)

    ;; If previous state was 0.0 (not pressed), this is a new press
    MOV   R7, R6
    FEQ   R7, 0.0
    JT    R7, _vircon32_btnp_edge_detected

    ;; Previous state was 1.0 (pressed) - not an edge
    JMP   _vircon32_btnp_no_edge

_vircon32_btnp_not_pressed:
    ;; Button is NOT currently pressed
    ;; Calculate word index (see note above -- no *4)
    MOV   R3, R4
    IMUL  R3, 11
    IADD  R3, R1

    ;; Update state to 0.0 (not pressed)
    MOV   R5, VIRCON32_BTN_PREV_STATE
    IADD  R5, R3
    MOV   R6, 0.0
    MOV   [R5], R6

    MOV   R0, BOXED_FALSE
    JMP   _vircon32_btnp_end

_vircon32_btnp_edge_detected:
    ;; New press detected - update state to 1.0 and return true
    MOV   R3, R4
    IMUL  R3, 11
    IADD  R3, R1

    MOV   R5, VIRCON32_BTN_PREV_STATE
    IADD  R5, R3
    MOV   R6, 1.0
    MOV   [R5], R6

    MOV   R0, BOXED_TRUE
    JMP   _vircon32_btnp_end

_vircon32_btnp_no_edge:
    ;; Button was already pressed - update state (stay at 1.0) and return false
    MOV   R3, R4
    IMUL  R3, 11
    IADD  R3, R1

    MOV   R5, VIRCON32_BTN_PREV_STATE
    IADD  R5, R3
    MOV   R6, 1.0
    MOV   [R5], R6

    MOV   R0, BOXED_FALSE
    JMP   _vircon32_btnp_end

_vircon32_btnp_invalid:
    MOV   R0, BOXED_FALSE

_vircon32_btnp_end:
    MOV   SP, BP
    POP   BP
    RET

