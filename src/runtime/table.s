;; ===========================================================================
;; SECTION: TABLE OPERATIONS
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; Core Memory Allocator: Creates a new Table struct on the heap 
;; Returns: R0 = Tagged Table Pointer (0x7F80....)
;; ---------------------------------------------------------------------------
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

;; ---------------------------------------------------------------------------
;; Table Read Indexer: t[k] -> Returns Value in R0 (or Nil if not found)
;; Incoming Stack: [BP+3] = Tagged Table Pointer, [BP+2] = Key
;; Register Usage: R1-R7 (Audited: reduced from 9 registers down to 7!)
;; ---------------------------------------------------------------------------
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
    ;; This eliminates all redundant unboxing instructions in subsequent
    ;; branches.
    AND  R1, BOXED_PAYLOAD

    ;; --- 2. FAST-PATH VALIDATION (O(1) Contiguous Array Read) ---
    ;; FAST-PATH CHECK 1: Is Key an unboxed IEEE Float?
    MOV  R3, R2
    AND  R3, NAN_VALUE      ; Isolate exponent bits
    IEQ  R3, NAN_VALUE      ; Are all exponent bits 1s? (If so, it's tagged)
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

;; ---------------------------------------------------------------------------
;; Table Write Indexer: t[k] = v -> Writes Value into Table Storage
;; Incoming Stack: [BP+4] = Table Pointer, [BP+3] = Key, [BP+2] = Value
;; Register Usage: R1-R8 (Audited: reduced from 10 registers to 8, fixing
;;                 R10 bug!)
;; ---------------------------------------------------------------------------
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

;; ---------------------------------------------------------------------------
;; Table Set With Shift: Inserts value at position, shifting elements to make
;;                       room.
;;
;; Incoming Stack: [BP+5] = Tagged Table Pointer, [BP+4] = Position (1-based),
;;                 [BP+3] = Value to insert, [BP+2] = Current array length
;; Register Usage: R1-R13
;; Returns: R0 = inserted value
;; ---------------------------------------------------------------------------
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

;; ---------------------------------------------------------------------------
;; Table Insert: Inserts a value at a specific position in a table array.
;; Shifts existing elements to make room.
;;
;; Incoming Stack: [BP+4] = Tagged Table Pointer, [BP+3] = Position (1-based),
;;                 [BP+2] = Value to insert
;; Register Usage: R1-R8
;; Returns: R0 = inserted value (for add() compatibility)
;; ---------------------------------------------------------------------------
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
    ;; --- Callee-Restore: Pop working registers in reverse order (LIFO) ---
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

;; ---------------------------------------------------------------------------
;; Unbox Table Pointer: Converts a tagged Table pointer to raw RAM address
;;
;; Input:  R0 = Tagged Table Pointer (0xFF8xxxxx)
;; Output: R0 = Raw RAM address (unboxed)
;; Clobbers: R0 only
;; ---------------------------------------------------------------------------
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

;; ---------------------------------------------------------------------------
;; Runtime Panic Handlers for Table Errors
;; ---------------------------------------------------------------------------
__runtime_error_not_table:
    ;; Trap CPU if script attempts to index a non-table (e.g. String or
    ;; Function in ROM)
    HLT
    JMP __runtime_error_not_table

__runtime_error_hash_overflow:
    ;; Trap CPU if hash part exceeds 7 pairs (until dynamic rehashing
    ;; is implemented)
    HLT
    JMP __runtime_error_hash_overflow

