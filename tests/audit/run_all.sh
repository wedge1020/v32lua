#!/bin/bash
# Runs the audit suite with the headless harness (tools/headless).
# Needs: bin/v32lua built, tools/headless/build.sh run once, and a
# reference Lua 5.4 as $LUA54 (default: lua5.4 on PATH).
cd "$(dirname "$0")"
H=../../tools/headless
echo "== core: v32lua vs reference Lua 5.4 (globals R_*)"
for t in *.lua; do case $t in *.ref.lua) continue;; esac; printf "%-14s %s\n" "$t" "$($H/difftest.py $t | tail -1)"; done
echo "== PICO-8 / TIC-80 smoke runs (expected values are in each file's comments;"
echo "   add -D to a runlua call to dump every global)"
for t in pico8/*.lua pico8/*.p8 tic80/*.lua; do
  printf "%-16s %s\n" "$t" "$($H/runlua $t -f 60 -q -p '0:Right=1;1:A=1' | grep -E 'FAIL|STATUS|TRAP' | head -1)"
done
# generated files (asm, vbin, logs, vsnd/vtex, reference copies) are removed
# unless KEEP=1
if [ -z "$KEEP" ]; then
  find . -type f ! -name "*.lua" ! -name "*.p8" ! -name "*.sh" ! -name "*.md" -delete
  find . -name "*.ref.lua" -delete
fi
