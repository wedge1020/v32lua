#!/bin/bash
# check.sh -- the base-color renderer (a row's majority color drawn as one run, the
# runs of it skipped) puts the same pixels on screen as the RAM image says: all
# 240x136 pixels of a dithered / noisy / banded image are compared with the palette
# colors computed independently here. Also prints the draw count.
set -e
cd "$(dirname "$0")"
: "${BIOS:=/home/claude/ext/v32sim-user/tools/oracle/bin/StandardBios.v32}"
t=$(mktemp -d)
cp base.lua $t/s.lua
(cd $t && v32lua --api tic80 --no-build-scripts s.lua -o s.asm >/dev/null \
  && assemble s.asm -o s.vbin -g program >/dev/null && packrom s.xml -o s.v32 >/dev/null \
  && v32shot "$BIOS" s.v32 /dev/null o 400 >/dev/null \
  && v32orun --bios "$BIOS" --cart s.v32 -f 420 -q -g 2>&1 | grep -c DrawZoomed > draws.txt) || true
python3 -W ignore - $t/o400.ppm $t/draws.txt <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
seed = 12345
def rnd():
    global seed
    seed = (seed * 75 + 74) % 65537
    return seed
def pick(y, x):
    if y < 34: return 3 if rnd() % 10 < 7 else 5
    if y < 68:
        r = rnd() % 5
        return 1 if r < 2 else (7 if r < 4 else 12)
    if y < 102: return 14 if rnd() % 12 == 0 else 9
    return (x // 30) % 16
pal = [((c * 16) % 256, (c * 37 + 11) % 256, (c * 91 + 50) % 256) for c in range(16)]
img = [[0] * 240 for _ in range(136)]
for y in range(136):
    for bx in range(120):
        img[y][2 * bx] = pick(y, 2 * bx)
        img[y][2 * bx + 1] = pick(y, 2 * bx + 1)
img[5][14], img[5][15] = 0xE, 0x2                # poke(120*5+7, 0x2E)
for k in range(10): img[6][100 + 2 * k], img[6][101 + 2 * k] = 5, 10   # memset 0xA5
runs = sum(1 + sum(1 for x in range(1, 240) if img[y][x] != img[y][x - 1]) for y in range(136))
bad = 0
for y in range(136):
    for x in range(240):
        got = im.getpixel((int((x + 0.5) * 2.625), int((y + 0.5) * 2.625)))
        if got != pal[img[y][x]]:
            bad += 1
            if bad <= 5: print("pixel", x, y, "got", got, "want", pal[img[y][x]])
draws = int(open(sys.argv[2]).read().strip() or 0)
print("%s: %d of %d pixels wrong; %d draws for %d runs" % ("FAIL" if bad else "PASS", bad, 240 * 136, draws, runs))
sys.exit(1 if bad else 0)
PY
