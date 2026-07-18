;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Vircon32 NaN-Boxed Routines for Lua Runtime Environment (runtime.s)
;; Audited & Consolidated Architecture
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; =====================================================================================
;; SECTION 1: MEMORY MANAGEMENT & ERROR HANDLING
;; =====================================================================================

;; -------------------------------------------------------------------------------------
;; Memory Allocator: Carves out raw word blocks from heap_pointer
;; Incoming Stack: [BP+2] = Number of words requested
;; Returns: R0 = Raw pointer to allocated memory (or 0 if Out-Of-Memory)
;; -------------------------------------------------------------------------------------
__malloc:
    PUSH BP
    MOV  BP, SP
    
    MOV  R1, [BP+2]          ; R1 = Requested size in words
    MOV  R0, [heap_pointer]  ; R0 = Address of new allocation block
    
    ;; Calculate potential new heap top
    MOV  R2, R0
    IADD R2, R1              ; R2 = Potential new heap_pointer
    
    ;; Stack Collision Check: SP grows down, Heap grows up!
    ;; We maintain a 1024-word safety buffer between Heap and Stack.
    MOV  R3, SP
    ISUB R3, 1024            ; R3 = Lowest safe memory address for stack
    MOV  R6, R2
    IGE  R6, R3              ; Will the new heap top collide with the stack?
    JT   R6, __malloc_oom    ; If Heap >= SafeBoundary, allocation fails!
    
    ;; Success: Commit new heap top and return base address in R0
    MOV  [heap_pointer], R2
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
    AND R1, 0xFF800000          ; Isolate upper tag bits (adjust if your tag mask differs)
    IEQ R1, 0xFF800000          ; Is this tagged as a boxed function pointer?
    JT  R1, __exec_valid            ; If valid, jump to unboxing and execution

    ; 2. Tag validation failed! We attempted to call nil, a number, or a table.
    JMP __runtime_error_not_callable

__exec_valid:
    ; 3. Unbox the address and restore the Vircon32 memory page bit
    AND R0, 0x003FFFFF          ; Strip NaN-box tag bits
    OR  R0, 0x20000000          ; Restore Vircon32 code memory page bit
    
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

    ;; 1. Allocate space for Table struct (4 words: flags, array_len, array_ptr, hash_ptr) 
    MOV  R0, 4 
    PUSH R0 
    CALL __malloc 
    ISUB SP, 1 
    
    ;; Check for out-of-memory (if R0 == 0, handle OOM error) 
    MOV  R1, R0
    IEQ  R1, 0 
    JT   R1, __oom_handler 
    
    ;; 2. Initialize table header in data memory (Stripped redundant +0 offset) 
    MOV  R1, 0
    MOV  [R0], R1            ; flags / metatable pointer = nil 
    MOV  [R0+1], R1          ; array part length = 0 
    MOV  [R0+2], R1          ; array part pointer = null 
    MOV  [R0+3], R1          ; hash part pointer = null 
    
    ;; 3. AUDITED: Box the raw data heap address as a Lua Table! 
    OR   R0, 0x7F800000 
    
    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Table Read Indexer: t[k] -> Returns Value in R0 (or Nil if not found) 
