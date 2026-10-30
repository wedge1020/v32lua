#!/usr/bin/env python3
# v32srcmark -- give the stock Vircon32 C compiler's output the same source
# markers v32lua / v32cc write, WITHOUT touching the stock tools.
#
#   compile prog.c -o prog.asm -g         (stock compiler, unmodified)
#   v32srcmark.py prog.asm                (this tool: reads prog.asm + prog.asm.debug)
#   v32opt prog.asm ... ; v32as prog.asm -g --map ...
#
# What it does
#   * Reads the compiler's own `-g` side file (FILE.asm.debug, entries
#     "asmfile,asmline,srcfile,srcline[,function]").
#   * Repairs the entries. The stock compiler records an entry's asm line while it
#     is still emitting a function's body, and only afterwards puts the frame set-up
#     (`isub SP,n`, `push Rk`...) in front of that body, so every entry after the
#     first one in a function is early by exactly the number of those added lines
#     (minus one: the compiler's own bias). The tool counts them from the code
#     (the `pop Rk` after the `_return:` label match the `push Rk` of the prologue;
#     `isub SP,n` right after `mov BP, SP`) and moves the entries.
#   * Writes ';@src FILE:LINE' lines (comments to every assembler/optimizer) in front
#     of the instructions, `;@src -` after the last function, and a new, exact
#     FILE.asm.debug whose line numbers are those of the rewritten file.
#
# Options: -o OUT.asm (default: rewrite in place), --check (do not write; verify every
# repaired entry lands on an instruction and report), -v.
# Exit status 0 = done / consistent, 1 = an entry could not be placed, 2 = bad input.
import os, re, sys

def die(msg):
    sys.stderr.write("v32srcmark: %s\n" % msg); sys.exit(2)

def is_instr(line):
    s = line.strip().lower()
    return bool(s) and line[:1] in " \t" and not s.startswith(";") and not s.endswith(":") \
        and re.match(r"[a-z]", s) is not None and not re.match(r"(integer|float|string|datafile|defined)\b", s)

def functions(lines):
    """[(name, label_idx, end_idx, ins)] for __global_scope_initialization and every
    __function_NAME: block (0-based). ins = lines the compiler adds in front of the body
    after it has recorded the map entries: `isub SP, n` and `push Rk`, in either order."""
    out = []
    n = len(lines)
    for i, l in enumerate(lines):
        m = re.match(r"(__global_scope_initialization|__function_(\w+)):\s*$", l)
        if not m or (m.group(2) or "").endswith("_return"): continue
        name = m.group(2) or "__global_scope_initialization"
        j = i + 1
        while j < n and lines[j].strip().lower() != "ret":
            j += 1
        end = j
        ins = 0
        k = i + 1
        if k + 1 < n and lines[k].strip().lower() == "push bp" and lines[k + 1].strip().lower().replace(" ", "") == "movbp,sp":
            k += 2
            # saved registers are popped after the `_return:` label (an `iadd SP, n` may come first)
            pops = 0
            for q in range(i, end):
                if lines[q].strip() == "%s_return:" % ("__function_" + name if m.group(2) else name):
                    q += 1
                    while q < n and re.match(r"\s*(iadd\s+SP\s*,\s*\d+|pop\s+R\d+)\s*$", lines[q], re.I):
                        if lines[q].split()[0].lower() == "pop": pops += 1
                        q += 1
                    break
            pushes = 0
            while k < end and re.match(r"\s*(isub\s+SP\s*,\s*\d+|push\s+R\d+)\s*$", lines[k], re.I):
                if lines[k].split()[0].lower() == "push":
                    if pushes >= pops: break      # the body's own push, not a saved register
                    pushes += 1
                ins += 1; k += 1
        out.append((name, i, end, ins))
    return out

