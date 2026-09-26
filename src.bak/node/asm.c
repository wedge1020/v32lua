#include "v32lua.h"

void  node_asm (ASTNode *node)
{
    emit_asm ("    ;; --- Begin Inline ASM Bubble (existing register states preserved) ---\n");
    
    // Get the formatted string for SP and BP snapshots
    char sp_access[256];
    char bp_access[256];
    get_variable_access_string ("asm_snap_sp", sp_access);
    get_variable_access_string ("asm_snap_bp", bp_access);
    
    emit_asm ("MOV %s, SP\n", sp_access);
    emit_asm ("MOV %s, BP\n", bp_access);

    for (int i = 0; i < NUM_GPRS; i++) {
        if (is_register_locked (i)) {
            char snap_name[32];
            sprintf (snap_name, "asm_snap_r%d", i);
            
            char reg_access[256];
            get_variable_access_string (snap_name, reg_access);
            emit_asm ("MOV %s, R%d\n", reg_access, i);
        }
    }
    
    emit_interpolated_asm (node->as.inline_asm.code);

    for (int i = 0; i < NUM_GPRS; i++) {
        if (is_register_locked (i)) {
            char snap_name[32];
            sprintf (snap_name, "asm_snap_r%d", i);
            
            char reg_access[256];
            get_variable_access_string (snap_name, reg_access);
            emit_asm ("MOV R%d, %s\n", i, reg_access);
        }
    }

    emit_asm ("MOV BP, %s\n", bp_access);
    emit_asm ("MOV SP, %s\n", sp_access);
    emit_asm ("    ;; --- End Inline ASM Bubble ---\n");
}

void  node_rawasm (ASTNode *node)
{
    emit_asm ("    ;; --- Begin Raw ASM (Unprotected) ---\n");
    emit_interpolated_asm (node -> as.inline_asm.code);
    emit_asm ("    ;; --- End Raw ASM ---\n");
}
