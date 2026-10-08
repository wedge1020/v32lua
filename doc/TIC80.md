# TIC-80 compatibility layer

Selected with `--#api tic80`, `--api tic80`, by compiling a `.tic` cartridge,
or automatically for a `.lua` whose entry point is `TIC()`. Under this API,
`spr()`, `btn()`, `print()` etc. are TIC-80's functions. The 240×136 screen is
scaled 2.625× onto Vircon32's 640×360.

## Getting a cart in

| Input | What happens |
|---|---|
| `v32lua game.lua` | A TIC-80 `.lua` project: the code, plus the `-- <TILES>` … `-- </TILES>` style sections TIC-80 appends (tiles, sprites, map, flags, palette, waves, SFX, patterns, tracks). |
| `v32lua game.tic` | A binary cart (Lua only): read chunk by chunk and turned into exactly the text TIC-80 writes for a `.lua` project, so both compile to the same program. PNG-wrapped carts and old compressed-code carts are refused with a message. |

`--title`, `--api` and `--rate` work as for PICO-8 carts; without `--title`
the title is the cart's `-- title:` metadata, prefixed with `[TIC80] `.

## Sound

`sfx()` and `music()` play the cart's own sound. The Vircon32 SPU only plays
sampled sound, so it is synthesized at compile time (`src/tic80_audio.c`) by
a port of TIC-80's sound engine (`src/core/sound.c`):

* the per-tick (60 Hz) SFX envelope machine — volume, wave, chord and pitch
  envelopes with their loops, the SFX speed, reverse chords, 16× pitch;
* the music sequencer — tempo/speed/rows per track, note-off, and the
  `M` (volume), `C` (chord), `J` (jump), `S` (slide), `P` (fine pitch),
  `V` (vibrato) and `D` (delay) commands;
* the register synthesis — a 32-step 4-bit waveform stepped every
  `CLOCKRATE*2/32/(2·freq) − 1` clocks (TIC-80's own slight detune
  included), the LFSR noise channel for flat waveforms, TIC-80's note
  frequency table, stereo volumes, and blip_buf's DC-removing high-pass.

What gets rendered is decided by the program's `sfx()`/`music()` calls:

| Call | Rendered |
|---|---|
| `music(track, …)` | The track, all four channels mixed in stereo, from frame 0 until the sequencer returns to a frame/row it has already played (the end of the track, an empty frame, or a `J` jump). That point becomes the sound's loop point, so the track loops in hardware. A computed track number renders every track. |
| `sfx(id)`, `sfx(id, "C#4")`, `sfx(id, 49)` | The SFX at its own default note, and at each literal note found at a call. |
| `sfx(id, expr)` | Additionally one reference render per octave (at F#), played at the SPU speed that gives the requested pitch. |
| `sfx(expr, …)` | Every non-silent SFX. |

A TIC-80 SFX plays until its duration runs out or it is replaced, so each
render loops over the SFX's sustained part; when the sustain is silent the
sound simply ends. Loop joins are crossfaded.

At run time `music()` plays on SPU channel 0 (starting at the frame's offset
in the track, plus the row; `loop=false` turns the loop off; `music()` or
`music(-1)` stops), and `sfx(id, note, duration, channel, volume)` plays on SPU
channel 4 + `channel`, with `duration` counted down in frames after every
`TIC()` and `volume` 0–15. `sfx(-1, …, channel)` stops a channel.

Differences from TIC-80:

* an `sfx()` on a channel doesn't silence that channel of the music (music
  is pre-mixed);
* a computed note is up to half an octave from its render, so its envelope
  runs up to 1.41× faster or slower than on TIC-80;
* the `sfx()` speed argument and `music()`'s tempo/speed/sustain arguments
  are ignored; `music(track, frame, row)` starts from the rendered track, so
  notes still ringing from the previous frame are heard;
* only bank 0 is read.

Programs without sound data keep the placeholder tone bank.

