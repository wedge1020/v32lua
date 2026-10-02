#include "v32lua.h"

// ----------------------------------------------------------------------------
// String coercion in arithmetic: Lua (and PICO-8) turn a numeric string
// operand into its number -- "12" + 1 is 13, ("0x".."ff") + 0 is 255
// (nanoman decodes its levels that way). An operand that isn't known to be
// a number is tested (4 instructions: is it NaN-boxed?) and, only then,
// converted by __arith_coerce; numbers pass straight through.
// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
// Locals that are always numbers
// ----------------------------------------------------------------------------
// The NaN-box test above costs 4 instructions per operand, on every pass
// through a loop: `i % j` in a doubly nested `for` paid 8 of its ~34
// instructions for it, though `i` and `j` can only ever hold numbers.
//
// So, per function, the names whose EVERY binding and assignment anywhere in
// the function body (nested functions included) gives a number are worked
// out before the body is generated:
//   * `local n = <number>` / `n = <number>`, where <number> is a numeric
//     literal, an arithmetic expression, or another such name;
//   * a numeric `for` variable whose start (and step) is such a <number>.
// Anything else -- a parameter of that name, `local n` with no value, a
// call's result, a generic-for variable, a function of that name -- rules
// the name out, as does any inline asm in the function. The analysis is
// per NAME, not per declaration, which keeps shadowing safe: two locals
// called `n` must both qualify.
//
// A name that is ONLY ever a `for` variable with a literal start > 0 and a
// literal (or default) step > 0 is also known to be non-zero, so `x % j`,
// `x / j` and `x // j` skip the division-by-zero guard (3 instructions).
//
// At a use the name must resolve to a stack local of the function being
// generated (not a global, not an upvalue): only then are the assignments
// that were examined all the assignments there are.
// ----------------------------------------------------------------------------
#define NUMLOCALS_MAX   96
#define NUMLOCALS_DEPTH 32

typedef struct {
    const char *name;
    bool        number;     // every binding / assignment is a number
    bool        positive;   // only ever a `for` variable counting up from > 0
} NumLocal;

typedef struct {
    NumLocal v[NUMLOCALS_MAX];
    int      n;
    bool     changed;
} NumLocals;

static NumLocals numlocals_stack[NUMLOCALS_DEPTH];
static int       numlocals_depth = 0;     // 0: not inside a function body

static NumLocal *numlocals_find (NumLocals *s, const char *name)
{
    if (name == NULL) return NULL;
    for (int i = 0; i < s->n; i++)
        if (strcmp (s->v[i].name, name) == 0) return &s->v[i];
    return NULL;
}

// A name seen for the first time starts out as a number; later passes only
// ever take that away.
static NumLocal *numlocals_get (NumLocals *s, const char *name)
{
    NumLocal *l = numlocals_find (s, name);
    if (l != NULL || name == NULL || s->n >= NUMLOCALS_MAX) return l;
    l = &s->v[s->n++];
    l->name = name; l->number = true; l->positive = true;
    s->changed = true;
    return l;
}

static void numlocals_rule_out (NumLocals *s, const char *name)
{
    NumLocal *l = numlocals_get (s, name);
    if (l == NULL) return;                 // table full: unknown names are not numbers
    if (l->number || l->positive) s->changed = true;
    l->number = false; l->positive = false;
}

static bool numlocals_is_number_expr (NumLocals *s, ASTNode *e)
{
    if (e == NULL) return false;
    switch (e->type) {
        case NODE_NUMBER: case NODE_ADD: case NODE_SUB: case NODE_MUL:
        case NODE_DIV: case NODE_MOD: case NODE_POW: case NODE_FLOORDIV:
            return true;
        case NODE_UNARY:
            return e->as.unary.operator == OP_LEN || e->as.unary.operator == OP_UNM;
        case NODE_IDENTIFIER: {
            NumLocal *l = numlocals_find (s, e->as.id.name);
            return l != NULL && l->number;
        }
        default:
            return false;
    }
}

static void numlocals_rule_out_all (NumLocals *s)
{
    for (int i = 0; i < s->n; i++) {
        if (s->v[i].number || s->v[i].positive) s->changed = true;
        s->v[i].number = false; s->v[i].positive = false;
    }
}

