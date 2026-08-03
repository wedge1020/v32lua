#include "v32lua.h"

/**
 * Emits assembly for the ioports.spu.cmd() intrinsic.
 *
 * Dispatches SPU commands based on the provided mode argument.
 * Supports static string literals, numeric literals (0-5), and dynamic variables.
 *
 * String modes:
 *   "play"     -> SPUCommand_PlaySelectedChannel   (0x30)
 *   "pause"    -> SPUCommand_PauseSelectedChannel  (0x31)
 *   "stop"     -> SPUCommand_StopSelectedChannel   (0x32)
 *   "pauseall" -> SPUCommand_PauseAllChannels      (0x33)
 *   "resume"   -> SPUCommand_ResumeAllChannels     (0x34)
 *   "allstop"  -> SPUCommand_StopAllChannels       (0x35)
 *
 * Numeric modes (0-5):
 *   0 -> SPUCommand_PlaySelectedChannel
 *   1 -> SPUCommand_PauseSelectedChannel
 *   2 -> SPUCommand_StopSelectedChannel
 *   3 -> SPUCommand_PauseAllChannels
 *   4 -> SPUCommand_ResumeAllChannels
 *   5 -> SPUCommand_StopAllChannels
 *
 * @param node     The AST node representing the function call.
 * @param dest_reg The destination register for the result (0 = discard).
 *                 If provided, returns BOXED_NIL (no meaningful return value).
 * @return         true if successfully emitted.
 */
bool emit_spu_cmd_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg_mode = node->as.call.args_head;

    emit_asm("    ;; --- Intrinsic: ioports.spu.cmd(mode) ---\n");

    // =====================================================================
    // CASE A: No argument -> Default to play
    // =====================================================================
    if (arg_mode == NULL) {
        emit_asm("OUT SPU_Command, SPUCommand_PlaySelectedChannel\n");
        if (dest_reg != 0) {
            emit_asm("MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
        }
        return true;
    }

    // =====================================================================
    // CASE B: Static String Literal -> Map to SPU command
    // =====================================================================
    if (arg_mode->type == NODE_STRING) {
        const char *val = arg_mode->as.string_val.value;

        if      (strcmp(val, "play")     == 0) emit_asm("OUT SPU_Command, SPUCommand_PlaySelectedChannel\n");
        else if (strcmp(val, "pause")    == 0) emit_asm("OUT SPU_Command, SPUCommand_PauseSelectedChannel\n");
        else if (strcmp(val, "stop")     == 0) emit_asm("OUT SPU_Command, SPUCommand_StopSelectedChannel\n");
        else if (strcmp(val, "pauseall") == 0) emit_asm("OUT SPU_Command, SPUCommand_PauseAllChannels\n");
        else if (strcmp(val, "resume")   == 0) emit_asm("OUT SPU_Command, SPUCommand_ResumeAllChannels\n");
        else if (strcmp(val, "allstop")  == 0) emit_asm("OUT SPU_Command, SPUCommand_StopAllChannels\n");
        else {
            // Unrecognized string: fallback to play
            emit_asm("OUT SPU_Command, SPUCommand_PlaySelectedChannel\n");
        }

        if (dest_reg != 0) {
            emit_asm("MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
        }
        return true;
    }

    // =====================================================================
    // CASE C: Static Number Literal -> Map to SPU command
    // =====================================================================
    if (arg_mode->type == NODE_NUMBER) {
        int cmd = (int)arg_mode->as.number.val;

        if      (cmd == 0) emit_asm("OUT SPU_Command, SPUCommand_PlaySelectedChannel\n");
        else if (cmd == 1) emit_asm("OUT SPU_Command, SPUCommand_PauseSelectedChannel\n");
        else if (cmd == 2) emit_asm("OUT SPU_Command, SPUCommand_StopSelectedChannel\n");
        else if (cmd == 3) emit_asm("OUT SPU_Command, SPUCommand_PauseAllChannels\n");
        else if (cmd == 4) emit_asm("OUT SPU_Command, SPUCommand_ResumeAllChannels\n");
        else if (cmd == 5) emit_asm("OUT SPU_Command, SPUCommand_StopAllChannels\n");
        else {
            // Invalid number: fallback to play
            emit_asm("OUT SPU_Command, SPUCommand_PlaySelectedChannel\n");
        }

        if (dest_reg != 0) {
            emit_asm("MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
        }
        return true;
    }

    // =====================================================================
    // CASE D: Dynamic Variable -> Runtime evaluation with nil-check
    // =====================================================================
    int mode_reg = allocate_register();
	register_pinned[mode_reg] = 1;
    generate_asm(arg_mode, mode_reg);

    int label_id = get_next_label();
    const char *ctx = get_current_function_name();

    char is_nil_label[128], end_label[128];
    snprintf(is_nil_label, sizeof(is_nil_label), "__%s_spu_cmd_nil_%d", ctx, label_id);
    snprintf(end_label,    sizeof(end_label),    "__%s_spu_cmd_end_%d", ctx, label_id);

    int scratch = allocate_register();
	register_pinned[scratch] = 1;

    // Check for runtime nil
    emit_asm("MOV R%d, R%d\n",          scratch, mode_reg);
    emit_asm("IEQ R%d, BOXED_NIL ; Check for runtime nil\n", scratch);
    emit_asm("JT R%d, %s ; If nil, jump to default fallback\n", scratch, is_nil_label);

    // Not nil: cast float to integer for SPU command
    emit_asm("CFI R%d\n", mode_reg);
    emit_asm("JMP %s\n",   end_label);

    // Nil fallback: use default play command (0)
    emit_asm("%s:\n", is_nil_label);
    emit_asm("MOV R%d, 0 ; Runtime nil -> Default to play (0)\n", mode_reg);

    emit_asm("%s:\n", end_label);

    // Dispatch the resolved mode to the SPU
    emit_asm("OUT SPU_Command, R%d ; Trigger SPU operation\n", mode_reg);

    if (dest_reg != 0) {
        emit_asm("MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
    }

	register_pinned[mode_reg] = 0;
	register_pinned[scratch] = 0;

    unlock_register(scratch);
    unlock_register(mode_reg);
    return true;
}
