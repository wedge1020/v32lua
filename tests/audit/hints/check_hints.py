#!/usr/bin/env python3
# check_hints.py -- the ';@' lines v32lua writes for v32opt and for source-level
# debugging (doc/HINTS.md). Compiles a small program with -g and checks the
# assembly and FILE.asm.debug; with V32OPT set (path to v32opt) also checks that
# the optimized program still assembles and gives the same result.
#   ./check_hints.py            (needs bin/v32lua; for the V32OPT part, v32sim's v32orun and assemble, see tools/headless/oracle.py)
import os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..")
V32LUA = os.environ.get("V32LUA", os.path.join(ROOT, "bin", "v32lua"))
H = os.path.join(ROOT, "tools", "headless")
SRC = """function main()
local s = 0
local t = {}
for i = 1, 20 do t[i] = i * 2 end
for r = 1, 3 do
  for i = 1, 20 do s = s + t[i] % 7 end
end
result_number = s
end
"""
fails = 0
def check(name, ok, extra=""):
    global fails
    fails += not ok
    print("%-62s %s%s" % (name, "ok" if ok else "FAIL", "" if ok else "   " + str(extra)))

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)

d = tempfile.mkdtemp()
open(os.path.join(d, "h.lua"), "w").write(SRC)
r = run([V32LUA, "-g", "-w", "--no-build-scripts", "h.lua", "-o", "h.asm"], cwd=d)
asm = open(os.path.join(d, "h.asm")).read()
dbg = open(os.path.join(d, "h.asm.debug")).read().splitlines()

check("compiles", r.returncode == 0, r.stderr[-200:])
check("header: ;@hints 1 abi=caller-save lang=lua", re.search(r"^\s*;@hints 1 abi=caller-save lang=lua$", asm, re.M) is not None)
check("numeric for: 3 ;@loop kind=for lines", len(re.findall(r"^\s*;@loop kind=for ", asm, re.M)) == 3)
check("for facts: stepval/from/to", re.search(r";@loop kind=for counter=-\d+ limit=-\d+ step=-\d+ var=-\d+ stepval=1 from=1 to=20$", asm, re.M) is not None)
check("each ;@loop is followed by its start label",
      all(re.search(r"^\s*;@loop[^\n]*\n__main_for_start_\d+:", asm, re.M) for _ in [0]) and
      len(re.findall(r"^\s*;@loop[^\n]*\n__main_for_start_\d+:", asm, re.M)) == 3)
check(";@cold precedes the table slow path label", re.search(r"^\s*;@cold\n__main_idx_slow_\d+:", asm, re.M) is not None)
check("main: ;@fn escapes=none (no LEA, no BP copy)", re.search(r";@fn __function_main escapes=none", asm) is not None)
check("main: ;@fn returns=0 (no return, no values)", re.search(r";@fn __function_main returns=0$", asm, re.M) is not None)
# returns=N: the most values any return produces; none for a function that forwards a call's values or `...`
RSRC = """function one(a) return a + 1 end
function two(a) return a, a end
function fwd(a) return two(a) end
function va(...) return ... end
function br(a) if a then return 1 else return end end
function main() local x, y = fwd(1) result_number = one(x) + y + br(true) end
"""
open(os.path.join(d, "r.lua"), "w").write(RSRC)
rr = run([V32LUA, "-w", "--no-build-scripts", "r.lua", "-o", "r.asm"], cwd=d)
rasm = open(os.path.join(d, "r.asm")).read() if rr.returncode == 0 else ""
rv = dict(re.findall(r"^\s*;@fn __function_(\w+) returns=(\d+)$", rasm, re.M))
check("returns=: one 1, two 2, br 1, main 0", (rv.get("one"), rv.get("two"), rv.get("br"), rv.get("main")) == ("1", "2", "1", "0"), rv)
check("returns=: none for `return f()` and `return ...`", "fwd" not in rv and "va" not in rv, rv)
check(";@cold { } regions are balanced and inline", len(re.findall(r"^\s*;@cold \{$", asm, re.M)) == len(re.findall(r"^\s*;@cold \}$", asm, re.M)) >= 1)
cl = dict(re.findall(r"^\s*;@fn (\w+) clobbers=(\S+)$", asm, re.M))
check("runtime: ;@fn LABEL clobbers= for helpers in the output", len(cl) > 20, len(cl))
check("runtime: only for labels the output defines",
      all(re.search(r"^" + k + ":", asm, re.M) for k in cl))
check("runtime: __arith_coerce clobbers=R0 (carries its own saves)", cl.get("__arith_coerce") == "R0", cl.get("__arith_coerce"))
check("runtime: each hint sits directly above its label",
      all(re.search(r";@fn " + k + r" clobbers=\S+\n" + k + ":", asm) for k in cl))
