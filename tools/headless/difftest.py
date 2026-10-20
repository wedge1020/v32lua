#!/usr/bin/env python3
# difftest.py test.lua [frames]  -- run under reference Lua 5.4 and v32lua,
# compare every global named R_*. Numbers compared as float32 (rel 1e-5).
import sys, subprocess, struct, os, re
T = os.path.dirname(os.path.abspath(__file__))
LUA = os.environ.get('LUA54', 'lua5.4')
test = sys.argv[1]; frames = sys.argv[2] if len(sys.argv) > 2 else '30'
src = open(test).read()
epi = r'''
main()
local keys = {}
for k, v in pairs(_G) do if type(k) == "string" and k:sub(1,2) == "R_" then keys[#keys+1] = k end end
table.sort(keys)
for _, k in ipairs(keys) do
  local v = _G[k]; local t = type(v)
  if t == "number" then print("CANON " .. k .. " num " .. string.format("%.9g", v))
  elseif t == "string" then print("CANON " .. k .. " str " .. v)
  elseif t == "boolean" then print("CANON " .. k .. " bool " .. tostring(v))
  else print("CANON " .. k .. " " .. t) end
end
'''
ref_src = re.sub(r'^--#.*$', '', src, flags=re.M)
open(test + '.ref.lua', 'w').write(ref_src + epi)
r = subprocess.run([LUA, test + '.ref.lua'], capture_output=True, text=True)
if r.returncode != 0:
    print("REFERENCE ERROR:", r.stderr.strip()); sys.exit(2)
ref = {}
for l in r.stdout.splitlines():
    if l.startswith('CANON '):
        p = l.split(' ', 3); ref[p[1]] = (p[2], p[3] if len(p) > 3 else '')
v = subprocess.run([T + '/runlua', test, '-f', frames, '-q', '-D'], capture_output=True, text=True)
got = {}; status = ''
for l in v.stdout.splitlines():
    if l.startswith('CANON R_'):
        p = l.split(' ', 3); got[p[1]] = (p[2], p[3] if len(p) > 3 else '')
    elif l.startswith(('STATUS', 'COMPILE FAIL', 'ASSEMBLE FAIL', 'TRAP', '[')) or 'rror' in l:
        status += l + '\n'
if 'COMPILE FAIL' in v.stdout or 'ASSEMBLE FAIL' in v.stdout:
    print(v.stdout); sys.exit(1)
def f32(x): return struct.unpack('f', struct.pack('f', x))[0]
bad = 0; names = sorted(set(ref) | set(got))
for n in names:
    a = ref.get(n, ('nil', '')); b = got.get(n, ('nil', ''))
    ok = a == b
    if not ok and a[0] == 'num' and b[0] == 'num':
        x, y = f32(float(a[1])), float(b[1])
        ok = (x == y) or abs(x - y) <= 1e-5 * max(abs(x), abs(y)) + 1e-6
    if not ok:
        bad += 1; print(f"MISMATCH {n}: lua={a[0]} {a[1]!r}  v32lua={b[0]} {b[1]!r}")
print(status.strip())
print(f"{len(names) - bad}/{len(names)} match")
