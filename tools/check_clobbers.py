#!/usr/bin/env python3
"""check_clobbers.py -- which registers does each v32lua runtime routine change?

Reads the runtime assembly (src/runtime/*.s) and works out, for every routine the
compiler calls, the set of registers R0..R13 it (and everything it calls) may leave
different from what the caller had. That set is what `;@fn LABEL clobbers=...` tells
v32opt, so it must be right: a register missing from it is a miscompile in the
optimizer's output. It is therefore computed, not trusted from the comments.

  tools/check_clobbers.py                 print the table and compare it with the doc comments
  tools/check_clobbers.py --write         write src/runtime_clobbers.h (the table the compiler uses)
  tools/check_clobbers.py --check         fail if src/runtime_clobbers.h is out of date (make test)
  tools/check_clobbers.py -v LABEL ...    show why a routine has no entry / what it clobbers

How. Each routine is walked instruction by instruction over its control-flow graph
(forward dataflow, states joined at labels). The state is: for each register, "still
holds the caller's value" or not; and the stack of what was PUSHed since the entry
("the caller's R3", or "something else"). A register is written by an instruction that
has it as destination (MOV, IN, LEA, POP, arithmetic, comparisons -- they leave a
boolean in the destination --, conversions...), by MOVS/SETS/CMPS (R0-R2 too), and by a
CALL to a routine that clobbers it. `PUSH R3` ... `POP R3` restores R3 when what is
popped is the caller's R3: that is the "saves every register it touches" pattern.
At every RET the registers that do not hold the caller's value are the routine's
clobbers. A routine is left out (no hint, the optimizer assumes the worst) when the
walk cannot follow it: an indirect jump or call, a stack that is not balanced at RET
(closures return with JMP R7 after dropping upvalues), a stack-pointer write other than
PUSH/POP/IADD SP/ISUB SP/MOV SP,BP, differing stack shapes at a join, or a call to
something that is not in the runtime.

What it does not see: a store that overwrites the stack slot of a saved register
between its PUSH and POP. No routine does that; the test suite (testing/) would not
catch it, so it is stated here.
"""
import glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
RUNTIME = sorted(glob.glob(os.path.join(ROOT, "src", "runtime", "*.s")))
TABLE_H = os.path.join(ROOT, "src", "runtime_clobbers.h")

NREG = 14                       # R0..R13; R14 = BP, R15 = SP
CLASS = {}
for n in "ISGN IABS FSGN FABS FLR CEIL ROUND SIN ACOS LOG CIF CFI CIB CFB NOT BNOT POP CMPS".split(): CLASS[n] = "W1"
for n in ("IEQ INE IGT IGE ILT ILE FEQ FNE FGT FGE FLT FLE AND OR XOR SHL IADD ISUB IMUL IDIV IMOD "
          "IMIN IMAX FADD FSUB FMUL FDIV FMOD FMIN FMAX ATAN2 POW MOV LEA IN").split(): CLASS[n] = "W1"
for n in "PUSH OUT HLT WAIT RET JMP CALL JT JF MOVS SETS".split(): CLASS[n] = n
OPCODES = set(CLASS)

class Unanalyzable(Exception): pass

def reg_index(tok):
    m = re.fullmatch(r"R(\d+)", tok.strip(), re.I)
    return int(m.group(1)) if m else None

