#!/bin/bash
# check.sh -- TIC-80 screen RAM drawing (poke / memset / memcpy into 0-0x3FBF
# with a palette poked at 0x3FC0), checked on a screenshot. Needs v32lua,
# assemble, packrom and v32shot in PATH; BIOS=path/to/StandardBios.v32 (the
# BIOS logo takes ~300 frames, so the shot is taken at frame 400).
set -e
cd "$(dirname "$0")"
: "${BIOS:=/home/claude/ext/v32sim-user/tools/oracle/bin/StandardBios.v32}"
t=$(mktemp -d)
cp screen_ram.lua $t/s.lua
(cd $t && v32lua --api tic80 --no-build-scripts s.lua -o s.asm >/dev/null \
  && assemble s.asm -o s.vbin -g program >/dev/null && packrom s.xml -o s.v32 >/dev/null \
  && v32shot "$BIOS" s.v32 /dev/null o 400 >/dev/null)
python3 -W ignore - $t/o400.ppm <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
px = lambda x, y: im.getpixel((int(x * 2.625 + 1), int(y * 2.625 + 1)))
R, G, B, Y, BG = (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0), (26, 28, 44)
want = [((5, 0), R), ((200, 9), R), ((5, 10), BG), ((20, 20), B), ((21, 20), G), ((22, 20), BG),
        ((10, 30), Y), ((119, 30), Y), ((120, 30), G), ((121, 30), R), ((10, 31), BG),
        ((50, 40), B), ((130, 40), BG), ((10, 60), BG)]
bad = [(p, px(*p), c) for p, c in want if px(*p) != c]
# the red block rows 0-9 must be solid (no one-pixel seams between runs)
seams = sum(1 for y in range(26) for x in range(630) if im.getpixel((x, y)) != R)
if bad or seams:
    print("FAIL", bad, "seams:", seams); sys.exit(1)
print("PASS: %d pixels, solid block" % len(want))
PY
