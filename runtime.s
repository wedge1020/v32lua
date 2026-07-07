; =================================================================
; VIRCON32 RUNTIME STANDARD LIBRARY FOR LUA
; =================================================================

; --- Memory Core Configuration ---
__heap_pointer:
  data 100000  

; --- String Concatenation Handler ---
__builtin_strcat:
  PUSH BP
  MOV BP, SP
  ; [BP+3] = Left String Addr, [BP+2] = Right String Addr
  
  ; Fetch tracking pointer from heap
  MOV R2, [__heap_pointer]
  PUSH R2 ; Save baseline destination pointer for return frame
  
  ; Phase 1: Copy first string
  MOV R0, [BP+3]
__strcat_copy1:
  MOV R1, [R0]
  IEQ R1, 0, R3
  JT R3, __strcat_phase2
  MOV [R2], R1
  ADD R0, 1
  ADD R2, 1
  JMP __strcat_copy1

__strcat_phase2:
  ; Phase 2: Copy second string
  MOV R0, [BP+2]
__strcat_copy2:
  MOV R1, [R0]
  IEQ R1, 0, R3
  JT R3, __strcat_finalize
  MOV [R2], R1
  ADD R0, 1
  ADD R2, 1
  JMP __strcat_copy2

__strcat_finalize:
  MOV R1, 0
  MOV [R2], R1          ; Write definitive Null-Terminator
  ADD R2, 1
  MOV [__heap_pointer], R2 ; Update heap boundary
  POP R0                ; Pull original string pointer to R0
  MOV SP, BP
  POP BP
  RET

; --- Table Index Lookup Handler ---
__builtin_table_get:
    PUSH BP
    MOV BP, SP
    MOV R2, [BP+2]      
    MOV R2, [R2]        ; Dereference Table Head Node

__table_get_loop:
    IEQ R2, 0, R3
    JT R3, __table_get_nil
    MOV R0, [R2]        ; R0 = Node->Key
    MOV R1, [BP+3]      ; R1 = Target Key String Pointer
    IEQ R0, R1, R0      
    JT R0, __table_get_hit
    MOV R2, [R2+2]      ; Move to Node->Next
    JMP __table_get_loop

__table_get_hit:
    MOV R0, [R2+1]      ; Capture Node->Value
    JMP __table_get_exit
__table_get_nil:
    MOV R0, 0           ; Return Nil
__table_get_exit:
    MOV SP, BP
    POP BP
    RET

; --- Table Mutator Assignment Handler ---
__builtin_table_set:
    PUSH BP
    MOV BP, SP
    MOV R2, [BP+2]      ; Base table anchor
    MOV R3, [R2]        ; Extract current Node address head

__table_set_loop:
    IEQ R3, 0, R1
    JT R1, __table_set_append
    MOV R0, [R3]
    MOV R1, [BP+3]
    IEQ R0, R1, R0
    JT R0, __table_set_overwrite
    MOV R3, [R3+2]      ; Navigate forward
    JMP __table_set_loop

__table_set_overwrite:
    MOV R0, [BP+4]
    MOV [R3+1], R0      ; Patch existing key memory entry
    JMP __table_set_done

__table_set_append:
    MOV R0, [__heap_pointer]
    MOV R1, [BP+3]
    MOV [R0], R1        ; Save Key
    MOV R1, [BP+4]
    MOV [R0+1], R1      ; Save Value
    MOV R1, [BP+2]      
    MOV R2, [R1]        
    MOV [R0+2], R2      ; Set new node's next field to target old head
    MOV [R1], R0        ; Reset head anchor address
    
    MOV R1, [__heap_pointer]
    ADD R1, 3
    MOV [__heap_pointer], R1 ; Update allocation boundary by 3 words

__table_set_done:
    MOV SP, BP
    POP BP
    RET