def split_ops(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "[": depth += 1
        if ch == "]": depth -= 1
        if ch == "," and depth == 0: out.append(cur.strip()); cur = ""
        else: cur += ch
    if cur.strip(): out.append(cur.strip())
    return out

def parse(files):
    """-> instrs [(op, ops, file, line)], labels {name: index}, doc {label: comment text}"""
    instrs, labels, doc = [], {}, {}
    for f in files:
        pending = []
        for n, raw in enumerate(open(f, errors="replace").read().splitlines(), 1):
            code = raw.split(";")[0] if not raw.lstrip().startswith("string") else ""
            if raw.lstrip().startswith(";;"): pending.append(raw.strip(";").strip()); continue
            line = code.strip()
            if not line: continue
            while True:
                m = re.match(r"^([A-Za-z_.$][\w.$]*):\s*(.*)$", line)
                if not m: break
                labels[m.group(1)] = len(instrs)
                doc[m.group(1)] = " ".join(pending); pending = []
                line = m.group(2)
            if not line or line.startswith("%"): pending = []; continue
            parts = line.split(None, 1)
            op = parts[0].upper()
            if op in OPCODES:
                instrs.append((op, split_ops(parts[1]) if len(parts) > 1 else [], os.path.basename(f), n))
            pending = []
    return instrs, labels, doc

def call_targets(instrs, extra):
    t = set(extra)
    for op, ops, _, _ in instrs:
        if op == "CALL" and ops and re.fullmatch(r"[A-Za-z_][\w]*", ops[0]) and reg_index(ops[0]) is None:
            t.add(ops[0])
    return t

def compiler_calls():
    """labels the compiler's own code calls: CALL __name in src/**/*.c strings"""
    names = set()
    for f in glob.glob(os.path.join(ROOT, "src", "**", "*.c"), recursive=True):
        for m in re.finditer(r'CALL\s+(__\w+)', open(f, errors="replace").read()):
            names.add(m.group(1))
    return names

def written(op, ops):
    """registers an instruction writes (not counting CALL)"""
    w = set()
    if op in ("MOVS", "SETS"): return {0, 1, 2}
    if CLASS.get(op) == "W1" and ops:
        r = reg_index(ops[0])
        if r is not None: w.add(r)
        if op == "CMPS": w |= {0, 1, 2}
    return w

class State:
    __slots__ = ("orig", "stack", "bp")
    def __init__(s, orig, stack, bp): s.orig, s.stack, s.bp = orig, stack, bp
    def key(s): return (s.orig, s.stack, s.bp)

def join(a, b):
    if len(a.stack) != len(b.stack): raise Unanalyzable("stack depth differs at a join")
    if a.bp != b.bp: raise Unanalyzable("frame pointer depth differs at a join")
    orig = tuple(x and y for x, y in zip(a.orig, b.orig))
    stack = tuple(x if x == y else "?" for x, y in zip(a.stack, b.stack))
    return State(orig, stack, a.bp)

def can_return(entry, instrs, labels, entries):
    """instruction indices from which a RET (or a tail call) can be reached. A CALL on a
    path that only leads to HLT (an error handler that prints and stops) never gives
    control back to the caller's caller, so what it clobbers does not matter."""
    succ, seen, work = {}, set(), [labels[entry]]
    while work:
        i = work.pop()
        if i in seen or i >= len(instrs): continue
        seen.add(i)
        op, ops, _, _ = instrs[i]
        if op in ("RET", "HLT"): succ[i] = []
        elif op == "JMP":
            t = ops[0]
            succ[i] = [labels[t]] if t in labels and not (t in entries and t != entry) else []
        elif op in ("JT", "JF"):
            t = ops[1]
            succ[i] = [i + 1] + ([labels[t]] if t in labels else [])
        else: succ[i] = [i + 1]
        work.extend(succ[i])
    good = {i for i in seen if instrs[i][0] == "RET" or
            (instrs[i][0] == "JMP" and instrs[i][1][0] in entries and instrs[i][1][0] != entry)}
    changed = True
    while changed:
        changed = False
        for i, ss in succ.items():
            if i not in good and any(j in good for j in ss): good.add(i); changed = True
    return good

ALL = frozenset(range(NREG))

def analyze(entry, instrs, labels, summaries, entries):
    """-> frozenset of clobbered registers; raises Unanalyzable"""
    start = labels[entry]
    returns = can_return(entry, instrs, labels, entries)
    st0 = State((True,) * NREG + (True,), (), None)       # index NREG = BP
    states, work = {start: st0}, [start]
    clob_calls = set()
    ret_states = []
    steps = 0
    while work:
        steps += 1
        if steps > 200000: raise Unanalyzable("too many steps")
        i = work.pop()
        st = states[i]
        if i >= len(instrs): raise Unanalyzable("falls off the end")
        op, ops, fil, ln = instrs[i]
        where = "%s:%d" % (fil, ln)
        orig, stack, bp = list(st.orig), list(st.stack), st.bp
        succ = [i + 1]

        def other_sp(): raise Unanalyzable("%s: stack pointer changed by %s %s" % (where, op, ",".join(ops)))
        dst = ops[0].upper() if ops else ""
        if op == "PUSH":
            r = reg_index(ops[0])
            if r is not None: stack.append("R%d" % r if orig[r] else "?")
            elif dst == "BP": stack.append("BP" if orig[NREG] else "?")
            else: stack.append("?")
        elif op == "POP":
            if not stack: raise Unanalyzable("%s: POP below the entry stack" % where)
            tag = stack.pop()
            r = reg_index(ops[0])
            if r is not None: orig[r] = (tag == "R%d" % r)
            elif dst == "BP": orig[NREG] = (tag == "BP")
            else: other_sp()
        elif op in ("IADD", "ISUB") and dst == "SP":
            m = re.fullmatch(r"-?\d+", ops[1].strip())
            if not m: other_sp()
            k = int(ops[1]) * (1 if op == "ISUB" else -1)
            if k >= 0: stack.extend(["?"] * k)
            else:
                if -k > len(stack): raise Unanalyzable("%s: drops more than it pushed" % where)
                del stack[len(stack) + k:]
        elif op == "MOV" and dst == "BP" and ops[1].strip().upper() == "SP":
            bp = len(stack); orig[NREG] = False
        elif op == "MOV" and dst == "SP" and ops[1].strip().upper() == "BP":
            if bp is None: raise Unanalyzable("%s: MOV SP,BP without a frame" % where)
            del stack[bp:]
        elif dst == "SP" or dst in ("IP", "IR", "IV"):
            other_sp()
        elif op == "MOV" and dst == "BP":
            other_sp()
        elif op == "CALL":
            tgt = ops[0]
            if reg_index(tgt) is not None or tgt.startswith("["): raise Unanalyzable("%s: indirect call" % where)
            if tgt not in summaries:
                if i in returns: raise Unanalyzable("%s: calls %s, not analysed" % (where, tgt))
                s = ALL
            else:
                s = summaries[tgt]
            # a callee that cannot be analysed is taken to clobber everything -- but only
            # matters on a path that comes back (an error path that halts does not)
            for r in s:
                if i in returns or s != ALL: orig[r] = False
        elif op == "JMP":
            tgt = ops[0]
            if reg_index(tgt) is not None or tgt.startswith("["): raise Unanalyzable("%s: indirect jump" % where)
            if tgt not in labels: raise Unanalyzable("%s: jumps to unknown %s" % (where, tgt))
            if tgt in entries and tgt != entry:             # tail call
                for r in summaries.get(tgt, ()): orig[r] = False
                ret_states.append(State(tuple(orig), tuple(stack), bp)); succ = []
            else:
                succ = [labels[tgt]]
        elif op in ("JT", "JF"):
            tgt = ops[1]
            if tgt not in labels: raise Unanalyzable("%s: jumps to unknown %s" % (where, tgt))
            if tgt in entries and tgt != entry:
                raise Unanalyzable("%s: conditional tail call to %s" % (where, tgt))
            succ = [i + 1, labels[tgt]]
        elif op == "RET":
            ret_states.append(State(tuple(orig), tuple(stack), bp)); succ = []
        elif op == "HLT":
            succ = []
        else:
            for r in written(op, ops): orig[r] = False
        ns = State(tuple(orig), tuple(stack), bp)
        for j in succ:
            if j in states:
                m = join(states[j], ns)
                if m.key() != states[j].key(): states[j] = m; work.append(j)
            else:
                states[j] = ns; work.append(j)
    if not ret_states: raise Unanalyzable("never returns")
    clob = set()
    for rs in ret_states:
        if rs.stack: raise Unanalyzable("returns with %d words left on the stack" % len(rs.stack))
        if not rs.orig[NREG]: raise Unanalyzable("returns without restoring BP")
        clob |= {r for r in range(NREG) if not rs.orig[r]}
    return frozenset(clob)

def solve(files=RUNTIME, extra=()):
    instrs, labels, doc = parse(files)
    entries = call_targets(instrs, set(extra) | compiler_calls())
    entries = {e for e in entries if e in labels}
    # internal CALL targets that are not labels of the runtime stay un-analysed
    summaries = {e: frozenset() for e in entries}
    why = {}
    for _ in range(40):
        changed = False
        for e in sorted(entries):
            try:
                s = analyze(e, instrs, labels, {k: v for k, v in summaries.items()}, entries)
                why.pop(e, None)
            except Unanalyzable as ex:
                s, why[e] = ALL, str(ex)
            s = frozenset(s | summaries.get(e, frozenset()))      # sets only grow: a fixpoint over recursion
            if s != summaries.get(e):
                summaries[e] = s; changed = True
        if not changed: break
    return summaries, why, doc, labels

def claims(doc):
    """what the comments above a routine say: ('preserves', {regs}) / ('clobbers', {regs}) / None"""
    d = doc or ""
    m = re.search(r"Clobbers?:?\s*(R\d+(?:\s*[-,]\s*R?\d+)*)", d)
    if m: return ("clobbers", expand(m.group(1)))
    m = re.search(r"Preserves?\s+(?:all\s+registers\s+except\s+)?(R\d+(?:\s*[-,]\s*R?\d+)*)", d)
    if m:
        regs = expand(m.group(1))
        return ("preserves", regs) if "except" not in d[m.start():m.end() + 1] else None
    return None

def expand(text):
    regs = set()
    for part in re.split(r"\s*,\s*", text.strip()):
        m = re.fullmatch(r"R?(\d+)\s*-\s*R?(\d+)", part.strip())
        if m: regs |= set(range(int(m.group(1)), int(m.group(2)) + 1))
        else:
            m = re.fullmatch(r"R?(\d+)", part.strip())
            if m: regs.add(int(m.group(1)))
    return regs

def fmt_regs(s):
    """{0,1,2,3,7} -> R0-R3,R7"""
    out, r = [], sorted(s)
    i = 0
    while i < len(r):
        j = i
        while j + 1 < len(r) and r[j + 1] == r[j] + 1: j += 1
        out.append("R%d" % r[i] if i == j else "R%d-R%d" % (r[i], r[j]))
        i = j + 1
    return ",".join(out) if out else "none"

def header(summaries):
    rows = ["    { \"%s\", \"%s\" }," % (k, fmt_regs(v)) for k, v in sorted(summaries.items()) if v != ALL]
    return ("// GENERATED by tools/check_clobbers.py --write; do not edit.\n"
            "// The registers each runtime routine (and everything it calls) may change, as worked out\n"
            "// from src/runtime/*.s. The compiler writes them as ';@fn LABEL clobbers=...' for v32opt.\n"
            "static const struct { const char *label; const char *regs; } runtime_clobbers[] = {\n"
            + "\n".join(rows) + "\n    { 0, 0 }\n};\n")

def main(argv):
    summaries, why, doc, labels = solve()
    if "--write" in argv:
        open(TABLE_H, "w").write(header(summaries)); print("wrote", TABLE_H, "(%d routines)" % sum(v != ALL for v in summaries.values())); return 0
    if "--check" in argv:
        cur = open(TABLE_H).read() if os.path.exists(TABLE_H) else ""
        if cur != header(summaries):
            print("src/runtime_clobbers.h is out of date: run tools/check_clobbers.py --write"); return 1
        print("src/runtime_clobbers.h is up to date"); return 0
    if "-v" in argv:
        for lab in argv[argv.index("-v") + 1:]:
            print(lab, "->", fmt_regs(summaries[lab]) if summaries.get(lab, ALL) != ALL else "no entry: " + why.get(lab, "unknown label or clobbers everything"))
        return 0
    bad = 0
    ok = [k for k, v in summaries.items() if v != ALL]
    print("%d routines analysed, %d left out" % (len(ok), len(summaries) - len(ok)))
    for k in sorted(summaries):
        v = summaries[k]
        if v == ALL: print("  %-44s no entry: %s" % (k, why.get(k, "clobbers every register"))); continue
        c = claims(doc.get(k))
        note = ""
        if c and c[0] == "preserves":
            wrong = sorted(v & c[1])
            if wrong: note = "   MISMATCH: comment says it preserves %s, analysis finds %s changed" % (fmt_regs(c[1]), fmt_regs(set(wrong))); bad += 1
        elif c and c[0] == "clobbers":
            extra = sorted(v - c[1])
            if extra: note = "   MISMATCH: comment says it clobbers %s, analysis also finds %s" % (fmt_regs(c[1]), fmt_regs(set(extra))); bad += 1
        print("  %-44s %s%s" % (k, fmt_regs(v), note))
    print("%d comment/analysis mismatches" % bad)
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
