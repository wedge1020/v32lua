#!/bin/sh
# Checks the optimized-cart title (--#titleopt, --titleopt, --no-diff-opt-title)
# and the Make.sh / Make.bat v32lua writes:
#   usage: tests/xml/build_scripts.sh <v32lua binary>
# The scripts are run against stub DevTools, so no Vircon32 tools are needed.
set -eu
bin=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
root=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

fail=0
no()  { echo "FAIL: $*" >&2; fail=1; }
has() {   # has FILE 'fixed string'
    grep -qF -- "$2" "$1" || { no "$1 lacks: $2"; }
}
hasnt() { if grep -qF -- "$2" "$1"; then no "$1 contains: $2"; fi; }
title() { sed -n 's/.*<rom [^>]*title="\([^"]*\)".*/\1/p' "$1"; }

proj() {   # proj DIR : a src/ + obj/ project
    rm -rf "$1"; mkdir -p "$1/src/textures" "$1/src/sounds" "$1/obj"
    touch "$1/src/textures/ship.png" "$1/src/sounds/vroom.wav"
    cat > "$1/src/game.lua" <<'LUA'
--#title "My Game"
--#texture SHIP "textures/ship.png"
--#sound VROOM "sounds/vroom.wav"
function main() while true do system.wait() end end
LUA
}

# ---- optimized title
proj t1
"$bin" -w --no-build-scripts -o t1/obj/game.asm t1/src/game.lua
[ "$(title t1/obj/game.xml)" = "My Game" ]               || no "title: $(title t1/obj/game.xml)"
[ "$(title t1/obj/gameOpt.xml)" = "My Game [optimized]" ] || no "default opt title: $(title t1/obj/gameOpt.xml)"

"$bin" -w --no-build-scripts --no-diff-opt-title -o t1/obj/game.asm t1/src/game.lua
[ "$(title t1/obj/gameOpt.xml)" = "My Game" ]            || no "--no-diff-opt-title: $(title t1/obj/gameOpt.xml)"

"$bin" -w --no-build-scripts --titleopt "Fast & Loose" -o t1/obj/game.asm t1/src/game.lua
[ "$(title t1/obj/gameOpt.xml)" = "Fast &amp; Loose" ]   || no "--titleopt: $(title t1/obj/gameOpt.xml)"
[ "$(title t1/obj/game.xml)" = "My Game" ]               || no "--titleopt changed the regular title"

sed -i '1a --#titleopt "Hint Opt"' t1/src/game.lua
"$bin" -w --no-build-scripts -o t1/obj/game.asm t1/src/game.lua
[ "$(title t1/obj/gameOpt.xml)" = "Hint Opt" ]           || no "--#titleopt: $(title t1/obj/gameOpt.xml)"
"$bin" -w --no-build-scripts --titleopt "Cli Opt" -o t1/obj/game.asm t1/src/game.lua
[ "$(title t1/obj/gameOpt.xml)" = "Cli Opt" ]            || no "CLI over hint: $(title t1/obj/gameOpt.xml)"
"$bin" -w --no-build-scripts --no-diff-opt-title -o t1/obj/game.asm t1/src/game.lua
[ "$(title t1/obj/gameOpt.xml)" = "Hint Opt" ]           || no "explicit titleopt must beat --no-diff-opt-title"
sed -i '/titleopt/d' t1/src/game.lua
sed -i '1a --#no-diff-opt-title' t1/src/game.lua
"$bin" -w --no-build-scripts -o t1/obj/game.asm t1/src/game.lua
[ "$(title t1/obj/gameOpt.xml)" = "My Game" ]            || no "--#no-diff-opt-title: $(title t1/obj/gameOpt.xml)"

