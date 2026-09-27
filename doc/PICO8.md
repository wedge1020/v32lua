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
over them — `--api pico8`, `--title "..."`, `--rate N`:

    v32lua celeste.p8 --title "celeste" --rate 11025

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

### Side panels

The 352×352 canvas leaves a 144-pixel strip on each side of the 640×360
screen. Those used to be masked black after every frame (PICO-8 clips its
drawing; the Vircon32 GPU has no clip rectangle, so off-canvas drawing would
show). They now carry two panels of original pixel art, drawn in their place
at no extra cost: the platform names as plain pixel text over a starfield
with a ship and a ringed planet (left) and a sunset over a perspective grid
(right), a controls legend (d-pad, O = A, X = B, Start = pause) and the
cart's title. They are generated at compile time into spare rows of the
sprite texture. `--no-bezel` (or `--#bezel off`) restores the black margins.

#### Custom panel art

`--bezel art.png` on the command line, or `--#bezel "art.png"` in the
source, replaces both panels with your own image (a default for every
cart can be set in `inc/config.h`, `V32LUA_DEFAULT_PICO8_BEZEL_FILE`).

* **One image, both panels side by side.** The left half is the left
  panel, the right half the right panel. Each panel covers 144×360 screen
  pixels, so the image has the proportions **4:5** (width : height).
