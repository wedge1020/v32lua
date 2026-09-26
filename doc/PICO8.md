# PICO-8 compatibility layer

Selected with `--#api pico8`, by compiling a `.p8` cartridge directly, or
with `--#p8 "cart.p8"` (which also selects the layer). Under this API,
`spr()`, `btn()`, `print()` etc. are PICO-8's functions, not the native
Vircon32 ones.

## Getting a cart in

| Input | What happens |
|---|---|
| `v32lua game.p8` | The `__lua__` section is compiled (every other line is blanked, so error line numbers match the `.p8`). `__gfx__` becomes the sprite sheet, `__gff__` the sprite flags, `__map__` the map. |
| `v32lua game.lua` with `--#p8 "game.p8"` | For stripped `.lua` exports: code from the `.lua`, assets from the cart. Put the hint at the top, like `--#api`. |
| `v32lua game.lua` with `--#api pico8` | No assets: blank sprite sheet, empty map, no flags. |

Nothing in the cart has to be edited: a `.p8` selects the PICO-8 layer by
itself, and the hints have command-line equivalents that take precedence
over them — `--api pico8`, `--title "..."`, `--p8rate N`:

    v32lua celeste.p8 --title "celeste" --p8rate 11025

Without `--title` (or a `--#title` hint) the title is the cart's first
comment line (PICO-8 shows it as the cart's name), else the file name,
prefixed with `[PICO8] ` — e.g. `[PICO8] ~celeste~`.

Map rows 32–63 are read from the lower half of `__gfx__`, exactly like
PICO-8's shared memory. Trailing all-zero rows that PICO-8 omits are fine.

The compiler writes `<output>_pico8.vtex` (128×128 sprite sheet plus a row
of 16 solid color swatches used by the shape primitives) next to the
`.asm` and registers it as texture 0. A PICO-8 cart can't declare its own
`--#texture` resources (texture 0 is reserved).

## Screen

The 128×128 PICO-8 screen is drawn at 2.75× (352×352) and centered on the
640×360 Vircon32 screen (offset 144, 4). After every `_draw()` the margins
are masked in black, because the GPU has no clip rectangle and PICO-8
clips everything to its screen. Palette index 0 is transparent in sprites.

## Main loop

`_init()` once, then per tick `_update()` → `_draw()` →
present. `_update()` runs at 30 fps (two Vircon32 frames per tick),
`_update60()` at 60 fps; ticks are paced by the frame counter, so a tick
that runs long only slows the game once it exceeds its frames. `_draw()`
never crosses a frame boundary: the GPU draws straight into the displayed
image, so a frame that ends mid-draw would show half-drawn. Before each
`_draw()` the loop checks, with the timer's cycle counter and the previous
draw's cost, whether the draw fits in what is left of the current frame,
and otherwise starts it on the next one. A cart too heavy for its frames
drops to 20 or 15 fps cleanly, like PICO-8. At least
one of `_update`, `_update60`, `_draw` must exist. Top-level code runs before `_init()`; the map and flags are
already loaded then.

## API

| Function | Notes |
|---|---|
| `spr(n, x, y [, w, h [, flip_x, flip_y]])` | Flips use Lua truthiness. |
| `map([celx, cely, sx, sy, celw, celh, layer])` | All arguments optional (defaults 0,0,0,0,128,32). Tile 0 isn't drawn; cells outside the map are empty; `layer` draws tiles whose flags share a bit with it. |
| `mget(x, y)`, `mset(x, y, v)` | 128×64 map; out-of-range reads 0, writes are ignored. |
| `fget(n [, f])`, `fset(n, [f,] v)` | From `__gff__`; writable at runtime. |
| `cls([c])`, `color([c])` | |
| `rectfill`, `rect`, `circfill`, `circ`, `line`, `pset` | Corners in any order. An omitted color uses the pen; a given color becomes the pen (PICO-8 rule). |
| `print(s [, x, y [, c]])` | BIOS font tinted with the palette color. Glyphs are the BIOS font's, not PICO-8's 3×5 font. |
| `camera([x, y])` | |
| `btn([i [, p]])`, `btnp([i [, p]])` | 0 left, 1 right, 2 up, 3 down, 4 O (→ A), 5 X (→ B). No `i` → bitfield. `btnp`: first frame of a press, then from frame 15 every 4 frames. |
| `add`, `del`, `count`, `foreach`, `for v in all(t)` | `del` uses full `==` (string contents compare). `foreach`/`all` follow PICO-8's rule that deleting the current element is safe. `count(t, v)` isn't supported. |
| `flr`, `ceil`, `abs`, `min`, `max`, `mid`, `sgn`, `rnd`, `srand`, `sin`, `cos`, `tan`, `sub` | `sin`/`cos`/`tan` take turns; `sin` is inverted (PICO-8 convention). The RNG is seeded from the clock at boot. |
| `sspr(sx, sy, sw, sh, dx, dy [, dw, dh [, flip_x, flip_y]])` | Stretched blit from the sprite sheet. |
| `sfx(n [, channel])`, `music(n)` | The cart's own `__sfx__`/`__music__`, synthesized at compile time (below). Without that data: a placeholder tone bank — see [PICO8_SFX_SOUND_BANK.md](PICO8_SFX_SOUND_BANK.md). |
| `split(s [, sep [, convert]])`, `unpack(t [, i])` | `unpack` returns up to 8 values. |
| `tostr(v [, hex])`, `tonum(s)`, `chr(n)`, `ord(s [, i])` | |
| `reload()` | Restores the map and sprite flags from the cart (no arguments). |
| `stat(n)`, `printh(s)` | Stubs (`stat` returns 0) — real functions, so `stat` works as a no-op value. |
| `_ENV[name]` | Reads or writes the global called `name` (only globals the program uses by name exist). |
| `pal`, `palt` | Accepted as no-ops (one warning): sprite colors are baked into the texture. |

## Syntax

With `--#api pico8` (or a `.p8`): `!=`, `+= -= *= /= %= ..= ^= \=`, `a\b`
(integer division), `if (cond) statement`, `?expr, ...` (print), button
glyphs ⬅️ ➡️ ⬆️ ⬇️ 🅾️ ❎ as the numbers 0–5, `f"str"` and `f{...}` calls
(standard Lua), and numeric strings wherever a builtin expects a number
(`rnd"128"`, `sfx"38"`, `music"-1"`). `unpack(split"72,32,56")` as the
last argument of a builtin is expanded at compile time.

## Sound

When the cart's `__sfx__`/`__music__` sections are available (a `.p8` is
compiled, or `--#p8 "cart.p8"` is given), the compiler synthesizes the 64
SFX into `<output>_sfxNN.vsnd`, and the runtime plays them:

