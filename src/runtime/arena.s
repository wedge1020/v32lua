;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Arena allocation (--gc arena): arena.mark() / arena.release(m)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Emitted only with --gc arena (src/gc.c). The heap stays a bump allocator
;; (__malloc, memory.s); an arena is a remembered heap top:
;;
;;   arena.mark()      push HEAP_POINTER on ARENA_STACK, return it (a number)
;;   arena.release(m)  m must be an open mark: close it and every mark opened
;;                     after it, and set HEAP_POINTER back to m -- everything
;;                     allocated since is gone, in one step
;;   arena.used()      heap words in use (HEAP_POINTER - HEAP_START)
;;
;; Fixed words (gc_emit_defines): ARENA_FLOOR = innermost open mark (0 =
;; none), ARENA_PIN_TOP, ARENA_DEPTH, ARENA_STACK[ARENA_MAX_DEPTH].
;;
;; PINNING. A block that belongs to something older than the innermost
;; arena -- the new array/hash part of a table made before the mark that
;; grows inside it, or a long-lived runtime buffer (PICO-8/TIC-80 RAM, the
;; ftoa scratch strings, a promoted tilemap) first allocated while an arena
;; is open -- is allocated through __malloc_owned (memory.s), which moves
;; ARENA_PIN_TOP up to the end of it. A release never goes below
;; ARENA_PIN_TOP: the arena's other garbage under a pinned block stays
;; allocated (a leak, bounded by one arena's worth per pin; tables grow by
;; doubling, so pins are rare), but nothing still in use is ever freed.
;;
;; WHAT IS NOT CAUGHT without --gc-check: a value made inside the arena and
;; stored somewhere that outlives it (a global, an older table, an upvalue,
;; a local of an outer function). After the release that reference points
;; at freed memory. --gc-check panics at such a store (__arena_check_*).
;;
;; RAM strings keep their length in STRLEN_CACHE (string.s) by address: a
;; release that frees the cached string clears it.
;; ---------------------------------------------------------------------------

;; ---------------------------------------------------------------------------
;; __arena_mark: no arguments -> R0 = the heap top, as a Lua number.
;; ---------------------------------------------------------------------------
__arena_mark:
    MOV  R1, [ARENA_DEPTH]
    MOV  R2, R1
    IGE  R2, ARENA_MAX_DEPTH
    JT   R2, __arena_err_depth
    MOV  R0, [HEAP_POINTER]
    MOV  R2, R1
    IADD R2, ARENA_STACK
    MOV  [R2], R0                ; ARENA_STACK[depth] = heap top
    IADD R1, 1
    MOV  [ARENA_DEPTH], R1
    MOV  [ARENA_FLOOR], R0       ; the innermost arena starts here
    CIF  R0                      ; word address -> number (exact: < 2^22)
    RET

__arena_err_depth:
    MOV  R1, __arena_str_err_depth
    OR   R1, BOXED_ROMSTRING
    JMP  __panic_with_message

;; ---------------------------------------------------------------------------
;; __arena_release: [BP+2] = m (a value arena.mark() returned) -> R0 = nil
;; ---------------------------------------------------------------------------
__arena_release:
    PUSH BP
    MOV  BP, SP

    MOV  R0, [BP+2]
    MOV  R1, R0
    AND  R1, NAN_VALUE
    IEQ  R1, NAN_VALUE           ; boxed (not a number)?
    JT   R1, __arena_err_mark
    CFI  R0                      ; R0 = the heap address it stands for

    ;; Find it among the open marks, innermost first
    MOV  R1, [ARENA_DEPTH]
__arena_release_find:
    JF   R1, __arena_err_mark    ; not open (never was, or released already)
    ISUB R1, 1
    MOV  R2, R1
    IADD R2, ARENA_STACK
    MOV  R2, [R2]
    IEQ  R2, R0
    JF   R2, __arena_release_find

    ;; R1 = its index: it and every mark above it close
    MOV  [ARENA_DEPTH], R1
    MOV  R2, 0
    JF   R1, __arena_release_floor
    MOV  R2, R1
    ISUB R2, 1
    IADD R2, ARENA_STACK
    MOV  R2, [R2]                ; the mark below: the new innermost arena
