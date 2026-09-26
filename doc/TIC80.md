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

Sample rate: `--rate 11025|22050|44100` (or `--#rate`), 22050 Hz by default
and shared with the PICO-8 layer. witchem_up: 16.5 MB at 22050 Hz (three
tracks of 25–83 s, 29 SFX renders), about half that at 11025.

## Sprites

`spr(id, x, y, colorkey, scale, flip, rotate, w, h)` follows TIC-80's
`drawSprite()`: flips are negative GPU scales; the 90°/270° orientations are
drawn with `DrawRegionRotozoomed`, and multi-tile sprites pick their source
tiles and cells exactly as TIC-80 does (all 16 flip × rotate combinations,
1×1 and 2×2, checked pixel by pixel against TIC-80's mapping).

## Pause

Start (gamepad 1) pauses: `TIC()` stops, every SPU channel pauses, one dimmed
frame is drawn with "- PAUSED -", and Start again resumes. `time()` keeps
counting while paused.
