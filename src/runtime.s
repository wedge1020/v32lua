;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Vircon32 NaN-Boxed Routines for Lua Runtime Environment (runtime.s)
;; Audited & Consolidated Architecture
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; =====================================================================================
;; SECTION 0: DEFINES
;; =====================================================================================
;;  V32_CART_PAGE   0x20000000
;;  NAN_VALUE       0x7F800000
;;  BOXED_CATEGORY  0x80000000 // sign bit used for RAM (1) vs ROM (0)
;;  BOXED_TYPE      0x00400000 // quiet-NaN used for TABLE/FUNCTION (0) vs STRING (1)
;;  BOXED_DATA      0xFFC00000 // common bitmask to indicate boxed data
;;  BOXED_FUNCTION  0x7F800000 // bitmask for boxed lua function (ROM)
;;  BOXED_ROMSTRING 0x7FC00000 // bitmank for boxed lua string literal (ROM)
;;  BOXED_TABLE     0xFF800000 // bitmask for boxed lua table (RAM)
;;  BOXED_RAMSTRING 0xFFC00000 // starting at offset 4 (includes nil/false/true)
;;  BOXED_NIL       0xFFC00000
;;  BOXED_FALSE     0xFFC00001
;;  BOXED_BOOLEAN   0xFFC00001 // mathing our way to true/false
;;  BOXED_TRUE      0xFFC00002
;;  BOXED_TOMBSTONE 0xFFC00003 // future feature
;;  BOXED_PAYLOAD   0x003FFFFF
;;  TABLE_ARRAYSIZE 0x0000FFFF

;; =====================================================================================
;; SECTION 1: MEMORY MANAGEMENT & ERROR HANDLING
;; =====================================================================================

;; -------------------------------------------------------------------------------------
;; Memory Allocator: Carves out raw word blocks from HEAP_POINTER
;; Incoming Stack: [BP+2] = Number of words requested
;; Returns: R0 = Raw pointer to allocated memory (or 0 if Out-Of-Memory)
;; -------------------------------------------------------------------------------------
__malloc:
    PUSH BP
    MOV  BP, SP
    
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
    MOV  R0, 0               ; Return 0 to signal Out-Of-Memory to caller
    
__malloc_done:
    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Out-Of-Memory Handler: Safely halts execution when memory is exhausted
;; -------------------------------------------------------------------------------------
__oom_handler:
    ;; Note: If you implement an error print routine later, call it here!
    HLT                      ; Halt Vircon32 CPU instantly to prevent data corruption
    JMP  __oom_handler       ; Infinite loop safeguard in case CPU resumes

; ==============================================================================
; __builtin_exec: Safely validates and executes a boxed function pointer in R0
; ==============================================================================
__builtin_exec:
    ; 1. Isolate and validate the NaN-box tag bits
    MOV R1, R0
    AND R1, BOXED_DATA          ; Isolate upper tag bits (adjust if your tag mask differs)
    IEQ R1, BOXED_FUNCTION          ; Is this tagged as a boxed function pointer?
    JT  R1, __exec_valid            ; If valid, jump to unboxing and execution

    ; 2. Tag validation failed! We attempted to call nil, a number, or a table.
    JMP __runtime_error_not_callable

__exec_valid:
    ; 3. Unbox the address and restore the Vircon32 memory page bit
    AND R0, BOXED_PAYLOAD          ; Strip NaN-box tag bits
    OR  R0, V32_CART_PAGE          ; Restore Vircon32 code memory page bit
    
    ; 4. The Tail-Call Jump!
    ; We do NOT use CALL R0 here. Because the original call site executed 
    ; "CALL __builtin_exec", the return address to the script is already on the 
    ; stack. By jumping directly to R0, the target function executes and its own 
    ; "RET" instruction will cleanly return straight to the original caller!
    JMP R0

; ==============================================================================
; Runtime Panic Handler
; ==============================================================================
__runtime_error_not_callable:
    ; Clear screen to dark red to signal a hardware/runtime panic
    MOV R0, 0xFF800000 
    OUT GPU_ClearColor, R0
    OUT GPU_Command, GPUCommand_ClearScreen
    
    ; Prepare screen coordinates for error text (e.g., X=20, Y=20)
    MOV   R0, 20                ; X coordinate
    PUSH  R0
    MOV   R0, 20                ; Y coordinate
    PUSH  R0

    ; Print base error message
    MOV   R0, __const_str_err_call_nil  ; Load base error string address
    PUSH  R0
    CALL __builtin_print        ; Call your runtime's internal print routine
    JMP __panic_halt
    
__panic_halt:
    WAIT                        ; Yield CPU frame to prevent runaway execution
    JMP __panic_halt            ; Trap CPU in an infinite loop

;; =====================================================================================
;; SECTION 2: TABLE OPERATIONS
;; =====================================================================================

;; -------------------------------------------------------------------------------------
;; Core Memory Allocator: Creates a new Table struct on the heap 
;; Returns: R0 = Tagged Table Pointer (0x7F80....)
;; -------------------------------------------------------------------------------------
__builtin_table_new:
    PUSH BP
    MOV  BP, SP

    MOV  R0, 4
    PUSH R0
    CALL __malloc
    IADD SP, 1

    MOV  R1, R0
    IEQ  R1, 0
    JT   R1, __oom_handler

    ;; Initialize table header
    MOV  R1, 0
    MOV  [R0], R1            ; Word 0: flags = nil
    MOV  [R0+1], R1          ; Word 1: length = 0
    MOV  [R0+2], R1          ; Word 2: array pointer = null
    MOV  [R0+3], R1          ; Word 3: hash pointer = null

    OR   R0, BOXED_TABLE

    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Table Read Indexer: t[k] -> Returns Value in R0 (or Nil if not found)
