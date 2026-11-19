#!/bin/bash
# compare.sh -- native tri() (__builtin_tic80_tri) against the Lua reference
# (tri_reference.lua, the former prelude). 150 random triangles (on screen,
# clipped, fractional, flat and vertical edges); the GPU draw logs must match
# line for line. Needs v32lua, assemble and v32orun in PATH.
set -e
cd "$(dirname "$0")"
t=$(mktemp -d)
{ echo "--#api tic80"; cat tri_reference.lua; sed 1d random_tris.lua; } > $t/lua.lua
cp random_tris.lua $t/native.lua
for n in lua native; do
  v32lua --api tic80 --no-build-scripts $t/$n.lua -o $t/$n.asm >/dev/null
  assemble $t/$n.asm -o $t/$n.vbin -g program >/dev/null
  v32orun -g -f 30 -q $t/$n.vbin | grep GPU | sed 's/^F[0-9]* //' > $t/$n.log
done
if cmp -s $t/lua.log $t/native.log; then echo "PASS: $(wc -l < $t/native.log) draws identical"; else echo FAIL; diff $t/lua.log $t/native.log | head; exit 1; fi
