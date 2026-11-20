#!/bin/bash
# check.sh -- TIC-80 rect()/rectb(): every one of the 240x136 TIC-80 pixels (sampled at
# the center of its screen area) against a model written independently here:
# filled / 1-pixel / border rectangles, clipping at all four edges, fractional
# arguments (truncated), zero and negative sizes (nothing).
set -e
cd "$(dirname "$0")"
: "${BIOS:=/home/claude/ext/v32sim-user/tools/oracle/bin/StandardBios.v32}"
t=$(mktemp -d)
cp rects.lua $t/s.lua
(cd $t && v32lua --api tic80 --no-build-scripts s.lua -o s.asm >/dev/null \
  && assemble s.asm -o s.vbin -g program >/dev/null && packrom s.xml -o s.v32 >/dev/null \
  && v32shot "$BIOS" s.v32 /dev/null o 400 >/dev/null)
python3 -W ignore - $t/o400.ppm <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
bg = (26, 28, 44)
W, H = 240, 136
m = [[0]*W for _ in range(H)]
def R(x, y, w, h):
    x, y, w, h = int(x), int(y), int(w), int(h)
    if w < 1 or h < 1: return
    for j in range(max(y, 0), min(y+h, H)):
        for i in range(max(x, 0), min(x+w, W)): m[j][i] = 1
def B(x, y, w, h):
    x, y, w, h = int(x), int(y), int(w), int(h)
    if w < 1 or h < 1: return
    R(x, y, w, 1); R(x, y+h-1, w, 1); R(x, y, 1, h); R(x+w-1, y, 1, h)
R(10,10,20,12); R(40,10,1,30); R(50,10,30,1); R(0,0,3,3); R(237,133,3,3)
R(-5,50,12,8); R(232,50,20,8); R(100,-4,8,10); R(100,130,8,20); R(-10,-10,400,3)
R(120.7,60.9,5.9,4.2); R(150,60,0,5); R(155,60,5,-3)
B(10,70,30,20); B(50,70,1,10); B(60,70,2,2); B(70,70,3,3); B(-6,100,20,10); B(220,100,30,10); B(100,95,40,30)
S = 2.625
bad = []
for j in range(H):
    for i in range(W):
        p = im.getpixel((int((i+0.5)*S), int((j+0.5)*S)))
        got = 0 if p == bg else 1
        if got != m[j][i]: bad.append((i, j, m[j][i], got))
n = sum(map(sum, m))
if bad:
    print('FAIL: %d of %d pixels differ, first %s' % (len(bad), W*H, bad[:6])); sys.exit(1)
print('PASS: %d pixels checked, %d covered' % (W*H, n))
PY
