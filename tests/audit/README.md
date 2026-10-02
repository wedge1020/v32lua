# Audit test suite (2026-09)

Written during the 2026-09 audit of the compiler, the PICO-8 layer and the
TIC-80 layer. Run everything with `./run_all.sh`.

* `*.lua` here: plain-Lua programs that assign results to globals named
  `R_*` inside `main()`. `difftest.py` runs each one under a reference
  Lua 5.4 and under v32lua (on the headless harness), then compares every
  `R_*` value (numbers to float32 precision). `tables2/3`,
  `tables_insrem` and `closures` cover the table rewrite (array part,
  hashing, content-equal string keys, deletion, growth, border) and local
  closures; `conds` and `index` cover conditions compiled as jumps,
  specialized equality and the inline `t.field` / `t[i]` reads. Keep test arithmetic inside float32's exact range (2^24).
* `pico8/`, `tic80/`: API-layer programs. The expected value of each
  `r_*` global is in a comment next to it (or is `true`); dump them with
  `../../tools/headless/runlua pico8/u1.lua -f 60 -q -D`.

Results at the end of the audit:

| Test | Result | Known reason for the misses |
|---|---|---|
| c1_expr | 68/69 | arithmetic on a numeric string (`"10" + 5`) is not coerced |
| c2_strargs, c3_strmeth, hk, ts, fl, ch, g1, ty, pl, tables2, tables3, tables_insrem, closures, conds, index | all pass | |
| bitops (added 2026-09-26) | all pass | Lua 5.4 bitwise operators, plus `x ^ y` inside a closure (used to lose its upvalue). `pico8/bitops.lua`, `pico8/flip.lua` and `tic80/mem.lua` cover the PICO-8 16.16 operators, `sqrt`/`flip`, and TIC-80 `peek`/`poke`/`memcpy`/`memset`. |
| c4_funcs | 38/41 | `{f()}` / `g(f())` keep only the first return value |
| c5_tables | 33/34 | `type(print)` (print is an intrinsic, not a function value) |
| c6_misc | 22/24 | number→string formatting (6 significant digits vs Lua's 14) |
| fmt | 8/9 | `0.9999999 .. ""` is `"1"` (float32 + 6 digits) |

Everything in `pico8/` and `tic80/` runs 60 frames without a trap.

Added 2026-10-02: `assign_order.lua` (a multiple assignment evaluates every
target's table and key before storing anything: `self.vx, self = 0, 0`,
`t[i], i = v, i + 1`) and `pico8/line2.lua` (`line(x1, y1 [, c])` and
`line()`; check the draws with `runlua pico8/line2.lua -f 3 -g`).
`pico8/cursor.lua`: `cursor()`, `print` at the text cursor, `print(s, col)`,
`print`'s return value, the cursor at 0x5F26/0x5F27.
