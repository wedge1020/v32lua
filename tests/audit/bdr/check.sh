#!/bin/bash
# check.sh -- TIC-80 BDR(row): the palette entry the callback writes changes by
# screen row. Second build uses --bdr-step 4 (BDR on rows 0,4,8,...; the
# palette it set holds for the three rows after). Needs v32lua, assemble,
# packrom and v32shot in PATH; BIOS=path/to/StandardBios.v32 (frame 400).
set -e
cd "$(dirname "$0")"
: "${BIOS:=/home/claude/ext/v32sim-user/tools/oracle/bin/StandardBios.v32}"
t=$(mktemp -d)
for step in 1 4; do
  mkdir $t/$step; cp bdr.lua $t/$step/s.lua
  (cd $t/$step && v32lua --api tic80 --no-build-scripts --bdr-step $step s.lua -o s.asm >/dev/null \
    && assemble s.asm -o s.vbin -g program >/dev/null && packrom s.xml -o s.v32 >/dev/null \
    && v32shot "$BIOS" s.v32 /dev/null o 400 >/dev/null)
done
python3 -W ignore - $t/1/o400.ppm $t/4/o400.ppm <<'PY'
import sys
from PIL import Image
px = lambda im, x, y: im.getpixel((int(x * 2.625 + 1), int(y * 2.625 + 1)))
a = Image.open(sys.argv[1]).convert('RGB'); b = Image.open(sys.argv[2]).convert('RGB')
bad = []
for y in (0, 1, 2, 5, 10, 20, 31, 39):
    want = (y * 4, 255 if y % 2 else 0, 0)
    if px(a, 100, y) != want: bad.append(("step1", y, px(a, 100, y), want))
for y in (0, 1, 3, 4, 7, 8, 21, 39):          # step 4: BDR(y - y%4 + 4)
    g = y - y % 4
    want = (g * 4, 255 if g % 2 else 0, 0)
    if px(b, 100, y) != want: bad.append(("step4", y, px(b, 100, y), want))
if bad: print("FAIL", bad); sys.exit(1)
print("PASS: BDR per row (step 1) and every 4th row (step 4)")
PY
