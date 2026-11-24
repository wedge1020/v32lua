#include "v32lua.h"

void  emit_system_wait_intrinsic ()
{
    v32io_emit_frame_end_hooks ();     // keyboard/mouse read every frame (if used)
    gc_emit_safepoint ();              // end of a frame: nothing half-allocated
    emit_asm ("WAIT\n");
}

void  emit_system_halt_intrinsic ()
{
    emit_asm ("HLT\n");
}
