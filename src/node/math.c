#include "v32lua.h"

void  node_add (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);
    int  right_reg  = allocate_register();  // May spill another value

    // ✅ Will be used immediately, short-lived
    mark_register_live (right_reg, 1);

    generate_asm (node -> as.binary.right, right_reg);

    // Ensure both are in registers (load from stack if spilled)
    ensure_in_register (dest_reg);
    ensure_in_register (right_reg);

    emit_asm("FADD R%d, R%d\n", dest_reg, right_reg);
    unlock_register(right_reg);
}

void  node_mul (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);
    int  right_reg  = allocate_register ();

    // ✅ Will be used immediately, short-lived
    mark_register_live (right_reg, 1);

    generate_asm (node -> as.binary.right, right_reg);

    // Ensure both are in registers (load from stack if spilled)
    ensure_in_register (dest_reg);
    ensure_in_register (right_reg);

    emit_asm ("FMUL R%d, R%d\n", dest_reg, right_reg);
    unlock_register (right_reg);
}

void  node_sub (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);
    int  right_reg  = allocate_register ();

    // ✅ Will be used immediately, short-lived
    mark_register_live (right_reg, 1);

    generate_asm (node -> as.binary.right, right_reg);

    // Ensure both are in registers (load from stack if spilled)
    ensure_in_register (dest_reg);
    ensure_in_register (right_reg);

    emit_asm ("FSUB R%d, R%d\n", dest_reg, right_reg);
    unlock_register (right_reg);
}

void  node_div (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);
    int  right_reg  = allocate_register ();

    // ✅ Will be used immediately, short-lived
    mark_register_live (right_reg, 1);

    generate_asm (node -> as.binary.right, right_reg);

    // Ensure both are in registers (load from stack if spilled)
    ensure_in_register (dest_reg);
    ensure_in_register (right_reg);

    emit_asm ("FDIV R%d, R%d\n", dest_reg, right_reg);
    unlock_register (right_reg);
}

void  node_mod (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);
    int  right_reg  = allocate_register();

    // Will be used immediately, short-lived
    mark_register_live (right_reg, 1);

    generate_asm (node -> as.binary.right, right_reg);

    // Ensure both are in registers (load from stack if spilled)
    ensure_in_register (dest_reg);
    ensure_in_register (right_reg);

    // Cast to integers for modulo (Lua % uses integer division)
    emit_asm ("CFI R%d ; Cast left to int\n", dest_reg);
    emit_asm ("CFI R%d ; Cast right to int\n", right_reg);

    // Perform integer modulo
    emit_asm ("IMOD R%d, R%d\n", dest_reg, right_reg);

    // Cast result back to float (Lua numbers are floats)
    emit_asm ("CIF R%d ; Cast result back to float\n", dest_reg);

    unlock_register (right_reg);
}

void node_floordiv (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);
    int  right_reg  = allocate_register ();
    mark_register_live (right_reg, 1);

    generate_asm (node -> as.binary.right, right_reg);

    ensure_in_register (dest_reg);
    ensure_in_register (right_reg);

    // Cast to integers for floor division (Lua // uses integer division)
    emit_asm ("CFI R%d ; Cast left to int\n",  dest_reg);
    emit_asm ("CFI R%d ; Cast right to int\n", right_reg);

    // Perform integer division
    emit_asm ("IDIV R%d, R%d\n", dest_reg, right_reg);

    // Cast result back to float (Lua numbers are floats)
    emit_asm ("CIF R%d ; Cast result back to float\n", dest_reg);

    unlock_register (right_reg);
}
