#include "v32lua.h"

// ============================================================================
// Conditions compiled as jumps
// ----------------------------------------------------------------------------
// generate_cond_jump(expr, when_true, label) emits code that jumps to `label`
// when expr's Lua truthiness equals `when_true`, and otherwise falls through.
//
// `if`/`while`/`repeat` used to evaluate their condition to a boxed value and
// then test it for nil/false; `and`/`or` did the same at every level, so a
// failed first term of `a and b and c and d` was re-tested once per enclosing
// `and` on the way out, and every comparison built a boxed true/false only to
// have it tested again. Here `and`/`or`/`not` become plain control flow and
// comparisons jump directly on the hardware compare result.
//
// Comparisons also get specialized forms:
//   x == nil / true / false   one IEQ against the constant (these values have
//                             exactly one representation)
//   x == 5 (number literal)   one FEQ: a boxed x is a NaN and never equal;
//                             -0 == 0 holds
//   x < y (etc.)              FLT/FLE/FGT/FGE inline when both are numbers;
//                             strings and mixed types go to __builtin_relcmp
//   x == y (general)          identical bits / both numbers / both strings
//                             inline; only string-vs-string content compares
//                             call __builtin_eq
// ============================================================================

// Constant truthiness of a literal; false if not a literal.
static bool const_truth (ASTNode *n, bool *truth)
{
    if (n == NULL) return false;
    switch (n->type)
    {
        case NODE_BOOLEAN: *truth = n->as.boolean.val; return true;
        case NODE_NIL:     *truth = false;             return true;
        case NODE_NUMBER:  *truth = true;              return true;   // 0 is truthy
        case NODE_STRING:  *truth = true;              return true;
        default:           return false;
    }
}

// A literal whose evaluation is a single MOV (no CALL): the left operand
// doesn't need spilling around it.
static bool is_literal (ASTNode *n)
{
    return n && (n->type == NODE_NUMBER || n->type == NODE_STRING ||
                 n->type == NODE_NIL    || n->type == NODE_BOOLEAN);
}

// nil / true / false literal -> its boxed word
static const char *unique_constant (ASTNode *n)
{
    if (n == NULL) return NULL;
    if (n->type == NODE_NIL) return "BOXED_NIL";
    if (n->type == NODE_BOOLEAN) return n->as.boolean.val ? "BOXED_TRUE" : "BOXED_FALSE";
    return NULL;
}

static void fresh_label (char *buf, size_t n, const char *what)
{
    snprintf (buf, n, "__%s_%s_%d", get_current_function_name (), what, get_next_label ());
}

// Jump to label if reg's truthiness == when_true. Clobbers reg's copy in R0
// (or reg itself when reg is R0).
void emit_truth_jump (int reg, bool when_true, const char *label)
{
    // nil = 0xFFC00000, false = 0xFFC00001: falsy <=> (v & ~1) == BOXED_NIL
    emit_asm ("MOV  R0, R%d\n", reg);
    emit_asm ("AND  R0, 0xFFFFFFFE\n");
    emit_asm ("IEQ  R0, BOXED_NIL ; R0 = 1 if nil or false\n");
    emit_asm ("%s   R0, %s\n", when_true ? "JF" : "JT", label);
}

// Evaluate left into *lr and right into *rr with the usual spill protection
// (the right operand may CALL, which clobbers every register).
static void eval_pair (ASTNode *left, ASTNode *right, int *lr, int *rr)
{
    *lr = allocate_register ();
    mark_register_live (*lr, 2);
    generate_asm (left, *lr);
    ensure_in_register (*lr);
    *rr = allocate_register ();
    mark_register_live (*rr, 2);
    // A literal right operand is one MOV: no CALL can clobber the left
    // one, so it needn't be spilled -- unless the allocator handed out the
    // left operand's own register.
    bool spill = !is_literal (right) || *rr == *lr;
    if (spill)
        emit_asm ("PUSH R%d ; spill left operand (right operand may CALL)\n", *lr);
    generate_asm (right, *rr);
    ensure_in_register (*rr);
    if (spill)
        emit_asm ("POP  R%d ; reload left operand\n", *lr);
}

