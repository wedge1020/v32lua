#!/bin/bash
# check.sh -- TIC-80 print(text,x,y,color,fixed,scale,smallfont): checked on a screenshot.
# Bounding boxes of "HH" at scale 1 / 3 / small font, and the widths print() returns
# (drawn as rects). Needs v32lua, assemble, packrom and v32shot in PATH.
set -e
cd "$(dirname "$0")"
: "${BIOS:=/home/claude/ext/v32sim-user/tools/oracle/bin/StandardBios.v32}"
t=$(mktemp -d)
cp ps.lua $t/s.lua
(cd $t && v32lua --api tic80 --no-build-scripts s.lua -o s.asm >/dev/null \
  && assemble s.asm -o s.vbin -g program >/dev/null && packrom s.xml -o s.v32 >/dev/null \
  && v32shot "$BIOS" s.v32 /dev/null o 400 >/dev/null)
python3 -W ignore - $t/o400.ppm <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
S = 2.625
bg = (26, 28, 44)
def bbox(x0, y0, x1, y1, col=None):
    xs = []; ys = []
    for y in range(int(y0*S), int(y1*S)):
        for x in range(int(x0*S), int(x1*S)):
            p = im.getpixel((x, y))
            if (p == col) if col else (p != bg):
                xs.append(x); ys.append(y)
    return (min(xs), min(ys), max(xs), max(ys)) if xs else None
ok = True
def chk(name, cond, info):
    global ok
    print(('ok   ' if cond else 'FAIL ') + name + ' ' + str(info))
    ok &= bool(cond)
a = bbox(0, 5, 110, 30)      # scale 1
b = bbox(0, 36, 110, 100)    # scale 3
c = bbox(110, 5, 239, 30)    # small font
wa, ha = a[2]-a[0]+1, a[3]-a[1]+1
wb, hb = b[2]-b[0]+1, b[3]-b[1]+1
wc, hc = c[2]-c[0]+1, c[3]-c[1]+1
chk('scale1 left edge', abs(a[0]-20*S) <= 3, a[0])
chk('scale3 left edge', 0 <= b[0]-20*S <= 3*5, b[0])
chk('scale3/scale1 width', 2.7 < wb/wa < 3.3, (wa, wb))
chk('scale3/scale1 height', 2.7 < hb/ha < 3.3, (ha, hb))
# second H starts one advance (6 px * scale) after the first: total width = adv + glyph
chk('scale1 advance', 20 <= wa <= 32, wa)
chk('small font narrower than normal', wc < wa and hc < ha, (wc, wa, hc, ha))
# returned widths drawn as rects: 3 chars * 6 * 2 = 36 px; 4 chars * 4 = 16 px
r1 = bbox(0, 109, 239, 115)
r2 = bbox(0, 119, 239, 125)
print('rect boxes', r1, r2)
if r1: chk('width scale2', abs((r1[2]-r1[0]+1)/S - 36) <= 1.5, (r1[2]-r1[0]+1)/S)
else: chk('width scale2', False, None)
if r2: chk('width smallfont', abs((r2[2]-r2[0]+1)/S - 16) <= 1.5, (r2[2]-r2[0]+1)/S)
else: chk('width smallfont', False, None)
sys.exit(0 if ok else 1)
PY