// One pass over a statement / expression list. Returns false if a node kind
// it doesn't know turned up (the caller then rules everything out).
static bool numlocals_scan (NumLocals *s, ASTNode *n)
{
    for (; n != NULL; n = n->next) {
        switch (n->type) {
            case NODE_MULTIPLE_ASSIGNMENT: {
                ASTNode *v = n->as.mult_assign.values_head;
                for (ASTNode *t = n->as.mult_assign.targets_head; t != NULL; t = t->next) {
                    if (t->type == NODE_IDENTIFIER) {
                        if (!numlocals_is_number_expr (s, v)) {
                            numlocals_rule_out (s, t->as.id.name);
                        } else {
                            NumLocal *l = numlocals_get (s, t->as.id.name);
                            if (l != NULL && l->positive) { l->positive = false; s->changed = true; }
                        }
                    } else if (t->type == NODE_TABLE_GET) {
                        ASTNode *te = t->as.table_get.table_expr, *ke = t->as.table_get.key;
                        // (children are scanned one at a time: a target's
                        // `next` is the next target, not a sibling to rescan)
                        ASTNode *tn = te ? te->next : NULL, *kn = ke ? ke->next : NULL;
                        if (te) { te->next = NULL; bool ok = numlocals_scan (s, te); te->next = tn; if (!ok) return false; }
                        if (ke) { ke->next = NULL; bool ok = numlocals_scan (s, ke); ke->next = kn; if (!ok) return false; }
                    } else {
                        return false;
                    }
                    if (v != NULL) v = v->next;
                }
                if (!numlocals_scan (s, n->as.mult_assign.values_head)) return false;
                break;
            }
            case NODE_FOR_NUMERIC: {
                ASTNode *st = n->as.for_numeric.start_expr, *sp = n->as.for_numeric.step_expr;
                const char *name = n->as.for_numeric.index_name;
                if (!numlocals_is_number_expr (s, st) || (sp != NULL && !numlocals_is_number_expr (s, sp))) {
                    numlocals_rule_out (s, name);
                } else {
                    NumLocal *l = numlocals_get (s, name);
                    bool up = st->type == NODE_NUMBER && st->as.number.val > 0 &&
                              (sp == NULL || (sp->type == NODE_NUMBER && sp->as.number.val > 0));
                    if (l != NULL && l->positive && !up) { l->positive = false; s->changed = true; }
                }
                if (!numlocals_scan (s, st)) return false;
                if (!numlocals_scan (s, n->as.for_numeric.stop_expr)) return false;
                if (!numlocals_scan (s, sp)) return false;
                if (!numlocals_scan (s, n->as.for_numeric.body)) return false;
                break;
            }
            case NODE_FOR_GENERIC:
                for (ASTNode *v = n->as.for_generic.var_list; v != NULL; v = v->next) {
                    if (v->type != NODE_IDENTIFIER) return false;
                    numlocals_rule_out (s, v->as.id.name);
                }
                if (!numlocals_scan (s, n->as.for_generic.iter_expr)) return false;
                if (!numlocals_scan (s, n->as.for_generic.body)) return false;
                break;
            case NODE_FUNCTION_DEF:
                numlocals_rule_out (s, n->as.function_def.name);
                for (ASTNode *p = n->as.function_def.params; p != NULL; p = p->next) {
                    if (p->type != NODE_IDENTIFIER) return false;
                    numlocals_rule_out (s, p->as.id.name);
                }
                if (!numlocals_scan (s, n->as.function_def.body)) return false;
                break;
            case NODE_FUNCTION_POINTER:
                if (!numlocals_scan (s, n->as.func_ptr.func_def)) return false;
                break;
            case NODE_WHILE:
                if (!numlocals_scan (s, n->as.while_loop.condition)) return false;
                if (!numlocals_scan (s, n->as.while_loop.body)) return false;
                break;
            case NODE_REPEAT:
                if (!numlocals_scan (s, n->as.repeat_loop.body)) return false;
                if (!numlocals_scan (s, n->as.repeat_loop.condition)) return false;
                break;
            case NODE_IF:
                if (!numlocals_scan (s, n->as.if_stmt.condition)) return false;
                if (!numlocals_scan (s, n->as.if_stmt.if_body)) return false;
                if (!numlocals_scan (s, n->as.if_stmt.else_body)) return false;
                break;
            case NODE_DO_BLOCK:
                if (!numlocals_scan (s, n->as.do_block.body)) return false;
                break;
            case NODE_FUNCTION_CALL:
                if (!numlocals_scan (s, n->as.call.target)) return false;
                if (!numlocals_scan (s, n->as.call.args_head)) return false;
                break;
            case NODE_RETURN:
                if (!numlocals_scan (s, n->as.return_stmt.expressions_head)) return false;
                break;
            case NODE_ADD: case NODE_SUB: case NODE_MUL: case NODE_DIV:
            case NODE_FLOORDIV: case NODE_MOD: case NODE_POW: case NODE_AND:
            case NODE_OR: case NODE_RELATIONAL: case NODE_CONCAT:
            case NODE_BAND: case NODE_BOR: case NODE_BXOR: case NODE_SHL:
            case NODE_SHR: case NODE_LSHR: case NODE_ROTL: case NODE_ROTR:
                if (!numlocals_scan (s, n->as.binary.left)) return false;
                if (!numlocals_scan (s, n->as.binary.right)) return false;
                break;
            case NODE_UNARY:
                if (!numlocals_scan (s, n->as.unary.operand)) return false;
                break;
            case NODE_TABLE_CONSTRUCTOR:
                if (!numlocals_scan (s, n->as.table_constructor.initializers_head)) return false;
                break;
            case NODE_TABLE_SET:
                if (!numlocals_scan (s, n->as.table_set.table_expr)) return false;
                if (!numlocals_scan (s, n->as.table_set.key)) return false;
                if (!numlocals_scan (s, n->as.table_set.value)) return false;
                break;
            case NODE_TABLE_GET:
                if (!numlocals_scan (s, n->as.table_get.table_expr)) return false;
                if (!numlocals_scan (s, n->as.table_get.key)) return false;
                break;
            case NODE_BREAK: case NODE_GOTO: case NODE_LABEL:
            case NODE_VARIADIC_EXPR: case NODE_STRING: case NODE_BOOLEAN:
            case NODE_NIL: case NODE_IDENTIFIER: case NODE_NUMBER:
            case NODE_COMMENT_LINE: case NODE_COMMENT_BLOCK:
                break;
            default:
                return false;       // inline asm, or a node this doesn't know
        }
    }
    return true;
}