lines = [int(x) for x in re.findall(r"^;@src h\.lua:(\d+)$", asm, re.M)]
check(";@src markers present, only Lua lines 1..9", lines and min(lines) >= 1 and max(lines) <= 9, lines[:5])
check(";@src - ends the program before the runtime", ";@src -" in asm)
# the side file: lines of the Lua program, 'main' named, asm lines point at instructions
ok = len(dbg) > 5
al = asm.splitlines()
for e in dbg:
    f = e.split(",")
    n = int(f[1]); ln = int(f[3])
    if not (1 <= ln <= 9) or not re.match(r"^\s+[A-Z]", al[n - 1]): ok = False; check("map entry " + e, False, al[n - 1]); break
check("FILE.asm.debug: entries point at instructions of lines 1-9", ok)
check("FILE.asm.debug: names main", any(e.endswith(",main") for e in dbg))
seen = [int(e.split(",")[3]) for e in dbg]
check("stepping order covers lines 2,3,4,5,6,8 (line 7 is an `end`)", all(x in seen for x in (2, 3, 4, 5, 6, 8)), seen)
# a negative literal step is a constant: `-1` is folded, so the loop gets stepval=-1 and the short header
NEG = "function main()\nlocal s, x = 0, 3\nfor i = 10, 1, -1 do s = s + i end\nfor i = -2, 2 do s = s + i end\nfor i = x, 1, -x do s = s + i end\nresult_number = s + -0\nend\n"
open(os.path.join(d, "n.lua"), "w").write(NEG)
run([V32LUA, "-g", "-w", "--no-build-scripts", "n.lua", "-o", "n.asm"], cwd=d)
nasm = open(os.path.join(d, "n.asm")).read()
check("negative step: ;@loop ... stepval=-1 from=10 to=1", re.search(r";@loop kind=for counter=-\d+ limit=-\d+ step=-\d+(?: var=-\d+)? stepval=-1 from=10 to=1$", nasm, re.M) is not None)
check("negative limit/start: from=-2 to=2", re.search(r";@loop kind=for [^\n]*stepval=1 from=-2 to=2$", nasm, re.M) is not None)
check("a variable step has no stepval", re.search(r";@loop kind=for counter=-\d+ limit=-\d+ step=-\d+(?: var=-\d+)?$", nasm, re.M) is not None)
check("negative step: short header, exit when control < limit", "FLT" in nasm and nasm.count("__main_for_pos_") == 2 * 1 and "Check if control < limit (exit condition)" in nasm)
check("-<literal> is not a __builtin_unm call (only -x is)", nasm.count("CALL  __builtin_unm") == 1, nasm.count("CALL  __builtin_unm"))
check("-0 keeps its sign bit as a constant", re.search(r"MOV\s+R\d+, 0x80000000 ; -0$", nasm, re.M) is not None)
# debug info for locals: ;@var and balanced ;@scope per function
vars_ = re.findall(r"^\s*;@var (\w+) loc=BP([-+]\d+) type=lua", asm, re.M)
check(";@var: locals s, t, i, r with frame slots", {"s", "t", "i", "r"} <= {v[0] for v in vars_}, vars_)
check(";@var: no compiler temporaries (__limit_N ...)", not any(v[0].startswith("__") for v in vars_))
check(";@scope { } balanced", len(re.findall(r"^\s*;@scope \{$", asm, re.M)) == len(re.findall(r"^\s*;@scope \}$", asm, re.M)) >= 1)
# main chunk: block locals (BP slots) get ;@var / ;@scope too; chunk-level locals are RAM words (global ';@var loc=@ADDR', below)
CHUNK = "local top = 1\nfor i = 1, 2 do local sq = i end\ndo local x, y = 1, 2 end\nfunction main() end\n"
open(os.path.join(d, "c.lua"), "w").write(CHUNK)
r = run([V32LUA, "-g", "-w", "--no-build-scripts", "c.lua", "-o", "c.asm"], cwd=d)
casm = open(os.path.join(d, "c.asm")).read()
init = casm.split("__global_scope_initialization:")[1].split("\n    RET")[0]
cv = {v for v in re.findall(r"^\s*;@var (\w+) loc=BP", init, re.M)}
check("main chunk: ;@var for block locals i, sq, x, y", {"i", "sq", "x", "y"} <= cv, cv)
check("main chunk: no ;@var for the RAM local 'top'", "top" not in cv)
check("main chunk: ;@scope { } balanced and >= 2", len(re.findall(r"^\s*;@scope \{$", init, re.M)) == len(re.findall(r"^\s*;@scope \}$", init, re.M)) >= 2)
# var=N: the frame word of the visible loop variable, only when nothing else can write it
VARSRC = ("local f\nfunction v(...)\nfor i = 1, 3 do end\nend\nfunction main()\nlocal s = 0\n"
          "for i = 1, 3 do s = s + i end\n"                                  # 1: var
          "for i = 1, 3 do i = i + 1; s = s + i end\n"                       # 2: assigned
          "for i = 1, 3 do if s > 0 then do i = 0 end end end\n"             # 3: assigned in a nested block
          "for k = 1, 3 do f = function() return k end end\n"                # 4: captured by a closure (boxing is by name: not `i`)
          "for i = 1, 3 do for i = 1, 2 do s = s + i end end\n"              # 5: outer shadowed (none), inner var
          "for i = 1, 3 do __asm__(\"NOP\") end\n"                            # 6: inline assembly
          "for i = 1, 3 do local i = 7; s = s + i end\n"                     # 7: shadowed by a local
          "for i = 1, 3 do local g = function(i) return i end; s = s + g(i) end\nend\n")   # 8: a parameter of that name is not ours: var
