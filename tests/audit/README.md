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
| c4_funcs | 38/41 | `{f()}` / `g(f())` keep only the first return value |
| c5_tables | 33/34 | `type(print)` (print is an intrinsic, not a function value) |
| c6_misc | 22/24 | number→string formatting (6 significant digits vs Lua's 14) |
| fmt | 8/9 | `0.9999999 .. ""` is `"1"` (float32 + 6 digits) |

Everything in `pico8/` and `tic80/` runs 60 frames without a trap.
