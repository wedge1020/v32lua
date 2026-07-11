;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Vircon32 NaN-Boxed Routines for Lua Runtime Environment (runtime.s)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Table Read Indexer: t[k] -> Returns Value in R0 (or Nil if not found)
;;
__builtin_table_get:

    MOV R1, [BP+1]              ; R1 = Tagged Table Pointer (0x7F80....)
    MOV R2, [BP+2]              ; R2 = Key (must be preserved for fallback!)

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;
    ;; FAST-PATH CHECK 1: Is Key an unboxed IEEE Float?
	;;
    MOV R3, R2
    AND R3, 0xFFC00000          ; Isolate top 10 bits of Key
    INE R3, 0                   ; Destructive test: If top bits != 0, it's tagged
    JT  R3, __table_get_fallback; Route tagged keys (String/Bool/Nil) to hash fallback!

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;
    ;; FAST-PATH CHECK 2: Is Key an integer >= 1?
	;;
    MOV R3, R2                  ; Copy float Key to R3 (preserves original in R2)
    CFI R3                      ; Vircon32 in-place conversion: R3 = (int) R3
    MOV R4, R3                  ; Copy integer index to R4 for destructive comparison
    ILT R4, 1                   ; Destructive test: Is integer key < 1?
    JT  R4, __table_get_fallback; Zero or negative keys go to fallback!

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;
    ;; FAST-PATH CHECK 3: Is Key within Array Capacity?
	;;
    MOV R4, R1
    AND R4, 0x003FFFFF          ; Unbox Table pointer into R4
    MOV R5, [R4+1]              ; R5 = Array Capacity (from Header Word 1)
    MOV R6, R3                  ; Copy integer index R3 to R6
    IGT R6, R5                  ; Destructive test: Is Key > Capacity?
    JT  R6, __table_get_fallback; Out-of-bounds integers go to fallback!

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;
    ;; FAST-PATH EXECUTION: O(1) Contiguous Array Read
	;;
    MOV R5, [R4+2]              ; R5 = Array Data Pointer (from Header Word 2)
    ISUB R3, 1                  ; Convert 1-based Lua index to 0-based memory offset
    IADD R5, R3                 ; Memory Address = ArrayPtr + (Key - 1)
    MOV R0, [R5]                ; Read value directly from heap buffer!
    RET

;; --- FALLBACK EXECUTION: Association List Scan ---
__table_get_fallback:
    MOV R4, R1
    AND R4, 0x003FFFFF          ; Unbox Table pointer
    MOV R5, [R4+3]              ; R5 = Hash Data Pointer (from Header Word 3)
    IEQ R5, 0                   ; Is Hash Buffer null (no sparse keys stored)?
    JT  R5, __table_get_not_found

    MOV R6, [R5+0]              ; R6 = PairCount (how many pairs are stored)
    MOV R7, 2                   ; R7 = Word index counter (starts at offset 2 for Key0)

__table_get_scan_loop:
    IEQ R6, 0                   ; Have we checked all stored pairs?
    JT  R6, __table_get_not_found
    
    MOV R8, [R5+R7]             ; R8 = Stored Key at [HashPtr + R7]
    IEQ R8, R2                  ; ZERO-COST COMPARISON: Does Stored Key == Search Key?
    JT  R8, __table_get_found   ; Match found!
    
    IADD R7, 2                  ; Advance index by 2 words (skip Value slot to next Key)
    ISUB R6, 1                  ; Decrement remaining PairCount
    JMP __table_get_scan_loop

__table_get_found:
    IADD R7, 1                  ; Value is stored 1 word after the matching Key
    MOV R0, [R5+R7]             ; Read Value into return register R0
    RET

__table_get_not_found:
    MOV R0, 0xFFC00000          ; Key does not exist -> Return canonical Lua Nil!
    RET


