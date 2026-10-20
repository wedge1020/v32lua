#!/bin/sh
# Checks -b (BIOS): the error vector, the BIOS ROM page, <rom type="bios">,
# the build scripts' -b, and the three constraints:
#   usage: tests/xml/bios.sh <v32lua binary>
set -eu
bin=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
fail=0
no()  { echo "FAIL: $*" >&2; fail=1; }
has() { grep -qF -- "$2" "$1" || no "$1 lacks: $2"; }
hasnt() { if grep -qF -- "$2" "$1"; then no "$1 contains: $2"; fi; }

cat > bios.lua <<'LUA'
--#title "Test BIOS"
--#texture FONT "font.png"
--#sound CHIME "chime.wav"
function error_handler() end
function main() while true do system.wait() end end
LUA
"$bin" -b bios.lua >/dev/null 2>&1 || no "-b build failed"
has bios.xml 'type="bios"'
has bios.asm '0x10000000'
has bios.asm 'CALL  __function_error_handler'
has Make.sh 'v32lua --no-build-scripts -b '
has Make.sh 'assemble -b bios.asm'
has Make.bat 'assemble -b bios.asm'
# the vector is the first code in the file
first=$(grep -m1 -E '^[[:space:]]+[A-Z]+' bios.asm | tr -s ' ')
[ "$first" = " CALL __function_error_handler" ] || no "first instruction is: $first"

# a normal build is unaffected
rm -f Make.sh Make.bat
"$bin" bios.lua >/dev/null 2>&1 || no "plain build failed"
has bios.xml 'type="cartridge"'
hasnt bios.asm 'Hardware Error Vector'
hasnt Make.sh 'assemble -b'

# constraints
printf 'function main() end\n' > n1.lua
"$bin" -b --no-build-scripts n1.lua >/dev/null 2>&1 && no "no texture accepted"
printf -- '--#texture A "a.png"\nfunction main() end\n' > n2.lua
"$bin" -b --no-build-scripts n2.lua >/dev/null 2>&1 && no "no error_handler accepted"
printf -- '--#texture A "a.png"\n--#sound S "s.wav"\n--#sound T "t.wav"\nfunction main() end\nfunction error_handler() end\n' > n3.lua
"$bin" -b --no-build-scripts n3.lua >/dev/null 2>&1 && no "two sounds accepted"

[ "$fail" = 0 ] && echo "bios: ok"
exit "$fail"
