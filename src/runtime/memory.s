;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Vircon32 NaN-Boxed Routines for Lua Runtime Environment (runtime.s)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ===========================================================================
;; SECTION: DEFINES
;; ===========================================================================
;;  V32_CART_PAGE   0x20000000 (0x10000000 when built with -b)
;;  NAN_VALUE       0x7F800000
;;  BOXED_CATEGORY  0x80000000 // sign bit used for RAM (1) vs ROM (0)
;;  BOXED_TYPE      0x00400000 // TABLE/FUNCTION (0) vs STRING (1)
;;  BOXED_DATA      0xFFC00000 // common bitmask to indicate boxed data
;;  BOXED_FUNCTION  0x7F800000 // bitmask for boxed lua function (ROM)
;;  BOXED_ROMSTRING 0x7FC00000 // bitmank for boxed lua string literal (ROM)
;;  BOXED_TABLE     0xFF800000 // bitmask for boxed lua table (RAM)
;;  BOXED_RAMSTRING 0xFFC00000 // starts at offset 4 (includes nil/false/true)
;;  BOXED_NIL       0xFFC00000
;;  BOXED_FALSE     0xFFC00001
;;  BOXED_BOOLEAN   0xFFC00001 // mathing our way to true/false
;;  BOXED_TRUE      0xFFC00002
;;  BOXED_TOMBSTONE 0xFFC00003 // future feature
;;  BOXED_PAYLOAD   0x003FFFFF
;;  TABLE_ARRAYSIZE 0x0000FFFF

;; ===========================================================================
;; SECTION: MEMORY MANAGEMENT & ERROR HANDLING
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; __malloc_owned: __malloc for a block that belongs to something that may be
;; older than the allocation itself -- the new array or hash part of an
;; existing table, or a long-lived runtime buffer kept in a fixed pointer.
;; Incoming Stack: [BP+2] = Number of words requested (as __malloc)
;; In: R0 = RAW address of the owner (a table header), 0 = a long-lived
;;     runtime buffer. Returns and clobbers exactly like __malloc.
;; Without --gc arena it IS __malloc (the label falls through). With it, a
;; block whose owner is older than the innermost open arena is pinned: the
;; arena's release keeps the heap up to the end of it (arena.s), so the
;; owner never ends up pointing at freed memory.
;; ---------------------------------------------------------------------------
__malloc_owned:
;#if GC_ARENA
    MOV  R1, [ARENA_FLOOR]
    JF   R1, __malloc            ; no arena open: a plain allocation
    IGT  R1, R0                  ; owner older than the innermost arena?
    JF   R1, __malloc            ; no: it is freed with its owner
    PUSH BP
    MOV  BP, SP
    MOV  R0, [BP+2]
    PUSH R0
    CALL __malloc
    IADD SP, 1
    MOV  R1, [HEAP_POINTER]
    MOV  [ARENA_PIN_TOP], R1     ; a release keeps everything up to here
    MOV  SP, BP
    POP  BP
    RET
;#endif

;; ---------------------------------------------------------------------------
;; Memory Allocator: Carves out raw word blocks from HEAP_POINTER
;; Incoming Stack: [BP+2] = Number of words requested
;; Returns: R0 = Raw pointer to allocated memory. Never returns on
;;          Out-Of-Memory: it goes straight to __oom_handler (the red panic
;;          screen). It used to return 0 and leave the check to the caller,
;;          and about half the callers never made it -- they then wrote
;;          their block over RAM word 0 (HEAP_POINTER) and onwards. The
;;          callers' old `IEQ Rn, 0 / JT Rn, __oom_handler` checks are now
;;          dead but harmless.
;; ---------------------------------------------------------------------------
__malloc:
    PUSH BP
    MOV  BP, SP
    MOV  R1, [FREE_MASK]
    JT   R1, __malloc_reuse  ; a freed block may fit (see __mfree below)

__malloc_bump:
    MOV  R1, [BP+2]          ; R1 = Requested size in words
    MOV  R0, [HEAP_POINTER]  ; R0 = Address of new allocation block
    
    ;; Calculate potential new heap top
    MOV  R2, R0
    IADD R2, R1              ; R2 = Potential new HEAP_POINTER
    
    ;; Stack Collision Check: SP grows down, Heap grows up!
    ;; We maintain a 1024-word safety buffer between Heap and Stack.
    MOV  R3, SP
    ISUB R3, 1024            ; R3 = Lowest safe memory address for stack
    MOV  R6, R2
    IGE  R6, R3              ; Will the new heap top collide with the stack?
    JT   R6, __malloc_oom    ; If Heap >= SafeBoundary, allocation fails!
    
    ;; Success: Commit new heap top and return base address in R0
    MOV  [HEAP_POINTER], R2
    JMP  __malloc_done
    
