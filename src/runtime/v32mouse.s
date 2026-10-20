;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; v32mouse: mouse decoder -- mouse(), mouse.*, PICO-8 stat(32..34)
;;
;; A v32mouse device is a mouse seen by the console as a gamepad. Its
;; controls, as packed by __v32io_read (v32io.s):
;;
;;   bit  0/1   X trit:  Left (-) / Right (+)   (never both)
;;   bit  2/3   Y trit:  Up (-) / Down (+)      (never both)
;;   bit  4     Start: middle button
;;   bit  5     A:     left button
;;   bit  6     B:     right button
;;   bit  7/8   X Gray code: X (high), Y (low)
;;   bit  9/10  Y Gray code: L (high), R (low)
;;
;; Each axis is a counter going around 12 positions, one control changing
;; per step (v32io PROTOCOLS.md, lib/mouse.h):
;;
;;   position:  0  1  2 | 3  4  5 | 6  7  8 | 9 10 11
;;   gray:        00    |   01    |   11    |   10
;;   trit:      -  0  + | +  0  - | -  0  + | +  0  -
;;
;; The movement is the change of position since the last read, mod 12, in
;; -5..+5 (6 can't be told from -6: no movement). At rest after power on
;; both counters are at position 1 (nothing pressed).
;;
;; The pointer is kept in the active API's screen units (640x360 native,
;; 240x136 TIC-80, 128x128 PICO-8; %defines from v32mouse.c), moved by
;; steps * scale and kept within bounds.
;;
;; State (fixed RAM, %defines from v32mouse.c):
;;   V32MOUSE_PORT     gamepad port (raw int 0-3)
;;   V32MOUSE_POLLED   frame counter at the last read
;;   V32MOUSE_CONN     connected at the last read (0/1)
;;   V32MOUSE_COUNTX/Y last counter positions (-1: not a valid position)
;;   V32MOUSE_X/Y      pointer (ints); MINX/MINY/MAXX/MAXY its bounds
;;   V32MOUSE_SCALE    units per step
;;   V32MOUSE_BUTTONS  held: 1 left, 2 right, 4 middle
;;   V32MOUSE_PRESSF   3 words (left, right, middle): frame on which each
;;   V32MOUSE_RELF     button's latest press / release is visible
;;   V32MOUSE_DFRAME   frame the movement in DX/DY belongs to
;;
;; Read every frame, like the keyboard (v32kbd.s): __v32mouse_update
;; (lazy, once per frame) from every builtin and the drivers,
;; __v32mouse_frame_end before a WAIT (what it reads is visible on the
;; next frame). Movement is only measured between two reads of a
;; connected device at most 2 frames apart (2 frames at the device's full
;; speed still fit in -5..+5); otherwise the read only sets the baseline --
;; a just-plugged device shows nothing pressed, which says nothing of where
;; its counters are, and frames spent in a pause screen are unknown.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ============================================================================
;; __v32mouse_init: startup (generate_global_setup). Preserves R1-R13.
;; ============================================================================
__v32mouse_init:
    MOV   R0, V32MOUSE_DEFAULT_PORT
    MOV   [V32MOUSE_PORT], R0
    MOV   R0, V32MOUSE_DEF_SCALE
    MOV   [V32MOUSE_SCALE], R0
    MOV   R0, 0
    MOV   [V32MOUSE_MINX], R0
    MOV   [V32MOUSE_MINY], R0
    MOV   R0, V32MOUSE_DEF_MAXX
    MOV   [V32MOUSE_MAXX], R0
    MOV   R0, V32MOUSE_DEF_MAXY
    MOV   [V32MOUSE_MAXY], R0
    MOV   R0, V32MOUSE_DEF_X
    MOV   [V32MOUSE_X], R0
    MOV   R0, V32MOUSE_DEF_Y
    MOV   [V32MOUSE_Y], R0
    CALL  __v32mouse_reset
    RET