static void compare_jump (ASTNode *node, bool when_true, const char *label)
{
    Operator  op    = node->as.binary.operator;
    ASTNode  *left  = node->as.binary.left;
    ASTNode  *right = node->as.binary.right;

    if (op == OP_EQ || op == OP_NEQ)
    {
        // jump when the operands are equal?
        bool jump_on_equal = ((op == OP_EQ) == when_true);

        // x == nil/true/false (either side)
        const char *k = unique_constant (right);
        ASTNode    *other = left;
        if (k == NULL) { k = unique_constant (left); other = right; }
        if (k != NULL)
        {
            int r = allocate_register ();
            mark_register_live (r, 2);
            generate_asm (other, r);
            ensure_in_register (r);
            emit_asm ("IEQ  R%d, %s\n", r, k);
            emit_asm ("%s   R%d, %s\n", jump_on_equal ? "JT" : "JF", r, label);
            unlock_register (r);
            return;
        }

        // x == number literal (either side)
        ASTNode *num = (right && right->type == NODE_NUMBER) ? right
                     : (left && left->type == NODE_NUMBER) ? left : NULL;
        if (num != NULL)
        {
            other = (num == right) ? left : right;
            int r = allocate_register ();
            mark_register_live (r, 2);
            generate_asm (other, r);
            ensure_in_register (r);
            float f = (float) num->as.number.val;
            uint32_t bits; memcpy (&bits, &f, 4);
            // (the constant goes through MOV: the assembler would convert
            // an integer immediate on a float instruction)
            emit_asm ("MOV  R0, 0x%08X ; %.9g\n", bits, num->as.number.val);
            emit_asm ("FEQ  R%d, R0 ; a boxed value is a NaN: never equal\n", r);
            emit_asm ("%s   R%d, %s\n", jump_on_equal ? "JT" : "JF", r, label);
            unlock_register (r);
            return;
        }

        // general equality
        int lr, rr;
        eval_pair (left, right, &lr, &rr);
        char skip[128], boxed[128];
        fresh_label (skip, sizeof skip, "eq_skip");
        fresh_label (boxed, sizeof boxed, "eq_boxed");
        const char *on_eq = jump_on_equal ? label : skip;
        const char *on_ne = jump_on_equal ? skip : label;

        emit_asm ("MOV  R0, R%d\n", lr);
        emit_asm ("IEQ  R0, R%d ; identical?\n", rr);
        emit_asm ("JT   R0, %s\n", on_eq);
        emit_asm ("MOV  R0, R%d\n", lr);
        emit_asm ("AND  R0, NAN_VALUE\n");
        emit_asm ("IEQ  R0, NAN_VALUE\n");
        emit_asm ("JT   R0, %s ; left is boxed\n", boxed);
        emit_asm ("MOV  R0, R%d ; left is a number: numeric compare (-0 == 0; boxed right is a NaN)\n", lr);
        emit_asm ("FEQ  R0, R%d\n", rr);
        emit_asm ("JT   R0, %s\n", on_eq);
        emit_asm ("JMP  %s\n", on_ne);
        emit_asm ("%s:\n", boxed);
        // Different bits, left boxed: only two strings can still be equal
        // (same text at different addresses). nil/booleans share the string
        // tag; __builtin_eq sorts those out.
        emit_asm ("MOV  R0, R%d\n", lr);
        emit_asm ("AND  R0, 0x7FC00000\n");
        emit_asm ("IEQ  R0, 0x7FC00000\n");
        emit_asm ("JF   R0, %s ; left is a table/function: identity only\n", on_ne);
        emit_asm ("MOV  R0, R%d\n", rr);
        emit_asm ("AND  R0, 0x7FC00000\n");
        emit_asm ("IEQ  R0, 0x7FC00000\n");
        emit_asm ("JF   R0, %s ; right is not a string\n", on_ne);
        emit_asm ("PUSH R%d\n", lr);
        emit_asm ("PUSH R%d\n", rr);
        emit_asm ("CALL __builtin_eq\n");
        emit_asm ("IADD SP, 2\n");
        emit_asm ("IEQ  R0, BOXED_TRUE\n");
        emit_asm ("%s   R0, %s\n", jump_on_equal ? "JT" : "JF", label);
        emit_asm ("%s:\n", skip);
        unlock_register (rr);
        unlock_register (lr);
        return;
    }

    // <, <=, >, >=
    int lr, rr;
    eval_pair (left, right, &lr, &rr);
    char slow[128], done[128];
    fresh_label (slow, sizeof slow, "cmp_slow");
    fresh_label (done, sizeof done, "cmp_done");
    const char *jmp = when_true ? "JT" : "JF";
    const char *fop = (op == OP_LT) ? "FLT" : (op == OP_LE) ? "FLE" : (op == OP_GT) ? "FGT" : "FGE";

    if (left->type != NODE_NUMBER)
    {
        emit_asm ("MOV  R0, R%d\n", lr);
        emit_asm ("AND  R0, NAN_VALUE\n");
        emit_asm ("IEQ  R0, NAN_VALUE\n");
        emit_asm ("JT   R0, %s ; left not a number\n", slow);
    }
    if (right->type != NODE_NUMBER)
    {
        emit_asm ("MOV  R0, R%d\n", rr);
        emit_asm ("AND  R0, NAN_VALUE\n");
        emit_asm ("IEQ  R0, NAN_VALUE\n");
        emit_asm ("JT   R0, %s ; right not a number\n", slow);
    }
    emit_asm ("MOV  R0, R%d\n", lr);
    emit_asm ("%s  R0, R%d\n", fop, rr);
    emit_asm ("%s   R0, %s\n", jmp, label);
    emit_asm ("JMP  %s\n", done);
    emit_asm ("%s:\n", slow);
    // strings (and non-comparable values: relcmp returns 2, never true)
    emit_asm ("PUSH R%d\n", lr);
    emit_asm ("PUSH R%d\n", rr);
    emit_asm ("CALL __builtin_relcmp ; -1 / 0 / 1, or 2 if not comparable\n");
    emit_asm ("IADD SP, 2\n");
    switch (op)
    {
        case OP_LT: emit_asm ("IEQ  R0, -1\n"); break;
        case OP_GT: emit_asm ("IEQ  R0, 1\n"); break;
        case OP_LE: emit_asm ("ILE  R0, 0 ; -1 or 0\n"); break;
        default:    emit_asm ("AND  R0, 0xFFFFFFFE\n");
                    emit_asm ("IEQ  R0, 0 ; 0 or 1\n"); break;
    }
    emit_asm ("%s   R0, %s\n", jmp, label);
    emit_asm ("%s:\n", done);
    unlock_register (rr);
    unlock_register (lr);
}

