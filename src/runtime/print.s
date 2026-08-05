;; ===========================================================================
;; SECTION: PRINT OPERATIONS
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; Built-in: Print to Screen at Position (x, y) with Split-Tag Coercion
;; Incoming Stack: [BP+4] = X Coordinate (integer)
;;                 [BP+3] = Y Coordinate (integer)
;;                 [BP+2] = Target Value (tagged)
;; ---------------------------------------------------------------------------
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
    IEQ  R4, BOXED_RAMSTRING ; Does it have the RAM String / Primitive tag?
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; __bios_print_text: Displays ASCII string content to the GPU screen 
;;
;;     Incoming Stack: [BP+2] = X
;;                     [BP+3] = Y
;;                     [BP+4] = Unboxed Heap String Pointer 
;;
__bios_print_text:
    PUSH BP 
    MOV  BP, SP 

    ;; Load Parameters from Stack 
    MOV  R1, [BP+2]              ; R1 = X Pixel Coordinate (Integer) 
    MOV  R2, [BP+3]              ; R2 = Y Pixel Coordinate (Integer) 
    MOV  R3, [BP+4]              ; R3 = Heap Offset to unboxed ASCII String

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
