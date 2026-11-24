#!/usr/bin/env python3
# panic_text.py -- the text of the numeric-for panic screen, read back from the GPU log.
#
# A `for` whose start, limit or step is not a number ends in __runtime_error_for, which prints a banner, the
# message ("'for' initial value must be a number", ...) and the value. The message is passed in R1, and
# __builtin_print overwrites R1, so until 20261124-dev the second line showed whatever print had left there.
# Each case is compiled, run headless (tools/headless/runlua ... -g) and the BIOS glyph draws of the message row
# (y = 20) are turned back into text and compared.
#
#   python3 tests/audit/panic_text.py            (V32LUA / V32ORUN / V32SIM_HOME as for runlua)
import os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
RUNLUA = os.path.join(HERE, '..', '..', 'tools', 'headless', 'runlua')
CASES = [
    ('initial', 'local s = "abc"\n  for i = s, 3 do end', "'FOR' INITIAL VALUE MUST BE A NUMBER"),
    ('limit',   'local s = {}\n  for i = 1, s do end',    "'FOR' LIMIT MUST BE A NUMBER"),
    ('step',    'local s = true\n  for i = 1, 3, s do end', "'FOR' STEP MUST BE A NUMBER"),
]

def row_text(gpu_lines, y):
    out = []
    for l in gpu_lines:
        m = re.search(r'DrawRegion tex=-1 reg=(\d+) pt=\((-?\d+),(-?\d+)\)', l)
        if m and int(m.group(3)) == y:
            c = int(m.group(1))
            out.append((int(m.group(2)), chr(c) if 32 <= c < 127 else '?'))
    return ''.join(c for _, c in sorted(out))

def main():
    fails = 0
    with tempfile.TemporaryDirectory() as tmp:
        for name, body, want in CASES:
            src = os.path.join(tmp, f'for_{name}.lua')
            with open(src, 'w') as f:
                f.write(f'function main()\n  {body}\nend\n')
            r = subprocess.run([RUNLUA, src, '-f', '3', '-g'], capture_output=True, text=True)
            got = row_text(r.stdout.splitlines(), 20)
            ok = want in got.upper()
            fails += not ok
            print(f"{'PASS' if ok else 'FAIL'}  for {name:8s} message row: {got!r}" + ('' if ok else f'  (want {want!r})'))
    print('panic_text: ' + ('all pass' if not fails else f'{fails} failed'))
    return 1 if fails else 0

if __name__ == '__main__':
    sys.exit(main())