// Called around the generation of a function's body (node/function.c).
void numlocals_enter (ASTNode *func_def)
{
    if (numlocals_depth >= NUMLOCALS_DEPTH) { numlocals_depth++; return; }
    NumLocals *s = &numlocals_stack[numlocals_depth++];
    s->n = 0;

    bool ok = true;
    int  rounds = 0;
    do {
        s->changed = false;
        for (ASTNode *p = func_def->as.function_def.params; p != NULL; p = p->next) {
            if (p->type == NODE_IDENTIFIER) numlocals_rule_out (s, p->as.id.name);
            else ok = false;
        }
        if (ok) ok = numlocals_scan (s, func_def->as.function_def.body);
    } while (ok && s->changed && ++rounds < NUMLOCALS_MAX + 2);

    if (!ok || s->changed || s->n >= NUMLOCALS_MAX) numlocals_rule_out_all (s);
}

void numlocals_leave (void)
{
    if (numlocals_depth > 0) numlocals_depth--;
}

static NumLocal *numlocals_current (ASTNode *e)
{
    if (e == NULL || e->type != NODE_IDENTIFIER) return NULL;
    if (numlocals_depth < 1 || numlocals_depth > NUMLOCALS_DEPTH) return NULL;
    NumLocal *l = numlocals_find (&numlocals_stack[numlocals_depth - 1], e->as.id.name);
    if (l == NULL || !l->number) return NULL;
    SymbolNode *sym = resolve_symbol (e->as.id.name);
    if (sym == NULL || sym->type != SYM_LOCAL || sym->is_function) return NULL;
    return l;
}

static bool is_static_number (ASTNode *e)
{
    if (e == NULL) return false;
    switch (e->type) {
        case NODE_NUMBER: case NODE_ADD: case NODE_SUB: case NODE_MUL:
        case NODE_DIV: case NODE_MOD: case NODE_POW: case NODE_FLOORDIV:
            return true;
        case NODE_UNARY:
            return e->as.unary.operator == OP_LEN || e->as.unary.operator == OP_UNM;
        case NODE_IDENTIFIER:
            return numlocals_current (e) != NULL;
        default:
            return false;
    }
}

// A divisor that can't be zero: a non-zero literal, or a `for` variable
// that only counts up from a positive start.
static bool is_static_nonzero (ASTNode *e)
{
    if (e == NULL) return false;
    if (e->type == NODE_NUMBER) return e->as.number.val != 0;
    NumLocal *l = numlocals_current (e);
    return l != NULL && l->positive;
}

