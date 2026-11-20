#!/bin/bash
# check.sh -- plain Vircon32 print(x, y, text) must draw whole strings at 10 px per
# glyph. Regression for the TIC-80 zoom flag in __bios_print_text: every program
# nil-initialises its globals (nil is not 0), so a plain `JF` on the flag sent every
# print down the zoomed path (one glyph, garbage advance). Counts the white pixels of
# "HELLO WORLD" + "1234" on a screenshot. Needs v32lua, assemble, packrom, v32shot.
set -e
cd "$(dirname "$0")"
: "${BIOS:=/home/claude/ext/v32sim-user/tools/oracle/bin/StandardBios.v32}"
t=$(mktemp -d)
cp pp.lua $t/s.lua
(cd $t && v32lua --no-build-scripts s.lua -o s.asm >/dev/null \
  && assemble s.asm -o s.vbin -g program >/dev/null && packrom s.xml -o s.v32 >/dev/null \
  && v32shot "$BIOS" s.v32 /dev/null o 300 >/dev/null)
python3 -W ignore - $t/o300.ppm <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
n = d.count(b'\xff')
print('white bytes', n)
# whole strings: ~1900 (a single glyph per string gives ~280)
sys.exit(0 if n > 1500 else 1)
PY
