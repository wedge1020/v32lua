# Changelog

## Unreleased (2026-09 audit)

All fixes below were found by running programs on the official Vircon32
CPU core in a headless harness (`tools/headless/`). Rendering and audio
were not run: GPU and SPU commands were checked from logs, not on screen
or speakers.

### New

- **Tables have a real array part and real hashing.** Keys 1..n live in a
  plain array (O(1) reads and writes, doubling growth); every other key
  lives in an open-addressing hash table. String keys hash by content, and
  string literals carry their hash precomputed in ROM, so `obj.field` never
  scans. `t.field` / `obj:method()` use a dedicated literal-key lookup.
  (Previously every table, arrays included, was a linked list of 7-pair
  buckets scanned linearly with a string compare per key.)
- **PICO-8 `sfx()`/`music()` play the cart's own sound.** When a cart's
  `__sfx__`/`__music__` data is available (a `.p8`, or `--#p8`), the
  compiler synthesizes it into `.vsnd` files: all 64 SFX, and each song
  that `music()` can start, with the song's loop point. `music(n)` with a
  computed `n` works too. See `doc/PICO8.md`.
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
