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

////////////////////////////////////////////////////////////////////////////////////////
//
// register function prototypes
//
void  lock_register (int);
void  unlock_register (int);
int   is_register_locked (int);
int   allocate_register (void); 

#endif
