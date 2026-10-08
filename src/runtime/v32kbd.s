;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; v32kbd: keyboard decoder -- key(), keyp(), kbd.*
;;
;; A v32kbd device is a keyboard seen by the console as a gamepad. Its
;; controls, as packed by __v32io_read (v32io.s):
;;
;;   bits 0-1  strobe: Left on the 1st event, Right on the 2nd, Left again...
;;             (a NEW event is a side different from the last one seen)
;;   bit  2    Up: the key was pressed
;;   bit  3    Down: the key was released
;;   bits 4-10 key code (Start = bit 0 of the code ... R = bit 6)
;;
;; At most one event per frame, held until the next one -- so the device
;; must be read on EVERY frame or events are lost. v32kbd.c arranges that:
;; __v32kbd_update (lazy, once per frame) from every builtin here and from
;; the game_loop()/TIC() drivers, __v32kbd_frame_end just before the WAIT
;; of system.wait()/ioports.gpu.sync().
;;
;; Key codes identify KEYS: the unshifted US-layout character for keys that
;; have one ('a'-'z', '0'-'9', space, ` - = [ ] \ ; ' , . /), and for the
;; rest: 1 up, 2 down, 3 left, 4 right, 5 caps lock, 6/7 left/right shift,
;; 8 backspace, 9 tab, 10/11 left/right ctrl, 12 left alt, 13 enter,
;; 14-25 F1-F12, 26 right alt, 27 escape, 28/29 left/right gui, 127 delete.
;;
;; State (fixed RAM, %defines from v32kbd.c):
;;   V32KBD_PORT    gamepad port of the keyboard (raw int 0-3)
;;   V32KBD_STROBE  last strobe side seen (0 none yet, 1 left, 2 right)
;;   V32KBD_POLLED  frame counter at the last read (-1: never)
;;   V32KBD_CAPS    caps lock (0/1), toggled by each caps lock press
;;   V32KBD_HELD    number of keys held
;;   V32KBD_ANYP    frame on which the latest press is visible (keyp())
;;   V32KBD_DOWN    128 words: frame on which each key's press is visible,
;;                  -1 while the key is up
;;   V32KBD_QUEUE   ring of V32KBD_QUEUE_SIZE (64) events for kbd.read() /
;;                  kbd.event(), V32KBD_QHEAD oldest, V32KBD_QCOUNT waiting.
;;                  Entry: code | pressed << 7 | symbol << 8. Full -> new
;;                  events are dropped (as in the C library).
;;
;; "Visible" frame: an event read by __v32kbd_frame_end (right before a
;; WAIT) belongs to the NEXT frame -- that is when the program can act on
;; it -- so keyp() still sees the press there.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ============================================================================
;; __v32kbd_init: startup (generate_global_setup). Preserves R1-R13.
;; ============================================================================
__v32kbd_init:
    MOV   R0, V32KBD_DEFAULT_PORT
    MOV   [V32KBD_PORT], R0
    CALL  __v32kbd_reset
    RET

;; ============================================================================
;; __v32kbd_reset: forget all keys and queued events; the strobe side the
;; device shows now becomes the baseline, so its last event from before
;; (the device keeps it, even across a console reset) is not taken as new.
;; Preserves R1-R13.
;; ============================================================================
__v32kbd_reset:
    PUSH  R1
    PUSH  R2
    PUSH  R3
    MOV   R1, -1
    MOV   R2, V32KBD_DOWN
    MOV   R3, 128
_v32kbd_reset_loop:
    MOV   [R2], R1
    IADD  R2, 1
    ISUB  R3, 1
    JT    R3, _v32kbd_reset_loop
    MOV   [V32KBD_POLLED], R1
    MOV   [V32KBD_ANYP], R1
    MOV   R1, 0
    MOV   [V32KBD_CAPS], R1
    MOV   [V32KBD_HELD], R1
    MOV   [V32KBD_QHEAD], R1
    MOV   [V32KBD_QCOUNT], R1
    MOV   R1, [V32KBD_PORT]
    CALL  __v32io_read
    AND   R0, 3
    MOV   [V32KBD_STROBE], R0
    POP   R3
    POP   R2
    POP   R1
    RET

;; ============================================================================
;; __v32kbd_update: read the keyboard, once per frame (later calls in the
;; same frame return at once). Preserves ALL registers.
;; ============================================================================
__v32kbd_update:
    PUSH  R0
    PUSH  R1
    IN    R0, TIM_FrameCounter
    MOV   R1, [V32KBD_POLLED]
    IEQ   R0, R1
    JT    R0, _v32kbd_update_done
    MOV   R1, 0                     ; events visible this frame
    CALL  __v32kbd_poll
_v32kbd_update_done:
    POP   R1
    POP   R0
    RET

;; ============================================================================
;; __v32kbd_frame_end: read the keyboard right before a WAIT; what arrives
;; is visible on the next frame. Preserves ALL registers (the WAIT it
;; precedes is inline program code).
;; ============================================================================
__v32kbd_frame_end:
    PUSH  R0
    PUSH  R1
    MOV   R1, 1                     ; events visible next frame
    CALL  __v32kbd_poll
    POP   R1
    POP   R0
    RET

;; ============================================================================
;; __v32kbd_poll (internal): read the device, decode a new event if any.
;; In: R1 = 0 (visible this frame) or 1 (next frame). Clobbers R0 only.
;; ============================================================================
__v32kbd_poll:
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    PUSH  R5
    IN    R5, TIM_FrameCounter
    MOV   [V32KBD_POLLED], R5
    IADD  R5, R1                    ; R5 = visible frame

    MOV   R1, [V32KBD_PORT]
    CALL  __v32io_read              ; R0 = packed controls
    MOV   R2, R0
    AND   R2, 3                     ; strobe side
    MOV   R3, R2
    IEQ   R3, 0
    JT    R3, _v32kbd_poll_done     ; no event since power-on
    MOV   R3, R2
    MOV   R4, [V32KBD_STROBE]
    IEQ   R3, R4
    JT    R3, _v32kbd_poll_done     ; same side: no new event
    MOV   [V32KBD_STROBE], R2

    MOV   R1, R0
    SHL   R1, -4
    AND   R1, 127                   ; R1 = key code
    JF    R1, _v32kbd_poll_done     ; code 0 is never sent
    MOV   R2, R1
    IADD  R2, V32KBD_DOWN           ; R2 = &DOWN[code]
    MOV   R3, R0
    AND   R3, 4                     ; Up: pressed
    JF    R3, _v32kbd_poll_release

    ;; --- press ---
    MOV   R3, [R2]
    ILT   R3, 0
    JF    R3, _v32kbd_poll_press_set    ; was already down (no release seen)
    MOV   R3, [V32KBD_HELD]
    IADD  R3, 1
    MOV   [V32KBD_HELD], R3
_v32kbd_poll_press_set:
    MOV   [R2], R5
    MOV   [V32KBD_ANYP], R5
    MOV   R3, R1
    IEQ   R3, 5                     ; caps lock toggles on its press
    JF    R3, _v32kbd_poll_symbol
    MOV   R3, [V32KBD_CAPS]
    XOR   R3, 1
    MOV   [V32KBD_CAPS], R3
_v32kbd_poll_symbol:
    CALL  __v32kbd_symbol           ; R0 = typed character
    MOV   R3, 128                   ; pressed flag
    JMP   _v32kbd_poll_queue

    ;; --- release ---
_v32kbd_poll_release:
    MOV   R3, [R2]
    ILT   R3, 0
    JT    R3, _v32kbd_poll_release_set  ; was not down
    MOV   R3, [V32KBD_HELD]
    ISUB  R3, 1
    MOV   [V32KBD_HELD], R3
_v32kbd_poll_release_set:
    MOV   R3, -1
    MOV   [R2], R3
    MOV   R0, R1                    ; symbol = code
    MOV   R3, 0

    ;; --- queue: R1 = code, R3 = pressed flag, R0 = symbol ---
_v32kbd_poll_queue:
    MOV   R2, [V32KBD_QCOUNT]
    MOV   R4, R2
    IGE   R4, V32KBD_QUEUE_SIZE
    JT    R4, _v32kbd_poll_done     ; full: dropped
    SHL   R0, 8
    OR    R0, R3
    OR    R0, R1
    MOV   R4, [V32KBD_QHEAD]
    IADD  R4, R2
    AND   R4, 63                    ; V32KBD_QUEUE_SIZE - 1
    IADD  R4, V32KBD_QUEUE
    MOV   [R4], R0
    IADD  R2, 1
    MOV   [V32KBD_QCOUNT], R2

_v32kbd_poll_done:
    POP   R5
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    RET

;; ============================================================================
;; __v32kbd_symbol (internal): R1 = key code -> R0 = typed character, with
;; the shift keys and caps lock as they are now (US layout). Keys with no
;; character give their own code. Preserves R1-R13.
;; ============================================================================
__v32kbd_symbol:
    PUSH  R2
    PUSH  R3
    MOV   R2, V32KBD_DOWN
    MOV   R3, [R2+6]
    IGE   R3, 0                     ; left shift down
    MOV   R2, [R2+7]
    IGE   R2, 0                     ; right shift down
    OR    R3, R2                    ; R3 = shift

    MOV   R0, R1
    ILT   R0, 97                    ; 'a'
    JT    R0, _v32kbd_symbol_other
    MOV   R0, R1
    IGT   R0, 122                   ; 'z'
    JT    R0, _v32kbd_symbol_other
    ;; letters: caps lock inverts shift
    MOV   R2, [V32KBD_CAPS]
    IEQ   R2, R3
    MOV   R0, R1
    JT    R2, _v32kbd_symbol_done   ; shift == caps: lowercase
    ISUB  R0, 32
    JMP   _v32kbd_symbol_done

_v32kbd_symbol_other:
    MOV   R0, R1
    JF    R3, _v32kbd_symbol_done
    MOV   R2, __v32kbd_shift_table
    IADD  R2, R1
    MOV   R0, [R2]

_v32kbd_symbol_done:
    POP   R3
    POP   R2
    RET

;; ============================================================================
;; __v32kbd_spec (internal): key() argument -> pair of key codes
;; In:  R1 = the Lua value, R2 = raw int: 0 v32kbd codes, 1 TIC-80 codes
;; Out: R0 = code1 | code2 << 8 (code2 0 for a single key), 0 = no such key
;; v32kbd: 1-127 that key, 128-131 shift / ctrl / alt / gui (either side).
;; TIC-80: 1-94 through __v32kbd_tic80_map. Non-numbers: 0.
;; Preserves R1-R13.
;; ============================================================================
__v32kbd_spec:
    PUSH  R1
    PUSH  R3
    MOV   R0, R1
    AND   R0, NAN_VALUE
    IEQ   R0, NAN_VALUE
    JT    R0, _v32kbd_spec_none     ; nil, strings, tables...
    MOV   R0, R1
    FLT   R0, 0.0
    JT    R0, _v32kbd_spec_none
    MOV   R0, R1
    FGE   R0, 256.0
    JT    R0, _v32kbd_spec_none
    FLR   R1
    CFI   R1
    JT    R2, _v32kbd_spec_tic80

    MOV   R3, R1
    ILT   R3, 128
    JF    R3, _v32kbd_spec_virtual
    MOV   R0, R1                    ; a single key (0 -> none)
    JMP   _v32kbd_spec_done
_v32kbd_spec_virtual:
    MOV   R3, R1
    IGT   R3, 131
    JT    R3, _v32kbd_spec_none
    ISUB  R1, 128
    MOV   R3, __v32kbd_virtual
    IADD  R3, R1
    MOV   R0, [R3]
    JMP   _v32kbd_spec_done

_v32kbd_spec_tic80:
    MOV   R3, R1
    IGT   R3, 94
    JT    R3, _v32kbd_spec_none
    MOV   R3, __v32kbd_tic80_map
    IADD  R3, R1
    MOV   R0, [R3]
    JMP   _v32kbd_spec_done

_v32kbd_spec_none:
    MOV   R0, 0
_v32kbd_spec_done:
    POP   R3
    POP   R1
    RET

;; ============================================================================
;; __v32kbd_down (internal): R1 = pair (from __v32kbd_spec) -> R0 = frame on
;; which the pair went down (the earlier of the two keys held), -1 if
;; neither is held. Preserves R1-R13.
;; ============================================================================
__v32kbd_down:
    PUSH  R1
    PUSH  R2
    PUSH  R3
    MOV   R0, -1
    MOV   R2, R1
    AND   R2, 127                   ; code 1
    JF    R2, _v32kbd_down_second
    IADD  R2, V32KBD_DOWN
    MOV   R0, [R2]
_v32kbd_down_second:
    SHL   R1, -8
    AND   R1, 127                   ; code 2
    JF    R1, _v32kbd_down_done
    IADD  R1, V32KBD_DOWN
    MOV   R2, [R1]
    MOV   R3, R2
    ILT   R3, 0
    JT    R3, _v32kbd_down_done     ; code 2 up
    MOV   R3, R0
    ILT   R3, 0
    JT    R3, _v32kbd_down_take     ; code 1 up
    IMIN  R0, R2                    ; both down: the earlier
    JMP   _v32kbd_down_done
_v32kbd_down_take:
    MOV   R0, R2
_v32kbd_down_done:
    POP   R3
    POP   R2
    POP   R1
    RET

;; __v32kbd_is_any (internal): R1 = key() argument, R2 = code set ->
;; R0 = 1 when it means "any key": nil, or (TIC-80 codes) 0, which is
;; tic_key_unknown -- TIC-80's key(0) is key(). Preserves R1-R13.
__v32kbd_is_any:
    MOV   R0, R1
    IEQ   R0, BOXED_NIL
    JT    R0, _v32kbd_is_any_done
    JF    R2, _v32kbd_is_any_done   ; v32kbd codes: 0 is no key
    PUSH  R1
    CALL  __v32kbd_int
    MOV   R0, R1
    IEQ   R0, 0
    POP   R1
_v32kbd_is_any_done:
    RET

;; __v32kbd_int (internal): R1 = Lua number -> R1 = raw int (floored, clamped
;; to +-2^30); nil / non-numbers -> -1. Clobbers R0 only.
__v32kbd_int:
    MOV   R0, R1
    AND   R0, NAN_VALUE
    IEQ   R0, NAN_VALUE
    JT    R0, _v32kbd_int_none
    MOV   R0, R1
    FLT   R0, -1073741824.0
    JF    R0, _v32kbd_int_lo
    MOV   R1, -1073741824.0
_v32kbd_int_lo:
    MOV   R0, R1
    FGT   R0, 1073741824.0
    JF    R0, _v32kbd_int_hi
    MOV   R1, 1073741824.0
_v32kbd_int_hi:
    FLR   R1
    CFI   R1
    RET
_v32kbd_int_none:
    MOV   R1, -1
    RET

;; ============================================================================
;; __builtin_v32kbd_key: key([k])
;; [BP+2] = key (Lua value; nil = any key), [BP+3] = code set (raw 0 / 1)
;; Returns BOXED_TRUE / BOXED_FALSE. Preserves R1-R13.
;; ============================================================================
__builtin_v32kbd_key:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    CALL  __v32kbd_update
    MOV   R1, [BP+2]
    MOV   R2, [BP+3]
    CALL  __v32kbd_is_any
    JT    R0, _v32kbd_key_any
    CALL  __v32kbd_spec
    MOV   R1, R0
    CALL  __v32kbd_down
    IGE   R0, 0                     ; down frame >= 0: held
    JMP   _v32kbd_key_return
_v32kbd_key_any:
    MOV   R0, [V32KBD_HELD]
    IGT   R0, 0
_v32kbd_key_return:
    IADD  R0, BOXED_FALSE           ; 0/1 -> false/true
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_v32kbd_keyp: keyp([k [, hold, period]])
;; [BP+2] = key (nil = any key), [BP+3] = hold, [BP+4] = period (-1 when
;; not given), [BP+5] = code set (raw 0 / 1). Returns a boxed boolean.
;;
;; TIC-80 semantics (core/io.c tic_api_keyp): true on the frame the key
;; goes down; with hold and period both >= 0, also while it is held, once
;; h >= hold, every frame if period is 0, else whenever h % period == 0 --
;; h = frames held after the first. Without a key: did any key go down
;; this frame (no autorepeat). Same rules as TIC-80 btnp() in tic80.s.
;; Preserves R1-R13.
;; ============================================================================
__builtin_v32kbd_keyp:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    PUSH  R4
    CALL  __v32kbd_update
    IN    R3, TIM_FrameCounter      ; this frame
    MOV   R1, [BP+2]
    MOV   R2, [BP+5]
    CALL  __v32kbd_is_any
    JF    R0, _v32kbd_keyp_key
    MOV   R0, [V32KBD_ANYP]
    IEQ   R0, R3
    JMP   _v32kbd_keyp_return

_v32kbd_keyp_key:
    CALL  __v32kbd_spec
    MOV   R1, R0
    CALL  __v32kbd_down             ; R0 = down frame, -1 = up
    MOV   R1, R0
    ILT   R1, 0
    JT    R1, _v32kbd_keyp_false
    ISUB  R3, R0                    ; h
    MOV   R1, R3
    ILT   R1, 0
    JT    R1, _v32kbd_keyp_false    ; visible from the next frame on
    MOV   R1, R3
    IEQ   R1, 0
    JT    R1, _v32kbd_keyp_true     ; went down this frame

    MOV   R1, [BP+3]
    CALL  __v32kbd_int
    MOV   R4, R1                    ; hold
    ILT   R1, 0
    JT    R1, _v32kbd_keyp_false
    MOV   R1, R3
    ILT   R1, R4
    JT    R1, _v32kbd_keyp_false    ; h < hold
    MOV   R1, [BP+4]
    CALL  __v32kbd_int
    MOV   R4, R1                    ; period
    ILT   R1, 0
    JT    R1, _v32kbd_keyp_false
    MOV   R1, R4
    IEQ   R1, 0
    JT    R1, _v32kbd_keyp_true     ; period 0: every frame
    IMOD  R3, R4
    IEQ   R3, 0
    JT    R3, _v32kbd_keyp_true

_v32kbd_keyp_false:
    MOV   R0, 0
    JMP   _v32kbd_keyp_return
_v32kbd_keyp_true:
    MOV   R0, 1
_v32kbd_keyp_return:
    IADD  R0, BOXED_FALSE
    POP   R4
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_v32kbd_read: kbd.read() / kbd.event()
;; [BP+2] = raw 0: kbd.read()  -- next key PRESS, as its typed character
;;                                (shift / caps lock applied when pressed;
;;                                keys with no character give their code)
;;          raw 1: kbd.event() -- next event of any kind: +code for a
;;                                press, -code for a release (no shift)
;; Returns a number, or nil when nothing is left. Preserves R1-R13.
;; ============================================================================
__builtin_v32kbd_read:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    PUSH  R2
    PUSH  R3
    CALL  __v32kbd_update
_v32kbd_read_next:
    MOV   R1, [V32KBD_QCOUNT]
    JF    R1, _v32kbd_read_empty
    MOV   R2, [V32KBD_QHEAD]
    MOV   R3, R2
    IADD  R3, V32KBD_QUEUE
    MOV   R0, [R3]                  ; entry
    IADD  R2, 1
    AND   R2, 63                    ; V32KBD_QUEUE_SIZE - 1
    MOV   [V32KBD_QHEAD], R2
    ISUB  R1, 1
    MOV   [V32KBD_QCOUNT], R1

    MOV   R1, R0
    AND   R1, 128                   ; pressed?
    MOV   R2, [BP+2]
    JT    R2, _v32kbd_read_event
    JF    R1, _v32kbd_read_next     ; kbd.read() skips releases
    SHL   R0, -8                    ; symbol
    JMP   _v32kbd_read_number
_v32kbd_read_event:
    AND   R0, 127                   ; code
    JT    R1, _v32kbd_read_number
    ISGN  R0                        ; release: negative
_v32kbd_read_number:
    CIF   R0
    JMP   _v32kbd_read_return
_v32kbd_read_empty:
    MOV   R0, BOXED_NIL
_v32kbd_read_return:
    POP   R3
    POP   R2
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; ============================================================================
;; __builtin_v32kbd_port: kbd.port([n])
;; [BP+2] = new port (0-3, clamped) or nil to only read it. Setting it --
;; even to the same port -- starts over (__v32kbd_reset): keys, queue and
;; caps lock are forgotten. Returns the port as a number. Preserves R1-R13.
;; ============================================================================
__builtin_v32kbd_port:
    PUSH  BP
    MOV   BP, SP
    PUSH  R1
    MOV   R1, [BP+2]
    MOV   R0, R1
    IEQ   R0, BOXED_NIL
    JT    R0, _v32kbd_port_get
    CALL  __v32kbd_int
    MOV   R0, 0
    IMAX  R1, R0
    MOV   R0, 3
    IMIN  R1, R0
    MOV   [V32KBD_PORT], R1
    CALL  __v32kbd_reset
_v32kbd_port_get:
    MOV   R0, [V32KBD_PORT]
    CIF   R0
    POP   R1
    MOV   SP, BP
    POP   BP
    RET

;; kbd.capslock() -> boolean. Preserves R1-R13.
__builtin_v32kbd_capslock:
    CALL  __v32kbd_update
    MOV   R0, [V32KBD_CAPS]
    IADD  R0, BOXED_FALSE
    RET

;; kbd.connected() -> boolean: is a device plugged into the keyboard's
;; port. Preserves R1-R13.
__builtin_v32kbd_connected:
    PUSH  R1
    MOV   R1, [V32KBD_PORT]
    CALL  __v32io_connected
    IADD  R0, BOXED_FALSE
    POP   R1
    RET

;; kbd.clear(): drop the unread events (held keys are kept). Preserves
;; R1-R13.
__builtin_v32kbd_clear:
    CALL  __v32kbd_update
    MOV   R0, 0
    MOV   [V32KBD_QCOUNT], R0
    MOV   R0, BOXED_NIL
    RET

;; ============================================================================
;; Tables (cartridge ROM)
;; ============================================================================

;; spec 128-131: either-side modifiers, code1 | code2 << 8
__v32kbd_virtual:
    integer 1798, 2826, 6668, 7452   ; shift 6|7, ctrl 10|11, alt 12|26, gui 28|29

;; the character each code types with shift held (US layout); letters
;; are handled in code (caps lock)
__v32kbd_shift_table:
    integer 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
    integer 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31
    integer 32, 33, 34, 35, 36, 37, 38, 34, 40, 41, 42, 43, 60, 95, 62, 63
    integer 41, 33, 64, 35, 36, 37, 94, 38, 42, 40, 58, 58, 60, 43, 62, 63
    integer 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79
    integer 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 123, 124, 125, 94, 95
    integer 126, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79
    integer 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 123, 124, 125, 126, 127

;; TIC-80 key code (0-94, tic.h tic_keycode) -> pair of v32kbd codes. No
;; v32kbd key for insert, page up/down, home, end (53-57), numpad + and *
;; (89, 91); the other numpad keys share the main keys' codes on v32kbd.
;; ctrl / shift / alt (63-65) are either side, as in TIC-80.
__v32kbd_tic80_map:
    integer 0, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111
    integer 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 48, 49, 50, 51, 52
    integer 53, 54, 55, 56, 57, 45, 61, 91, 93, 92, 59, 39, 96, 44, 46, 47
    integer 32, 9, 13, 8, 127, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 2826
    integer 1798, 6668, 27, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 48
    integer 49, 50, 51, 52, 53, 54, 55, 56, 57, 0, 45, 0, 47, 13, 46