Sample rate: `--rate 11025|22050|44100` (or `--#rate`), 22050 Hz by default (`V32LUA_DEFAULT_TIC80_RATE` in `inc/config.h`)
and shared with the PICO-8 layer. witchem_up: 16.5 MB at 22050 Hz (three
tracks of 25–83 s, 29 SFX renders), about half that at 11025.

## Sprites

TIC-80 draws at whole pixels: `spr`, `pix`, `print`, `map`, `rect` and the
circles take their x and y as integers (TIC-80's API truncates them toward
zero), and so does this layer before scaling to the Vircon32 screen. A
sprite at y = 112.6 is drawn at row 112, like on TIC-80. (Before, fractional
positions were rounded at the 2.625× screen scale, so a sprite settling on
the ground at 112.0 / 112.2 / 112.6 was drawn one screen row apart each
frame: superblock_adventure's ground-contact vibration.) `line` keeps
fractional endpoints, as TIC-80's does.

`spr(id, x, y, colorkey, scale, flip, rotate, w, h)` follows TIC-80's
`drawSprite()`: flips are negative GPU scales; the 90°/270° orientations are
drawn with `DrawRegionRotozoomed`, and multi-tile sprites pick their source
tiles and cells exactly as TIC-80 does (all 16 flip × rotate combinations,
1×1 and 2×2, checked pixel by pixel against TIC-80's mapping).

## Shapes

`circ`/`circb` draw TIC-80's own pixels (its `drawEllipse()`, Zingl's
algorithm, on the circle's bounding square; `circ` fills each row between
the outline's outermost pixels) — checked pixel for pixel by
`tools/headless/circles.py`. Every circle up to radius 31 is pre-rendered
at compile time into a small white texture (256×407, only in carts that
draw circles) and drawn as **one** zoomed region tinted with the GPU
multiply color: 3–28× less CPU time than the point-by-point / span-by-span
drawing before (180 cycles per circle at any radius up to 31). Larger
circles are drawn from the algorithm, one rectangle per run of pixels
(the first octant's runs and their mirror images), about 1.8× faster than
before. The pause screen's dimming applies to them like to everything else.

With `--fast-circles` (or `--#fast-circles`) a filled circle larger than
radius 31 is the radius-31 disc scaled up: one draw instead of ~1.2 per unit
of radius (2,893 → 200 cycles at radius 40), with about 1.5% of its edge
pixels differing from TIC-80's. Outlines are never approximated: scaling a
ring thickens it.

`map` draws its cells itself (it used to call `spr` for each one): the
texture, scale and row position are set once, each cell costs ~30 cycles
instead of ~240, and cells showing tile 0 are skipped when tile 0 is fully
transparent under the call's color key. Pixel-identical to before; about 9×
faster (witchem_up's gameplay went from 991 overrun frames in 2,500 to 5).

`rect` is one scaled draw of a solid swatch, `rectb` four. Their
arguments are truncated to integers as TIC-80 does, and a width or height
of 0 or less draws nothing (it used to draw the rectangle mirrored).

Circles and rectangles are clipped to the 240×136 screen before they reach
the GPU, and ones entirely off it aren't drawn at all. The Vircon32 GPU has
a pixel budget of 9 screens per frame. Each draw is charged its whole
scaled size, whether or not it lands on screen, and once the budget is
spent the GPU silently skips every later draw in that frame. witchem_up's
title screen scrolls 294 cloud circles, mostly off screen or hanging below
it. Those cost 29 screens a frame, so the title and the witch, drawn last,
never appeared. Clipped, they cost 5.3. A circle crossing the left or top
edge is trimmed in whole 8-pixel steps (21 screen pixels), so its pixels
stay on exactly the same grid. The headless runner models this budget (see
`gpu_dropped` in tools/headless/README.md).

## Memory

`peek`/`peek1`/`peek2`/`peek4`, `poke`/`poke1`/`poke2`/`poke4`, `memcpy`
and `memset` work on an emulated 96 KB RAM: the palette, tiles, sprites
and map come from the cart; the map (0x8000), gamepads (0xFF80) and sprite
flags (0x14404) are live views of `mget`/`mset`, `btn` and `fget`/`fset`;
the rest is plain storage (writing the screen, palette or sound registers
changes nothing seen or heard).

`pmem(index [, value])` has TIC-80's 256 slots of 32 bits. It returns the
slot's value — when writing, the value before the write, as TIC-80 does —
as an unsigned number; values are truncated to integers; an index outside
0–255 gives nil. The slots are saved on the memory card (earlier versions
kept one byte per slot at the same place, so their saves still read back);
without a card they are kept in RAM for the session instead of faulting.

## Input

`btn(id)` and `btnp(id, hold, period)` follow TIC-80's `core/io.c`: `id` is
floored and masked to 0–31, and `btnp` is true on the press frame and, when
`hold` and `period` are both given and ≥ 0, again while the button stays held
once it has been down `hold` frames, every `period` frames (`period` 0: every
frame). There is no default autorepeat.

`key([code])` and `keyp([code [, hold, period]])` read a real keyboard
through a **v32kbd** device: a USB keyboard gadget the console sees as a
gamepad (see the native [API.md](API.md#keyboard-key--keyp--kbd) for how
it works). It goes in gamepad port 1 by default — the second port, so
player 1's gamepad stays in port 0 — or wherever `--keyboard N` /
`--#keyboard N` puts it (`kbd.port(n)` at run time). Without the device
plugged in, no key is ever down.

The codes are TIC-80's (`tic.h`): 1–26 A–Z, 27–36 0–9, 37–47
`` - = [ ] \ ; ' ` , . / ``, 48 space, 49 tab, 50 return, 51 backspace,
52 delete, 58–61 up/down/left/right, 62 caps lock, 63 ctrl, 64 shift,
65 alt, 66 escape, 67–78 F1–F12, 79–94 the numeric keypad. `key()` and
`key(0)` are "any key", `keyp()`/`keyp(0)` "any key went down this frame";
`keyp` repeats with `hold`/`period` exactly as `btnp` does (TIC-80's
`core/io.c`). Ctrl, shift and alt are either side, as in TIC-80. Codes with
no key on a v32kbd device are never down: insert, page up/down, home, end
(53–57), keypad + and * (89, 91). The other keypad keys can't be told
apart from the main ones on the device, so keypad 1 (80) is also the main
1 key, and so on. Codes outside 0–94 are `false` (TIC-80 stops with an
error). The device must be read every frame; the `TIC()` driver does
that, also on frames a cart skips its own `key()` calls. The `kbd.*`
functions (typed text with Shift applied, events, the port) are available
here too.

`mouse()` reads a mouse through a **v32mouse** device (see
[API.md](API.md#mouse-mouse--mouse)), in gamepad port 3 by default
(`--mouse N`, `--#mouse N`, `mouse.port(n)`). It returns TIC-80's
`x, y, left, middle, right, scrollx, scrolly`: the pointer in TIC-80 pixels
(it starts at (120, 68), moves 1 pixel per step and stays on the 240 × 136
screen), the buttons as booleans, and the scroll always 0 (the device has
no wheel). TIC-80's relative mouse mode (poking 0x7FC3F) is not supported.
The `mouse.*` functions (buttons pressed this frame, movement, bounds,
speed, port) work here too.

## reset()

`reset()` starts the cart over, as TIC-80 does. The hardware goes back to
its defaults:
- texture -1, region 0; sound -1, channel 0; gamepad 0;
- all sound stopped;
- multiply color white; alpha blending;
- the screen cleared to black.

After the next frame, the cart restarts from its first instruction with a
fresh stack. Globals, the heap and the layer's state are re-created by the
cart's own start-up code; `pmem` values saved on the memory card survive it (without a card they
live in RAM and start over).

## Pause

Start (gamepad 1) pauses: `TIC()` stops, every SPU channel pauses, one dimmed
frame is drawn with "- PAUSED -", and Start again resumes. `time()` keeps
counting while paused.