;; ============================================================================
;; __v32mouse_reset: forget button edges and movement; the device's current
;; counters and buttons become the baseline. The pointer stays where it is.
;; Preserves R1-R13.
;; ============================================================================
__v32mouse_reset:
    PUSH  R1
    PUSH  R2
    MOV   R1, -1
    MOV   R2, V32MOUSE_PRESSF
    MOV   [R2], R1
    MOV   [R2+1], R1
    MOV   [R2+2], R1
    MOV   R2, V32MOUSE_RELF
    MOV   [R2], R1
    MOV   [R2+1], R1
    MOV   [R2+2], R1
    MOV   [V32MOUSE_DFRAME], R1
    IN    R1, TIM_FrameCounter
    MOV   [V32MOUSE_POLLED], R1

    MOV   R1, [V32MOUSE_PORT]
    CALL  __v32io_connected
    MOV   [V32MOUSE_CONN], R0
    CALL  __v32io_read              ; R0 = packed controls
    MOV   R1, R0
    CALL  __v32mouse_buttons_of
    MOV   [V32MOUSE_BUTTONS], R0
    MOV   R2, 0
    CALL  __v32mouse_counter
    MOV   [V32MOUSE_COUNTX], R0
    MOV   R2, 1
    CALL  __v32mouse_counter
    MOV   [V32MOUSE_COUNTY], R0
    POP   R2
    POP   R1
    RET

;; ============================================================================
;; __v32mouse_update: read the mouse, once per frame (later calls in the
;; same frame return at once). Preserves ALL registers.
;; ============================================================================
__v32mouse_update:
    PUSH  R0
    PUSH  R1
    IN    R0, TIM_FrameCounter
    MOV   R1, [V32MOUSE_POLLED]
    IEQ   R0, R1
    JT    R0, _v32mouse_update_done
    MOV   R1, 0                     ; visible this frame
    CALL  __v32mouse_poll
_v32mouse_update_done:
    POP   R1
    POP   R0
    RET

;; ============================================================================
;; __v32mouse_frame_end: read the mouse right before a WAIT; what it reads
;; is visible on the next frame. Preserves ALL registers.
;; ============================================================================
__v32mouse_frame_end:
    PUSH  R0
    PUSH  R1
    MOV   R1, 1                     ; visible next frame
    CALL  __v32mouse_poll
    POP   R1
    POP   R0
    RET

;; ============================================================================
;; __v32mouse_poll (internal): read the device; update buttons, their edges,
;; the movement and the pointer. In: R1 = 0 (visible this frame) or 1 (the
;; next). Clobbers R0 only.
;; ============================================================================
__v32mouse_poll:
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    PUSH  R6
    PUSH  R7

    IN    R5, TIM_FrameCounter
    MOV   R4, R5
    MOV   R0, [V32MOUSE_POLLED]
    ISUB  R4, R0                    ; R4 = frames since the last read
    MOV   [V32MOUSE_POLLED], R5
    IADD  R5, R1                    ; R5 = visible frame

    ;; --- movement allowed? connected now and before, read <= 2 frames ago
    MOV   R1, [V32MOUSE_PORT]
    CALL  __v32io_connected
    MOV   R6, [V32MOUSE_CONN]
    MOV   [V32MOUSE_CONN], R0
    AND   R6, R0
    ILE   R4, 2
    AND   R6, R4                    ; R6 = 1: measure movement

    CALL  __v32io_read
    MOV   R7, R0                    ; R7 = packed controls

    ;; --- buttons and their edges ---
    MOV   R1, R7
    CALL  __v32mouse_buttons_of     ; R0 = held now
    MOV   R2, [V32MOUSE_BUTTONS]
    MOV   [V32MOUSE_BUTTONS], R0
    MOV   R3, R2
    XOR   R3, R0                    ; changed
    MOV   R4, R3
    AND   R4, R0                    ; R4 = went down
    AND   R3, R2                    ; R3 = went up
    MOV   R1, V32MOUSE_PRESSF
    MOV   R2, V32MOUSE_RELF
    MOV   R0, R4
    AND   R0, 1
    JF    R0, _v32mouse_poll_p1
    MOV   [R1], R5
_v32mouse_poll_p1:
    MOV   R0, R4
    AND   R0, 2
    JF    R0, _v32mouse_poll_p2
    MOV   [R1+1], R5
_v32mouse_poll_p2:
    MOV   R0, R4
    AND   R0, 4
    JF    R0, _v32mouse_poll_r0
    MOV   [R1+2], R5
_v32mouse_poll_r0:
    MOV   R0, R3
    AND   R0, 1
    JF    R0, _v32mouse_poll_r1
    MOV   [R2], R5
_v32mouse_poll_r1:
    MOV   R0, R3
    AND   R0, 2
    JF    R0, _v32mouse_poll_r2
    MOV   [R2+1], R5
_v32mouse_poll_r2:
    MOV   R0, R3
    AND   R0, 4
    JF    R0, _v32mouse_poll_move
    MOV   [R2+2], R5

    ;; --- movement: R3 = X steps, R4 = Y steps ---