* **Size.** 288×360 is drawn pixel for pixel. Smaller images are scaled
  up by 360 ÷ height with no smoothing, which suits pixel art: 96×120 at
  3× (the built-in panels' own size), 144×180 at 2×, 192×240 at 1.5×
  (fractional scales repeat some pixel rows and columns unevenly; prefer
  whole ones). At most 816×1020 (a Vircon32 texture is at most
  1024×1024). The width must be even. Any other size is a compile error
  that says what was expected.
* **Colors.** Any colors (32-bit RGBA); the PICO-8 palette isn't
  required. Transparent pixels show black: the panels are drawn over
  black margins then, which also hide anything the cart draws off its
  screen. Keep it opaque to save those two draws.
* **The inner edges** touch the 352×352 game screen at x = 144 and
  x = 496: a dark frame line in the art's innermost columns reads well.
  The top and bottom 4 pixels of the screen columns between the panels
  stay black.
* **File format.** A PNG — grayscale, RGB, palette (with transparency),
  gray+alpha or RGBA, 8-bit (palette and grayscale also 1/2/4-bit;
  16-bit is reduced to 8), *not interlaced* (most editors don't
  interlace by default; GIMP: uncheck "Interlacing (Adam7)" on export).
  A `.vtex` made by Vircon32's `png2vircon` works too. A relative path is
  looked up in the current directory first, then next to the source file.
* The art becomes its own texture (`<cart>_bezel.vtex`, listed in the
  cart's XML), so it doesn't take room from the sprite sheet. The cart's
  title isn't drawn on custom art — put it in the image if you want it.

A template: start from a 96×120 canvas (or 288×360), draw a vertical guide
at the middle, and export both halves in one PNG:

```
v32lua --bezel panels.png game.p8
```

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
drops to 20 or 15 fps cleanly, like PICO-8. A cart may also have none
of `_update`, `_update60`, `_draw`: top-level code or an `_init()` that runs
its own `while true do ... flip() end` loop works too. Top-level code runs
before `_init()`; the map and flags are already loaded then.

## API

| Function | Notes |
|---|---|
| `spr(n, x, y [, w, h [, flip_x, flip_y]])` | Flips use Lua truthiness. |
| `map([celx, cely, sx, sy, celw, celh, layer])` | All arguments optional (defaults 0,0,0,0,128,32). Tile 0 isn't drawn; cells outside the map are empty; `layer` draws tiles whose flags share a bit with it. |
| `mget(x, y)`, `mset(x, y, v)` | 128×64 map; out-of-range reads 0, writes are ignored. |
| `fget(n [, f])`, `fset(n, [f,] v)` | From `__gff__`; writable at runtime. |
| `cls([c])`, `color([c])` | |
| `rectfill`, `rect`, `circfill`, `circ`, `line`, `pset` | Corners in any order. A zero-length `line(x, y, x, y)` draws one pixel. An omitted color uses the pen; a given color becomes the pen (PICO-8 rule). Circles are PICO-8's own pixels (see [Circles](#circles)). |
| `print(s [, x, y [, c]])` | BIOS font tinted with the palette color (the letters are the BIOS font's, not PICO-8's 3×5 font). PICO-8's glyph characters 128–153 (button glyphs, arrows, ♥, ★, ● …) are drawn as 7×5 icons, two characters wide; `\n` starts a new line. |
| `camera([x, y])` | |
| `btn([i [, p]])`, `btnp([i [, p]])` | 0 left, 1 right, 2 up, 3 down, 4 O (→ A), 5 X (→ B). No `i` → bitfield. `btnp`: first frame of a press, then from frame 15 every 4 frames. |
| `add`, `del`, `count`, `foreach`, `for v in all(t)` | `del` uses full `==` (string contents compare). `foreach`/`all` follow PICO-8's rule that deleting the current element is safe. `count(t, v)` isn't supported. |
| `flr`, `ceil`, `abs`, `min`, `max`, `mid`, `sgn`, `rnd`, `srand`, `sin`, `cos`, `tan`, `atan2`, `sqrt`, `sub` | `sin`/`cos`/`tan` take turns; `sin` is inverted (PICO-8 convention). `atan2(dx, dy)` returns turns in [0, 1) in screen space (y down), so `atan2(cos(a), sin(a)) == a`; `atan2(0, 0)` is 0.25, as in PICO-8. `sqrt` of a negative number is 0. The RNG is seeded from the clock at boot. |
| `band`, `bor`, `bxor`, `bnot`, `shl`, `shr`, `lshr`, `rotl`, `rotr` | 16.16 fixed point, like the operators (below). Real functions, so usable as values. |
| `flip()` | Shows the frame drawn so far and waits one PICO-8 frame (1/30 s, or 1/60 s with `_update60`), keeping music on time — for carts that run their own loop. |
| `sspr(sx, sy, sw, sh, dx, dy [, dw, dh [, flip_x, flip_y]])` | Stretched blit from the sprite sheet. |
| `sfx(n [, channel])`, `music(n)` | The cart's own `__sfx__`/`__music__`, synthesized at compile time (below). Without that data: a placeholder tone bank — see [PICO8_SFX_SOUND_BANK.md](PICO8_SFX_SOUND_BANK.md). |
| `split(s [, sep [, convert]])`, `unpack(t [, i])` | `unpack` returns up to 8 values. `split` with a one-character separator is one native pass (a 2 KB string used to take ~7M cycles). |
| `deli(t [, i])`, `assert(v [, msg])` | A failed `assert` shows "assertion failed" and the message, and stops. |
| `oval`, `ovalfill` | The ellipse inscribed in the box, drawn as one span per row. |
| `menuitem(i [, label, fn])` | Adds an entry to the pause menu (see [Pause](#pause)). |
| `tostr(v [, hex])`, `tonum(s)`, `chr(n)`, `ord(s [, i])` | |
| `peek`, `peek2`, `peek4`, `poke`, `poke2`, `poke4`, `memcpy`, `memset`, `@a %a $a` | On an emulated 64 KB RAM in PICO-8's layout (see [Memory](#memory)). `peek(a, n)` returns n values (up to 8); `poke(a, v1, v2, …)` writes several. |
| `reload([dest, src, len])`, `cstore(…)` | `reload` copies from the cart's own data (as compiled, before any `poke`/`mset`/`fset`); no arguments restores all of 0x0000–0x42FF. `reload` from another cart file and `cstore` do nothing (with a warning). |
| `sget(x, y)`, `sset(x, y [, c])` | The sprite sheet in memory. `sset` isn't seen by `spr`/`map`, which draw the sheet as compiled. |
| `cartdata(id)`, `dget(n)`, `dset(n, v)` | 64 persistent numbers at 0x5E00, saved on the memory card (see [Memory](#memory)). |
| `run()` | Starts the cart over: hardware defaults (texture -1, region 0, sound -1, channel 0, gamepad 0), all sound stopped, white multiply color, alpha blending, a black screen, then the cart's first instruction on the next frame with a fresh stack. `cartdata` values on the memory card survive it; `run`'s parameter string isn't passed on. |
| `time()`, `t()` | Seconds since the cart started, counted in PICO-8 frames (1/30 s each, 1/60 s with `_update60`) as PICO-8 does, so it stands still while paused. |
| `stat(n)`, `printh(s)` | Stubs (`stat` returns 0) — real functions, so `stat` works as a no-op value. |
| `_ENV[name]` | Reads or writes the global called `name` (only globals the program uses by name exist). The drawing builtins (`rect`, `rectfill`, `line`, `pset`, `circ`, `circfill`, `spr`, `sspr`, `map`, `print`, `pal`, `palt`, `clip`, `fillp`, `camera`, `color`, `cls`) are there too, for carts that call them by name. |
| `pal`, `palt` | Accepted as no-ops (one warning): sprite colors are baked into the texture. |
| `clip`, `fillp` | Accepted as no-ops (one warning) for now: drawing isn't clipped, and fill patterns draw solid. |

## Pause

Start (on gamepad 1) pauses the game, as on the TIC-80 layer: the cart's
code stops, the SPU channels pause, the last frame stays on screen darkened
with "- PAUSED -" over it, and Start again resumes. Music picks up where it
stopped (the sequencer's clock is moved forward by the time spent paused).
`flip()` loops check for the pause too.

A cart that registers `menuitem()` entries gets PICO-8's pause menu
instead of "- PAUSED -": "continue", the cart's items (slots 1–5), then
"reset cart".
* Up/down choose; O or X picks; Start closes the menu.
* Picking an item calls its callback with 32. The menu stays open only if
  the callback returns true.
* Left/right on an item call its callback with 1 / 2, and the menu stays
  open.
* "reset cart" restarts the cart, as `run()` does.
* The camera and pen color are restored when the menu closes.

## Memory

`peek`/`poke` and friends address a 64 KB RAM laid out like PICO-8's. It
is created the first time it is used (so carts that don't use it pay
nothing) and filled from the cart:

| Address | Contents |
|---|---|
| 0x0000–0x0FFF | Sprites 0–127 |
| 0x1000–0x2FFF | The map (rows 32–63 at 0x1000, shared with sprites 128–255; rows 0–31 at 0x2000) — **live**: `poke` changes what `mget`/`map` see, `mset` what `peek` reads |
| 0x3000–0x30FF | Sprite flags — **live** (`fget`/`fset`) |
| 0x3100–0x42FF | Music and SFX, in PICO-8's format |
| 0x4300–0x5DFF | General use (and the custom font area) |
| 0x5E00–0x5EFF | `cartdata` storage (`dget`/`dset` are `peek4`/`poke4` here) |
| 0x5F00–0x5F3F | Draw state, with PICO-8's defaults; the pen (0x5F25) and camera (0x5F28–0x5F2B) are **live** |
| 0x5F4C–0x5F4F | Buttons of players 0–3 — **live**, read only |
| 0x6000–0x7FFF | The screen: writes (`poke`, `memset`, `memcpy`) are **drawn**; `cls` fills it too. `memset` of whole rows with a byte whose two pixels match (the `memset(0x6000, 0, 0x2000)` idiom) is at most 3 draws |
| 0x8000–0xFFFF | Upper memory |

Addresses wrap at 16 bits as in PICO-8 (`0x8000` and the fixed-point
`-32768` are the same address). `peek2`/`poke2` are signed 16-bit,
`peek4`/`poke4` the raw 16.16 bits.

Limits: sprites and sound are rendered at compile time, so writing the
sprite sheet, the palette registers or the sound data changes nothing seen
or heard; reading the screen returns what was written to screen memory,
not what `spr`/`rect`/`print` drew (Vircon32 has no GPU read-back).

`cartdata(id)` claims the memory card's data area for `id` (a hash is
stored with the data, so another cart's save isn't mistaken for this
one's): if the card already holds this id's data it is loaded and
`cartdata` returns true; from then on every write to 0x5E00–0x5EFF is also
written to the card. Without a memory card `dget`/`dset` still work for
the session, and nothing is saved.

## Syntax

With `--#api pico8` (or a `.p8`): `!=`, `+= -= *= /= %= ..= ^= \=`, `a\b`
(integer division), then-less `if (cond) ...` and do-less `while (cond) ...`
(below), `?expr, ...` (print), button
glyphs ⬅️ ➡️ ⬆️ ⬇️ 🅾️ ❎ as the numbers 0–5, `f"str"` and `f{...}` calls
(standard Lua), and numeric strings wherever a builtin expects a number
(`rnd"128"`, `sfx"38"`, `music"-1"`). `unpack(split"72,32,56")` as the
last argument of a builtin is expanded at compile time. The peek operators
`@a`, `%a` and `$a` are `peek(a)`, `peek2(a)` and `peek4(a)`.

`if (cond) body` without `then`, and `while (cond) body` without `do`,
take the **rest of the line** as the body, as in PICO-8: several
statements, `return` with a value, `else`, and further shorthand all work
(`if (n==1) return 12`, `if (a) x=1 else x=2`). A body that opens a bracket
or a block (`if (x) run(function()` …) runs until the line where that
closes; an `end` that closes an enclosing block ends the body first
(`function f(a) if (a) return 1 end`). The condition must be one
parenthesized expression followed on the same line by a statement: in
`if (a) < (b) then` the parentheses are just part of the condition. This
is a source rewrite before parsing (pico8_shorthand.c) on the same lines,
so error line numbers don't move.

`unpack(t)` as the last argument of a call or the last item of a table
constructor passes all its values, as in Lua (`f(unpack(t))`,
`{unpack(t)}`); `...` as the last argument of a builtin is spread the same
way (`function box(...) rectfill(...) end`).

Glyph characters in strings — a `.p8` stores them as Unicode, e.g. 🅾️ ❎ ⬅️
♥ ★ — become their single P8SCII character (128–153), as in PICO-8:
`#"🅾️" == 1`, `ord("❎") == 151`, `sub()` sees one character. Strings also
take Lua's `\ddd` and `\xHH` escapes. (Kana, 154–253, stay UTF-8.)

`//` starts a line comment, as in PICO-8 (outside PICO-8 mode it's Lua's
floor division).

Number literals take PICO-8's 16.16 fixed-point value, the nearest
multiple of 1/65536: `0.1` is `0x0.199a` and `0.4` is `0x0.6666`. So is a
number `split()` reads from a string. Numbers are still floats, but these
values add and subtract exactly. For example, `v += 0.4` four times, then
`v -= 0.4` four times, gives exactly 0, as in PICO-8. With plain float
literals it gave 6e-8, and froggo's player kept creeping one pixel at a
time. Products and quotients aren't rounded to the 16.16 grid.

Bitwise operators work on PICO-8's 16.16 fixed-point representation, as in
PICO-8: `& | ~` (or `^^`) `<< >> >>> <<> >><` and unary `~`, with the
compound forms `&= |= ^^= <<= >>= >>>= <<>= >><=`. `>>` is arithmetic,
`>>>` logical; fractions take part (`0.5 | 1 == 1.5`). Binary literals
(`0b1010`, `0b1.1`) and hex fractions (`0x0.8`) are accepted, and hex
literals `0x8000`–`0xffff.ffff` are negative (`0xffff == -1`).

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

Sample rate (`--rate N` on the command line, or `--#rate` at the top of
the file with `--#api`/`--#p8`; `--p8rate`/`--#p8rate` are the old names,
still accepted; the default when neither is given is
`V32LUA_DEFAULT_PICO8_RATE` in `inc/config.h`, 22050 as shipped). The same
option applies to TIC-80 carts:

| `--rate` | Celeste's sound data | Notes |
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

## Circles

`circ` and `circfill` draw the pixels PICO-8 does (its midpoint circle, as
reimplemented by zepto8 — checked pixel for pixel by
`tools/headless/circles.py`). Every circle up to radius 31 is pre-rendered
at compile time into a small texture (256×407, only in carts that draw
circles), so each is **one** GPU draw, tinted to its color: 4–33× less CPU
time than drawing it point by point or span by span, as before. Larger
circles are drawn from the algorithm, one rectangle per run of pixels,
about 2.3× faster than before. With `--fast-circles` (or `--#fast-circles`)
a filled circle larger than radius 31 is the radius-31 disc scaled up: one
draw, with about 1.5% of its edge pixels differing from PICO-8's; outlines
stay exact (a scaled ring would get thicker).

Circles entirely off the 128×128 canvas aren't drawn, and one crossing an
edge is drawn trimmed to it. The Vircon32 GPU charges every draw its
whole size against a per-frame budget (9 screens), on screen or not, and
silently skips every draw after the budget runs out. froggo's circle wipe
(270 overlapping discs, many off the canvas) cost 21 screens and lost
13,562 draws; trimmed, it costs 7.8. Trims at the left and top edges come
in steps of 4 pixels (11 screen pixels), so the pixels keep their grid.

## Performance

Table field access, arrays and `all()` loops are the hot paths in most
carts. Celeste runs at a full 30 updates per second in the test harness.
evercore-style engines that test every object against every object, several
times per object per frame, run at about half of full speed.

What the layer does to keep the common calls cheap:

* `map` visits only the cells that can land on the screen, clipped to the
  map once, and draws each one itself (no `spr` call). The cell loop keeps
  the cell index, screen x and count in registers and reads each map word
  (4 cells) once; a word of 4 empty cells is stepped over in one go. About
  19 cycles per cell with a layer filter, ~12 without (was ~55 plus a
  helper call): Celeste's 16×16 room layers went from ~14,000 to ~4,800
  cycles per call.
* `spr` with one 8×8 sprite (`w`/`h` omitted or 1, the usual call) takes a
  short path: 75 cycles instead of 128 in Celeste.
* `for v in all(t)` steps through the array part inline (~25 cycles per
  element instead of ~70); the end of the loop, deletions and holes fall
  back to the runtime step, so PICO-8's deletion-safe order is unchanged.
  `all(nil)` is an empty loop, as in PICO-8.
* `x == "literal"` (and `~=`) is decided inline: string literals are
  interned, so two different literals are never equal and only a string
  built at run time needs a content compare. froggo's
  `if obj.name == "ant" then …` chains went from ~12M cycles per 1,800
  frames to nothing measurable.

Measured on the harness with the same random input over 1,800 frames:
Celeste 127k → 100k cycles per update; froggo 383k → 327k (766 overrun
frames → 21); evercore 919k → 811k (13% more updates per second).

## Lua details that carts rely on

* **Multi-value lists.** `unpack(t [, i [, j]])` returns every value from
  `t[i]` to `t[j]` (it used to stop at 8), and `...`, `unpack(...)` or a
  call returning several values expand in full as the last argument,
  return value, table field or assignment value: `fn(unpack(args))`,
  `ctx[name](ctx, ...)`, `return x, unpack(list, 2)`, `{"move",
  unpack(params)}`. A cart's own recursive `unpack` works too (just one
  boss's promise chains are built this way). Up to 32 values.
* **Numeric strings in arithmetic** become numbers, as in PICO-8:
  `("0x".."ff") + 0` is 255, `"12" + 1` is 13 (nanoman's level data).
* `add`, `del`, `count` and `foreach` on `nil` do nothing (`count` is 0),
  as in PICO-8 — just one boss adds its first entities before the list
  exists. `all(nil)` is an empty loop.

## Not supported (yet)

`clip` and `fillp` (accepted, no effect), real `stat` values, custom
`menuitem` entries in the pause screen, custom fonts (poked to 0x5600), the
text cursor (`print` without coordinates prints at 0,0), palette remapping,
fractional `spr` widths (`spr(n, x, y, 0.5)`), `pget`, loading data from other
cart files (`reload` with a file name, multi-cart games), and `cstore`.
