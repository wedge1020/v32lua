#include "v32lua.h"

void  emit_system_wait_intrinsic ()
{
    v32io_emit_frame_end_hooks ();     // keyboard/mouse read every frame (if used)
    emit_asm ("WAIT\n");
}

void  emit_system_halt_intrinsic ()
{
    emit_asm ("HLT\n");
}
