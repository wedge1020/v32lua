#include "v32lua.h"

void  emit_system_wait_intrinsic ()
{
    emit_asm ("WAIT\n");
}

void  emit_system_halt_intrinsic ()
{
    emit_asm ("HLT\n");
}