open(os.path.join(d, "v.lua"), "w").write(VARSRC)
run([V32LUA, "-g", "-w", "--no-build-scripts", "v.lua", "-o", "v.asm"], cwd=d)
vasm = open(os.path.join(d, "v.asm")).read()
vl = re.findall(r"^\s*;@loop kind=for ([^\n]*)$", vasm, re.M)
vv = [bool(re.search(r" var=-\d+", x)) for x in vl]
check("var=: variadic function none; then main's loops 1..8 = yes no no no (outer no, inner yes) no no yes",
      vv == [False, True, False, False, False, False, True, False, False, True], vv)
check("var=: placed after step= and before stepval=", all(re.search(r"step=-\d+ var=-\d+( stepval|$)", x) for x in vl if "var=" in x), vl)
check("var=: names the word the loop stores the variable in (init local 'i' just before the hint)",
      all(re.search(r"MOV\s+\[BP - " + re.search(r"var=-(\d+)", x).group(1) + r"\], R\d+ ; init local 'i'\n\s*;@loop kind=for " + re.escape(x) + "$", vasm, re.M)
         for x in vl if "var=" in x))
def only_copy_writes(text):
    # between a loop's start and end label, the only store to its var= word is the per-iteration copy
    lines = text.split("\n"); ok = True
    for n, l in enumerate(lines):
        m = re.match(r"\s*;@loop kind=for .* var=-(\d+)", l)
        if not m: continue
        end = lines[n + 1].strip().replace("_start_", "_end_")
        k = n + 2; stores = 0
        while lines[k].strip() != end:
            if re.match(r"\s*\w+\s+\[BP - %s\]," % m.group(1), lines[k]): stores += 1
            k += 1
        ok = ok and stores == 1
    return ok
check("var=: the only store to the word inside the loop is the per-iteration copy", only_copy_writes(vasm))
# a numeric `for` value that is not provably a number is checked once, before the ;@loop line; literals are not
FCHK = ("local g = 4\nfunction main()\nlocal s, n = 0, g\nfor i = 1, 10 do s = s + i end\nfor i = 10, 1, -1 do s = s + i end\n"
        "for i = 1, n do s = s + i end\nfor i = g, 9, g do s = s + i end\nend\n")
open(os.path.join(d, "fc.lua"), "w").write(FCHK)
run([V32LUA, "-g", "-w", "--no-build-scripts", "fc.lua", "-o", "fc.asm"], cwd=d)
fasm = open(os.path.join(d, "fc.asm")).read()
check("for check: limit, initial and step are each checked once (no check for literals)",
      [fasm.count("CALL  __for_number_" + k) for k in ("limit", "initial", "step")] == [1, 1, 1], fasm.count("__for_number_"))
check("for check: sits before the ;@loop line (the loop's shape is unchanged)",
      re.search(r"CALL  __for_number_limit\n(?:(?!;@loop)[^\n]*\n)*?\s*;@loop[^\n]*stepval=1\n", fasm) is not None)
check("for check: the first two loops (literals) have no check between their ;@loop lines",
      re.search(r";@loop[^\n]*from=1 to=10\n(?:(?!__for_number_)[^\n]*\n)*?[^\n]*;@loop[^\n]*from=10 to=1", fasm) is not None)
# globals and chunk-level locals: one ';@var NAME loc=@0xADDR type=lua global' each, before the code
check("globals: top (chunk-level local) and counter at the top of the program, with their RAM word",
      re.search(r"^;@var top loc=@0x[0-9A-F]{8} type=lua global$", casm, re.M) is not None)
