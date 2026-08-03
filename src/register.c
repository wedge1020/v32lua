// ============================================================================
// register.c - Liveness-Aware Register Allocator
// ============================================================================

#include "v32lua.h"
#include "emit.h"

// Register state
int  register_inventory[NUM_GPRS]     = { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
int  register_pinned[NUM_GPRS]        = { 0 };
int  spill_slot_for_reg[NUM_GPRS]     = { 0 };
int  register_use_distance[NUM_GPRS]  = { 0 };
int  base_spill_frame_offset          = -1;

// ============================================================================
// Spill Management
// ============================================================================

static int   get_register_spill_slot (int  reg)
{
    return (base_spill_frame_offset - reg - 1);
}

static void  emit_load_from_spill (int  reg, int  slot)
{
    emit_asm ("MOV R%d, [BP %d] ; REGSPILL: Load from spill slot\n", reg, slot);
}

static void  emit_store_to_spill (int  reg, int  slot)
{
    emit_asm ("MOV [BP %d], R%d ; REGSPILL: Store to spill slot\n", slot, reg);
}

void  reset_spill_slots (int  start_slot)
{
    base_spill_frame_offset           = start_slot;
    for (int index                    = 0;
		 index                       <  NUM_GPRS;
		 index                        = index + 1)
	{
        spill_slot_for_reg[index]     = 0;
        register_use_distance[index]  = 0;
    }
}

// ============================================================================
// Core Operations
// ============================================================================

void spill_register(int reg) {
    if (reg < 0 || reg >= NUM_GPRS) return;
    if (register_pinned[reg]) return;

    int slot = get_register_spill_slot(reg);
    spill_slot_for_reg[reg] = slot;
    emit_store_to_spill(reg, slot);
    register_inventory[reg] = 0;
}

// FIXED: Check for non-zero instead of > 0
int ensure_in_register(int reg) {
    if (reg < 0 || reg >= NUM_GPRS) return -1;

    if (spill_slot_for_reg[reg] != 0) {
        emit_load_from_spill(reg, spill_slot_for_reg[reg]);
        spill_slot_for_reg[reg] = 0;
        register_inventory[reg] = 1;
    }
    return reg;
}

void lock_register(int reg) {
    if (reg >= 0 && reg < NUM_GPRS) register_inventory[reg] = 1;
}

void unlock_register(int reg) {
    if (reg >= 0 && reg < NUM_GPRS) {
        register_inventory[reg] = 0;
        register_use_distance[reg] = 0; // Clear liveness
    }
}

int is_register_locked(int reg) {
    return (reg >= 0 && reg < NUM_GPRS) ? register_inventory[reg] : 0;
}

// ============================================================================
// Liveness Tracking
// ============================================================================

void mark_register_live(int reg, int distance) {
    if (reg >= 0 && reg < NUM_GPRS) {
        register_use_distance[reg] = distance;
    }
}

void update_register_live(int reg) {
    if (reg >= 0 && reg < NUM_GPRS && register_use_distance[reg] > 0) {
        register_use_distance[reg]--;
    }
}

// ============================================================================
// Intelligent Allocation with Liveness
// ============================================================================

int allocate_register(void) {
    // Phase 1: Free register
    for (int i = 1; i < NUM_GPRS; i++) {
        if (!register_inventory[i] && !register_pinned[i]) {
            register_inventory[i] = 1;
            spill_slot_for_reg[i] = 0;
            register_use_distance[i] = 0;
            return i;
        }
    }

    // Phase 2: Dead register (use_distance == 0)
    for (int i = 1; i < NUM_GPRS; i++) {
        if (register_inventory[i] && !register_pinned[i] && register_use_distance[i] == 0) {
            spill_slot_for_reg[i] = 0;
            register_use_distance[i] = 0;
            return i;
        }
    }

    // Phase 3: Spill farthest-use register
    int best_candidate = -1;
    int max_distance = -1;

    for (int i = 1; i < NUM_GPRS; i++) {
        if (register_inventory[i] && !register_pinned[i]) {
            if (register_use_distance[i] > max_distance) {
                max_distance = register_use_distance[i];
                best_candidate = i;
            }
        }
    }

    // Phase 4: Fallback to highest-numbered
    if (best_candidate == -1) {
        for (int i = NUM_GPRS - 1; i >= 1; i--) {
            if (register_inventory[i] && !register_pinned[i]) {
                best_candidate = i;
                break;
            }
        }
    }

    if (best_candidate == -1) {
        compiler_error(ERR_INTERNAL, -1, "Register inventory exhausted!");
        return -1;
    }

    spill_register(best_candidate);
    register_inventory[best_candidate] = 1;
    spill_slot_for_reg[best_candidate] = 0;
	// ✅ FIX: Set to large value instead of 0 to prevent immediate reuse
	register_use_distance[best_candidate] = 10000;  // Or any value > existing distances
    //register_use_distance[best_candidate] = 0; // bug

    return best_candidate;
}
