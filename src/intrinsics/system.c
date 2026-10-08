#include "v32lua.h"

void  emit_system_wait_intrinsic ()
{
    v32kbd_emit_frame_end_hook ();     // keyboard read every frame (if used)
    emit_asm ("WAIT\n");
}

void  emit_system_halt_intrinsic ()
{
    emit_asm ("HLT\n");
}
