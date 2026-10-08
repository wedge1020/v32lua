;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; v32io: gamepad group read
;;
;; Devices that tunnel their own data through a gamepad port (v32kbd now,
;; v32mouse later) all start the same way: read the 11 controls of THEIR
;; gamepad as one packed word, without disturbing the gamepad the program
;; has selected. This module is only that read; each device's decoder
;; (v32kbd.s, ...) takes the word from here.
;;
;; It also owns gamepad SELECTION. The desktop and simplified emulators
;; return garbage when INP_SelectedGamepad is read (ReadPort sets the
;; result, then falls through to the per-gamepad port array and reads
;; PortArray[-1]), so code that must put the program's selection back can't
;; ask the port. Every runtime/compiler write of INP_SelectedGamepad goes
;; through __v32io_select (or also stores V32IO_GAMEPAD), and the selection
;; is read from V32IO_GAMEPAD instead. (A __rawasm__ OUT to the port
;; bypasses this and leaves V32IO_GAMEPAD stale.)
;;
;; Always emitted (btn() of every API selects through it); the group read
;; is only called by v32kbd.s, emitted when the program uses the keyboard.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ============================================================================
;; __v32io_select: select a gamepad, and remember it
;; ============================================================================
;; In: R1 = gamepad (raw int). 0-3: selected, and stored in V32IO_GAMEPAD;
;; anything else is ignored, as the hardware ignores it.
;; Preserves ALL registers.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__v32io_select:
    PUSH  R0
    MOV   R0, R1
    ILT   R0, 0
    JT    R0, _v32io_select_done
    MOV   R0, R1
    IGT   R0, 3
    JT    R0, _v32io_select_done
    OUT   INP_SelectedGamepad, R1
    MOV   [V32IO_GAMEPAD], R1
_v32io_select_done:
    POP   R0
    RET

;; ============================================================================
;; __v32io_read: every control of one gamepad, one bit each
;; ============================================================================
;; In:  R1 = gamepad port (raw int 0-3)
;; Out: R0 = packed controls, 1 = pressed (port value > 0):
;;
;;        bit  0  Left       bit  4  Start      bit  8  Y
;;        bit  1  Right      bit  5  A          bit  9  L
;;        bit  2  Up         bit  6  B          bit 10  R
;;        bit  3  Down       bit  7  X
;;
;;      i.e. bit n = INP port 0x402 + n -- the same packing as the v32kbd
;;      C library's v32kbd_scan() (NOT ioports.inp.inputs, whose order is
;;      reversed for the gamepad API).
;; The program's selected gamepad (V32IO_GAMEPAD) is selected again
;; afterwards. Preserves R1-R13.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__v32io_read:
    PUSH  R2
    PUSH  R3
    MOV   R3, [V32IO_GAMEPAD]
    OUT   INP_SelectedGamepad, R1

    IN    R0, INP_GamepadLeft
    IGT   R0, 0                     ; bit 0
    IN    R2, INP_GamepadRight
    IGT   R2, 0
    SHL   R2, 1
    OR    R0, R2
    IN    R2, INP_GamepadUp
    IGT   R2, 0
    SHL   R2, 2
    OR    R0, R2
    IN    R2, INP_GamepadDown
    IGT   R2, 0
    SHL   R2, 3
    OR    R0, R2
    IN    R2, INP_GamepadButtonStart
    IGT   R2, 0
    SHL   R2, 4
    OR    R0, R2
    IN    R2, INP_GamepadButtonA
    IGT   R2, 0
    SHL   R2, 5
    OR    R0, R2
    IN    R2, INP_GamepadButtonB
    IGT   R2, 0
    SHL   R2, 6
    OR    R0, R2
    IN    R2, INP_GamepadButtonX
    IGT   R2, 0
    SHL   R2, 7
    OR    R0, R2
    IN    R2, INP_GamepadButtonY
    IGT   R2, 0
    SHL   R2, 8
    OR    R0, R2
    IN    R2, INP_GamepadButtonL
    IGT   R2, 0
    SHL   R2, 9
    OR    R0, R2
    IN    R2, INP_GamepadButtonR
    IGT   R2, 0
    SHL   R2, 10
    OR    R0, R2

    OUT   INP_SelectedGamepad, R3
    POP   R3
    POP   R2
    RET

;; ============================================================================
;; __v32io_connected: is a device plugged into a gamepad port
;; ============================================================================
;; In:  R1 = gamepad port (raw int 0-3)
;; Out: R0 = 1 / 0 (INP_GamepadConnected). Selected gamepad restored.
;; Preserves R1-R13.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__v32io_connected:
    PUSH  R2
    MOV   R2, [V32IO_GAMEPAD]
    OUT   INP_SelectedGamepad, R1
    IN    R0, INP_GamepadConnected
    OUT   INP_SelectedGamepad, R2
    POP   R2
    RET