__malloc_oom:
    JMP  __oom_handler       ; fatal: halts, never returns

__malloc_done:
    MOV  SP, BP
    POP  BP
    RET

;; --- Reuse a freed block -------------------------------------------------
;; R1 = FREE_MASK (non-zero). Registers: R0-R3 and R6 only (the __malloc
;; contract). Size classes ("bins"): bin k holds free blocks of 2^k to
;; 2^(k+1)-1 words; FREE_MASK bit k is set while bin k is not empty.
;; floor(log2 n) is three instructions: CIF makes n a float, whose
;; exponent field is it (n < 2^22, so exact).
;;   1. first fit among the first 4 blocks of n's own bin (they may be
;;      smaller than n -- the table blocks freed in practice are 8, 16, ...
;;      array words and 18, 34, ... hash words, so this is where an equal
;;      size is found);
;;   2. otherwise the head of the smallest non-empty bin above it: every
;;      block there is >= 2^(k+1) > n;
;;   3. otherwise a fresh block from the heap top (__malloc_bump).
;; A taken block is split: a remainder of 2 words or more goes back into
;; its own bin. The block's old contents are left as they are -- every
;; allocation site initialises what it allocates.
__malloc_reuse:
;#if GC_ARENA
    MOV  R2, [ARENA_DEPTH]
    JT   R2, __malloc_bump   ; inside an arena: fresh memory only (arena.s)
;#endif
    MOV  R0, [BP+2]          ; R0 = n
    MOV  R2, R0
    ILT  R2, 2
    JF   R2, __malloc_reuse_n
    MOV  R0, 2               ; a 1-word request takes a 2-word block
__malloc_reuse_n:
    MOV  R3, R0
    CIF  R3
    SHL  R3, -23
    ISUB R3, 127             ; R3 = k = floor(log2 n)
    IADD R3, FREE_BINS       ; R3 = the link to follow: &bin[k]
    MOV  R6, 4               ; blocks to look at in bin k
__malloc_fit_loop:
    MOV  R1, [R3]            ; R1 = candidate block
    JF   R1, __malloc_fit_none
    MOV  R2, [R1+1]          ; its size
    IGE  R2, R0
    JT   R2, __malloc_fit_take
    MOV  R3, R1              ; the next link is this block's word 0
    ISUB R6, 1
    JT   R6, __malloc_fit_loop
    JMP  __malloc_fit_none
__malloc_fit_take:
    MOV  R2, [R1]
    MOV  [R3], R2            ; unlink it
    MOV  R2, R0
    CIF  R2
    SHL  R2, -23
    ISUB R2, 127             ; R2 = the bin it came from
    JMP  __malloc_took

__malloc_fit_none:
    MOV  R2, R0
    CIF  R2
    SHL  R2, -23
    ISUB R2, 127             ; k
    MOV  R3, 2
    SHL  R3, R2
    ISUB R3, 1               ; bits 0..k
    NOT  R3                  ; bits above k
    MOV  R1, [FREE_MASK]
    AND  R1, R3
    JF   R1, __malloc_bump   ; nothing big enough: fresh memory
    MOV  R3, R1
    ISGN R3
    AND  R1, R3              ; lowest set bit: the smallest bin that fits
    CIF  R1
    SHL  R1, -23
    ISUB R1, 127
    MOV  R2, R1              ; R2 = j
    MOV  R3, R2
    IADD R3, FREE_BINS
    MOV  R1, [R3]            ; its first block
    MOV  R6, [R1]
    MOV  [R3], R6            ; unlink it

;; R1 = the block, R0 = n, R2 = the bin it was in
__malloc_took:
    MOV  R3, R2
    IADD R3, FREE_BINS
    MOV  R3, [R3]
    JT   R3, __malloc_split  ; the bin still has blocks
    MOV  R3, 1
    SHL  R3, R2
    NOT  R3
    MOV  R6, [FREE_MASK]
    AND  R6, R3
    MOV  [FREE_MASK], R6     ; bin now empty
__malloc_split:
    MOV  R2, [R1+1]
    ISUB R2, R0              ; R2 = what is left over
    MOV  R3, R2
    ILT  R3, 2
    JT   R3, __malloc_reuse_done
    MOV  R3, R1
    IADD R3, R0              ; R3 = the remainder block
    MOV  [R3+1], R2
    CIF  R2
    SHL  R2, -23
    ISUB R2, 127             ; its bin
    MOV  R6, R2
    IADD R6, FREE_BINS
    MOV  R0, [R6]
    MOV  [R3], R0
    MOV  [R6], R3            ; pushed on its bin
    MOV  R0, 1
    SHL  R0, R2
    MOV  R6, [FREE_MASK]
    OR   R6, R0
    MOV  [FREE_MASK], R6
__malloc_reuse_done:
    MOV  R0, R1
    JMP  __malloc_done

