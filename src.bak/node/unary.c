#include "v32lua.h"

void  node_unary (ASTNode *node, int  dest_reg)
{
    // Evaluate the operand into dest_reg
    generate_asm(node->as.unary.operand, dest_reg);
    
    if (node->as.unary.operator == OP_LEN) {
        // Push the operand to the stack
        emit_asm ("PUSH R%d\n", dest_reg);
        
        // Call the built-in
        emit_asm ("CALL __builtin_len\n");
        
        // Clean up the stack
        emit_asm ("IADD SP, 1\n");
        
        // Move the returned length into the destination register
        emit_asm ("MOV R%d, R0\n", dest_reg);

    }
    else if (node->as.unary.operator == OP_NOT) {
        int label_id = get_next_label();
        const char *ctx = get_current_function_name(); // Fetch context
        char to_true_label[128], end_label[128];
        snprintf(to_true_label, sizeof(to_true_label), "__%s_not_true_%d", ctx, label_id); // Prefix added
        snprintf(end_label, sizeof(end_label), "__%s_not_end_%d", ctx, label_id);         // Prefix added
        int  scratch_reg  = allocate_register ();

        // ✅ Short-lived scratch
        mark_register_live(scratch_reg, 2);

        ensure_in_register(dest_reg);  // Reload dest_reg if it was spilled by allocate_register()

        // 1. Check if Nil or False using scratch register
        emit_asm("MOV R%d, R%d\n", scratch_reg, dest_reg);
        emit_asm("IEQ R%d, BOXED_NIL ; Is Nil?\n", scratch_reg);
        emit_asm("JT  R%d, %s\n", scratch_reg, to_true_label);
        emit_asm("MOV R%d, R%d\n", scratch_reg, dest_reg);
        emit_asm("IEQ R%d, BOXED_FALSE ; Is False?\n", scratch_reg);
        emit_asm("JT  R%d, %s\n", scratch_reg, to_true_label);

        // 2. If truthy, return BOXED_FALSE
        emit_asm("MOV R%d, BOXED_FALSE ; Return False\n", dest_reg);
        emit_asm("JMP %s\n", end_label);

        // 3. If falsy, return BOXED_TRUE
        emit_asm("%s:\n", to_true_label);
        emit_asm("MOV R%d, BOXED_TRUE ; Return True\n", dest_reg);
        emit_asm("%s:\n", end_label);
        unlock_register (scratch_reg);
    }
    else if (node -> as.unary.operator == OP_UNM) {
        emit_asm ("PUSH R%d\n", dest_reg);
        emit_asm ("CALL __builtin_unm\n");
        emit_asm ("IADD SP, 1\n");
        emit_asm ("MOV R%d, R0\n", dest_reg);
    }
}
