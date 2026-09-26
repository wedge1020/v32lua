#include "v32lua.h"

// ============================================================================
// Bitwise operators: & | ~ << >> (Lua 5.3/5.4), unary ~, and PICO-8's
// ^^ >>> <<> >><.
//
// Every v32lua number is a float32, so each operation converts its operands
// to a 32-bit word, operates, and converts back -- in __builtin_bitop
// (runtime/math.s). Two models, chosen at compile time:
//
//   Lua / TIC-80 / native: integers. Operands are floored, then taken
//     modulo 2^32 (so 0xFFFFFFFF and -1 are the same word). Real Lua works
//     on 64-bit integers; the runtime carries the sign of the 64-bit value
//     alongside the low word, so & | ~ and unary ~ give Lua's exact answer
//     for operands in [-2^31, 2^32): 0xFF00 & 0x0FF0 == 0x0F00,
//     ~0 == -1, -1 & 0xFF == 255, 0xFF << 24 == 4278190080 (not negative).
//     >> is logical. A shift count of 32 or more gives 0 (Lua: 64 or more).
//
//   PICO-8: 16.16 fixed point, as PICO-8 itself does it. x is taken as
//     x * 65536 modulo 2^32, so fractions take part (0.5 | 1 == 1.5,
//     bnot(0) == -1/65536) and results are signed 16.16. >> is arithmetic,
//     >>> logical, <<> / >>< rotate. Shift counts are plain integers.
//
// Hard limit (both): a float32 holds 24 significant bits, so a result with
// more (0xDEADBEEF) comes back rounded. Masks and packed fields with few
// significant bits (0xFF000000, 0xF0F0) are exact.
//
// Operands that are both literals are folded here, with bitop_eval() --
// the C twin of __builtin_bitop, which must stay in step with it.
// ============================================================================

enum { BITOP_AND, BITOP_OR, BITOP_XOR, BITOP_NOT, BITOP_SHL, BITOP_SHR, BITOP_SAR,
       BITOP_ROTL, BITOP_ROTR };

static int bitop_code (NodeType t)
{
    switch (t) {
    case NODE_BAND: return BITOP_AND;
    case NODE_BOR:  return BITOP_OR;
    case NODE_BXOR: return BITOP_XOR;
    case NODE_SHL:  return BITOP_SHL;
    // Lua's >> is logical; PICO-8's is arithmetic (>>> is its logical one)
    case NODE_SHR:  return runtime_req.needs_pico8 ? BITOP_SAR : BITOP_SHR;
    case NODE_LSHR: return BITOP_SHR;
    case NODE_ROTL: return BITOP_ROTL;
    case NODE_ROTR: return BITOP_ROTR;
    default:        return BITOP_NOT;
    }
}

// Mirrors __bit_in: float -> 32-bit word + "the 64-bit value is negative"
static uint32_t bit_in (double v, bool p8, int *high)
{
    float f = (float) v;
    if (f != f) { *high = 0; return 0; }            // nil/NaN-boxed: 0
    *high = f < 0.0f;
    if (p8) f = f * 65536.0f;
    f = floorf (f);
    if (f >= 2147483648.0f) {
        if (f >= 4294967296.0f) return 0xFFFFFFFFu;
        f = f - 4294967296.0f;
    } else if (f < -2147483648.0f) {
        if (f < -4294967296.0f) return 0x80000000u;
        f = f + 4294967296.0f;
    }
    return (uint32_t) (int32_t) f;
}

// Mirrors __bit_out
static double bit_out (uint32_t w, int high, bool p8)
{
    float s = (float) (int32_t) w;
    if (p8) return (double) (s * (1.0f / 65536.0f));
    int bit31 = (w & 0x80000000u) != 0;
    if (bit31 != high) s = bit31 ? s + 4294967296.0f : s - 4294967296.0f;
    return (double) s;
}