_v32mouse_poll_move:
    MOV   R1, R7
    MOV   R2, 0
    CALL  __v32mouse_counter        ; R0 = X position now
    MOV   R3, R0
    MOV   R1, [V32MOUSE_COUNTX]
    MOV   [V32MOUSE_COUNTX], R3
    MOV   R2, R3
    CALL  __v32mouse_steps          ; R0 = steps from R1 to R2
    MOV   R3, R0

    MOV   R1, R7
    MOV   R2, 1
    CALL  __v32mouse_counter        ; R0 = Y position now
    MOV   R4, R0
    MOV   R1, [V32MOUSE_COUNTY]
    MOV   [V32MOUSE_COUNTY], R4
    MOV   R2, R4
    CALL  __v32mouse_steps
    MOV   R4, R0

    JT    R6, _v32mouse_poll_scale
    MOV   R3, 0                     ; baseline only
    MOV   R4, 0
_v32mouse_poll_scale:
    MOV   R0, [V32MOUSE_SCALE]
    IMUL  R3, R0                    ; dx
    IMUL  R4, R0                    ; dy

    ;; --- this frame's movement (several reads can make up one frame) ---
    MOV   R0, [V32MOUSE_DFRAME]
    IEQ   R0, R5
    JT    R0, _v32mouse_poll_add
    MOV   [V32MOUSE_DFRAME], R5
    MOV   R0, 0
    MOV   [V32MOUSE_DX], R0
    MOV   [V32MOUSE_DY], R0
_v32mouse_poll_add:
    MOV   R0, [V32MOUSE_DX]
    IADD  R0, R3
    MOV   [V32MOUSE_DX], R0
    MOV   R0, [V32MOUSE_DY]
    IADD  R0, R4
    MOV   [V32MOUSE_DY], R0

    ;; --- the pointer, within its bounds ---
    MOV   R1, [V32MOUSE_X]
    IADD  R1, R3
    MOV   R2, [V32MOUSE_Y]
    IADD  R2, R4
    CALL  __v32mouse_place

    POP   R7
    POP   R6
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    RET

;; __v32mouse_place (internal): pointer = (R1, R2) (raw ints), kept within
;; the bounds. Clobbers R0 only.
__v32mouse_place:
    PUSH  R1
    PUSH  R2
    MOV   R0, [V32MOUSE_MINX]
    IMAX  R1, R0
    MOV   R0, [V32MOUSE_MAXX]
    IMIN  R1, R0
    MOV   [V32MOUSE_X], R1
    MOV   R0, [V32MOUSE_MINY]
    IMAX  R2, R0
    MOV   R0, [V32MOUSE_MAXY]
    IMIN  R2, R0
    MOV   [V32MOUSE_Y], R2
    POP   R2
    POP   R1
    RET

;; __v32mouse_buttons_of (internal): R1 = packed controls -> R0 = buttons
;; held, 1 left (A), 2 right (B), 4 middle (Start). Preserves R1-R13.
__v32mouse_buttons_of:
    MOV   R0, R1
    SHL   R0, -4
    AND   R0, 7                     ; Start | A << 1 | B << 2
    PUSH  R1
    MOV   R1, __v32mouse_btnmap
    IADD  R0, R1
    POP   R1
    MOV   R0, [R0]
    RET

;; __v32mouse_counter (internal): R1 = packed controls, R2 = 0 (X) or 1 (Y)
;; -> R0 = counter position 0-11, -1 if the controls are no position (both
;; trit controls pressed, which the console never shows). Preserves R1-R13.
__v32mouse_counter:
    PUSH  R3
    PUSH  R4
    MOV   R0, R1
    MOV   R3, R1
    JT    R2, _v32mouse_counter_y
    AND   R0, 3                     ; X trit: Left | Right << 1
    SHL   R3, -7                    ; X Gray: bit 0 high (X), bit 1 low (Y)
    JMP   _v32mouse_counter_index
_v32mouse_counter_y:
    SHL   R0, -2
    AND   R0, 3                     ; Y trit: Up | Down << 1
    SHL   R3, -9                    ; Y Gray: bit 0 high (L), bit 1 low (R)
_v32mouse_counter_index:
    MOV   R4, R3
    AND   R4, 1
    SHL   R4, 3                     ; high -> bit 3
    OR    R0, R4
    MOV   R4, R3
    AND   R4, 2
    SHL   R4, 1                     ; low -> bit 2
    OR    R0, R4
    MOV   R4, __v32mouse_positions
    IADD  R0, R4
    MOV   R0, [R0]
    POP   R4
    POP   R3
    RET