;; Incoming Stack: [BP+3] = Tagged Table Pointer, [BP+2] = Key
;; Register Usage: R1-R7 (Audited: reduced from 9 registers down to 7!)
;; -------------------------------------------------------------------------------------
__builtin_table_get:
    PUSH BP
    MOV  BP, SP
    
    ;; --- Callee-Save: Preserve 7 working registers ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7

    MOV  R1, [BP+3]          ; R1 = Tagged Table Pointer (0x7F80xxxx)
    MOV  R2, [BP+2]          ; R2 = Search Key (preserved throughout routine)

    ;; --- 1. STRICT TABLE TYPE VALIDATION ---
    ;; Ensure R1 is actually a Table before touching memory!
    MOV  R4, R1
    AND  R4, BOXED_DATA      ; Isolate upper tag bits
    IEQ  R4, BOXED_TABLE      ; Is it tagged as a Table?
    JF   R4, __runtime_error_not_table ; Trap if indexing a non-table!

    ;; --- OPTIMIZATION: EARLY UNBOXING ---
    ;; Strip tag immediately! R1 is now permanently the raw RAM heap address.
    ;; This eliminates all redundant unboxing instructions in subsequent branches.
    AND  R1, BOXED_PAYLOAD

    ;; --- 2. FAST-PATH VALIDATION (O(1) Contiguous Array Read) ---
    ;; FAST-PATH CHECK 1: Is Key an unboxed IEEE Float?
    MOV  R3, R2
    AND  R3, NAN_VALUE      ; Isolate exponent bits
    IEQ  R3, NAN_VALUE      ; Are all exponent bits 1s? (If so, it's tagged/NaN)
    JT   R3, __table_get_fallback

    ;; FAST-PATH CHECK 2: Convert float to integer & verify no fractional part
    MOV  R3, R2              ; Copy float Key to R3
    CFI  R3                  ; Vircon32 in-place conversion: R3 = (int) R3
    
    ;; Ensure float key had no fractional component (R3 == R2 mathematically)
    MOV  R4, R3
    CIF  R4                  ; Cast int back to float in R4
    INE  R4, R2              ; If (float)(int)Key != Key, it's fractional -> fallback!
    JT   R4, __table_get_fallback

    ;; FAST-PATH CHECK 3: Is integer key >= 1?
    MOV  R4, R3              ; Copy integer index to R4 for comparison
    ILT  R4, 1               ; Destructive test: Is integer key < 1?
    JT   R4, __table_get_fallback ; Zero or negative keys go to fallback!

    ;; FAST-PATH CHECK 4: Is Key within Array Capacity?
    MOV  R5, [R1+1]          ; R5 = Array Capacity (from Table Header Word 1)
    MOV  R4, R3              ; Copy integer index R3 to scratch R4
    IGT  R4, R5              ; Destructive test: Is Key > Capacity?
    JT   R4, __table_get_fallback ; Out-of-bounds integers go to fallback!

    ;; --- FAST-PATH EXECUTION: O(1) Contiguous Array Read ---
    MOV  R5, [R1+2]          ; R5 = Array Data Pointer (from Table Header Word 2)
    ISUB R3, 1               ; Convert 1-based Lua index to 0-based memory offset
    IADD R5, R3              ; Memory Address = ArrayPtr + (Key - 1)
    MOV  R0, [R5]            ; Read value directly from contiguous heap buffer!
    JMP  __table_get_done

;; --- FALLBACK EXECUTION: Association List Scan ---
__table_get_fallback:
    ;; Note: R1 is already unboxed! We read directly from Table Header Word 3.
    MOV  R5, [R1+3]          ; R5 = Base Hash Data Pointer
    MOV  R4, R5              ; Test on scratch R4 to preserve R5 pointer
    IEQ  R4, 0               ; Is Hash Buffer null (no sparse keys stored)?
    JT   R4, __table_get_not_found

;; --- BUCKET SEARCH LOOP ---
__table_get_bucket_loop:
    MOV  R6, [R5]            ; R6 = PairCount (how many pairs are stored in this bucket)
    MOV  R7, R5              ; Setup R7 as running memory pointer
    IADD R7, 2               ; Advance R7 to point directly at Key0 (Offset 2 words)

__table_get_scan_loop:
    MOV  R4, R6              ; Check remaining pairs using scratch R4
    IEQ  R4, 0               ; Have we checked all stored pairs in this bucket?
    JT   R4, __table_get_check_next_bucket ; If 0, step to next bucket in chain!
    
    ;; OPTIMIZATION: ZERO-COST DESTRUCTIVE COMPARISON
    MOV  R4, [R7]            ; Load Stored Key directly into scratch R4
    IEQ  R4, R2              ; Does Stored Key == Search Key? (Destroys R4!)
    JT   R4, __table_get_found ; Match found!
    
    ;; No match: advance memory pointer and decrement loop counter
    IADD R7, 2               ; Advance pointer by 2 words (skip Value slot to next Key)
    ISUB R6, 1               ; Decrement remaining PairCount
    JMP  __table_get_scan_loop

;; --- BUCKET CHAIN STEPPING ---
__table_get_check_next_bucket:
    MOV  R4, [R5+1]          ; Load NextBucketPtr (Word 1 of current bucket)
    MOV  R3, R4              ; Test on scratch R3 to preserve NextBucketPtr in R4
    IEQ  R3, 0               ; Is this the end of the chain (Next == 0x0)?
    JT   R3, __table_get_not_found ; End of chain reached -> Key does not exist!
    
    MOV  R5, R4              ; Step forward: Current Bucket = Next Bucket
    JMP  __table_get_bucket_loop ; Scan the next bucket in the chain!

__table_get_found:
    IADD R7, 1               ; Value is stored exactly 1 word after the matching Key
    MOV  R0, [R7]            ; Read Value into return register R0
    JMP  __table_get_done

__table_get_not_found:
    MOV  R0, BOXED_NIL      ; Key does not exist -> Return canonical Lua Nil!

__table_get_done:
    ;; --- Callee-Restore: Pop 7 working registers in reverse order (LIFO) ---
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Table Write Indexer: t[k] = v -> Writes Value into Table Storage
;; Incoming Stack: [BP+4] = Table Pointer, [BP+3] = Key, [BP+2] = Value
;; Register Usage: R1-R8 (Audited: reduced from 10 registers to 8, fixing R10 bug!)
;; -------------------------------------------------------------------------------------
__builtin_table_set:
    PUSH BP
    MOV  BP, SP
    
    ;; --- Callee-Save: Preserve 8 working registers ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8
    
    MOV  R1, [BP+4]          ; R1 = Tagged Table Pointer (0x7F80xxxx)
    MOV  R2, [BP+3]          ; R2 = Search Key (preserved throughout routine)
    MOV  R3, [BP+2]          ; R3 = Value to store (preserved throughout routine)

    ;; --- 1. STRICT TABLE TYPE VALIDATION ---
    ;; Ensure R1 is actually a Table before touching memory!
    MOV  R4, R1
    AND  R4, BOXED_DATA      ; Isolate upper tag bits
    IEQ  R4, BOXED_TABLE      ; Is it tagged as a Table?
    JF   R4, __runtime_error_not_table ; Trap if indexing a non-table!

    ;; --- OPTIMIZATION: EARLY UNBOXING ---
    ;; Strip tag immediately! R1 is now permanently the raw RAM heap address.
    AND  R1, BOXED_PAYLOAD

    ;; --- 2. FAST-PATH VALIDATION (O(1) Contiguous Array Write) ---
    ;; FAST-PATH CHECK 1: Is Key an unboxed IEEE Float?
    MOV  R4, R2
    AND  R4, NAN_VALUE      ; Isolate exponent bits
    IEQ  R4, NAN_VALUE      ; Are all exponent bits 1s? (If so, it's tagged/NaN)
    JT   R4, __table_set_fallback

    ;; FAST-PATH CHECK 2: Convert float to integer & verify no fractional part
    MOV  R4, R2              ; Copy float Key to R4
    CFI  R4                  ; Vircon32 in-place conversion: R4 = (int) R4
    
    ;; Ensure float key had no fractional component (R4 == R2 mathematically)
    MOV  R5, R4
    CIF  R5                  ; Cast int back to float in R5
    INE  R5, R2              ; If (float)(int)Key != Key, it's fractional -> fallback!
    JT   R5, __table_set_fallback

    ;; FAST-PATH CHECK 3: Is integer key >= 1?
    MOV  R5, R4              ; Copy integer index to R5 for comparison
    ILT  R5, 1               ; Destructive test: Is integer key < 1?
    JT   R5, __table_set_fallback ; Zero or negative keys go to fallback!
    
    ;; FAST-PATH CHECK 4: Is Key within Length?
    MOV  R6, [R1+1]          ; R6 = Length (from Table Header Word 1)
    MOV  R7, R4              ; Copy integer index R4 to scratch R7
    IGT  R7, R6              ; Destructive test: Is Key > Capacity?
    JT   R7, __table_set_fallback ; Out-of-bounds integers go to fallback!

    ;; --- FAST-PATH EXECUTION: O(1) Contiguous Array Write ---
    MOV  R6, [R1+2]          ; R6 = Array Data Pointer (from Table Header Word 2)
    ISUB R4, 1               ; Convert 1-based Lua index to 0-based memory offset
    IADD R6, R4              ; Memory Address = ArrayPtr + (Key - 1)
    MOV  [R6], R3            ; Write Value directly into contiguous array slot!
    JMP  __table_set_done

;; --- FALLBACK EXECUTION: Association List Storage ---
__table_set_fallback:
    ;; Note: R1 is already unboxed! Read directly from Table Header Word 3.
    MOV  R6, [R1+3]          ; R6 = Base Hash Data Pointer

    ;; 1. Ensure Base Hash Buffer exists (Test on scratch R4)
    MOV  R4, R6
    INE  R4, 0               ; Is Base Hash Pointer non-null?
    JT   R4, __table_set_bucket_loop

    ;; Allocate Base Bucket (16 words)
    PUSH R1
    PUSH R2
    PUSH R3
    MOV  R0, 16
    PUSH R0
    CALL __malloc
    IADD SP, 1               ; Correct stack cleanup for SP growing down!
    POP  R3
    POP  R2
    POP  R1

    MOV  R6, R0              ; R6 = New Base Bucket Address
    MOV  R4, R6              ; Check OOM on scratch register R4
    IEQ  R4, 0
    JT   R4, __oom_handler   ; Trap out-of-memory if allocation failed

    ;; Initialize Base Bucket header
    MOV  R7, 0
    MOV  [R6], R7            ; Word 0: PairCount = 0
    MOV  [R6+1], R7          ; Word 1: NextBucketPtr = 0x0 (Tail)

    ;; Link newly created Base Bucket to Table Header Word 3 (R1 is raw RAM address!)
    MOV  [R1+3], R6

;; --- BUCKET SEARCH LOOP ---
__table_set_bucket_loop:
    MOV  R7, [R6]            ; R7 = PairCount in current bucket
    MOV  R8, R6              ; Setup R8 as running memory pointer
    IADD R8, 2               ; Advance R8 to point directly at Key0 (Offset 2 words)

__table_set_scan_pairs:
    MOV  R4, R7              ; Check remaining pairs using scratch R4
    IEQ  R4, 0               ; Have we checked all stored pairs in this bucket?
    JT   R4, __table_set_check_next_bucket ; If 0, check chain or append!
    
    ;; OPTIMIZATION: ZERO-COST DESTRUCTIVE COMPARISON
    MOV  R4, [R8]            ; Load stored Key into scratch R4
    IEQ  R4, R2              ; Does Stored Key == Search Key? (Destroys R4!)
    JT   R4, __table_set_overwrite_val ; Found existing key -> Overwrite value!
    
    ;; No match: advance memory pointer and decrement loop counter
    IADD R8, 2               ; Advance 2 words (skip Value slot to next Key)
    ISUB R7, 1               ; Decrement remaining PairCount
    JMP  __table_set_scan_pairs

__table_set_overwrite_val:
    IADD R8, 1               ; Step from Key slot to Value slot (Offset +1 word)
    MOV  [R8], R3            ; Update value in place
    JMP  __table_set_done

;; --- BUCKET CHAIN STEPPING ---
__table_set_check_next_bucket:
    MOV  R4, [R6+1]          ; Load NextBucketPtr (Word 1 of current bucket)
    
    ;; OPTIMIZATION & BUG FIX: REUSE DEAD REGISTER
    ;; At this point, R7 (PairCount) reached 0 and is completely dead.
    ;; We reuse R7 to test NextBucketPtr instead of clobbering unsaved R10!
    MOV  R7, R4
    IEQ  R7, 0               ; Is this the end of the chain (Next == 0x0)?
    JT   R7, __table_set_append_to_tail ; If end of chain, append new pair!
    
    MOV  R6, R4              ; Step forward: Current Bucket = Next Bucket
    JMP  __table_set_bucket_loop ; Scan the next bucket in the chain!

;; --- APPEND NEW PAIR (Reached tail bucket and key was not found) ---
__table_set_append_to_tail:
    MOV  R7, [R6]            ; R7 = PairCount of the TAIL bucket
    MOV  R4, R7              ; Check capacity on scratch R4
    IGE  R4, 7               ; Is this tail bucket completely full (7 pairs / 14 words)?
    JT   R4, __table_set_allocate_extension_bucket

    ;; Room exists in tail bucket.
    ;; Note: Because we advanced R8 exactly PairCount times in the scan loop above,
    ;; R8 already points directly to the first unallocated Key slot!
    MOV  [R8], R2            ; Store new Key
    IADD R8, 1               ; Step to Value slot
    MOV  [R8], R3            ; Store new Value
    
    ;; Increment PairCount in current tail bucket header
    IADD R7, 1
    MOV  [R6], R7
    JMP  __table_set_done

;; --- ALLOCATE EXTENSION BUCKET (Tail bucket was full) ---
__table_set_allocate_extension_bucket:
    ;; Preserve working registers across __malloc call
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R6
    MOV  R0, 16              ; Request another 16-word chunk for extension bucket
    PUSH R0
    CALL __malloc
    IADD SP, 1               ; Correct stack cleanup direction!
    POP  R6
    POP  R3
    POP  R2
    POP  R1

    MOV  R8, R0              ; R8 = New Extension Bucket Address
    MOV  R4, R8              ; Check OOM on scratch register R4
    IEQ  R4, 0
    JT   R4, __oom_handler   ; Trap out-of-memory if allocation failed

    ;; Initialize New Extension Bucket Header
    MOV  R7, 1
    MOV  [R8], R7            ; Word 0: PairCount = 1 (we are storing 1 pair immediately)
    MOV  R7, 0
    MOV  [R8+1], R7          ; Word 1: NextBucketPtr = 0x0 (This is the new tail!)
    
    ;; Store the new Key/Value pair directly into Slot 0 of the new bucket
    MOV  [R8+2], R2          ; Word 2: Key0
    MOV  [R8+3], R3          ; Word 3: Val0

    ;; Link old tail bucket to this new extension bucket!
    MOV  [R6+1], R8          ; OldTailBucket[NextBucketPtr] = NewBucketAddress

__table_set_done:
    ;; --- Callee-Restore: Pop 8 working registers in reverse order (LIFO) ---
    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Table Set With Shift: Inserts value at position, shifting elements to make room.
;;
;; Incoming Stack: [BP+5] = Tagged Table Pointer, [BP+4] = Position (1-based),
;;                 [BP+3] = Value to insert, [BP+2] = Current array length
;; Register Usage: R1-R13
;; Returns: R0 = inserted value
;; -------------------------------------------------------------------------------------
__builtin_table_set_with_shift:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: Preserve working registers ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8
    PUSH R9
    PUSH R10
    PUSH R11
    PUSH R12
    PUSH R13

    ;; --- Load arguments ---
    MOV  R1, [BP+5]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+4]          ; R2 = Insertion position (1-based)
    MOV  R3, [BP+3]          ; R3 = Value to insert (return this)
    MOV  R4, [BP+2]          ; R4 = Current array length

    ;; --- Unbox table to get raw address ---
    MOV  R5, R1
    AND  R5, BOXED_PAYLOAD   ; R5 = Raw table header address

    ;; --- Get array pointer from table header ---
    MOV  R6, [R5+2]          ; R6 = Array data pointer (Word 2)

    ;; --- FIX: Allocate array if it doesn't exist ---
    MOV  R7, R6
    IEQ  R7, 0
    JT    R7, __set_with_shift_allocate_array
    JMP   __set_with_shift_get_capacity

__set_with_shift_allocate_array:
    ;; Allocate initial array (start with capacity of 8)
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6

    MOV  R0, 8
    PUSH R0
    CALL __malloc
    IADD SP, 1

    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  R6, R0              ; R6 = New array pointer
    MOV  R7, R0
    IEQ  R7, 0
    JT    R7, __oom_handler

    ;; Store new array pointer in table header
    MOV  [R5+2], R6

    ;; Set initial capacity to 8 in flags
    MOV  R7, [R5]
    MOV  R8, TABLE_ARRAYSIZE
    NOT  R8
    AND  R7, R8              ; Clear old capacity
    OR   R7, 8               ; Set capacity to 8
    MOV  [R5], R7

    ;; Fall through to get capacity

__set_with_shift_get_capacity:
    ;; --- Get capacity from flags ---
    MOV  R7, [R5]            ; R7 = Flags/array capacity (Word 0)
    AND  R7, TABLE_ARRAYSIZE  ; Extract capacity from lower bits

    ;; --- Check if we need to reallocate ---
    IGT  R2, R7
    JT   R2, __set_with_shift_reallocate
    JMP  __set_with_shift_check_shifting

__set_with_shift_reallocate:
    ;; --- Calculate new capacity (double current, or position+1, whichever is larger) ---
    MOV  R8, R7
    IADD R8, R7              ; R8 = 2 * current capacity

    MOV  R9, R2
    IADD R9, 1               ; R9 = position + 1 (minimum needed)

    IGT  R8, R9
    JT   R8, __set_with_shift_use_doubled
    MOV  R8, R9              ; Use position+1 if doubling isn't enough

__set_with_shift_use_doubled:
    ;; --- Allocate new array ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7

    MOV  R0, R8
    PUSH R0
    CALL __malloc
    IADD SP, 1

    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  R8, R0              ; R8 = New array pointer
    MOV  R9, R0
    IEQ  R9, 0
    JT   R9, __oom_handler

    ;; --- Copy existing elements to new array ---
    MOV  R9, 0               ; R9 = Source index counter
    MOV  R10, 0              ; R10 = Destination index counter

__set_with_shift_copy_loop:
    IGE  R9, R4
    JT   R9, __set_with_shift_copy_done

    MOV  R11, R6
    IADD R11, R9

    MOV  R12, R8
    IADD R12, R10

    MOV  R13, [R11]
    MOV  [R12], R13

    IADD R9, 1
    IADD R10, 1
    JMP  __set_with_shift_copy_loop

__set_with_shift_copy_done:
    ;; --- Update table header with new array pointer ---
    MOV  [R5+2], R8

    ;; --- Update capacity in flags: clear old capacity, set new ---
    MOV  R6, [R5]            ; Get current flags
    MOV  R7, TABLE_ARRAYSIZE
    NOT  R7                  ; Invert mask to clear capacity bits
    AND  R6, R7              ; Clear old capacity
    OR   R6, R8              ; Set new capacity
    MOV  [R5], R6

    ;; --- Update R6 to point to new array for shifting ---
    MOV  R6, R8

__set_with_shift_check_shifting:
    ;; --- Check if we need to shift elements ---
    MOV  R8, R4
    IADD R8, 1
    IEQ  R2, R8
    JT   R2, __set_with_shift_no_shift

    ;; --- Shift elements from position to end one slot to the right ---
    MOV  R8, R4              ; R8 = Current length (last valid index)
    MOV  R9, R2              ; R9 = Insertion position

__set_with_shift_loop:
    IGE  R9, R8
    JT   R9, __set_with_shift_store

    MOV  R10, R6
    IADD R10, R8

    MOV  R11, R6
    IADD R11, R8
    IADD R11, 1

    MOV  R12, [R10]
    MOV  [R11], R12

    ISUB R8, 1
    JMP  __set_with_shift_loop

__set_with_shift_no_shift:
    JMP  __set_with_shift_store

__set_with_shift_store:
    ;; --- Store the new value at the insertion position ---
    MOV  R8, R6
    IADD R8, R2
    ISUB R8, 1

    MOV  [R8], R3

    ;; --- Update array length in table header ---
    IADD R4, 1
    MOV  [R5+1], R4

    ;; --- Return the inserted value ---
    MOV  R0, R3

__set_with_shift_done:
    ;; --- Callee-Restore: Pop all working registers ---
    POP  R13
    POP  R12
    POP  R11
    POP  R10
    POP  R9
    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Table Insert: Inserts a value at a specific position in a table array.
;; Shifts existing elements to make room.
;;
;; Incoming Stack: [BP+4] = Tagged Table Pointer, [BP+3] = Position (1-based),
;;                 [BP+2] = Value to insert
;; Register Usage: R1-R8
;; Returns: R0 = inserted value (for add() compatibility)
;; -------------------------------------------------------------------------------------
__builtin_table_insert:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: Preserve all 8 working registers ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8

    ;; --- Load arguments from caller's stack frame ---
    MOV  R1, [BP+4]          ; R1 = Tagged Table Pointer (0x7F80xxxx)
    MOV  R2, [BP+3]          ; R2 = Position/Index (1-based, or NIL for append)
    MOV  R3, [BP+2]          ; R3 = Value to insert (preserved for return)

    ;; --- Unbox table pointer to get raw RAM address ---
    MOV  R4, R1
    AND  R4, BOXED_PAYLOAD   ; Strip the boxed tag to get raw pointer

    ;; --- Get current array length from table header ---
    MOV  R5, [R4+1]          ; R5 = Current array length (Word 1 of header)

    ;; --- Check if position is NIL or > length (default to append) ---
    MOV  R6, R2
    IEQ  R6, BOXED_NIL
    JT   R6, __insert_append
    IGT  R6, R5
    JT   R6, __insert_append
    JMP  __insert_check_bounds

__insert_append:
    IADD R2, R5              ; Position = length + 1 (append at end)
    IADD R2, 1               ; Position = length + 1 (append at end)
    JMP  __insert_prepare

__insert_check_bounds:
    ;; Position is valid and within bounds, continue
    ;; (Could add lower bound check: ILT R2, 1, but Lua tables are 1-indexed)

__insert_prepare:
    ;; --- Get array data pointer from table header ---
    MOV  R6, [R4+2]          ; R6 = Array Data Pointer (Word 2 of header)

    ;; --- Check if we need to reallocate (position > current array capacity) ---
    MOV  R7, [R4]            ; R7 = Flags from table header
    AND  R7, TABLE_ARRAYSIZE
    IGT  R2, R7
    JT   R2, __insert_reallocate_array
    JMP  __insert_shift_elements

__insert_reallocate_array:
    ;; TODO: Implement array reallocation logic
    ;; For now, assume we have enough space or fail gracefully
    JMP  __insert_shift_elements

__insert_shift_elements:
    ;; --- Shift elements from position to end one slot to the right ---
    ;; Start from the end and work backwards to avoid overwriting
    MOV  R7, R5              ; R7 = current length (last valid index)
    MOV  R8, R2              ; R8 = insertion position

__insert_shift_loop:
    ;; If position >= current length, no shifting needed
    IGE  R8, R7
    JT   R8, __insert_store_value

    ;; Shift element at R7 to R7+1
    MOV  R9, R7
    IADD R9, 1               ; Destination index = source index + 1

    ;; Calculate source address: array_ptr + (R7 - 1)
    MOV  R10, R6
    IADD R10, R7
    ISUB R10, 1

    ;; Calculate destination address: array_ptr + (R9 - 1)
    MOV  R11, R6
    IADD R11, R9
    ISUB R11, 1

    ;; Load value from source
    MOV  R12, [R10]

    ;; Store value at destination
    MOV  [R11], R12

    ;; Decrement counter and loop
    ISUB R7, 1
    JMP  __insert_shift_loop

__insert_store_value:
    ;; --- Store the new value at the insertion position ---
    ;; Calculate address: array_ptr + (position - 1)
    MOV  R7, R6
    IADD R7, R2
    ISUB R7, 1

    MOV  [R7], R3            ; Store value at calculated address

    ;; --- Update the array length ---
    IADD R5, 1               ; New length = old length + 1
    MOV  [R4+1], R5          ; Update table header with new length

    ;; --- Return the inserted value (for add() compatibility) ---
    MOV  R0, R3

__insert_done:
    ;; --- Callee-Restore: Pop all 8 working registers in reverse order (LIFO) ---
    POP  R8
    POP  R7
    POP  R6
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; __builtin_table_len: Get length of table array part
__builtin_table_len:
    PUSH BP
    MOV  BP, SP
    MOV  R0, [BP+2]    ; Table pointer
    CALL __unbox_table
    MOV  R0, [R1+1]    ; Return array length
    CIF  R0            ; Convert to float
    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Unbox Table Pointer: Converts a tagged Lua Table pointer to raw RAM address.
;;
;; Input:  R0 = Tagged Table Pointer (0xFF8xxxxx)
;; Output: R0 = Raw RAM address (unboxed)
;; Clobbers: R0 only
;; -------------------------------------------------------------------------------------
__unbox_table:
    ;; Strip the BOXED_TABLE tag (0xFF800000) from the upper bits
    ;; to get the raw heap address
    AND  R0, BOXED_PAYLOAD

    ;; Verify the result is a valid pointer (optional safety check)
    ;; IEQ  R2, R0
    ;; JT   R2, __unbox_table_valid
    ;; MOV  R0, 0  ; Return 0 for invalid (shouldn't happen in practice)
__unbox_table_valid:
    RET

;; -------------------------------------------------------------------------------------
;; Runtime Panic Handlers for Table Errors
;; -------------------------------------------------------------------------------------
__runtime_error_not_table:
    ;; Trap CPU if script attempts to index a non-table (e.g. String or Function in ROM)
    HLT
    JMP __runtime_error_not_table

__runtime_error_hash_overflow:
    ;; Trap CPU if hash part exceeds 7 pairs (until dynamic rehashing is implemented)
    HLT
    JMP __runtime_error_hash_overflow

;; ===================================================================================
;; SECTION 3: STRING & TERMINAL OPERATIONS
;; ===================================================================================

;; ===================================================================================
;; Internal Helper: __unbox_string
;; Input:  R0 = NaN-boxed String (RAM or ROM)
;; Output: R0 = Raw Vircon32 Hardware Memory Address (Page bit applied if ROM)
;; Clobbers: R1
;; ===================================================================================
__unbox_string:
    MOV R1, R0
    AND R1, BOXED_CATEGORY      ; Check Bit 31 (1 = RAM String, 0 = ROM String)
    AND R0, BOXED_PAYLOAD       ; Strip the entire NaN tag (Leaves 22-bit offset)

    INE R1, 0                   ; If Bit 31 is non-zero, it is a RAM string
    JT  R1, __unbox_string_end  ; Jump to end (RAM addresses start at 0x00000000)

    ;; It is a ROM string: Apply Vircon32 Cartridge Page Bit (Bit 29)
    OR  R0, V32_CART_PAGE

__unbox_string_end:
    RET

;; -------------------------------------------------------------------------------------
;; Built-in: Tag-Aware String Concatenation (4MW RAM / 128MW ROM Rework)
;; Incoming Stack: [BP+3] = Tagged Left_Str, [BP+2] = Tagged Right_Str
;; Returns: R0 = Tagged pointer to newly allocated RAM heap string (0xFFC0....)
;; -------------------------------------------------------------------------------------
__builtin_strcat:
    PUSH BP
    MOV  BP, SP

    ;; --- 1. Unbox and Calculate Length of Left String ---
    MOV  R0, [BP+3]          ; Load Left tagged pointer
    CALL __unbox_string      ; R0 is now raw hardware address (ROM or RAM)
    MOV  R7, R0              ; Cache unboxed Left pointer in R7 for Step 4
    MOV  R1, R7              ; R1 = Reading pointer
    MOV  R2, 0               ; R2 = Left length counter
__strcat_len_left:
    MOV  R3, [R1]            ; Read ASCII character
    IEQ  R3, 0               ; Check for null terminator
    JT   R3, __strcat_len_right_check
    IADD R1, 1
    IADD R2, 1
    JMP  __strcat_len_left

    ;; --- 2. Unbox and Calculate Length of Right String ---
__strcat_len_right_check:
    MOV  R0, [BP+2]          ; Load Right tagged pointer
    CALL __unbox_string      ; R0 is now raw hardware address (ROM or RAM)
    MOV  R8, R0              ; Cache unboxed Right pointer in R8 for Step 5
    MOV  R1, R8              ; R1 = Reading pointer
    MOV  R4, 0               ; R4 = Right length counter
__strcat_len_right:
    MOV  R3, [R1]            ; Read ASCII character
    IEQ  R3, 0               ; Check for null terminator
    JT   R3, __strcat_alloc
    IADD R1, 1
    IADD R4, 1
    JMP  __strcat_len_right

    ;; --- 3. Allocate Memory on Heap ---
__strcat_alloc:
    MOV  R0, [HEAP_POINTER]  ; R0 = New string base (raw pointer)
    MOV  R5, R0              ; R5 = Write head

    ;; Advance HEAP_POINTER = old_heap + left_len + right_len + 1
    MOV  R6, R0
    IADD R6, R2
    IADD R6, R4
    IADD R6, 1
    MOV  [HEAP_POINTER], R6

    ;; --- 4. Copy Left String to Heap ---
    MOV  R1, R7              ; Restore cached unboxed Left pointer
__strcat_copy_left:
    MOV  R3, [R1]            ; Read ASCII character into R3
    MOV  R6, R3              ; Copy to scratch register R6 for testing
    IEQ  R6, 0               ; Check for null terminator (R3 remains intact)
    JT   R6, __strcat_copy_right_check
    MOV  [R5], R3            ; Write preserved character to heap
    IADD R1, 1
    IADD R5, 1
    JMP  __strcat_copy_left

    ;; --- 5. Copy Right String to Heap ---
__strcat_copy_right_check:
    MOV  R1, R8              ; Restore cached unboxed Right pointer
__strcat_copy_right:
    MOV  R3, [R1]            ; Read ASCII character into R3
    MOV  R6, R3              ; Copy to scratch register R6 for testing
    IEQ  R6, 0               ; Check for null terminator (R3 remains intact)
    JT   R6, __strcat_finish
    MOV  [R5], R3            ; Write preserved character to heap
    IADD R1, 1
    IADD R5, 1
    JMP  __strcat_copy_right

    ;; --- 6. Null-Terminate, BOX as RAM String, and Return ---
__strcat_finish:
    MOV  R3, 0
    MOV  [R5], R3            ; Write Null terminator

    ;; Apply RAM Heap String Tag (BOXED_RAMSTRING)
    OR   R0, BOXED_RAMSTRING      ; BOX: R0 untouched since Step 3, holds new string base!

    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Built-in: Direct Print to Screen at Coordinate (x, y) with Split-Tag Coercion
;; Incoming Stack: [BP+4] = X Coordinate, [BP+3] = Y Coordinate, [BP+2] = Target Value
;; -------------------------------------------------------------------------------------
__builtin_print:
    PUSH BP
    MOV  BP, SP

    ;; 1. Initialize GPU Texture/Region state
    IN   R5, GPU_SelectedTexture ; Save current texture
	PUSH R5
    IN   R6, GPU_SelectedRegion  ; Save current region
	PUSH R6
    OUT  GPU_SelectedTexture, -1 ; Set BIOS font texture

    ;; 2. Load Parameters
    MOV  R1, [BP+4]          ; R1 = X Pixel Coordinate (Integer)
    MOV  R2, [BP+3]          ; R2 = Y Pixel Coordinate (Integer)
    MOV  R3, [BP+2]          ; R3 = Target Value to Print

__print_check_tag:
    ;; 3. SAFETY COERCION LAYER: Check for ROM vs RAM String tags
    MOV  R4, R3              ; Copy target value to scratch register R4
    AND  R4, BOXED_DATA      ; Isolate upper 10 bits (Tag)

    IEQ  R4, BOXED_ROMSTRING      ; Is it a ROM String Literal?
    JT   R4, __print_unbox_rom

    MOV  R4, R3              ; Copy target value to scratch register R4
    AND  R4, BOXED_DATA      ; Isolate upper 10 bits (Tag)

    ;; Check if it's a RAM Heap String (Tag 0xFFC0xxxx with address >= 4)
    IEQ  R4, BOXED_RAMSTRING      ; Does it have the RAM String / Primitive tag?
    JF   R4, __print_coerce  ; If neither string tag, coerce!

    ;; It is BOXED_DATA. Make sure it's not Nil (0), False (1), or True (2)!
    MOV  R4, R3
    AND  R4, BOXED_PAYLOAD      ; Isolate payload
    ILT  R4, 4               ; Is payload < 4 (Nil/False/True)?
    JT   R4, __print_coerce  ; If < 4, it's a boolean/nil -> coerce!

__print_unbox_ram:
    ;; 4a. Unbox RAM String: Keep raw 22-bit heap address (4MW limit)
    AND  R3, BOXED_PAYLOAD      ; Isolate 22-bit raw RAM heap pointer
    JMP  __print_dispatch

__print_unbox_rom:
    ;; 4b. Unbox ROM String: Isolate offset and add ROM page bit
    AND  R3, BOXED_PAYLOAD      ; Isolate up to 27-bit raw ROM offset
    OR   R3, V32_CART_PAGE      ; Restore Vircon32 CART page bit

__print_dispatch:
    ;; 5. Dispatch Unboxed Pointer to BIOS
    PUSH R3                  ; Push Unboxed Raw String Pointer
    PUSH R2                  ; Push Y Coordinate
    PUSH R1                  ; Push X Coordinate
    CALL __bios_print_text   ; Draw the string directly to the GPU screen
    IADD SP, 3               ; Clean up arguments from stack

    ;; 6. Restore previous GPU texture and region
	POP  R6
	POP  R5
    OUT  GPU_SelectedTexture, R5 ; Restore previous texture
    OUT  GPU_SelectedRegion, R6  ; Restore previous region

    MOV  SP, BP
    POP  BP
    RET

__print_coerce:
    PUSH  R6                  ; Save GPU_SelectedRegion
    PUSH  R5                  ; Save GPU_SelectedTexture
    PUSH  R2                  ; Preserve Y coordinate
    PUSH  R1                  ; Preserve X coordinate
    PUSH  R3                  ; Push non-string value as argument
    CALL  __builtin_tostring  ; R0 = Tagged String result

    POP  R3                  ; Discard the argument (was pushed before CALL)
    POP  R1                  ; Restore X
    POP  R2                  ; Restore Y
    POP  R5                  ; Restore GPU_SelectedTexture
    POP  R6                  ; Restore GPU_SelectedRegion
    MOV  R3, R0              ; Move result to R3
    JMP  __print_check_tag

;; =====================================================================================
;; SECTION 4: CORE OPERATORS & TYPE UTILITIES
;; =====================================================================================

;; -------------------------------------------------------------------------------------
;; Built-in: Lexicographical String Comparison (strcmp)
;; Incoming: R1 = Unboxed string (left), R2 = Unboxed string (right)
;; Returns: R0 = Raw integer (-1 if Left < Right, 0 if Equal, 1 if Left > Right)
;; -------------------------------------------------------------------------------------
__builtin_strcmp:
    ;; Unbox Left Operand into R1
    MOV  R0, R1
    CALL __unbox_string
    PUSH R0                  ; Save unboxed Left pointer on stack safely

    ;; Unbox Right Operand into R2
    MOV  R0, R2
    CALL __unbox_string
    MOV  R2, R0              ; R2 = Unboxed Right pointer
    POP  R1                  ; R1 = Unboxed Left pointer

__strcmp_loop:
    MOV  R3, [R1]
    MOV  R4, [R2]

    ;; If characters differ, return difference (R3 - R4)
    INE  R3, R4
    JT   R3, __strcmp_diff

    ;; If end of string reached, strings are equal (return 0)
    IEQ  R3, 0
    JT   R3, __strcmp_equal

    IADD R1, 1
    IADD R2, 1
    JMP  __strcmp_loop

__strcmp_diff:
    ISUB R3, R4
    MOV  R0, R3                  ; Return <0 if Left < Right, >0 if Left > Right
    RET

__strcmp_equal:
    MOV  R0, 0
    RET

;; -------------------------------------------------------------------------------------
;; Universal Equality (==): Returns raw integer 1 (true) or 0 (false) in R0 
;; Incoming Stack: [BP+3] = Left_Val, [BP+2] = Right_Val 
;; -------------------------------------------------------------------------------------
;; Universal Equality (==): Returns raw integer 1 (true) or 0 (false) in R0
;; Incoming Stack: [BP+3] = Left_Val, [BP+2] = Right_Val
;; -------------------------------------------------------------------------------------
__builtin_eq:
    PUSH BP
    MOV  BP, SP

    MOV  R1, [BP+3]
    MOV  R2, [BP+2]

    ;; Fast-path: If bitwise identical, they are strictly equal
    IEQ  R1, R2
    JT   R1, __eq_return_true

    ;; Validate LEFT Operand is a String (Tag 0x7FC0... or 0xFFC0... with payload >= 4)
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_ROMSTRING
    JT   R3, __eq_left_valid

    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_RAMSTRING
    JF   R3, __eq_return_false

    MOV  R3, R1
    AND  R3, BOXED_PAYLOAD
    ILT  R3, 4
    JT   R3, __eq_return_false

__eq_left_valid:
    ;; Validate RIGHT Operand is a String
    MOV  R3, R2
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_ROMSTRING
    JT   R3, __eq_right_valid

    MOV  R3, R2
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_RAMSTRING
    JF   R3, __eq_return_false

    MOV  R3, R2
    AND  R3, BOXED_PAYLOAD
    ILT  R3, 4
    JT   R3, __eq_return_false

__eq_right_valid:
    ;; Unbox both validated string pointers!
    MOV  R0, R1
    CALL __unbox_string
    PUSH R0                  ; Save unboxed Left pointer

    MOV  R0, R2
    CALL __unbox_string
    MOV  R2, R0              ; R2 = Unboxed Right pointer
    POP  R1                  ; R1 = Unboxed Left pointer

__eq_strcmp_loop:
    MOV  R3, [R1]
    MOV  R4, [R2]

    ;; Compare current characters
    INE  R3, R4
    JT   R3, __eq_return_false   ; Characters differ -> strings not equal

    ;; Check for null terminator (0x00)
    IEQ  R3, 0
    JT   R3, __eq_return_true    ; Both reached null terminator -> strings equal!

    ;; Advance pointers to next character
    IADD R1, 1
    IADD R2, 1
    JMP  __eq_strcmp_loop

__eq_return_true:
    MOV  R0, BOXED_TRUE          ; Return boxed Boolean True
    MOV  SP, BP                  ; Stack Restore
    POP  BP
    RET

__eq_return_false:
    MOV  R0, BOXED_FALSE         ; Return boxed Boolean False
    MOV  SP, BP                  ; Stack Restore
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Length Operator Dispatch (#): Returns length as an IEEE 754 Float in R0 
;; Incoming Stack: [BP+2] = Target Value 
;; -------------------------------------------------------------------------------------
;; =========================================================================
;; Runtime Built-in: __builtin_len
;; ABI: Arg 1 at [BP+2] (Stack Parameter), Caller cleans up.
;; Returns: R0 = Length of string as a Lua Float.
;; =========================================================================
__builtin_len:
    PUSH BP
    MOV  BP, SP

    ;; 1. Fetch argument from caller's stack frame
    ;; [BP+0] is old BP, [BP+1] is Return Address, [BP+2] is Arg 1
    MOV  R0, [BP+2]

    ;; 2. Unbox to get raw hardware address (handles RAM vs ROM automatically)
    CALL __unbox_string

    ;; 3. Calculate string length
    MOV  R1, 0                  ; R1 = Character counter
__len_loop:
    MOV  R2, [R0]               ; Read character from address
    IEQ  R2, 0                  ; Is it null terminator?
    JT   R2, __len_done
    IADD R0, 1                  ; Advance pointer
    IADD R1, 1                  ; Increment counter
    JMP  __len_loop

__len_done:
    ;; 4. Convert integer count in R1 to a Vircon32 Float in R0
    MOV  R0, R1
    CIF  R0                     ; Cast Integer to Float (Standard Lua number)

    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Universal Type Serializer: Converts any tagged value to a String pointer 
;; Incoming Stack: [BP+2] = Target Value 
;; -------------------------------------------------------------------------------------
__builtin_tostring:
    PUSH BP
    MOV  BP, SP
    
    MOV  R1, [BP+2]          ; Load argument from Base Pointer

    MOV  R3, R1
    AND  R3, BOXED_DATA

    ;; Pass through ROM Strings unchanged
    IEQ  R3, BOXED_ROMSTRING
    JT   R3, __tostring_passthrough

    MOV  R3, R1
    AND  R3, BOXED_DATA

    ;; Check for RAM Strings
    IEQ  R3, BOXED_RAMSTRING
    JF   R3, __tostring_check_primitives

    MOV  R4, R1
    AND  R4, BOXED_PAYLOAD
    IGE  R4, 4
    JT   R4, __tostring_passthrough  ; It is a RAM String: return unchanged!

__tostring_check_primitives:
    ;; Check for nil/false/true
    MOV  R6, R1
    IEQ  R6, BOXED_NIL
    JT   R6, __tostring_nil
    MOV  R6, R1
    IEQ  R6, BOXED_FALSE
    JT   R6, __tostring_false
    MOV  R6, R1
    IEQ  R6, BOXED_TRUE
    JT   R6, __tostring_true

    ;; Check for Table/Function (optional - remove if you don't need them)
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_TABLE
    JT   R3, __tostring_table

    MOV  R3, R1                 ; this was missing, adding
    AND  R3, BOXED_DATA         ; this was missing, adding
    IEQ  R3, BOXED_FUNCTION
    JT   R3, __tostring_function

    ;; Fall through: It's a float
    PUSH R1
    CALL __builtin_ftoa
    IADD SP, 1
    OR   R0, BOXED_RAMSTRING
    JMP  __tostring_done

__tostring_nil:
    MOV  R0, __const_str_nil ; Load address of static "nil" string 
    OR   R0, BOXED_ROMSTRING      ; Box as String 
    JMP  __tostring_done

__tostring_false:
    MOV  R0, __const_str_false ; Load address of static "false" string 
    OR   R0, BOXED_ROMSTRING      ; Box as String 
    JMP  __tostring_done

__tostring_true:
    MOV  R0, __const_str_true ; Load address of static "true" string 
    OR   R0, BOXED_ROMSTRING      ; Box as String 
    JMP  __tostring_done

__tostring_passthrough:
    MOV  R0, R1                  ; Return string pointer exactly as received
    MOV  SP, BP
    POP  BP
    RET

__tostring_table:
    MOV  SP, BP
    POP  BP
    JMP  __format_table_address 

__tostring_function:
    MOV  SP, BP
    POP  BP
    JMP  __format_function_address 
    
__tostring_done:
    MOV  SP, BP
    POP  BP
    RET

__format_table_address:
    PUSH BP
    MOV  BP, SP

    MOV  R0, __const_str_table
    OR   R0, BOXED_ROMSTRING      ; Box raw pointer as a valid Lua String

    MOV  SP, BP
    POP  BP
    RET

__format_function_address:
    PUSH BP
    MOV  BP, SP

    MOV  R0, __const_str_function
    OR   R0, BOXED_ROMSTRING      ; Box raw pointer as a valid Lua String

    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Built-in: Float to ASCII (Full Floating Point Support)
;; Incoming Stack: [BP+2] = Raw IEEE754 Float
;; Returns: R0 = Raw Heap Pointer to null-terminated ASCII string
;; Registers: R0-R13 (R14/BP and R15/SP preserved)
;; -------------------------------------------------------------------------------------
__builtin_ftoa:
    PUSH BP
    MOV  BP, SP

    ;; --- Allocate buffer (32 bytes for integer + fractional + null) ---
    MOV  R0, 32
    PUSH R0
    CALL __malloc
    IADD SP, 1

    ;; 1. Trap OOM to prevent HEAP_POINTER corruption at address 0
    MOV  R4, R0
    IEQ  R4, 0
    JT   R4, __oom_handler

    ;; 2. R2 is unused in this routine. Use it to safely lock in the base pointer.
    MOV  R2, R0
    MOV  R9, R2              ; R9 = write head

    ;; --- Unbox the float value first ---
    MOV  R3, [BP+2]          ; R3 = value from stack

    ;; --- Handle sign ---
    MOV  R4, R3              ; Copy to R4 for sign check
    FLT  R4, 0.0
    JF   R4, __ftoa_positive

    ;; Negative: write '-' and use absolute value
    MOV  R5, 45              ; ASCII '-'
    MOV  [R9], R5
    IADD R9, 1
    FABS R3                  ; R3 = |float value|
    JMP  __ftoa_extract_int

__ftoa_positive:
    ;; --- Extract integer part ---
__ftoa_extract_int:
    MOV  R4, R3              ; Copy float to R4
    CFI  R4                  ; Convert to integer in R4 (truncates toward zero)
    MOV  R7, R4              ; Use R7 for integer value

    ;; Check if integer part is zero
    MOV  R5, R7
    INE  R5, 0
    JT   R5, __ftoa_write_int_digits

    ;; Integer part is zero: write single '0'
    MOV  R5, 48              ; ASCII '0'
    MOV  [R9], R5
    IADD R9, 1
    MOV  R6, R9              ; R6 = start of integer digits (points to '0')
    JMP  __ftoa_check_fraction

__ftoa_write_int_digits:
    MOV  R6, R9              ; R6 = start of integer digits (save for reversal)

    ;; Extract digits in reverse order (LSB first)
__ftoa_int_loop:
    MOV  R5, R7              ; Copy current integer value
    INE  R5, 0
    JF   R5, __ftoa_reverse_int

    ;; Get next digit (LSB)
    MOV  R5, R7
    IMOD R5, 10
    IADD R5, 48              ; Convert to ASCII
    MOV  [R9], R5
    IADD R9, 1

    ;; Divide by 10 for next iteration
    IDIV R7, 10              ; R7 is consumed here
    JMP  __ftoa_int_loop

    ;; Reverse integer digits (they were written LSB first)
__ftoa_reverse_int:
    MOV  R10, R6             ; R10 = start of digits
    MOV  R11, R9
    ISUB R11, 1              ; R11 = end of digits
__ftoa_reverse_int_loop:
    ;; 3. Protect R10 from destructive comparison!
    MOV  R4, R10
    IGE  R4, R11
    JT   R4, __ftoa_check_fraction

    ;; Swap [R10] and [R11]
    MOV  R12, [R10]
    MOV  R13, [R11]
    MOV  [R10], R13
    MOV  [R11], R12

    IADD R10, 1
    ISUB R11, 1
    JMP  __ftoa_reverse_int_loop

__ftoa_check_fraction:
    ;; --- Check if there's a fractional part ---
    MOV  R5, R3              ; Original float

    ;; 4. R7 was destroyed by the division loop!
    ;; Re-extract the integer safely from the original float.
    MOV  R6, R3
    CFI  R6                  ; Convert to int
    CIF  R6                  ; Cast back to float
    FSUB R5, R6              ; R5 = precise fractional part

    ;; If fractional part is very small, we're done
	MOV  R4, R5              ; ← Backup fractional part to R4
    MOV  R6, 0.000001
    FLT  R4, R6
    JT   R4, __ftoa_done

    ;; Write decimal point
    MOV  R6, 46              ; ASCII '.'
    MOV  [R9], R6
    IADD R9, 1

    ;; Scale fractional part to integer (6 decimal places)
    MOV  R6, 1000000.0
    FMUL R5, R6              ; R5 = fractional * 1,000,000
    CFI  R5                  ; Convert to integer

    ;; Save start of fractional digits for reversal
    MOV  R1, R9              ; R1 = start of fractional digits

    ;; Extract fractional digits (LSB first, will reverse later)
    MOV  R6, 6               ; Counter for 6 digits
__ftoa_extract_frac:
    MOV  R12, R5
    IMOD R12, 10
    IADD R12, 48
    MOV  [R9], R12
    IADD R9, 1

    IDIV R5, 10
    ISUB R6, 1
	MOV  R4, R6
    IGT  R4, 0
    JT   R4, __ftoa_extract_frac

    ;; Reverse fractional digits
    MOV  R10, R1             ; R10 = start of fractional digits
    MOV  R11, R9
    ISUB R11, 1
__ftoa_reverse_frac_loop:
    ;; 5. Protect R10 from destructive comparison again!
    MOV  R4, R10
    IGE  R4, R11
    JT   R4, __ftoa_done

    ;; Swap [R10] and [R11]
    MOV  R12, [R10]
    MOV  R13, [R11]
    MOV  [R10], R13
    MOV  [R11], R12

    IADD R10, 1
    ISUB R11, 1
    JMP  __ftoa_reverse_frac_loop

    ;; --- Null-terminate and return ---
__ftoa_done:
    MOV  R10, 0
    MOV  [R9], R10           ; Null terminator

    ;; Return the securely preserved base pointer
    MOV  R0, R2
    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Built-in: Unary Minus (-x) -> Flips IEEE-754 Sign Bit 
;; Incoming Stack: [BP+2] = Tagged Value (Expected Float) 
;; Returns: R0 = Negated Float 
;; -------------------------------------------------------------------------------------
__builtin_unm:
    PUSH BP 
    MOV  BP, SP 

    MOV  R1, [BP+2]          ; R1 = Value to negate 
    XOR  R1, 0x80000000      ; Instantly changes positive <-> negative 
    MOV  R0, R1 
    
    MOV  SP, BP 
    POP  BP 
    RET 

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; SECTION 5: BIOS & HARDWARE SUPPORT ROUTINES
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __bios_print_text: Displays ASCII string content to the GPU screen 
;;
;;     Incoming Stack: [BP+2]=X
;;                     [BP+3]=Y
;;                     [BP+4]=Unboxed Heap String Pointer 
;;
__bios_print_text:
    PUSH BP 
    MOV  BP, SP 

    ;; Load Parameters from Stack 
    MOV  R1, [BP+2]              ; R1 = X Pixel Coordinate (Integer) 
    MOV  R2, [BP+3]              ; R2 = Y Pixel Coordinate (Integer) 
    MOV  R3, [BP+4]              ; R3 = Raw Heap Offset to ASCII String (Unboxed) 

__bios_print_loop:
    MOV  R4, [R3]                ; Read character from string memory 
    OUT  GPU_SelectedRegion, R4  ; set character to display 
    IEQ  R4, 0                   ; Check for null terminator 
    JT   R4, __bios_print_done 

    ;; Display character to screen 
    OUT  GPU_DrawingPointX, R1   ; display at X 
    OUT  GPU_DrawingPointY, R2   ; display at Y 
    OUT  GPU_Command, GPUCommand_DrawRegion ; display to screen 
    
    ;; Advance to next character and increment X coordinate 
    IADD R3, 1                   ; Next char word in memory 
    IADD R1, 10                  ; Advance X by font width (e.g., 10 pixels) 
    JMP  __bios_print_loop 

__bios_print_done:

    MOV  SP, BP 
    POP  BP 
    RET 

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; SECTION 6: PICO-8 API LAYER
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_spr:
    PUSH  BP
    MOV   BP, SP

    ;; --- 1. Set Global Scales & Flip Flags ---
    MOV   R1, 3.0
    MOV   R2, [BP+7]        ; flip_x
    INE   R2, BOXED_TRUE
    JT    R2, _set_scale_x
    MOV   R1, -3.0
_set_scale_x:
    OUT   GPU_DrawingScaleX, R1

    MOV   R1, 3.0
    MOV   R2, [BP+8]        ; flip_y
    INE   R2, BOXED_TRUE
    JT    R2, _set_scale_y
    MOV   R1, -3.0

_set_scale_y:
    OUT   GPU_DrawingScaleY, R1

    ;; --- 2. Prepare Loop Limits & Convert ALL Floats to Integers ---
    MOV   R1, [BP+5]
    MOV   R5, R1            ; R5 = w
    CFI   R5                ; Convert float 'w' to integer limit (cols)
    MOV   R1, [BP+6]
    MOV   R6, R1            ; R6 = h
    CFI   R6                ; Convert float 'h' to integer limit (rows)

    MOV   R7, [BP+2]        ; R7 = Base sprite 'n'
    CFI   R7                ; [FIX 1] Convert float 'n' to integer!
    MOV   R8, [BP+3]        ; R8 = Base 'x'
    CFI   R8                ; [FIX 1] Convert float 'x' to integer!
    MOV   R9, [BP+4]        ; R9 = Base 'y'
    CFI   R9                ; [FIX 1] Convert float 'y' to integer!

    ;; Initialize Row Counter
    MOV   R4, 0             ; R4 = row

_row_loop_start:
    MOV   R1, R4            ; preserve R4 from destructive comparison
    IGE   R1, R6
    JT    R1, _end_spr      ; If row >= h, we are done

    ;; Initialize Col Counter
    MOV   R3, 0             ; R3 = col

_col_loop_start:
    MOV   R1, R3            ; preserve R3 from destructive comparison
    IGE   R1, R5            ; [FIX 2] Changed IGT to IGE! (If col >= w, move to next row)
    JT    R1, _row_loop_end

    ;; --- 3. Calculate Target Region ID ---
    ;; region = n + col + (row * 16)
    MOV   R1, R4
    IMUL  R1, 16
    IADD  R1, R3
    IADD  R1, R7
    OUT   GPU_SelectedRegion, R1

    ;; --- 4. Calculate X Coordinate ---
    MOV   R1, [BP+7]        ; check flip_x
    IEQ   R1, BOXED_TRUE
    JT    R1, _calc_flip_x

    ;; Normal X = base_x + (col * 8)
    MOV   R1, R3
    IMUL  R1, 8
    IADD  R1, R8
    JMP   _set_x

_calc_flip_x:
    ;; [FIX 3] Flipped X = base_x + (w - 1 - col) * 8
    MOV   R1, R5
    ISUB  R1, 1             ; Subtract 1 for zero-indexed grid mirroring
    ISUB  R1, R3
    IMUL  R1, 8
    IADD  R1, R8

_set_x:
    OUT   GPU_DrawingPointX, R1

    ;; --- 5. Calculate Y Coordinate ---
    MOV   R1, [BP+8]        ; check flip_y
    IEQ   R1, BOXED_TRUE
    JT    R1, _calc_flip_y

    ;; Normal Y = base_y + (row * 8)
    MOV   R1, R4
    IMUL  R1, 8
    IADD  R1, R9
    JMP   _set_y

_calc_flip_y:
    ;; [FIX 3] Flipped Y = base_y + (h - 1 - row) * 8
    MOV   R1, R6
    ISUB  R1, 1             ; Subtract 1 for zero-indexed grid mirroring
    ISUB  R1, R4
    IMUL  R1, 8
    IADD  R1, R9

_set_y:
    OUT   GPU_DrawingPointY, R1

    ;; --- 6. Issue Draw Command ---
    OUT   GPU_Command, GPUCommand_DrawRegionZoomed

    ;; --- 7. Inner Loop Iteration ---
    IADD  R3, 1             ; col++
    JMP   _col_loop_start

_row_loop_end:
    ;; --- 8. Outer Loop Iteration ---
    IADD  R4, 1             ; row++
    JMP   _row_loop_start

_end_spr:
    ;; --- 9. Cleanup ---
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_btn: approximating the PICO-8 'btn()' function
;;
;; Stack layout relative to BP:
;; [BP+2]: i (Button ID 0-5)
;; [BP+3]: p (Player ID 0-3)
;;
;; Returns BOXED_TRUE or BOXED_FALSE in R0
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_btn:
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
    JT    R1, _btn_up
    MOV   R1, R2
    IEQ   R1, 1
    JT    R1, _btn_down
    MOV   R1, R2
    IEQ   R1, 2
    JT    R1, _btn_left
    MOV   R1, R2
    IEQ   R1, 3
    JT    R1, _btn_right
    MOV   R1, R2
    IEQ   R1, 4
    JT    R1, _btn_a
    MOV   R1, R2
    IEQ   R1, 5
    JT    R1, _btn_b

    ;; If invalid button ID, return false
    JMP   _btn_false

_btn_left:
    IN    R2, INP_GamepadLeft
    JMP   _btn_eval
_btn_right:
    IN    R2, INP_GamepadRight
    JMP   _btn_eval
_btn_up:
    IN    R2, INP_GamepadUp
    JMP   _btn_eval
_btn_down:
    IN    R2, INP_GamepadDown
    JMP   _btn_eval
_btn_a:
    IN    R2, INP_GamepadButtonA
    JMP   _btn_eval
_btn_b:
    IN    R2, INP_GamepadButtonB

_btn_eval:
    ;; Vircon32 returns 1 for pressed, 0 for not pressed
    IGE   R2, 1
    JT    R2, _btn_true

_btn_false:
    MOV   R0, BOXED_FALSE
    JMP   _btn_end

_btn_true:
    MOV   R0, BOXED_TRUE

_btn_end:
    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __builtin_btnp: approximating the PICO-8 'btnp()' function
;;
;; Stack layout relative to BP:
;; [BP+2]: i (Button ID 0-5)
;; [BP+3]: p (Player ID 0-3)
;;
;; Returns BOXED_TRUE or BOXED_FALSE in R0
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__builtin_btnp:
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
    JT    R1, _btnp_left
    MOV   R1, R2
    IEQ   R1, 1
    JT    R1, _btnp_right
    MOV   R1, R2
    IEQ   R1, 2
    JT    R1, _btnp_up
    MOV   R1, R2
    IEQ   R1, 3
    JT    R1, _btnp_down
    MOV   R1, R2
    IEQ   R1, 4
    JT    R1, _btnp_a
    MOV   R1, R2
    IEQ   R1, 5
    JT    R1, _btnp_b

    JMP   _btnp_false

_btnp_left:
    IN    R2, INP_GamepadLeft
    JMP   _btnp_eval
_btnp_right:
    IN    R2, INP_GamepadRight
    JMP   _btnp_eval
_btnp_up:
    IN    R2, INP_GamepadUp
    JMP   _btnp_eval
_btnp_down:
    IN    R2, INP_GamepadDown
    JMP   _btnp_eval
_btnp_a:
    IN    R2, INP_GamepadButtonA
    JMP   _btnp_eval
_btnp_b:
    IN    R2, INP_GamepadButtonB

_btnp_eval:
    ;; R2 now contains Frames Held (>0) or Frames Released (<=0)

    ;; Condition A: Is button not pressed?
    MOV   R1, R2
    ILT   R1, 1
    JT    R1, _btnp_false   ; If < 1, return false

    ;; Condition B: Initial Press (Frame 1)
    MOV   R1, R2
    IEQ   R1, 1
    JT    R1, _btnp_true    ; If exactly 1, return true

    ;; Condition C: Delay Phase (Frames 2-14)
    MOV   R1, R2
    ILT   R1, 15
    JT    R1, _btnp_false   ; If < 15 (and > 1), return false

    ;; Condition D: Autorepeat Phase (Frames 15+)
    ;; Logic: (FramesHeld - 15) % 4 == 0
    MOV   R1, R2
    ISUB  R1, 15            ; Shift down by 15 frames
    IMOD  R1, 4             ; Modulo 4
    IEQ   R1, 0             ; Is remainder 0?
    JT    R1, _btnp_true    ; If yes, return true

_btnp_false:
    MOV   R0, BOXED_FALSE
    JMP   _btnp_end

_btnp_true:
    MOV   R0, BOXED_TRUE

_btnp_end:
    MOV   SP, BP
    POP   BP
    RET

;; -------------------------------------------------------------------------------------
;; Pico-8 add(): Inserts value into table at position (default: append)
;;
;; Incoming Stack: [BP+4] = Tagged Table Pointer, [BP+3] = Value, [BP+2] = Index (or NIL)
;; Returns: R0 = inserted value
;; -------------------------------------------------------------------------------------
__builtin_add:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: Preserve working registers ---
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5

    ;; --- Load arguments ---
    MOV  R1, [BP+2]          ; R1 = table
    MOV  R2, [BP+3]          ; R2 = value
    MOV  R3, [BP+4]          ; R3 = index (or NIL)

    ;; --- Unbox table to get raw address ---
    MOV  R4, R1
    AND  R4, BOXED_PAYLOAD   ; R4 = raw table header address

    ;; --- Get current array length from table header ---
    MOV  R5, [R4+1]          ; R5 = current array length

    ;; --- Handle default index (NIL = length + 1) ---
    MOV  R4, R3
    IEQ  R4, BOXED_NIL
    JT   R4, __add_use_length_plus_1
    MOV  R3, R4              ; Use provided index
    JMP  __add_call_table_set

__add_use_length_plus_1:
    MOV  R3, R5
    FADD R3, 1              ; R3 = length + 1

__add_call_table_set:
    ;; --- Call __builtin_table_set(table, index, value) ---
    PUSH R1
    PUSH R3
    PUSH R2
    CALL __builtin_table_set
    IADD SP, 3

    ;; --- Update length if we appended (index == old_length + 1) ---
    MOV  R4, R5
    FADD R4, 1
    IEQ  R3, R4
    JF   R3, __add_return

    ;; --- Update table length in header ---
    FADD R5, 1
    MOV  [R1+1], R5

__add_return:
    ;; --- Return the inserted value ---
    MOV  R0, R2

    ;; --- Callee-Restore ---
    POP  R5
    POP  R4
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; SECTION 7: ROM DATA & STRING CONSTANTS
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

__const_str_nil:
    string "nil"

__const_str_false:
    string "false"

__const_str_true:
    string "true"

__const_str_table:
    string "table"

__const_str_function:
    string "function"

__const_str_err_call_nil:
    string "RUNTIME ERROR: ATTEMPT TO CALL NIL"