;; ---------------------------------------------------------------------------
;; __mfree: give a block back for __malloc to reuse.
;; Incoming Stack: [BP+3] = RAW block address, [BP+2] = its size in words
;; (exactly what was allocated, or the tail of it). Preserves every register.
;; The free-list layout -- FREE_MASK bit k while bin k is not empty, 22 bins
;; at FREE_BINS (bin k: 2^k .. 2^(k+1)-1 words), block header [next, size]
;; -- is also read by v32sim's --heap report: tell v32sim if it changes.
;; Used where the runtime KNOWS a block is garbage: the array or hash part a
;; table has just outgrown (table.s), the unused tail of a number's text
;; (string.s). Blocks under 2 words are dropped (a free block keeps its
;; next pointer and its size in its first two words).
;; With --gc arena, a block inside an open arena is not kept (the release
;; frees it anyway, and a list entry above the heap top after the release
;; would be handed out twice), and __malloc does not reuse blocks while an
;; arena is open (an object made there must lie above the mark, or the
;; release would not free it and --gc-check would take it for an old one).
;; ---------------------------------------------------------------------------
__mfree:
    PUSH BP
    MOV  BP, SP
    PUSH R0
    PUSH R1
    PUSH R2
    PUSH R3
    MOV  R1, [BP+2]          ; size
    MOV  R0, R1
    ILT  R0, 2
    JT   R0, __mfree_done
    MOV  R0, [BP+3]          ; block
;#if GC_ARENA
    MOV  R2, [ARENA_DEPTH]
    JF   R2, __mfree_keep
    MOV  R2, [ARENA_STACK]   ; the outermost open mark
    IGT  R2, R0              ; is the block below every arena?
    JF   R2, __mfree_done    ; no: it goes with the arena
__mfree_keep:
;#endif
    MOV  [R0+1], R1
    CIF  R1
    SHL  R1, -23
    ISUB R1, 127             ; its bin
    MOV  R2, R1
    IADD R2, FREE_BINS
    MOV  R3, [R2]
    MOV  [R0], R3
    MOV  [R2], R0            ; pushed on its bin
    MOV  R2, 1
    SHL  R2, R1
    MOV  R3, [FREE_MASK]
    OR   R3, R2
    MOV  [FREE_MASK], R3
__mfree_done:
    POP  R3
    POP  R2
    POP  R1
    POP  R0
    MOV  SP, BP
    POP  BP
    RET

;; ---------------------------------------------------------------------------
;; Out-Of-Memory Handler: Safely halts execution when memory is exhausted
;; ---------------------------------------------------------------------------
__oom_handler:
    PUSH BP
    MOV  BP, SP
    ISUB SP, 1

    MOV  R0, [HEAP_POINTER]
    CIF  R0                        ; word address -> float (Lua number)
    MOV  [BP-1], R0

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
    MOV  R0, __const_str_err_oom
    OR   R0, BOXED_ROMSTRING
    PUSH R0
    CALL __builtin_print

    ;; Heap-words-used diagnostic. Deliberately NOT routed through
    ;; print()/tostring() -- see __panic_print_uint's header comment.
    MOV   R0, 20
    PUSH  R0                       ; X
    MOV   R0, 40
    PUSH  R0                       ; Y
    MOV   R0, [HEAP_POINTER]
    PUSH  R0                       ; value
    CALL __panic_print_uint

    JMP __panic_halt

;; ---------------------------------------------------------------------------
;; __panic_with_message: the red panic screen with one ROM message, then halt.
;; In: R1 = boxed ROM string. Never returns. Allocation-free (safe to use
;; before __global_scope_initialization and with a full heap).
;; Used by the cartridge-layout check in the entry vector (generator.c) and
;; by the arena allocator.
;; ---------------------------------------------------------------------------
__panic_with_message:
    PUSH BP
    MOV  BP, SP
    ISUB SP, 1
    MOV  [BP-1], R1

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
    MOV  R0, [BP-1]
    PUSH R0
    CALL __builtin_print

    JMP __panic_halt

;; ---------------------------------------------------------------------------
;; Built-in: Unary Minus (-x) -> Flips IEEE-754 Sign Bit 
;; Incoming Stack: [BP+2] = Tagged Value (Expected Float) 
;; Returns: R0 = Negated Float 
;; ---------------------------------------------------------------------------
__builtin_unm:
    PUSH BP 
    MOV  BP, SP 

    MOV  R1, [BP+2]          ; R1 = Value to negate 
    XOR  R1, 0x80000000      ; Instantly changes positive <-> negative 
    MOV  R0, R1 
    
    MOV  SP, BP 
    POP  BP 
    RET 

