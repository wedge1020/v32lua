#!/usr/bin/env python3
# unittest.py file.lua [file.lua ...]  -- run testing/ unit tests headless.
#
# Same contract as testing/run_tests.sh (v32sim): every global whose name is
# <type>_<...> (number_/string_/boolean_/hex_) is scraped after the cart
# halts and compared against the "=== EXPECTED OUTPUT ===" block.
# Formats mirror v32sim's d/f (%.4f), d/s ("..." with \xHH escapes),
# d/B (true/false) and d (0xXXXXXXXX).
#   -v   print each mismatch        -f N  default frame cap (30)
# Header directive (a line anywhere in the file):
#   --@ frames: N      frame cap for this file (wins over -f)
# A file may also (or only) carry a trap block, inside the --[[ ]] comment:
#   === EXPECTED TRAP ===
#   label: __arena_err_mark        (one or more labels, comma separated)
# The cart is run with --expect-reach LABEL and passes if it reaches one
# (counts as 1 test). If EXPECTED OUTPUT is present too, the globals are
# checked as well (the -D dump is printed after the label is reached).
# Unlike run_tests.sh the comparison is by NAME, not by line order, so one
# missing variable doesn't cascade into a run of false failures.
import sys, os, re, struct, subprocess
T = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]; verbose = False; frames = '30'
if '-v' in args: verbose = True; args.remove('-v')
if '-f' in args: i = args.index('-f'); frames = args[i + 1]; del args[i:i + 2]

def fmt(kind, raw, estr):
    u = int(raw, 16)
    if kind == 'number':
        f = struct.unpack('<f', struct.pack('<I', u))[0]
        return 'nan' if f != f else '%.4f' % f     # v32sim d/f shows nil as nan
    if kind == 'hex': return '0x%08X' % u
    if kind == 'boolean':
        return {0xFFC00001: 'false', 0xFFC00002: 'true', 0xFFC00000: 'nil'}.get(u, 'raw:0x%08X' % u)
    if kind == 'string':
        if u == 0xFFC00000: return 'nil'
        return '"%s"' % estr if estr is not None else 'raw:0x%08X' % u
    return raw

tot_pass = tot_all = 0
for test in args:
    src = open(test).read().splitlines()
    at = next((i for i, l in enumerate(src) if 'EXPECTED OUTPUT' in l), None)
    tat = next((i for i, l in enumerate(src) if '=== EXPECTED TRAP ===' in l), None)
    if at is None and tat is None: print(f"{test}: no EXPECTED OUTPUT block"); continue
    want = {}
    if at is not None:
        for l in src[at + 1:]:
            m = re.match(r'^\s*((number|string|boolean|hex)_\w+):\s?(.*?)\s*$', l)
            if m: want[m.group(1)] = (m.group(2), m.group(3))
    labels = []
    if tat is not None:
        for l in src[tat + 1:]:
            if l.strip().startswith(']]') or '=== EXPECTED' in l: break
            m = re.match(r'^\s*(?:--@\s*)?label:\s*(.+?)\s*$', l)
            if m: labels += [x.strip() for x in m.group(1).split(',') if x.strip()]
        if not labels: print(f"{test}: EXPECTED TRAP block has no 'label:' line"); continue
    fcap = frames
    for l in src:
        m = re.match(r'^\s*--@\s*frames:\s*(\d+)\s*$', l)
        if m: fcap = m.group(1)
    cmd = [T + '/runlua', test, '-f', fcap, '-q', '-D']
    if labels: cmd += ['--expect-reach', ','.join(labels)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    ntest = len(want) + (1 if labels else 0)
    out = r.stdout
    name = os.path.relpath(test)
    if 'COMPILE FAIL' in out or 'ASSEMBLE FAIL' in out:
        print(f"{name:48s} {'':9s} ... {out.splitlines()[0]}")
        if verbose: print('\n'.join(out.splitlines()[1:12]))
        tot_all += ntest; continue
    raw = {}; est = {}
    for l in out.splitlines():
        p = l.split(' ', 2)
        if p[0] == 'RAW': raw[p[1]] = p[2]
        elif p[0] == 'ESTR': est[p[1]] = p[2] if len(p) > 2 else ''
    trap = [l for l in out.splitlines() if l.startswith('TRAP') or 'HWERROR' in l or 'budget' in l]
    bad = []
    tok = 0; tmsg = ''
    if labels:
        reached = [l.split()[2] for l in out.splitlines() if l.startswith('EXPECT REACHED')]
        status = next((l for l in out.splitlines() if l.startswith('STATUS')), '')
        if reached: tok = 1; tmsg = 'reached ' + reached[0]
        elif any(l.startswith('EXPECT MISSED') for l in out.splitlines()):
            tmsg = 'missed ' + ','.join(labels) + (' (' + status + ')' if status else '')
        else:
            tmsg = 'no result: ' + (r.stderr.strip() or out).splitlines()[0] if (r.stderr.strip() or out.strip()) else 'no result'
        if not tok: bad.append(('<trap>', ','.join(labels), tmsg))
    for n, (kind, exp) in want.items():
        got = fmt(kind, raw[n], est.get(n, '')) if n in raw else '<missing>'
        if got != exp: bad.append((n, exp, got))
    ok = ntest - len(bad); tot_pass += ok; tot_all += ntest
    note = ('  ' + tmsg) if labels else ('  ' + trap[0] if trap else '')
    if labels and tok and trap: note = '  ' + tmsg
    print(f"{name:48s} ({ok:2d}/{ntest:2d}) ... {'PASS' if not bad else 'FAIL'}{note}")
    if verbose:
        for n, e, g in bad: print(f"      {n:24s} want {e:24s} got {g}")
print(f"TOTAL {tot_pass}/{tot_all}")