;; ============================================================================
;; Table Write Indexer: t[k] = v -> Writes Value into Table Storage
;; ============================================================================
__builtin_table_set:
    MOV R1, [BP+1]              ; R1 = Table Pointer
    MOV R2, [BP+2]              ; R2 = Key (must be preserved for fallback!)
    MOV R3, [BP+3]              ; R3 = Value to store

    ;; --- FAST-PATH VALIDATION ---
    MOV R4, R2
    AND R4, 0xFFC00000
    INE R4, 0
    JT  R4, __table_set_fallback
    
    MOV R4, R2                  ; Copy float Key to R4
    CFI R4                      ; Vircon32 in-place conversion: R4 = (int) R4
    MOV R5, R4                  ; Copy integer index to R5 for destructive comparison
    ILT R5, 1
    JT  R5, __table_set_fallback
    
    MOV R5, R1
    AND R5, 0x003FFFFF          ; R5 = Unboxed Table Pointer
    MOV R6, [R5+1]              ; R6 = Array Capacity
    MOV R7, R4                  ; Copy integer index R4 to R7
    IGT R7, R6
    JT  R7, __table_set_fallback

    ;; --- FAST-PATH EXECUTION: O(1) Contiguous Array Write ---
    MOV R6, [R5+2]              ; R6 = Array Data Pointer
    ISUB R4, 1                  ; Convert 1-based Lua index to 0-based memory offset
    IADD R6, R4                 ; Memory Address = ArrayPtr + (Key - 1)
    MOV [R6], R3                ; Write Value directly into contiguous array slot!
    RET

;; --- FALLBACK EXECUTION: Update Existing or Append New ---
__table_set_fallback:
    MOV R5, R1
    AND R5, 0x003FFFFF          ; Unbox Table pointer
    MOV R6, [R5+3]              ; R6 = Hash Data Pointer
    
    ;; Note: If R6 is null or full, call your __hash_grow helper here!
    
    MOV R7, [R6+0]              ; R7 = PairCount
    MOV R8, 2                   ; R8 = Word index counter

__table_set_update_loop:
    IEQ R7, 0                   ; If we exhausted existing pairs, Key is brand new!
    JT  R7, __table_set_append_new_pair
    
    MOV R9, [R6+R8]             ; Load stored Key
    IEQ R9, R2                  ; Does Stored Key == Search Key?
    JT  R9, __table_set_overwrite_val ; Key already exists -> overwrite its value!
    
    IADD R8, 2                  ; Step to next key
    ISUB R7, 1
    JMP __table_set_update_loop

__table_set_overwrite_val:
    IADD R8, 1                  ; Step to Value slot
    MOV [R6+R8], R3             ; Overwrite existing value with new Value
    RET

__table_set_append_new_pair:
    ;; R8 currently points to the first unallocated slot at the end of the buffer
    MOV [R6+R8], R2             ; Store new Key
    IADD R8, 1
    MOV [R6+R8], R3             ; Store new Value
    
    ;; Increment PairCount in Hash Buffer Header (Word 0)
    MOV R7, [R6+0]
    IADD R7, 1
    MOV [R6+0], R7
    RET


;; ============================================================================
;; Core Memory Allocator: Creates a new Table struct on the heap
;; ============================================================================
__builtin_table_new:
    ;; 1. Allocate space for the Table struct (4 words: flags, array_len, array_ptr, hash_ptr)
    MOV R0, 4
    PUSH R0
    CALL __malloc
    ISUB SP, 1
    
    ;; Check for out-of-memory (if R0 == 0, handle OOM error)
    IEQ R0, 0
    JT R0, __oom_handler
    
    ;; 2. Initialize the table header in data memory
    MOV [R0+0], 0               ; flags / metatable pointer = nil
    MOV [R0+1], 0               ; array part length = 0
    MOV [R0+2], 0               ; array part pointer = null
    MOV [R0+3], 0               ; hash part pointer = null
    
    ;; 3. AUDITED: Box the raw data heap address as a Lua Table!
    OR R0, 0x7F800000
    RET


