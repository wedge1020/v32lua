#include "v32lua.h"
#include "emit.h"

// Register inventory and spill tracking
static int register_inventory[NUM_GPRS] = { 1, 0 };
int spill_slot_for_reg[NUM_GPRS] = {0};  // Tracks whether register is currently spilled

// Base offset in stack frame where register spill slots begin
static int base_spill_frame_offset = -1;

// Initialize or reset spill frame layout at function entry
void reset_spill_slots(int start_slot) {
    base_spill_frame_offset = start_slot; // e.g., -(num_locals + 1)
    for (int i = 0; i < NUM_GPRS; i++) {
        spill_slot_for_reg[i] = 0;
    }
}

// Compute the fixed, dedicated stack slot for a given register
static int get_register_spill_slot(int reg) {
    // Each register gets its own permanent slot relative to BP
    // e.g., base_spill_frame_offset - reg
    return base_spill_frame_offset - reg;
}

static void emit_load_from_spill(int reg, int slot) {
    emit_asm("MOV R%d, [BP %d] ; REGSPILL: Load spilled value from dedicated slot\n", reg, slot);
}

static void emit_store_to_spill(int reg, int slot) {
    emit_asm("MOV [BP %d], R%d ; REGSPILL: Store value to dedicated slot\n", slot, reg);
}

void spill_register(int reg) {
    if (reg < 0 || reg >= NUM_GPRS) return;

    int slot = get_register_spill_slot(reg);
    spill_slot_for_reg[reg] = slot;

    emit_store_to_spill(reg, slot);
    register_inventory[reg] = 0; // Mark register as free
}

int ensure_in_register(int reg) {
    if (reg < 0 || reg >= NUM_GPRS) return -1;

    if (spill_slot_for_reg[reg] > 0) {  // > 0 = valid spill slot (not pinned)
        emit_load_from_spill(reg, spill_slot_for_reg[reg]);
        spill_slot_for_reg[reg] = 0;
        register_inventory[reg] = 1;
    }
    return reg;
}

int is_register_locked(int reg) {
    if (reg >= 0 && reg < NUM_GPRS) {
        return register_inventory[reg];
    }
    return 0;
}

int allocate_register(void) {
    // 1. Try to find an unlocked, free register
    for (int i = 1; i < NUM_GPRS; i++) {
        if (!register_inventory[i]) {
            register_inventory[i] = 1;
            spill_slot_for_reg[i] = 0;
            return i;
        }
    }

	// In the spill path:
	for (int i = NUM_GPRS - 1; i >= 1; i--) {
		if (register_inventory[i] && spill_slot_for_reg[i] == 0 && !register_pinned[i]) {
			spill_register(i);
			register_inventory[i] = 1;
			return i;
		}
	}

    compiler_error(ERR_INTERNAL, -1, "Register inventory exhausted (no spill candidates)!");
    return -1;
}

void unlock_register(int reg) {
    if (reg >= 0 && reg < NUM_GPRS) {
        register_inventory[reg] = 0;
    }
}

/*

#include "v32lua.h"
#include "emit.h"  // For emit_asm()

// ============================================================================
// --- Register Inventory Implementation ---
// ============================================================================

// Existing inventory
static int register_inventory[NUM_GPRS] = { 1, 0 };

// Spill tracking
int spill_slot_for_reg[NUM_GPRS] = {0};  // 0 = not spilled
int next_spill_slot = -1;  // Stack grows downward from BP

// Emit load/store helpers
static void emit_load_from_spill (int  reg, int  slot) {
    emit_asm ("MOV R%d, [BP %d] ; Load spilled value from stack\n", reg, slot);
}

static void emit_store_to_spill (int  reg, int  slot) {
    emit_asm ("MOV [BP %d], R%d ; Store value to spill slot\n", slot, reg);
}

// Spill a register to stack
void spill_register(int reg) {
    if (reg < 0 || reg >= NUM_GPRS) return;

    // Allocate a spill slot
    int slot = next_spill_slot--;
    spill_slot_for_reg[reg] = slot;

    // Store the value to stack
    emit_store_to_spill(reg, slot);

    // Mark register as free
    register_inventory[reg] = 0;
}

// Ensure value is in a register (load from stack if spilled)
int ensure_in_register(int reg) {
    if (reg < 0 || reg >= NUM_GPRS) return -1;

    if (spill_slot_for_reg[reg] != 0) {
        // Value is spilled - load it back
        emit_load_from_spill(reg, spill_slot_for_reg[reg]);
        spill_slot_for_reg[reg] = 0;  // No longer spilled
        register_inventory[reg] = 1;  // Mark as in-use
        return reg;
    }

    // Already in register
    return reg;
}

int  is_register_locked (int  reg)
{
    if (reg >= 0 && reg < NUM_GPRS) {
        return register_inventory[reg];
    }
    return 0;
}

// allocate_register with spilling
int allocate_register(void) {
    // 1. Try to find a free register
    for (int i = 1; i < NUM_GPRS; i++) {
        if (!register_inventory[i]) {
            register_inventory[i] = 1;
			spill_slot_for_reg[i] = 0;
            return i;
        }
    }

    // 2. No free registers - find one to spill
    // Strategy: Spill the register with the highest number (simplest)
    // TODO: Better strategy - track liveness and spill least recently used
    for (int i = NUM_GPRS - 1; i >= 1; i--) {
        if (register_inventory[i] && spill_slot_for_reg[i] == 0) {
            // This register is in use and not already spilled
            spill_register(i);
            register_inventory[i] = 1;  // Re-lock it for new use
			//spill_slot_for_reg[i] = 0;
            return i;
        }
    }

    // 3. Should never reach here
    compiler_error(ERR_INTERNAL, -1, "Register inventory exhausted (no spill candidates)!");
    return -1;
}

// unlock_register - check if we should spill
void unlock_register(int reg) {
    if (reg >= 0 && reg < NUM_GPRS) {
        // Don't actually free - just mark as available for spilling
        // The allocator will spill it when needed
        register_inventory[reg] = 0;
    }
}

// Add this function:
void reset_spill_slots(int start_slot) {
    next_spill_slot = start_slot;
    // Clear any stale spill info
    for (int i = 0; i < NUM_GPRS; i++) {
        spill_slot_for_reg[i] = 0;
    }
}
*/