# ---- scripts: src/ and obj/ siblings -> the project folder
proj t2
"$bin" --rate 44100 -o t2/obj/game.asm t2/src/game.lua
[ -f t2/Make.sh ] && [ -f t2/Make.bat ] || no "scripts not in the project folder"
[ ! -e t2/src/Make.sh ] || no "script written in src/"
has t2/Make.sh 'v32lua --no-build-scripts --rate 44100 -o obj/game.asm src/game.lua || abort_build'
has t2/Make.sh 'png2vircon src/textures/ship.png -o obj/ship.vtex || abort_build'
has t2/Make.sh 'wav2vircon src/sounds/vroom.wav -o obj/vroom.vsnd || abort_build'
has t2/Make.sh 'assemble obj/game.asm -o obj/game.vbin || abort_build'
has t2/Make.sh 'packrom obj/game.xml -o bin/game.v32 || abort_build'
has t2/Make.sh 'command -v v32opt'
has t2/Make.sh 'command -v v32lua'
has t2/Make.sh 'v32opt -O3 -o obj/gameOpt.asm obj/game.asm'
has t2/Make.sh 'packrom obj/gameOpt.xml -o bin/gameOpt.v32'
has t2/Make.sh 'BUILD SUCCESSFUL'
has t2/Make.bat 'v32lua --no-build-scripts --rate 44100 -o obj\game.asm src\game.lua || goto :failed'
has t2/Make.bat 'png2vircon src\textures\ship.png -o obj\ship.vtex || goto :failed'
has t2/Make.bat 'where v32opt'
has t2/Make.bat 'where v32lua'
has t2/Make.bat 'BUILD FAILED'
grep -q "$(printf '\r')" t2/Make.bat || no "Make.bat lacks CR LF line ends"
grep -q "$(printf '\r')" t2/Make.sh && no "Make.sh has CR LF line ends"
[ -x t2/Make.sh ] || no "Make.sh is not executable"
sh -n t2/Make.sh || no "Make.sh does not parse"
bash -n t2/Make.sh 2>/dev/null || true

# ---- running it against stub tools
stubs="$work/stubs"; mkdir -p "$stubs"
for t in assemble packrom png2vircon wav2vircon; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls.txt"\n' "$t" "$work" > "$stubs/$t"
    chmod +x "$stubs/$t"
done
ln -s "$bin" "$stubs/v32lua"
# without v32opt: skipped, still succeeds
out=$(cd / && PATH="$stubs:/usr/bin:/bin" "$work/t2/Make.sh" 2>&1) || no "Make.sh failed without v32opt: $out"
echo "$out" | grep -q 'BUILD SUCCESSFUL' || no "no BUILD SUCCESSFUL: $out"
echo "$out" | grep -q 'skipping the optimized build' || no "v32opt skip not reported"
[ -d t2/bin ] || no "bin/ not created"
grep -q 'packrom obj/game.xml' calls.txt || no "packrom not run"
grep -q 'packrom obj/gameOpt.xml' calls.txt && no "optimized path ran without v32opt"
# with v32opt
printf '#!/bin/sh\necho "v32opt $*" >> "%s/calls.txt"\n' "$work" > "$stubs/v32opt"; chmod +x "$stubs/v32opt"
: > calls.txt
out=$(PATH="$stubs:/usr/bin:/bin" t2/Make.sh 2>&1) || no "Make.sh failed with v32opt: $out"
grep -q 'packrom obj/gameOpt.xml -o bin/gameOpt.v32' calls.txt || no "optimized path did not run"
# a failing tool aborts
printf '#!/bin/sh\nexit 1\n' > "$stubs/assemble"
out=$(PATH="$stubs:/usr/bin:/bin" t2/Make.sh 2>&1) && no "Make.sh ignored a failing tool"
echo "$out" | grep -q 'BUILD FAILED' || no "no BUILD FAILED"
# no v32lua on the path
out=$(PATH="/usr/bin:/bin" t2/Make.sh 2>&1) && no "Make.sh ran without v32lua"
echo "$out" | grep -q 'v32lua is needed' || no "missing-v32lua message absent: $out"

# ---- regenerating keeps a generated script current, but never touches a foreign one
echo "mine" > t2/Make.sh
"$bin" --no-build-scripts -w -o t2/obj/game.asm t2/src/game.lua
[ "$(cat t2/Make.sh)" = "mine" ] || no "--no-build-scripts rewrote Make.sh"
"$bin" -o t2/obj/game.asm t2/src/game.lua 2> warn.txt
[ "$(cat t2/Make.sh)" = "mine" ] || no "a Make.sh v32lua did not write was overwritten"
grep -q 'not written by v32lua' warn.txt || no "no warning for the foreign Make.sh"
has t2/Make.bat 'Generated by v32lua'

# ---- source and output in the same folder: scripts beside the source
rm -rf t3; mkdir t3; cp t2/src/game.lua t3/; mkdir -p t3/textures t3/sounds; touch t3/textures/ship.png t3/sounds/vroom.wav
"$bin" -w -o t3/game.asm t3/game.lua
[ -f t3/Make.sh ] || no "no script beside the source"
has t3/Make.sh 'png2vircon textures/ship.png -o ship.vtex'
has t3/Make.sh 'packrom game.xml -o bin/game.v32'

# ---- --xml-preserve-paths
proj t4
"$bin" -w --xml-preserve-paths -o t4/obj/game.asm t4/src/game.lua
has t4/Make.sh 'packrom src/game.xml -o bin/game.v32'
has t4/Make.sh 'src/textures/ship.png -o src/textures/ship.vtex'

[ $fail = 0 ] && echo "build_scripts: OK"
exit $fail
