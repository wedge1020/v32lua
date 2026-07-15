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
    IEQ  R0, 0 
    JT   R0, __oom_handler 
    
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
    MOV  R2, [BP+3]          ; R2 = Key (must be preserved for fallback!) 
    MOV  R3, [BP+2]          ; R3 = Value to store 

    ;; --- FAST-PATH VALIDATION ---
    MOV  R4, R2
    AND  R4, 0x7F800000      ; Isolate exponent bits
    IEQ  R4, 0x7F800000      ; Are they all 1s? (If so, it's tagged/NaN)
    JT   R4, __table_set_fallback

    MOV  R4, R2              ; Copy float Key to R4 
    CFI  R4                  ; Vircon32 in-place conversion: R4 = (int) R4 
    MOV  R5, R4              ; Copy integer index to R5 for destructive comparison 
    ILT  R5, 1 
    JT   R5, __table_set_fallback 
    
    MOV  R5, R1 
    AND  R5, 0x003FFFFF      ; R5 = Unboxed Table Pointer 
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
__table_set_fallback:
    MOV  R5, R1 
    AND  R5, 0x003FFFFF      ; Unbox Table pointer 
    MOV  R6, [R5+3]          ; R6 = Hash Data Pointer 
    
    ;; Note: If R6 is null or full, call your __hash_grow helper here! 
    
    MOV  R7, [R6]            ; R7 = PairCount 
    MOV  R8, R6              ; Setup R8 as running memory pointer
    IADD R8, 2               ; Advance R8 to point directly at Key0 

__table_set_update_loop:
    IEQ  R7, 0               ; If we exhausted existing pairs, Key is brand new! 
    JT   R7, __table_set_append_new_pair 
    
    MOV  R9, [R8]            ; Load stored Key directly from running pointer R8
    IEQ  R9, R2              ; Does Stored Key == Search Key? 
    JT   R9, __table_set_overwrite_val ; Key already exists -> overwrite its value! 
    
    IADD R8, 2               ; Step to next key 
    ISUB R7, 1 
    JMP  __table_set_update_loop 

__table_set_overwrite_val:
    IADD R8, 1               ; Step to Value slot 
    MOV  [R8], R3            ; Overwrite existing value with new Value
    JMP  __table_set_done

__table_set_append_new_pair:
    ;; R8 currently points to the first unallocated slot at the end of the buffer 
    MOV  [R8], R2            ; Store new Key
    IADD R8, 1 
    MOV  [R8], R3            ; Store new Value
    
    ;; Increment PairCount in Hash Buffer Header (Word 0) 
    MOV  R7, [R6]
    IADD R7, 1 
    MOV  [R6], R7
    
__table_set_done:
    MOV  SP, BP
    POP  BP
    RET


;; =====================================================================================
;; SECTION 3: STRING & TERMINAL OPERATIONS
;; =====================================================================================

;; -------------------------------------------------------------------------------------
;; Built-in: Tag-Aware String Concatenation (Non-Destructive & Safe) 
;; Incoming Stack: [BP+3] = Tagged Left_Str, [BP+2] = Tagged Right_Str 
;; Returns: R0 = Tagged pointer to newly allocated string 
;; -------------------------------------------------------------------------------------
__builtin_strcat:
    PUSH BP 
    MOV  BP, SP 
    
    ;; Unbox and Calculate Length of Left String 
    MOV  R1, [BP+3]          ; R1 = Left tagged pointer 
    AND  R1, 0x003FFFFF      ; UNBOX: Isolate 22-bit raw pointer 
    MOV  R2, 0               ; R2 = Left length 
__strcat_len_left:
    MOV  R3, [R1]            ; Read character 
    IEQ  R3, 0               ; Destructive test is safe here (we don't need R3 again) 
    JT   R3, __strcat_len_right_init 
    IADD R1, 1 
    IADD R2, 1 
    JMP  __strcat_len_left 

    ;; Unbox and Calculate Length of Right String 
__strcat_len_right_init:
    MOV  R1, [BP+2]          ; R1 = Right tagged pointer 
    AND  R1, 0x003FFFFF      ; UNBOX: Isolate 22-bit raw pointer 
    MOV  R4, 0               ; R4 = Right length 
__strcat_len_right:
    MOV  R3, [R1]            ; Read character 
    IEQ  R3, 0               ; Destructive test is safe here 
    JT   R3, __strcat_alloc 
    IADD R1, 1 
    IADD R4, 1 
    JMP  __strcat_len_right 

    ;; Allocate Memory on Heap 
__strcat_alloc:
    MOV  R0, [heap_pointer]  ; R0 = New string base (raw pointer) 
    MOV  R5, R0              ; R5 = Write head 

    ;; Advance heap_pointer = old_heap + left_len + right_len + 1 
    MOV  R6, R0 
    IADD R6, R2 
    IADD R6, R4 
    IADD R6, 1 
    MOV  [heap_pointer], R6 

    ;; Copy Left String (Using R6 as a non-destructive scratch register!) 
    MOV  R1, [BP+3]          ; R1 = Reset left pointer 
    AND  R1, 0x003FFFFF      ; UNBOX for copying 
__strcat_copy_left:
    MOV  R3, [R1]            ; Read ASCII character into R3 
    MOV  R6, R3              ; Copy to scratch register R6 for testing 
    IEQ  R6, 0               ; Destructive test on R6 (R3 remains intact!) 
    JT   R6, __strcat_copy_right_init 
    MOV  [R5], R3            ; Write preserved character to heap 
    IADD R1, 1 
    IADD R5, 1 
    JMP  __strcat_copy_left 

    ;; Copy Right String (Using R6 as a non-destructive scratch register!) 
__strcat_copy_right_init:
    MOV  R1, [BP+2]          ; R1 = Reset right pointer 
    AND  R1, 0x003FFFFF      ; UNBOX for copying 
__strcat_copy_right:
    MOV  R3, [R1]            ; Read ASCII character into R3 
    MOV  R6, R3              ; Copy to scratch register R6 for testing 
    IEQ  R6, 0               ; Destructive test on R6 (R3 remains intact!) 
    JT   R6, __strcat_finish 
    MOV  [R5], R3            ; Write preserved character to heap 
    IADD R1, 1 
    IADD R5, 1 
    JMP  __strcat_copy_right 

    ;; Null-Terminate, BOX output, and Return 
__strcat_finish:
    MOV  R3, 0 
    MOV  [R5], R3            ; Null terminator 
    
    ;; Apply NaN-Box String Tag to the returned heap pointer 
    OR   R0, 0x7FC00000      ; BOX: R0 is now a valid Lua String! 
    
    MOV  SP, BP 
    POP  BP 
    RET 

;; -------------------------------------------------------------------------------------
;; Built-in: Print to Terminal 
;; Incoming Stack: [BP+2] = Tagged String Pointer 
;; -------------------------------------------------------------------------------------
;; -------------------------------------------------------------------------------------
;; Built-in: Direct Print to Screen at Coordinate (x, y)
;; Incoming Stack: [BP+4] = X Coordinate, [BP+3] = Y Coordinate, [BP+2] = Tagged String
;; -------------------------------------------------------------------------------------
;; -------------------------------------------------------------------------------------
;; Built-in: Direct Print to Screen at Coordinate (x, y) with Safety Coercion
;; Incoming Stack: [BP+4] = X Coordinate, [BP+3] = Y Coordinate, [BP+2] = Target Value
;; -------------------------------------------------------------------------------------
__builtin_print:
    PUSH BP 
    MOV  BP, SP 

    ;; 1. Initialize GPU Texture/Region state (back up existing, set to BIOS)
    IN   R5, GPU_SelectedTexture ; Save current texture
    IN   R6, GPU_SelectedRegion  ; Save current region
    OUT  GPU_SelectedTexture, -1 ; Set BIOS font texture
    
    ;; 2. Load Parameters
    MOV  R1, [BP+4]          ; R1 = X Pixel Coordinate (Integer)
    MOV  R2, [BP+3]          ; R2 = Y Pixel Coordinate (Integer)
    MOV  R3, [BP+2]          ; R3 = Target Value to Print

    ;; 3. SAFETY COERCION LAYER: Verify Tag without destroying R3
    MOV  R4, R3              ; Copy target value to scratch register R4
    AND  R4, 0xFFC00000      ; Isolate upper 10 bits (Tag)
    IEQ  R4, 0x7FC00000      ; Is it ALREADY a String? (Destructive test on R4)
    JT   R4, __print_unbox   ; If Tag == 0x7FC00000, skip coercion!

    ;; --- COERCION FALLBACK ---
    ;; Target is a Float, Boolean, Nil, Table, or Function. 
    ;; Route it through __builtin_tostring to generate a valid String on the heap!
    PUSH R3                  ; Push non-string value as argument
    CALL __builtin_tostring  ; R0 now holds a newly minted Tagged String Pointer
    ISUB SP, 1               ; Clean up argument from stack
    MOV  R3, R0              ; Replace our target register R3 with the new String pointer

__print_unbox:
    ;; 4. Unbox String and Dispatch to BIOS
    AND  R3, 0x003FFFFF      ; UNBOX: Isolate 22-bit raw heap pointer
    
    ;; __bios_print_text expects: [BP+4]=String, [BP+3]=Y, [BP+2]=X
    PUSH R3                  ; Push Unboxed Raw String Pointer
    PUSH R2                  ; Push Y Coordinate
    PUSH R1                  ; Push X Coordinate
    CALL __bios_print_text   ; Draw the string directly to the GPU screen
    ISUB SP, 3               ; Clean up arguments from stack

    ;; 5. Restore previous GPU texture and region
    OUT  GPU_SelectedTexture, R5 ; Restore previous texture
    OUT  GPU_SelectedRegion, R6  ; Restore previous region
    
    MOV  SP, BP 
    POP  BP 
    RET

;; =====================================================================================
;; SECTION 4: CORE OPERATORS & TYPE UTILITIES
;; =====================================================================================

;; -------------------------------------------------------------------------------------
;; Universal Equality (==): Returns raw integer 1 (true) or 0 (false) in R0 
;; Incoming Stack: [BP+3] = Left_Val, [BP+2] = Right_Val 
;; -------------------------------------------------------------------------------------
__builtin_eq:
    PUSH BP
    MOV  BP, SP

    MOV  R1, [BP+3]          ; R1 = Left Value
    MOV  R2, [BP+2]          ; R2 = Right Value

    ;; FAST-PATH 1: Bitwise match (Handles identical types instantly)
    MOV  R3, R1
    IEQ  R3, R2
    JT   R3, __eq_true

    ;; FAST-PATH 2: Check if BOTH are raw floats (Exponent bits != all 1s)
    MOV  R3, R1
    AND  R3, 0x7F800000
    IEQ  R3, 0x7F800000      ; Is Left tagged? (R3 = 1 if tagged, 0 if float)
    JT   R3, __eq_check_tags ; If Left is tagged, skip float check

    MOV  R4, R2
    AND  R4, 0x7F800000
    IEQ  R4, 0x7F800000      ; Is Right tagged?
    JT   R4, __eq_check_tags ; If Right is tagged, skip float check

    ;; Both are floats! Perform standard floating-point equality
    MOV  R3, R1
    FEQ  R3, R2              ; Destructive float equality
    JT   R3, __eq_true
    JMP  __eq_false

__eq_check_tags:
    ;; 1. Re-isolate tags into scratch registers R3 and R4
    MOV  R3, R1
    AND  R3, 0xFFC00000      ; Isolate Left Tag in R3
    MOV  R4, R2
    AND  R4, 0xFFC00000      ; Isolate Right Tag in R4

    ;; 2. Do the tags match? If not, different types cannot be equal!
    IEQ  R3, R4
    JF   R3, __eq_false      ; If tags differ -> return false!

    ;; 3. FAST-PATH 3: Are they Strings?
    ;; Re-isolate Left tag into R3 since the previous IEQ destroyed it
    MOV  R3, R1
    AND  R3, 0xFFC00000
    IEQ  R3, 0x7FC00000      ; Is it the String Tag?
    JF   R3, __eq_false      ; If not strings (e.g., distinct tables), return false!

    ;; FALLBACK: Deep String Comparison (strcmp)
    AND  R1, 0x003FFFFF      ; Unbox Left string pointer -> R1
    AND  R2, 0x003FFFFF      ; Unbox Right string pointer -> R2

__eq_strcmp_loop:
    MOV  R3, [R1]            ; Load character word from Left string -> R3 
    MOV  R4, [R2]            ; Load character word from Right string -> R4 

    ;; Check if characters are different 
    MOV  R5, R3 
    IEQ  R5, R4              ; Does Left char == Right char? 
    JF   R5, __eq_false      ; If characters differ, strings are not equal! 

    ;; We know characters match. Did we reach the null terminator (0)? 
    IEQ  R3, 0               ; Is Left char == 0? 
    JT   R3, __eq_true       ; If we hit null terminator while identical -> strings match! 

    ;; Advance pointers to next character word in memory 
    IADD R1, 1 
    IADD R2, 1 
    JMP  __eq_strcmp_loop 

__eq_true:
    MOV  R0, 1               ; Return raw integer 1 (True) 
    JMP  __eq_done 

__eq_false:
    MOV  R0, 0               ; Return raw integer 0 (False) 

__eq_done:
    MOV  SP, BP 
    POP  BP 
    RET 

;; -------------------------------------------------------------------------------------
;; Length Operator Dispatch (#): Returns length as an IEEE 754 Float in R0 
;; Incoming Stack: [BP+2] = Target Value 
;; -------------------------------------------------------------------------------------
__builtin_len:
    PUSH BP
    MOV  BP, SP
    
    MOV  R1, [BP+2]          ; R1 = Target Value
    
    ;; 1. Extract Tag into R2 
    MOV  R2, R1 
    AND  R2, 0xFFC00000 
    
    ;; 2. Check if String (Tag == 0x7FC00000) 
    MOV  R3, R2 
    IEQ  R3, 0x7FC00000 
    JT   R3, __len_string 
    
    ;; 3. Check if Table (Tag == 0x7F800000) 
    MOV  R3, R2 
    IEQ  R3, 0x7F800000 
    JT   R3, __len_table 
    
    ;; 4. Fallback: Invalid type for length operator -> Runtime Error! 
    MOV  SP, BP
    POP  BP
    JMP  __error_attempt_to_get_length 
    
__error_attempt_to_get_length:
    ;; Fatal Runtime Error: Attempted to get length of an unsupported type
    HLT                      ; Halt CPU to preserve register state for debugging
    JMP __error_attempt_to_get_length

__len_string:
    AND  R1, 0x003FFFFF      ; Unbox string pointer to read header 
    MOV  R0, [R1]            ; String struct stores length in word 0 (Stripped +0 offset)
    CIF  R0                  ; Vircon32 in-place conversion: R0 = (float) R0 
    JMP  __len_done

__len_table:
    AND  R1, 0x003FFFFF      ; Unbox table pointer to read header 
    MOV  R0, [R1+1]          ; Table struct stores array boundary length in word 1 
    CIF  R0                  ; Vircon32 in-place conversion: R0 = (float) R0 
    
__len_done:
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
    
    ;; 1. Check Exact Primitives (Nil and Booleans) 
    MOV  R2, R1 
    IEQ  R2, 0xFFC00000      ; Is Nil? 
    JT   R2, __tostring_nil 
    
    MOV  R2, R1 
    IEQ  R2, 0xFFC00001      ; Is False? 
    JT   R2, __tostring_false 
    
    MOV  R2, R1 
    IEQ  R2, 0xFFC00002      ; Is True? 
    JT   R2, __tostring_true 
    
    ;; 2. Check Pointer Tags 
    MOV  R2, R1 
    AND  R2, 0xFFC00000      ; Isolate upper 10 bits 
    
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
    PUSH R1 
    CALL __builtin_ftoa 
    ISUB SP, 1 
    OR   R0, 0x7FC00000      ; Box raw pointer as String 
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
    MOV  R0, R1              ; Already a string! Return as-is. 
    JMP  __tostring_done

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
    
    MOV  R1, [BP+2]          ; R1 = Float value
    CFI  R1                  ; Convert Float to Integer (in-place)
    
    ;; Allocate a 16-word character buffer on the heap for the string
    MOV  R0, 16
    PUSH R0
    CALL __malloc            ; R0 = Base address of new string buffer
    ISUB SP, 1
    
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
    IEQ  R1, 0               ; If quotient is 0, we are done extracting digits
    JT   R1, __ftoa_reverse_init
    
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
    IGE  R5, R4              ; If Left >= Right, string is reversed
    JT   R5, __ftoa_terminate
    
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

;; =====================================================================================
;; SECTION 5: BIOS & HARDWARE SUPPORT ROUTINES
;; =====================================================================================

;; -------------------------------------------------------------------------------------
;; __bios_print_text: Displays ASCII string content to the GPU screen 
;; Incoming Stack: [BP+2]=X, [BP+3]=Y, [BP+4]=Unboxed Heap String Pointer 
;; -------------------------------------------------------------------------------------
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

;; =====================================================================================
;; SECTION 6: STATIC DATA & STRING CONSTANTS
;; =====================================================================================

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
