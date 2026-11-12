#!/bin/sh
# Numeric `for` with a start, limit or step that is not a number: the program must stop with the
# runtime error ("'for' limit must be a number", ...) at loop entry. The unit-test harness
# (testing/run_tests.sh) cannot observe a panic: the console halts in __panic_halt waiting for
# frames, so this script runs each program for a few frames in v32sim and checks
#   - the global `reached` is still 0 (the body never ran, nothing after the loop ran: the old bug
#     was an endless loop that set it to 1, or a silent skip that set it to 2),
#   - the CPU stopped at __panic_halt (its address is in the .vbin.debug file).
# A numeric string is accepted, as in Lua 5.4 (control: reached is 2 and the loop ran 3 times).
#   usage: tests/loops/for_errors.sh <v32lua binary>      needs assemble, packrom and v32sim on PATH
set -eu
bin=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
fail=0
no() { echo "FAIL: $*" >&2; fail=1; }

# run NAME 'lua statements' EXPECT   (EXPECT: panic | done)
run() {
    name=$1; body=$2; want=$3
    cat > "$name.lua" <<LUA
local nl, fl, tl, sl, xl = nil, false, {}, "x", "3"
function main()
    reached = 0
    count = 0
    $body
    reached = 2
end
LUA
    "$bin" --no-build-scripts -w -g "$name.lua" -o "$name.asm" >/dev/null 2>"$name.err" || { no "$name: compile failed"; return; }
    assemble -g program -o "$name.vbin" "$name.asm" >/dev/null 2>&1 || { no "$name: assemble failed"; return; }
    packrom -o "$name.v32" "$name.xml" >/dev/null 2>&1 || { no "$name: packrom failed"; return; }
    addr=$(sed -n 's/^\(0x[0-9A-Fa-f]*\),[^,]*,[0-9]*,__panic_halt$/\1/p' "$name.vbin.debug")
    var=$(sed -n 's/^%define  var_reached  *\(0x[0-9A-Fa-f]*\)$/\1/p' "$name.asm")
    cvar=$(sed -n 's/^%define  var_count  *\(0x[0-9A-Fa-f]*\)$/\1/p' "$name.asm")
    printf 'd/f %s number_reached\nd/f %s number_count\n' "$var" "$cvar" > "$name.cmd"
    v32sim -r --fast --max-frames=60 -C "$name.cmd" -L lua "$name.v32" </dev/null > "$name.out" 2>&1 || true
    reached=$(sed -n 's/.*:\(-\{0,1\}[0-9.]*\):number_reached$/\1/p' "$name.out")
    count=$(sed -n 's/.*:\(-\{0,1\}[0-9.]*\):number_count$/\1/p' "$name.out")
    ip=$(sed -n 's/^IP: \(0x[0-9A-Fa-f]*\)$/\1/p' "$name.out" | tr 'a-f' 'A-F' | sed 's/0X/0x/')
    addr=$(echo "$addr" | tr 'a-f' 'A-F' | sed 's/0X/0x/')
    case $want in
      panic) [ "$reached" = "0.0000" ] && [ "$count" = "0.0000" ] && [ -n "$addr" ] && [ "$ip" = "$addr" ] \
                 || no "$name: expected the runtime error (reached=$reached count=$count ip=$ip panic=$addr)";;
      done)  [ "$reached" = "2.0000" ] && [ "$count" = "3.0000" ] || no "$name: expected 3 iterations (reached=$reached count=$count)";;
    esac
}

b='count = count + 1; reached = 1; if count > 5 then break end'
run limit_nil       "for i = 1, nl do $b end" panic
run limit_nil_lit   "for i = 1, nil do $b end" panic
run limit_false     "for i = 1, fl do $b end" panic
run limit_table     "for i = 1, tl do $b end" panic
run limit_string    "for i = 1, sl do $b end" panic
run start_nil       "for i = nl, 3 do $b end" panic
run start_table     "for i = tl, 3 do $b end" panic
run start_string    "for i = sl, 3 do $b end" panic
run step_nil        "for i = 1, 3, nl do $b end" panic
run step_false      "for i = 1, 3, fl do $b end" panic
run step_string     "for i = 1, 3, sl do $b end" panic
run valid_strings   "for i = '1', xl, '1' do count = count + 1 end" done

[ $fail = 0 ] && echo "for_errors: OK"
exit $fail