void generate_cond_jump (ASTNode *node, bool when_true, const char *label)
{
    bool truth;
    if (const_truth (node, &truth))
    {
        if (truth == when_true)
            emit_asm ("JMP  %s ; constant condition\n", label);
        return;
    }

    switch (node->type)
    {
        case NODE_AND:
            if (!when_true)
            {
                generate_cond_jump (node->as.binary.left,  false, label);
                generate_cond_jump (node->as.binary.right, false, label);
            }
            else
            {
                char skip[128];
                fresh_label (skip, sizeof skip, "and_skip");
                generate_cond_jump (node->as.binary.left,  false, skip);
                generate_cond_jump (node->as.binary.right, true,  label);
                emit_asm ("%s:\n", skip);
            }
            return;

        case NODE_OR:
            if (when_true)
            {
                generate_cond_jump (node->as.binary.left,  true, label);
                generate_cond_jump (node->as.binary.right, true, label);
            }
            else
            {
                char skip[128];
                fresh_label (skip, sizeof skip, "or_skip");
                generate_cond_jump (node->as.binary.left,  true,  skip);
                generate_cond_jump (node->as.binary.right, false, label);
                emit_asm ("%s:\n", skip);
            }
            return;

        case NODE_UNARY:
            if (node->as.unary.operator == OP_NOT)
            {
                generate_cond_jump (node->as.unary.operand, !when_true, label);
                return;
            }
            break;

        case NODE_RELATIONAL:
            compare_jump (node, when_true, label);
            return;

        default:
            break;
    }

    int r = allocate_register ();
    mark_register_live (r, 2);
    generate_asm (node, r);
    ensure_in_register (r);
    emit_truth_jump (r, when_true, label);
    unlock_register (r);
}

// A comparison / not / and-of-comparisons as a VALUE: evaluate as jumps and
// materialize the boolean once.
void generate_bool_value (ASTNode *node, int dest_reg)
{
    char t[128], e[128];
    fresh_label (t, sizeof t, "bool_true");
    fresh_label (e, sizeof e, "bool_end");
    generate_cond_jump (node, true, t);
    if (dest_reg != 0) emit_asm ("MOV  R%d, BOXED_FALSE\n", dest_reg);
    emit_asm ("JMP  %s\n", e);
    emit_asm ("%s:\n", t);
    if (dest_reg != 0) emit_asm ("MOV  R%d, BOXED_TRUE\n", dest_reg);
    emit_asm ("%s:\n", e);
}