;; ---------------------------------------------------------------------------
;; Length Operator Dispatch (#): Returns length as IEEE 754 Float in R0
;; Incoming Stack: [BP+2] = Target Value
;; Handles: strings, tables, and returns 0 for other types
;; ---------------------------------------------------------------------------
__builtin_len:
    PUSH BP
    MOV  BP, SP

    MOV  R0, [BP+2]            ; Load argument

    ;; --- Type check: Is it a STRING (ROM or RAM)? ---
    MOV   R1, R0
    AND   R1, BOXED_DATA        ; Extract tag bits
    IEQ   R1, BOXED_ROMSTRING
    JT    R1, __builtin_len_string

    MOV   R1, R0
    AND   R1, BOXED_DATA        ; Extract tag bits
    IEQ   R1, BOXED_RAMSTRING
    JF    R1, __builtin_len_check_table

    ;; tag matched RAMSTRING -- confirm payload >= 4 before treating it
    ;; as a real string. nil/true/false/tombstone fall through to the
    ;; table check below (and from there to default, since none of them
    ;; carry the TABLE tag either).
    MOV   R1, R0
    AND   R1, BOXED_PAYLOAD
    IGE   R1, 4
    JT    R1, __builtin_len_string

__builtin_len_check_table:
    ;; FIX: this check was missing entirely. __builtin_len_table below
    ;; was unreachable dead code -- nothing in this function ever tested
    ;; for the TABLE tag, so every table (regardless of contents) fell
    ;; through to __builtin_len_default and silently returned 0. Adding
    ;; the actual dispatch here.
    MOV   R1, R0
    AND   R1, BOXED_DATA
    IEQ   R1, BOXED_TABLE
    JT    R1, __builtin_len_table

__builtin_len_default:
    ;; --- Default: Not a string or table (number, boolean, nil, function) ---
    MOV   R0, 0                 ; Return 0 as integer
    CIF   R0                    ; Convert to float
    JMP   __builtin_len_done

__builtin_len_string:
    PUSH R0                    ; need to repush the boxed pointer
    CALL __builtin_string_len  ; String length handler
    JMP  __builtin_len_done

__builtin_len_table:
    MOV  R1, R0
    AND  R1, BOXED_PAYLOAD
    MOV  R1, [R1+4]            ; a metatable? its __len answers first
    JF   R1, __builtin_len_raw
    MOV  R1, __mm_str_len
    OR   R1, BOXED_ROMSTRING
    CALL __table_unary_meta    ; R1 = 1 when it did (R0 = its result)
    JT   R1, __builtin_len_done
__builtin_len_raw:
    PUSH R0                    ; need to repush the boxed pointer
    CALL __builtin_table_len   ; Table length handler
    ; R0 already contains float result from __builtin_table_len

__builtin_len_done:
    MOV  SP, BP
    POP  BP
    RET

__builtin_type:
    PUSH BP
    MOV  BP, SP

    MOV  R0, [BP+2]          ; Load argument into R0

    ;; --- Check exact values for primitives FIRST ---
    MOV  R1, R0
    IEQ  R1, BOXED_NIL
    JT   R1, __type_nil

    MOV  R1, R0
    IEQ  R1, BOXED_FALSE
    JT   R1, __type_boolean

    MOV  R1, R0
    IEQ  R1, BOXED_TRUE
    JT   R1, __type_boolean

    ;; --- Check for number (unboxed float) ---
    MOV  R1, R0
    AND  R1, 0x7F800000      ; NaN/boxed tag mask
    INE  R1, 0x7F800000      ; NOT equal to NaN tag → it's a number
    JT   R1, __type_number

    ;; --- Check for ROM string ---
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, BOXED_ROMSTRING
    JT   R1, __type_string

    ;; --- Check for RAM string: tag 0xFFC00000 AND payload >= 4 ---
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, 0xFFC00000      ; Same tag as NIL, but we already ruled out exact NIL
    JF   R1, __type_check_table
    MOV  R1, R0
    AND  R1, BOXED_PAYLOAD   ; Extract lower 22 bits
    IGE  R1, 4               ; RAM strings start at payload 4
    JT   R1, __type_string

__type_check_table:
    ;; --- Check for table ---
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, BOXED_TABLE
    JT   R1, __type_table

    ;; --- Check for function ---
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, BOXED_FUNCTION
    JT   R1, __type_function

    ;; --- Fallthrough: unknown ---
    MOV  R0, __const_str_nil
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_nil:
    MOV  R0, __const_str_nil
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_boolean:
    MOV  R0, __const_str_boolean
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_number:
    MOV  R0, __const_str_number
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_string:
    MOV  R0, __const_str_string
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_table:
    MOV  R0, __const_str_table
    OR   R0, BOXED_ROMSTRING
    JMP  __type_done

__type_function:
    MOV  R0, __const_str_function
    OR   R0, BOXED_ROMSTRING

__type_done:
    MOV  SP, BP
    POP  BP
    RET