def main(argv):
    out = None; check = False; verbose = False; paths = []
    it = iter(argv)
    for a in it:
        if a == "-o": out = next(it)
        elif a == "--check": check = True
        elif a == "-v": verbose = True
        elif a.startswith("-"): die("unknown option " + a)
        else: paths.append(a)
    if len(paths) != 1: die("usage: v32srcmark.py [-o OUT.asm] [--check] [-v] FILE.asm   (needs FILE.asm.debug beside it)")
    asm_path = paths[0]
    try: lines = open(asm_path).read().split("\n")
    except OSError as e: die(str(e))
    dbg_path = asm_path + ".debug"
    try: raw = [l for l in open(dbg_path).read().splitlines() if l.strip()]
    except OSError: die(dbg_path + " not found (compile with -g)")
    if any(l.lstrip().startswith(";@src") for l in lines):
        die(asm_path + " already carries ';@src' markers")
    if lines and lines[-1] == "": lines.pop()

    funcs = functions(lines)
    entries = []                 # (asm line 1-based, srcfile, srcline, fname or None)
    for l in raw:
        f = l.split(",")
        if len(f) < 4: continue
        try: entries.append((int(f[1]), f[2], int(f[3]), f[4] if len(f) > 4 else None))
        except ValueError: continue
    placed = {}                  # 0-based asm line -> (srcfile, srcline)
    bad = 0
    cur = next((fn for fn in funcs if fn[0] == "__global_scope_initialization"), None)
    for (aline, sf, sl, fname) in entries:
        if fname is not None:
            cur = next((fn for fn in funcs if fn[0] == fname), None)
            target = aline - 1                     # the entry is the line after the label: `push BP`
            first = True
        else:
            first = False
            if cur is None: bad += 1; continue
            target = aline - 1 + cur[3] - 1 + 0    # early by the frame lines added, less the compiler's bias of one
        if target < 0 or target >= len(lines) or not is_instr(lines[target]):
            # a statement whose first line is a label (loop start etc.): take the next instruction
            t = target
            while 0 <= t < len(lines) and not is_instr(lines[t]) and t < target + 3: t += 1
            if t >= len(lines) or not is_instr(lines[t]):
                bad += 1
                if verbose: sys.stderr.write("  cannot place %s:%d (asm line %d -> %d)\n" % (sf, sl, aline, target + 1))
                continue
            target = t
        placed[target] = (sf, sl)      # two statements on one instruction (a label-only line): the later one
    if check:
        print("%d entries, %d placed, %d not" % (len(entries), len(placed), bad))
        return 1 if bad else 0

    # rewrite: markers before the placed instructions, `;@src -` after the last function
    funclabels = {fn[1] for fn in funcs}
    res = []
    last_end = max((fn[2] for fn in funcs), default=len(lines) - 1)
    for i, l in enumerate(lines):
        if i in placed and not (i > 0 and re.match(r"__function_\w+:\s*$", lines[i - 1]) and i - 1 in funclabels):
            res.append(";@src %s:%d" % placed[i])
        elif i in placed:
            res.insert(len(res) - 1, ";@src %s:%d" % placed[i])   # above the function label
        res.append(l)
        if i == last_end: res.append(";@src -")
    dst = out or asm_path
    open(dst, "w").write("\n".join(res) + "\n")

    # the exact map, same rules as v32lua's write_source_map
    src, src_line, func, last_func, last_line = "", 0, "", "", -1
    rows = []
    for n, l in enumerate(res, 1):
        p = l.lstrip()
        if p.startswith(";@src "):
            v = p[6:].strip()
            if v == "-": src_line = 0; last_line = -1; continue
            c = v.rfind(":"); src = v[:c]; src_line = int(v[c + 1:])
        elif re.match(r"__function_\w+:", p) and not re.match(r"__function_\w+_return:", p):
            func = p[11:p.index(":")]
        elif src_line > 0 and l[:1] in " \t" and is_instr(l):
            if src_line != last_line or func != last_func:
                rows.append("%s,%d,%s,%d%s" % (dst, n, src, src_line, ("," + func) if func != last_func else ""))
                last_line = src_line; last_func = func
    open(dst + ".debug", "w").write("\n".join(rows) + "\n")
    print("%s: %d source markers, %d map entries%s" % (dst, len(placed), len(rows), ("; %d entries could not be placed" % bad) if bad else ""))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