- `sfx(n [, channel])` plays on SPU channel 4 + `channel` (any free one of
  4–7 when no channel is given). A looping SFX loops until stopped, as in
  PICO-8; `sfx(-1 [, channel])` stops, `sfx(-2, channel)` lets a loop run
  out.
- `music(n)` is sequenced at run time from the SFX, pattern by pattern, on
  SPU channels 0–3 (one per PICO-8 music channel), following the
  loop-start / loop-end / stop flags. No song is pre-rendered, so music
  costs no sound data beyond its SFX. A computed `n` works.

Each pattern lasts a whole number of frames (the tick is 1/120 s, 0.4%
slower than PICO-8's, which is inaudible), and the SPU mixes a frame's
sound at the end of the frame, so the next pattern starts exactly where
the previous one ends. A game update that runs past the frame a pattern
ends on starts the next one late, at the position it would have reached.

Sample rate (`--p8rate N` on the command line, or `--#p8rate` at the top of
the file with `--#api`/`--#p8`):

| `--#p8rate` | Celeste's sound data | Notes |
|---|---|---|
| `22050` (default) | 18 MB | PICO-8's own rate |
| `11025` | 9 MB | lo-fi: the SPU plays samples without interpolation, so a quarter-speed sound has audible images around 10 kHz |
| `44100` | 36 MB | the cleanest playback |

(The earlier approach, pre-rendered songs at 44.1 kHz, took 66 MB.)

The synth follows PICO-8's documented model — 8 waveforms, the 8 effects
(slide, vibrato, drop, fade in/out, fast/slow arpeggio), custom
instruments — with waveform shapes modeled on the zepto8
reimplementation. It is an approximation: the SFX editor's filter
switches (noiz, buzz, detune, reverb, dampen) are ignored, a slide doesn't
carry across patterns, and it hasn't been compared against PICO-8 by ear.
`music()`'s fade and channel-mask arguments are ignored.

## Performance

Table field access, arrays and `all()` loops are the hot paths in most
carts. Celeste runs at a full 30 updates per second in the test harness.
evercore-style engines that test every object against every object, several
times per object per frame, run at about a third of full speed.

## Not supported (yet)

`clip`, `peek`/`poke`/`memcpy`/`memset`, `cartdata`/`dget`/`dset`, real
`stat` values, `menuitem`, `band`/`bor`/`shl`/..., the text cursor
(`print` without coordinates prints at 0,0), palette remapping,
fractional `spr` widths (`spr(n, x, y, 0.5)`), and `reload` with
arguments.
