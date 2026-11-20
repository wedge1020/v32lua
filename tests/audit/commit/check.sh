#!/bin/bash
# check.sh -- TIC-80 frame commit: the scene in cm.lua drawn with --tic80-commit must be
# pixel-identical to the same cart built without it, and not blank. Needs v32lua,
# assemble, packrom and v32shot in PATH.
set -e
cd "$(dirname "$0")"
: "${BIOS:=/home/claude/ext/v32sim-user/tools/oracle/bin/StandardBios.v32}"
t=$(mktemp -d)
cp cm.lua $t/s.lua
cd $t
for v in n c; do
  o=""; [ $v = c ] && o="--tic80-commit"
  v32lua --api tic80 --no-build-scripts $o s.lua -o $v.asm >/dev/null
  assemble $v.asm -o $v.vbin -g program >/dev/null && packrom $v.xml -o $v.v32 >/dev/null
  v32shot "$BIOS" $v.v32 /dev/null $v 400 >/dev/null
done
cmp -s n400.ppm c400.ppm || { echo "FAIL: commit screenshot differs"; exit 1; }
python3 -W ignore - n400.ppm <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
n = len(set(d[15:][i:i+3] for i in range(0, len(d) - 15, 3 * 11)))
print('distinct colors', n)
sys.exit(0 if n > 8 else 1)
PY
echo ok