__arena_release_floor:
    MOV  [ARENA_FLOOR], R2

    ;; New heap top: m, unless a pinned block sits above it
    MOV  R1, [ARENA_PIN_TOP]
    MOV  R2, R1
    IGT  R2, R0
    JF   R2, __arena_release_set
    MOV  R0, R1
__arena_release_set:
    MOV  [HEAP_POINTER], R0

    ;; Forget a cached string length whose string was just freed
    MOV  R1, STRLEN_CACHE
    MOV  R2, [R1]
    IGE  R2, R0
    JF   R2, __arena_release_done
    MOV  R2, 0
    MOV  [R1], R2

__arena_release_done:
    MOV  R0, BOXED_NIL
    MOV  SP, BP
    POP  BP
    RET

__arena_err_mark:
    MOV  R1, __arena_str_err_mark
    OR   R1, BOXED_ROMSTRING
    JMP  __panic_with_message

;; ---------------------------------------------------------------------------
;; __arena_used: no arguments -> R0 = heap words in use, as a Lua number
;; ---------------------------------------------------------------------------
__arena_used:
    MOV  R0, [HEAP_POINTER]
    ISUB R0, HEAP_START
    CIF  R0
    RET

;#if GC_CHECK
;; ---------------------------------------------------------------------------
;; --gc-check: escape checks. Each preserves every register.
;;
;; __arena_check_store: [BP+3] = RAW address of the container being written
;;                      (table header, upvalue cell), [BP+2] = boxed value
;; __arena_check_global: [BP+2] = boxed value, going into a global
;;
;; Panics when an arena is open, the value is a heap object made inside the
;; innermost one (address >= ARENA_FLOOR), and the container is older than
;; it (address < ARENA_FLOOR; a global is always older). Values from outer
;; arenas, numbers, booleans, ROM strings and plain functions pass.
;; ---------------------------------------------------------------------------
__arena_check_store:
    PUSH BP
    MOV  BP, SP
    PUSH R0
    PUSH R1
    PUSH R2
    MOV  R1, [BP+3]
    MOV  R0, [BP+2]
    CALL __arena_check_core
    POP  R2
    POP  R1
    POP  R0
    MOV  SP, BP
    POP  BP
    RET

__arena_check_global:
    PUSH BP
    MOV  BP, SP
    PUSH R0
    PUSH R1
    PUSH R2
    MOV  R1, 0
    MOV  R0, [BP+2]
    CALL __arena_check_core
    POP  R2
    POP  R1
    POP  R0
    MOV  SP, BP
    POP  BP
    RET

;; __arena_check_core: R0 = value, R1 = container (0 = global). Clobbers
;; R0-R2; never returns on an escape.
__arena_check_core:
    MOV  R2, [ARENA_FLOOR]
    JF   R2, __arena_check_ok    ; no arena open
    PUSH R1
    CALL __arena_value_addr      ; R0 = object address, 0 = not a heap object
    POP  R1
    JF   R0, __arena_check_ok
    MOV  R2, [ARENA_FLOOR]
    IGT  R2, R0                  ; value older than the arena?
    JT   R2, __arena_check_ok
    MOV  R2, [ARENA_FLOOR]
    IGT  R2, R1                  ; container older than the arena?
    JF   R2, __arena_check_ok    ; no: it goes away with the value
    ;; escape: R0 = value's object, R1 = container
    PUSH R1
    PUSH R0
    JMP  __arena_err_escape
__arena_check_ok:
    RET

;; __arena_value_addr: R0 = boxed value -> R0 = RAW address of the heap
;; object it refers to (table header, RAM string, closure record), or 0.
;; Clobbers R0-R1.
__arena_value_addr:
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, BOXED_TABLE
    JT   R1, __arena_value_payload
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, BOXED_RAMSTRING
    JT   R1, __arena_value_ramstring
    MOV  R1, R0
    AND  R1, 0xFFE00000
    IEQ  R1, 0x7FA00000          ; BOXED_FUNCTION | BOXED_CLOSURE_FLAG
    JT   R1, __arena_value_closure
    MOV  R0, 0                   ; number, ROM string, plain function
    RET