;; __v32mouse_steps (internal): R1 = position before, R2 = after -> R0 =
;; movement -5..+5 (0 if either is -1, or for the ambiguous 6).
;; Preserves R1-R13.
__v32mouse_steps:
    PUSH  R3
    MOV   R0, 0
    MOV   R3, R1
    ILT   R3, 0
    JT    R3, _v32mouse_steps_done
    MOV   R3, R2
    ILT   R3, 0
    JT    R3, _v32mouse_steps_done
    MOV   R0, R2
    ISUB  R0, R1
    IADD  R0, 12                    ; 1..23
    IMOD  R0, 12                    ; 0..11
    MOV   R3, R0
    IEQ   R3, 6
    JF    R3, _v32mouse_steps_sign
    MOV   R0, 0
    JMP   _v32mouse_steps_done
_v32mouse_steps_sign:
    MOV   R3, R0
    IGT   R3, 6
    JF    R3, _v32mouse_steps_done
    ISUB  R0, 12
_v32mouse_steps_done:
    POP   R3
    RET

;; __v32mouse_int (internal): R1 = Lua value -> R1 = raw int (floored,
;; clamped to +-2^30), R0 = 1; R0 = 0 for nil / non-numbers (R1 then
;; unchanged). Preserves R2-R13.
__v32mouse_int:
    MOV   R0, R1
    AND   R0, NAN_VALUE
    IEQ   R0, NAN_VALUE
    JT    R0, _v32mouse_int_none
    MOV   R0, R1
    FLT   R0, -1073741824.0
    JF    R0, _v32mouse_int_lo
    MOV   R1, -1073741824.0
_v32mouse_int_lo:
    MOV   R0, R1
    FGT   R0, 1073741824.0
    JF    R0, _v32mouse_int_hi
    MOV   R1, 1073741824.0
_v32mouse_int_hi:
    FLR   R1
    CFI   R1
    MOV   R0, 1
    RET
_v32mouse_int_none:
    MOV   R0, 0
    RET

;; __v32mouse_edge (internal): R1 = button mask (raw int, 1/2/4), R2 =
;; V32MOUSE_PRESSF or V32MOUSE_RELF -> R0 = 1 if any button in the mask has
;; that edge visible on this frame. Preserves R1-R13.
__v32mouse_edge:
    PUSH  R3
    PUSH  R4
    IN    R3, TIM_FrameCounter
    MOV   R0, R1
    AND   R0, 1
    JF    R0, _v32mouse_edge_1
    MOV   R4, [R2]
    IEQ   R4, R3
    JT    R4, _v32mouse_edge_yes
_v32mouse_edge_1:
    MOV   R0, R1
    AND   R0, 2
    JF    R0, _v32mouse_edge_2
    MOV   R4, [R2+1]
    IEQ   R4, R3
    JT    R4, _v32mouse_edge_yes
_v32mouse_edge_2:
    MOV   R0, R1
    AND   R0, 4
    JF    R0, _v32mouse_edge_no
    MOV   R4, [R2+2]
    IEQ   R4, R3
    JT    R4, _v32mouse_edge_yes
_v32mouse_edge_no:
    MOV   R0, 0
    JMP   _v32mouse_edge_done
_v32mouse_edge_yes:
    MOV   R0, 1
_v32mouse_edge_done:
    POP   R4
    POP   R3
    RET

;; ============================================================================
;; __builtin_v32mouse_mouse: mouse()
;; Returns 7 values, as a Lua call does: R0 = x, R2 = y, R3 = left,
;; MV_BUF[3] = middle, MV_BUF[4] = right, MV_BUF[5] = scroll x,
;; MV_BUF[6] = scroll y (always 0: the protocol has no wheel); RET_COUNT 7.
;; x, y in the API's screen units; buttons are booleans. (TIC-80's
;; mouse(), in every API.) Clobbers R0, R2, R3; preserves R1, R4-R13.
;; ============================================================================
__builtin_v32mouse_mouse:
    PUSH  R1
    CALL  __v32mouse_update
    MOV   R1, MV_BUF
    MOV   R2, [V32MOUSE_BUTTONS]
    MOV   R0, R2
    SHL   R0, -2
    AND   R0, 1
    IADD  R0, BOXED_FALSE
    MOV   [R1+3], R0                ; middle
    MOV   R0, R2
    SHL   R0, -1
    AND   R0, 1
    IADD  R0, BOXED_FALSE
    MOV   [R1+4], R0                ; right
    MOV   R0, 0.0
    MOV   [R1+5], R0                ; scroll x
    MOV   [R1+6], R0                ; scroll y
    MOV   R3, R2
    AND   R3, 1
    IADD  R3, BOXED_FALSE           ; left
    MOV   R2, [V32MOUSE_Y]
    CIF   R2
    MOV   R0, 7
    MOV   [RET_COUNT], R0
    MOV   R0, [V32MOUSE_X]
    CIF   R0
    POP   R1
    RET

