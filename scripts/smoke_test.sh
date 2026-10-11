#!/bin/sh
# ----------------------------------------------------------------------------
#   Release smoke test for a built v32lua binary
#
#   usage: scripts/smoke_test.sh <v32lua binary> <library dir> [<version>]
#
#   Lays the binary out the way the release zips (and Windows installs) do
#   -- v32lua next to include/v32lua/*.lua -- in a scratch directory, then:
#     1. `v32lua --version` must run (and print <version>, when given);
#     2. a program that --#includes every library file must compile from an
#        unrelated directory, with V32LUA_INCLUDE unset, so the library can
#        only have been found next to the compiler.
#
#   Plain POSIX sh: runs on Linux, macOS, MSYS2, OpenBSD (ksh) and Haiku.
#   Used by .github/workflows/release-builds.yml; harmless to run by hand:
#       scripts/smoke_test.sh bin/v32lua lib
# ----------------------------------------------------------------------------
set -eu

if [ $# -lt 2 ]; then
    echo "usage: $0 <v32lua binary> <library dir> [<version>]" >&2
    exit 2
fi
bin=$1
lib=$2
want=${3:-}

fail() {
    echo "smoke test FAILED: $*" >&2
    exit 1
}

[ -f "$bin" ] || fail "no binary at $bin"
ls "$lib"/*.lua >/dev/null 2>&1 || fail "no *.lua files in $lib"

tmp=$(mktemp -d 2>/dev/null || mktemp -d -t v32lua-smoke)
trap 'rm -rf "$tmp"' EXIT INT TERM

case "$bin" in
    *.exe) exe=v32lua.exe ;;
    *)     exe=v32lua ;;
esac
mkdir -p "$tmp/pkg/include/v32lua" "$tmp/work"
cp "$bin" "$tmp/pkg/$exe"
cp "$lib"/*.lua "$tmp/pkg/include/v32lua/"

# 1. The binary runs and reports the expected version.
out=$("$tmp/pkg/$exe" --version) || fail "'$exe --version' did not run"
echo "$out"
if [ -n "$want" ]; then
    case "$out" in
        *"$want"*) ;;
        *) fail "--version printed '$out', expected '$want'" ;;
    esac
fi

# 2. Every library file is found through --#include, next to the compiler.
{
    for f in "$lib"/*.lua; do
        printf -- '--#include "%s"\n' "${f##*/}"
    done
    printf 'function main()\nend\n'
} > "$tmp/work/smoke.lua"

(
    unset V32LUA_INCLUDE
    cd "$tmp/work"
    "../pkg/$exe" -w -o smoke.asm smoke.lua
) || fail "a program including the library ($(cd "$lib" && echo *.lua)) did not compile"
[ -s "$tmp/work/smoke.asm" ] || fail "the compiler wrote no assembly"

echo "smoke test passed: --#include found $(ls "$lib"/*.lua | wc -l | tr -d ' ') library files next to the compiler"
