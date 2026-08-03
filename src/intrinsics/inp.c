#include "v32lua.h"

/**
 * Emits assembly to read the current gamepad input bitfield.
 * Used by ioports.inp.inputs action intrinsic.
 *
 * @param dest_reg The destination register for the result.
 */
void  emit_get_gamepad_inputs_intrinsic (int  dest_reg)
{
    int  bit_reg  = allocate_register();
	register_pinned[bit_reg] = 1;
    emit_asm ("    ;; --- Intrinsic: Read Gamepad Inputs, collate into one word ---\n");
    emit_asm ("MOV R%d, 0\n", dest_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadLeft");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 10\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadRight");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 9\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadUp");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 8\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadDown");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 7\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonStart");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 6\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonA");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 5\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonB");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 4\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonX");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 3\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonY");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 2\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonL");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 1\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonR");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("    ;; --- Intrinsic: Cast to Lua Float ---\n");
    emit_asm ("CIF R%d\n", dest_reg);
	register_pinned[bit_reg] = 0;
    unlock_register (bit_reg);
}
