#!/bin/sh
# Checks the cartridge XML v32lua writes (see "XML paths" in AGENTS.md):
#   usage: tests/xml/xml_paths.sh <v32lua binary>
# Default mode: bare names beside the -o file, subdirectories kept only to
# tell colliding assets apart, plus an Opt twin. --xml-preserve-paths: paths
# as written, XML in the source directory, <binary> relative to it. A PICO-8
# cart's generated assets are named correctly in both modes.
set -eu
bin=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
root=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
mkdir -p src obj
cp "$root/game.lua" src/game.lua

fail=0
expect() {   # expect FILE 'exact line'
    if ! grep -qxF -- "$2" "$1"; then
        echo "FAIL: $1 lacks: $2" >&2; sed 's/^/    | /' "$1" >&2; fail=1
    fi
}
reject() {   # reject FILE 'substring'
    if grep -qF -- "$2" "$1"; then echo "FAIL: $1 contains: $2" >&2; fail=1; fi
}

# ---- default mode
"$bin" -w --no-build-scripts -o obj/game.asm src/game.lua 2> warn.txt
[ -f obj/game.xml ] && [ -f obj/gameOpt.xml ] || { echo "FAIL: obj/game.xml or obj/gameOpt.xml missing" >&2; exit 1; }
[ ! -e src/game.xml ] || { echo "FAIL: default mode wrote src/game.xml" >&2; fail=1; }
expect obj/game.xml    '<binary path="game.vbin" />'
expect obj/gameOpt.xml '<binary path="gameOpt.vbin" />'
for f in obj/game.xml obj/gameOpt.xml; do
    expect $f '    <texture path="ship.vtex" /> <!-- SHIP -->'
    expect $f '    <texture path="extra/ship.vtex" /> <!-- SHIP2 -->'
    expect $f '    <sound path="vroom.vsnd" /> <!-- VROOM -->'
    reject $f 'textures/'
done
sed 's/Opt\.vbin/.vbin/; s/ \[optimized\]//' obj/gameOpt.xml | cmp -s - obj/game.xml || { echo "FAIL: Opt twin differs by more than <binary>" >&2; fail=1; }
grep -q "both become" warn.txt && { echo "FAIL: spurious collision warning" >&2; fail=1; }

# ---- preserve mode
rm -f obj/*
"$bin" -w --no-build-scripts --xml-preserve-paths -o obj/game.asm src/game.lua 2>/dev/null
[ -f src/game.xml ] && [ -f src/gameOpt.xml ] || { echo "FAIL: preserve mode did not write src/game.xml and src/gameOpt.xml" >&2; exit 1; }
expect src/game.xml    '<binary path="../obj/game.vbin" />'
expect src/gameOpt.xml '<binary path="../obj/gameOpt.vbin" />'
expect src/game.xml '    <texture path="textures/ship.vtex" /> <!-- SHIP -->'
expect src/game.xml '    <texture path="textures/extra/ship.vtex" /> <!-- SHIP2 -->'
expect src/game.xml '    <sound path="sounds/vroom.vsnd" /> <!-- VROOM -->'

# ---- a PICO-8 cart: compiler-made assets sit beside the output
rm -f obj/* src/*.xml
printf 'pico-8 cartridge // http://www.pico-8.com\nversion 8\n__lua__\nfunction _draw() cls() end\n__gfx__\n' > src/c.p8
"$bin" -w --no-build-scripts -o obj/my.cart.asm src/c.p8 2>/dev/null
expect obj/my.cart.xml '    <texture path="my.cart_pico8.vtex" /> <!-- pico8_spritesheet -->'
[ -f obj/my.cart_pico8.vtex ] || { echo "FAIL: obj/my.cart_pico8.vtex was not written" >&2; fail=1; }
"$bin" -w --no-build-scripts --xml-preserve-paths -o obj/my.cart.asm src/c.p8 2>/dev/null
expect src/my.cart.xml '    <texture path="../obj/my.cart_pico8.vtex" /> <!-- pico8_spritesheet -->'

[ $fail -eq 0 ] && echo "xml_paths: OK"
exit $fail
