#include "v32lua.h"

// ============================================================================
// system.date() - Returns FOUR values: formatted string, year, month, day.
//
// Adds the "YYYY-MM-DD" string as return value 1 (built by
// __builtin_format_date_string, itself built on the reusable
// __builtin_write_padded_int zero-pad helper). year/month/day are
// unchanged in VALUE from the already-verified numeric unpack -- they
// just shift from return positions 1-3 into positions 2-4.
// ============================================================================
int emit_system_date_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL) {
        int reg = allocate_register();
        generate_asm(curr, reg);
        unlock_register(reg);
        curr = curr->next;
    }

    emit_asm("    ;; --- Intrinsic: system.date() ---\n");

    // --- Step 1: read the hardware register and unpack it ---
    int raw_reg = allocate_register();
    force_spill_register(raw_reg);
    emit_asm("    IN R%d, TIM_CurrentDate\n", raw_reg);
    emit_asm("    PUSH R%d\n", raw_reg);
    emit_asm("    CALL __builtin_unpack_date\n");
    emit_asm("    IADD SP, 1\n");
    unlock_register(raw_reg);
    // R0 = year (float), R2 = month (float), R3 = day (float)

    // --- Step 2: spill all 3 floats -- another CALL is coming, and ---
    // --- every register is caller-saved.                           ---
    emit_asm("    PUSH R0 ; spill year (float)\n");
    emit_asm("    PUSH R2 ; spill month (float)\n");
    emit_asm("    PUSH R3 ; spill day (float)\n");

    // --- Step 3: reload, convert each to a raw int for digit extraction ---
    emit_asm("    POP R3 ; day (float)\n");
    emit_asm("    POP R2 ; month (float)\n");
    emit_asm("    POP R1 ; year (float)\n");
    emit_asm("    MOV R4, R1\n");
    emit_asm("    CFI R4 ; year as raw int\n");
    emit_asm("    MOV R5, R2\n");
    emit_asm("    CFI R5 ; month as raw int\n");
    emit_asm("    MOV R6, R3\n");
    emit_asm("    CFI R6 ; day as raw int\n");

    // --- Step 4: re-spill the FLOATS across the upcoming CALL ---
    emit_asm("    PUSH R1 ; year (float)\n");
    emit_asm("    PUSH R2 ; month (float)\n");
    emit_asm("    PUSH R3 ; day (float)\n");

    // --- Step 5: build the formatted string ---
    emit_asm("    PUSH R4 ; year (int)\n");
    emit_asm("    PUSH R5 ; month (int)\n");
    emit_asm("    PUSH R6 ; day (int)\n");
    emit_asm("    CALL __builtin_format_date_string\n");
    emit_asm("    IADD SP, 3\n");
    // R0 = boxed date string

    // --- Step 6: reload the floats, place into final return slots ---
    emit_asm("    POP R3 ; day (float)\n");
    emit_asm("    POP R2 ; month (float)\n");
    emit_asm("    POP R1 ; year (float)\n");

    char extra_ret_access[128];
    get_extra_return_slot_access(0, extra_ret_access);
    emit_asm("    MOV %s, R3 ; return value 4: day\n", extra_ret_access);
    emit_asm("    MOV R3, R2 ; return value 3: month\n");
    emit_asm("    MOV R2, R1 ; return value 2: year\n");
    // R0 already holds the formatted string: return value 1

    return 4;
}

// ============================================================================
// system.time() - Returns FOUR values: formatted string, hour, minute, second.
// Mirrors system.date() exactly; the only difference is the source port
// (TIM_CurrentTime) and the unpack/format routines it calls into.
// ============================================================================
int emit_system_time_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL) {
        int reg = allocate_register();
        generate_asm(curr, reg);
        unlock_register(reg);
        curr = curr->next;
    }

    emit_asm("    ;; --- Intrinsic: system.time() ---\n");

    int raw_reg = allocate_register();
    force_spill_register(raw_reg);
    emit_asm("    IN R%d, TIM_CurrentTime\n", raw_reg);
    emit_asm("    PUSH R%d\n", raw_reg);
    emit_asm("    CALL __builtin_unpack_time\n");
    emit_asm("    IADD SP, 1\n");
    unlock_register(raw_reg);
    // R0 = hour (float), R2 = minute (float), R3 = second (float)

    emit_asm("    PUSH R0 ; spill hour (float)\n");
    emit_asm("    PUSH R2 ; spill minute (float)\n");
    emit_asm("    PUSH R3 ; spill second (float)\n");

    emit_asm("    POP R3 ; second (float)\n");
    emit_asm("    POP R2 ; minute (float)\n");
    emit_asm("    POP R1 ; hour (float)\n");
    emit_asm("    MOV R4, R1\n");
    emit_asm("    CFI R4 ; hour as raw int\n");
    emit_asm("    MOV R5, R2\n");
    emit_asm("    CFI R5 ; minute as raw int\n");
    emit_asm("    MOV R6, R3\n");
    emit_asm("    CFI R6 ; second as raw int\n");

    emit_asm("    PUSH R1 ; hour (float)\n");
    emit_asm("    PUSH R2 ; minute (float)\n");
    emit_asm("    PUSH R3 ; second (float)\n");

    emit_asm("    PUSH R4 ; hour (int)\n");
    emit_asm("    PUSH R5 ; minute (int)\n");
    emit_asm("    PUSH R6 ; second (int)\n");
    emit_asm("    CALL __builtin_format_time_string\n");
    emit_asm("    IADD SP, 3\n");
    // R0 = boxed time string

    emit_asm("    POP R3 ; second (float)\n");
    emit_asm("    POP R2 ; minute (float)\n");
    emit_asm("    POP R1 ; hour (float)\n");

    char extra_ret_access[128];
    get_extra_return_slot_access(0, extra_ret_access);
    emit_asm("    MOV %s, R3 ; return value 4: second\n", extra_ret_access);
    emit_asm("    MOV R3, R2 ; return value 3: minute\n");
    emit_asm("    MOV R2, R1 ; return value 2: hour\n");
    // R0 already holds the formatted string: return value 1

    return 4;
}