void emit_arith_coerce (int reg, ASTNode *e)
{
    if (is_static_number (e)) return;
    int id = get_next_label ();
    const char *ctx = get_current_function_name ();
    emit_asm ("MOV  R0, R%d\n", reg);
    emit_asm ("AND  R0, NAN_VALUE\n");
    emit_asm ("IEQ  R0, NAN_VALUE ; not a number?\n");
    emit_asm ("JF   R0, __%s_num_%d\n", ctx, id);
    emit_asm ("MOV  R0, R%d\n", reg);
    emit_asm ("CALL __arith_coerce ; a numeric string -> its number\n");
    emit_asm ("MOV  R%d, R0\n", reg);
    emit_asm ("__%s_num_%d:\n", ctx, id);
}

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
    emit_arith_coerce (dest_reg, node -> as.binary.left);
    emit_arith_coerce (right_reg, node -> as.binary.right);

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
    emit_arith_coerce (dest_reg, node -> as.binary.left);
    emit_arith_coerce (right_reg, node -> as.binary.right);

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
    emit_arith_coerce (dest_reg, node -> as.binary.left);
    emit_arith_coerce (right_reg, node -> as.binary.right);

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
    emit_arith_coerce (dest_reg, node -> as.binary.left);
    emit_arith_coerce (right_reg, node -> as.binary.right);

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
    if (is_static_nonzero (node -> as.binary.right)) {
        emit_asm ("FDIV R%d, R%d ; divisor is never zero\n", dest_reg, right_reg);
        unlock_register (right_reg);
        return;
    }

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
    emit_arith_coerce (dest_reg, node -> as.binary.left);
    emit_arith_coerce (right_reg, node -> as.binary.right);

    // Lua's % is FLOOR modulo: a % b == a - floor(a/b)*b -- NOT C's
    // truncating modulo, which the old CFI->IMOD->CIF implementation
    // used. Truncating and floor modulo only agree when a and b share a
    // sign; they diverge whenever the operands have opposite signs (e.g.
    // -5 % 3 must be 1 in Lua, not -2), which is exactly the case the
    // old implementation got wrong. Computed here in pure floats, the
    // same way node_floordiv() computes // via FDIV+FLR, so this also
    // stays correct for fractional operands, not just integers.
    //
    // Needs a third register: dest_reg (a) and right_reg (b) both have
    // to survive intact until the final subtract, so the quotient can't
    // be computed in either of them.
    int quot_reg = allocate_register ();
    mark_register_live (quot_reg, 1);

    // FDIV by zero is a Vircon32 hardware error (DivisionError). a % 0 is
    // 0: PICO-8's answer, and for Lua (NaN) the only safe one -- a NaN
    // bit pattern here would read as a boxed value (see node_div()).
    int         mod_id  = get_next_label ();
    const char *mod_ctx = get_current_function_name ();
    bool        guarded = !is_static_nonzero (node -> as.binary.right);
    if (guarded) {
        emit_asm ("MOV R%d, 0.0\n", quot_reg);
        emit_asm ("FEQ R%d, R%d ; is divisor zero?\n", quot_reg, right_reg);
        emit_asm ("JF  R%d, __%s_mod_ok_%d\n", quot_reg, mod_ctx, mod_id);
        emit_asm ("MOV R%d, 0.0 ; a %% 0 = 0\n", dest_reg);
        emit_asm ("JMP __%s_mod_done_%d\n", mod_ctx, mod_id);
        emit_asm ("__%s_mod_ok_%d:\n", mod_ctx, mod_id);
    }
    emit_asm ("MOV R%d, R%d ; quot = a\n", quot_reg, dest_reg);
    emit_asm ("FDIV R%d, R%d ; quot = a / b\n", quot_reg, right_reg);
    emit_asm ("FLR  R%d ; quot = floor(a / b)\n", quot_reg);
    emit_asm ("FMUL R%d, R%d ; quot = floor(a / b) * b\n", quot_reg, right_reg);
    emit_asm ("FSUB R%d, R%d ; dest = a - floor(a / b) * b\n", dest_reg, quot_reg);
    if (guarded) {
        emit_asm ("__%s_mod_done_%d:\n", mod_ctx, mod_id);
    }

    unlock_register (quot_reg);
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
    emit_arith_coerce (dest_reg, node -> as.binary.left);
    emit_arith_coerce (right_reg, node -> as.binary.right);

    // Use float division, then floor - matches Lua // semantics. FDIV by
    // zero is a Vircon32 hardware error: a // 0 is floor(a / 0), with the
    // same saturated +-huge node_div() gives a / 0.
    int         fd_id  = get_next_label ();
    const char *fd_ctx = get_current_function_name ();
    int         z_reg  = allocate_register ();
    emit_asm ("MOV R%d, 0.0\n", z_reg);
    emit_asm ("FEQ R%d, R%d ; is divisor zero?\n", z_reg, right_reg);
    emit_asm ("JF  R%d, __%s_fdiv_ok_%d\n", z_reg, fd_ctx, fd_id);
    emit_asm ("MOV R%d, R%d\n", z_reg, dest_reg);
    emit_asm ("MOV R%d, [__const_math_huge]\n", dest_reg);
    emit_asm ("FLT R%d, 0.0 ; negative dividend: -huge\n", z_reg);
    emit_asm ("JF  R%d, __%s_fdiv_done_%d\n", z_reg, fd_ctx, fd_id);
    emit_asm ("FSGN R%d\n", dest_reg);
    emit_asm ("JMP __%s_fdiv_done_%d\n", fd_ctx, fd_id);
    emit_asm ("__%s_fdiv_ok_%d:\n", fd_ctx, fd_id);
    emit_asm ("FDIV R%d, R%d\n", dest_reg, right_reg);
    emit_asm ("FLR R%d\n", dest_reg);  // Floor the result
    emit_asm ("__%s_fdiv_done_%d:\n", fd_ctx, fd_id);
    unlock_register (z_reg);

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
    emit_arith_coerce (dest_reg, node -> as.binary.left);
    emit_arith_coerce (right_reg, node -> as.binary.right);

    emit_asm ("CFI R%d ; Cast left to int\n",  dest_reg);
    emit_asm ("CFI R%d ; Cast right to int\n", right_reg);

    emit_asm ("IDIV R%d, R%d\n", dest_reg, right_reg);

    emit_asm ("CIF R%d ; Cast result back to float\n", dest_reg);

    unlock_register (right_reg);
}*/