UP = "counter = 5\nlocal function mk(start) local n = start; return function() n = n + 1; return n end end\nfunction main() counter = counter + mk(1)() end\n"
open(os.path.join(d, "u.lua"), "w").write(UP)
run([V32LUA, "-g", "-w", "--no-build-scripts", "u.lua", "-o", "u.asm"], cwd=d)
uasm = open(os.path.join(d, "u.asm")).read()
gl = re.findall(r"^;@var (\w+) loc=@0x([0-9A-F]{8}) type=lua global$", uasm, re.M)
check("globals: counter listed once", [g[0] for g in gl].count("counter") == 1, gl)
check("globals: the records come before the first function", uasm.index(";@var counter") < uasm.index("__function_main:"))
define = dict(re.findall(r"%define\s+var_(\w+)\s+0x([0-9A-F]{8})", uasm))
check("globals: loc= is the var_NAME address", all(define.get(n) == a for n, a in gl), (gl, define))
check("globals: functions and compiler names are not listed", not any(n.startswith("__") or n in ("mk", "main") for n, _ in gl), gl)
SH = "local function f(a) local sum = a + 1; sum = sum + 1; return sum end\nfunction main() local r = f(3); r = r + 1 end\n"
open(os.path.join(d, "sh.lua"), "w").write(SH)
run([V32LUA, "-g", "-w", "--no-build-scripts", "sh.lua", "-o", "sh.asm"], cwd=d)
shasm = open(os.path.join(d, "sh.asm")).read()
shg = re.findall(r"^;@var (\w+) loc=@0x[0-9A-F]{8} type=lua global$", shasm, re.M)
check("globals: a name only assigned inside a function that declares it local is not listed as a global", "sum" not in shg and "r" not in shg and "f" not in shg, shg)
check("upvalue: ';@var n loc=BP+N type=lua boxed upvalue' inside the closure",
      re.search(r"^\s*;@var n loc=BP\+2 type=lua boxed upvalue$", uasm, re.M) is not None)
check("upvalue: the creating function lists n as an ordinary boxed local",
      re.search(r"^\s*;@var n loc=BP-\d+ type=lua boxed$", uasm, re.M) is not None)
r = run([V32LUA, "-w", "--no-build-scripts", "u.lua", "-o", "u0.asm"], cwd=d)
check("without -g: no ';@var' at all", ";@var" not in open(os.path.join(d, "u0.asm")).read())
# side file: the function is on EVERY row; code outside any function is "__chunk"
mrows = [l.split(",") for l in open(os.path.join(d, "c.asm.debug")).read().splitlines()]
check("c.asm.debug: every row has 5 fields (function on every row)", mrows and all(len(x) == 5 for x in mrows), mrows[:3])
check("c.asm.debug: chunk rows are named __chunk, 'main' only for main's own", {x[4] for x in mrows} <= {"__chunk", "main"} and "__chunk" in {x[4] for x in mrows}, {x[4] for x in mrows})
check("h.asm.debug: every row has 5 fields", all(len(e.split(",")) == 5 for e in dbg), dbg[:3])
r = run([sys.executable, os.path.join(ROOT, "tools", "check_clobbers.py"), "--check"])
check("tools/check_clobbers.py --check: src/runtime_clobbers.h is current", r.returncode == 0, r.stdout[-300:] + r.stderr[-200:])
r = run([V32LUA, "--no-hints", "-w", "--no-build-scripts", "h.lua", "-o", "n.asm"], cwd=d)
check("--no-hints leaves no ;@ lines", ";@" not in open(os.path.join(d, "n.asm")).read())
strip = lambda t: "\n".join(l for l in t.splitlines() if ";@" not in l)
check("hints and markers are comments: same instructions as --no-hints",
      [l.split(";")[0].strip() for l in strip(asm).splitlines()] ==
      [l.split(";")[0].strip() for l in open(os.path.join(d, "n.asm")).read().splitlines()])

vo = os.environ.get("V32OPT")
if vo:
    sys.path.insert(0, H); import oracle; ORUN, ASM = oracle.find()     # v32sim's v32orun and the stock assembler
    run([vo, "h.asm", "-o", "ho.asm", "-O3", "-L", "lua"], cwd=d)
    for nm in ("h", "ho"):
        run([ASM, nm + ".asm", "-o", nm + ".vbin"], cwd=d)
    outs = [run([ORUN, os.path.join(d, nm + ".vbin"), "-f", "20", "-q", "-a", os.path.join(d, nm + ".asm"),
                 "-D"], cwd=d).stdout for nm in ("h", "ho")]
    outs = [re.findall(r"CANON result_number num (\S+)", o) for o in outs]
    check("v32opt -O3 -L lua: still assembles and gives the same result",
          os.path.exists(os.path.join(d, "ho.vbin")) and outs[0] != [] and outs[0] == outs[1], outs)
print("FAILED" if fails else "ALL PASS"); sys.exit(1 if fails else 0)
