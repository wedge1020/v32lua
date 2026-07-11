#include <stdio.h>
#include "codegen.h"

// Emits Vircon32 assembly to jump to target_label if reg is TRUTHY!
// (i.e., NOT Nil and NOT False). Uses scratch register R6.
void emit_truthy_jump(int reg, const char* target_label) {
    int check_id = get_next_label();
    char eval_right_label[128];
    snprintf(eval_right_label, sizeof(eval_right_label), "__truthy_fail_%d", check_id);

    // 1. If it IS Nil, it's not truthy -> jump to evaluate right operand
    emit_asm("MOV R6, R%d ; Copy to scratch register R6\n", reg);
    emit_asm("IEQ R6, 0xFFC00000 ; Is it Nil?\n");
    emit_asm("JT R6, %s ; If Nil, do not short-circuit\n", eval_right_label);

    // 2. If it IS False, it's not truthy -> jump to evaluate right operand
    emit_asm("MOV R6, R%d ; Copy to scratch register R6\n", reg);
    emit_asm("IEQ R6, 0xFFC00001 ; Is it False?\n");
    emit_asm("JT R6, %s ; If False, do not short-circuit\n", eval_right_label);

    // 3. If we survived both checks, the value is TRUTHY! Short-circuit!
    emit_asm("JMP %s ; Value is truthy -> short-circuit!\n", target_label);

    emit_asm("%s:\n", eval_right_label);
}
// Emits Vircon32 assembly to jump to target_label if reg holds Nil or False.
// Uses scratch register R6 to prevent destructive comparison bugs!
void emit_falsy_jump(int reg, const char* target_label) {
    // 1. Test against canonical Nil (0xFFC00000)
    emit_asm("MOV R6, R%d ; Copy condition to scratch register R6\n", reg);
    emit_asm("IEQ R6, 0xFFC00000 ; Destructive test: Is it Nil?\n");
    emit_asm("JT R6, %s ; If Nil (falsy), jump to target\n", target_label);

    // 2. Test against Boolean False (0xFFC00001)
    emit_asm("MOV R6, R%d ; Copy condition to scratch register R6\n", reg);
    emit_asm("IEQ R6, 0xFFC00001 ; Destructive test: Is it False?\n");
    emit_asm("JT R6, %s ; If False (falsy), jump to target\n", target_label);
}
