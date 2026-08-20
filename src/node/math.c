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

    emit_asm ("PUSH R%d ; spill left operand (protect across possible nested CALL in right operand)\n", dest_reg);

    int  right_reg  = allocate_register ();
    mark_register_live (right_reg, 1);
    generate_asm (node -> as.binary.right, right_reg);
    ensure_in_register (right_reg);

    emit_asm ("POP R%d ; reload spilled left operand\n", dest_reg);

    // -------------------------------------------------------------------
    // FIX: guard against division by zero. Vircon32's FDIV instruction
    // HALTS the CPU on a zero divisor -- a genuine hardware exception --
    // instead of following IEEE-754's normal non-trapping float division
    // semantics (x/0 = +-Infinity, 0/0 = NaN) that Lua actually relies
    // on. Real Lua/TIC-80 never crashes on `x / 0`; it just keeps
    // computing with an infinite or NaN result. Left unguarded, any Lua
    // program that legitimately divides by zero -- completely ordinary
    // code, not a bug in the SOURCE -- halts this whole VM instead of
    // continuing (this is exactly what happens in tiger_stripes.lua's
    // bipolar-coordinate math, which hits an exact zero denominator at
    // one specific pixel: i=60, j=0).
    //
    // We deliberately do NOT construct a real IEEE-754 +-Infinity here
    // (0x7F800000 / 0xFF800000), even though that's what real Lua would
    // produce: this runtime's OWN NaN-boxing tag scheme reuses those
    // exact bit patterns for BOXED_FUNCTION and BOXED_TABLE respectively
    // (see v32lua.h). A genuine infinity result would be silently
    // misread by the rest of the runtime as a valid function or table
    // pointer the next time it's compared, printed, or passed anywhere
    // -- trading a loud, diagnosable halt for silent memory corruption
    // somewhere downstream. Saturating to __const_math_huge (already
    // used for math.huge, and already deliberately a large FINITE float
    // rather than a true infinity, presumably for this same reason)
    // keeps the result completely ordinary and safe everywhere else in
    // the runtime. 0/0 saturates to +huge as well, rather than
    // manufacturing a NaN bit pattern with the identical hazard.
    // -------------------------------------------------------------------
    int is_zero_reg = allocate_register();
    emit_asm ("MOV R%d, 0.0\n", is_zero_reg);
    emit_asm ("FEQ R%d, R%d ; is divisor zero?\n", is_zero_reg, right_reg);

    int         label_id    = get_next_label ();
    const char *ctx         = get_current_function_name ();
    char safe_label[128], negate_label[128], done_label[128];
    snprintf (safe_label,   sizeof (safe_label),   "__%s_div_by_zero_%d", ctx, label_id);
    snprintf (negate_label, sizeof (negate_label), "__%s_div_neg_huge_%d", ctx, label_id);
    snprintf (done_label,   sizeof (done_label),   "__%s_div_done_%d", ctx, label_id);

    emit_asm ("JT R%d, %s ; divisor is zero -- skip the real FDIV entirely\n", is_zero_reg, safe_label);
    unlock_register (is_zero_reg);

    emit_asm ("FDIV R%d, R%d\n", dest_reg, right_reg);
    emit_asm ("JMP %s\n", done_label);

    emit_asm ("%s:\n", safe_label);
    // dest_reg still holds the untouched dividend here -- check its sign
    // to decide which saturated value to produce.
    emit_asm ("MOV R%d, R%d ; copy dividend to test its sign\n", right_reg, dest_reg);
    emit_asm ("FLT R%d, 0.0 ; is dividend negative?\n", right_reg);
    emit_asm ("JT R%d, %s\n", right_reg, negate_label);

    emit_asm ("MOV R%d, [__const_math_huge]\n", dest_reg);
    emit_asm ("JMP %s\n", done_label);

    emit_asm ("%s:\n", negate_label);
    emit_asm ("MOV R%d, [__const_math_huge]\n", dest_reg);
    emit_asm ("FSGN R%d\n", dest_reg);

    emit_asm ("%s:\n", done_label);

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

    // Use float division, then floor - matches Lua // semantics
    emit_asm ("FDIV R%d, R%d\n", dest_reg, right_reg);
    emit_asm ("FLR R%d\n", dest_reg);  // Floor the result

    unlock_register (right_reg);
}

/* old version, just in case
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
}*/

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