;; Incoming Stack: [BP+3] = Tagged Table Pointer, [BP+2] = Key 
;; -------------------------------------------------------------------------------------
__builtin_table_get:
    PUSH BP
    MOV  BP, SP
    
    MOV  R1, [BP+3]          ; R1 = Tagged Table Pointer (0x7F80....) 
    MOV  R2, [BP+2]          ; R2 = Key (must be preserved for fallback!) 

    ;; FAST-PATH CHECK 1: Is Key an unboxed IEEE Float? 
    MOV  R3, R2 
    AND  R3, 0x7F800000      ; Isolate exponent bits
    IEQ  R3, 0x7F800000      ; Are they all 1s? (If so, it's tagged/NaN)
    JT   R3, __table_get_fallback

    ;; FAST-PATH CHECK 2: Is Key an integer >= 1? 
    MOV  R3, R2              ; Copy float Key to R3 (preserves original in R2) 
    CFI  R3                  ; Vircon32 in-place conversion: R3 = (int) R3 
    MOV  R4, R3              ; Copy integer index to R4 for destructive comparison 
    ILT  R4, 1               ; Destructive test: Is integer key < 1? 
    JT   R4, __table_get_fallback ; Zero or negative keys go to fallback! 

    ;; FAST-PATH CHECK 3: Is Key within Array Capacity? 
    MOV  R4, R1 
    AND  R4, 0x003FFFFF      ; Unbox Table pointer into R4 
    MOV  R5, [R4+1]          ; R5 = Array Capacity (from Header Word 1) 
    MOV  R9, R3              ; Copy integer index R3 to R9
    IGT  R9, R5              ; Destructive test: Is Key > Capacity? 
    JT   R9, __table_get_fallback ; Out-of-bounds integers go to fallback! 

    ;; FAST-PATH EXECUTION: O(1) Contiguous Array Read 
    MOV  R5, [R4+2]          ; R5 = Array Data Pointer (from Header Word 2) 
    ISUB R3, 1               ; Convert 1-based Lua index to 0-based memory offset 
    IADD R5, R3              ; Memory Address = ArrayPtr + (Key - 1) 
    MOV  R0, [R5]            ; Read value directly from heap buffer! 
    JMP  __table_get_done

;; --- FALLBACK EXECUTION: Association List Scan ---
__table_get_fallback:
    MOV  R4, R1 
    AND  R4, 0x003FFFFF      ; Unbox Table pointer 
    MOV  R5, [R4+3]          ; R5 = Hash Data Pointer (from Header Word 3) 
    MOV  R9, R5              ; use R9 as scratch to prevent destructive comparison
    IEQ  R9, 0               ; Is Hash Buffer null (no sparse keys stored)? 
    JT   R9, __table_get_not_found 

    MOV  R6, [R5]            ; R6 = PairCount (how many pairs are stored) 
    MOV  R7, R5              ; Setup R7 as running memory pointer
    IADD R7, 2               ; Advance R7 to point directly at Key0 (Offset 2 words) 

__table_get_scan_loop:
    IEQ  R6, 0               ; Have we checked all stored pairs? 
    JT   R6, __table_get_not_found 
    
    MOV  R8, [R7]            ; Load Stored Key directly from running pointer R7
    MOV  R9, R8              ; R9 as scratch
    IEQ  R9, R2              ; ZERO-COST COMPARISON: Does Stored Key == Search Key? 
    JT   R9, __table_get_found ; Match found! 
    
    IADD R7, 2               ; Advance pointer by 2 words (skip Value slot to next Key) 
    ISUB R6, 1               ; Decrement remaining PairCount 
    JMP  __table_get_scan_loop 

__table_get_found:
    IADD R7, 1               ; Value is stored 1 word after the matching Key 
    MOV  R0, [R7]            ; Read Value into return register R0
    JMP  __table_get_done

__table_get_not_found:
    MOV  R0, 0xFFC00000      ; Key does not exist -> Return canonical Lua Nil! 

__table_get_done:
    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Table Write Indexer: t[k] = v -> Writes Value into Table Storage 
;; Incoming Stack: [BP+4] = Table Pointer, [BP+3] = Key, [BP+2] = Value 
;; -------------------------------------------------------------------------------------
__builtin_table_set:
    PUSH BP
    MOV  BP, SP
    
    MOV  R1, [BP+4]          ; R1 = Table Pointer 
    MOV  R2, [BP+3]          ; R2 = Key 
    MOV  R3, [BP+2]          ; R3 = Value to store 

    ;; --- 1. STRICT TABLE TYPE VALIDATION ---
    ;; Ensure R1 is actually a Table (0x7F80xxxx) before touching memory!
    MOV  R4, R1
    AND  R4, 0xFF800000      ; Isolate upper tag bits
    IEQ  R4, 0x7F800000      ; Is it tagged as a Table?
    JF   R4, __runtime_error_not_table ; Trap if indexing a string/func/nil!

    ;; --- 2. FAST-PATH VALIDATION ---
    MOV  R4, R2
    AND  R4, 0x7F800000      ; Isolate exponent bits
    IEQ  R4, 0x7F800000      ; Are all exponent bits 1s? (If so, it's tagged/NaN)
    JT   R4, __table_set_fallback

    MOV  R4, R2              ; Copy float Key to R4 
    CFI  R4                  ; Vircon32 in-place conversion: R4 = (int) R4 
    
    ;; Ensure float key had no fractional component (R4 == R2 mathematically)
    MOV  R5, R4
    CIF  R5                  ; Cast int back to float in R5
    INE  R5, R2              ; If (float)(int)Key != Key, it's fractional -> fallback!
    JT   R5, __table_set_fallback

    MOV  R5, R4              ; Copy integer index to R5 for comparison 
    ILT  R5, 1 
    JT   R5, __table_set_fallback 
    
    MOV  R5, R1 
    AND  R5, 0x003FFFFF      ; R5 = Unboxed Table Pointer (Guaranteed RAM address!)
    MOV  R6, [R5+1]          ; R6 = Array Capacity 
    MOV  R7, R4              ; Copy integer index R4 to R7 
    IGT  R7, R6 
    JT   R7, __table_set_fallback 

    ;; --- FAST-PATH EXECUTION: O(1) Contiguous Array Write ---
    MOV  R6, [R5+2]          ; R6 = Array Data Pointer 
    ISUB R4, 1               ; Convert 1-based Lua index to 0-based memory offset 
    IADD R6, R4              ; Memory Address = ArrayPtr + (Key - 1) 
    MOV  [R6], R3            ; Write Value directly into contiguous array slot! 
    JMP  __table_set_done

;; --- FALLBACK EXECUTION: Update Existing or Append New ---
;; --- FALLBACK EXECUTION: Chained Hash Bucket Traversal ---
__table_set_fallback:
    MOV  R5, R1
    AND  R5, 0x003FFFFF      ; Unbox Table pointer to raw RAM address
    MOV  R6, [R5+3]          ; R6 = Base Hash Data Pointer

    ;; 1. Ensure Base Hash Buffer exists
    INE  R6, 0               
    JT   R6, __table_set_bucket_loop

    ;; Allocate Base Bucket (16 words)
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R5
    MOV  R0, 16              
    PUSH R0
    CALL __malloc
    ISUB SP, 1
    POP  R5
    POP  R3
    POP  R2
    POP  R1

    MOV  R6, R0
    IEQ  R6, 0
    JT   R6, __oom_handler   ; Trap out-of-memory

    MOV  R7, 0
    MOV  [R6], R7            ; Word 0: PairCount = 0
    MOV  [R6+1], R7          ; Word 1: NextBucketPtr = 0x0 (Tail)
    MOV  [R5+3], R6          ; Link to Table Header Word 3

;; --- BUCKET SEARCH LOOP ---
;; R6 always points to the start of the CURRENT bucket being scanned
__table_set_bucket_loop:
    MOV  R7, [R6]            ; R7 = PairCount in current bucket
    MOV  R8, R6              
    IADD R8, 2               ; R8 points to Key0 of current bucket

__table_set_scan_pairs:
    IEQ  R7, 0               ; No more pairs in this specific bucket?
    JT   R7, __table_set_check_next_bucket
    
    MOV  R9, [R8]            ; Load stored Key
    IEQ  R9, R2              ; Does Stored Key == Search Key?
    JT   R9, __table_set_overwrite_val ; Found it -> Overwrite value!
    
    IADD R8, 2               ; Advance 2 words to next key
    ISUB R7, 1
    JMP  __table_set_scan_pairs

__table_set_overwrite_val:
    IADD R8, 1               ; Step from Key slot to Value slot
    MOV  [R8], R3            ; Update value in place
    JMP  __table_set_done

;; --- BUCKET CHAIN STEPPING ---
__table_set_check_next_bucket:
    MOV  R9, [R6+1]          ; Load NextBucketPtr (Word 1)
    IEQ  R9, 0               ; Is this the end of the chain (Next == 0x0)?
    JT   R9, __table_set_append_to_tail
    
    MOV  R6, R9              ; Step forward: Current Bucket = Next Bucket
    JMP  __table_set_bucket_loop ; Scan the next bucket in the chain!

;; --- APPEND NEW PAIR (We reached the tail and key wasn't found) ---
__table_set_append_to_tail:
    MOV  R7, [R6]            ; R7 = PairCount of the TAIL bucket
    IGE  R7, 7               ; Is this tail bucket completely full (7 pairs)?
    JT   R7, __table_set_allocate_extension_bucket

    ;; There is room in the current tail bucket! 
    ;; R8 already points to the exact unallocated word offset from our scan loop.
    MOV  [R8], R2            ; Store Key
    IADD R8, 1
    MOV  [R8], R3            ; Store Value
    
    ;; Increment PairCount in current bucket header
    IADD R7, 1
    MOV  [R6], R7
    JMP  __table_set_done

;; --- ALLOCATE EXTENSION BUCKET (Tail was full) ---
__table_set_allocate_extension_bucket:
    PUSH R1
    PUSH R2
    PUSH R3
    PUSH R6
    MOV  R0, 16              ; Request another 16-word chunk
    PUSH R0
    CALL __malloc
    ISUB SP, 1
    POP  R6
    POP  R3
    POP  R2
    POP  R1

    MOV  R8, R0              ; R8 = New Extension Bucket Address
    IEQ  R8, 0
    JT   R8, __oom_handler

    ;; Initialize New Extension Bucket
    MOV  R7, 1
    MOV  [R8], R7            ; Word 0: PairCount = 1 (We are adding a pair right now)
    MOV  R7, 0
    MOV  [R8+1], R7          ; Word 1: NextBucketPtr = 0x0 (This is the new tail)
    
    ;; Store the new Key/Value pair directly into Slot 0 of the new bucket
    MOV  [R8+2], R2          ; Word 2: Key0
    MOV  [R8+3], R3          ; Word 3: Val0

    ;; Link old tail bucket to this new extension bucket!
    MOV  [R6+1], R8          ; OldBucket[NextBucketPtr] = NewBucketAddress

__table_set_done:
    MOV  SP, BP
    POP  BP
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
;; Input:  R0 = NaN-boxed String (0x7F800000 for RAM, 0x7FC00000 for ROM)
;; Output: R0 = Raw Vircon32 Hardware Memory Address (Page bit applied if ROM)
;; Clobbers: R1
;; ===================================================================================
__unbox_string:
    MOV R1, R0
    AND R1, 0x80000000          ; Check Bit 31 (1 = RAM String, 0 = ROM String)
    AND R0, 0x003FFFFF          ; Strip the entire NaN tag (Leaves 22-bit offset)

    INE R1, 0                   ; If Bit 31 is non-zero, it is a RAM string
    JT  R1, __unbox_string_end  ; Jump to end (RAM addresses start at 0x00000000)

    ;; It is a ROM string: Apply Vircon32 Cartridge Page Bit (Bit 29)
    OR  R0, 0x20000000

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
    MOV  R0, [heap_pointer]  ; R0 = New string base (raw pointer)
    MOV  R5, R0              ; R5 = Write head

    ;; Advance heap_pointer = old_heap + left_len + right_len + 1
    MOV  R6, R0
    IADD R6, R2
    IADD R6, R4
    IADD R6, 1
    MOV  [heap_pointer], R6

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

    ;; Apply RAM Heap String Tag (0xFFC00000)
    OR   R0, 0xFFC00000      ; BOX: R0 untouched since Step 3, holds new string base!

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
    IN   R6, GPU_SelectedRegion  ; Save current region
    OUT  GPU_SelectedTexture, -1 ; Set BIOS font texture

    ;; 2. Load Parameters
    MOV  R1, [BP+4]          ; R1 = X Pixel Coordinate (Integer)
    MOV  R2, [BP+3]          ; R2 = Y Pixel Coordinate (Integer)
    MOV  R3, [BP+2]          ; R3 = Target Value to Print

__print_check_tag:
    ;; 3. SAFETY COERCION LAYER: Check for ROM vs RAM String tags
    MOV  R4, R3              ; Copy target value to scratch register R4
    AND  R4, 0xFFC00000      ; Isolate upper 10 bits (Tag)

    IEQ  R4, 0x7FC00000      ; Is it a ROM String Literal?
    JT   R4, __print_unbox_rom

    ;; Check if it's a RAM Heap String (Tag 0xFFC0xxxx with address >= 4)
    IEQ  R4, 0xFFC00000      ; Does it have the RAM String / Primitive tag?
    JF   R4, __print_coerce  ; If neither string tag, coerce!

    ;; It has tag 0xFFC00000. Make sure it's not Nil (0), False (1), or True (2)!
    MOV  R4, R3
    AND  R4, 0x003FFFFF      ; Isolate payload
    ILT  R4, 4               ; Is payload < 4 (Nil/False/True)?
    JT   R4, __print_coerce  ; If < 4, it's a boolean/nil -> coerce!

__print_unbox_ram:
    ;; 4a. Unbox RAM String: Keep raw 22-bit heap address (4MW limit)
    AND  R3, 0x003FFFFF      ; Isolate 22-bit raw RAM heap pointer
    JMP  __print_dispatch

__print_unbox_rom:
    ;; 4b. Unbox ROM String: Isolate offset and add ROM page bit
    AND  R3, 0x003FFFFF      ; Isolate up to 27-bit raw ROM offset
    OR   R3, 0x20000000      ; Restore Vircon32 CART page bit

__print_dispatch:
    ;; 5. Dispatch Unboxed Pointer to BIOS
    PUSH R3                  ; Push Unboxed Raw String Pointer
    PUSH R2                  ; Push Y Coordinate
    PUSH R1                  ; Push X Coordinate
    CALL __bios_print_text   ; Draw the string directly to the GPU screen
    ISUB SP, 3               ; Clean up arguments from stack

    ;; 6. Restore previous GPU texture and region
    OUT  GPU_SelectedTexture, R5 ; Restore previous texture
    OUT  GPU_SelectedRegion, R6  ; Restore previous region

    MOV  SP, BP
    POP  BP
    RET

__print_coerce:
    ;; Target is a Float, Boolean, Nil, Table, or Function.
    PUSH  R1                  ; ADD THIS: Preserve X coordinate
    PUSH  R2                  ; ADD THIS: Preserve Y coordinate
    PUSH  R3                  ; Push non-string value as argument
    CALL  __builtin_tostring  ; R0 now holds a Tagged String (ROM or RAM!)
    ISUB  SP, 1               ; Clean up argument from stack
    MOV   R3, R0              ; Replace target R3 with the new String pointer
    POP   R2                  ; ADD THIS: Restore Y coordinate
    POP   R1                  ; ADD THIS: Restore X coordinate
    JMP   __print_check_tag   ; Loop back to safely unbox the new string!

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
__builtin_eq:
    ;; Fast-path: If bitwise identical, they are strictly equal
    IEQ  R1, R2
    JT   R1, __eq_return_true

    ;; Validate LEFT Operand is a String (Tag 0x7FC0... or 0xFFC0... with payload >= 4)
    MOV  R3, R1
    AND  R3, 0xFFC00000
    IEQ  R3, 0x7FC00000
    JT   R3, __eq_left_valid
    IEQ  R3, 0xFFC00000
    JF   R3, __eq_return_false
    MOV  R3, R1
    AND  R3, 0x003FFFFF
    ILT  R3, 4
    JT   R3, __eq_return_false

__eq_left_valid:
    ;; Validate RIGHT Operand is a String
    MOV  R3, R2
    AND  R3, 0xFFC00000
    IEQ  R3, 0x7FC00000
    JT   R3, __eq_right_valid
    IEQ  R3, 0xFFC00000
    JF   R3, __eq_return_false
    MOV  R3, R2
    AND  R3, 0x003FFFFF
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
    MOV  R0, 0xFFC00002          ; Return boxed Boolean True
    RET

__eq_return_false:
    MOV  R0, 0xFFC00001          ; Return boxed Boolean False
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
    AND  R3, 0xFFC00000

    ;; Pass through ROM Strings unchanged
    IEQ  R3, 0x7FC00000
    JT   R3, __tostring_passthrough

    ;; Check for RAM Strings
    IEQ  R3, 0xFFC00000
    JF   R3, __tostring_check_primitives

    MOV  R4, R1
    AND  R4, 0x003FFFFF
    IGE  R4, 4
    JT   R4, __tostring_passthrough  ; It is a RAM String: return unchanged!

__tostring_check_primitives:
    ;; Add these three explicit checks:
    MOV  R6, R1
    IEQ  R6, 0xFFC00000
    JT   R6, __tostring_nil
    MOV  R6, R1
    IEQ  R6, 0xFFC00001
    JT   R6, __tostring_false
    MOV  R6, R1
    IEQ  R6, 0xFFC00002
    JT   R6, __tostring_true

    ;; Existing tag checks follow...
    MOV  R2, R1
    AND  R2, 0xFFC00000

    MOV  R3, R2 
    IEQ  R3, 0x7FC00000      ; Is it already a String? 
    JT   R3, __tostring_passthrough 
    
    MOV  R3, R2 
    IEQ  R3, 0x7F800000      ; Is it a Table? 
    JT   R3, __tostring_table 
    
    MOV  R3, R2 
    IEQ  R3, 0xFF800000      ; Is it a Function? 
    JT   R3, __tostring_function 
    
    ;; 3. Fallback: It must be a standard IEEE 754 Float! 
    ;; In __builtin_tostring float fallback:
    PUSH R1 
    CALL __builtin_ftoa 
    ISUB SP, 1 
    
    ;; Box as RAM Heap String (0xFFC00000) instead of ROM (0x7FC00000)
    OR   R0, 0xFFC00000      ; Box raw pointer as RAM String 
    JMP  __tostring_done

__tostring_nil:
    MOV  R0, __const_str_nil ; Load address of static "nil" string 
    OR   R0, 0x7FC00000      ; Box as String 
    JMP  __tostring_done

__tostring_false:
    MOV  R0, __const_str_false ; Load address of static "false" string 
    OR   R0, 0x7FC00000      ; Box as String 
    JMP  __tostring_done

__tostring_true:
    MOV  R0, __const_str_true ; Load address of static "true" string 
    OR   R0, 0x7FC00000      ; Box as String 
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
    OR   R0, 0x7FC00000      ; Box raw pointer as a valid Lua String

    MOV  SP, BP
    POP  BP
    RET

__format_function_address:
    PUSH BP
    MOV  BP, SP

    MOV  R0, __const_str_function
    OR   R0, 0x7FC00000      ; Box raw pointer as a valid Lua String

    MOV  SP, BP
    POP  BP
    RET

;; -------------------------------------------------------------------------------------
;; Built-in: Float to ASCII (Whole Integer Fast-Path)
;; Incoming Stack: [BP+2] = Raw IEEE Float
;; Returns: R0 = Raw Heap Pointer to null-terminated ASCII string (Unboxed)
;; -------------------------------------------------------------------------------------
__builtin_ftoa:
    PUSH BP
    MOV  BP, SP
    
    ;; Allocate a 16-word character buffer on the heap for the string
    MOV  R0, 16
    PUSH R0
    CALL __malloc            ; R0 = Base address of new string buffer
    ISUB SP, 1

    MOV  R1, [BP+2]          ; R1 = Float value
    CFI  R1                  ; Convert Float to Integer (in-place)
    
    MOV  R2, R0              ; R2 = Start of buffer
    MOV  R3, R0              ; R3 = End of string pointer (will advance)
    
    ;; Handle zero explicitly
    MOV  R4, R1
    INE  R4, 0               ; Overwrites R4, preserving R1
    JT   R4, __ftoa_extract_loop
    MOV  R4, '0'
    MOV  [R3], R4
    IADD R3, 1
    JMP  __ftoa_terminate

__ftoa_extract_loop:
    MOV  R5, R1
    IEQ  R5, 0               ; If quotient is 0, we are done extracting digits
    JT   R5, __ftoa_reverse_init
    
    MOV  R4, R1              ; R4 = Current number
    IMOD R4, 10              ; R4 = Remainder (Digit 0-9)
    IADD R4, '0'             ; Convert integer digit to ASCII character word
    MOV  [R3], R4            ; Store character in buffer (in reverse order!)
    IADD R3, 1               ; Advance buffer pointer
    
    IDIV R1, 10              ; Divide number by 10 for next iteration
    JMP  __ftoa_extract_loop

;; Digits were extracted backwards (e.g., 123 stored as '3','2','1'). Reverse them!
__ftoa_reverse_init:
    MOV  R4, R3
    ISUB R4, 1               ; R4 = Right pointer (last character)
    MOV  R5, R2              ; R5 = Left pointer (first character)

__ftoa_reverse_loop:
    MOV  R6, R5              ; Copy left pointer R5 to scratch R6
    IGE  R6, R4              ; Test R6 instead of R5!
    JT   R6, __ftoa_terminate

    ;; Swap characters at [R5] and [R4]
    MOV  R6, [R5]
    MOV  R7, [R4]
    MOV  [R5], R7
    MOV  [R4], R6

    IADD R5, 1               ; Move Left pointer inward
    ISUB R4, 1               ; Move Right pointer inward
    JMP  __ftoa_reverse_loop

__ftoa_terminate:
    MOV  R6, 0
    MOV  [R3], R6            ; Write null-terminator word at the end of string
    
    ;; Note: R0 still holds the raw heap base pointer from __malloc. 
    ;; __builtin_tostring will apply the 0x7FC00000 String tag to R0!
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
;; SECTION 6: ROM DATA & STRING CONSTANTS
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
