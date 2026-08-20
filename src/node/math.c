#include "v32lua.h"

void  node_add (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);

    // -------------------------------------------------------------------
    // FIX (cross-CALL register clobber): evaluating the RIGHT operand
    // below may itself contain a nested function call (e.g.
    // `n + accumulate(n - 1)`) -- and per this compiler's own established
    // convention, plain registers never survive a CALL boundary; every
    // callee treats every register as scratch. dest_reg (holding the
    // already-computed LEFT operand) was previously left sitting in its
    // physical register completely unprotected while the right operand
    // was evaluated, so any nested call on the right silently destroyed
    // it before the arithmetic op ever ran. Observed directly:
    // `k * factorial(k - 1)`-style recursion collapsing to the base
    // case's own return value at every level, because the multiplication
    // never actually saw the real 'k'.
    //
    // Spilling dest_reg to the stack before evaluating the right operand
    // -- and reloading it immediately after, right before the op itself
    // -- makes this immune to whatever the right operand's evaluation
    // does internally, including arbitrarily deep nested CALLs. Same
    // spill-across-possible-nested-CALLs idiom already used for table
    // operations elsewhere in this compiler (see node_table_set()). This
    // supersedes the old post-hoc ensure_in_register(dest_reg) call,
    // which only recovered a value the COMPILER's own allocator chose to
    // spill -- it had no protection against a hardware CALL clobbering
    // the register directly.
    // -------------------------------------------------------------------
    emit_asm ("PUSH R%d ; spill left operand (protect across possible nested CALL in right operand)\n", dest_reg);

    int  right_reg  = allocate_register();
    mark_register_live (right_reg, 1);
    generate_asm (node -> as.binary.right, right_reg);
    ensure_in_register (right_reg);

    emit_asm ("POP R%d ; reload spilled left operand\n", dest_reg);

    emit_asm("FADD R%d, R%d\n", dest_reg, right_reg);
    unlock_register(right_reg);
}

void  node_mul (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);

    // See node_add() for the full rationale -- identical fix, applied
    // here because this exact node type is what exposed the bug
    // (`k * factorial(k - 1)`-style recursion).
    emit_asm ("PUSH R%d ; spill left operand (protect across possible nested CALL in right operand)\n", dest_reg);

    int  right_reg  = allocate_register ();
    mark_register_live (right_reg, 1);
    generate_asm (node -> as.binary.right, right_reg);
    ensure_in_register (right_reg);

    emit_asm ("POP R%d ; reload spilled left operand\n", dest_reg);

    emit_asm ("FMUL R%d, R%d\n", dest_reg, right_reg);
    unlock_register (right_reg);
}

void  node_sub (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);

    // See node_add() for the full rationale.
    emit_asm ("PUSH R%d ; spill left operand (protect across possible nested CALL in right operand)\n", dest_reg);

    int  right_reg  = allocate_register ();
    mark_register_live (right_reg, 1);
    generate_asm (node -> as.binary.right, right_reg);
    ensure_in_register (right_reg);

    emit_asm ("POP R%d ; reload spilled left operand\n", dest_reg);

    emit_asm ("FSUB R%d, R%d\n", dest_reg, right_reg);
    unlock_register (right_reg);
}

void  node_div (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);

    // See node_add() for the full rationale.
    emit_asm ("PUSH R%d ; spill left operand (protect across possible nested CALL in right operand)\n", dest_reg);

    int  right_reg  = allocate_register ();
    mark_register_live (right_reg, 1);
    generate_asm (node -> as.binary.right, right_reg);
    ensure_in_register (right_reg);

    emit_asm ("POP R%d ; reload spilled left operand\n", dest_reg);

    emit_asm ("FDIV R%d, R%d\n", dest_reg, right_reg);
    unlock_register (right_reg);
}

void  node_mod (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);

    // See node_add() for the full rationale.
    emit_asm ("PUSH R%d ; spill left operand (protect across possible nested CALL in right operand)\n", dest_reg);

    int  right_reg  = allocate_register();
    mark_register_live (right_reg, 1);
    generate_asm (node -> as.binary.right, right_reg);
    ensure_in_register (right_reg);

    emit_asm ("POP R%d ; reload spilled left operand\n", dest_reg);

    // Cast to integers for modulo (Lua % uses integer division)
    emit_asm ("CFI R%d ; Cast left to int\n", dest_reg);
    emit_asm ("CFI R%d ; Cast right to int\n", right_reg);

    emit_asm ("IMOD R%d, R%d\n", dest_reg, right_reg);

    emit_asm ("CIF R%d ; Cast result back to float\n", dest_reg);

    unlock_register (right_reg);
}

void node_floordiv (ASTNode *node, int  dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);

    // See node_add() for the full rationale.
    emit_asm ("PUSH R%d ; spill left operand (protect across possible nested CALL in right operand)\n", dest_reg);

    int  right_reg  = allocate_register ();
    mark_register_live (right_reg, 1);
    generate_asm (node -> as.binary.right, right_reg);
    ensure_in_register (right_reg);

    emit_asm ("POP R%d ; reload spilled left operand\n", dest_reg);

    emit_asm ("CFI R%d ; Cast left to int\n",  dest_reg);
    emit_asm ("CFI R%d ; Cast right to int\n", right_reg);

    emit_asm ("IDIV R%d, R%d\n", dest_reg, right_reg);

    emit_asm ("CIF R%d ; Cast result back to float\n", dest_reg);

    unlock_register (right_reg);
}

void node_pow (ASTNode *node, int dest_reg)
{
    generate_asm (node -> as.binary.left, dest_reg);

    // See node_add() for the full rationale.
    emit_asm ("PUSH R%d ; spill left operand (protect across possible nested CALL in right operand)\n", dest_reg);

    int right_reg = allocate_register ();
    mark_register_live (right_reg, 1);
    generate_asm (node -> as.binary.right, right_reg);
    ensure_in_register (right_reg);

    emit_asm ("POP R%d ; reload spilled left operand\n", dest_reg);

    emit_asm ("POW R%d, R%d\n", dest_reg, right_reg);
    unlock_register (right_reg);
}
