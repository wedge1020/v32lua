#!/usr/bin/env python3
# check_srcmark.py -- tools/v32srcmark.py on output of the UNMODIFIED stock Vircon32
# C compiler (canned: *.c, *.asm.in (the .asm) and *.asm.debug here came from `compile X.c -g`).
# Expected markers were checked against a compiler patched to write them itself (34 of
# the stock CCompiler/Tests programs agree); here they are spelled out.
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "..", "..", "tools", "v32srcmark.py")
fails = 0
def check(n, ok, extra=""):
    global fails; fails += not ok
    print("%-66s %s%s" % (n, "ok" if ok else "FAIL", "" if ok else "  " + str(extra)))
def mark(name):
    d = tempfile.mkdtemp()
    for e in (".c", ".asm.debug"): shutil.copy(os.path.join(HERE, name + e), d)
    shutil.copy(os.path.join(HERE, name + ".asm.in"), os.path.join(d, name + ".asm"))
    # the side file names its asm file
    p = os.path.join(d, name + ".asm.debug")
    txt = open(p).read().replace(name + ".asm", os.path.join(d, name + ".asm"))
    open(p, "w").write(txt)
    r = subprocess.run([sys.executable, TOOL, os.path.join(d, name + ".asm")], capture_output=True, text=True)
    asm = open(os.path.join(d, name + ".asm")).read().split("\n")
    pairs = []; m = None
    for l in asm:
        if l.startswith(";@src "): m = l[6:]
        elif re.match(r"^\s+[a-z]", l) and not re.match(r"^\s+(string|integer|float)", l):
            if m is not None and m != "-": pairs.append((m, l.strip()))
            m = None
    return r, asm, pairs, open(os.path.join(d, name + ".asm.debug")).read().splitlines()

r, asm, pairs, dbg = mark("sc")
check("sc: runs", r.returncode == 0, r.stderr)
want = [("sc.c:4", "mov R0, [BP+2]"), ("sc.c:5", "mov R0, [BP-1]"), ("sc.c:9", "mov R0, 0"),
        ("sc.c:11", "mov R1, [BP-1]"), ("sc.c:12", "mov R0, R0"), ("sc.c:16", "mov R0, [BP-1]")]
check("sc: statements after a prologue with isub+push sit on the right instruction",
      all(w in pairs for w in want), [w for w in want if w not in pairs])
check("sc: markers are comments and add only ';@src' lines",
      [l for l in asm if not l.startswith(";@src") and l != ""] == [l for l in open(os.path.join(HERE, "sc.asm.in")).read().split("\n") if l != ""])
check("sc: exact map names add and main", any(x.endswith(",sc.c,2,add") for x in dbg) and any(x.endswith(",sc.c,7,main") for x in dbg), dbg[:3])
i = {l: n for n, l in enumerate(asm, 1)}
ok = True
for x in dbg:
    f = x.split(","); n = int(f[1])
    if not re.match(r"^\s+[a-z]", asm[n - 1]): ok = False
check("sc: every map entry is an instruction line of the rewritten file", ok)
r, asm, pairs, dbg = mark("rec")
check("rec: push R1 before isub (other order): statement 3 on `mov R0, [BP+2]`", ("rec.c:3", "mov R0, [BP+2]") in pairs, pairs[:3])
r, asm, pairs, dbg = mark("goto")
check("goto: label-only lines share an instruction, the later line wins", ("goto.c:7", "mov R0, 1") in pairs and not any(p[0] == "goto.c:5" for p in pairs), pairs[:3])
print("FAILED" if fails else "ALL PASS"); sys.exit(1 if fails else 0)
