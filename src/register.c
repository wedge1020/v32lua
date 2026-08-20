// ============================================================================
// register.c - Liveness-Aware Register Allocator with Emergency Spill
// ============================================================================
//
// This module implements a liveness-aware register allocator for the Vircon32
// architecture. It tracks register usage, implements spilling to stack memory,
// and manages register pinning for values that must stay in registers.
//
// FIX 3: Added emergency spill capability for when all registers are pinned.
// When normal allocation fails, we can force-spill a pinned register to free
// up space. This is a last-resort measure to prevent compilation failures.
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

// Returns the stack slot offset for a given register
static int get_register_spill_slot(int reg)
{
    return (base_spill_frame_offset - reg - 1);
}

// Emits assembly to load a register value from its spill slot
static void emit_load_from_spill(int reg, int slot)
{
    emit_asm("MOV R%d, [BP %d] ; REGSPILL: Load from spill slot\n", reg, slot);
}

// Emits assembly to store a register value to its spill slot
static void emit_store_to_spill(int reg, int slot)
{
    emit_asm("MOV [BP %d], R%d ; REGSPILL: Store to spill slot\n", slot, reg);
}

// Initializes spill slot tracking for a new function
void reset_spill_slots(int start_slot)
{
    base_spill_frame_offset = start_slot;
    for (int index = 0; index < NUM_GPRS; index++) {
        spill_slot_for_reg[index] = 0;
        register_use_distance[index] = 0;
    }
}

// ============================================================================
// Core Operations
// ============================================================================

// Spills a register to its assigned stack slot
// Will NOT spill if the register is pinned (use force_spill_register for that)
void spill_register(int reg)
{
    if (reg < 0 || reg >= NUM_GPRS) return;
    if (register_pinned[reg]) return;

    int slot = get_register_spill_slot(reg);
    spill_slot_for_reg[reg] = slot;  // Overwrite with new slot
    emit_store_to_spill(reg, slot);
    register_inventory[reg] = 0;
}

// Forces a register to spill even if it's pinned
// Used for emergency register recovery when inventory is exhausted
// FIX 3: New function for emergency spilling
void force_spill_register(int reg)
{
    if (reg < 0 || reg >= NUM_GPRS) return;

    // Debug output if in verbose debug mode
    if (g_verbose_debug) {
        fprintf(stderr, "[debug] force_spill_register() EMERGENCY: Force-spilling pinned R%d to free inventory\n", reg);
    }

    int slot = get_register_spill_slot(reg);
    spill_slot_for_reg[reg] = slot;
    emit_store_to_spill(reg, slot);
    register_inventory[reg] = 0;
    // Note: We do NOT clear the pinned flag here - the register is still
    // conceptually pinned, but it's now spilled to memory. The caller must
    // restore it with ensure_in_register() when needed.
}

// Ensures a register's value is in the register (loads from spill if needed)
int ensure_in_register(int reg)
{
    if (reg < 0 || reg >= NUM_GPRS) return -1;

    // Reload if there's ANY spilled value, regardless of inventory state
    if (spill_slot_for_reg[reg] != 0) {
        emit_load_from_spill(reg, spill_slot_for_reg[reg]);
        spill_slot_for_reg[reg] = 0;  // Clear after reload
        register_inventory[reg] = 1;
    }
    return reg;
}

// Locks a register (marks as allocated but not pinned)
void lock_register(int reg)
{
    if (reg >= 0 && reg < NUM_GPRS) {
        register_inventory[reg] = 1;
        // A freshly-allocated register has use_distance == 0, which Phase 2
        // of allocate_register() treats as "dead" and will silently hand
        // back out to the very next caller with NO spill at all. Locking a
        // register is supposed to protect it from exactly this kind of
        // casual reuse (callers still allocate around it, it just isn't a
        // free-for-all target) -- so mark it long-lived. It remains
        // spillable under real pressure via Phase 3, which correctly saves
        // and (via ensure_in_register) restores its value.
        register_use_distance[reg] = 10000;
    }
}

// Unlocks a register (marks as free)
void unlock_register(int reg)
{
    if (reg >= 0 && reg < NUM_GPRS) {
        register_inventory[reg] = 0;
        register_use_distance[reg] = 0; // Clear liveness
    }
}

// Checks if a register is currently locked (allocated)
int is_register_locked(int reg)
{
    return (reg >= 0 && reg < NUM_GPRS) ? register_inventory[reg] : 0;
}

// ============================================================================
// Liveness Tracking
// ============================================================================

// Marks a register as live for a certain number of instructions
void mark_register_live(int reg, int distance)
{
    if (reg >= 0 && reg < NUM_GPRS) {
        register_use_distance[reg] = distance;
    }
}

// Decrements the liveness counter for a register
void update_register_live(int reg)
{
    if (reg >= 0 && reg < NUM_GPRS && register_use_distance[reg] > 0) {
        register_use_distance[reg]--;
    }
}