;; ============================================================================
;; __builtin_v32mouse_pressed / _released: mouse.pressed([b]) /
;; mouse.released([b]) -- did a button in b (1 left, 2 right, 4 middle, or a
;; sum; nil: any) go down / up this frame. [BP+2] = b. Returns a boolean.
;; Preserves R1-R13.
;; ============================================================================
__builtin_v32mouse_pressed:
    PUSH  BP
    MOV   BP, SP
    PUSH  R2
    MOV   R2, V32MOUSE_PRESSF
    JMP   _v32mouse_edge_common
__builtin_v32mouse_released:
    PUSH  BP
    MOV   BP, SP
    PUSH  R2
    MOV   R2, V32MOUSE_RELF
_v32mouse_edge_common:
    PUSH  R1
    CALL  __v32mouse_update
    MOV   R1, [BP+2]
    CALL  __v32mouse_int
    JT    R0, _v32mouse_edge_mask
    MOV   R1, 7                     ; nil: any button
_v32mouse_edge_mask:
    CALL  __v32mouse_edge
    IADD  R0, BOXED_FALSE
    POP   R1
    POP   R2
    MOV   SP, BP
    POP   BP
    RET

;; mouse.buttons() -> buttons held, 1 left + 2 right + 4 middle. Preserves
;; R1-R13.
__builtin_v32mouse_buttons:
    CALL  __v32mouse_update
    MOV   R0, [V32MOUSE_BUTTONS]
    CIF   R0
    RET

;; ============================================================================
;; __builtin_v32mouse_delta: mouse.delta() -> dx, dy: this frame's movement,
;; in the API's units (R0, R2; RET_COUNT 2). Clobbers R0, R2.
;; ============================================================================
__builtin_v32mouse_delta:
    PUSH  R1
    CALL  __v32mouse_update
    IN    R1, TIM_FrameCounter
    MOV   R0, [V32MOUSE_DFRAME]
    IEQ   R0, R1
    MOV   R2, 0
    JF    R0, _v32mouse_delta_none
    MOV   R0, [V32MOUSE_DX]
    MOV   R2, [V32MOUSE_DY]
    JMP   _v32mouse_delta_done
_v32mouse_delta_none:
    MOV   R0, 0
_v32mouse_delta_done:
    CIF   R0
    CIF   R2
    MOV   R1, 2
    MOV   [RET_COUNT], R1
    POP   R1
    RET

;; ============================================================================
;; __builtin_v32mouse_position: mouse.position([x, y]) -> x, y
;; [BP+2] = x, [BP+3] = y: each one given moves the pointer (floored, kept
;; within the bounds). Returns the pointer (R0, R2; RET_COUNT 2).
;; Clobbers R0, R2.
;; ============================================================================
__builtin_v32mouse_position:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    CALL  __v32mouse_update
    MOV   R1, [BP+2]
    CALL  __v32mouse_int
    JT    R0, _v32mouse_position_x
    MOV   R1, [V32MOUSE_X]
_v32mouse_position_x:
    MOV   R2, R1
    MOV   R1, [BP+3]
    CALL  __v32mouse_int
    JT    R0, _v32mouse_position_y
    MOV   R1, [V32MOUSE_Y]
_v32mouse_position_y:
    MOV   R0, R2
    MOV   R2, R1
    MOV   R1, R0
    CALL  __v32mouse_place
    MOV   R0, [V32MOUSE_X]
    CIF   R0
    MOV   R2, [V32MOUSE_Y]
    CIF   R2
    MOV   R1, 2
    MOV   [RET_COUNT], R1
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_v32mouse_bounds: mouse.bounds(x1, y1, x2, y2) -- the area the
;; pointer stays in, inclusive (each nil keeps its current value); the
;; pointer is moved inside. Returns nil. Preserves R1-R13.
;; ============================================================================
__builtin_v32mouse_bounds:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    MOV   R1, [BP+2]
    CALL  __v32mouse_int
    JF    R0, _v32mouse_bounds_1
    MOV   [V32MOUSE_MINX], R1
