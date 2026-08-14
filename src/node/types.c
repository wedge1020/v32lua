#include "v32lua.h"

void  node_identifier (ASTNode *node, int  dest_reg)
{
    ////////////////////////////////////////////////////////////////////////
    //
    // Dynamically lookup identifier location
    //
    char  var_access[256];
    get_variable_access_string (node -> as.id.name, var_access);
    emit_asm ("MOV R%d, %s\n", dest_reg, var_access);
}

void  node_number (ASTNode *node, int  dest_reg)
{
    emit_asm ("MOV R%d, %f\n", dest_reg, node -> as.number.val);
}

void  node_string (ASTNode *node, int  dest_reg)
{
    // Register the literal and get its ID
    int  string_id  = add_string_literal (node -> as.string_val.value);
    
    // Load the raw pointer into the destination register
    emit_asm ("MOV R%d, __string_%d\n", dest_reg, string_id);
    
    // Apply the NaN-box String Tag (Base NaN + Bit 22)
    emit_asm ("OR R%d, BOXED_ROMSTRING ; Box as ROM String\n", dest_reg);
}

void node_concat (ASTNode *node, int dest_reg)
{
    // Evaluate left operand into R0 and push immediately
    generate_asm(node->as.binary.left, 0);
    emit_asm("PUSH R0             ; Save left operand\n");

    // Evaluate right operand into R0 and push immediately
    generate_asm(node->as.binary.right, 0);
    emit_asm("PUSH R0             ; Save right operand\n");

    // Call __builtin_strcat (operands safely on stack)
    emit_asm("CALL __builtin_strcat\n");
    emit_asm("IADD SP, 2\n");

    if (dest_reg != 0)
        emit_asm("MOV R%d, R0\n", dest_reg);
}
