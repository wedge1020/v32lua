#!/usr/bin/env python3
# check_hints.py -- the ';@' lines v32lua writes for v32opt and for source-level
# debugging (doc/HINTS.md). Compiles a small program with -g and checks the
# assembly and FILE.asm.debug; with V32OPT set (path to v32opt) also checks that
# the optimized program still assembles and gives the same result.
#   ./check_hints.py            (needs bin/v32lua; tools/headless built)
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
check("for facts: stepval/from/to", re.search(r";@loop kind=for counter=-\d+ limit=-\d+ step=-\d+ stepval=1 from=1 to=20$", asm, re.M) is not None)
check("each ;@loop is followed by its start label",
      all(re.search(r"^\s*;@loop[^\n]*\n__main_for_start_\d+:", asm, re.M) for _ in [0]) and
      len(re.findall(r"^\s*;@loop[^\n]*\n__main_for_start_\d+:", asm, re.M)) == 3)
check(";@cold precedes the table slow path label", re.search(r"^\s*;@cold\n__main_idx_slow_\d+:", asm, re.M) is not None)
check("main: ;@fn escapes=none (no LEA, no BP copy)", re.search(r";@fn __function_main escapes=none", asm) is not None)
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
# debug info for locals: ;@var and balanced ;@scope per function
vars_ = re.findall(r"^\s*;@var (\w+) loc=BP([-+]\d+) type=lua", asm, re.M)
check(";@var: locals s, t, i, r with frame slots", {"s", "t", "i", "r"} <= {v[0] for v in vars_}, vars_)
check(";@var: no compiler temporaries (__limit_N ...)", not any(v[0].startswith("__") for v in vars_))
check(";@scope { } balanced", len(re.findall(r"^\s*;@scope \{$", asm, re.M)) == len(re.findall(r"^\s*;@scope \}$", asm, re.M)) >= 1)
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
    run([vo, "h.asm", "-o", "ho.asm", "-O3", "-L", "lua"], cwd=d)
    for nm in ("h", "ho"):
        run([os.path.join(H, "Assembler"), nm + ".asm", "-o", nm + ".vbin"], cwd=d)
    outs = [run([os.path.join(H, "v32run"), os.path.join(d, nm + ".vbin"), "-f", "20", "-q", "-a", os.path.join(d, nm + ".asm"),
                 "-D"], cwd=d).stdout for nm in ("h", "ho")]
    outs = [re.findall(r"CANON result_number num (\S+)", o) for o in outs]
    check("v32opt -O3 -L lua: still assembles and gives the same result",
          os.path.exists(os.path.join(d, "ho.vbin")) and outs[0] != [] and outs[0] == outs[1], outs)
print("FAILED" if fails else "ALL PASS"); sys.exit(1 if fails else 0)
