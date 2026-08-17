//
// Register Inventory:
//
// Vircon32 has R0-R15, but R14 is BP and R15 is SP. 
// We will track general purpose registers R0 through R13.
//
////////////////////////////////////////////////////////////////////////////////////////

#ifndef _REGISTER_H
#define _REGISTER_H

#define NUM_GPRS 14
#define MAX_SPILL_SLOTS 64  // Arbitrary limit for spilled values

// Track which registers should NOT be spilled
extern int  register_pinned[NUM_GPRS];

// Track spilled values: which register → which stack slot
extern int  spill_slot_for_reg[NUM_GPRS];

// Track next available stack slot (negative offset from BP)
extern int  next_spill_slot;
extern int  register_inventory[];
extern int  register_use_distance[NUM_GPRS];
extern int  base_spill_frame_offset;

////////////////////////////////////////////////////////////////////////////////////////
//
// register function prototypes
//
void  lock_register             (int);
void  unlock_register           (int);
int   allocate_pinned_register  (void);
void  unlock_pinned_register    (int);
int   is_register_locked        (int);
int   allocate_register         (void);
void  spill_register            (int);  // Spill a register to stack
void  force_spill_register      (int);
int   ensure_in_register        (int);  // Load if spilled
void  reset_spill_slots         (int);  // per-function spilling
void  mark_register_live        (int,  int);
void  update_register_live      (int);
void  update_all_registers_live (void);
void  update_if_register        (const char *);

#endif
