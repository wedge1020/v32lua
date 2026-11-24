# Changelog

## 20261124-dev
- **Fix: "label `__pico8_sgn_done_26` has already been declared" (and the same for `math.atan2` and PICO-8 `stat()`).** `get_next_label()` counts per function, so a label built from it must also carry the function's name; `sgn()`'s (`__pico8_sgn_done_N`), `atan2()`'s (`__atan2_ok_N` / `__atan2_done_N`) and `stat()`'s mouse-dispatch labels (`__stat_general_N` / `__stat_done_N`) did not, and a cart whose 27th `sgn()` fell in a second function failed to assemble (found on nanoman.p8, a PICO-8 cart, with every compiler since the label scheme). They are now `__<function>_sgn_done_N`, `__<function>_atan2_ok_N`, ... like every other per-function label; the other `get_next_label()` users already were.
- **PICO-8 `menuitem()` no longer allocates, so it is safe inside an arena.** It kept its five slots in a table made on first use plus a `{label, cb}` table per item; called from a frame wrapped in an arena (nanoman.p8 calls `menuitem(1)` from its title screen), `--gc-check` stopped on the store into the global list, and without the check the menu would have read freed memory after the release. The slots are now ten fixed globals (`__p8_mi_l1`..`5`, `__p8_mi_c1`..`5`) read by the pause menu through `__p8_menuitem_get(i)`; a label or callback made inside an arena is now the cart's own escape and `--gc-check` reports it at the store like any other. The prelude also follows `needs` to the end of a chain now (menuitem -> `__p8_pausemenu` -> `__p8_menuitem_get`), not one link. Test: `testing/special/29_pico8_menuitem_arena.lua`. Verified: the whole `testing/` suite (2124/2139, the 4 SPU/RNG misses) unoptimized and through v32opt 20261124-dev at -O1 and -Os.
- doc/USAGE.md section 7 (and es/fr): "Measuring the heap" follows v32sim 20261124-dev's second pass -- the same `HEAP` lines from `v32sim --heap` and `v32orun --heap` (also with `-q`), `free=`/`blocks=` for the free lists so that `used - free` is live memory, and the two runners' frame numbering. AGENTS.md, `memory.s` and `gc.c` note that v32sim decodes the heap, arena and free-list words: changing their names or layout means telling v32sim. Checked: `--heap`'s `free=65 blocks=6` on a test cart matches a walk of the free lists in a RAM dump, and `FREE_MASK` matches the non-empty bins.
- doc/V32FFI.md section 5 (FFI memory and arena rules, settled with v32cc; the FFI itself is still unimplemented): with the FFI, C keeps the bottom of RAM (word 0 is its null pointer, globals from word 1) and all of v32lua's RAM moves above the reserve; v32cc 2026-11-24's `--ffi-c-heap=WORDS` link option writes `;;FFI_MAX_MEM` and `;;FFI_C_HEAP` (words) at the top of the linked `.asm`, which v32lua will read; the C heap lives in the reserve; rules for Lua values held by C across `arena.release`. Also corrected: the marshalling (a Lua number is a plain float -- the old `AND 0x003FFFFF` / `OR 0x7FF00000` would destroy it) and the memory map's end (`0x003FFFFF`). v32lua's reader for those lines is not written yet (the old one in `src/ast.c` is commented out).
- **Fix: the numeric-`for` panic screen showed the wrong message.** `__runtime_error_for` (`src/runtime/exec.s`) took the message in R1 and read it after its first `CALL __builtin_print`, which overwrites R1 (the X coordinate) and does not restore it, so the second line drew garbage (an empty line, `?4???3?`, `????` for the start / limit / step cases) instead of "'for' initial value must be a number" and the like. The message now goes to the frame with the value (`[BP-2]` beside `[BP-1]`). Found from v32opt: its dead-register pass deleted the `MOV R1, __const_str_err_for_*` before `JMP __for_number`, rightly, since nothing read that R1 before it was overwritten; with the fix the store is used and v32opt keeps it. Test: `tests/audit/panic_text.py` (in `run_all.sh`) runs the three cases headless and reads the message row back from the GPU log (`runlua -g`): all three failed before, pass now, also through `v32opt -L lua -O3`. No other runtime routine reads a register after `CALL __builtin_print` (checked over `src/runtime/*.s`).
- `tests/audit/run_all.sh`: its clean-up deleted every file that is not `.lua` / `.p8` / `.sh` / `.md`, which included `hints/check_hints.py`; `.py` files are kept now.
- Verification with v32opt 20261124-dev (which fixes two register bugs found with this suite: an input read after a save pair, and a loop promotion into a register the body POPs into): the whole `testing/` suite headless on v32sim's oracle gives the same result at `-O1`, `-O2`, `-O3` and `-Os` as unoptimized, test for test (151/166 files pass in the default mode; the 15 others fail the same way unoptimized: the `v32stdapi/` files and `math/07_math_random`). With `--gc arena --gc-check` likewise, apart from where `gc/09_oom_handler` stops after running out of frames (it does unoptimized too: `--gc-check` on top of its `--#gc arena` slows it past its 700 frames).
- **Every runtime routine the compiler calls now gets its `;@fn ... clobbers=` hint.** `tools/check_clobbers.py` only looked for `CALL __name` in the compiler's C, so the six routines reached through `emit_runtime_call_intrinsic()` -- `__arena_release` (a literal name) and `__builtin_setmetatable`, `__builtin_getmetatable`, `__builtin_rawget`, `__builtin_rawset`, `__builtin_rawlen` (from the `{ "name", nargs, "__routine" }` table in `intrinsics/core.c`) -- had none, and v32opt treated their calls as clobbering everything. The script also reads those two forms now; `src/runtime_clobbers.h` regenerated (`__arena_release` is `R0-R2`). Reported by v32opt 20261124-dev.
- **`;@fn __malloc ... nonzero` (and on `__malloc_owned`)**: says outright that R0 is never 0 on return (doc/HINTS.md), so v32opt can stop inferring it from `__malloc_owned` being defined. Tools that don't know the attribute ignore it.
- **`--gc-check` under v32opt**: `__arena_check_core` read its R1 input (the container) after a `PUSH R1 / CALL __arena_value_addr / POP R1` save, which v32opt 20261124-dev's input analysis read as "R1 is not an input"; it removed the caller's `MOV R1, [BP+3]` and every checked store then panicked as an escape at -O1 and above. `__arena_value_addr` now leaves R1 alone (clobbers R0, R2) and the save is gone. Checked: the whole `testing/` suite through v32opt -O2 (default mode) and -O3 (`--gc arena --gc-check`) on v32sim's oracle -- all `testing/gc` tests pass, and the 9 tests that fail are the same at -O2 and -O3 and with the 20261120 and earlier compilers: the 5 known misses plus 4 that failed only optimized (`special/13_metatables`, `tables/19_index_computed_key`, `tables/20_index_known_number_key` from -O1, `special/26_pico8_stat` from -O2). Those were v32opt bugs, fixed in v32opt 20261124-dev (see the verification entry above). One thing blamed on v32opt here was v32lua's own: the `MOV R1, __const_str_err_for_*` that its dead-register pass removed really was dead -- see the numeric-`for` panic message fix above.
- **Block reuse in every `--gc` mode (also the default `none`).** When a table outgrows its array part or its hash part, the old block is now given back to the allocator (`__mfree`, `src/runtime/memory.s`) instead of being abandoned, and `__malloc` reuses such blocks for later allocations of any kind (strings, tables, closures...). Free lists by size class: bin k holds free blocks of 2^k .. 2^(k+1)-1 words; `__malloc` first tries the first 4 blocks of the request's own bin (first fit; this is where same-size table blocks are found: arrays are 8, 16, 32... words, hash parts 18, 34, 66...), then the head of the smallest non-empty larger bin, and splits a block, returning a remainder of 2 or more words to its bin; otherwise it bumps the heap top as before. Reused memory is not zeroed; every allocation site initialises what it allocates. Cost: 23 fixed RAM words (`FREE_MASK` + 22 bin heads) and 2 instructions per allocation while nothing has been freed yet; cycle counts over 600 frames of five demo carts (Celeste, froggo, BlasTIC, Superblock Adventure, Witchem Up) are within +-0.5% of the previous version. Measured (`testing/gc/04_block_reuse.lua`): a table grown one element at a time to 64 elements costs about 75 heap words instead of about 128 (header 5 + arrays of 8+16+32+64). With `--gc arena` there is no reuse while an arena is open (objects made in an arena must lie above its mark) and a block freed inside an open arena is not kept (the release frees it anyway); blocks freed outside arenas, or below the outermost open mark, are reused once no arena is open. This is NOT a garbage collector: only blocks the runtime knows to be garbage are freed (outgrown table parts, the unused tail of number text); dead tables, strings and closures are still never freed in `--gc none`, so the advice to reuse tables stands. PICO-8 `stat(0)` still reports the heap top, so freed-and-reusable words count as used there. This corrects the 20261120-dev claims that `--gc none` generates exactly the code and RAM it did before and never frees. See doc/USAGE.md section 7.
- **`tostring(number)` (and other uses of the fresh number-to-text buffer) keeps only the words its text needs.** It allocated 48 words per call and kept them all; the unused tail is now given back (the heap top is lowered when the buffer is the newest block, otherwise the tail is freed to the lists). Measured: about 4.9 words per `tostring(i + 0.5)` instead of 48. The two shared scratch buffers used by `print`, `string.format` and `..` coercion are unchanged.
- **Fix: programs including `lib/string.lua` failed to assemble.** The runtime label `__ftoa_return`, added in 20261120-dev, collided with the label the compiler generates for the end of a user function named `ftoa` (`__NAME_return`), and `lib/string.lua` defines `ftoa`. The runtime label is now `__ftoa_tail_done`. Rule for runtime authors (AGENTS.md): runtime labels must not end in `_return` or `_skip`, or look like `_mvpad_N` / `_mvarg_N`, the suffixes generated for user functions.
- Internals: `__mfree` (stack: `[BP+3]` = raw block, `[BP+2]` = size; preserves every register; drops blocks under 2 words); `__malloc` keeps its R0-R3, R6 clobber contract. Verification: the whole `testing/` suite headless is 2101/2123 in the default mode (the same 5 known misses as before: the 4 SPU/RNG tests and `16_table_large_array`, which ran out of `unittest.py`'s default 30 frames -- it now sets `--@ frames: 150` itself, see the `unittest.py` entry below); with `--gc arena --gc-check` the result was the same.

- **`unittest.py`: per-file frame cap and expected-trap tests.** A header line `--@ frames: N` sets that file's frame cap (wins over `-f N`, which stays the default, 30). A `=== EXPECTED TRAP ===` block with `label: NAME[,NAME2]` (inside the `--[[ ]]` comment, before any EXPECTED OUTPUT block) runs the cart with v32orun's `--expect-reach` (v32sim 20261124-dev) and passes when a label is reached (one test in the total; with an EXPECTED OUTPUT block as well, the globals are checked too). `testing/run_tests.sh` (v32sim) skips trap-only files. New tests: `testing/gc/06_arena_err_double_release` (`__arena_err_mark`), `07_arena_err_depth` (`__arena_err_depth`), `08_arena_err_escape` (`--gc-check`, `__arena_err_escape`), `09_oom_handler` (`__oom_handler`, `--@ frames: 700`); `testing/tables/16_table_large_array` now carries `--@ frames: 150` and passes without `-f`.
- `make archive` writes `../v32lua-project-YYYYMMDD.zip`; `make clean` removes it (and the undated name).

## 20261120-dev
- **`--gc arena`: explicit arenas, with `arena.mark()` / `arena.release(m)` / `arena.used()` and `--gc-check`.** The heap never freed anything, so a game that built strings or tables every frame ran out of memory. With `--gc arena` (or `--#gc arena`; the CLI wins) a program can open an arena with `m = arena.mark()` and free everything allocated since with `arena.release(m)`, in a few instructions whatever the amount; marks nest up to 16 deep and releasing an outer mark closes the inner ones (a release of something that is not an open mark, or a 17th mark, shows a red `ARENA ERROR` screen). Works in every API mode. Tables made before the arena that grow inside it get their new array/hash block pinned, so the release never leaves an old table pointing into freed memory (the arena's other garbage below the pin stays allocated); the runtime's long-lived buffers (PICO-8/TIC-80 RAM, `pmem`, banks, a promoted tilemap) are always pinned, and the two number-to-text scratch buffers are allocated at boot in arena mode. The rule is that nothing that outlives the arena (a global, an older table, an upvalue or outer local) may keep a value made inside it; `--gc-check` (`--#gc-check`) panics at such a store (globals, upvalue writes, every table store, `setmetatable`), at about 9% more cycles in a table-heavy PICO-8 cart, so it is for development builds. `--gc none` is the default (`V32LUA_DEFAULT_GC`, `V32LUA_DEFAULT_GC_CHECK` in `inc/config.h`) and generates exactly the code and RAM it did before; `--gc marksweep` is reserved and rejected; `arena.*` without arena mode is a compile error. Both options go into the generated `Make.sh`/`Make.bat`. Tests: `testing/gc/` (basic, pinning, check without false positives). See doc/USAGE.md section 7 and doc/API.md.
- **Fix: running out of memory could corrupt RAM instead of reaching the out-of-memory screen.** (1) `__malloc` returned 0 when the heap would run into the stack, and about half of its callers (`string.sub`/`upper`/`lower`/`rep`/`format`/`gsub`, `split`, date formatting, ...) never checked, so they wrote their result over RAM word 0 (the heap pointer) onwards; `__malloc` now goes to the out-of-memory panic itself and never returns 0. (2) String concatenation (`..`) had no check at all: it bumped the heap pointer by hand, so a long enough `s = s .. c` loop wrote over the stack; it now allocates through `__malloc`. (3) `table.concat` of an empty range returns a shared ROM empty string instead of allocating one word each time. Applies to every mode.
- **Boot-time cartridge layout check.** Function values are NaN-boxed with a 22-bit ROM offset and a closure is a function-tagged value with bit 21 set, so a plain function whose code sits 2M words (8 MB) or more into the ROM would have been called as a closure record, and a string literal past 4M words cannot be addressed. The entry vector now compares two labels the assembler resolves (`__v32lua_code_end`, `__v32lua_rom_end`) once at boot and shows `CART ERROR: PROGRAM CODE EXCEEDS 2M ROM WORDS` or `CART ERROR: PROGRAM DATA EXCEEDS 4M ROM WORDS` instead of misbehaving later. Practically unreachable for real carts. See doc/NaN_boxing.md.
- Internals (heap modes): new `src/gc.c` / `inc/gc.h`, `src/runtime/arena.s` (emitted only in arena mode) and `src/intrinsics/arena.c`. Runtime `.s` files can now bracket lines with `;#if NAME` / `;#if !NAME` / `;#else` / `;#endif` (nestable; names `GC_ARENA`, `GC_NONE`, `GC_CHECK`), resolved by `emit_embedded_asm()`; `tools/check_clobbers.py` sees the markers as comments and so computes clobbers over all branches (a safe superset for v32opt's `clobbers=` hints), and `src/runtime_clobbers.h` is regenerated. `__malloc_owned` (R0 = owning object, 0 = long-lived runtime buffer) is `__malloc` plus the owner, used by the table grow paths and the runtime's persistent buffers; without arena mode it is a second label on `__malloc`. `gc_emit_safepoint()` is called at every frame end (beside the v32io hooks) and emits nothing yet: the hook for a future collecting mode. `__panic_with_message` is an allocation-free red panic screen. Verification: the whole `testing/` suite headless (`tools/headless/unittest.py` on v32sim's oracle) in the default mode is identical to before (2076/2098 before, 2094/2116 with the 18 new checks; the same 5 known misses: the 4 SPU/RNG tests and `16_table_large_array`, which needs `-f 150`); the whole suite compiled with `--gc arena --gc-check` also passes, except that `16_table_large_array` runs out of its 30 frames (it passes with `-f 150`). Celeste, froggo, BlasTIC and Superblock Adventure run 300 frames of random input with no trap in both modes.
- New `--tic80-commit` (TIC-80 API): the drawing calls are queued while `TIC()` runs and replayed in one burst when it returns (at once if the rest of the hardware frame can hold it, else on the next frame), so a `TIC()` that spans several hardware frames no longer shows a cleared or half-drawn screen. `peek`/`poke`/`memcpy`/`memset` (below 0x10000), `mset`, `fset`, `sync` and a raw-color `cls()` replay the queue first; a queued `print()` still returns its width. On BlasTIC's battle screen every presented frame is complete (tests/audit/commit). See doc/TIC80.md.
- Fix: plain `print(x, y, text)` (Vircon32, PICO-8 shorthand and every non-TIC-80 program) drew a single glyph with a garbage advance since the TIC-80 print-scale change. `__bios_print_text` tested its zoom flag with `JF`, but every global is initialised to nil, which is not 0, so every print took the zoomed path. The flag is now tested against an explicit raw 1 (tests/audit/plainprint).
- `X and X[k]` where X is the same side-effect-free read of variables/literals (the `map[r] and map[r][c] or D` idiom, `t.a and t.a.b`) reads X once: the right operand starts from the value the left operand left in the result register. Not applied in programs that use `setmetatable` (an `__index` function could observe the second read). About 10% on BlasTIC drawMap (testing/tables/21).
- Inline `t[i]` array reads are tighter: the table payload is computed once, the range test is a single fused check, and the "is it a number" test is skipped when the key is provably a number (literal, arithmetic, number local / for variable). About 3% on BlasTIC drawMap. NaN, 0, negative, fractional and too-large keys still miss correctly (testing/tables/20).
- Calls to named (static) functions are now direct `CALL __function_NAME` instead of going through the `__builtin_exec` trampoline (about 2.7% on BlasTIC BATTLE). `--no-direct-calls` restores the old path.
- Small functions whose body is a single `return <expr>` (at most 16 AST nodes, no loops/calls to themselves) are inlined at call sites when every argument is a simple expression (literal, local/global name, or simple arithmetic). Parameters are bound to the caller's argument expressions, evaluated in the caller's scope. `--no-inline` disables it.

- **TIC-80 `rect` / `rectb`: leaner runtime path.** `__builtin_tic80_rect[b]` no longer builds a BP frame (arguments are read relative to SP), tests width and height together (`IMIN`, one compare), and the draw routine computes the zoom as `n * 0.875` (2.625 / 3, exact; it was `n * 2.625 * 0.333333333`) and the position with integer math (`(21 n + 4) >> 3` = floor(2.625 n + 0.5)) instead of five float/convert steps per coordinate. A filled rectangle goes from ~66 to ~52 instructions in the runtime. Measured on BlasTIC BATTLE (headless): ~1.6% of the cycles (~823k -> ~810k per game frame); the runtime part of `rect` is now ~8% of the frame, the rest of a `rect` call's cost is evaluating its arguments at the call site. Test: `tests/audit/rectpix/check.sh` (all 240x136 TIC-80 pixels against an independent model: filled, 1-pixel, border, clipping on all four edges, fractional arguments, zero / negative sizes); the older runtime passes it too.
- **Table reads: fewer calls to the general lookup.** (1) `t[expr]` with a computed key (`sp[i+1]`, `t[f(x)]`, `warn[c*100+r]`) used to always CALL `__builtin_table_get`; the table is now pushed while the key is evaluated, popped, and the inline array-part read used for `t[i]` applies (a key that is not a whole number in range still takes the CALL). (2) A `t.field` / `s:sub()` read whose first hash slot is empty (the field is absent) answers nil inline instead of calling `__builtin_table_getk` (a table with a metatable still asks the general routine). (3) A string receiver with a string-library name (`s:sub`, `len`, `upper`, `lower`, `rep`, `byte`, `find`, `reverse`, `gsub`) resolves to its method wrapper at the call site instead of walking `__builtin_string_method_lookup`'s chain of name compares. (4) `__builtin_table_get` probes the hash part inline for number keys (0, negatives, fractions, keys past the array, sparse `y*100+x` keys) instead of going through `__table_hash_find` / `__table_hash`. (5) The `ipairs` iterator reads the array part directly. Measured on BlasTIC BATTLE (headless, cycles per presented game frame): 905k -> ~820k (-9%); `__builtin_table_get` 11.2% -> 4.1% of cycles. Test: `testing/tables/19_index_computed_key.lua` (computed keys, holes, 0 / negative / fractional keys, a metatable's `__index` answering for holes, 50 sparse numeric keys with 50 misses, string methods on strings and on a table with a `sub` field). Baseline (older) compiler passes the same test, so the expected values are the language's, not the new code's.
- **TIC-80 `print`: `scale` and `smallfont` honored, 6-pixel advance.** `print(text, x, y, color, fixed, scale, smallfont)` took only four arguments and drew every glyph unzoomed at the BIOS font's 10-pixel advance (3.8 TIC-80 pixels), while the width it returned assumed 6 -- so text came out narrow and scaled titles (BlasTIC's logo: `print(ch, x, y, col, true, 3)`) were drawn at scale 1. Each glyph is now drawn zoomed (x 1.3125 * scale, y 0.984 * scale; small font 0.79 / 0.82) and advances 6 TIC-80 pixels * scale (4 for the small font); the returned width is `#text * 6 * scale` (`* 4` for the small font). `fixed` is accepted and ignored (the font is always fixed-width). Other `print` calls (PICO-8, plain Lua) are unchanged; the zoom state is four globals (`PRINT_EX_*`) read by `__bios_print_text`, so every program now carries four more RAM words. Test: `tests/audit/printscale/check.sh` (bounding boxes at scale 1 / 3 / small font and the returned widths, on a screenshot).
- **Screen RAM: a row's base color is drawn once.** A row segment of 24 or more bytes is first filled, as one run, with the color most of a 16-pixel sample has (a majority vote of 8 bytes spread over the segment); the runs of that color are then skipped, so every pixel is the same and a row costs 1 + (runs of the other colors) draws at most. A dithered test image: 6080 draws for 10297 runs (-41%); BlasTIC's cutscene art (8+ colors, mostly 1-pixel runs): about -17%, and no change in cycles (the vote costs about what the skipped runs saved). Fixed while testing: the row's Y position is now set before the first draw of the row. Test: `tests/audit/screenbase/check.sh` (all 240x136 pixels of a dithered / noisy / banded image against palette colors computed independently, plus the draw count). Measured on BlasTIC's cutscene: the screen-RAM backdrop is essentially the whole cost -- `--skip-fn showBackdrop` takes it from ~200k cycles and ~2000 draws per hardware frame to ~29k and ~250.
- **`--hook-fn FN=HOOK` and `tools/tic80_pcm_capture.py`: music a TIC-80 cart synthesizes itself.** `--hook-fn` (also `--#hook-fn`, repeatable) inserts `if HOOK(<FN's parameters>) then return end` at the top of FN's body, so a function can be intercepted without editing the cart (the hook returns `true` to take the call over; `Obj.method` names work like `--skip-fn`'s). The tool uses it to replace a software synth (BlasTIC's `updateMusic()`: 128 samples a frame at 7680 Hz into RAM at 0x14E24, ~8 frames of CPU per frame of sound, and nothing to stream a RAM buffer to) with sounds rendered offline: for each `--event` (a call of the music function, e.g. `startSong(3,true)`, `startSong(1~,true,MOODS.calm)` with `1~` a wildcard) it compiles the cart with a driver, runs it headless with the SPU port log as the sample sink, and writes a `.vsnd`. Calls the cart makes to the music function while the sound renders (the next song; the same one, to loop) are skipped and recorded with their position; the generated hooks (`<stem>_pcm.lua`, compiled via the generated `<stem>_pcm_main.lua` that includes the cart) play the sound on SPU channels 8-11 (sfx 12-15), replace the mixer with a tick that fires the recorded follow-ups at the same position of the sound (a crossfade overlaps as the synth's did), and fade out the music a game call interrupts (`--fade`). The functions' own bodies still run, so the cart's bookkeeping keeps working. BlasTIC: 12 songs, 3 moods and the explosion = 17 sounds, 60 MB at the default `--upsample 2`, ~10 minutes to render on 2 cores; on the console logic the title song starts at frame 311 and the follow-up into song 2 comes exactly 3367 frames later. Limits: follow-ups to the nearest 128 samples; mixer effects tied to other game state (the music ducking under an explosion) are not reproduced. Tests: `testing/special/22_hook_fn.lua`, `tools/test_tic80_pcm_capture.py` (synthetic synth cart: follow-up timing, interrupt fade and cancelled follow-up, on the real BIOS).
- **TIC-80 `BDR(row)` (per-scanline callback).** A cart that defines `BDR` now has it called before each screen row is drawn from screen RAM (`row = y + 4`, the console's scanline numbering); whatever it pokes into the palette (0x3FC0, e.g. BlasTIC's sky gradient on entry 11) is in force for that row, and the next rows. The renderer rebuilds only the color-table entries whose palette bytes were written since the last call (`TIC80_PALETTE_DIRTY` is a mask of colors, set by `poke` into 0x3FC0-0x3FEF; `memset`/`memcpy` and `sync` set all 16); a cart without `BDR` pays nothing (a one-word test per row). `--bdr-step N` / `--#bdr-step N` calls it on every Nth row only (default 1 = every row, exact), the palette it set holding for the rows between: a Lua `BDR` costing ~1500 cycles a row would otherwise eat 200k+ cycles of the 250k budget over 136 rows. Limits: only draws from screen RAM see it; `spr`, `rect`, `print` and the other GPU calls draw at call time with the palette as it is then (they are not scanline-timed). Measured on BlasTIC's cutscene: a Lua `BDR` is ~13% of the cycles (about 60k per presented frame) and `--bdr-step 4` cuts that to ~4%; the console presents a frame only when the game's frame is done, so a game frame just over 250k cycles takes two hardware frames (the cutscene is at ~300-450k: 30 fps, whatever BDR costs). Tests: `testing/special/21_tic80_bdr.lua`, `tests/audit/bdr/check.sh` (screenshot: red = 4 * row at step 1, held per group at step 4).
- **TIC-80 `sync()` memory banks.** `sync(mask, bank, tocart)` was a no-op, so a cart that keeps data in banks 1-7 read the wrong data (BlasTIC's backdrops, packed in `<MAP1>`/`<MAP2>`, came out as noise). Now `-- <MAP1>` ... `-- <MAP7>` (and TILES, SPRITES, FLAGS, PALETTE with a bank digit) are read -- from `.lua` projects by a text scan (the lexer's section tags are letters only, so to it they stay comments) and from binary `.tic` carts (bank > 0 chunks) -- and emitted as bank images next to bank 0's own (only when the program calls `sync`). `sync` copies bank -> RAM, or RAM -> bank with `tocart = true`, for mask bits 1 tiles, 2 sprites, 4 map (the live map buffer and its RAM mirror at 0x8000, one `MOVS` each), 32 palette (0x3FC0, so it feeds the screen-RAM colors), 64 flags; mask 0 = all; 8/16 (sfx/music) are accepted and ignored. A bank the cart lacks reads as zeros (the palette is left alone); `tocart` keeps the saved bank in a heap buffer, made on first use. Limit: only RAM changes -- `spr()` still draws the sheet built from bank 0 at compile time. BlasTIC's title screen and menu now draw. Tests: `testing/special/20_tic80_sync_banks.lua`, `tests/audit/ticbanks/check.sh` (a synthetic `.tic` with two map banks).
- **Screen RAM draws faster.** `__tic80_scr_render` scans a row in one tight loop (a byte equal to the current run's just lengthens it) and draws each run with inline integer position math (the Y scale and position once a row): about 2.7x fewer cycles on a dithered backdrop (BlasTIC's title: ~320k -> ~240k a frame, 3000 runs; it overran the 250k budget before).
- **TIC-80 screen RAM (0-0x3FBF) is drawn; `cls` follows the RAM palette.** The 240x136 screen is 4 bits a pixel in RAM (low nibble = left pixel, 120 bytes a row); carts that `memcpy` an image or `poke` pixels into it drew nothing. Writes there (`poke*`, `memset`, `memcpy`) now draw at once, as horizontal runs of one color, one `DrawRegionZoomed` per run (`__tic80_scr_render`); the swatch bank gained a white swatch (region 528, `vtex_generator.c`) that is tinted with `GPU_MultiplyColor` from the **RAM palette** (3 bytes a color at 0x3FC0), so a cart that pokes its palette (BlasTIC's `fadePal`) is honoured for these draws. Once the cart has written screen RAM, `cls(c)` takes its color from the RAM palette and fills the screen RAM with `c` (all literal `cls` calls now go through `__tic80_cls_idx`; before the first screen write nothing changes). Limits: the other drawing calls (`spr`, `rect`, `print`...) do not write screen RAM, so reading it back shows only what the cart itself wrote; a palette poke does not recolor pixels already on screen (the GPU keeps no indices); `pix` still reads nothing. The cost is data dependent (one draw per run, a full-screen noise image is ~230k cycles). Tests: `testing/special/19_tic80_screen_ram.lua`, `tests/audit/screenram/check.sh` (screenshot pixel check).
- **TIC-80 `memset`/`memcpy` run in bulk; `peek`/`poke` fast path; `#s` uses the length cache.** `memset`/`memcpy` went through `__tic80_rd`/`__tic80_wr` one byte at a time (~30 cycles a byte plus a RAM-existence check each; BlasTIC copies whole screens). Runs of 8 or more bytes inside plain storage (0-0x7FFF, 0xFF84-0x14403, 0x14604 up -- not the live map, gamepad bytes or sprite flags) now use SETS / MOVS (one word per cycle); anything else, overlapping copies (forward byte semantics kept), and short runs stay byte by byte. `__tic80_rd`/`__tic80_wr` handle addresses 0-0x7FFF inline (the RAM pointer test no longer costs a call). `__builtin_string_len` (`#s`) now goes through `__str_length`'s one-entry cache, so `for i = 1, #s` / `i <= #s` over a long string measures it once. BlasTIC: load 650 -> ~400 frames, steady state 72k -> ~32k cycles a frame of the 250k budget. Tests: `testing/special/18_tic80_memcpy_bulk.lua`, `testing/strings/17_string_len_long.lua`.
- **TIC-80 map buffer was half the size of the map (heap overflow, `peek` past 0xC000 read 0).** `TIC80_MAP_BUFFER_WORDS` was 16384 while a 240x136 map is 32640 cells, so `__builtin_tic80_init_map` copied twice the buffer's size into it: the heap was overrun and every cell from map row 68 on (RAM 0xC000-0xFF7F) was lost -- `peek` there returned 0, `mget`/`mset` failed on those rows. BlasTIC keeps its LZ-packed art in the high rows, so `loadCast` read zero distances and panicked (`'for' must be a number`, frame ~357). The buffer is now 32640 words, and the zero-fill fallback no longer multiplies the size by 4. Test: `testing/special/17_tic80_map_full.lua` (6 of 7 values fail on the old size).
- **Strings holding NUL bytes.** Strings end at the first zero word, so `string.char(0)` silently truncated them (BlasTIC's packed sprite runs). A NUL byte is now stored as the word 256; `string.byte` reads 256 back as 0 and `print` draws it as a space. A `\0` escape inside a string literal is still not supported. Test: `testing/strings/16_string_nul_byte.lua`.
- **`tools/tic80_audio_snapshot.py`: sound a cart defines at run time.** A cart that `poke`s its waveforms and SFX into RAM while it runs (BlasTIC's `initAudio()` / `putSfx()`) has no `<WAVES>` / `<SFX>` sections, so the compile-time synthesizer had nothing to render and its `sfx()` calls played the placeholder tones. The tool compiles the cart with the named functions called at the end of its top-level code, runs it headless for a few frames, reads waveform and SFX RAM (0x0FFE4..0x11163) back and writes a copy of the cart with the matching sections; the copy compiles as usual and `sfx()` plays the cart's own sounds (`python3 tools/tic80_audio_snapshot.py blastic.lua -o blastic_audio.lua --call initAudio`: BlasTIC's 5 SFX, 6 renders). Test: `tools/test_tic80_audio_snapshot.py`. Sound a cart mixes itself into a RAM buffer (BlasTIC's music) is covered by `tools/tic80_pcm_capture.py`.
- **`--skip-fn NAME[,NAME...]` / `--#skip-fn NAME`: compile named functions with an empty body.** They still exist and return nil, so every call to them stays valid, but they cost a call and a return. For work the target can't show: BlasTIC's `updateMusic` is a software synth that writes PCM into RAM at 0x14E24, which nothing plays, and took 36% of the cart's cycles. Names are as written (`f`, `obj.f`, `obj:f`); the option repeats and takes commas, the hint takes a comma or space separated list. (An earlier version of this entry claimed BlasTIC then ran at 22k cycles a frame; that was the panic screen idling, not the game -- see the map-buffer fix below. Measured steady state, no panic: about 72k of the 250k budget, after a ~650-frame load.) Test: `testing/functions/skipfn00.lua`.
- **`string.byte` measures a long string once.** Strings carry no length, so each call scanned to the terminator: BlasTIC reads a 60k-character string a byte at a time, and `__mv_string_byte` alone was 35% of its cycles. `__str_length` (`src/runtime/string.s`) remembers the address and length of the last string of 64 or more characters (`STRLEN_CACHE`, 2 words of RAM); strings are never modified once built, and the shorter number-to-text scratch buffers that are rewritten in place are never cached. Test: `testing/strings/15_string_byte_long.lua`.
- **Native `tri()`.** The triangle fill was Lua (a prelude, ~2,300 cycles per BlasTIC blade triangle plus a `rect` call per row); it is now `__builtin_tic80_tri` in `src/runtime/tic80.s`, called as an intrinsic (`emit_tic80_tri_intrinsic`) with the same algorithm: per-edge column bounds `c + m * row`, flat edges as a row range, one swatch blit per row straight to `__tic80_rect_draw`. 150 random triangles (on screen, clipped, fractional, flat and vertical edges) produce the identical 7,440 GPU draws as the Lua version, in 38% of the cycles (about 5.3k against 13.8k per triangle including the draws). A program defining its own `tri` still shadows it. `tic80_append_prelude` is now a no-op. Check: `tests/audit/tri/compare.sh`.
- **Fix: `string.byte(s, i, j)` returns every byte; works through an alias and as `s:byte(i, j)`.** It returned only the first byte for `string.byte(s, 2, 5)`, and nil for `local byte = string.byte; byte(s, 2, 5)` (`string.byte` as a value was a lookup in a `string` table that does not exist) and for `s:byte(1, 2)`. BlasTIC's `loadCast` reads `local w,h,ox,oy = byte(castRuns, i+len+1, i+len+4)` and stopped with `'for' must be a number`. A call with three arguments is now a multi-value expression (`__mv_string_byte`, `src/runtime/string.s`): it fills any number of targets, table constructors, call arguments and `return` lists. `string.byte` as a value is `__strfn_byte`, which reads the real argument count from R13 (missing arguments are nil) and returns the list in the Lua return form; `s:byte` uses the same routine. Negative indices count from the end and ranges clamp to the string, in this form and now in the single-value `string.byte(s, -1)` too. One-argument and two-argument calls compile as before. Test: `testing/strings/14_string_byte_multi.lua`.
- **Fix: tables with more than 32,768 sequential elements lost every element.** The array part's capacity is a 16-bit header field; doubling 32768 gave 65536, which overflowed it and read back as capacity 0, so a table holding 32,769 elements was empty (`t[1]` nil, `#t` stuck at 32769). BlasTIC's art loader builds a 35,000-entry table and then spun forever on `nil`. `__table_array_grow` now clamps at 65,535 (`TABLE_ARRAYSIZE`), keys beyond it go to the hash part, and the border (`#t`) follows the sequence into the hash part (`__table_border_follow`), so `t[#t+1] = v`, `#t` and `table.concat` keep working to any length. Test: `testing/tables/16_table_large_array.lua` (run with `unittest.py -f 150`). Elements past 65,535 are in the hash part, about 300 cycles each instead of 150.
- **`table.concat` is linear.** It appended one element at a time with `strcat`, copying the whole accumulator every step: quadratic time (1,000 elements: 14.4M cycles) and, with no GC, quadratic memory. It now measures the result, allocates once and copies (1,000 elements: 0.32M cycles, 44x faster; 500: 23x). Same results, including numbers as elements or separator and empty ranges. Test: `testing/tables/15_table_concat_ext.lua`.
- **Bitwise operators have an inline fast path.** `& | ~ << >>` of whole numbers in [0, 2^24) (shift counts 0..7 for `<<`, 0..31 for `>>`) are computed inline: about 6 cycles over the loop instead of about 96 for the `__builtin_bitop` call. Negative, fractional, larger or non-number operands, other counts, unary `~` and every PICO-8 operator still use `__builtin_bitop`. Checked against the old build on 4,278 operand pairs covering those edges: identical results. Test: `testing/math/10_bitops_fast_path.lua`.
- **Fix: `table.unpack` in two functions gave `label "__unpack_nil_3" has already been declared`** (the assembler stopped on BlasTIC, which unpacks tables in two functions). The label and the `__unpack_t/i/j_N` temporaries were numbered with `get_next_label()`, which restarts in every function and, unlike the other labels, these carry no function name, so each function reused the same names. They now take ids from a program-wide counter (`next_unpack_id`, `src/table.c`). The code was always wrong this way; only a program that unpacks in more than one function showed it. Test: `testing/table_unpack_twofunc00.lua`. No other duplicate labels across the 180 test programs.
- **`math.min` / `math.max` take any number of arguments**, as in Lua (one or more, folded left: `min(a, b, c) == min(min(a, b), c)`; one argument is returned unchanged). They were refused for anything but exactly two (`math.min() expects exactly two arguments`), which stopped BlasTIC's `math.min(1, v.t/200, (v.len-v.t)/300)`. One shared emitter (`emit_math_minmax`, `src/intrinsics/math.c`) does the `PUSH`/evaluate/`POP`/`FMIN|FMAX` step per extra argument, so a later argument may still `CALL`. A call with no arguments is refused (`expects at least one argument`). Two-argument calls compile to the same instructions as before (30 programs diffed). Tests: `testing/math/09_math_minmax_variadic.lua`, `tests/audit/minmax.lua`, `testing/fail/minmax00.lua`.
- **TIC-80 `tri(x1, y1, x2, y2, x3, y3, color)`.** A filled triangle, written in Lua (a prelude appended when a TIC-80 program calls `tri` and does not define it: `tic80_append_prelude`, `src/pico8_prelude.c`). It follows TIC-80's own `drawTri` (core/draw.c): the same bounding box, degenerate-triangle rejection, winding normalization and the same three barycentric weights, but since each weight is linear in x it finds each row's covered run directly and draws it with ONE `rect()` per row, instead of testing every pixel. Compared against a port of `drawTri` on 600 random triangles (clipped and unclipped): 0.03% of pixels differ, all on edges (float32 here, double there). Test: `testing/api/09_tri_basic.lua` (compile only), `tests/audit/tri_span_check.py`. Per-row work was cut (one reciprocal, per-edge bounds computed once, flat edges become a row range): measured on the stock console logic, 27 grass-blade triangles went from 100,086 to 83,884 cycles per frame (-16%). The rest is the Lua arithmetic itself; a native routine would be the next step.
- **TIC-80 `rect()` with literal geometry is drawn inline.** When x, y, w, h are whole-number literals and the rectangle is fully on screen, the scale and position are computed at compile time (with the same float32 steps the runtime uses) and the GPU writes are emitted directly: no argument pushes, no `CALL`, no clip test. Variable, fractional, off-screen or empty rectangles take the existing path unchanged.
- **`tools/tic80_unload.py`: inline a cart's packed code before compiling.** Carts that keep code compressed in cart memory and run it with `assert(load(table.concat(o),"name"))()` (BlasTIC does) cannot be compiled, since `load()` needs the program at run time. The tool rebuilds the cart's RAM image from its `-- <PATTERNS>` / `-- <TILES>` ... sections, decodes the LZ blob at the loader's address and replaces the loader with the code (stripping a `(function() ... end)()` wrapper, as v32lua's global prepass does not see functions declared inside one). `python3 tools/tic80_unload.py game.lua -o game.unpacked.lua`; `--dump-code` prints the code. Self-test: `tools/test_tic80_unload.py`. Checked against BlasTIC: the decoded 18,087 bytes are identical to the hand-decoded story.

## 20261114-dev

- **`AGENTS.md`: notes for larger programs.** Pooling instead of per-frame allocation (no GC), table field reads as builtin calls, top-level `local`s shared across `--#include`d files, positional resource hints, `-1` as the no-tint multiply color. Documentation only; `AGENTS.md` is English only, `README`/`API`/`USAGE` translations unchanged. Also: sorted lists with windowed iteration for long levels, and two hidden per-frame allocators (menu string concatenation, per-frame cloud tables).

## 20261113-dev

- **`;@fn __function_f returns=N`.** The most values any `return` of the function produces (0 for no value). Not written for a function
  with a `return f(...)` or `return ...` (they forward however many values come back) or with inline assembly. A caller reads R2/R3
  only after checking `[RET_COUNT]`, so with N <= 1 `v32opt` knows they are dead at the function's `RET`. `doc/HINTS.md`; test in
  `tests/audit/hints/check_hints.py`. An older `v32opt` ignores the attribute.
- **`Make.sh` / `Make.bat` run `v32opt -L lua -O3`.** They ran `v32opt -O3`, which treats the file as C output. (A `v32opt` that reads the
  `lang=lua` of the `;@hints` header does this by itself; `-L lua` is for the ones that do not.) `doc/USAGE*.md`.
- **`tools/check_clobbers.py`**: a join of paths with different stack depths before a `MOV SP, BP` epilogue and a conditional tail
  call to another routine are followed instead of leaving the routine out. `__pico8_add`, `__builtin_vircon32_memcard_append` and
  `__builtin_vircon32_memcard_load_table` now have a `clobbers=` list (217 of 237 routines). The lists of the 214 routines that
  had one are unchanged.

## 20261112-dev

- **A numeric `for` whose start, limit or step is not a number is a runtime error.** `for i = 1, nil do` used to loop forever and
  a nil step ran zero iterations; now the loop entry panics with `RUNTIME ERROR: 'FOR' LIMIT MUST BE A NUMBER` (`INITIAL VALUE`,
  `STEP`). A numeric string is converted, as in Lua 5.4; a step of 0 is still not an error. Nothing is added for a value the
  compiler sees is a number. Tests: `testing/loops/08_for_variable_bounds.lua`, `tests/loops/for_errors.sh`.

## 20261109-dev

- **A minus sign before a number literal is folded.** `-1`, `-(2)`, `- -3` and `-0` are compiled as the negated constant
  (`MOV R1, 0xBF800000 ; -1`) instead of `MOV` / `PUSH` / `CALL __builtin_unm` / `IADD SP` / `MOV`: same bits as the call
  returned (`-0` is still negative zero), fewer instructions. `-x`, `-"2"` and `-(a + b)` are unchanged. The numeric `for` then
  sees a constant step: `for i = 10, 1, -1` gets the short loop header (`control < limit` exits) and
  `;@loop ... stepval=-1 from=10 to=1`, where it used to test the sign of the step on every iteration and write no `stepval=`.
  A constant step is now loaded with its exact float bits (it went through `%f`, six decimals, so a step like `-0.0000004`
  would have become zero). Tests: `testing/loops/06_negative_step_loops.lua`, `testing/math/08_unary_minus_literals.lua`,
  `tests/audit/hints/check_hints.py`.
- **`-g` cleanup.** `;@var ... global` is written only for names that really are globals (a name assigned only inside a function
  that declares it `local` is no longer listed). A function's prologue carries the `function` line, so `v32opt` no longer
  leaves `;@src -` straight after the label (which ended the function early in `v32as`).
- **`;@loop ... var=N`.** A numeric `for` says which frame word holds the visible loop variable (a copy of the counter,
  refreshed at the top of each iteration), after `step=`: `;@loop kind=for counter=-4 limit=-2 step=-3 var=-5 stepval=1 from=1 to=10`.
  Left out when the body assigns a variable of that name, a closure captured it, the body has inline assembly or the
  function is variadic. `doc/HINTS.md`; tests in `tests/audit/hints/check_hints.py` and `testing/loops/07_loop_variable_copy.lua`. An older `v32opt` ignores the attribute.

## 20261105-dev

- **`-g`: `;@var` for upvalues.** Inside a closure the captured variable is listed:
  `;@var n loc=BP+2 type=lua boxed upvalue` (the hidden leading parameter holding the shared box).
- **`-g`: `;@var` for globals and chunk-level locals**, one per name before the code:
  `;@var counter loc=@0x00000075 type=lua global`. With `v32as -g` they reach `.vbin.vars`/`.vbin.sym`.
- **No private runner any more: v32sim's `v32orun`.** `tools/headless/v32run.cpp`, `build.sh` and `sdlshim/` are gone;
  the same runner (same options, same log format, byte-identical output on the test carts) lives in v32sim
  (`tools/oracle/orun.cpp`, `make oracle COMPUTERSOFTWARE=...`), built on ComputerSoftware's `DesktopEmulator/ConsoleLogic`,
  and also runs a real BIOS + cartridge with `-g -s -t -B -P`. `runlua`, `trap`, `unittest.py`, `circles.py`, `difftest.py`
  and `tests/audit/hints` find it through `tools/headless/oracle.sh` / `oracle.py` (`$V32ORUN`, `$V32SIM_HOME`, a
  v32sim checkout next to this one, `$PATH`). `scripts/testing_harness`: `-v32orun` replaces `-v32run` and `-v32bench`
  (`-b` is v32bench's per-frame cycle counts); `build_tools.py -only v32orun` builds it from a v32sim checkout.
  `unittest.py`: 1811/1826 as before.
- **`demos/api_spu`**: `music.wav` (27 MB) is made from `music.mp3` (3 MB) with `ffmpeg` at build time and removed by
  `make clean`; the source tree shrinks by 24 MB.
- Version `20261105-dev`.

## Unreleased (2026-09 audit)

All fixes below were found by running programs on the official Vircon32
CPU core in a headless harness (`tools/headless/`). Rendering and audio
were not run: GPU and SPU commands were checked from logs, not on screen
or speakers.

### Added

- `;@fn LABEL clobbers=...` for 214 runtime routines, from `tools/check_clobbers.py`
  (`src/runtime_clobbers.h`, checked by `tests/audit/hints/check_hints.py`). `doc/HINTS.md`.

### Fixed

- **Stale register comments in the runtime.** `__table_metamethod`, `__table_rawget_rk`,
  `__table_newindex`, `__table_index_miss` and `__table_unary_meta` said they preserve
  R1-R13 but call `__builtin_table_get` (R6-R13); `__pico8_poke_w` said it preserves R0;
  `__builtin_random` listed R0-R5 in one place, R0-R6 in another. Comments only; no code changed.

- **`-g` wrote a wrong source map.** The map was estimated while generating (an entry said
  line 32720, 11 entries for an 11,000-line program) and several AST nodes (`make_node_*`)
  had an uninitialised line number. The assembly now carries `;@src FILE:LINE` markers and
  `FILE.asm.debug` is made from them, so the lines are exact and survive a tool that
  rewrites the file. `doc/HINTS.md`; test `tests/audit/hints/check_hints.py`.

- **PICO-8 `stat(1)` counted the idle wait as CPU.** To keep a half-drawn
  frame off the screen the runtime starts `_draw()` on a fresh frame when it
  would not fit in the rest of this one, and that wait (up to a whole frame)
  was read as CPU: a light cart showed 1.5 where the work was ~0.6. Idle
  cycles are now accumulated (`PICO8_IDLE`) and left out; a pause is skipped
  and `flip()` starts the count again. Test: `testing/special/28_pico8_stat_cpu.lua`.

### New

- **Compiler hints for `v32opt`, as comments**: `;@hints 1 abi=caller-save lang=lua`,
  `;@fn ... escapes=none`, `;@loop kind=for counter= limit= step= [stepval= from= to=]` and
  `;@cold` on slow paths. Nothing changes in the cartridge (`--no-hints` leaves them out).
  An inline `;@cold {` ... `;@cold }` region marks the `__arith_coerce` call. With `-g`
  also `;@var NAME loc=BP-n type=lua [boxed]` for locals and parameters and balanced
  `;@scope {` / `;@scope }` per block, for a source-level debugger. v32opt does not use the
  loop/cold facts yet; the proposals for it, `v32sim` and `v32as` are in `proposals/`.

- **PICO-8 `stat(30)` / `stat(31)` read the keyboard** (a v32kbd device,
  `--#keyboard N`): a typed-character queue, `stat(30)` true while one waits
  (without consuming it) and `stat(31)` taking it. Switched on by a literal
  `stat(30)` / `stat(31)` or `poke(0x5f2d, …)`; other carts pay nothing.
  Test: `tests/audit/kbd/p8_stat_keys.py`. `stat(28, scancode)` and `stat(2)`
  are not implemented.

- **PICO-8 `stat()` reports real values.** `stat(n)` was a stub that knew
  only the devkit mouse (32-34). It now answers Lua memory in KB (0), CPU
  used this tick (1, from the cycle counter: 1.0 is the whole tick), the
  version id (5, 43), the frame rates (7-9), the sound state (the sfx index
  playing on each channel, 16-19 / 46-49; the music pattern, 24 / 54; music
  playing, 57; a channel reports its `sfx()` sound first, else the music's),
  the clock (80-85, and 90-95 which is the same clock), and the string / nil
  / false ids (4, 6, 31, 100, 101, 30, 110). The mouse ids still go to the
  v32mouse decoder. Not tracked: the note on a channel (-1), patterns and
  ticks played (0), the devkit keyboard, system CPU. Froggo's
  `srand(stat(95))` and `stat(54) == 63` now do what they say.
  `__builtin_pico8_stat` (pico8.s), `emit_pico8_stat_intrinsic`
  (v32mouse.c), the prelude's `stat`. Tests: `testing/special/26_...` and
  `27_...` (with the mouse), `tests/audit/pico8/stat_audio.p8` (sound
  state, needs `V32_SPU_STATE=1`).
- **PICO-8 `all(t)` works as a value.** It was a compile error anywhere but
  `for v in all(t)`. `local it = all(t)`, `f = all`, an iterator stored in a
  table or passed to a function, and `for v in all(t), x do` now call a
  prelude `all()` that returns PICO-8's own iterator function (same
  deletion-tolerant order as the inline loop; `all(nil)` is empty). It is a
  closure, so it costs a heap block per call that nothing frees; carts that
  only use `for v in all(t)` (or `all{...}`) are unchanged and do not get the
  function (`all_needs_function` in pico8_prelude.c; a mention in a `--`
  comment doesn't count). Test: `testing/special/25_pico8_all_value.lua`,
  its expected values produced by PICO-8's definition under real Lua 5.4.
- **Headless harness: `V32_SPU_STATE=1`** gives the SPU stand-in a state per
  channel (`ChannelState`, `ChannelAssignedSound` read back what the selected
  channel was given; Play / Pause / Stop and the `*All` commands). Sounds
  never end. Off by default, so existing `-s` logs are unchanged.

- **`-b` builds a Vircon32 BIOS** instead of a cartridge, under the same
  rules as the Vircon32 toolchain's `compile -b`: a `function error_handler()`
  (run by the console on a CPU hardware error), exactly one `--#texture`
  and at most one `--#sound`, native vircon32 API only (every violation is
  reported at once). The assembly begins with the hardware error vector
  (`CALL __function_error_handler`, `WAIT`, `HLT`), ROM addresses use the
  BIOS page (`0x10000000`, `V32_CART_PAGE`), the XML `<rom>` gets
  `type="bios"`, and the build scripts pass `-b` to `v32lua` and `assemble`.
  Checked by `tests/xml/bios.sh` (`ctest` entry `xml/bios`). See the README.
- **Releases can publish themselves.** The `release` run of the
  "Generate Global Binaries" workflow can publish the GitHub release at once
  (`publish_release`) instead of leaving a draft, attaches a `SHA256SUMS.txt`,
  and takes its text from `.github/release-notes.md` (`@VERSION@` is the
  version). Only the release job has write access.
- **Tables have a real array part and real hashing.** Keys 1..n live in a
  plain array (O(1) reads and writes, doubling growth); every other key
  lives in an open-addressing hash table. String keys hash by content, and
  string literals carry their hash precomputed in ROM, so `obj.field` never
  scans. `t.field` / `obj:method()` use a dedicated literal-key lookup.
  (Previously every table, arrays included, was a linked list of 7-pair
  buckets scanned linearly with a string compare per key.)
- **PICO-8 `sfx()`/`music()` play the cart's own sound.** When a cart's
  `__sfx__`/`__music__` data is available (a `.p8`, or `--#p8`), the
  compiler synthesizes the 64 SFX into `.vsnd` files, and the runtime
  sequences `music()` from them pattern by pattern on SPU channels 0–3
  (`sfx()` uses 4–7). Looping SFX loop until stopped, as in PICO-8;
  `music(n)` with a computed `n` works. Sounds are 22050 Hz (PICO-8's own
  rate) played at half speed; `--#p8rate 11025|22050|44100` picks another
  rate. Celeste's sound: 18 MB (9 MB lo-fi), where pre-rendered 44.1 kHz
  songs took 66 MB. Patterns are a whole number of frames long, so they
  join seamlessly. See `doc/PICO8.md`.
- PICO-8 dialect: `f"str"` / `f{...}` calls, `?` print shorthand, `\` and
  `\=` integer division, `..=`, `^=`, button glyphs (⬅️➡️⬆️⬇️🅾️❎),
  numeric strings in number arguments (`rnd"128"`, `sfx"38"`),
  `unpack(split"...")` as a builtin's last argument, one-argument
  `min`/`max`, `_ENV[name]` read and write of globals.
- PICO-8 functions: `sspr`, `split`, `unpack`, `tostr`, `tonum`, `chr`,
  `ord`, `reload`, and `stat`/`printh` (stubs, usable as values).
- `ioports.gpu.clear(r, g, b [, a])`: color from components (0–255, alpha
  defaults to opaque). Literal values fold to a constant.
- `spr()` blend mode accepts `"alpha"`/`"default"`, `"add"`, `"subtract"`.
- `goto` and `::label::` (block-scoped, forward references allowed).
- Single-quoted strings, `[[long]]` strings, exponent literals (`1e-3`).
- String library calls as methods: `s:sub(2, #s)`, `("x"):upper()`, …
- PICO-8: a `.p8` cart compiles directly (`__lua__` is the code; `__gfx__`,
  `__gff__`, `__map__` become sprite sheet, flags and map), or `--#p8
  "cart.p8"` gives a `.lua` a cart's assets. New `rect`, `pset`, `circ`,
  `color`, `fget`, `fset`, `sub`, `for v in all(t)`, `_update60`;
  `pal`/`palt` are accepted as no-ops with a warning. See `doc/PICO8.md`.
- TIC-80 `sfx()`/`music()` play from a generated placeholder tone bank;
  `print()` uses its color argument and returns the text width.

### Changed

- `spr()`'s `color_mult` is now passed to `GPU_MultiplyColor` as the raw
  packed `0xAABBGGRR` word, with no float → integer conversion (the same
  model as `ioports.gpu.clear(color)`). `hex("0xFFFFFFFF")` used to become
  0 on ARM64 hosts and `0x80000000` on x86_64. A value computed at runtime
  must be a packed word (from `hex()`), not a plain number.
- **Faster generated code** (see Performance):
  * Conditions in `if`/`while`/`repeat` and inside `and`/`or`/`not` compile
    to jumps; no true/false value is built and re-tested at every level.
  * `x == nil/true/false` and `x == <number>` are one compare; `<`, `<=`,
    `>`, `>=` on numbers are inline; general `==` only calls the runtime
    for two strings.
  * `t.field` (and `obj:method()` lookup) does its first hash probe inline,
    with the key's hash computed at compile time; `t[i]` reads the array
    part inline; the hash part is kept at most half full (was 3/4) so
    lookups of absent fields stay short; PICO-8 `count(t)` is O(1) (it is
    `#t`, as in PICO-8 0.2+); `for v in all(t)` steps read the array
    directly.
- PICO-8 main loop is paced by the frame counter, and `_draw()` never
  crosses a frame boundary. The GPU draws straight into the displayed
  frame, so a `_draw()` still running when a frame ended was shown
  half-drawn (Celeste's 400m room flickered). The loop checks the timer's
  cycle counter against the last draw's cost and starts the draw on the
  next frame only when it wouldn't fit. A tick too slow for its frames
  drops to a lower frame rate cleanly, as PICO-8 does.
- PICO-8 `map()` only visits cells that can appear on screen and draws them
  directly (it used to call `spr()` for every cell of the whole region).

### Fixed — compiler core

- **A comment (or string) that merely mentioned `--#api pico8` half-enabled
  PICO-8.** `main.c` looked for the hint with a plain `strstr()`, so
  `-- no --#api pico8 here` switched on the PICO-8 shorthand pass and
  prelude while the API stayed native: `Undeclared function:
  '__p8_cursor_get'` (any source also containing the word "cursor"), and
  then-less `if`s were silently expanded in native mode. It also disabled
  entry-point API auto-detection. Hints are now found the way the lexer
  finds them (a `--#` that opens a comment; text inside comments, long
  brackets and strings is skipped). Tests: `testing/apihint00.lua`,
  `testing/fail/apihint00.lua`.

- Globals started out as 0.0 (a truthy number) instead of `nil` -- and on
  hardware, as whatever the BIOS left in RAM. evercore's player never
  moved: `if pause_player then return end` with `pause_player` never
  assigned. Every global is now set to `nil` before any top-level code.
- Number literals were emitted with 6 decimals: `1e-7` compiled to 0 and
  `0.70710678` lost precision. They are now emitted as their exact bits.

- The register allocator could hand the same register to two live values;
  `2*sign(this.spd.x)` then indexed a string, giving Celeste's
  "attempt to index a non-table value: spd".
- `function t.f()` / `function t:m()` / `local function f()` inside another
  function didn't capture that function's locals (evercore's
  `function obj.left() return obj.x ... end`).
- Functions defined inside a block, or as anonymous values at file scope,
  had their bodies run inline where they were defined.
- `t[expr]` could lose the table when the key needed a call to compute.
- String keys compared by address, not contents (`t["a".."b"]` missed
  `t.ab`).
- `pairs()` looped forever on tables with more than 7 entries.
- `#t` stopped at the first gap in fill order (`t[2]=b; t[1]=a` gave 1).
- `table.remove()` on an array wrote before the array's start.
- Calls through a variable left missing arguments as stack garbage instead
  of `nil`.
- `math.random()` with fewer than 2 arguments read the caller's stack.
- String functions with several arguments could overwrite one argument with
  another (`string.sub(s, i, j)` with computed `i`/`j`).
- `...` used as a value was a stub.
- Concatenating math calls (`"x" .. math.floor(y)`) used the wrong register.
- Numbers printed with trailing zeros (`"0.500000"`); now `"0.5"`.
- `-0 == 0` was false.
- A comment such as `-- 5:6` broke parsing.
- Windows (CRLF) line endings leaked `\r` into long strings.
- Two memory-safety bugs in the compiler itself (an out-of-scope buffer in
  the assembly emitter, a fixed 8-argument array in PICO-8 intrinsics).
- `-w` only silenced the `main()` WAIT warning; it now silences all
  warnings, as documented.
- `make` failed on a fresh checkout because `bin/` didn't exist.

### Fixed — PICO-8 layer

- `cos()` emitted an instruction that doesn't exist (the cart failed to
  assemble).
- Several runtime labels and defines were missing or invalid assembly
  (`VIRCON32_SFX_CURSOR`, `__builtin_tan`, labels used as immediates).
- Map loading read past the end of ROM; `mget`/`mset` corrupted a caller
  register.
- Sprites were drawn off by the hotspot, mis-centered, and flipped sprites
  were one tile off.
- `btn()` directions were wrong; `btnp()` only worked for button 0 and read
  the wrong gamepad.
- `del()` had its arguments swapped; `foreach()` skipped elements after a
  deletion; `count()` counted string keys.
- `mid()` lost its first argument when another argument was a call.
- `circfill()` passed integers to a float routine.
- `rect()` drew wrong edges.
- The palette was Sweetie-16, not PICO-8's.
- `_update` now runs at 30 fps (`_update60` at 60), in PICO-8's order.
- `music()` passed its loop flag as the channel.

### Fixed — TIC-80 layer

- After the first `print()`, sprites and shapes were drawn almost
  invisible: `print()` restored the GPU multiply color from a register
  that the print routine overwrites.

- `spr()` with colorkey `-1` drew from the BIOS texture; flips used
  uninitialized registers.
- Shapes drawn after a sprite used the sprite's texture.
- `map()` could read outside the map (negative origin, `sy = 0` path).
- `sfx()`/`music()` were empty stubs.

### Performance (headless harness, CPU cycles)

Cycles per game update, before and after the condition / equality /
table-access work:

| Workload | Before | Now |
|---|---|---|
| Celeste, first rooms | ~172k | ~134k |
| Celeste, 400m room | ~790k (15 updates/s) | ~442k (full 30 updates/s) |
| evercore level 1 | ~1.35M (player frozen, see Fixed) | ~1.13M with the player moving (~12 updates/s) |
| `primes` demo, fixed work | 50.9M total | 18.9M total (2.7x) |

(The table rewrite before that had already taken Celeste from ~267k.)

evercore is still well short of 30 updates per second: its every-object-
against-every-object collision loops need register-resident locals and
call inlining (`v32opt`), see `design-performance-plan`.

### Known limitations

See the README roadmap. The main ones: `{f()}`/`g(f())` keep only the first
return value; no `select`, `next()`, bitwise operators, or arithmetic on
numeric strings; no garbage collection.

### Not verified

Everything was checked on the real CPU core only. Not checked on real
hardware or a full emulator: what the GPU actually draws, how the
synthesized PICO-8 audio sounds, and packing the generated `.vtex`/`.vsnd`
files with `packrom`.

# Release prep: DEST_LANG docs install, VERSION sync, release workflow (2026-10-11)

Patch: `v32lua-dest-lang-release.patch` (against the 20261011-dev project zip). Compiler output is unchanged: all 209 testing/ + tests/ programs produce byte-identical asm vs. the previous build. ctest 127/127.

## DEST_LANG (Makefile and CMake, same semantics)
- Values: `all` (default; every language under its own name, English man page), `en`, `es`, `fr`. An invalid value is a hard error in both builds.
- es/fr: README, doc/API, doc/USAGE translations installed under plain names (README.md, doc/API.md, doc/USAGE.md); `.<lang>.md` links rewritten to `.md`; English-only docs (PICO8, TIC80, FEATURES, ...) installed beside them. The language-switcher links dangle, same as in v32opt.
- Man page: `man/v32lua.<lang>.1` if present, else English plus a notice. No translated man pages exist yet. `make version` already stamps es/fr pages (localized month) if they're added.
- `make sysinstall` now also installs the docs to `.../v32tools/docs/v32lua` (previously CMake only). Also new: PREFIX/BINDIR/MANDIR/LIBDIR/DOCDIR/DESTDIR. LIBDIR defaults to config.h's path; with a non-default PREFIX it is `$(PREFIX)/Vircon32/v32tools/include/v32lua`.
- Verified: make-es install == cmake-es install (diff -r); cpack names es/fr packages `-es`/`-fr`.

## VERSION sync
- The v32opt bug (workflow `grep -i VERSION | head -1` picking a comment line) was latent in v32lua: only one line of v32lua.h mentions "version" today. The workflow now uses the anchored `#define` sed in a single `version` job; build and release jobs read its output.
- The workflow checks that the man page .TH and the DEBUGGING.md footer match the header: warning on test builds, error on release builds. At patch time both were still stamped 20261010-dev, so run `make version` before a release.
- `make version VERSION=...` now writes the header, as in v32opt. It validates first: an empty value or characters outside `[A-Za-z0-9._+-]` refuse to run, and a missing YYYYMMDD prefix warns. v32opt's `make version` has no such guard (`VERSION=` writes `""`; `/` or `&` break the sed).
- Base Makefile: `bin/$(TARGET)` is now a phony target that recurses into src/, as in v32opt (stale or missing binary for install/sysinstall/tests). src/Makefile names the target `v32lua.exe` on Windows_NT.

## --#include for release zips
- New last-resort search step 5 in resolve_include_path(): `<exe_dir>/include/v32lua`, then `<exe_dir>/../Vircon32/v32tools/include/v32lua`.
- How the exe location is found:
  - Windows: GetModuleFileNameA, declared by hand (no windows.h).
  - macOS: _NSGetExecutablePath.
  - Linux: /proc/self/exe.
  - Elsewhere: argv[0], or a PATH search.
- main() calls include_set_program_name(argv[0]).
- config.h: `_WIN32` default is `V32LUA_WIN32_INCLUDE_PATH` ("C:/Program Files/Vircon32/v32tools/include/v32lua"). It is named so the Makefile's INCPATH sed still matches only the Unix line.
- Tested in five layouts: zip layout, via PATH, symlink, prefix layout, and the argv0/PATH fallback built with -U__linux__.

## Workflow (ported from v32opt's overhaul)
- Windows x86_64 UCRT64 gcc; Windows arm64 CLANGARM64 clang on windows-11-arm.
- OpenBSD 7.9 x86_64/arm64 and Haiku r1beta5 via cross-platform-actions; optional (continue-on-error). Direct compile from inside src/ (for the runtime_embed.S .incbin paths), excluding the dead vsnd_generator.c; no -lm on Haiku.
- Touches parser.c/parser.h then lexer.c after checkout, so make never runs bison/flex.
- `scripts/smoke_test.sh BIN LIBDIR [VERSION]` runs on native jobs (Windows x2, macOS arm64, Linux x86_64) and inside the VMs: checks `--version` and compiles a program that --#includes every lib/*.lua, with V32LUA_INCLUDE unset.
- Zip layout mirrors the Windows install: `v32lua[.exe]`, `include/v32lua/*.lua`, `docs/v32lua/{README*.md, doc/, v32lua*.1}`.
- Not run on GitHub from the session (no actionlint or MinGW reachable). The run blocks were syntax-checked; the version and packaging steps were simulated locally. runtime_embed.S assembles for aarch64/x86_64 Windows, OpenBSD and Haiku targets with clang.