_v32mouse_bounds_1:
    MOV   R1, [BP+3]
    CALL  __v32mouse_int
    JF    R0, _v32mouse_bounds_2
    MOV   [V32MOUSE_MINY], R1
_v32mouse_bounds_2:
    MOV   R1, [BP+4]
    CALL  __v32mouse_int
    JF    R0, _v32mouse_bounds_3
    MOV   [V32MOUSE_MAXX], R1
_v32mouse_bounds_3:
    MOV   R1, [BP+5]
    CALL  __v32mouse_int
    JF    R0, _v32mouse_bounds_4
    MOV   [V32MOUSE_MAXY], R1
_v32mouse_bounds_4:
    MOV   R1, [V32MOUSE_X]
    MOV   R2, [V32MOUSE_Y]
    CALL  __v32mouse_place
    MOV   R0, BOXED_NIL
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_v32mouse_scale: mouse.scale([n]) -> units per step. [BP+2] = n
;; (>= 1 sets it). Preserves R1-R13.
;; ============================================================================
__builtin_v32mouse_scale:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    MOV   R1, [BP+2]
    CALL  __v32mouse_int
    JF    R0, _v32mouse_scale_get
    MOV   R0, R1
    ILT   R0, 1
    JT    R0, _v32mouse_scale_get
    MOV   [V32MOUSE_SCALE], R1
_v32mouse_scale_get:
    MOV   R0, [V32MOUSE_SCALE]
    CIF   R0
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_v32mouse_port: mouse.port([n]) -> the mouse's gamepad port.
;; [BP+2] = n (0-3, clamped) moves it there and starts over
;; (__v32mouse_reset: the device's state is the new baseline). Preserves
;; R1-R13.
;; ============================================================================
__builtin_v32mouse_port:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    MOV   R1, [BP+2]
    CALL  __v32mouse_int
    JF    R0, _v32mouse_port_get
    MOV   R0, 0
    IMAX  R1, R0
    MOV   R0, 3
    IMIN  R1, R0
    MOV   [V32MOUSE_PORT], R1
    CALL  __v32mouse_reset
_v32mouse_port_get:
    MOV   R0, [V32MOUSE_PORT]
    CIF   R0
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; mouse.connected() -> is a device plugged into the mouse's port.
;; Preserves R1-R13.
__builtin_v32mouse_connected:
    PUSH  R1
    MOV   R1, [V32MOUSE_PORT]
    CALL  __v32io_connected
    IADD  R0, BOXED_FALSE
    POP   R1
    RET

;; ============================================================================
;; __builtin_v32mouse_stat: the PICO-8 prelude's stat(n) -- its devkit
;; mouse: 32 x, 33 y (0-127), 34 buttons (1 left, 2 right, 4 middle); any
;; other n: 0. [BP+2] = n. Preserves R1-R13.
;; ============================================================================
__builtin_v32mouse_stat:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    CALL  __v32mouse_update
    MOV   R1, [BP+2]
    CALL  __v32mouse_int
    JF    R0, _v32mouse_stat_zero
    MOV   R0, R1
    IEQ   R0, 32
    JT    R0, _v32mouse_stat_x
    MOV   R0, R1
    IEQ   R0, 33
    JT    R0, _v32mouse_stat_y
    MOV   R0, R1
    IEQ   R0, 34
    JT    R0, _v32mouse_stat_b
_v32mouse_stat_zero:
    MOV   R0, 0
    JMP   _v32mouse_stat_done
_v32mouse_stat_x:
    MOV   R0, [V32MOUSE_X]
    JMP   _v32mouse_stat_done
_v32mouse_stat_y:
    MOV   R0, [V32MOUSE_Y]
    JMP   _v32mouse_stat_done
_v32mouse_stat_b:
    MOV   R0, [V32MOUSE_BUTTONS]
_v32mouse_stat_done:
    CIF   R0
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; Tables (cartridge ROM)
;; ============================================================================

;; counter position by Left|Right<<1 (trit) | low<<2 | high<<3 (Gray), -1:
;; both trit controls pressed (never shown by the console)
__v32mouse_positions:
    integer 1, 0, 2, -1, 4, 5, 3, -1, 10, 11, 9, -1, 7, 6, 8, -1

;; buttons by Start|A<<1|B<<2 -> 1 left (A), 2 right (B), 4 middle (Start)
__v32mouse_btnmap:
    integer 0, 4, 1, 5, 2, 6, 3, 7