double bitop_eval (NodeType type, double a, double b)
{
    bool p8 = runtime_req.needs_pico8;
    int  op = (type == NODE_UNARY) ? BITOP_NOT : bitop_code (type);
    int  ha, hb;
    uint32_t x = bit_in (a, p8, &ha);

    if (op <= BITOP_NOT) {
        uint32_t y = (op == BITOP_NOT) ? 0 : bit_in (b, p8, &hb);
        switch (op) {
        case BITOP_AND: x &= y; ha &= hb; break;
        case BITOP_OR:  x |= y; ha |= hb; break;
        case BITOP_XOR: x ^= y; ha ^= hb; break;
        default:        x = ~x; ha = !ha; break;
        }
        return bit_out (x, ha, p8);
    }

    float nf = floorf ((float) b);
    if (nf != nf) nf = 0;
    if (nf > 64.0f) nf = 64.0f;
    if (nf < -64.0f) nf = -64.0f;
    int n = (int) nf;
    if (n < 0) {
        n = -n;
        if      (op == BITOP_SHL)  op = p8 ? BITOP_SAR : BITOP_SHR;
        else if (op == BITOP_SHR || op == BITOP_SAR) op = BITOP_SHL;
        else if (op == BITOP_ROTL) op = BITOP_ROTR;
        else                       op = BITOP_ROTL;
    }
    switch (op) {
    case BITOP_SHL:  x = (n >= 32) ? 0 : x << n; if (n >= 32) ha = 0; break;
    case BITOP_SHR:  if (n > 0) ha = 0; x = (n >= 32) ? 0 : x >> n; break;
    case BITOP_SAR:  x = (n >= 32) ? ((x & 0x80000000u) ? 0xFFFFFFFFu : 0)
                                   : (uint32_t) ((int32_t) x >> n); break;
    case BITOP_ROTL: n &= 31; if (n) x = (x << n) | (x >> (32 - n)); break;
    case BITOP_ROTR: n &= 31; if (n) x = (x >> n) | (x << (32 - n)); break;
    }
    return bit_out (x, ha, p8);
}

// Emits: push mode, op; evaluate operands; push a, b; CALL __builtin_bitop.
static void emit_bitop_call (int op, ASTNode *left, ASTNode *right, int dest_reg)
{
    runtime_req.needs_math = true;   // __builtin_bitop lives in math.s

    emit_asm ("MOV R%d, %d ; bitop mode: %s\n", dest_reg, runtime_req.needs_pico8 ? 1 : 0,
              runtime_req.needs_pico8 ? "PICO-8 16.16" : "integer");
    emit_asm ("PUSH R%d\n", dest_reg);
    emit_asm ("MOV R%d, %d ; bitop op\n", dest_reg, op);
    emit_asm ("PUSH R%d\n", dest_reg);

    generate_asm (left, dest_reg);
    ensure_in_register (dest_reg);

    if (right != NULL) {
        // spill the left operand across any nested CALL in the right one
        emit_asm ("PUSH R%d ; spill left operand\n", dest_reg);
        int right_reg = allocate_register ();
        mark_register_live (right_reg, 1);
        generate_asm (right, right_reg);
        ensure_in_register (right_reg);
        emit_asm ("POP R%d ; reload left operand\n", dest_reg);
        emit_asm ("PUSH R%d ; a\n", dest_reg);
        emit_asm ("PUSH R%d ; b\n", right_reg);
        unlock_register (right_reg);
    } else {
        emit_asm ("PUSH R%d ; a\n", dest_reg);
        emit_asm ("PUSH R%d ; b (unused)\n", dest_reg);
    }

    emit_asm ("CALL __builtin_bitop\n");
    emit_asm ("IADD SP, 4\n");
    if (dest_reg != 0) {
        emit_asm ("MOV R%d, R0\n", dest_reg);
    }
}

static void emit_folded (double v, int dest_reg)
{
    ASTNode *num = make_node (NODE_NUMBER);
    num->as.number.val = v;
    generate_asm (num, dest_reg);
    free (num);
}

void node_bitop (ASTNode *node, int dest_reg)
{
    ASTNode *l = node->as.binary.left, *r = node->as.binary.right;
    if (l->type == NODE_NUMBER && r->type == NODE_NUMBER) {
        emit_folded (bitop_eval (node->type, l->as.number.val, r->as.number.val), dest_reg);
        return;
    }
    emit_bitop_call (bitop_code (node->type), l, r, dest_reg);
}

void node_bnot (ASTNode *node, int dest_reg)
{
    ASTNode *operand = node->as.unary.operand;
    if (operand->type == NODE_NUMBER) {
        emit_folded (bitop_eval (NODE_UNARY, operand->as.number.val, 0), dest_reg);
        return;
    }
    emit_bitop_call (BITOP_NOT, operand, NULL, dest_reg);
}
