;; ===========================================================================
;; SECTION: TABLE OPERATIONS
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; Core Memory Allocator: Creates a new Table struct on the heap
;; Returns: R0 = Tagged Table Pointer (0x7F80....)
;; Register Usage: R1 (Callee-Saved for the CALLER's benefit -- separate from
;;                 the R2/R3/R6 save below, which only protects values across
;;                 the internal CALL __malloc)
;; ---------------------------------------------------------------------------
__builtin_table_new:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: preserve R1 for the CALLER ---
    ;; R1 is an ordinary general-purpose register the compiler can hand out
    ;; for any live value, so a caller can easily have something live in R1
    ;; across a `{}` table-constructor call (e.g. an earlier argument already
    ;; evaluated into R1 before a later argument is a table literal). This
    ;; function uses R1 as scratch below for the OOM check / header init
    ;; without ever saving it -- silently destroying that caller value.
    PUSH R1

    ;; Save registers clobbered by __malloc
    PUSH  R2
    PUSH  R3
    PUSH  R6

    MOV  R0, 4
    PUSH R0
    CALL __malloc
    IADD SP, 1

    ;; Restore registers
    POP   R6
    POP   R3
    POP   R2

    MOV  R1, R0
    IEQ  R1, 0
    JT   R1, __oom_handler   ; Fatal path -- halts the CPU, never returns, so
                              ; no need to restore R1 before jumping here.

    ;; Initialize table header
    MOV  R1, 0
    MOV  [R0], R1            ; Word 0: flags = nil
    MOV  [R0+1], R1          ; Word 1: length = 0
    MOV  [R0+2], R1          ; Word 2: array pointer = null
    MOV  [R0+3], R1          ; Word 3: hash pointer = null

    OR   R0, BOXED_TABLE

    ;; --- Callee-Restore ---
    POP  R1

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
    JT   R3, __builtin_table_get_fallback

    ;; FAST-PATH CHECK 2: Convert float to integer & verify no fractional part
    MOV  R3, R2              ; Copy float Key to R3
    CFI  R3                  ; Vircon32 in-place conversion: R3 = (int) R3
    
    ;; Ensure float key had no fractional component (R3 == R2 mathematically)
    MOV  R4, R3
    CIF  R4                  ; Cast int back to float in R4
    INE  R4, R2              ; If (float)(int)Key != Key, it's fractional -> fallback!
    JT   R4, __builtin_table_get_fallback

    ;; FAST-PATH CHECK 3: Is integer key >= 1?
    MOV  R4, R3              ; Copy integer index to R4 for comparison
    ILT  R4, 1               ; Destructive test: Is integer key < 1?
    JT   R4, __builtin_table_get_fallback ; Zero or negative keys go to fallback!

    ;; FAST-PATH CHECK 4: Is Key within LENGTH AND array allocated?
    MOV  R5, [R1+1]          ; R5 = Array LENGTH (Word 1)
    MOV  R6, [R1+2]          ; R6 = Array Data Pointer
    IEQ  R6, 0
    JT   R6, __builtin_table_get_fallback_intkey   ; no array, but key is a known-valid positive int (R3)
    MOV  R4, R3
    IGT  R4, R5
    JT   R4, __builtin_table_get_fallback

    ;; --- FAST-PATH EXECUTION: O(1) Contiguous Array Read ---
    MOV  R5, [R1+2]          ; R5 = Array Data Pointer (from Table Header Word 2)
    ISUB R3, 1               ; Convert 1-based Lua index to 0-based memory offset
    IADD R5, R3              ; Memory Address = ArrayPtr + (Key - 1)
    MOV  R0, [R5]            ; Read value directly from contiguous heap buffer!
    JMP  __builtin_table_get_done

__builtin_table_get_fallback_intkey:
    ;; NOTE: this used to short-circuit straight to "not found" whenever the
    ;; key was numerically beyond the tracked contiguous `length` (Word 1),
    ;; on the assumption that nothing could be stored past it. But we only
    ;; land in this branch when there's NO array (array pointer is null,
    ;; Word 2 == 0) -- in that case the hash is the *only* storage, and
    ;; __builtin_table_set stores any positive-integer key there
    ;; unconditionally, regardless of whether it also happened to advance
    ;; `length` (e.g. `t[5] = "x"` on an empty table). The shortcut was
    ;; therefore returning nil for keys that had genuinely been set. Just
    ;; fall through to a real hash scan.
    JMP  __builtin_table_get_fallback

;; --- FALLBACK EXECUTION: Association List Scan ---
__builtin_table_get_fallback:
    ;; Note: R1 is already unboxed! We read directly from Table Header Word 3.
    MOV  R5, [R1+3]          ; R5 = Base Hash Data Pointer
    MOV  R4, R5              ; Test on scratch R4 to preserve R5 pointer
    IEQ  R4, 0               ; Is Hash Buffer null (no sparse keys stored)?
    JT   R4, __builtin_table_get_not_found

;; --- BUCKET SEARCH LOOP ---
__builtin_table_get_bucket_loop:
    MOV  R6, [R5]            ; R6 = PairCount (how many pairs are stored in this bucket)
    MOV  R7, R5              ; Setup R7 as running memory pointer
    IADD R7, 2               ; Advance R7 to point directly at Key0 (Offset 2 words)

__builtin_table_get_scan_loop:
    MOV  R4, R6              ; Check remaining pairs using scratch R4
    IEQ  R4, 0               ; Have we checked all stored pairs in this bucket?
    JT   R4, __builtin_table_get_check_next_bucket ; If 0, step to next bucket in chain!
    
    ;; OPTIMIZATION: ZERO-COST DESTRUCTIVE COMPARISON
    MOV  R4, [R7]            ; Load Stored Key directly into scratch R4
    IEQ  R4, R2              ; Does Stored Key == Search Key? (Destroys R4!)
    JT   R4, __builtin_table_get_found ; Match found!
    
    ;; No match: advance memory pointer and decrement loop counter
    IADD R7, 2               ; Advance pointer by 2 words (skip Value slot to next Key)
    ISUB R6, 1               ; Decrement remaining PairCount
    JMP  __builtin_table_get_scan_loop

;; --- BUCKET CHAIN STEPPING ---
__builtin_table_get_check_next_bucket:
    MOV  R4, [R5+1]          ; Load NextBucketPtr (Word 1 of current bucket)
    MOV  R3, R4              ; Test on scratch R3 to preserve NextBucketPtr in R4
    IEQ  R3, 0               ; Is this the end of the chain (Next == 0x0)?
    JT   R3, __builtin_table_get_not_found ; End of chain reached -> Key does not exist!
    
    MOV  R5, R4              ; Step forward: Current Bucket = Next Bucket
    JMP  __builtin_table_get_bucket_loop ; Scan the next bucket in the chain!

__builtin_table_get_found:
    IADD R7, 1               ; Value is stored exactly 1 word after the matching Key
    MOV  R0, [R7]            ; Read Value into return register R0
    JMP  __builtin_table_get_done