__arena_value_ramstring:
    MOV  R1, R0
    AND  R1, BOXED_PAYLOAD
    ILT  R1, 4                   ; nil / false / true / tombstone
    JF   R1, __arena_value_payload
    MOV  R0, 0
    RET
__arena_value_closure:
    AND  R0, CLOSURE_ADDR_MASK
    SHL  R0, 1                   ; record address (boxed as address / 2)
    RET
__arena_value_payload:
    AND  R0, BOXED_PAYLOAD
    RET

;; The panic screen for an escape: the message, then the two addresses.
;; Stack on entry: [SP] = value's object address, [SP+1] = container (0 =
;; a global).
__arena_err_escape:
    PUSH BP
    MOV  BP, SP

    MOV  R0, 0xFF000080
    OUT  GPU_ClearColor, R0
    OUT  GPU_Command, GPUCommand_ClearScreen

    MOV  R0, 20
    PUSH R0
    MOV  R0, 0
    PUSH R0
    MOV  R0, __const_str_panic_banner
    OR   R0, BOXED_ROMSTRING
    PUSH R0
    CALL __builtin_print

    MOV  R0, 20
    PUSH R0
    MOV  R0, 20
    PUSH R0
    MOV  R0, __arena_str_err_escape
    OR   R0, BOXED_ROMSTRING
    PUSH R0
    CALL __builtin_print

    MOV  R0, 20
    PUSH R0
    MOV  R0, 40
    PUSH R0
    MOV  R0, __arena_str_err_escape2
    OR   R0, BOXED_ROMSTRING
    PUSH R0
    CALL __builtin_print

    MOV  R0, 20
    PUSH R0
    MOV  R0, 70
    PUSH R0
    MOV  R0, __arena_str_value_at
    OR   R0, BOXED_ROMSTRING
    PUSH R0
    CALL __builtin_print
    MOV  R0, 260
    PUSH R0
    MOV  R0, 70
    PUSH R0
    MOV  R0, [BP+1]              ; value's object
    PUSH R0
    CALL __panic_print_uint

    MOV  R0, 20
    PUSH R0
    MOV  R0, 90
    PUSH R0
    MOV  R0, __arena_str_container_at
    OR   R0, BOXED_ROMSTRING
    PUSH R0
    CALL __builtin_print
    MOV  R0, 260
    PUSH R0
    MOV  R0, 90
    PUSH R0
    MOV  R0, [BP+2]              ; container (0 = a global)
    PUSH R0
    CALL __panic_print_uint

    MOV  R0, 20
    PUSH R0
    MOV  R0, 110
    PUSH R0
    MOV  R0, __arena_str_floor_at
    OR   R0, BOXED_ROMSTRING
    PUSH R0
    CALL __builtin_print
    MOV  R0, 260
    PUSH R0
    MOV  R0, 110
    PUSH R0
    MOV  R0, [ARENA_FLOOR]
    PUSH R0
    CALL __panic_print_uint

    JMP  __panic_halt

__arena_str_err_escape:
    string "ARENA ERROR: A VALUE MADE IN THE OPEN ARENA"
__arena_str_err_escape2:
    string "WAS STORED IN SOMETHING OLDER (--gc-check)"
__arena_str_value_at:
    string "VALUE AT WORD:"
__arena_str_container_at:
    string "STORED INTO (0 = GLOBAL):"
__arena_str_floor_at:
    string "ARENA STARTS AT WORD:"
;#endif

__arena_str_err_depth:
    string "ARENA ERROR: TOO MANY OPEN arena.mark()s (16)"
__arena_str_err_mark:
    string "ARENA ERROR: arena.release(m): m IS NOT AN OPEN MARK"