;; ============================================================================
;; Length Operator Dispatch (#): Returns length as an IEEE 754 Float in R0
;; ============================================================================
__builtin_len:
    ;; Argument is passed in [BP+1]
    MOV R1, [BP+1]
    
    ;; 1. Extract Tag into R2
    MOV R2, R1
    AND R2, 0xFFC00000
    
    ;; 2. Check if String (Tag == 0x7FC00000)
    MOV R3, R2
    IEQ R3, 0x7FC00000
    JT R3, __len_string
    
    ;; 3. Check if Table (Tag == 0x7F800000)
    MOV R3, R2
    IEQ R3, 0x7F800000
    JT R3, __len_table
    
    ;; 4. Fallback: Invalid type for length operator -> Runtime Error!
    JMP __error_attempt_to_get_length
    
__len_string:
    ;; Unbox string pointer to read header
    AND R1, 0x003FFFFF
    ;; Assume string struct stores length in word 0: [len, char0, char1, ...]
    MOV R0, [R1+0]
    ;; AUDITED: Vircon32 in-place conversion: R0 = (float) R0
    CIF R0                      
    RET

__len_table:
    ;; Unbox table pointer to read header
    AND R1, 0x003FFFFF
    ;; Assume table struct stores array boundary length in word 1
    MOV R0, [R1+1]
    ;; AUDITED: Vircon32 in-place conversion: R0 = (float) R0
    CIF R0                      
    RET


;; ============================================================================
;; Universal Type Serializer: Converts any tagged value to a String pointer
;; ============================================================================
__builtin_tostring:
    MOV R1, [BP+1]              ; Load argument from Base Pointer
    
    ;; 1. Check Exact Primitives (Nil and Booleans)
    MOV R2, R1
    IEQ R2, 0xFFC00000          ; Is Nil?
    JT R2, __tostring_nil
    
    MOV R2, R1
    IEQ R2, 0xFFC00001          ; Is False?
    JT R2, __tostring_false
    
    MOV R2, R1
    IEQ R2, 0xFFC00002          ; Is True?
    JT R2, __tostring_true
    
    ;; 2. Check Pointer Tags
    MOV R2, R1
    AND R2, 0xFFC00000          ; Isolate upper 10 bits
    
    MOV R3, R2
    IEQ R3, 0x7FC00000          ; Is it already a String?
    JT R3, __tostring_passthrough
    
    MOV R3, R2
    IEQ R3, 0x7F800000          ; Is it a Table?
    JT R3, __tostring_table
    
    MOV R3, R2
    IEQ R3, 0xFF800000          ; Is it a Function?
    JT R3, __tostring_function
    
    ;; 3. Fallback: It must be a standard IEEE 754 Float!
    ;; Call float-to-string formatter (ftoa)
    PUSH R1
    CALL __builtin_ftoa
    ISUB SP, 1
    ;; R0 now holds raw pointer to new string; box it before returning!
    OR R0, 0x7FC00000
    RET

__tostring_nil:
    MOV R0, __const_str_nil     ; Load address of static "nil" string
    OR R0, 0x7FC00000           ; Box as String
    RET
__tostring_false:
    MOV R0, __const_str_false   ; Load address of static "false" string
    OR R0, 0x7FC00000           ; Box as String
    RET
__tostring_true:
    MOV R0, __const_str_true    ; Load address of static "true" string
    OR R0, 0x7FC00000           ; Box as String
    RET
__tostring_passthrough:
    MOV R0, R1                  ; Already a string! Return as-is.
    RET
__tostring_table:
    ;; Unbox pointer (AND 0x003FFFFF), format as "table: 0x...", box result, return
    JMP __format_table_address
__tostring_function:
    ;; Unbox pointer (AND 0x003FFFFF), format as "function: 0x...", box result, return
    JMP __format_function_address

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Vircon32 BIOS support routines for Lua Runtime Environment
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __bios_print_text: assembly routine for use with in-built print() to display
;;                    content to the screen
;;
__bios_print_text:

    PUSH  BP
    MOV   BP, SP

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;
    ;; Initialize function
	;;
	IN    R5, GPU_SelectedTexture ; save current texture
	IN    R6, GPU_SelectedRegion  ; save current region
	OUT   GPU_SelectedTexture, -1 ; set BIOS texture

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;
    ;; Load Parameters from Stack
	;;
    MOV   R1, [BP + 2]   ; R1 = X Pixel Coordinate (Integer)
    MOV   R2, [BP + 3]   ; R2 = Y Pixel Coordinate (Integer)
    MOV   R3, [BP + 4]   ; R3 = Raw Heap Offset to ASCII String (Unboxed)

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;
    ;; GPU Rendering Loop
	;;
__bios_print_loop:

    MOV   R4, [R3]       ; Read character from string memory
    IEQ   R4, 0          ; Check for null terminator
    JT    R4, __bios_print_done

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;
    ;; Set coordinates and display the current character to the screen
	;;
	OUT   GPU_SelectedRegion, R3  ; set character to display
	OUT   GPU_DrawingPointX, R1   ; display at X
	OUT   GPU_DrawingPointY, R2   ; display at Y
	OUT   GPU_Command, GPUCommand_DrawRegion ; display to screen
    
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;
    ;; Advance to next character and increment X coordinate
	;;
    IADD  R3, 1          ; Next char word in memory
    IADD  R1, 10         ; Advance X by font width (e.g., 10 pixels)
    JMP   __bios_print_loop

__bios_print_done:

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;
    ;; Restore previous texture and region
	;;
	OUT   GPU_SelectedTexture, R5 ; restore previous texture
	OUT   GPU_SelectedRegion, R6  ; restore previous region

    MOV   SP, BP
    POP   BP
    RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __bios_clear_screen: assembly routine for use with in-built print() to clear
;;                      the screen
;;
__bios_clear_screen:

    PUSH  BP
    MOV   BP, SP

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;
    ;; Use the color currently set in GPU_ClearColor and clear the screen
	;;
    OUT   GPU_Command, GPUCommand_ClearScreen
    
    MOV   SP, BP
    POP   BP
    RET
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Built-in: Tag-Aware String Concatenation (Non-Destructive & Safe)
;; Stack incoming: [BP+3]=Tagged Left_Str, [BP+2]=Tagged Right_Str
;; Returns: R0 = Tagged pointer to newly allocated string
;;
__builtin_strcat:
    PUSH  BP
    MOV   BP, SP
    
;; Unbox and Calculate Length of Left String
    MOV   R1, [BP + 3] ; R1 = Left tagged pointer
    AND   R1, 0x003FFFFF ; UNBOX: Isolate 22-bit raw pointer
    MOV   R2, 0        ; R2 = Left length
__strcat_len_left:
    MOV   R3, [R1]     ; Read character
    IEQ   R3, 0        ; Destructive test is safe here (we don't need R3 again)

    JT    R3, __strcat_len_right_init
    IADD  R1, 1
    IADD  R2, 1
    JMP   __strcat_len_left

;; Unbox and Calculate Length of Right String
__strcat_len_right_init:
    MOV   R1, [BP + 2] ; R1 = Right tagged pointer
    AND   R1, 0x003FFFFF ; UNBOX: Isolate 22-bit raw pointer
    MOV   R4, 0        ; R4 = Right length
__strcat_len_right:
    MOV   R3, [R1]     ; Read character
    IEQ   R3, 0        ; Destructive test is safe here
    JT    R3, __strcat_alloc
    IADD  R1, 1
    IADD  R4, 1
    JMP   __strcat_len_right

;; Allocate Memory on Heap
__strcat_alloc:
    MOV   R0, [heap_pointer] ; R0 = New string base (raw pointer)
    MOV   R5, R0             ; R5 = Write head

    ;; Advance heap_pointer = old_heap + left_len + right_len + 1
    MOV   R6, R0
    IADD  R6, R2
    IADD  R6, R4
    IADD  R6, 1
    MOV   [heap_pointer], R6

;; Copy Left String (Using R6 as a non-destructive scratch register!)
    MOV   R1, [BP + 3] ; R1 = Reset left pointer
    AND   R1, 0x003FFFFF ; UNBOX for copying
__strcat_copy_left:
    MOV   R3, [R1]     ; Read ASCII character into R3
    MOV   R6, R3       ; Copy to scratch register R6 for testing
    IEQ   R6, 0        ; Destructive test on R6 (R3 remains intact!)
    JT    R6, __strcat_copy_right_init
    MOV   [R5], R3     ; Write preserved character to heap
    IADD  R1, 1
    IADD  R5, 1
    JMP   __strcat_copy_left

;; Copy Right String (Using R6 as a non-destructive scratch register!)
__strcat_copy_right_init:
    MOV   R1, [BP + 2] ; R1 = Reset right pointer
    AND   R1, 0x003FFFFF ; UNBOX for copying

__strcat_copy_right:
    MOV   R3, [R1]     ; Read ASCII character into R3
    MOV   R6, R3       ; Copy to scratch register R6 for testing
    IEQ   R6, 0        ; Destructive test on R6 (R3 remains intact!)
    JT    R6, __strcat_finish
    MOV   [R5], R3     ; Write preserved character to heap
    IADD  R1, 1
    IADD  R5, 1
    JMP   __strcat_copy_right

;; Null-Terminate, BOX output, and Return
__strcat_finish:
    MOV   R3, 0
    MOV   [R5], R3       ; Null terminator
    
    ; Apply NaN-Box String Tag to the returned heap pointer
    OR    R0, 0x7FC00000 ; BOX: R0 is now a valid Lua String!
    
    MOV   SP, BP
    POP   BP
    RET

;; --- Built-in: Print to Terminal ---
;; Stack incoming: [BP+2]=Tagged String Pointer
__builtin_print:
    PUSH  BP
    MOV   BP, SP
    
    ;; 1. Get String and Unbox
    MOV   R1, [BP + 2]   ; R1 = Tagged String
    AND   R1, 0x003FFFFF ; UNBOX: Get raw pointer
    
    ;; 2. Check Cursor Y
    MOV   R2, [term_ypos]
    ILT   R2, 16
    JT    R2, __print_append ; If < 16, just append

    ;; 3. Scroll History (Shift Array Up)
    ;; We are at line 16, so we drop index 0 and move 1-15 up.
__print_scroll:
    MOV   R3, term_history
    MOV   R4, term_history
    IADD  R4, 1          ; R4 points to index 1
    MOV   R5, 15         ; Loop 15 times
    
__print_scroll_loop:
    MOV   R6, [R4]       ; Read from N+1
    MOV   [R3], R6       ; Write to N
    IADD  R3, 1
    IADD  R4, 1
    ISUB  R5, 1
    IGT   R5, 0
    JT    R5, __print_scroll_loop
    
;; Set Y index to 15 to overwrite the bottom line
    MOV   R2, 15
    JMP   __print_insert

;; 4. Append to History
__print_append:
    MOV   R3, R2         ; Store old Y to R3
    IADD  R2, 1
    MOV   [term_ypos], R2 ; Increment Y pos
    MOV   R2, R3         ; Restore index for insertion

;; 5. Insert New String Pointer
__print_insert:
    MOV   R3, term_history
    IADD  R3, R2         ; term_history + current_y
    MOV   [R3], R1       ; Save raw string pointer to history

;; 6. Trigger Screen Redraw
    CALL  __term_redraw
    
    MOV   SP, BP
    POP   BP
    RET

;; --- Built-in: Redraw Terminal ---
;; Clears the screen and redraws all strings in term_history
__term_redraw:
    PUSH  BP
    MOV   BP, SP

;; 1. Clear the screen 
;; Usually achieved via a BIOS call or a GPU clear command.
    CALL  __bios_clear_screen ; Replace with your specific clear call

;; 2. Initialize Loop Variables
    MOV   R1, 0          ; R1 = Current Y Index (0 to 15)
    MOV   R2, term_history ; R2 = Pointer to history array

;; 3. The Rendering Loop Boundary Check
__term_redraw_loop:
    MOV   R3, [term_ypos]
    IGE   R1, R3
    JT    R1, __term_redraw_done ; If Index >= term_ypos, we are done

;; 4. Calculate Y Pixel Position (Index * 20 pixels per line)
    MOV   R4, R1
    IMUL  R4, 20         ; R4 = Y Pixel Coordinate

;; 5. Get the String Pointer for this Line
    MOV   R5, [R2]       ; R5 = Raw String Pointer

;; 6. Draw the String via BIOS
;; Assuming a standard BIOS print function that takes (X, Y, StringPtr)
    PUSH  R5             ; Push String Pointer
    PUSH  R4             ; Push Y Position
    PUSH  0              ; Push X Position (0 margin)
    CALL  __bios_print_text ; Draw the string to the GPU
    ISUB  SP, 3          ; Clean up arguments

;; 7. Advance to Next Line
    IADD  R1, 1          ; Increment Y Index
    IADD  R2, 1          ; Advance history pointer
    JMP   __term_redraw_loop

;; 8. Return
__term_redraw_done:
    MOV   SP, BP
    POP   BP
    RET

;; --- Built-in: Unary Minus (-x) ---
;; Stack incoming: [BP+2] = Tagged Value (Expected Float)
;; Returns: R0 = Negated Float
__builtin_unm:
    PUSH  BP
    MOV   BP, SP

    ;; 1. Load the incoming value
    MOV   R1, [BP + 2]   ; R1 = Value to negate

    ;; 2. Flip the IEEE-754 sign bit (Bit 31)
    XOR   R1, 0x80000000 ; Instantly changes positive <-> negative

    ;; 3. Move to return register and exit
    MOV   R0, R1
    MOV   SP, BP
    POP   BP
    RET
