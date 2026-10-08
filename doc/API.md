# Native Vircon32 fantasy-console API

This document covers ONLY the native Vircon32 API — the surface active when
neither `--#api pico8` nor `--#api tic80` compatibility mode is selected.
Under those modes, `spr()`/`btn()`/etc. are that console's own API instead
(see the PICO-8 / TIC-80 compatibility docs), and the calls below are not
available.

The [Quick reference](#quick-reference) below lists every intrinsic and
every `ioports.*` port on one page; the sections after it cover each part
in detail.

The SPU port write order matters for sound; see
[Sound: music.\* / sfx.\*](#sound-music--sfx).

---

## Table of Contents

- [Quick reference](#quick-reference)
  - [Intrinsic functions](#intrinsic-functions)
  - [ioports.\* — every hardware port](#ioports--every-hardware-port)
  - [Standard library](#standard-library)
- [Sound: music.\* / sfx.\*](#sound-music--sfx)
- [ioports.spu.cmd() — the raw escape hatch](#ioportsspucmd--the-raw-escape-hatch)
- [Boolean IO ports](#boolean-io-ports)
- [System: system.\*](#system-system)
- [Graphics: spr()](#graphics-spr)
- [Graphics: rect() / rectfill()](#graphics-rect--rectfill)
- [Input: btn() / btnp()](#input-btn--btnp)
- [Keyboard: key() / keyp() / kbd.\*](#keyboard-key--keyp--kbd)
- [Tilemap: tilemap.\*](#tilemap-tilemap)
- [Memory card: memcard.\*](#memory-card-memcard)
- [Other raw IO ports](#other-raw-io-ports)

---

## Quick reference

An **intrinsic** is a name the compiler recognizes and turns into inline
instructions or a call to a runtime routine: there is no Lua table or
function behind it. A function of your own with the same name (`spr`,
`rgba`, `color`, …) replaces the intrinsic.

### Intrinsic functions

*Graphics*

| Call | Returns | What it does |
|---|---|---|
| `spr(region, x, y [, sx [, sy [, angle [, color [, blend]]]]])` | nil | Draws a texture region; picks the plain, zoomed, rotated or rotozoomed draw from the arguments. [Details](#graphics-spr) |
| `rect(x1, y1, x2, y2 [, color])` | nil | 1-pixel rectangle outline between two inclusive corners. Color: packed word, default white. [Details](#graphics-rect--rectfill) |
| `rectfill(x1, y1, x2, y2 [, color])` | nil | Filled rectangle, one GPU draw. |
| `print(x, y, value)` | nil | Draws `value` (converted with `tostring`) at pixel `x, y` with the BIOS font. |
| `ioports.gpu.clear([color])` / `clear(r, g, b [, a])` | nil | Sets the clear color (optional) and clears the screen. [Details](#gpu-clear) |
| `ioports.gpu.draw([mode])` | nil | Draws the selected region at `gpu.x, gpu.y`. `mode`: `"draw"` (default), `"zoom"`, `"rotate"`, `"rotozoom"`, or `0`–`3`. |
| `ioports.gpu.blending(mode)` | nil | Sets the blending mode: `"alpha"`/`"default"`, `"add"`, `"subtract"` (string literal). |
| `ioports.gpu.sync()` | nil | Waits for the next frame (`WAIT`); same as `system.wait()`. |
| `rgba(r, g, b [, a])` | packed word | Packs a color into the GPU's `0xAABBGGRR` word. Components clamped to 0–255, alpha defaults to 255. [Details](#colors-rgba) |
| `color(n)` | packed word | Turns a number holding a packed color into the word (for colors you computed or loaded). [Details](#colors-color) |
| `hex("0x…")` | packed word | A string literal of hex digits as the exact 32-bit word. |

*Input*

| Call | Returns | What it does |
|---|---|---|
| `btn(id [, pad])` | boolean | Button `id` (0–10, hardware order) is held. [Details](#input-btn--btnp) |
| `btnp(id [, pad])` | boolean | Button `id` was pressed this frame. |

*Keyboard* (v32kbd device) — [details](#keyboard-key--keyp--kbd)

| Call | Returns | What it does |
|---|---|---|
| `key([k])` | boolean | Key `k` (code or literal name: `"a"`, `"enter"`, `"shift"`) is held; no `k`: any key. |
| `keyp([k [, hold, period]])` | boolean | Key `k` went down this frame (autorepeat with `hold`/`period`, as TIC-80). |
| `kbd.read()` | number / nil | Next key press as the character it types (Shift, Caps Lock applied). |
| `kbd.event()` | number / nil | Next event: `+code` pressed, `-code` released. |
| `kbd.port([n])` | number | Gamepad port of the keyboard (default 1); setting it starts over. |
| `kbd.capslock()`, `kbd.connected()` | boolean | Caps Lock state; device plugged in. |
| `kbd.clear()` | nil | Drops unread events. |

*Sound* — [details](#sound-music--sfx)

| Call | Returns | What it does |
|---|---|---|
| `music.play(snd [, ch [, loop [, vol [, start]]]])` | channel | Plays a sound, on channel 0 by default. |
| `music.pause([ch])`, `music.resume([ch])`, `music.stop([ch])` | nil | Channel control. |
| `music.playing([ch])` | boolean | Is the channel playing. |
| `music.volume(vol [, ch])` | nil | Channel volume. |
| `sfx.play(snd [, ch [, vol [, speed]]])` | channel | Plays an effect on the next of channels 1–15. |
| `sfx.stop([ch])`, `sfx.volume(vol [, ch])` | nil | Stops effects (channels 1–15), sets volume. |
| `ioports.spu.cmd(mode)` (or `.command`) | nil | Raw SPU command on the selected channel. [Details](#ioportsspucmd--the-raw-escape-hatch) |

*Tilemaps, memory card, system*

| Call | Returns | What it does |
|---|---|---|
| `tilemap.get(MAP, x, y)` | number / nil | Tile at `x, y` of a `--#tilemap`. [Details](#tilemap-tilemap) |
| `tilemap.set(MAP, x, y, v)` | v | Changes a tile (the map is copied to RAM on the first write). |
| `tilemap.render(MAP, sx, sy, w, h, x, y, tw, th [, skip])` | nil | Draws a block of tiles. |
| `memcard.save(v [, pos])`, `memcard.load([pos])` | v | Reads/writes one word on the memory card. [Details](#memory-card-memcard) |
| `memcard.load_table(pos)` | table / nil | Loads a table saved with `memcard.save(t)`. |
| `memcard.title(str)` | nil | Sets the card's save title. |
| `memcard[pos]`, `memcard[pos] = v` | | Same as `load` / `save`. |
| `system.wait()` / `system.halt()` | nil | `WAIT` for the next frame / `HLT`. [Details](#system-system) |
| `system.date()` / `system.time()` | string, 3 numbers | `"YYYY-MM-DD", y, m, d` / `"HH:MM:SS", h, m, s`. |
| `system.frames()` / `system.cycles()` | number | Frames since power-on / CPU cycles in the current frame (also without `()`). |

*Language and inline assembly*

| Call | What it does |
|---|---|
| `tostring(v)`, `tonumber(s [, base])`, `type(v)` | As in Lua. |
| `pairs(t)`, `ipairs(t)` | Iterators for `for k, v in …`. |
| `setmetatable`, `getmetatable`, `rawget`, `rawset`, `rawlen`, `rawequal` | Metatables: `__index`, `__newindex`, `__call`, `__tostring`, `__len`, `__metatable`. |
| `__asm__("…")` | Inline assembly with `{var}` substitution; registers and stack are saved around it. |
| `__rawasm__("…")` | Assembly copied into the output as is. |

`print` and `ioports.*` are native-mode names; under `--#api pico8` or
`--#api tic80`, `print`, `spr`, `btn` and so on are that console's
functions instead (see [PICO8.md](PICO8.md) and [TIC80.md](TIC80.md)).
Not available: `printf`, `pcall`/`error`/`assert`, `select`, `next`,
`string.match`/`gmatch`, `os.*`, `io.*`, `coroutine.*`.

### ioports.\* — every hardware port

Each property reads or writes one Vircon32 I/O port directly (`IN`/`OUT`),
with no table lookup. Types:

* **int** — a whole number. Reading gives a Lua number; writing a number
  truncates it toward zero (`CFI`). A numeric literal is written as the
  exact 32-bit word instead, so `ioports.gpu.bgcolor = 0xFF003366` and
  `ioports.gpu.x = -5` both store what you wrote (see
  [Integer ports and literals](#integer-ports-and-literals)).
* **float** — a Lua number, stored as is.
* **bool** — a Lua boolean: reads give `true`/`false`, writes test Lua
  truthiness. See [Boolean IO ports](#boolean-io-ports).
* **color** — an int port that holds a packed `0xAABBGGRR` word. Write a
  literal, `rgba()`, `color()` or `hex()`; a runtime number is converted to
  an integer, which is not the same bits.

R = read, W = write.

**ioports.gpu.\* — graphics**

| Property | Port | Access | Type | Meaning |
|---|---|---|---|---|
| `ioports.gpu.texture` | `GPU_SelectedTexture` | R/W | int | Texture used by region settings and draws (`--#texture` names, or -1 for the BIOS texture). |
| `ioports.gpu.region` | `GPU_SelectedRegion` | R/W | int | Region (0–4095) of the selected texture to define or draw. |
| `ioports.gpu.minX`, `minY` | `GPU_RegionMinX/Y` | R/W | int | Region top-left corner, in texture pixels. Writing one also sets `hotX`/`hotY` to the same value. |
| `ioports.gpu.maxX`, `maxY` | `GPU_RegionMaxX/Y` | R/W | int | Region bottom-right corner (inclusive). |
| `ioports.gpu.hotX`, `hotY` | `GPU_RegionHotSpotX/Y` | R/W | int | Region hotspot: the point placed at `gpu.x, gpu.y`. Set after `minX/minY`. |
| `ioports.gpu.x`, `y` | `GPU_DrawingPointX/Y` | R/W | int | Screen position of the next draw. |
| `ioports.gpu.scaleX`, `scaleY` | `GPU_DrawingScaleX/Y` | R/W | float | Scale for zoomed draws. |
| `ioports.gpu.angle` | `GPU_DrawingAngle` | R/W | float | Angle for rotated draws, in radians. |
| `ioports.gpu.bgcolor` | `GPU_ClearColor` | R/W | color | Color used by `clear()`. |
| `ioports.gpu.multiply` | `GPU_MultiplyColor` | R/W | color | Color every draw is multiplied by (`0xFFFFFFFF` = unchanged). |
| `ioports.gpu.blending` | `GPU_ActiveBlending` | R/W | int | Blending mode number (alpha `0x20`, add `0x21`, subtract `0x22`); or call `ioports.gpu.blending("add")`. |
| `ioports.gpu.pixels` | `GPU_RemainingPixels` | R | int | Pixels the GPU can still draw this frame. |

Methods: `ioports.gpu.clear()`, `ioports.gpu.draw()`,
`ioports.gpu.blending()`, `ioports.gpu.sync()` (see the table above).

**ioports.inp.\* — gamepads**

| Property | Port | Access | Type | Meaning |
|---|---|---|---|---|
| `ioports.inp.gamepad` | `INP_SelectedGamepad` | R/W | int | Gamepad (0–3) the other properties read. Reads give the last value set (the emulators can't read this port back; see [The gamepad port](#keyboard-key--keyp--kbd)). |
| `ioports.inp.status` | `INP_GamepadConnected` | R | bool | Is the selected gamepad connected. |
| `ioports.inp.left`, `right`, `up`, `down` | `INP_GamepadLeft/…` | R | int | D-pad: frames held (> 0) or frames since release (< 0). |
| `ioports.inp.A`, `B`, `X`, `Y`, `L`, `R`, `START` | `INP_GamepadButton*` | R | int | Buttons, same encoding. |
| `ioports.inp.inputs` | (all of the above) | R | int | Every button of the selected gamepad as one bitmask, held = 1: bit 10 left, 9 right, 8 up, 7 down, 6 START, 5 A, 4 B, 3 X, 2 Y, 1 L, 0 R. |

**ioports.spu.\* — sound**

| Property | Port | Access | Type | Meaning |
|---|---|---|---|---|
| `ioports.spu.volume` | `SPU_GlobalVolume` | R/W | float | Master volume. |
| `ioports.spu.channel` | `SPU_SelectedChannel` | R/W | int | Channel (0–15) the `chan*` properties and `cmd()` act on. |
| `ioports.spu.sound` | `SPU_SelectedSound` | R/W | int | Sound (`--#sound` name) the sound properties act on. |
| `ioports.spu.length` | `SPU_SoundLength` | R | int | Length of the selected sound, in samples. |
| `ioports.spu.soundloop` | `SPU_SoundPlayWithLoop` | R/W | bool | Selected sound loops by default. |
| `ioports.spu.loopstart`, `loopend` | `SPU_SoundLoopStart/End` | R/W | int | Loop points of the selected sound, in samples. |
| `ioports.spu.state` | `SPU_ChannelState` | R | int | Selected channel: 0x40 stopped, 0x41 paused, 0x42 playing. |
| `ioports.spu.chansound` | `SPU_ChannelAssignedSound` | R/W | int | Sound assigned to the selected channel. |
| `ioports.spu.chanvolume` | `SPU_ChannelVolume` | R/W | float | Channel volume. |
| `ioports.spu.chanspeed` | `SPU_ChannelSpeed` | R/W | float | Channel playback speed (1.0 = normal). |
| `ioports.spu.chanloop` | `SPU_ChannelLoopEnabled` | R/W | bool | Channel loops. Set **after** `cmd("play")`. |
| `ioports.spu.chanpos` | `SPU_ChannelPosition` | R/W | int | Channel playback position, in samples. |

Method: `ioports.spu.cmd(mode)` / `ioports.spu.command(mode)` —
`"play"`, `"pause"`, `"stop"`, `"resume"`, `"pauseall"`, `"stopall"`,
`"resumeall"`.

**ioports.tim.\*, rng, car, mem — timer, random numbers, cartridge, memory card**

| Property | Port | Access | Type | Meaning |
|---|---|---|---|---|
| `ioports.tim.date` | `TIM_CurrentDate` | R | int | Year × 65536 + day of the year (`system.date()` decodes it). |
| `ioports.tim.time` | `TIM_CurrentTime` | R | int | Seconds since midnight (`system.time()` decodes it). |
| `ioports.tim.frames` | `TIM_FrameCounter` | R | int | Frames since power-on (= `system.frames`). |
| `ioports.tim.cycles` | `TIM_CycleCounter` | R | int | CPU cycles this frame (= `system.cycles`). |
| `ioports.rng.value` | `RNG_CurrentValue` | R | int | Next hardware random number. |
| `ioports.rng.seed` | `RNG_CurrentValue` | W | int | Seeds the hardware generator. |
| `ioports.car.connected` | `CAR_Connected` | R | bool | A cartridge is inserted. |
| `ioports.car.romsize` | `CAR_ProgramROMSize` | R | int | Program ROM size, in words. |
| `ioports.car.numvtex`, `numvsnd` | `CAR_NumberOfTextures/Sounds` | R | int | Textures / sounds in the cartridge. |
| `ioports.mem.connected` | `MEM_Connected` | R | bool | A memory card is inserted. |

Writing a read-only port, reading a write-only one, or an unknown name
(`ioports.gpu.colour`) is a compile error that lists the valid names.

### Standard library

| Library | Functions |
|---|---|
| `math` | `abs acos asin atan atan2 ceil cos cosh deg exp floor fmod frexp ldexp log log10 max min modf pow rad random randomseed sin sinh sqrt tan tanh`, constants `pi huge e` |
| `string` | `byte char find format gsub len lower rep reverse sub upper` (also as methods: `s:sub(1, 3)`) |
| `table` | `concat insert move pack remove sort unpack` |
| operators | `+ - * / % ^ //`, `..`, `#`, `== ~= < > <= >=`, `and or not`, `& | ~ << >>` (see the README) |

Numbers are float32 (24 significant bits); strings that look like numbers
are converted in arithmetic (`"5" + 1` is 6), as in Lua.

---

## Sound: music.\* / sfx.\*

```
music.play(SOUND [, CHANNEL [, LOOP [, VOL [, START]]]])  -> channel used
music.pause  ([CHANNEL])
music.resume ([CHANNEL])
music.stop   ([CHANNEL])
music.playing([CHANNEL])                                  -> boolean
music.volume (VOL [, CHANNEL])

sfx.play(SOUND [, CHANNEL [, VOL [, SPEED]]])             -> channel used
sfx.stop([CHANNEL])
sfx.volume(VOL [, CHANNEL])

ioports.spu.cmd(MODE)   -- raw escape hatch, see below
```

`music` defaults to channel 0. `sfx.play()` with no channel round-robins
over channels 1–15 via one compiler-reserved RAM word
(`VIRCON32_SFX_CURSOR`), so an effect never cuts the music off. `sfx` never
loops: anything sustained is `music.play(..., true)` on its own channel.

`sfx.stop()` with no channel stops channels 1–15 only, deliberately NOT
`StopAllChannels`, which would silence the music too. That is
`__builtin_vircon32_sfx_stop_all`.

The cursor advances unconditionally rather than searching for an idle
channel: searching would cost up to 15 `IN` + compare on the hot path
(`sfx.play()` runs on every jump and footstep) to protect against a case
that only arises when 15 effects overlap, where the oldest is the right one
to lose anyway.

**Vircon32 SPU: the port write order**

*The rule*

```asm
OUT SPU_SelectedChannel, ch
OUT SPU_Command, SPUCommand_StopSelectedChannel   ; 1
OUT SPU_ChannelAssignedSound, snd
OUT SPU_ChannelVolume, R                          ; float port
OUT SPU_Command, SPUCommand_PlaySelectedChannel
OUT SPU_ChannelLoopEnabled, 0|1                   ; 2 - AFTER the command
OUT SPU_ChannelPosition, samples                  ; 3 - AFTER the command
```

Three console behaviours force this. All three fail **silently** — no error,
no rejected port write, just the wrong sound.

**1. A sound only assigns to a STOPPED channel.**
**2 & 3. The play command overwrites loop AND position.**

A loop flag or seek written *before* the command is discarded. Note that the
loop flag is replaced by the SOUND's `PlayWithLoop`, which is false unless
something set `SPU_SoundPlayWithLoop` on that sound — so channel-level
looping only works if written after the command. Write it even when it is 0,
since the command has just replaced it with the sound's flag.

For a **Paused** channel `PlayChannel()` takes neither branch — it only sets
`State = Playing`. That is what makes Play the correct per-channel resume,
and why resume never disturbs position or loop.

*Channel states and what resume actually means*

`channel_stopped 0x40`, `channel_paused 0x41`, `channel_playing 0x42`.
`SPU_ChannelState` is **read-only** (`WriteSPUChannelState` returns false).

There is no `ResumeSelectedChannel` command. `ResumeAllChannels` is literally
a loop calling `PlayChannel()` on every paused channel, so `resume(ch)` =
`PlaySelectedChannel` is the right per-channel equivalent.

**A "resume" that restarts from the beginning means the channel was STOPPED,
not paused.** That is the diagnostic signature of a lost loop flag: the sound
ran to its end, the channel went Stopped, and Play rewound it.

`PauseChannel()` sets `State = Paused` unconditionally — it does *not* check
for an already-stopped channel, despite the C API docs saying pause has "no
effect if already stopped". So pausing a finished channel leaves it Paused at
position 0, and a later resume plays from the start. Guard with a
`SPU_ChannelState == 0x42` check if that matters.

*Port types*

`SPU_ChannelPosition` is an **INTEGER** port — a sample index, clamped by the
console to `0 .. SoundLength-1`. `audio.h` declares
`set_channel_position( int )`, and `WriteSPUChannelPosition()` reads
`Value.AsInteger`. The IOPortMap table had `ioports.spu.chanpos` as
`IOPORT_TYPE_FLOAT`, which wrote raw float bit patterns to it; corrected to
`IOPORT_TYPE_INTEGER`.

Genuine float ports: `SPU_ChannelVolume` (clamped 0–8), `SPU_ChannelSpeed`
(0–128, changes pitch), `SPU_GlobalVolume` (clamped 0–2). NaN/inf writes to
any of these are ignored rather than rejected.

**music.volume(VOL [, CHANNEL]) / sfx.volume(VOL [, CHANNEL])**

Sets playback volume. `VOL` is required. `CHANNEL` has **three** distinct
meanings depending on what the call site writes:

| Call | Meaning |
|---|---|
| `music.volume(VOL)` | apply `VOL` to every channel **this namespace currently owns** (see channel-ownership tracking, below) |
| `music.volume(VOL, -1)` | the real hardware **global** volume (`SPU_GlobalVolume`, clamped 0–2) — every channel, unconditionally |
| `music.volume(VOL, N)` | that one channel's volume (`SPU_ChannelVolume`, clamped 0–8), `N` in 0–15 |

`sfx.volume` behaves identically, against `sfx`'s own tracked channels.

```lua
music.play(MUSIC, 0, true)   -- claims channel 0 for music
sfx.play(BLIP)                -- claims some channel 1-15 for sfx

sfx.volume(0.3)               -- ducks ONLY the sfx channel(s) above;
                               -- channel 0 (music) is untouched
music.volume(0.5)             -- turns music down; sfx is untouched
music.volume(1.0, 0)          -- channel 0 specifically, full volume
sfx.volume(0.0, -1)           -- true global mute, both namespaces
```

Explicit channel numbers (`N` or `-1`) never change ownership — only
`.play()` does that. A paused or stopped channel is still found by the
no-argument "tracked channels" mode; only playing a *different* channel
under the other namespace releases it.

*Channel-ownership tracking*

Two compiler-reserved RAM words, `VIRCON32_MUSIC_CHANNEL_MASK` and
`VIRCON32_SFX_CHANNEL_MASK`, each a bitmask over channels 0–15: bit *N* set
means channel *N* was last assigned a sound by that namespace's `.play()`.
Ownership is exclusive by construction — every `music.play(S, ch)` claims
`ch` for music and clears it from the sfx mask, and every `sfx.play(S, ch)`
does the reverse — since a channel doesn't actually belong to either
namespace at the hardware level, only by convention in how the game's
`.play()` calls have been using it. Both masks start at 0 (nothing
claimed); `music.volume(VOL)`/`sfx.volume(VOL)` with no channel is a no-op
until something has actually played on that namespace.

Only `.play()` touches the masks. `.pause()`, `.resume()`, `.stop()`, and
`.volume()` itself never do — so a channel that's currently paused or
stopped is still "owned" by whoever last played on it, and still gets
picked up by the no-argument volume mode.

*Codegen*

An all-literal call (`music.volume(0.5, 0)`, `sfx.volume(0.0, -1)`) folds
to a straight-line `OUT` sequence at compile time, same as the rest of this
surface. `music.volume(VOL)`/`sfx.volume(VOL)` with no channel argument is
**always** a `CALL` — which channels are currently owned is only known at
runtime — to `__builtin_vircon32_volume_mask`, which loops bits 0–15 of the
namespace's mask and writes `SPU_ChannelVolume` for each set one. Any other
runtime-valued call goes to `__builtin_vircon32_volume`, which checks the
channel value against `-1` (global) at runtime and clamps otherwise.

**Why the bare names went away**

`play` / `pause` / `resume` / `stop` were the four most collision-prone
identifiers a game could want for itself, which is what the old
`resolve_symbol()` step-aside guard in the dispatcher was working around.
They are gone; the namespaces replace them, and the alias mechanism restores
them by choice rather than by default.

**Compile-time aliases**

`play = music.play` records an alias and emits nothing. Later `play(...)`
calls compile to the identical inline OUT sequence — no runtime value, no
CALL, no RAM. The aliasable surface is `music.play`, `music.pause`,
`music.resume`, `music.stop`, `music.playing`, `music.volume`, `sfx.play`,
`sfx.stop`, and `sfx.volume`.

- `register_intrinsic_aliases_prepass()` runs before codegen, so an alias
  declared at the bottom of a file governs a call at the top.
- Resolution happens in `try_emit_call_intrinsic()` immediately after
  `resolve_static_path()`, so an aliased call is indistinguishable from the
  real path everywhere downstream.
- `node_multiple_assignment()` emits nothing for an alias declaration;
  `node_identifier()` errors if one is read as a value.

Limits, all of them deliberate:

- An alias is a NAME, not a VALUE. `{ hit = sfx.play }` or passing it to a
  function is a compile error naming the limitation, not a miscompile.
- Aliases are program-wide. `local p = music.play` compiles but warns —
  the `local` does not scope it.
- Namespace aliasing (`m = music` then `m.play()`) is not supported.
- Alias targets still consume a global RAM word, since
  `register_all_globals_prepass` sees them as assignment targets. One word
  each; not worth destabilizing the symbol table over.

If first-class sound-function values are ever wanted, the precedent is
`__mathfn_sin` / `__mathfn_log` in runtime.s — real labels boxed with
`BOXED_FUNCTION`, resolved in `try_emit_table_get_intrinsic()` where
`math.sin`-as-a-value already is. That would be additive; the alias table
stays as the zero-cost path.

**music.playing() and why a Lua flag is the wrong toggle**

`SPU_ChannelState` is a read-only integer port returning `channel_stopped`
0x40, `channel_paused` 0x41, `channel_playing` 0x42. `music.playing(ch)`
selects the channel, reads it, and returns a real Lua boolean.

A pause/resume toggle built on a Lua flag drifts the moment a sound ends on
its own: the program still believes it is playing, so the next press pauses
an already-stopped channel instead of resuming it. Asking the hardware
cannot drift.

**Codegen: hybrid fold**

All arguments compile-time-known → straight-line `OUT` sequence, no CALL.
Anything dynamic → push and CALL the runtime routine, which does
nil-defaulting, Lua-truthiness decoding and channel clamping. All-or-nothing:
one dynamic argument sends the whole call down the runtime path.

`sfx.play()` additionally requires an *explicit literal* channel to fold,
since the auto path must read and advance the cursor. `sfx.play(BLIP)` —
the common form — is therefore always a CALL, which is also the smaller
emission.

`--#sound` names count as compile-time-known: `node_cart_hint()` already
assigns `MUSIC` its resource id, so `music.play(MUSIC, 0)` emits
`OUT SPU_ChannelAssignedSound, 0` rather than reading the RAM global. The
fold is suppressed when `spu_name_is_rebound()` finds the name assigned to,
used as a loop variable, declared as a parameter, or mentioned in inline asm
anywhere in the AST.

---

## ioports.spu.cmd() — the raw escape hatch

Issues one raw SPU command against whatever `SPU_SelectedChannel` currently
names. No channel selection, no sound assignment, no defaulting — pair it
with the `ioports.spu.*` properties for sequences the intrinsics don't cover
(crossfades, sample-accurate seeking, custom loop points).

It carries the same port-ordering constraints as everything else: set
`chanloop` **after** `cmd("play")`, never before.

Modes: `"play"` 0, `"pause"` 1, `"stop"` 2, `"pauseall"` 3, `"resume"` 4,
`"allstop"` 5, plus aliases `"resumeall"` and `"stopall"`. Omitted or nil →
`"play"`.

---

## Boolean IO ports

A Lua boolean is not a float. `true`/`false`/`nil` are NaN-boxed bit
patterns; the hardware ports trade in integers 0 and 1. Writes decode Lua
truthiness (only `nil` and `false` are falsy), with literals folding to a
bare 0/1 immediate. Reads branch to `BOXED_TRUE`/`BOXED_FALSE`.

Affects `ioports.spu.chanloop`, `ioports.spu.soundloop`,
`ioports.inp.status`, `ioports.car.connected`, `ioports.mem.connected`.

Boolean ports return `true`/`false`, not `1.0`/`0.0`. Arithmetic on one
needs rewriting as `if p then 1 else 0`.

---

## System: system.\*

```
system.wait()   -> nil   (WAIT for the next new-cycle signal)
system.halt()   -> nil   (HLT -- stops the CPU)
system.date()   -> string, year, month, day
system.time()   -> string, hour, minute, second
```

**system.wait() / system.halt()**

`system.wait()` compiles straight to `WAIT` — the same instruction
`ioports.gpu.sync()` uses, and interchangeable with it; both just wait for
the timer's next new-cycle signal. `system.halt()` compiles to `HLT`,
stopping the CPU outright — for a program that's completed its work and
has nothing left to render.

**system.date() / system.time()**

Both decode the timer chip's real-time clock (see Vircon32 System
Specification Part 7, section 1.2 — this is an actual wall-clock/RTC, not
a monotonic since-boot counter) and return **four** values: a formatted
string, then the three numeric components.

```lua
local date_str, year, month, day     = system.date()   -- "2026-09-06", 2026, 9, 6
local time_str, hour, minute, second = system.time()    -- "03:00:04", 3, 0, 4
```

`system.date()`'s string is `"YYYY-MM-DD"`; `system.time()`'s is
`"HH:MM:SS"`. Both are always zero-padded to a fixed width (`printf`'s
`%0*d`, not a hard cap) — `year` is padded to 4 digits but never truncated,
so a year past 9999 (up to the hardware's `CurrentYear` max of 65535)
still prints in full, just wider than 4 characters; month/day/hour/
minute/second are always exactly 2 digits. Leap years use the standard
Gregorian rule (divisible by 4, except centuries unless divisible by
400) — the spec confirms the day-count range extends to 365 in a leap
year but doesn't itself define the rule, so this is the one sane,
universal reading of it. There is no `os.time()`/`os.date()` format-string
or table-construction support — this is a fixed-shape decode of the
hardware register, not a general date library.

**system.frames / system.cycles**

```lua
local f = system.frames()   -- TIM_FrameCounter -- frames since power-on
local c = system.cycles()   -- TIM_CycleCounter -- CPU cycles since this frame began
```

Both are read-only hardware counters, and neither is wall-clock time.
`system.frames()` counts frames since power-on; `system.cycles()` counts
CPU cycles since the current frame began and restarts at 0 every frame,
so reading it just before `system.wait()` shows how much of the frame's
CPU budget the frame used. `system.frames()` is the natural fit for "every
N frames, do X" timing (this is exactly what the tilemap scroll demo uses
to pace its scroll speed) since it free-runs regardless of what the
program does, unlike a hand-rolled counter variable
that has to be remembered and incremented every frame. Both are also
reachable as raw ports (`ioports.tim.frames`, `ioports.tim.cycles`) — see
[Other raw IO ports](#other-raw-io-ports) — the `system.*` names are
identical, just under the more discoverable namespace.

---

## Graphics: spr()

```
spr(region_id, x, y [, scale_x [, scale_y [, angle_deg [, color_mult [, blend_mode]]]]])
```

Draws GPU texture region `region_id` (as declared by a `--#texture` hint,
or a raw region index) at pixel position `(x, y)`.

| Arg | Default | Notes |
|---|---|---|
| `region_id` | required | GPU region index (`GPU_SelectedRegion`) |
| `x`, `y` | required | top-left draw position, `GPU_DrawingPointX/Y` |
| `scale_x`, `scale_y` | `1.0` | independent X/Y scale factors |
| `angle_deg` | `0` | rotation, **degrees**, counter-clockwise; converted to radians internally (console's `GPU_DrawingAngle` is radians) |
| `color_mult` | `0xFFFFFFFF` | packed RGBA multiply color — `0xFFFFFFFF` is "no change" |
| `blend_mode` | `"alpha"` (`0x20`) | a mode name string or its numeric value — see blend modes below |

An argument can be **omitted** (just stop supplying trailing arguments) or
passed as an **explicit `nil`** to skip it and reach a later one —
`spr(id, x, y, nil, nil, 45)` to rotate without touching scale — both mean
"use the default."

Blend modes — pass either the name string or the number:

| String | Number | Effect |
|---|---|---|
| `"alpha"` or `"default"` | `0x20` | normal alpha blending (the default) |
| `"add"` | `0x21` | additive — brightens what's underneath |
| `"subtract"` | `0x22` | subtractive — darkens what's underneath |

```lua
spr(7, 100, 80, nil, nil, nil, nil, "add")       -- glow / light effect
spr(7, 100, 80, nil, nil, nil, nil, 0x21)        -- same thing, numeric
spr(7, 100, 80, nil, nil, nil, 0x80FFFFFF, "alpha")
```

A mode string must be a **string literal**; it's resolved to its number at
compile time, and any other string (`"multiply"`, a typo) is a compile
error. A string held in a variable is not recognized (there's no runtime
string dispatch — it would reach the GPU as a pointer, not a mode); keep
the mode in a variable as a number instead (`local mode = 0x21`). Numbers
are passed through as-is, as before.

`spr()` returns nothing (Lua `nil`), matching the console having no
meaningful value to hand back from a draw call. More than 8 arguments is a
compile-time warning; the extras are ignored.

**Runtime dispatch, not compile-time fold**

Unlike the sound API, `spr()` always calls `__builtin_vircon32_spr` — there
is no straight-line-`OUT` fast path for a fully-literal call. The routine
reads the actual runtime values of `scale_x`/`scale_y`/`angle_deg` on
*every* call and picks the cheapest of the four GPU draw commands each
time:

| Condition | Command |
|---|---|
| scale = 1,1 and angle = 0 | `GPUCommand_DrawRegion` |
| scale ≠ 1 and angle = 0 | `GPUCommand_DrawRegionZoomed` |
| scale = 1,1 and angle ≠ 0 | `GPUCommand_DrawRegionRotated` |
| scale ≠ 1 and angle ≠ 0 | `GPUCommand_DrawRegionRotozoomed` |

`color_mult` and `blend_mode` are written unconditionally on every call,
before that dispatch — `GPU_MultiplyColor` and `GPU_ActiveBlending` are
persistent GPU state every draw variant consults, unlike
`GPU_DrawingScaleX/Y`/`GPU_DrawingAngle`, which are only written in the
branches that actually use them (harmless to leave stale, since e.g.
`DrawRegionRotated` is defined to ignore scale entirely).

`color_mult` is a packed `0xAABBGGRR` word and is written to
`GPU_MultiplyColor` as-is, without a float → integer conversion (the same
model as `ioports.gpu.clear(color)`). A numeric literal (`0xFFFFFFFF`,
`0x80FFFFFF`, `-1`) is folded to that word at compile time. Any other
expression must already hold the packed word: `rgba(r, g, b [, a])`
(see [Colors: rgba()](#colors-rgba)), `hex("0xFF8080FF")`, or a variable
assigned from one of them. A plain number computed at runtime is *not*
converted — float32 can't hold a 32-bit color exactly anyway. For a color
that changes at runtime (a fade), keep the components as numbers and pack
them at the draw:

```lua
spr(REGION_SOLID, x, y, w, h, 0, rgba(0, 0, 0, frame * 8))   -- fade to black
```

An explicitly-passed `nil` for an optional argument (e.g.
`spr(id, x, y, nil, nil, 45)`) is treated identically to that argument
being omitted entirely — both fall back to the default. A call sitting in
an expression context (`local unused = spr(1, 10, 10)`) correctly gets
`nil` assigned, matching every other intrinsic in this file.

<a id="gpu-clear"></a>
**ioports.gpu.clear([color]) / ioports.gpu.clear(r, g, b [, a])**

Clears the screen: writes `GPU_ClearColor` (if a color is given) then
issues `GPUCommand_ClearScreen`. Omit the arguments to clear with whatever
`GPU_ClearColor` currently holds. The color can be given four ways:

| Form | Example | Notes |
|---|---|---|
| preset name | `clear("black")` | `"black"`, `"white"`, `"blue"`, `"red"`, `"green"` — string literal, resolved at compile time; any other name is a compile error |
| packed literal | `clear(0xFF202020)` | `0xAABBGGRR`; folded at compile time to the raw 32-bit word |
| packed word | `clear(rgba(32, 32, 32))`, `clear(hex("0xFF202020"))`, `clear(c)` | a non-literal value is written to the port untouched, so it must already hold the raw word — i.e. come from `rgba()` or `hex()` |
| components | `clear(32, 32, 32)`, `clear(r, g, b, 128)` | red, green, blue, alpha, each `0`–`255`; alpha is optional and defaults to `255` (opaque) |

```lua
ioports.gpu.clear("black")
ioports.gpu.clear(0xFF202020)       -- packed 0xAABBGGRR, dark grey
ioports.gpu.clear(32, 32, 32)       -- the same dark grey, as components
ioports.gpu.clear(r, g, b)          -- variables work too; alpha = 255
ioports.gpu.clear(0, 0, 64, 128)    -- half-transparent dark blue
ioports.gpu.clear()                 -- reuses the last ClearColor set
```

Note the GPU's byte order is `0xAABBGGRR` — red is the *low* byte — which
is the main reason the component form exists: `clear(r, g, b)` packs it in
the right order for you.

The component form accepts 3 or 4 arguments (2, or more than 4, is a
compile error). When every component is a literal it folds to a single
packed constant at compile time — out-of-range literals are clamped to
`0`–`255` with a warning. Otherwise each component is evaluated as an
ordinary expression, clamped to `0`–`255`, truncated to an integer, and
packed at runtime. An explicit `nil` for `a` means opaque, like leaving it
out, and so does an alpha that is `nil` at runtime; there is no runtime
nil check on red, green and blue, so a variable that is `nil` there gives
an undefined color.

*Why a packed variable needs `rgba()` or `hex()`:* v32lua numbers are
float32, so a number like `0xFF202020` stored in a variable holds a float,
not the color bits, and `clear()` can't tell the two apart at runtime.
Literals written directly in the call are fine, because they're folded at
compile time.

<a id="colors-rgba"></a>
**Colors: rgba(r, g, b [, a])**

Returns the GPU's packed `0xAABBGGRR` word for a color — the raw 32-bit
word, *not* a Lua number — for anything that takes one: `spr()`'s
`color_mult`, `ioports.gpu.clear(color)`, `ioports.gpu.multiply`,
`ioports.gpu.bgcolor`.

```lua
spr(id, x, y, 1, 1, 0, rgba(255, 255, 255, alpha))   -- fade in/out
ioports.gpu.multiply = rgba(r, g, b)                 -- no float conversion
ioports.gpu.clear(rgba(16, 16, 48))
```

* 3 or 4 arguments (any other count is a compile error). Alpha defaults
  to 255; `nil` alpha (literal or at runtime) is 255 too.
* Each component is clamped to `0`–`255` and truncated (`127.9` → 127),
  exactly like `clear(r, g, b [, a])`, whose packing code it shares.
* All-literal arguments fold at compile time to one constant
  (`rgba(1, 2, 3, 4)` is `0x04030201`); out-of-range literals are clamped
  with a warning. Otherwise it packs at runtime; components that call
  functions are safe.
* Native Vircon32 mode only. A function of your own named `rgba` takes
  precedence.

**Caveat — keep the components, not the word.** A raw word whose top bits
match one of the language's value tags *is* that value to the rest of the
program: `rgba(0, 0, 192, 255)` is `0xFFC00000`, which is `nil`, and
`0xFF8xxxxx` reads as a table. Passing the result straight to a call or a
port is always safe (it is only copied). Storing it in a table (a `nil`
value deletes the key), testing it (`if c then`), or comparing it with
`nil` is not. `hex()` has the same issue. The safe idiom is to keep the
components as numbers and call `rgba()` where the color is used, as in
the examples above.

<a id="colors-color"></a>
**Colors: color(n)**

Turns a number that holds a packed `0xAABBGGRR` color into the raw word,
for colors you have as a number rather than as components: one computed
with arithmetic, read from a table of colors, or loaded from the memory
card.

```lua
local palette = { 0xFF1D2B53, 0xFF7E2553, 0xFF008751 }
ioports.gpu.multiply = color(palette[i])
spr(id, x, y, 1, 1, 0, color(base + fade * 0x01000000))
```

* One argument (any other count is a compile error; a string, `nil` or
  boolean literal is too).
* The number is floored and wrapped into 32 bits, so negative numbers
  give their two's-complement word (`color(-1)` is `0xFFFFFFFF`). Values
  outside `[-2^31, 2^32)` saturate.
* A literal folds at compile time and is exact: `color(0x802040FF)` is
  `0x802040FF`.
* At runtime the number is a float32, which holds only 24 significant
  bits, so a color whose bits span more than 24 is rounded before
  `color()` sees it: a variable holding `0x802040FF` gives `0x80204100`.
  Colors with alpha `0xFF` and many other common values are exact
  (`0xFF003366`, `0x80FFFFFF`), but when the exact bits matter, keep
  the components and use `rgba()`.
* Same caveat as `rgba()` about words that look like `nil` or a table.
* Native Vircon32 mode only. A function of your own named `color` takes
  precedence (PICO-8's `color()` is PICO-8's own function).

<a id="integer-ports-and-literals"></a>
**Integer ports and literals**

A number written to an integer port (`ioports.gpu.x`, `bgcolor`,
`multiply`, …) is converted with `CFI`, truncating toward zero. A
**numeric literal** is instead written as its exact 32-bit word, computed
at compile time: `ioports.gpu.bgcolor = 0xFF003366` stores `0xFF003366`
(a float conversion would saturate it), `ioports.gpu.x = -5` stores `-5`,
and `ioports.gpu.y = 12.7` stores `12`. Literals outside `[-2^31, 2^32)`
saturate with a warning.

**Defining texture regions**

`spr()`'s `region_id` doesn't refer to anything until a region has actually
been carved out of a loaded texture. There is no compiler-side region
authoring — this is six raw port writes, normally done once in `init()`
(or once per texture at the top of `main()` if there's no separate
`init()`), one region at a time:

```lua
ioports.gpu.texture = SPRITES   -- select which loaded texture this region cuts from
ioports.gpu.region  = 1         -- select region SLOT 1 to define (this is the id spr() will use)
ioports.gpu.minX = 6            -- top-left corner of the region, in texture pixels
ioports.gpu.minY = 156
ioports.gpu.maxX = 58           -- bottom-right corner, inclusive
ioports.gpu.maxY = 208
ioports.gpu.hotX = 6            -- see below -- NOT 0
ioports.gpu.hotY = 156          -- see below -- NOT 0
```

*Region HotSpot considerations and compiler behaviours*

While Region HotSpots give us the ability to render regions relative to a
set of hotspot coordinates, forgetting to set them can result in rendering
issues, as unset hotspot coordinates may default to 0, 0. If far enough
away from your region's defined X and Y extrema, your region may not end
up rendering where you want it, or on the screen at all.

For this reason, `v32lua` adopts an auto-setting of `ioports.gpu.hotX` and 
`ioports.gpu.hotY`, so any neglected hot spot coordinates on region
definition would still result in a visible region rendering:

When setting a regions's minimum X and Y, the corresponding hotspot X and
Y will be set to the exact same values. This way, a default of a "top-left"
hotspot coordinates will occur.

Should you wish to set your hotspot coordinates to something other than 
the regions top-left, simply set them AFTER you establish the minimum X 
and Y.

`GPU_RegionMinX/MinY/MaxX/MaxY/HotSpotX/HotSpotY` are the raw ports behind
`ioports.gpu.minX` etc. — see the full port table in
[Other raw IO ports](#other-raw-io-ports) for everything else `ioports.gpu.*`
exposes (drawing point, scale, angle, multiply color, blending, and the
read-only `ioports.gpu.pixels` GPU-busy counter).

---

## Graphics: rect() / rectfill()

```
rect(x1, y1, x2, y2 [, color])       -- 1-pixel outline
rectfill(x1, y1, x2, y2 [, color])   -- filled
```

`(x1, y1)` and `(x2, y2)` are opposite corners, both **inclusive**, in any
order: `rectfill(10, 20, 19, 24)` covers 10 × 5 pixels, columns 10–19 and
rows 20–24, and `rectfill(19, 24, 10, 20)` is the same rectangle.
Coordinates are floored (`rectfill(9.8, ...)` starts at column 9); `nil` or
a non-number counts as 0. One corner equal to the other draws one pixel.

`color` is a packed `0xAABBGGRR` word, exactly like `spr()`'s
`color_mult`: a literal (`0xFF0000FF`), `rgba()`, `color()`, `hex()`, or a
variable holding one of those. Absent or `nil`: opaque white. A color with
alpha below 255 blends with the current blending mode
(`ioports.gpu.blending`), which `rect()` leaves as it is.

```lua
rectfill(0, 0, 639, 359, rgba(0, 0, 64))      -- whole screen, dark blue
rect(100, 50, 199, 99, 0xFF00FFFF)           -- yellow frame, 100 x 50
rectfill(px, py, px + 15, py + 15, rgba(255, 0, 0, 128))   -- translucent red
```

**How it draws**

A program that calls `rect` or `rectfill` gets a small texture of its own:
4 × 4 opaque white pixels, added to the cartridge **after** every
`--#texture` (so your texture numbers don't move; `ioports.car.numvtex`
counts it). Region 0 of it is one white pixel; `rectfill()` is **one**
zoomed draw of that region at scale (width, height), tinted with the
multiply color — exact to the pixel for any size. `rect()` is up to 4 draws
that don't overlap (top and bottom edges full width, the sides between
them), so a translucent outline isn't darker at the corners.

The GPU state the call uses is put back afterwards: selected texture and
region, multiply color, drawing scale. A `rect()` can sit in the middle of
`ioports.gpu.*` drawing code without disturbing it.

Each draw costs GPU pixels like any other (`ioports.gpu.pixels`), plus the
GPU's scaling penalty; a full-screen `rectfill()` is a full screen of
pixels.

A function of your own named `rect` or `rectfill` replaces the built-in,
as with every intrinsic. Under `--#api pico8` the two names are PICO-8's
palette-color versions (see [PICO8.md](PICO8.md)); under `--#api tic80`,
`rect(x, y, w, h, color)` / `rectb(...)` are TIC-80's (see
[TIC80.md](TIC80.md)).

---

## Input: btn() / btnp()

```
btn(id [, player])   -> boolean, currently held down
btnp(id [, player])  -> boolean, true only on the frame it was first pressed
```

`player` selects a gamepad 0–3 (`INP_SelectedGamepad`); omitted or `nil`
uses whichever gamepad is already selected without writing the port.

**Button IDs**

Vircon32 hardware order, not PICO-8's or TIC-80's:

| id | Button | IOPort |
|---|---|---|
| 0 | Left | `INP_GamepadLeft` |
| 1 | Right | `INP_GamepadRight` |
| 2 | Up | `INP_GamepadUp` |
| 3 | Down | `INP_GamepadDown` |
| 4 | Start | `INP_GamepadButtonStart` |
| 5 | A | `INP_GamepadButtonA` |
| 6 | B | `INP_GamepadButtonB` |
| 7 | X | `INP_GamepadButtonX` |
| 8 | Y | `INP_GamepadButtonY` |
| 9 | L (left shoulder) | `INP_GamepadButtonL` |
| 10 | R (right shoulder) | `INP_GamepadButtonR` |

An `id` outside 0–10, or an unmapped combination, returns `false` rather
than erroring — there's no OS-level error path available on this target
(see `pcall`/`error`/`assert` in the compiler's deferred-features list).

**btn(): direct polling**

`__builtin_vircon32_btn` reads the mapped `INP_Gamepad*` port for the
selected gamepad and returns `true` when the hardware reports it pressed
(`>= 1`).

**btnp(): edge detection**

`btnp()` needs state the hardware doesn't track on its own: "was this
button not pressed last frame, and is it pressed now." That state lives in
`VIRCON32_BTN_PREV_STATE`, a fixed, compiler-reserved 44-word RAM range —
one word per (player, button) pair, `player * 11 + button_id` — updated on
every `btnp()` call regardless of the result. Only a genuine
not-pressed → pressed transition returns `true`; a button held across
multiple frames returns `true` once, then `false` on every subsequent
frame until it's released and pressed again.

An out-of-range `player` (an explicit value outside 0–3) is clamped to
0–3 before being used as an index into that 44-word table, rather than
being allowed to compute an address outside it.

**ioports.inp.inputs — one-word bitmask**

```lua
local mask = ioports.inp.inputs   -- current gamepad, all 11 buttons in one read
```

Reads every `INP_Gamepad*` port for whichever gamepad is currently selected
(`ioports.inp.gamepad`) and collates them into a single 11-bit number in one
shot, instead of eleven separate `btn()` calls. Bit layout, MSB to LSB:

| Bit | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Button | Left | Right | Up | Down | Start | A | B | X | Y | L | R |

Each bit is `1` if that button currently reads pressed (`> 0`), same
"currently held" semantics as `btn()` — this is a held-state snapshot, not
an edge-triggered one; there's no bitmask equivalent of `btnp()`. Useful for
passing a whole frame's input as one value (e.g. into a replay/input log)
rather than for everyday per-button game logic, where `btn()`/`btnp()` read
more clearly.

**What's intentionally NOT here**

- No bitfield/"any button" form (`btn()` with no arguments) the way
  PICO-8's does — every call names a specific button.
- No analog stick or trigger-pressure reporting; Vircon32's gamepad model
  is digital per the IOPort list above.
- No rumble/vibration output port exists on the console to expose.

These match the underlying Vircon32 hardware rather than PICO-8/TIC-80
conventions; that emulation lives entirely in the `--#api pico8`/`--#api tic80`
compatibility layers, not here.

---

## Keyboard: key() / keyp() / kbd.\*

```
key([k])                      -> boolean, k held (no k: any key held)
keyp([k [, hold, period]])    -> boolean, k went down this frame (+ autorepeat)
kbd.read()                    -> next typed character (a number), or nil
kbd.event()                   -> next event: +code pressed, -code released, or nil
kbd.port([n])                 -> gamepad port of the keyboard (and sets it)
kbd.capslock()                -> boolean, caps lock on
kbd.connected()               -> boolean, something is plugged into that port
kbd.clear()                   -- forget the events not read yet
```

These read a full keyboard through a **v32kbd** device: a USB keyboard
gadget the console sees as an ordinary gamepad, whose 11 controls carry key
events instead of buttons (see the v32kbd project). It plugs into a gamepad
port — **port 1 (the second) by default**, leaving port 0 for a regular
gamepad. Change it with `--keyboard N` on the command line, a `--#keyboard N`
hint in the source, or `kbd.port(n)` at run time.

`key()`/`keyp()` follow TIC-80's: same names, same rules, with v32kbd key
codes. Under `--#api tic80` the same two calls take TIC-80's own key codes
(see [TIC80.md](TIC80.md#input)); `kbd.*` works under every API. A global
of your own named `kbd` (a table you assign) replaces the `kbd.*` built-ins.

**Key codes**

A code names a **key**, not a character: the keys that type a character
use it unshifted, US layout — `'a'`–`'z'` (97–122), `'0'`–`'9'` (48–57),
space (32) and `` ` - = [ ] \ ; ' , . / `` — and the others:

| Code | Key | Code | Key |
|---|---|---|---|
| 1 | Up | 11 | Right Ctrl |
| 2 | Down | 12 | Left Alt (Option) |
| 3 | Left | 13 | Enter |
| 4 | Right | 14–25 | F1–F12 |
| 5 | Caps Lock | 26 | Right Alt (Option) |
| 6 | Left Shift | 27 | Escape |
| 7 | Right Shift | 28 | Left GUI (Command, Windows) |
| 8 | Backspace | 29 | Right GUI |
| 9 | Tab | 127 | Delete |
| 10 | Left Ctrl | | |

Numeric keypad keys report the same codes as their main-keyboard
equivalents.

`k` can also be a **string literal**, turned into the code at compile
time: one character (`"a"`, `"/"`, `" "`; a shifted character names its
key, so `"A"` is the a key and `"!"` the 1 key), or a name — `up` `down`
`left` `right` `enter` (`return`) `tab` `space` `backspace` `delete`
(`del`) `escape` (`esc`) `capslock` `lshift` `rshift` `lctrl` `rctrl`
`lalt` `ralt` `lgui` `rgui` `f1`–`f12`, case-insensitive. Four names mean
either side: `shift`, `ctrl`, `alt`, `gui` (`key("shift")` is true while
either Shift is held). An unknown name is a compile error. Only literals
are folded: a string held in a variable is not a key (`false`).

```lua
function game_loop()
    if key("left")  then x = x - 2 end
    if key("right") then x = x + 2 end
    if keyp("space") then fire() end
    if key("ctrl") and keyp("s") then save() end
    if keyp("down", 20, 4) then menu_next() end   -- repeats while held
end
```

**key([k]), keyp([k [, hold, period]])**

`key(k)` is true while the key is held. `keyp(k)` is true on the frame it
goes down; with `hold` and `period` both given and ≥ 0, it is also true
while the key stays held, from `hold` frames on, every `period` frames
(`period` 0: every frame) — counting the frames after the first, as
TIC-80's `keyp` and `btnp` do. There is no default autorepeat. Without `k`,
`key()` is "any key held" and `keyp()` "any key went down this frame". A
code with no key behind it is `false`.

**Typed text: kbd.read()**

```lua
local text = ""
function game_loop()
    local c = kbd.read()
    while c do
        if c == 8 then                          -- Backspace
            text = string.sub(text, 1, -2)
        elseif c >= 32 and c < 127 then
            text = text .. string.char(c)
        end
        c = kbd.read()
    end
    print(0, 0, text .. "_")
end
```

`kbd.read()` returns the next key **press** as the character it types,
with Shift and Caps Lock applied as they were when the key went down
(`"A"`, `"!"`, `"{"` ... as numbers, matching the BIOS font), and keys
with no character as their code (Enter 13, Backspace 8, arrows 1–4...).
Releases are skipped. `nil` when nothing is left.

`kbd.event()` returns every event instead, presses and releases, as the
key code with no Shift applied: positive for a press, negative for a
release (`-97`: the a key went up). Both read the same queue — use one or
the other. The queue holds 64 events; past that, new ones are dropped
until it is read (`kbd.clear()` empties it — the held keys `key()` sees
are not affected).

**kbd.port([n]), kbd.capslock(), kbd.connected()**

`kbd.port(n)` moves the keyboard to gamepad port `n` (0–3, clamped) and
starts over: held keys, queued events and Caps Lock are forgotten, and the
device's current state is taken as the starting point. It returns the port;
`kbd.port()` only returns it. `kbd.capslock()` is the Caps Lock state, kept
by counting its presses (it starts off). `kbd.connected()` is true when
something is plugged into the keyboard's port.

**Reading every frame**

The device reports at most one key event per frame and holds it until the
next one, so it has to be read **on every frame** or events are lost. The
compiler arranges that when the program uses the keyboard:

- every `key`/`keyp`/`kbd.*` call reads the device (once per frame);
- the `game_loop()` and TIC-80 `TIC()` drivers read it before each frame;
- `system.wait()` and `ioports.gpu.sync()` read it before their `WAIT`
  (what arrives then counts for the next frame, so `keyp()` still sees it).

So a `main()` loop that waits with `system.wait()` loses nothing, even if
it only looks at the keyboard now and then. A bare `__rawasm__("WAIT")`
skips that read. Nothing of this is in a program that doesn't use the
keyboard.

**The gamepad port**

The keyboard's port is read without disturbing the gamepad the program has
selected: `btn()`, `btnp()` and `ioports.inp.*` keep reading the gamepad
they read before. Don't read the keyboard's port with `btn()` — its
"buttons" are key-code bits.

The selected gamepad is remembered by the runtime (`V32IO_GAMEPAD`) rather
than read back from `INP_SelectedGamepad`: the Vircon32 emulators return a
wrong value when that port is read. `ioports.inp.gamepad` reads give the
remembered value too. A `__rawasm__` write to the port bypasses it.

---

## Tilemap: tilemap.\*

```
tilemap.get(NAME, x, y)        -> number or nil (out of bounds)
tilemap.set(NAME, x, y, v)     -> v (out-of-bounds write is a silent no-op)
tilemap.render(NAME, sx, sy, w, h, x, y, tile_w, tile_h [, skip_id])
```

`NAME` is always a bare `--#tilemap`-declared identifier, resolved entirely
at compile time — never a runtime value, the same restriction (and the same
reason) `--#sound`/`--#texture` names have: there's nothing sensible for a
dynamically-computed name to resolve against, since the whole point is that
the compiler knows the tilemap's width/height and ROM location by name
before any code runs.

Unlike `--#texture`/`--#sound`, a tilemap is **not** a cart-XML resource —
no `<textures>`/`<sounds>` entry, no resource id baked into generated code.
Its data is embedded as literal values directly in the assembled program.

**--#tilemap NAME "file" and the CSV format**

```lua
--#tilemap LEVEL1 "level1.csv"
```

The file is plain text: rows of comma-separated tile ids, one row per
line. Row count becomes the tilemap's height; the first row's value count
becomes its width, and every other row must match that count exactly or
it's a compile error — a ragged map silently reading garbage past a short
row is worse than refusing to build. A tile id is just a number; there's no
required meaning, but the natural one (and the one `tilemap.render()`
assumes) is a GPU region id, ready to hand to `spr()`.

This format is deliberately plain enough that Tiled's **Export As... CSV**
(per-layer) output can be used directly with no conversion step — no TMX/
TSX parsing anywhere in this compiler.

**tilemap.get() / tilemap.set()**

```lua
local id = tilemap.get(LEVEL1, 4, 2)   -- tile at column 4, row 2
tilemap.set(LEVEL1, 4, 2, 99)          -- overwrite it
```

Both are 0-indexed, `(x, y)` = `(column, row)`. `tilemap.get()` out of
bounds (either axis, either direction) returns `nil`, the same as reading
past the end of a Lua table. `tilemap.set()` out of bounds is a silent
no-op — there's no sensible value to hand back for "you tried to write
nowhere," so it just declines, mirroring how the TIC-80 compatibility
layer's `mset()` already treats an out-of-range write.

Values are stored and returned as plain numbers with **no clamping** —
unlike the TIC-80 layer's `mset()`, which clamps to 0–255 because TIC-80
sprite ids are byte-sized. A tile value here is just whatever the calling
code wants it to mean, typically a GPU region id, which can run well past
255.

**Lazy ROM-to-RAM promotion**

A tilemap starts life read-only, sitting wherever the compiler placed its
data in the program image — `tilemap.get()` before any write reads directly
from there, at no RAM cost. The **first** `tilemap.set()` against a given
tilemap promotes it: allocates a private RAM copy and copies every cell
across, and only after that does the tilemap become mutable. Every read or
write to a *different* tilemap that hasn't been promoted is unaffected —
promotion is tracked per tilemap, not globally. A second and later
`tilemap.set()` on an already-promoted tilemap writes straight through,
without re-copying or disturbing earlier writes.

**tilemap.render()**

```lua
tilemap.render(LEVEL1, sx, sy, w, h, x, y, tile_w, tile_h)
tilemap.render(LEVEL1, sx, sy, w, h, x, y, tile_w, tile_h, skip_id)
```

Draws a `w`-by-`h` region of cells, starting at tilemap cell `(sx, sy)`, to
the screen starting at pixel `(x, y)`, `tile_w`/`tile_h` pixels apart per
cell — one `spr(tile_value, screen_x, screen_y)` call per visible cell,
read-only (never promotes). `sx`/`sy` are clamped to `0 .. max(0,
dimension - w_or_h)`, the same clamping philosophy the TIC-80 compatibility
layer's `map()` already uses, so a scroll position can be walked past the
map's true edge without drawing garbage or needing the caller to clamp it
first.

`tile_w`/`tile_h` are **required**, unlike TIC-80's `map()`, which assumes
a fixed 8×8 grid — this API has no equivalent assumption to fall back on,
since GPU regions can be any size. They control only the pixel *spacing*
between drawn cells; `render()` draws every region at its own native size
regardless of `tile_w`/`tile_h`, so a region narrower or shorter than the
pitch sits flush against one edge of its cell rather than being stretched
to fill it.

`skip_id` (optional) — a cell whose value equals `skip_id` gets no
`spr()` call at all, useful for a sparse map where most cells are "nothing
here." This is a coarser mechanism than TIC-80 `map()`'s colorkey
transparency (which blends per-pixel); native regions already carry real
alpha, so the common need is just "don't bother drawing this cell,"
not "draw it but blend certain pixels away."

**Scrolling is cell-granularity, not sub-pixel.** `sx`/`sy` are cell
indices; there's no fractional source offset anywhere in the design, so
walking `sx` by 1 moves the drawn content by one full `tile_w` on screen —
the same limitation TIC-80's own `map()` has. Smooth pixel scrolling would
need drawing one extra row/column beyond `w`/`h` and shifting the whole
block's screen origin by a sub-tile pixel remainder; that's a real,
separate extension, not implemented here.

**What's intentionally NOT here**

- No sub-pixel/smooth scrolling — see above.
- No `mget()`/`mset()`/`map()` naming — those names belong to the TIC-80
  compatibility layer; this is a distinct, native surface, not an
  extension of it.
- No multi-layer support — one `--#tilemap` hint is one flat grid. Layering
  is a caller-side concern (declare several tilemaps, render them in order).
- No collision/query helpers beyond `tilemap.get()` itself — checking "is
  this a wall" is just comparing the returned tile id.

---

## Memory card: memcard.\*

```
memcard.save(value, position)   -> value   (raw write, exactly 1 word)
memcard.save(value)             -> value   (auto-append; see below)
memcard.load(position)          -> value   (raw read, exactly 1 word)
memcard.load()                  -> value   (position 0)
memcard.load_table(position)    -> table or nil   (see Tables, below)
memcard.title(str)              -> nil     (sets the 20-word title)

memcard[position]                  == memcard.load(position)
memcard[position] = value          == memcard.save(value, position)
```

The memory card is a real Vircon32 hardware peripheral: a fixed, persistent
storage range at physical address `0x30000000`, entirely separate from the
cartridge ROM and from Vircon32 RAM. Unlike RAM, it survives a power cycle
— it is the console's save-game device.

**This VM is word-addressed throughout**, and the memory card follows the
same convention: an address (and a `position`) advances by whole 4-byte
words, not individual bytes. This matches how this VM already stores Lua
strings internally — one word per character (see `string.len()`) — rather
than a byte-packed representation.

**memcard.save() / memcard.load()**

There are two distinct forms, chosen by whether a `position` is given:

**With an explicit `position`** — the low-level primitive. Writes (or
reads) exactly one raw word at `position`, with no bookkeeping of any
kind. `position 0` is the first word of the data region; see
**Address layout** below for the full range, including how
negative positions reach into the title. You are fully responsible for
knowing what you put where — writing the same position twice simply
overwrites it.

```lua
memcard.save(1234, 0)     -- word 0: raw number
memcard.save(true, 1)     -- word 1: raw boolean
local hi = memcard.load(0)  -- 1234
```

**With no `position` at all** — `memcard.save(value)` auto-appends through
a persistent cursor stored *on the card itself* (not in RAM), so repeated
no-position saves keep extending a log across many play sessions instead
of overwriting word 0 every run. This form is type-aware: saving a real
Lua string writes its full contents (tagged and length-prefixed, see
**Type tags**), not just a raw pointer.

```lua
memcard.save("high score run")   -- appended at the current cursor
memcard.save(9001)               -- appended right after it
```

The cursor itself — "how many words have been auto-appended so far" — is
readable at any time as `memcard.load(-1)` / `memcard[-1]`; there is no
separate counting function.

`memcard.load()` with no `position` always reads word 0 — it does **not**
follow the auto-append cursor the way `memcard.save()` does. Reading back
an entry written by the auto-append form means reading its tag word
yourself at a known position (see **Type tags**),
or simply knowing what you wrote there.

**memcard[position]**

`memcard[position]` and `memcard[position] = value` are shorthand for the
explicit-position form of `load`/`save` above — never the auto-append
form, since Lua's bracket syntax has no "no index" spelling.

```lua
memcard[0] = 1234
local hi = memcard[0]        -- 1234
local cursor = memcard[-1]    -- reads the auto-append cursor
```

**memcard.title(str) -> nil**

Sets the memory card's title — up to 20 characters, one word per
character, matching this VM's internal string representation. Longer
strings are truncated; shorter strings are zero-padded. This is
independent of any `--#title` cart hint, which names the *cartridge*, not
the *save data* — a single cart can have many memory cards in circulation,
each with its own title.

```lua
memcard.title("My Save File")
```

**Tables: memcard.save() / memcard.load_table()**

`memcard.save(a_table)` — the no-position auto-append form **only** —
writes a **raw dump** of the table's contents: a straight walk of its
internal hash-bucket storage, the same way you'd `fwrite()` a struct to a
file in C. It is not a general recursive serializer.

```lua
local highscores = { alice = 500, bob = 350, carol = 900 }
memcard.save(highscores)

local restored = memcard.load_table(0)
print(10, 10, restored.alice)   -- 500
```

`memcard.save(a_table, position)` (the **explicit-position** form) is
unaffected by any of this — it still writes a single raw pointer word,
exactly like saving a table that way always has. The table dump format
below is exclusively a feature of the no-position auto-append form.

**Why "the hash side" and not an array**: this compiler's table
implementation has an array-part fast path in principle, but its
reallocation path is currently an unimplemented stub — capacity never
grows past 0, so **every** table, whether it looks array-shaped
(`{1, 2, 3}`) or not, is already stored entirely in the hash-bucket chain.
There is no separate, simpler "array case" to special-case today; dumping
the hash side covers all tables as they actually exist right now.

**What gets copied, and what doesn't**: each key and value is written
exactly as it's boxed. A number, boolean, or nil key/value round-trips
correctly forever. A key or value that is itself a table, string, or
function is written as its raw pointer — **not** recursively unpacked —
so it's only meaningful within the same run that wrote it; reloading it in
a future session (or after the pointer's target has moved/been collected)
is undefined. This is the same safety boundary the rest of `memcard.*`
already draws (see *Safety note*) — a table dump doesn't
cross it, it just applies it per-entry instead of once.

**`memcard.load_table(position)`** rebuilds a fresh table from a dump
written this way. `position` is **required** — unlike `memcard.load()`,
there's no sensible "position 0" default for something whose size in
words isn't known until the entry itself is read. It validates the tag
word before trusting anything after it; reading at a position that
doesn't hold a table dump returns `nil` rather than misreading unrelated
words as a pair count and garbage keys/values.

**Address layout**

```
0x30000000  +-------------------------------------+  position -24
            |  title: 20 characters               |
            |  (memcard.title() writes here)      |  position -5
            +-------------------------------------+
            |  reserved (3 words, unused)          |  position -4 .. -2
            +-------------------------------------+
            |  auto-append cursor                  |  position -1
0x30000018  +-------------------------------------+  position 0
            |  data region                         |
            |  (memcard.save()/.load()/[pos])     |
            |  ...                                 |
0x3003FFFF  +-------------------------------------+  last valid word
```

`position` is always relative to the start of the data region
(`0x30000018`). Negative positions reach backward into the title/metadata
block — reachable, but only by consciously going negative. Note the
metadata region (4 words, positions -4..-1) is separate from the title
block (20 words, positions -24..-5) — previously the metadata was carved
out of the *last 4 words of the title itself*, capping the usable title
at 16 characters; the full 20 is available now.

| Constant | Value | Meaning |
|---|---|---|
| `VIRCON32_MEMCARD_BASE` | `0x30000000` | start of the card; position `-24` |
| `VIRCON32_MEMCARD_DATA_BASE` | `0x30000018` | position `0` |
| `VIRCON32_MEMCARD_CURSOR_ADDR` | `0x30000017` | the auto-append cursor; position `-1` |
| `VIRCON32_MEMCARD_END` | `0x3003FFFF` | last valid word, inclusive |

**Type tags (auto-append form only)**

`memcard.save(value)` with no position writes one of three shapes at the
cursor, then advances the cursor by however many words that shape used:

| Value type | Layout | Words used |
|---|---|---|
| Real Lua string | `[TAG_STRING][length][char 0][char 1]...` | `2 + length` |
| Table | `[TAG_TABLE][pair_count][key 0][val 0]...` | `2 + 2 * pair_count` |
| Number / boolean / nil / function | `[TAG_SCALAR][raw value]` | `2` |

`TAG_SCALAR` is `0`, `TAG_STRING` is `1`, `TAG_TABLE` is `2`. A function
saved this way is stored as its raw boxed pointer under `TAG_SCALAR` — see
the safety note below, this is not a general serialization.

The explicit-`position` form (`memcard.save(value, position)` /
`memcard[position] = value`) never writes a tag — it is always exactly one
raw word, regardless of value type. This includes tables: a table saved
with an explicit position is a single raw pointer word, not a dump — see
**Tables** above.

*Safety note*

A number, boolean, or nil round-trips correctly forever — that bit pattern
means the same thing on any run. A real Lua string or table saved through
the auto-append form round-trips correctly too — a string's actual
characters are copied, and a table's actual key/value pairs are copied,
restorable with `memcard.load_table()`. A table saved via the
*explicit-position* form, a string saved via the *explicit-position* form
(which stores a raw pointer, not real string contents), or a function
value — including any such value found as a *key or value inside a saved
table*, since those are not recursively unpacked — round-trips fine
**within the same run** — its pointer is still valid — but is meaningless
after a fresh boot reads it back from a real memory card, since heap/ROM
layout is not guaranteed to match between runs. Stick to numbers/booleans/
nil (or real strings/tables of such, via the auto-append form) for
anything meant to survive an actual save/reload cycle.

**What's intentionally NOT here**

- No *recursive* table serialization — a table dump copies its direct
  key/value pairs only; a nested table inside one is a raw pointer, one
  level, same as everywhere else in `memcard.*`.
- `memcard.load()`'s no-position default does not follow the auto-append
  cursor the way `memcard.save()`'s does — it always reads word 0.
- No format/erase call — a card is formatted by writing to it, not by a
  separate call.

Both PICO-8's `dget()`/`dset()` and TIC-80's `pmem()` are unrelated APIs
that also use this same physical address range under their own layouts —
`memcard.*` is unavailable (a compile error) under `--#api pico8`/
`--#api tic80` to prevent a program from mixing the two and corrupting
whichever one it isn't currently addressing.

---

## Other raw IO ports

Every `ioports.*` port lives in one table (`core.c`'s `IOPortMap`),
organized under seven categories: `tim`, `rng`, `gpu`, `spu`, `inp`, `car`,
`mem`. The sound (`spu`), graphics (`gpu`, partially — see
**Defining texture regions**), and input (`inp`,
partially — see [btn()/btnp()](#input-btn--btnp)) categories are covered
above where they have a higher-level wrapper. What's left is either raw
hardware with no wrapper at all, or a wrapper that only covers part of a
category. The complete table of ports is in the [Quick reference](#ioports--every-hardware-port).

An unknown category or property name is a compile error listing the valid
categories, not a silent no-op or an undeclared-global read — see
`validate_ioports_path()`.

**ioports.tim.\* — raw timer**

```lua
local d = ioports.tim.date    -- TIM_CurrentDate:  year * 65536 + day of the year
local t = ioports.tim.time    -- TIM_CurrentTime:  seconds since midnight
local f = ioports.tim.frames  -- TIM_FrameCounter: same as system.frames()
local c = ioports.tim.cycles  -- TIM_CycleCounter: same as system.cycles()
```

`ioports.tim.date`/`ioports.tim.time` are the packed raw registers
`system.date()`/`system.time()` decode into a formatted string and three
separate numbers — reach for `system.date()`/`system.time()` unless the
packed representation itself is what's needed (e.g. storing one word to a
memory card instead of three separate fields).

**ioports.rng.\* — hardware RNG**

```lua
local r = ioports.rng.value   -- RNG_CurrentValue, read: the next random value
ioports.rng.seed = 12345      -- RNG_CurrentValue, write: reseed the generator
```

Same underlying hardware register for both directions — reading returns the
current random value (and advances the generator), writing reseeds it.
This is the console's own hardware RNG, independent of `math.random()`
(which is a software PRNG in the runtime, seeded separately) — the two do
not share state and will not produce the same sequence from the same seed.

**ioports.car.\* — cartridge info**

```lua
local ok   = ioports.car.connected  -- CAR_Connected,        boolean
local size = ioports.car.romsize    -- CAR_ProgramROMSize,   integer
local ntex = ioports.car.numvtex    -- CAR_NumberOfTextures, integer
local nsnd = ioports.car.numvsnd    -- CAR_NumberOfSounds,   integer
```

Read-only introspection of the currently-inserted cartridge itself — its
program ROM size in words, and how many textures/sounds its cart-XML
declared. Since a running program's own cart is always connected,
`ioports.car.connected` reading `false` is not a case normal cart code needs
to handle; it exists for completeness of the port table rather than a
practical branch condition; really only something transacted in the BIOS.

**ioports.mem.connected — memory card presence**

```lua
if ioports.mem.connected then
    memcard.save(highscore)
end
```

`MEM_Connected`, boolean, read-only — whether a memory card is actually
present before `memcard.*` calls touch it.
