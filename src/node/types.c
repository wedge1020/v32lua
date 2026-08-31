#include "v32lua.h"

void  node_identifier (ASTNode *node, int  dest_reg)
{
    // An alias resolves at compile time and has no boxed value, so it cannot
    // be read as one. Say so instead of emitting a load from a global slot
    // that nothing ever initializes.
    if (is_intrinsic_alias(node->as.id.name)) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "'%s' is a compile-time alias for %s and has no runtime value; "
            "call it directly", node->as.id.name,
            resolve_intrinsic_alias(node->as.id.name));
        return;
    }

    ////////////////////////////////////////////////////////////////////////
    //
    // Dynamically lookup identifier location
    //
    SymbolNode *sym  = resolve_symbol (node -> as.id.name);

    // Function values are constant code addresses, not data sitting in a
    // RAM slot -- nested/local functions never get their global slot
    // initialized (only top-level functions do, in
    // __global_scope_initialization). Load and box the address directly
    // instead of indirecting through memory that may be uninitialized.
    if ((sym        != NULL) &&
        (sym -> is_function))
    {
        emit_load_function_value (sym -> def_node, node -> as.id.name, dest_reg);
        return;
    }

    emit_load_variable (node -> as.id.name, dest_reg);
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