// Allocates a register using a 4-phase strategy:
// 1. Free register (not allocated, not pinned)
// 2. Dead register (allocated but use_distance == 0)
// 3. Spill farthest-future-use register (allocated, not pinned)
// 4. Fallback to highest-numbered register (allocated, not pinned)
//
// Phase 5 (pinned-register emergency spill) has been REMOVED. It used to
// force-spill a still-pinned register out from under whoever pinned it,
// with no way to notify that code its register had been silently
// evicted -- the very next read of that register would get garbage
// instead of the value the caller believed was still safely resident.
// That's exactly what caused the intermittent, hard-to-trace runtime
// corruption behind a real bug (a pin/unlock mismatch in
// emit_tic80_print_intrinsic() that leaked 3 pinned registers per call).
//
// If normal allocation genuinely can't find a register now, that means
// too many registers are pinned simultaneously somewhere in the call
// stack of codegen functions currently executing -- which is a real bug
// in the compiler, not something safe to paper over at runtime. Failing
// loudly here, at the exact point of exhaustion, is far more debuggable
// than letting a corrupted ROM run and blue-screen minutes later.
int allocate_register(void)
{
    // Phase 1: Free register
    for (int i = 1; i < NUM_GPRS; i++) {
        if (!register_inventory[i] && !register_pinned[i]) {
            register_inventory[i] = 1;
            register_use_distance[i] = 0;
            return i;
        }
    }

    // Phase 2: Dead register (use_distance == 0)
    for (int i = 1; i < NUM_GPRS; i++) {
        if (register_inventory[i] && !register_pinned[i] && register_use_distance[i] == 0) {
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

    // No unpinned register available anywhere -- this means something
    // upstream pinned registers and never released them (a pin/unlock
    // mismatch), or a genuinely pathological amount of simultaneous
    // pinning. Either way, report it as a compiler bug instead of
    // silently stealing a pinned register out from under its owner.
    if (best_candidate == -1) {
        if (g_verbose_debug) {
            fprintf(stderr, "[debug] allocate_register() CRITICAL: All registers pinned and allocated!\n");
            fprintf(stderr, "[debug] allocate_register() Register Inventory: ");
            for (int i = 0; i < NUM_GPRS; i++) {
                fprintf(stderr, "R%d=%d(p=%d) ", i, register_inventory[i], register_pinned[i]);
            }
            fprintf(stderr, "\n");
        }
        compiler_error(ERR_INTERNAL, -1,
            "Register inventory exhausted: every register is pinned. "
            "This means some codegen function pinned a register via "
            "allocate_pinned_register() and released it with plain "
            "unlock_register() instead of unlock_pinned_register() -- "
            "check for that mismatch, or an unlock_pinned_register() "
            "call missing on an error/early-return path.");
        return -1;
    }

    // Spill the selected candidate if it was allocated
    if (register_inventory[best_candidate]) {
        spill_register(best_candidate);
        // spill_register() just recorded a pending spill slot so the OLD
        // occupant's value can be restored later via ensure_in_register().
        // But this register is about to be handed out fresh, for a brand
        // new and unrelated value -- if we leave the flag set, the first
        // ensure_in_register() call the NEW owner makes (e.g. right after
        // computing its own value into this register) will wrongly reload
        // the OLD spilled value on top of it. Clear it: only a future
        // spill of the NEW value should set this flag again.
        spill_slot_for_reg[best_candidate] = 0;
    }

    // Allocate the register
    register_inventory[best_candidate] = 1;
    // Set to large value to prevent immediate reuse
    register_use_distance[best_candidate] = 10000;

    // Debug output
    if (g_verbose_debug) {
        fprintf(stderr, "[debug] allocate_register(): Allocated R%d (was pinned: %d)\n",
                best_candidate, register_pinned[best_candidate]);
    }

    return best_candidate;
}

// Allocates and pins a register (won't be spilled by normal allocation)
int allocate_pinned_register(void)
{
    int reg = allocate_register();
    register_pinned[reg] = 1;
    return reg;
}

// Unpins and unlocks a register
void unlock_pinned_register(int reg)
{
    register_pinned[reg] = 0;
    unlock_register(reg);
}

// Updates liveness for all registers
void update_all_registers_live(void)
{
    for (int i = 0; i < NUM_GPRS; i++) {
        update_register_live(i);
    }
}

//////////////////////////////////////////////////////////////////////////////
//
// Helper to update liveness only if the operand is a valid register
//
void  update_if_register (const char *operand)
{
    //////////////////////////////////////////////////////////////////////////
    //
    // Safety check for NULL pointers
    //
    if (operand                               != NULL)
    {
        int reg_idx = -1;

        //////////////////////////////////////////////////////////////////////
        //
        // 2. Try to parse the string as "R" followed by an integer.
        // sscanf returns the number of successfully matched items.
        //
        if (sscanf (operand, "R%d", &reg_idx) == 1)
        {
            //////////////////////////////////////////////////////////////////
            //
            // 3. Boundary check to ensure it's a valid GPR before updating
            //
            if ((reg_idx                      >= 0) &&
                (reg_idx                      <  NUM_GPRS))
            {
                update_register_live (reg_idx);
            }
        }
    }
}
