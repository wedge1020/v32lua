#!/bin/bash
# check.sh -- sync() banks from a binary .tic cartridge: the cart has map bank 0
# (cell 0,0 = 3) and bank 1 (= 9); its code syncs bank 1 and clears to color
# mget(0,0). The screenshot background must be palette color 9, not 3.
set -e
cd "$(dirname "$0")"
: "${BIOS:=/home/claude/ext/v32sim-user/tools/oracle/bin/StandardBios.v32}"
t=$(mktemp -d)
python3 make_tic.py $t/b.tic
(cd $t && v32lua --api tic80 --no-build-scripts b.tic -o b.asm >/dev/null \
  && assemble b.asm -o b.vbin -g program >/dev/null && packrom b.xml -o b.v32 >/dev/null \
  && v32shot "$BIOS" b.v32 /dev/null o 500 >/dev/null)
python3 -W ignore - $t/o500.ppm <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
got = im.getpixel((5, 5))
# TIC-80's default palette (Sweetie 16): index 9 = 3b5dc9, index 3 = ef7d57
if got == (0x3b, 0x5d, 0xc9): print("PASS: bank 1 synced, background", got)
else: print("FAIL: background", got, "(expected 3b5dc9; ef7d57 = bank 0)"); sys.exit(1)
PY
