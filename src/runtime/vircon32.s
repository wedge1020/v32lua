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
;; Channel-Ownership Tracking Memory (for music.volume()/sfx.volume()'s
;; no-channel "apply to every channel I've used" mode)
;; ============================================================================
;; Two words, VIRCON32_MUSIC_CHANNEL_MASK and VIRCON32_SFX_CHANNEL_MASK,
;; each a 16-bit-relevant bitmask over channels 0-15: bit N set means
;; channel N was last assigned a sound by that namespace's .play(). Written
;; by __builtin_vircon32_play/_sfx_play below (and by the compile-time
;; equivalent in the static-fold path, emit_vircon32_claim_channel_static()
;; in v32lua.c) every time a channel is claimed; read by
;; __builtin_vircon32_volume_mask when music.volume(VOL)/sfx.volume(VOL) is
;; called with no channel argument. These are ordinary fixed RAM words, not
;; a heap allocation -- same reasoning as VIRCON32_BTN_PREV_STATE above:
;; their size (1 word each) is fixed at compile time, so a malloc/heap
;; indirection would be solving a problem this doesn't have.
;;
;; Requires four small additions on the compiler side (v32lua.c), mirroring
;; the VIRCON32_BTN_PREV_STATE additions above:
;;
;;   1. Two globals, in context.c near vircon32_sfx_cursor_base:
;;          int vircon32_music_channel_mask_base = -1;
;;          int vircon32_sfx_channel_mask_base   = -1;
;;
;;   2. Reserve one word each, in main.c, in the same
;;      "if (runtime_req.needs_vircon32)" block that reserves
;;      VIRCON32_BTN_PREV_STATE/VIRCON32_SFX_CURSOR, BEFORE
;;      register_all_globals_prepass() runs:
;;          vircon32_music_channel_mask_base = next_ram_address;
;;          next_ram_address                 = next_ram_address + 1;
;;          vircon32_sfx_channel_mask_base    = next_ram_address;
;;          next_ram_address                  = next_ram_address + 1;
;;
;;   3. Emit their %defines -- in emit_variable_map() (emit.c), right after
;;      VIRCON32_SFX_CURSOR:
;;          fprintf (out(), "%%define  VIRCON32_MUSIC_CHANNEL_MASK 0x%.8X\n",
;;                   vircon32_music_channel_mask_base);
;;          fprintf (out(), "%%define  VIRCON32_SFX_CHANNEL_MASK   0x%.8X\n",
;;                   vircon32_sfx_channel_mask_base);
;;
;;   4. Zero-initialize both at startup -- in generate_global_setup()
;;      (generator.c), right after the VIRCON32_SFX_CURSOR init. UNLIKE the
;;      btnp prev-state table's zero-init (a correctness nicety), this one
;;      matters: a stale nonzero mask would make music.volume()/
;;      sfx.volume()'s no-channel mode apply volume to channels nothing
;;      has actually played on yet.
;;          emit_asm ("MOV R1, 0 ; no channels claimed by either namespace yet\n");
;;          emit_asm ("MOV [VIRCON32_MUSIC_CHANNEL_MASK], R1\n");
;;          emit_asm ("MOV [VIRCON32_SFX_CHANNEL_MASK], R1\n");
;;
;; ============================================================================
;; Memory Card: fixed hardware address range, NOT a compiler-reserved
;; allocation
;; ============================================================================
;; VIRCON32_MEMCARD_BASE (0x30000000), VIRCON32_MEMCARD_DATA_BASE
;; (0x30000014), and VIRCON32_MEMCARD_END (0x3003FFFF) are fixed physical
;; addresses -- unlike everything else on this page, they are NOT reserved
;; out of next_ram_address; they live entirely outside the compiler's RAM
;; pool, the same category as V32_CART_PAGE. This VM is word-addressed
;; throughout (an address unit is one 4-byte word -- see the [Rd+N] note
;; on __builtin_vircon32_btnp below), so VIRCON32_MEMCARD_DATA_BASE sits
;; exactly 20 WORDS past VIRCON32_MEMCARD_BASE: the first 20 words
;; (0x30000000..0x30000013) are the card's title, one word per character
;; (see __builtin_vircon32_memcard_title below), and
;; VIRCON32_MEMCARD_DATA_BASE is where memcard.save()/load()/[pos]'s
;; position 0 lands. Position -1..-20 reach back into the title itself.
;;
;; Requires three %defines on the compiler side, in emit_variable_map()
;; (emit.c), alongside the ones above -- these need no globals and no
;; next_ram_address reservation, since the addresses are fixed constants
;; already available as C #defines in v32lua.h:
;;          fprintf (out(), "%%define  VIRCON32_MEMCARD_BASE      0x%.8X\n",
;;                   VIRCON32_MEMCARD_BASE);
;;          fprintf (out(), "%%define  VIRCON32_MEMCARD_DATA_BASE 0x%.8X\n",
;;                   VIRCON32_MEMCARD_DATA_BASE);
;;          fprintf (out(), "%%define  VIRCON32_MEMCARD_END       0x%.8X\n",
;;                   VIRCON32_MEMCARD_END);
;;
;; See the full compiler-side patch notes for the complete drop-in function
;; bodies all of the above lives inside.
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