/*
 * x_reg = x_reg ^ y_reg, without the CPU's PowerError: POW raises a
 * hardware error for a negative base with a non-integer exponent. The real
 * answer is NaN, which NaN-boxing can't carry (it would read back as a boxed
 * value, see node_div()), so the result is 0 -- as PICO-8's sqrt() of a
 * negative. y_is_int: the exponent is a known integer, so no guard needed.
 */
void emit_safe_pow (int x_reg, int y_reg, bool y_is_int)
{
    if (y_is_int)
    {
        emit_asm ("POW R%d, R%d\n", x_reg, y_reg);
        return;
    }
    int         id  = get_next_label ();
    const char *ctx = get_current_function_name ();
    int         t   = allocate_register ();
    emit_asm ("MOV R%d, R%d\n", t, x_reg);
    emit_asm ("FLT R%d, 0.0 ; negative base?\n", t);
    emit_asm ("JF  R%d, __%s_pow_ok_%d\n", t, ctx, id);
    emit_asm ("MOV R%d, R%d\n", t, y_reg);
    emit_asm ("FLR R%d\n", t);
    emit_asm ("FEQ R%d, R%d ; integer exponent?\n", t, y_reg);
    emit_asm ("JT  R%d, __%s_pow_ok_%d\n", t, ctx, id);
    emit_asm ("MOV R%d, 0.0 ; no real result: 0, not a PowerError\n", x_reg);
    emit_asm ("JMP __%s_pow_done_%d\n", ctx, id);
    emit_asm ("__%s_pow_ok_%d:\n", ctx, id);
    emit_asm ("POW R%d, R%d\n", x_reg, y_reg);
    emit_asm ("__%s_pow_done_%d:\n", ctx, id);
    unlock_register (t);
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
    emit_arith_coerce (dest_reg, node -> as.binary.left);
    emit_arith_coerce (right_reg, node -> as.binary.right);

    ASTNode *r = node -> as.binary.right;
    emit_safe_pow (dest_reg, right_reg,
                   r -> type == NODE_NUMBER && r -> as.number.val == (double) (long long) r -> as.number.val);
    unlock_register (right_reg);
}
