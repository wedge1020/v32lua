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
`_update60()` at 60 fps. At least one of `_update`, `_update60`, `_draw`
must exist. Top-level code runs before `_init()`; the map and flags are
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
| `sfx`, `music` | Placeholder tone bank — see [PICO8_SFX_SOUND_BANK.md](PICO8_SFX_SOUND_BANK.md). |
| `pal`, `palt` | Accepted as no-ops (one warning): sprite colors are baked into the texture. |

`!=` and PICO-8's other syntax extensions follow the `--#api pico8` hint.

## Not supported (yet)

`sspr`, `clip`, `peek`/`poke`/`memcpy`/`memset`/`reload`, `cartdata`/
`dget`/`dset`, `stat`, `menuitem`, `split`, `chr`/`ord`, `tostr`/`tonum`,
`band`/`bor`/`shl`/..., the text cursor (`print` without coordinates
prints at 0,0), palette remapping, and real `__sfx__`/`__music__`
playback.