;; ============================================================================
;; __builtin_vircon32_play: play a sound on a channel
;; ============================================================================
;; Stack layout relative to BP:
;; [BP+2]: sound      (Lua float resource id, or BOXED_NIL -> nothing to play)
;; [BP+3]: channel    (Lua float 0-15,        or BOXED_NIL -> 0)
;; [BP+4]: chanloop   (any Lua value,         or BOXED_NIL -> false)
;; [BP+5]: chanvol    (Lua float,             or BOXED_NIL -> 1.0)
;; [BP+6]: startindex (Lua float sample index, or BOXED_NIL -> no seek)
;;
;; Returns: R0 = the channel actually used, as a Lua float
;;
;; The compiler-side emitter (emit_vircon32_play_intrinsic in v32lua.c) only
;; calls this when at least one argument is NOT known at compile time. A call
;; whose arguments are all literals -- including a bare --#sound name, which
;; the compiler folds to its resource id -- is emitted as a straight-line OUT
;; sequence instead and never reaches this routine. Both paths emit the SAME
;; port order, and that order is not arbitrary:
;;
;;   1. SPU_SelectedChannel        -- every per-channel port acts on it
;;   2. SPUCommand_StopSelectedChannel
;;   3. SPU_ChannelAssignedSound
;;   4. SPU_ChannelVolume
;;   5. SPUCommand_PlaySelectedChannel
;;   6. SPU_ChannelLoopEnabled     <-- AFTER the play command
;;   7. SPU_ChannelPosition        <-- AFTER the play command
;;
;; Three console behaviours force that shape. All three are silent when you
;; get them wrong -- no error, no port-write rejection, just the wrong sound:
;;
;; A. A SOUND CANNOT BE ASSIGNED TO A BUSY CHANNEL.
;;    WriteSPUChannelAssignedSound() ignores the write outright unless the
;;    channel is Stopped ("sounds can only be assigned to a non playing
;;    channel"). Without the stop at step 2, calling play() with a new sound
;;    on a channel that is still sounding replays the OLD sound. Stopping an
;;    already-idle channel costs nothing.
;;
;; B. THE PLAY COMMAND OVERWRITES THE CHANNEL'S LOOP FLAG.
;;    PlayChannel(), for a Stopped or already-Playing channel, does:
;;        TargetChannel.LoopEnabled = ChannelSound->PlayWithLoop;
;;        TargetChannel.Position    = 0;
;;    so SPU_ChannelLoopEnabled written BEFORE the command is thrown away and
;;    replaced by the SOUND's own PlayWithLoop -- which is false unless
;;    something set SPU_SoundPlayWithLoop on that sound. That is why loop is
;;    written at step 6: by then the channel is Playing and the value sticks.
;;    It is written even when it is 0, because step 5 has just replaced it
;;    with the sound's flag and "no loop argument" must mean no loop.
;;
;; C. THE PLAY COMMAND REWINDS THE CHANNEL.
;;    Same two lines: Position = 0. A seek written before the command is
;;    discarded, so the optional startindex is applied at step 7.
;;
;;    (For a PAUSED channel PlayChannel() takes neither branch -- it just
;;    sets State = Playing -- which is what makes resume() work. So on a
;;    resume neither the loop flag nor the position is disturbed.)
;;
;; SPU_ChannelPosition is an INTEGER port: a sample index, clamped by the
;; console to 0..length-1. It takes CFI like the sound and channel ids, NOT
;; a raw Lua float. SPU_ChannelVolume and SPU_ChannelSpeed are the genuine
;; float ports here.
;;
;; Register use follows __builtin_vircon32_spr/btn/btnp: R1-R3 are used
;; freely without saving, since the emitter frees its registers before the
;; CALL. Comparisons are 2-operand and destructive, so R1 (the channel) is
;; never compared directly -- only disposable copies in R2/R3 are.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_vircon32_play:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Resolve the channel: nil -> 0, otherwise clamp to 0-15 ---
    MOV   R1, [BP+3]
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JT    R2, _vircon32_play_chan_zero

    CFI   R1                      ; Lua float -> hardware integer
    MOV   R2, R1
    ILT   R2, 0
    JT    R2, _vircon32_play_chan_zero
    MOV   R2, R1
    IGT   R2, 15
    JF    R2, _vircon32_play_chan_ready
    MOV   R1, 15                  ; clamp high
    JMP   _vircon32_play_chan_ready

_vircon32_play_chan_zero:
    MOV   R1, 0                   ; nil or negative -> channel 0

_vircon32_play_chan_ready:
    OUT   SPU_SelectedChannel, R1

    ;; --- 2. Fetch the sound; a nil sound leaves the channel alone ---
    MOV   R2, [BP+2]
    MOV   R3, R2
    IEQ   R3, BOXED_NIL
    JT    R3, _vircon32_play_done

    ;; --- 3. Stop, THEN assign (see note A above) ---
    OUT   SPU_Command, SPUCommand_StopSelectedChannel
    CFI   R2
    OUT   SPU_ChannelAssignedSound, R2

    ;; --- 3b. Track channel ownership: claim R1 for music, release it from
    ;; sfx if sfx had it. See emit_vircon32_claim_channel_static() in
    ;; v32lua.c (intrinsics_vircon32_sound.c) for the mirror-image
    ;; compile-time version of this, used by the static-fold path this
    ;; routine's dynamic path complements. R1 (channel) must survive this;
    ;; R2 held the sound value, already OUT'd above and not needed again
    ;; until step 4 re-fetches it from the stack, so R2/R3 are free scratch
    ;; here. VIRCON32_MUSIC_CHANNEL_MASK/VIRCON32_SFX_CHANNEL_MASK are new
    ;; compiler-reserved RAM words -- see the header comment block at the
    ;; top of this file for the v32lua.c-side additions they require.
    MOV   R2, 1
    SHL   R2, R1                        ; R2 = 1 << channel
    MOV   R3, [VIRCON32_MUSIC_CHANNEL_MASK]
    OR    R3, R2
    MOV   [VIRCON32_MUSIC_CHANNEL_MASK], R3

    MOV   R3, R2
    NOT   R3                            ; R3 = ~(1 << channel)
    MOV   R2, [VIRCON32_SFX_CHANNEL_MASK]
    AND   R2, R3
    MOV   [VIRCON32_SFX_CHANNEL_MASK], R2

    ;; --- 4. Channel volume: nil -> 1.0 (true float port, no cast) ---
    MOV   R2, [BP+5]
    MOV   R3, R2
    IEQ   R3, BOXED_NIL
    JF    R3, _vircon32_play_vol_ready
    MOV   R2, 1.0

_vircon32_play_vol_ready:
    OUT   SPU_ChannelVolume, R2

    ;; --- 5. Start playback ---
    OUT   SPU_Command, SPUCommand_PlaySelectedChannel

    ;; --- 6. Loop flag, AFTER the play command (see note B above) ---
    ;; Lua truthiness: only nil and false are falsy; every number, 0
    ;; included, is truthy.
    MOV   R2, [BP+4]
    MOV   R3, R2
    IEQ   R3, BOXED_NIL
    JT    R3, _vircon32_play_loop_off
    MOV   R3, R2
    IEQ   R3, BOXED_FALSE
    JT    R3, _vircon32_play_loop_off

    OUT   SPU_ChannelLoopEnabled, 1
    JMP   _vircon32_play_seek

_vircon32_play_loop_off:
    OUT   SPU_ChannelLoopEnabled, 0

    ;; --- 7. Optional seek, AFTER the play command (see note C above) ---
_vircon32_play_seek:
    MOV   R2, [BP+6]
    MOV   R3, R2
    IEQ   R3, BOXED_NIL
    JT    R3, _vircon32_play_done
    CFI   R2                      ; integer sample index, not a float
    OUT   SPU_ChannelPosition, R2

_vircon32_play_done:
    ;; Return the channel actually used, as a Lua number, so callers can
    ;; write  local ch = play(MUSIC)  and later  stop(ch).
    MOV   R0, R1
    CIF   R0

    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_vircon32_chancmd: issue an SPU command at a channel, or globally
;; ============================================================================
;; Stack layout relative to BP:
;; [BP+2]: channel      (Lua float 0-15, or BOXED_NIL -> apply to all channels)
;; [BP+3]: selected_cmd (raw SPU command integer, used when a channel is given)
;; [BP+4]: all_cmd      (raw SPU command integer, used when channel is nil)
;;
;; Returns: R0 = BOXED_NIL
;;
;; This one routine backs stop(), pause() and resume(): the three differ only
;; in which command pair the compiler pushes.
;;
;;   stop(ch)    StopSelectedChannel     stop()    StopAllChannels
;;   pause(ch)   PauseSelectedChannel    pause()   PauseAllChannels
;;   resume(ch)  PlaySelectedChannel     resume()  ResumeAllChannels
;;
;; resume(ch) uses Play rather than a "resume selected channel" command
;; because the console has no such command. PlayChannel() leaves a PAUSED
;; channel's position and loop flag untouched and simply sets it Playing, so
;; Play IS the per-channel resume. (ResumeAllChannels is literally a loop
;; calling PlayChannel on every paused channel.)
;;
;; Note that Play only resumes a channel that is genuinely PAUSED. On a
;; STOPPED channel it rewinds to 0 and restarts -- so a "resume" that
;; restarts from the beginning means the channel had stopped, not paused.
;; The usual cause is a sound that ran to its end because its loop flag was
;; lost; see note B on __builtin_vircon32_play above.
;;
;; The two command arguments are pushed by the compiler as raw hardware
;; integers (MOV R0, SPUCommand_...), not as Lua floats, so they are OUT-ed
;; directly with no CFI.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_vircon32_chancmd:
    PUSH  BP
    MOV   BP, SP

    MOV   R1, [BP+2]
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JT    R2, _vircon32_chancmd_all

    ;; --- A channel was named: select it, clamping to 0-15 first ---
    CFI   R1
    MOV   R2, R1
    ILT   R2, 0
    JT    R2, _vircon32_chancmd_low
    MOV   R2, R1
    IGT   R2, 15
    JT    R2, _vircon32_chancmd_high
    JMP   _vircon32_chancmd_selected

_vircon32_chancmd_low:
    MOV   R1, 0
    JMP   _vircon32_chancmd_selected

_vircon32_chancmd_high:
    MOV   R1, 15

_vircon32_chancmd_selected:
    OUT   SPU_SelectedChannel, R1
    MOV   R2, [BP+3]
    OUT   SPU_Command, R2
    JMP   _vircon32_chancmd_done

_vircon32_chancmd_all:
    MOV   R2, [BP+4]
    OUT   SPU_Command, R2

_vircon32_chancmd_done:
    MOV   R0, BOXED_NIL

    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_vircon32_sfx_play: fire a transient sound effect
;; ============================================================================
;; Stack layout relative to BP:
;; [BP+2]: sound   (Lua float resource id, or BOXED_NIL -> nothing to play)
;; [BP+3]: channel (Lua float 0-15, or BOXED_NIL -> allocate one)
;; [BP+4]: volume  (Lua float,      or BOXED_NIL -> 1.0)
;; [BP+5]: speed   (Lua float,      or BOXED_NIL -> 1.0)
;;
;; Returns: R0 = the channel actually used, as a Lua float
;;
;; Port order is the same as __builtin_vircon32_play and for the same three
;; reasons -- stop before assigning (a sound only assigns to a stopped
;; channel), and clear the loop flag AFTER the play command (which overwrites
;; it from the sound's own PlayWithLoop). See the notes on that routine.
;;
;; CHANNEL ALLOCATION
;; ------------------
;; With no channel given, the next one is taken from VIRCON32_SFX_CURSOR, a
;; single compiler-reserved RAM word cycling over channels 1-15. Channel 0 is
;; never handed out, so music.play() on the default channel is never cut off
;; by a sound effect.
;;
;; The cursor is advanced unconditionally rather than searching for a channel
;; that is actually idle. Searching would cost up to 15 IN + compare on the
;; hot path -- sfx.play() runs on every jump and footstep -- to protect
;; against a case that only arises when 15 effects overlap, at which point
;; the oldest is the right one to lose anyway.
;;
;; The cursor holds a plain hardware integer, not a Lua float: nothing but
;; this routine ever reads it. generate_global_setup() initialises it to 1.
;;
;; Register use follows the other __builtin_vircon32_* routines: R1-R3 used
;; freely without saving, since the emitter frees its registers before the
;; CALL. Comparisons are 2-operand and destructive, so R1 (the channel) is
;; only ever compared through a throwaway copy.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_vircon32_sfx_play:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Resolve the channel ---
    MOV   R1, [BP+3]
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JT    R2, _vircon32_sfx_auto_channel

    ;; Explicit channel: cast and clamp to 0-15
    CFI   R1
    MOV   R2, R1
    ILT   R2, 0
    JT    R2, _vircon32_sfx_clamp_low
    MOV   R2, R1
    IGT   R2, 15
    JF    R2, _vircon32_sfx_channel_ready
    MOV   R1, 15
    JMP   _vircon32_sfx_channel_ready

_vircon32_sfx_clamp_low:
    MOV   R1, 0
    JMP   _vircon32_sfx_channel_ready

_vircon32_sfx_auto_channel:
    ;; Take the cursor, then advance it with wrap 1 -> 15 -> 1
    MOV   R1, [VIRCON32_SFX_CURSOR]

    MOV   R2, R1
    IADD  R2, 1
    MOV   R3, R2
    IGT   R3, 15
    JF    R3, _vircon32_sfx_store_cursor
    MOV   R2, 1

_vircon32_sfx_store_cursor:
    MOV   [VIRCON32_SFX_CURSOR], R2

_vircon32_sfx_channel_ready:
    OUT   SPU_SelectedChannel, R1

    ;; --- 2. Fetch the sound; a nil sound leaves the channel alone ---
    MOV   R2, [BP+2]
    MOV   R3, R2
    IEQ   R3, BOXED_NIL
    JT    R3, _vircon32_sfx_done

    ;; --- 3. Stop, THEN assign ---
    OUT   SPU_Command, SPUCommand_StopSelectedChannel
    CFI   R2
    OUT   SPU_ChannelAssignedSound, R2

    ;; --- 3b. Track channel ownership: claim R1 for sfx, release it from
    ;; music if music had it. Mirror image of the block in
    ;; __builtin_vircon32_play above -- see the notes there. R1 (channel)
    ;; must survive this; R2/R3 are free scratch (R2's sound value was
    ;; already OUT'd above, and gets re-fetched from the stack at step 4).
    MOV   R2, 1
    SHL   R2, R1                        ; R2 = 1 << channel
    MOV   R3, [VIRCON32_SFX_CHANNEL_MASK]
    OR    R3, R2
    MOV   [VIRCON32_SFX_CHANNEL_MASK], R3

    MOV   R3, R2
    NOT   R3                            ; R3 = ~(1 << channel)
    MOV   R2, [VIRCON32_MUSIC_CHANNEL_MASK]
    AND   R2, R3
    MOV   [VIRCON32_MUSIC_CHANNEL_MASK], R2

    ;; --- 4. Volume: nil -> 1.0 (true float port, no cast) ---
    MOV   R2, [BP+4]
    MOV   R3, R2
    IEQ   R3, BOXED_NIL
    JF    R3, _vircon32_sfx_volume_ready
    MOV   R2, 1.0

_vircon32_sfx_volume_ready:
    OUT   SPU_ChannelVolume, R2

    ;; --- 5. Speed / pitch: nil -> 1.0 (float port, console clamps 0-128) ---
    MOV   R2, [BP+5]
    MOV   R3, R2
    IEQ   R3, BOXED_NIL
    JF    R3, _vircon32_sfx_speed_ready
    MOV   R2, 1.0

_vircon32_sfx_speed_ready:
    OUT   SPU_ChannelSpeed, R2

    ;; --- 6. Start, then clear the loop flag the command just set ---
    OUT   SPU_Command, SPUCommand_PlaySelectedChannel
    OUT   SPU_ChannelLoopEnabled, 0

_vircon32_sfx_done:
    ;; Return the channel used, as a Lua number, so the caller can hold on to
    ;; it (local ch = sfx.play(ENGINE) ... sfx.stop(ch)).
    MOV   R0, R1
    CIF   R0

    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_vircon32_sfx_stop_all: stop channels 1-15, leaving 0 alone
;; ============================================================================
;; Takes no arguments. Returns R0 = BOXED_NIL.
;;
;; This is what bare sfx.stop() compiles to. It deliberately does NOT use
;; SPUCommand_StopAllChannels: that would stop channel 0 as well and cut the
;; music, which is the one thing a caller asking to silence sound EFFECTS
;; does not mean.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_vircon32_sfx_stop_all:
    PUSH  BP
    MOV   BP, SP

    MOV   R1, 1

_vircon32_sfx_stop_loop:
    OUT   SPU_SelectedChannel, R1
    OUT   SPU_Command, SPUCommand_StopSelectedChannel

    IADD  R1, 1
    MOV   R2, R1
    IGT   R2, 15
    JF    R2, _vircon32_sfx_stop_loop

    MOV   R0, BOXED_NIL

    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_vircon32_volume: set one channel's volume, or the true global
;; volume when the channel is -1
;; ============================================================================
;; Stack layout relative to BP:
;; [BP+2]: volume  (Lua float, or BOXED_NIL -> 1.0 default)
;; [BP+3]: channel (Lua float; -1 -> SPU_GlobalVolume, else clamped 0-15)
;;
;; Returns: R0 = BOXED_NIL
;;
;; Backs music.volume(VOL, CHANNEL)/sfx.volume(VOL, CHANNEL) when CHANNEL
;; was written explicitly at the call site (as opposed to omitted, which
;; goes to __builtin_vircon32_volume_mask instead -- see that routine).
;; The compiler-side emitter (emit_vircon32_volume_intrinsic in v32lua.c,
;; file intrinsics_vircon32_sound.c) only reaches THIS routine when the
;; volume and/or the channel value isn't known at compile time; an
;; all-literal call folds to a straight-line OUT sequence instead.
;;
;; CHANNEL is guaranteed by the emitter to be a real (non-nil) expression
;; here -- "no channel argument at all" is a different call site entirely.
;; The BOXED_NIL check on volume is kept anyway as a cheap defensive
;; default, same as every other optional numeric argument in this file.
;;
;; SPU_ChannelVolume (per-channel, clamped 0-8 by the console) and
;; SPU_GlobalVolume (clamped 0-2) are both genuine float ports -- the Lua
;; volume value is used directly, no CFI. The channel argument, when it
;; isn't -1, takes the same clamp-to-0-15 treatment as every other
;; per-channel routine in this file (see __builtin_vircon32_play/_chancmd/
;; _sfx_play above).
;;
;; Register use follows the other __builtin_vircon32_* routines: R1-R3 used
;; freely without saving, since the emitter frees its registers before the
;; CALL. R1 holds the resolved volume and is never itself compared -- only
;; the disposable copies in R2/R3 are, since IEQ/ILT/IGT are destructive.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_vircon32_volume:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Resolve the volume: nil -> 1.0 ---
    MOV   R1, [BP+2]
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JF    R2, _vircon32_volume_val_ready
    MOV   R1, 1.0

_vircon32_volume_val_ready:
    ;; --- 2. Channel == -1 -> global volume; otherwise clamp and select ---
    MOV   R2, [BP+3]
    CFI   R2                      ; Lua float -> hardware integer
    MOV   R3, R2
    IEQ   R3, -1
    JT    R3, _vircon32_volume_global

    MOV   R3, R2
    ILT   R3, 0
    JT    R3, _vircon32_volume_chan_low
    MOV   R3, R2
    IGT   R3, 15
    JF    R3, _vircon32_volume_chan_ready
    MOV   R2, 15                  ; clamp high
    JMP   _vircon32_volume_chan_ready

_vircon32_volume_chan_low:
    MOV   R2, 0                   ; clamp low

_vircon32_volume_chan_ready:
    OUT   SPU_SelectedChannel, R2
    OUT   SPU_ChannelVolume, R1
    JMP   _vircon32_volume_done

_vircon32_volume_global:
    OUT   SPU_GlobalVolume, R1

_vircon32_volume_done:
    MOV   R0, BOXED_NIL

    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_vircon32_volume_mask: apply a volume to every channel a
;; namespace's channel-ownership mask currently marks as claimed
;; ============================================================================
;; Stack layout relative to BP:
;; [BP+2]: volume    (Lua float, or BOXED_NIL -> 1.0 default)
;; [BP+3]: mask_addr (raw hardware integer -- the RAM address of either
;;                    VIRCON32_MUSIC_CHANNEL_MASK or VIRCON32_SFX_CHANNEL_MASK,
;;                    pushed by the compiler as a literal, NOT a Lua value)
;;
;; Returns: R0 = BOXED_NIL
;;
;; Backs music.volume(VOL)/sfx.volume(VOL) called with NO channel argument
;; at all. The mask is a 16-bit-relevant bitmask, bit N set meaning channel
;; N was last assigned a sound by THIS namespace's .play() (see
;; emit_vircon32_claim_channel_static() in v32lua.c, and the matching
;; inline claim/release block in __builtin_vircon32_play/_sfx_play above,
;; for how the mask gets populated). Every set bit's channel gets its
;; SPU_ChannelVolume written; an empty mask (nothing has played on this
;; namespace yet) makes this a no-op, which is the correct behaviour --
;; there is nothing to apply the volume to.
;;
;; This intentionally does NOT touch SPU_GlobalVolume. Reaching the true
;; global port is music.volume(VOL, -1)/sfx.volume(VOL, -1), handled by
;; __builtin_vircon32_volume above instead.
;;
;; Register use: R1 = resolved volume (kept live, never compared directly).
;; R2 = mask address, then free once the mask value is loaded into R3
;; (kept live for the whole loop). R4 = channel counter 0-15 (kept live).
;; R5/R6/R7 are throwaway per-iteration scratch.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_vircon32_volume_mask:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Resolve the volume: nil -> 1.0 ---
    MOV   R1, [BP+2]
    MOV   R2, R1
    IEQ   R2, BOXED_NIL
    JF    R2, _vircon32_volmask_val_ready
    MOV   R1, 1.0

_vircon32_volmask_val_ready:
    ;; --- 2. Load this namespace's channel-ownership mask ---
    MOV   R2, [BP+3]              ; mask RAM address (raw hardware int)
    MOV   R3, [R2]                ; mask value: bit N set = channel N is ours

    ;; --- 3. For each set bit 0-15, select that channel and set its volume ---
    MOV   R4, 0                   ; channel counter

_vircon32_volmask_loop:
    MOV   R5, R4
    IGE   R5, 16
    JT    R5, _vircon32_volmask_done

    MOV   R6, 1
    SHL   R6, R4                  ; R6 = 1 << channel
    MOV   R7, R3
    AND   R7, R6
    JF    R7, _vircon32_volmask_next   ; bit clear -> not ours, skip

    OUT   SPU_SelectedChannel, R4
    OUT   SPU_ChannelVolume, R1

_vircon32_volmask_next:
    IADD  R4, 1
    JMP   _vircon32_volmask_loop

_vircon32_volmask_done:
    MOV   R0, BOXED_NIL

    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_vircon32_memcard_title: set the memcard's title, one word per
;; character, into the first VIRCON32_MEMCARD_TITLE_DISPLAY_WORDS (16) of
;; the 20-word title block. The last 4 words (VIRCON32_MEMCARD_DATA_BASE-4
;; .. VIRCON32_MEMCARD_DATA_BASE-1) are reserved metadata -- see the header
;; comment block near the top of this file -- and are never touched here.
;; ============================================================================
;; Stack layout relative to BP:
;; [BP+2]: title string (boxed, ROM or RAM)
;;
;; Returns: R0 = BOXED_NIL
;;
;; Truncates to 16 characters if the string is longer; zero-pads the
;; remainder of the 16 if shorter. One word per character, matching this
;; VM's own internal string representation (see __builtin_string_len) --
;; NOT a packed byte string.
;;
;; Register use: R1 = source pointer (from __unbox_string). R2 = dest
;; pointer, starts at VIRCON32_MEMCARD_BASE. R3 = characters written so
;; far (0-16). R4/R5 are per-iteration scratch.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_vircon32_memcard_title:
    PUSH  BP
    MOV   BP, SP

    MOV   R0, [BP+2]
    CALL  __unbox_string           ; R0 = raw char-array address
    MOV   R1, R0                   ; R1 = source pointer

    MOV   R2, VIRCON32_MEMCARD_BASE   ; R2 = dest pointer (title start)
    MOV   R3, 0                    ; R3 = characters written so far

_memcard_title_copy_loop:
    MOV   R4, R3
    IGE   R4, 16
    JT    R4, _memcard_title_done     ; wrote all 16 -> nothing to pad either
    MOV   R4, [R1]
    IEQ   R4, 0
    JT    R4, _memcard_title_pad_loop ; hit NUL -> pad the remainder with 0
    MOV   R4, [R1]                    ; IEQ above clobbered R4 with its 0/1
                                       ; result -- reload the real character
    ;; Character words in this VM's internal string storage are raw
    ;; hardware-integer ASCII codes, NOT boxed Lua floats (see
    ;; string.byte()'s own CIF on this exact read, __builtin_string_byte
    ;; above). CIF it here so a title word reads back through
    ;; memcard.load()/memcard[pos] as the same value string.byte() would
    ;; report, not a raw bit pattern.
    CIF   R4
    MOV   [R2], R4
    IADD  R1, 1
    IADD  R2, 1
    IADD  R3, 1
    JMP   _memcard_title_copy_loop

_memcard_title_pad_loop:
    MOV   R4, R3
    IGE   R4, 16
    JT    R4, _memcard_title_done
    MOV   R5, 0
    MOV   [R2], R5
    IADD  R2, 1
    IADD  R3, 1
    JMP   _memcard_title_pad_loop

_memcard_title_done:
    MOV   R0, BOXED_NIL

    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_vircon32_memcard_append: memcard.save(value) with NO position
;; -- auto-append through the persistent on-card cursor
;; ============================================================================
;; Stack layout relative to BP:
;; [BP+2]: value (any Lua value)
;;
;; Returns: R0 = value, unchanged (same "returns what you gave" convention
;; as memcard.save(value, position) and play()/sfx.play() elsewhere).
;;
;; THE CURSOR (VIRCON32_MEMCARD_CURSOR_ADDR, the memcard's own last title
;; word) is a raw hardware integer -- a WORD OFFSET from
;; VIRCON32_MEMCARD_DATA_BASE, NOT a Lua value -- and lives ON THE CARD
;; ITSELF, not in Vircon32 RAM. That is the entire point: it survives a
;; reboot, so repeated no-position saves keep extending a log across many
;; play sessions instead of overwriting position 0 every single run. A
;; blank/never-written card reads this word as its all-zero bit pattern,
;; which is exactly the float 0.0 -- so a fresh card's cursor starts at 0
;; with no separate "is this formatted" check needed.
;;
;; ENTRY FORMAT written at the cursor's current word:
;;   Real Lua string (ROM or RAM):  [TAG_STRING][length][char words...]
;;                                  -- 2 + length words total.
;;   Everything else (number,
;;   boolean, nil, table, function): [TAG_SCALAR][raw boxed value]
;;                                  -- 2 words total. A table/function is
;;                                  stored as a raw pointer here, same
;;                                  within-a-run-only caveat as the
;;                                  explicit-position save form -- see the
;;                                  safety note in v32lua.c.
;;
;; The classification test (real ROM/RAM string vs. everything else) is
;; the same tag+payload check __builtin_strcat uses to decide whether an
;; operand needs tostring() coercion -- see that routine above for the
;; original.
;;
;; CALL-CLOBBERS-EVERYTHING DISCIPLINE: this routine calls
;; __builtin_string_len and __unbox_string internally. Per this file's
;; standing rule (plain registers do not survive a CALL), every value that
;; must outlive one of those calls is PUSHed onto the stack as a local
;; instead of being trusted to survive in a register -- old_cursor at
;; [BP-1], base_addr at [BP-2], and (string path only) length at [BP-3].
;; These are never individually POPped; MOV SP, BP at the end discards
;; them wholesale, which is safe regardless of which path was taken.
;;
;; UNVERIFIED: written to the same standard as the rest of this file, but
;; not yet run through v32sim. Flagging per this project's usual
;; verification discipline.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_vircon32_memcard_append:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Read the persistent on-card cursor ---
    ;; Stored as a real Lua number (see the CIF at the bottom of this
    ;; routine) so memcard.load(-1)/memcard[-1] can read it back directly
    ;; like any other value -- CFI it back to a raw hardware int here for
    ;; this routine's own arithmetic.
    MOV   R1, [VIRCON32_MEMCARD_CURSOR_ADDR]
    CFI   R1
    PUSH  R1                            ; [BP-1] = old_cursor

    ;; --- 2. This entry's base address, saturated to stay on-card ---
    MOV   R2, VIRCON32_MEMCARD_DATA_BASE
    IADD  R2, R1
    MOV   R3, R2
    IGT   R3, VIRCON32_MEMCARD_END
    JF    R3, _memcard_append_addr_ok
    MOV   R2, VIRCON32_MEMCARD_END      ; card is full: keep overwriting the last slot
_memcard_append_addr_ok:
    PUSH  R2                            ; [BP-2] = base_addr

    ;; --- 3. Classify the value: real string, or anything else ---
    MOV   R1, [BP+2]
    MOV   R3, R1
    AND   R3, BOXED_DATA
    IEQ   R3, BOXED_ROMSTRING
    JT    R3, _memcard_append_is_string
    IEQ   R3, BOXED_RAMSTRING
    JF    R3, _memcard_append_scalar
    MOV   R3, R1
    AND   R3, BOXED_PAYLOAD
    ILT   R3, 4                         ; payload < 4 -> nil/true/false, not a real string
    JT    R3, _memcard_append_scalar
    JMP   _memcard_append_is_string

_memcard_append_scalar:
    ;; --- SCALAR PATH: [TAG_SCALAR][raw value] -- 2 words ---
    ;; The tag is written as a proper Lua number (CIF'd) so a caller can
    ;; compare "memcard.load(pos) == 0" directly, the same way any other
    ;; memcard word behaves -- a bare hardware-integer 0 happens to share
    ;; 0.0's all-zero bit pattern, so this CIF is a no-op for TAG_SCALAR
    ;; specifically, but it's here for symmetry with TAG_STRING below,
    ;; where the equivalent CIF is NOT a no-op.
    MOV   R5, [BP-2]                    ; base_addr
    MOV   R7, 0                         ; TAG_SCALAR
    CIF   R7
    MOV   [R5], R7
    IADD  R5, 1
    MOV   R6, [BP+2]                    ; the value itself is already a
    MOV   [R5], R6                      ; properly boxed Lua value -- no CIF

    MOV   R1, [BP-1]                    ; old_cursor
    IADD  R1, 2                         ; new_cursor = old_cursor + 2
    JMP   _memcard_append_store_cursor

_memcard_append_is_string:
    ;; --- STRING PATH: [TAG_STRING][length][char words...] ---
    MOV   R0, [BP+2]
    PUSH  R0
    CALL  __builtin_string_len          ; R0 = length, boxed
    IADD  SP, 1
    CFI   R0                            ; R0 = length, hardware integer
    PUSH  R0                            ; [BP-3] = length (raw int -- loop counter)

    MOV   R0, [BP+2]
    CALL  __unbox_string                ; R0 = raw char-array pointer
    MOV   R4, R0                        ; R4 = source pointer (no more CALLs after this)

    MOV   R5, [BP-2]                    ; R5 = dest pointer, starts at base_addr
    MOV   R6, [BP-3]                    ; R6 = remaining char count (raw int)

    ;; TAG_STRING (1) and the length word both need CIF before storage --
    ;; unlike TAG_SCALAR's 0, a raw hardware integer 1 (0x00000001) is a
    ;; completely different bit pattern from the Lua float 1.0
    ;; (0x3F800000), so without this a caller comparing
    ;; "memcard.load(pos) == 1" against an unconverted tag would never
    ;; match.
    MOV   R7, 1
    CIF   R7                            ; TAG_STRING, as a real Lua number
    MOV   [R5], R7
    IADD  R5, 1

    MOV   R7, R6                        ; a COPY of the length -- R6 itself
    CIF   R7                            ; stays a raw int; the loop below
    MOV   [R5], R7                      ; still needs it that way
    IADD  R5, 1

_memcard_append_str_copy:
    MOV   R7, R6
    IEQ   R7, 0
    JT    R7, _memcard_append_str_done
    ;; Character words in this VM's internal string storage are raw
    ;; hardware-integer ASCII codes, NOT boxed Lua floats -- confirmed by
    ;; string.byte()'s own CIF on this exact read (see __builtin_string_
    ;; byte above). Copying them verbatim would embed that same raw-int
    ;; mismatch into the memcard; CIF each one on the way in so
    ;; memcard.load() at a char's position reads back the same value
    ;; string.byte() would report for it.
    MOV   R7, [R4]
    CIF   R7
    MOV   [R5], R7
    IADD  R4, 1
    IADD  R5, 1
    ISUB  R6, 1
    JMP   _memcard_append_str_copy

_memcard_append_str_done:
    MOV   R1, [BP-1]                    ; old_cursor
    IADD  R1, 2                         ; +tag +length words
    MOV   R6, [BP-3]                    ; original length
    IADD  R1, R6                        ; new_cursor = old_cursor + 2 + length

_memcard_append_store_cursor:
    ;; Best-effort saturate: once a no-position save would run the cursor
    ;; past the end of the card, pin it at the last valid data offset so
    ;; every further no-position save just keeps overwriting that final
    ;; slot instead of the cursor wandering out of range forever. This
    ;; clamp compares raw hardware integers -- CIF happens AFTER, right
    ;; before the store.
    MOV   R3, R1
    MOV   R2, VIRCON32_MEMCARD_END
    ISUB  R2, VIRCON32_MEMCARD_DATA_BASE
    IGT   R3, R2
    JF    R3, _memcard_append_cursor_ok
    MOV   R1, R2
_memcard_append_cursor_ok:
    CIF   R1                            ; store as a real Lua number --
    MOV   [VIRCON32_MEMCARD_CURSOR_ADDR], R1  ; see the read at the top

    ;; --- Return the original value, matching save()'s convention ---
    MOV   R0, [BP+2]

    MOV   SP, BP
    POP   BP
    RET

