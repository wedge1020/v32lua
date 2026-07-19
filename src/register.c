#include "v32lua.h"

// ============================================================================
// --- Register Inventory Implementation ---
// ============================================================================

// 0 means free, 1 means currently holding data
static int  register_inventory[NUM_GPRS] = { 1, 0 }; 

void  lock_register (int  reg)
{
    if (reg >= 0 && reg < NUM_GPRS) {
        register_inventory[reg] = 1;
    }
}

void  unlock_register (int  reg)
{
    if (reg >  0 && reg < NUM_GPRS) {
        register_inventory[reg] = 0;
    }
}

int  is_register_locked (int  reg)
{
    if (reg >= 0 && reg < NUM_GPRS) {
        return register_inventory[reg];
    }
    return 0;
}

int  allocate_register (void)
{
    for (int i = 1; i < NUM_GPRS; i++) {
        if (!register_inventory[i]) {
            register_inventory[i] = 1;
            return i;
        }
    }
    compiler_error(ERR_INTERNAL, -1, "Register inventory exhausted!");
    return -1;
}
