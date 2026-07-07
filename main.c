#include "codegen.h"
#include <stdio.h>
#include <stdlib.h>

// External endpoints provided by Flex/Bison
extern int yyparse(void);
extern FILE* yyin;

// Concrete implementation of the runtime library injector
void emit_runtime_library(void) {
    printf("\n; =================================================================\n");
    printf("; VIRCON32 RUNTIME STANDARD LIBRARY FOR LUA\n");
    printf("; =================================================================\n\n");
    
    printf("__heap_pointer:\n  data 100000\n\n");

    printf("__builtin_strcat:\n");
    printf("  PUSH BP\n  MOV BP, SP\n");
    printf("  MOV R2, [__heap_pointer]\n  PUSH R2\n");
    printf("  MOV R0, [BP+3]\n");
    printf("__strcat_copy1:\n");
    printf("  MOV R1, [R0]\n  IEQ R1, 0, R3\n  JT R3, __strcat_phase2\n");
    printf("  MOV [R2], R1\n  ADD R0, 1\n  ADD R2, 1\n  JMP __strcat_copy1\n");
    printf("__strcat_phase2:\n");
    printf("  MOV R0, [BP+2]\n");
    printf("__strcat_copy2:\n");
    printf("  MOV R1, [R0]\n  IEQ R1, 0, R3\n  JT R3, __strcat_finalize\n");
    printf("  MOV [R2], R1\n  ADD R0, 1\n  ADD R2, 1\n  JMP __strcat_copy2\n");
    printf("__strcat_finalize:\n");
    printf("  MOV R1, 0\n  MOV [R2], R1\n  ADD R2, 1\n");
    printf("  MOV [__heap_pointer], R2\n  POP R0\n");
    printf("  MOV SP, BP\n  POP BP\n  RET\n\n");

    printf("__builtin_table_get:\n");
    printf("  PUSH BP\n  MOV BP, SP\n  MOV R2, [BP+2]\n  MOV R2, [R2]\n");
    printf("__table_get_loop:\n");
    printf("  IEQ R2, 0, R3\n  JT R3, __table_get_nil\n");
    printf("  MOV R0, [R2]\n  MOV R1, [BP+3]\n  IEQ R0, R1, R0\n  JT R0, __table_get_hit\n");
    printf("  MOV R2, [R2+2]\n  JMP __table_get_loop\n");
    printf("__table_get_hit:\n");
    printf("  MOV R0, [R2+1]\n  JMP __table_get_exit\n");
    printf("__table_get_nil:\n");
    printf("  MOV R0, 0\n");
    printf("__table_get_exit:\n");
    printf("  MOV SP, BP\n  POP BP\n  RET\n\n");

    printf("__builtin_table_set:\n");
    printf("  PUSH BP\n  MOV BP, SP\n  MOV R2, [BP+2]\n  MOV R3, [R2]\n");
    printf("__table_set_loop:\n");
    printf("  IEQ R3, 0, R1\n  JT R1, __table_set_append\n");
    printf("  MOV R0, [R3]\n  MOV R1, [BP+3]\n  IEQ R0, R1, R0\n  JT R0, __table_set_overwrite\n");
    printf("  MOV R3, [R3+2]\n  JMP __table_set_loop\n");
    printf("__table_set_overwrite:\n");
    printf("  MOV R0, [BP+4]\n  MOV [R3+1], R0\n  JMP __table_set_done\n");
    printf("__table_set_append:\n");
    printf("  MOV R0, [__heap_pointer]\n  MOV R1, [BP+3]\n  MOV [R0], R1\n");
    printf("  MOV R1, [BP+4]\n  MOV [R0+1], R1\n  MOV R1, [BP+2]\n  MOV R2, [R1]\n");
    printf("  MOV [R0+2], R2\n  MOV [R1], R0\n  MOV R1, [__heap_pointer]\n");
    printf("  ADD R1, 3\n  MOV [__heap_pointer], R1\n");
    printf("__table_set_done:\n");
    printf("  MOV SP, BP\n  POP BP\n  RET\n");
}

int main(int argc, char** argv) {
    if (argc > 1) {
        // Read from a source file if provided
        FILE* file = fopen(argv[1], "r");
        if (!file) {
            fprintf(stderr, "Error: Execution halted. Could not open target file '%s'\n", argv[1]);
            return 1;
        }
        yyin = file;
    } else {
        fprintf(stderr, "; Compiler reading from standard input. Type Lua code then press Ctrl+D:\n");
    }

    // Launch the parsing cycle. Bison will trigger generate_asm() automatically
    // once the grammar matches the target sequence successfully.
    int parse_status = yyparse();

    if (parse_status == 0) {
        fprintf(stderr, "; --- Status: Compilation completed cleanly ---\n");
    } else {
        fprintf(stderr, "; --- Status: Compilation halted due to structural syntax errors ---\n");
    }

    if (argc > 1 && yyin) {
        fclose(yyin);
    }

    return parse_status;
}