__builtin_table_get_not_found:
    MOV  R0, BOXED_NIL      ; Key does not exist -> Return canonical Lua Nil!

__builtin_table_get_done:
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
;; Table Write Indexer: t[k] = v
;; Incoming Stack: [BP+4] = Table Pointer, [BP+3] = Key, [BP+2] = Value
;; Register Usage: R1-R8 (Audited: reduced from 10 registers to 8, fixing
;;                 R10 bug! -- and, in this pass, an R9 bug in the hash
;;                 length-bookkeeping block that had slipped through.)
;; ---------------------------------------------------------------------------
__builtin_table_set:
    PUSH BP
    MOV  BP, SP

    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8

    MOV  R1, [BP+4]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+3]          ; R2 = Search Key
    MOV  R3, [BP+2]          ; R3 = Value to store

    ;; --- Validate & unbox table pointer EXACTLY ONCE ---
    ;; (Previously this validation/unbox ran once for the nil case and then
    ;; unconditionally AGAIN afterward, on a pointer already stripped down
    ;; to a raw payload address -- the second pass always failed its own
    ;; tag check, so every `t[k] = nil` unconditionally trapped into
    ;; __runtime_error_not_table. Validating/unboxing exactly once, up
    ;; front, fixes this for both the nil and non-nil cases -- nil values
    ;; now simply fall through and get stored like any other value, which
    ;; __builtin_table_get reads back correctly.)
    MOV  R4, R1
    AND  R4, BOXED_DATA
    IEQ  R4, BOXED_TABLE
    JF   R4, __runtime_error_not_table
    AND  R1, BOXED_PAYLOAD   ; R1 = raw RAM address (unboxed once, for good)

    ;; --- 2. FAST-PATH VALIDATION (O(1) Contiguous Array Write) ---
    ;; FAST-PATH CHECK 1: Is Key an unboxed IEEE Float?
    MOV  R4, R2
    AND  R4, NAN_VALUE      ; Isolate exponent bits
    IEQ  R4, NAN_VALUE      ; Are all exponent bits 1s? (If so, it's tagged/NaN)
    JT   R4, __builtin_table_set_fallback

    ;; FAST-PATH CHECK 2: Convert float to integer & verify no fractional part
    MOV  R4, R2              ; Copy float Key to R4
    CFI  R4                  ; Vircon32 in-place conversion: R4 = (int) R4

    ;; Ensure float key had no fractional component (R4 == R2 mathematically)
    MOV  R5, R4
    CIF  R5                  ; Cast int back to float in R5
    INE  R5, R2              ; If (float)(int)Key != Key, it's fractional -> fallback!
    JT   R5, __builtin_table_set_fallback

    ;; FAST-PATH CHECK 3: Is integer key >= 1?
    MOV  R5, R4              ; Copy integer index to R5 for comparison
    ILT  R5, 1               ; Destructive test: Is integer key < 1?
    JT   R5, __builtin_table_set_fallback ; Zero or negative keys go to fallback!

    ;; --- FAST-PATH CHECK 4: Is Key within CAPACITY? (not Length!) ---
    MOV  R6, [R1]            ; R6 = Flags from Table Header Word 0
    AND  R6, TABLE_ARRAYSIZE ; Extract capacity from lower bits
    MOV  R7, R4              ; Copy integer index R4 to scratch R7
    IGT  R7, R6              ; Destructive test: Is Key > Capacity?
    JT   R7, __builtin_table_set_reallocate ; Need array reallocation!

    ;; --- FAST-PATH EXECUTION: O(1) Contiguous Array Write ---
    MOV  R6, [R1+2]          ; R6 = Array Data Pointer (from Table Header Word 2)
    MOV  R2, R4              ; R2 = preserve original 1-based key (boxed float
                              ;      key no longer needed past this point, so
                              ;      R2 is free to reuse as scratch here)
    ISUB R4, 1               ; Convert 1-based Lua index to 0-based memory offset
    IADD R6, R4              ; Memory Address = ArrayPtr + (Key - 1)
    MOV  [R6], R3            ; Write Value directly into contiguous array slot!

    ;; --- UPDATE LENGTH FOR CONTIGUOUS KEYS ---
    ;; NOTE: this path is currently unreachable in practice -- array
    ;; capacity is always 0 (see __builtin_table_set_reallocate's TODO), so
    ;; every write funnels through the hash fallback below instead. Fixing
    ;; it now anyway so it's correct on day one once real array storage
    ;; lands. As written before this pass, this block compared/stored using
    ;; the *0-based* offset (R4, already decremented above) against
    ;; length+1, which was off by one on both the comparison and the stored
    ;; value -- using the preserved 1-based key (R2) instead fixes that too.
    ;;
    ;; R2 = original 1-based key, R7 = current contiguous length.
    ;;   1. Non-nil value written exactly at length+1 -> length grows to R2.
    ;;   2. Nil value written exactly at length (clearing the last element)
    ;;      -> length shrinks to R2-1. This is what makes the common
    ;;      `t[#t] = nil` "pop" idiom work.
    ;; Anything else (gaps, mid-array holes, out-of-range) intentionally
    ;; leaves length untouched -- Lua only guarantees *a* border, not
    ;; necessarily the largest one.
    MOV  R7, [R1+1]          ; R7 = Current contiguous length
    MOV  R5, R3
    IEQ  R5, BOXED_NIL       ; Is the value we just stored nil?
    JT   R5, __builtin_table_set_array_maybe_shrink

    ;; --- Non-nil: grow if this extended the array by exactly one ---
    MOV  R5, R7
    IADD R5, 1                ; R5 = length + 1
    MOV  R6, R2
    IEQ  R6, R5                ; R6 = (key == length + 1)?
    JF   R6, __builtin_table_set_done
    MOV  [R1+1], R2            ; New length = the key we just wrote
    JMP  __builtin_table_set_done

__builtin_table_set_array_maybe_shrink:
    ;; --- Nil: clamp length down to key-1 if key was within the tracked
    ;; contiguous range (key <= length) -- same rationale as the
    ;; hash-fallback version of this logic above; see there for details.
    MOV  R6, R2
    IGT  R6, R7                 ; R6 = (key > length)? out of range -> no-op
    JT   R6, __builtin_table_set_done
    MOV  R7, R2
    ISUB R7, 1                   ; length = key - 1
    MOV  [R1+1], R7

    JMP  __builtin_table_set_done

;; --- REALLOCATION PATH: Key exceeds array capacity ---
__builtin_table_set_reallocate:
    ;; TODO: Implement proper array reallocation
    MOV  R6, [R1+3]          ; R6 = Base Hash Data Pointer
    JMP  __builtin_table_set_fallback

;; --- FALLBACK EXECUTION: Association List Storage ---
__builtin_table_set_fallback:
    ;; Note: R1 is already unboxed! Read directly from Table Header Word 3.
    MOV  R6, [R1+3]          ; R6 = Base Hash Data Pointer

    ;; --- UPDATE LENGTH FOR POSITIVE INTEGER KEYS ---
    MOV  R7, R2              ; R7 = Key
    AND  R7, NAN_VALUE
    IEQ  R7, NAN_VALUE
    JF   R7, __builtin_table_set_hash_check_int ; Not tagged, might be integer

    ;; Tagged key - go to hash storage without length update
    JMP  __builtin_table_set_hash_store

__builtin_table_set_hash_check_int:
    ;; Check if key is a positive integer
    MOV  R7, R2
    CFI  R7                  ; R7 = integer key
    MOV  R8, R7
    CIF  R8                  ; R8 = float(int key)

    ;; --- Scratch here MUST stay within R1-R8 ---
    ;; This function only PUSH/POPs R1-R8 at entry/exit. The bucket-chain
    ;; code further below already calls this out explicitly for R10
    ;; ("reuse R7 ... instead of clobbering unsaved R10!") -- this block
    ;; previously used an unsaved R9 for the same kind of scratch compare,
    ;; silently destroying any caller value that happened to live in R9.
    ;; Reusing R4 (dead here -- see FAST-PATH CHECK 2/3 above, nothing
    ;; downstream in this block still needs it) keeps everything in-budget.
    MOV  R4, R8
    INE  R4, R2               ; Has fractional part? (R4 destroyed; R2/R7/R8 kept)
    JT   R4, __builtin_table_set_hash_store

    ;; Check if integer >= 1
    MOV  R4, R7
    ILT  R4, 1
    JT   R4, __builtin_table_set_hash_store ; < 1

    ;; --- Key is a positive integer: keep contiguous LENGTH in sync ---
    ;; R7 = integer key, R8 = current contiguous length.
    ;;   1. Non-nil value stored exactly at key == length + 1 (appending)
    ;;      -> length grows to R7.
    ;;   2. Nil value stored exactly at key == length (clearing the last
    ;;      element) -> length shrinks to R7 - 1. This is what makes
    ;;      `t[#t] = nil` ("pop") work correctly instead of leaving a
    ;;      removed element permanently counted in #t.
    ;; Anything else (gaps, mid-table holes, out-of-range keys) intentionally
    ;; leaves length untouched -- Lua only guarantees *a* border, not
    ;; necessarily the largest one.
    MOV  R8, [R1+1]          ; R8 = Current contiguous length
    MOV  R4, R3
    IEQ  R4, BOXED_NIL       ; Is the value being stored nil?
    JT   R4, __builtin_table_set_hash_maybe_shrink

    ;; --- Non-nil: grow if this appends exactly one past the end ---
    MOV  R4, R8
    IADD R4, 1                 ; R4 = length + 1
    IEQ  R4, R7                 ; R4 = (length + 1 == key)?
    JF   R4, __builtin_table_set_hash_store
    MOV  [R1+1], R7             ; length = key
    JMP  __builtin_table_set_hash_store

__builtin_table_set_hash_maybe_shrink:
    ;; --- Nil: clamp length down to key-1 if this key was within the
    ;; currently-tracked contiguous range (key <= length), not just an
    ;; exact match on the last element. This handles clearing out of
    ;; order -- e.g. `t[1]=nil; t[2]=nil; t[3]=nil` on a {1,2,3} table --
    ;; by collapsing length to 0 as soon as the lowest surviving index is
    ;; cleared, matching what real Lua's # operator converges to once an
    ;; entire array-part range is nil'd out. An exact-match-only check
    ;; (key == length) only covers clearing from the top down (the
    ;; `t[#t] = nil` "pop" idiom); this covers both. Keys already beyond
    ;; the current length are already uncounted, so they stay a no-op.
    MOV  R4, R7
    IGT  R4, R8                ; R4 = (key > length)? out of range -> no-op
    JT   R4, __builtin_table_set_hash_store
    MOV  R8, R7
    ISUB R8, 1                  ; length = key - 1
    MOV  [R1+1], R8

__builtin_table_set_hash_store:
    ;; Resume original hash storage logic:
    MOV  R4, R6              ; Test on scratch R4 to preserve R6 pointer

    ;; 1. Ensure Base Hash Buffer exists (Test on scratch R4)
    MOV  R4, R6
    INE  R4, 0               ; Is Base Hash Pointer non-null?
    JT   R4, __builtin_table_set_bucket_loop

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
__builtin_table_set_bucket_loop:
    MOV  R7, [R6]            ; R7 = PairCount in current bucket
    MOV  R8, R6              ; Setup R8 as running memory pointer
    IADD R8, 2               ; Advance R8 to point directly at Key0 (Offset 2 words)

__builtin_table_set_scan_pairs:
    MOV  R4, R7              ; Check remaining pairs using scratch R4
    IEQ  R4, 0               ; Have we checked all stored pairs in this bucket?
    JT   R4, __builtin_table_set_check_next_bucket ; If 0, check chain or append!

    ;; OPTIMIZATION: ZERO-COST DESTRUCTIVE COMPARISON
    MOV  R4, [R8]            ; Load stored Key into scratch R4
    IEQ  R4, R2              ; Does Stored Key == Search Key? (Destroys R4!)
    JT   R4, __builtin_table_set_overwrite_val ; Found existing key -> Overwrite value!

    ;; No match: advance memory pointer and decrement loop counter
    IADD R8, 2               ; Advance 2 words (skip Value slot to next Key)
    ISUB R7, 1               ; Decrement remaining PairCount
    JMP  __builtin_table_set_scan_pairs

__builtin_table_set_overwrite_val:
    IADD R8, 1               ; Step from Key slot to Value slot (Offset +1 word)
    MOV  [R8], R3            ; Update value in place
    JMP  __builtin_table_set_done

;; --- BUCKET CHAIN STEPPING ---
__builtin_table_set_check_next_bucket:
    MOV  R4, [R6+1]          ; Load NextBucketPtr (Word 1 of current bucket)

    ;; OPTIMIZATION & BUG FIX: REUSE DEAD REGISTER
    ;; At this point, R7 (PairCount) reached 0 and is completely dead.
    ;; We reuse R7 to test NextBucketPtr instead of clobbering unsaved R10!
    MOV  R7, R4
    IEQ  R7, 0               ; Is this the end of the chain (Next == 0x0)?
    JT   R7, __builtin_table_set_append_to_tail ; If end of chain, append new pair!

    MOV  R6, R4              ; Step forward: Current Bucket = Next Bucket
    JMP  __builtin_table_set_bucket_loop ; Scan the next bucket in the chain!

;; --- APPEND NEW PAIR (Reached tail bucket and key was not found) ---
__builtin_table_set_append_to_tail:
    MOV  R7, [R6]            ; R7 = PairCount of the TAIL bucket
    MOV  R4, R7              ; Check capacity on scratch R4
    IGE  R4, 7               ; Is this tail bucket completely full (7 pairs / 14 words)?
    JT   R4, __builtin_table_set_allocate_extension_bucket

    ;; Room exists in tail bucket.
    ;; Note: Because we advanced R8 exactly PairCount times in the scan loop above,
    ;; R8 already points directly to the first unallocated Key slot!
    MOV  [R8], R2            ; Store new Key
    IADD R8, 1               ; Step to Value slot
    MOV  [R8], R3            ; Store new Value

    ;; Increment PairCount in current tail bucket header
    IADD R7, 1
    MOV  [R6], R7
    JMP  __builtin_table_set_done

;; --- ALLOCATE EXTENSION BUCKET (Tail bucket was full) ---
__builtin_table_set_allocate_extension_bucket:
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

__builtin_table_set_done:
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
;; Table Insert: table.insert(t, [pos], value)
;; Inserts a value at a specific 1-based position, shifting existing
;; elements up by one. With no position (BOXED_NIL), appends at the end.
;; Negative positions count backward from the end: resolved = length + pos + 1
;; (this is a v32lua extension, not standard Lua -- e.g.
;; table.insert(t, -1, x) inserts immediately before the current last
;; element, per this project's test suite).
;;
;; Incoming Stack: [BP+4] = Tagged Table Pointer, [BP+3] = Position (1-based
;;                 float, negative float, or BOXED_NIL for append),
;;                 [BP+2] = Value to insert
;; Register Usage: R1-R8
;; Returns: R0 = inserted value (for pico8 add() compatibility)
;;
;; IMPLEMENTATION NOTE: this is implemented entirely in terms of
;; __builtin_table_get / __builtin_table_set rather than raw array-pointer
;; arithmetic. Real contiguous-array storage doesn't exist yet in this
;; runtime (table capacity is always 0 -- see __builtin_table_set's
;; __builtin_table_set_reallocate TODO), so every table here is actually
;; backed by the hash association list. The previous version of this
;; function assumed a working raw array and wrote directly through the
;; (always-null) array pointer -- on top of never converting the boxed
;; float position to a raw integer, and corrupting the position on the
;; default-append path. Routing every read/write through
;; table_get/table_set fixes all of that at once, and gets negative
;; positions and correct length bookkeeping for free (the shift loop's
;; first table_set naturally lands on key == length + 1, which
;; __builtin_table_set already bumps the tracked length for). It'll also
;; automatically become real O(1) array shifting for free whenever array
;; allocation is implemented, with zero changes needed here.
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
    MOV  R1, [BP+4]          ; R1 = Tagged Table Pointer (kept BOXED -- table_get/table_set want it boxed)
    MOV  R2, [BP+3]          ; R2 = Position (boxed float, negative float, or BOXED_NIL)
    MOV  R3, [BP+2]          ; R3 = Value to insert (boxed; preserved for the final store + return)

    ;; --- Validate table type, and get the raw header address just to
    ;;     read the current contiguous length directly (Word 1) ---
    MOV  R4, R1
    AND  R4, BOXED_DATA
    IEQ  R4, BOXED_TABLE
    JF   R4, __runtime_error_not_table
    MOV  R5, R1
    AND  R5, BOXED_PAYLOAD   ; R5 = raw table header address

    MOV  R6, [R5+1]          ; R6 = current contiguous length

    ;; --- Resolve the insertion position into R7 (a raw integer) ---
    MOV  R4, R2
    IEQ  R4, BOXED_NIL
    JT   R4, __insert_default_append

    ;; Position given: convert boxed float -> raw integer.
    MOV  R7, R2
    CFI  R7                  ; R7 = integer position (may be negative)

    MOV  R4, R7
    ILT  R4, 0                ; negative position?
    JF   R4, __insert_position_resolved

    ;; Negative position: count backward from the end (v32lua extension).
    ;; resolved = length + position + 1
    MOV  R4, R6
    IADD R4, R7
    IADD R4, 1
    MOV  R7, R4
    JMP  __insert_position_resolved

__insert_default_append:
    MOV  R7, R6
    IADD R7, 1                ; resolved = length + 1

__insert_position_resolved:
    ;; Clamp: never let the resolved position fall below 1. Guards against
    ;; pathological / wildly out-of-range negative input producing a
    ;; degenerate shift loop. (Real Lua would raise an error for an
    ;; out-of-bounds position; this runtime doesn't have error-raising
    ;; infrastructure for library calls yet, so clamping is the safe,
    ;; cheap guard for now.)
    MOV  R4, R7
    ILT  R4, 1
    JF   R4, __insert_shift_init
    MOV  R7, 1

__insert_shift_init:
    MOV  R8, R6                ; R8 = shift cursor, starts at current length

    ;; --- Shift elements from length down to position (descending) ---
    ;; Each step: t[cursor + 1] = t[cursor]. Going from the top down avoids
    ;; overwriting a value before it's been read. The very first shift (if
    ;; any) writes to key == length + 1, which naturally makes
    ;; __builtin_table_set bump the tracked length by one as a side
    ;; effect -- exactly the length update this insert needs, for free.
__insert_shift_loop:
    MOV  R4, R8
    ILT  R4, R7                ; cursor < position? shifting is done
    JT   R4, __insert_store_value

    ;; --- fetch t[cursor] ---
    MOV  R4, R8
    CIF  R4                    ; R4 = boxed float source key
    PUSH R1                    ; table pointer
    PUSH R4                    ; key = cursor
    CALL __builtin_table_get
    IADD SP, 2
    MOV  R5, R0                ; R5 = fetched value (boxed)

    ;; --- store into t[cursor + 1] ---
    MOV  R6, R8
    IADD R6, 1
    CIF  R6                    ; R6 = boxed float destination key

    PUSH R1                    ; table pointer
    PUSH R6                    ; key = cursor + 1
    PUSH R5                    ; value = fetched
    CALL __builtin_table_set
    IADD SP, 3

    ISUB R8, 1
    JMP  __insert_shift_loop

__insert_store_value:
    ;; --- Store the new value at the resolved position ---
    MOV  R4, R7
    CIF  R4                    ; R4 = boxed float position key

    PUSH R1                    ; table pointer
    PUSH R4                    ; key = position
    PUSH R3                    ; value to insert
    CALL __builtin_table_set
    IADD SP, 3

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
    CALL __unbox_table   ; R0 = raw table header address

    ;; --- VALIDATION: Use R1 and R2 (scratch) to preserve R0 ---
    MOV  R1, R0          ; Copy for null check
    IEQ  R1, 0
    JT   R1, __table_len_invalid

    MOV  R2, R0          ; Copy for ROM check (R0 still intact!)
    IGE  R2, 0x20000000
    JT   R2, __table_len_invalid

    MOV  R0, [R0+1]     ; Read array length from header word 1
    CIF  R0             ; Convert to float
    MOV  SP, BP
    POP  BP
    RET

__table_len_invalid:
    MOV  R0, 0
    CIF  R0
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

;; ===========================================================================
;; LUA TABLE LIBRARY IMPLEMENTATION FOR V32LUA
;; ===========================================================================
;;
;; This file implements the standard Lua table library functions for the v32lua
;; compiler targeting the Vircon32 fantasy console.
;;
;; Implemented functions:
;; - table.insert(t, [pos], value)  - Already exists as __builtin_table_insert
;; - table.remove(t, [pos])          - Remove element at position
;; - table.sort(t, [comp])          - Sort table elements in-place
;; - table.concat(t, [sep], [i], [j]) - Concatenate array elements
;; - table.move(a1, f, e, t, [a2])  - Move elements between tables
;; - table.pack(...)                - Pack arguments into table with .n field
;; - table.unpack(t, [i], [j])      - Unpack table elements as multiple returns
;;
;; ===========================================================================

;; ===========================================================================
;; SECTION: TABLE REMOVE
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; table.remove(t, [pos]) - Removes and returns element at position pos
;; If pos is nil or > length, removes and returns last element
;; Shifts elements left to fill the gap
;;
;; Incoming Stack: [BP+3] = Tagged Table Pointer, [BP+2] = Position (optional)
;; Returns: R0 = removed value
;; Register Usage: R1-R8
;; ---------------------------------------------------------------------------
__builtin_table_remove:
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

    ;; --- Load arguments ---
    MOV  R1, [BP+3]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+2]          ; R2 = Position (may be NIL)

    ;; --- Validate table ---
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_TABLE
    JF   R3, __runtime_error_not_table

    ;; --- Unbox table pointer ---
    AND  R1, BOXED_PAYLOAD   ; R1 = raw table header address

    ;; --- Get current length ---
    MOV  R3, [R1+1]          ; R3 = current array length

    ;; --- Handle default position (NIL or > length = remove last) ---
    MOV  R4, R2
    IEQ  R4, BOXED_NIL
    JT   R4, __table_remove_last

    ;; Convert position to integer if it's a float
    MOV  R4, R2
    AND  R4, NAN_VALUE
    IEQ  R4, NAN_VALUE
    JT   R4, __table_remove_check_position

    ;; It's a float, convert to integer
    MOV  R4, R2
    CFI  R4
    MOV  R5, R4
    CIF  R5
    INE  R5, R2
    JT   R5, __table_remove_invalid_position

__table_remove_check_position:
    ;; --- Resolve negative positions: count backward from the end,
    ;; matching table.insert's convention (resolved = length + pos + 1).
    ;; e.g. table.remove(t, -1) removes the last element. Previously any
    ;; position < 1 -- including legitimate negative ones -- fell straight
    ;; into the "invalid position" bailout below without ever being
    ;; resolved, so table.remove(t, -1) always returned nil without
    ;; touching the table.
    MOV  R8, R4
    ILT  R8, 0
    JF   R8, __table_remove_bounds_check
    MOV  R8, R3
    IADD R8, R4
    IADD R8, 1
    MOV  R4, R8

__table_remove_bounds_check:
    ;; R4 now contains integer position (use R8 for comparisons)
    MOV  R8, R4
    ILT  R8, 1
    JT   R8, __table_remove_invalid_position
    MOV  R8, R4
    IGT  R8, R3
    JT   R8, __table_remove_last
    JMP  __table_remove_at_position

__table_remove_last:
    MOV  R4, R3              ; Position = length (last element)

__table_remove_at_position:
    ;; --- Get array data pointer ---
    MOV  R5, [R1+2]          ; R5 = array data pointer

    ;; --- Check if array exists ---
    MOV  R6, R5
    IEQ  R6, 0
    JT   R6, __table_remove_hash_path   ; No array (the common case: __builtin_table_set's
                                     ; reallocation path is currently a stub, so array-
                                     ; backed tables never actually exist) -> use the
                                     ; hash-backed slow path instead of silently no-op'ing.

    ;; --- Calculate address of element to remove ---
    MOV  R6, R5
    IADD R6, R4
    ISUB R6, 1               ; Address = array_ptr + (position - 1)

    ;; --- Save the value to return ---
    MOV  R7, [R6]            ; R7 = value to return

    ;; --- Shift elements left to fill the gap ---
    MOV  R8, R4              ; R8 = position to remove

__table_remove_shift_loop:
    MOV  R9, R8
    ILT  R9, R3
    JF   R9, __table_remove_update_length

    MOV  R9, R5
    IADD R9, R8
    ISUB R9, 1

    MOV  R10, R5
    IADD R10, R8
    ISUB R10, 2

    MOV  R11, [R9]
    MOV  [R10], R11

    IADD R8, 1
    JMP  __table_remove_shift_loop

__table_remove_update_length:
    ISUB R3, 1
    MOV  [R1+1], R3

    MOV  R0, R7
    JMP  __table_remove_done

;; ---------------------------------------------------------------------------
;; HASH PATH: element lives in the hash bucket, not the (currently always-
;; empty) contiguous array. Shift down via table_get/table_set instead of
;; touching array memory directly. NOTE: table_get only callee-saves R1-R7,
;; so every value that must survive a sub-CALL here is kept in R1-R7 -- R8+
;; is NOT safe to hold state in across these calls.
;; ---------------------------------------------------------------------------
__table_remove_hash_path:
    ;; value_to_return = get(table, position)
    MOV  R5, R4
    CIF  R5                   ; R5 = float(position)
    MOV  R6, R1
    OR   R6, BOXED_TABLE      ; R6 = re-tagged table pointer
    PUSH R6
    PUSH R5
    CALL __builtin_table_get
    IADD SP, 2
    MOV  R7, R0               ; R7 = value to return (preserved: within R1-R7)

    MOV  R2, R4                ; R2 = shift index i, starting at position
__table_remove_hash_shift_loop:
    MOV  R5, R2
    ILT  R5, R3                ; i < length ?
    JF   R5, __table_remove_hash_shift_done

    ;; tmp = get(table, i+1)
    MOV  R5, R2
    IADD R5, 1
    CIF  R5
    MOV  R6, R1
    OR   R6, BOXED_TABLE
    PUSH R6
    PUSH R5
    CALL __builtin_table_get
    IADD SP, 2
    MOV  R5, R0                ; R5 = fetched value

    ;; set(table, i, tmp)
    MOV  R6, R1
    OR   R6, BOXED_TABLE
    MOV  R0, R2
    CIF  R0                    ; R0 = float(i)
    PUSH R6
    PUSH R0
    PUSH R5
    CALL __builtin_table_set
    IADD SP, 3

    IADD R2, 1
    JMP  __table_remove_hash_shift_loop

__table_remove_hash_shift_done:
    ;; --- FIX: clear the now-vacated slot ---
    ;; The shift loop above only ever OVERWRITES each slot with the NEXT
    ;; slot's value -- it never actually deletes anything -- so the very
    ;; last slot (at the OLD length's key, still held in R3 here) keeps a
    ;; live, non-nil duplicate forever. Any subsequent `t[k]` read past
    ;; the new (shrunk) length incorrectly still finds that duplicate
    ;; instead of nil, since the hash-fallback read path scans for the
    ;; key directly and never consults the tracked length at all. This is
    ;; exactly what makes the extremely common
    ;; `while t[1] ~= nil do table.remove(t, 1) end` idiom loop forever --
    ;; index 1 never actually becomes nil no matter how many elements are
    ;; removed.
    ;;
    ;; Storing BOXED_NIL at the vacated key matches this runtime's
    ;; established "nil-valued hash entry == absent" convention (see
    ;; __builtin_next's own doc comment). This single table_set call also
    ;; replaces the old manual "ISUB R3,1; MOV [R1+1],R3" entirely:
    ;; __builtin_table_set's own nil-handling logic
    ;; (__builtin_table_set_hash_maybe_shrink) already clamps the tracked
    ;; length down to (key - 1) whenever a nil is stored at a key within
    ;; the current length -- which the key we're storing here (the OLD
    ;; length, unchanged since before this loop) always is. Letting it
    ;; do that bookkeeping itself avoids two separate, easy-to-desync
    ;; length writes.
    MOV  R5, R3
    CIF  R5                    ; R5 = float(old length) -- the vacated key
    MOV  R6, R1
    OR   R6, BOXED_TABLE
    MOV  R0, BOXED_NIL
    PUSH R6
    PUSH R5
    PUSH R0
    CALL __builtin_table_set   ; also shrinks tracked length to (old_length - 1)
    IADD SP, 3

    MOV  R0, R7
    JMP  __table_remove_done

__table_remove_not_found:
    MOV  R0, BOXED_NIL
    JMP  __table_remove_done

__table_remove_invalid_position:
    MOV  R0, BOXED_NIL

__table_remove_done:
    ;; --- Callee-Restore ---
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

;; ===========================================================================
;; SECTION: TABLE SORT
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; table.sort(t, [comp]) - Sorts table elements in-place
;; Uses simple bubble sort for now (can be optimized later)
;;
;; Incoming Stack: [BP+4] = Tagged Table Pointer, [BP+3] = Compare function (optional)
;; Returns: none (table sorted in-place)
;; Register Usage: R1-R10
;; ---------------------------------------------------------------------------
__builtin_table_sort:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: Preserve 10 working registers ---
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

    ;; --- Load arguments ---
    MOV  R1, [BP+4]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+3]          ; R2 = Compare function (may be NIL)

    ;; --- Validate table ---
    MOV  R3, R1
    AND  R3, BOXED_DATA
    IEQ  R3, BOXED_TABLE
    JF   R3, __runtime_error_not_table

    ;; --- Unbox table pointer ---
    AND  R1, BOXED_PAYLOAD   ; R1 = raw table header address

    ;; --- Get array info ---
    MOV  R3, [R1+1]          ; R3 = array length
    MOV  R4, [R1+2]          ; R4 = array data pointer

    ;; --- Check if array exists or has elements ---
    MOV  R5, R4
    IEQ  R5, 0
    JT   R5, __table_sort_done

    MOV  R5, R3
    ILT  R5, 2
    JT   R5, __table_sort_done      ; Need at least 2 elements to sort

    ;; --- Bubble sort implementation ---
    MOV  R5, R3              ; R5 = outer loop counter (n)
    ISUB R5, 1

__table_sort_outer_loop:
    MOV  R6, 0               ; R6 = inner loop counter (i)
    MOV  R7, R5              ; R7 = outer loop limit

__table_sort_inner_loop:
    MOV  R8, R6
    ILT  R8, R7
    JF   R8, __table_sort_outer_continue

    ;; --- Compare elements at positions R6+1 and R6+2 ---
    ;; Calculate address of element i
    MOV  R8, R4
    IADD R8, R6

    ;; Calculate address of element i+1
    MOV  R9, R4
    IADD R9, R6
    IADD R9, 1

    ;; Load values
    MOV  R10, [R8]           ; R10 = t[i]
    MOV  R11, [R9]           ; R11 = t[i+1]

    ;; For now, use simple numeric comparison
    ;; TODO: Implement custom compare function support

    ;; Check if R10 is a number (not NaN-boxed)
    MOV  R8, R10
    AND  R8, NAN_VALUE
    IEQ  R8, NAN_VALUE
    JT   R8, __table_sort_compare_as_float

    ;; It's a number, convert R10 to integer
    CFI  R10

    ;; Check if R11 is a number
    MOV  R8, R11
    AND  R8, NAN_VALUE
    IEQ  R8, NAN_VALUE
    JT   R8, __table_sort_compare_as_float

    ;; It's a number, convert R11 to integer
    CFI  R11

    ;; Compare R10 and R11 (use R8 for comparison result)
    MOV  R8, R10
    ILT  R8, R11
    JT   R8, __table_sort_no_swap
    JMP  __table_sort_swap

__table_sort_compare_as_float:
    ;; For non-numbers, use direct float comparison
    FLT  R8, R10
    JT   R8, __table_sort_no_swap

__table_sort_swap:
    ;; --- Swap elements ---
    MOV  R8, R4
    IADD R8, R6              ; Address of t[i]

    MOV  R9, R4
    IADD R9, R6
    IADD R9, 1               ; Address of t[i+1]

    MOV  R10, [R8]           ; Load t[i]
    MOV  R11, [R9]           ; Load t[i+1]

    MOV  [R8], R11           ; Store t[i+1] at t[i]
    MOV  [R9], R10           ; Store t[i] at t[i+1]

__table_sort_no_swap:
    IADD R6, 1
    JMP  __table_sort_inner_loop

__table_sort_outer_continue:
    ISUB R5, 1
    MOV  R8, R5
    ILT  R8, 0
    JF   R8, __table_sort_outer_loop

__table_sort_done:
    ;; --- Callee-Restore ---
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
;; __concat_make_empty_string: allocate a fresh zero-length RAM string.
;; Output: R0 = boxed empty string. Clobbers: R0, R1, R2 only.
;; ---------------------------------------------------------------------------
__concat_make_empty_string:
    MOV  R1, [HEAP_POINTER]   ; R1 = base address for this new string
    MOV  R2, 0
    MOV  [R1], R2             ; write null terminator
    MOV  R0, R1
    IADD R0, 1
    MOV  [HEAP_POINTER], R0   ; bump heap pointer past the 1 byte used
    MOV  R0, R1
    OR   R0, BOXED_RAMSTRING  ; box the STRING BASE (not the bumped pointer)
    RET

;; ---------------------------------------------------------------------------
;; table.concat(t, [sep], [i], [j]) - Concatenates array elements into a string
;;
;; Incoming Stack (pushed t, sep, i, j in that order):
;;   [BP+5] = t (boxed table pointer)
;;   [BP+4] = sep (boxed string, or BOXED_NIL for "no separator")
;;   [BP+3] = i (boxed float, or BOXED_NIL for "default 1")
;;   [BP+2] = j (boxed float, or BOXED_NIL for "default #t")
;; Returns: R0 = boxed result string
;;
;; REPLACES the previous stub, which ignored the separator entirely,
;; returned the first element raw/unstringified instead of concatenating,
;; and returned BOXED_NIL instead of "" for an empty range.
;;
;; STACK-OFFSET NOTE: the previous version of this routine documented and
;; read from [BP+6]..[BP+3], one slot higher across the board than every
;; other proven N-argument builtin in this file ([BP+(N+1)]..[BP+2] --
;; see table_get, table_insert). That looks like an authoring bug in the
;; abandoned stub. This rewrite uses the established convention instead:
;; [BP+5]..[BP+2] for 4 arguments, matching emit_table_concat_intrinsic's
;; push order (t, sep, i, j).
;; ---------------------------------------------------------------------------
__builtin_table_concat:
    PUSH BP
    MOV  BP, SP
    ISUB SP, 6   ; [BP-1]=i  [BP-2]=j  [BP-3]=accumulator  [BP-4]=loop idx
                 ; [BP-5]=resolved sep  [BP-6]=first-element flag

    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R4
    PUSH R5
    PUSH R6
    PUSH R7
    PUSH R8

    ;; --- Validate table type up front ---
    MOV  R1, [BP+5]
    MOV  R2, R1
    AND  R2, BOXED_DATA
    IEQ  R2, BOXED_TABLE
    JF   R2, __runtime_error_not_table

    ;; --- Resolve j: default to #t if nil ---
    MOV  R1, [BP+2]
    MOV  R2, R1
    IEQ  R2, BOXED_NIL
    JF   R2, __concat_j_given
    MOV  R3, [BP+5]        ; table pointer (still boxed -- __builtin_len wants it boxed)
    PUSH R3
    CALL __builtin_len      ; R0 = float length
    IADD SP, 1
    MOV  R1, R0
__concat_j_given:
    CFI  R1
    MOV  [BP-2], R1

    ;; --- Resolve i: default to 1 if nil ---
    MOV  R1, [BP+3]
    MOV  R2, R1
    IEQ  R2, BOXED_NIL
    JF   R2, __concat_i_given
    MOV  R1, 1.0
__concat_i_given:
    CFI  R1
    MOV  [BP-1], R1

    ;; --- Resolve sep: default to a fresh empty string if nil ---
    MOV  R1, [BP+4]
    MOV  R2, R1
    IEQ  R2, BOXED_NIL
    JF   R2, __concat_sep_given
    CALL __concat_make_empty_string
    MOV  R1, R0
__concat_sep_given:
    MOV  [BP-5], R1

    ;; --- Seed accumulator with a fresh empty string, first-flag = true ---
    CALL __concat_make_empty_string
    MOV  [BP-3], R0
    MOV  R1, 1
    MOV  [BP-6], R1

    MOV  R1, [BP-1]
    MOV  [BP-4], R1      ; loop index = i

__concat_loop:
    MOV  R1, [BP-4]
    MOV  R2, [BP-2]
    IGT  R1, R2
    JT   R1, __concat_done

    ;; --- If not the first element, append the separator first ---
    MOV  R1, [BP-6]
    IEQ  R1, 1
    JT   R1, __concat_skip_sep

    MOV  R3, [BP-3]       ; accumulator
    PUSH R3
    MOV  R4, [BP-5]       ; separator
    PUSH R4
    CALL __builtin_strcat
    IADD SP, 2
    MOV  [BP-3], R0       ; accumulator = accumulator .. sep

__concat_skip_sep:
    ;; --- Fetch element and append it ---
    MOV  R5, [BP-4]        ; raw int loop index
    MOV  R6, R5
    CIF  R6                ; boxed float key
    MOV  R7, [BP+5]        ; table pointer
    PUSH R7
    PUSH R6
    CALL __builtin_table_get
    IADD SP, 2
    MOV  R8, R0            ; R8 = element value (any type; strcat coerces)

    MOV  R3, [BP-3]        ; accumulator
    PUSH R3
    PUSH R8
    CALL __builtin_strcat
    IADD SP, 2
    MOV  [BP-3], R0        ; accumulator = accumulator .. tostring(element)

    ;; --- Clear the first-flag, advance loop index ---
    MOV  R1, 0
    MOV  [BP-6], R1
    MOV  R1, [BP-4]
    IADD R1, 1
    MOV  [BP-4], R1
    JMP  __concat_loop

__concat_done:
    MOV  R0, [BP-3]         ; R0 = final accumulator string

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

;; ===========================================================================
;; SECTION: TABLE MOVE
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; table.move(a1, f, e, t, [a2]) - Copies elements from a1[f..e] to a2 starting at t
;; If a2 is nil, a1 is used as destination
;;
;; Incoming Stack: [BP+6] = Source Table (a1)
;;                 [BP+5] = Start index (f)
;;                 [BP+4] = End index (e)
;;                 [BP+3] = Target index (t)
;;                 [BP+2] = Destination Table (a2, optional)
;; Returns: R0 = destination table
;; Register Usage: R1-R10
;; ---------------------------------------------------------------------------
__builtin_table_move:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: Preserve 10 working registers ---
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

    ;; --- Load arguments ---
    MOV  R1, [BP+6]          ; R1 = Source Table (a1)
    MOV  R2, [BP+5]          ; R2 = Start index (f)
    MOV  R3, [BP+4]          ; R3 = End index (e)
    MOV  R4, [BP+3]          ; R4 = Target index (t)
    MOV  R5, [BP+2]          ; R5 = Destination Table (a2, may be NIL)

    ;; --- Validate source table ---
    MOV  R6, R1
    AND  R6, BOXED_DATA
    IEQ  R6, BOXED_TABLE
    JF   R6, __runtime_error_not_table

    ;; --- Unbox source table ---
    AND  R1, BOXED_PAYLOAD   ; R1 = raw source table header

    ;; --- Set destination table ---
    MOV  R6, R5
    IEQ  R6, BOXED_NIL
    JT   R6, __table_move_dest_is_source

    ;; Validate destination table
    AND  R6, BOXED_DATA
    IEQ  R6, BOXED_TABLE
    JF   R6, __runtime_error_not_table
    AND  R5, BOXED_PAYLOAD   ; R5 = raw destination table header
    JMP  __table_move_dest_set

__table_move_dest_is_source:
    MOV  R5, R1              ; Use source as destination

__table_move_dest_set:
    ;; --- Get array info ---
    MOV  R6, [R1+1]          ; R6 = source array length
    MOV  R7, [R1+2]          ; R7 = source array data pointer
    MOV  R8, [R5+1]          ; R8 = destination array length
    MOV  R9, [R5+2]          ; R9 = destination array data pointer

    ;; --- Convert indices to integers ---
    CFI  R2                  ; Convert f to integer
    CFI  R3                  ; Convert e to integer
    CFI  R4                  ; Convert t to integer

    ;; --- Validate indices (use R10 for comparison results) ---
    MOV  R10, R2
    ILT  R10, 1
    JT   R10, __table_move_invalid_range
    MOV  R10, R2
    IGT  R10, R6
    JT   R10, __table_move_invalid_range
    MOV  R10, R3
    ILT  R10, R2
    JT   R10, __table_move_invalid_range
    MOV  R10, R3
    IGT  R10, R6
    JT   R10, __table_move_end_adjust
    JMP  __table_move_indices_valid

__table_move_end_adjust:
    MOV  R3, R6

__table_move_indices_valid:
    MOV  R10, R4
    ILT  R10, 1
    JT   R10, __table_move_invalid_range

    ;; --- Calculate number of elements to copy ---
    MOV  R10, R3
    ISUB R10, R2            ; R10 = e - f
    IADD R10, 1             ; R10 = e - f + 1 (number of elements)

    ;; --- Check if destination has enough space ---
    MOV  R11, R4
    IADD R11, R10
    ISUB R11, 1              ; R11 = t + (e - f) (last destination index)

    IGT  R11, R8
    JT   R11, __table_move_resize_destination

__table_move_copy_loop:
    ;; --- Copy elements from source to destination ---
    MOV  R11, 0              ; R11 = counter

__table_move_copy_iteration:
    MOV  R12, R11
    ILT  R12, R10
    JF   R12, __table_move_done

    ;; Calculate source address: source_array + (f + counter - 1)
    MOV  R12, R7
    IADD R12, R2
    IADD R12, R11
    ISUB R12, 1

    ;; Calculate destination address: dest_array + (t + counter - 1)
    MOV  R13, R9
    IADD R13, R4
    IADD R13, R11
    ISUB R13, 1

    ;; Copy value (use R8 as temporary, avoiding R14/R15)
    MOV  R8, [R12]
    MOV  [R13], R8

    IADD R11, 1
    JMP  __table_move_copy_iteration

__table_move_resize_destination:
    ;; TODO: Implement destination table resizing
    ;; For now, just copy what we can
    JMP  __table_move_copy_loop

__table_move_invalid_range:
    MOV  R0, BOXED_NIL
    JMP  __table_move_return

__table_move_done:
    ;; --- Update destination length if needed ---
    IADD R8, R4
    IADD R8, R10
    ISUB R8, 1              ; New length = max(old_length, t + count - 1)

    MOV  R11, [R5+1]        ; Current destination length
    IGT  R8, R11
    JT   R8, __table_move_update_length
    MOV  R8, R11

__table_move_update_length:
    MOV  [R5+1], R8          ; Update destination length

    ;; --- Return destination table ---
    MOV  R0, R5
    OR   R0, BOXED_TABLE ; Re-box the destination table pointer

__table_move_return:
    ;; --- Callee-Restore ---
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

;; ===========================================================================
;; SECTION: TABLE PACK
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; table.pack(...) - Packs all arguments into a new table with .n field
;;
;; This is implemented in C as it needs variable argument handling
;; Assembly version would need stack manipulation
;;
;; For now, this is a placeholder. The actual implementation should be in C
;; to handle the variable arguments properly.
;;
;; Returns: R0 = new table with .n field
;; ---------------------------------------------------------------------------
__builtin_table_pack:
    PUSH BP
    MOV  BP, SP

    ;; --- Callee-Save: Preserve working registers ---
    PUSH R1
    PUSH R2
    PUSH R3

    ;; --- Create new table ---
    CALL __builtin_table_new
    MOV  R1, R0              ; R1 = new table

    ;; --- TODO: This needs to be implemented in C to access variable arguments ---
    ;; For now, return empty table

    ;; --- Callee-Restore ---
    POP  R3
    POP  R2
    POP  R1

    MOV  SP, BP
    POP  BP
    RET

;; ===========================================================================
;; SECTION: TABLE UNPACK
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; table.unpack(t, [i], [j]) - Returns elements from table as multiple values
;;
;; Incoming Stack: [BP+4] = Tagged Table Pointer
;;                 [BP+3] = Start index (optional, may be NIL)
;;                 [BP+2] = End index (optional, may be NIL)
;; Returns: Multiple values on stack (Lua convention)
;; Register Usage: R1-R8
;; ---------------------------------------------------------------------------
__builtin_table_unpack:
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

    ;; --- Load arguments ---
    MOV  R1, [BP+4]          ; R1 = Tagged Table Pointer
    MOV  R2, [BP+3]          ; R2 = Start index (may be NIL)
    MOV  R3, [BP+2]          ; R3 = End index (may be NIL)

    ;; --- Validate table ---
    MOV  R4, R1
    AND  R4, BOXED_DATA
    IEQ  R4, BOXED_TABLE
    JF   R4, __runtime_error_not_table

    ;; --- Unbox table pointer ---
    AND  R1, BOXED_PAYLOAD   ; R1 = raw table header address

    ;; --- Get array info ---
    MOV  R4, [R1+1]          ; R4 = array length
    MOV  R5, [R1+2]          ; R5 = array data pointer

    ;; --- Set default start index = 1 ---
    MOV  R6, R2
    IEQ  R6, BOXED_NIL
    JT   R6, __table_unpack_start_default

    CFI  R6
    JMP  __table_unpack_start_set

__table_unpack_start_default:
    MOV  R6, 1

__table_unpack_start_set:
    ;; --- Set default end index = length ---
    MOV  R7, R3
    IEQ  R7, BOXED_NIL
    JT   R7, __table_unpack_end_default

    CFI  R7
    JMP  __table_unpack_end_set

__table_unpack_end_default:
    MOV  R7, R4

__table_unpack_end_set:
    ;; --- Validate indices (use R8 for comparison results) ---
    MOV  R8, R6
    ILT  R8, 1
    JT   R8, __table_unpack_invalid_range
    MOV  R8, R4
    IGT  R8, R6
    JT   R8, __table_unpack_invalid_range
    MOV  R8, R7
    ILT  R8, R6
    JT   R8, __table_unpack_invalid_range
    MOV  R8, R4
    IGT  R8, R7
    JT   R8, __table_unpack_end_adjust
    JMP  __table_unpack_validate_done

__table_unpack_end_adjust:
    MOV  R7, R4

__table_unpack_validate_done:
    ;; --- Calculate number of elements to return ---
    MOV  R8, R7
    ISUB R8, R6
    IADD R8, 1              ; R8 = number of elements to return

    ;; --- For now, return first element (simplified) ---
    ;; TODO: Implement proper multiple return values
    MOV  R9, R5
    IADD R9, R6
    ISUB R9, 1
    MOV  R0, [R9]
    JMP  __table_unpack_done

__table_unpack_invalid_range:
    MOV  R0, BOXED_NIL

__table_unpack_done:
    ;; --- Callee-Restore ---
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

;; ===========================================================================
;; SECTION: UTILITY FUNCTIONS
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; Helper: Validate and unbox table pointer
;; Input: R0 = Tagged table pointer
;; Output: R0 = Raw table pointer, or jump to error
;; Clobbers: R1
;; ---------------------------------------------------------------------------
__unbox_table_validated:
    MOV  R1, R0
    AND  R1, BOXED_DATA
    IEQ  R1, BOXED_TABLE
    JF   R1, __runtime_error_not_table
    AND  R0, BOXED_PAYLOAD
    RET
