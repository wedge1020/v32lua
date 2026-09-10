# Native Vircon32 fantasy-console API

This document covers ONLY the native Vircon32 API — the surface active when
neither `--#api pico8` nor `--#api tic80` compatibility mode is selected.
Under those modes, `spr()`/`btn()`/etc. are that console's own API instead
(see the PICO-8 / TIC-80 compatibility docs), and the calls below are not
available.

Files: `v32lua_sound_intrinsics.c`, `v32lua_sound_namespaces.c`,
`v32lua_spu_cmd_intrinsic.c`, `v32lua_ioport_boolean.c`,
`intrinsics_vircon32.c`, `intrinsics_vircon32_memcard.c`,
`runtime_vircon32_sound.s`, `runtime_vircon32_sfx.s`, `runtime_vircon32_spr.s`,
`runtime_vircon32_input.s`, `runtime_vircon32_memcard.s`.

See also `vircon32-spu-port-ordering.md` — the SPU port write order is
important and every sound emitter here depends on it.

---

## Table of Contents

- [Sound: music.\* / sfx.\*](#sound-music--sfx)
  - [SPU port ordering](#spu-port-ordering)
  - [music.volume() / sfx.volume()](#musicvolumevol--channel--sfxvolumevol--channel)
  - [Why the bare names went away](#why-the-bare-names-went-away)
  - [Compile-time aliases](#compile-time-aliases)
  - [music.playing()](#musicplaying-and-why-a-lua-flag-is-the-wrong-toggle)
  - [Codegen: hybrid fold](#codegen-hybrid-fold)
- [ioports.spu.cmd() — the raw escape hatch](#ioportsspucmd--the-raw-escape-hatch)
- [Boolean IO ports](#boolean-io-ports)
- [System: system.\*](#system-system)
  - [system.wait() / system.halt()](#systemwait--systemhalt)
  - [system.date() / system.time()](#systemdate--systemtime)
  - [system.frames / system.cycles](#systemframes--systemcycles)
- [Graphics: spr()](#graphics-spr)
  - [Runtime dispatch](#runtime-dispatch-not-compile-time-fold)
  - [ioports.gpu.clear()](#ioportsgpuclearcolor)
  - [Defining texture regions](#defining-texture-regions)
- [Input: btn() / btnp()](#input-btn--btnp)
  - [Button IDs](#button-ids)
  - [btn(): direct polling](#btn-direct-polling)
  - [btnp(): edge detection](#btnp-edge-detection)
  - [ioports.inp.inputs](#ioportsinpinputs----one-word-bitmask)
  - [What's intentionally not here](#whats-intentionally-not-here)
- [Tilemap: tilemap.\*](#tilemap-tilemap)
  - [--#tilemap and the CSV format](#tilemap-name-file-and-the-csv-format)
  - [tilemap.get() / tilemap.set()](#tilemapget--tilemapset)
  - [Lazy ROM-to-RAM promotion](#lazy-rom-to-ram-promotion)
  - [tilemap.render()](#tilemaprender)
  - [What's intentionally not here](#whats-intentionally-not-here-2)
- [Other raw IO ports](#other-raw-io-ports)
  - [ioports.tim.\* — raw timer](#ioportstim--raw-timer)
  - [ioports.rng.\* — hardware RNG](#ioportsrng--hardware-rng)
  - [ioports.car.\* — cartridge info](#ioportscar--cartridge-info)
  - [ioports.mem.connected — memory card presence](#ioportsmemconnected--memory-card-presence)
- [Memory card: memcard.\*](#memory-card-memcard)
  - [memcard.save() / memcard.load()](#memcardsave--memcardload)
  - [memcard[position]](#memcardposition)
  - [memcard.title()](#memcardtitlestr---nil)
  - [Tables: memcard.save() / memcard.load_table()](#tables-memcardsave--memcardload_table)
  - [Address layout](#address-layout)
  - [Type tags (auto-append form only)](#type-tags-auto-append-form-only)
  - [What's intentionally not here](#whats-intentionally-not-here-1)

---

# Sound: music.\* / sfx.\*

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

## Vircon32 SPU: the port write order

### The rule

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

### Channel states and what resume actually means

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

### Port types

`SPU_ChannelPosition` is an **INTEGER** port — a sample index, clamped by the
console to `0 .. SoundLength-1`. `audio.h` declares
`set_channel_position( int )`, and `WriteSPUChannelPosition()` reads
`Value.AsInteger`. The IOPortMap table had `ioports.spu.chanpos` as
`IOPORT_TYPE_FLOAT`, which wrote raw float bit patterns to it; corrected to
`IOPORT_TYPE_INTEGER`.

Genuine float ports: `SPU_ChannelVolume` (clamped 0–8), `SPU_ChannelSpeed`
(0–128, changes pitch), `SPU_GlobalVolume` (clamped 0–2). NaN/inf writes to
any of these are ignored rather than rejected.

## music.volume(VOL [, CHANNEL]) / sfx.volume(VOL [, CHANNEL])

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

### Channel-ownership tracking

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

### Codegen

An all-literal call (`music.volume(0.5, 0)`, `sfx.volume(0.0, -1)`) folds
to a straight-line `OUT` sequence at compile time, same as the rest of this
surface. `music.volume(VOL)`/`sfx.volume(VOL)` with no channel argument is
**always** a `CALL` — which channels are currently owned is only known at
runtime — to `__builtin_vircon32_volume_mask`, which loops bits 0–15 of the
namespace's mask and writes `SPU_ChannelVolume` for each set one. Any other
runtime-valued call goes to `__builtin_vircon32_volume`, which checks the
channel value against `-1` (global) at runtime and clamps otherwise.

## Why the bare names went away

`play` / `pause` / `resume` / `stop` were the four most collision-prone
identifiers a game could want for itself, which is what the old
`resolve_symbol()` step-aside guard in the dispatcher was working around.
They are gone; the namespaces replace them, and the alias mechanism restores
them by choice rather than by default.

## Compile-time aliases

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

## music.playing() and why a Lua flag is the wrong toggle

`SPU_ChannelState` is a read-only integer port returning `channel_stopped`
0x40, `channel_paused` 0x41, `channel_playing` 0x42. `music.playing(ch)`
selects the channel, reads it, and returns a real Lua boolean.

A pause/resume toggle built on a Lua flag drifts the moment a sound ends on
its own: the program still believes it is playing, so the next press pauses
an already-stopped channel instead of resuming it. Asking the hardware
cannot drift.

## Codegen: hybrid fold

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

# ioports.spu.cmd() — the raw escape hatch

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

# Boolean IO ports

A Lua boolean is not a float. `true`/`false`/`nil` are NaN-boxed bit
patterns; the hardware ports trade in integers 0 and 1. Writes decode Lua
truthiness (only `nil` and `false` are falsy), with literals folding to a
bare 0/1 immediate. Reads branch to `BOXED_TRUE`/`BOXED_FALSE`.

Affects `ioports.spu.chanloop`, `ioports.spu.soundloop`,
`ioports.inp.status`, `ioports.car.connected`, `ioports.mem.connected`.

Boolean ports return `true`/`false`, not `1.0`/`0.0`. Arithmetic on one
needs rewriting as `if p then 1 else 0`.

---

# System: system.\*

```
system.wait()   -> nil   (WAIT for the next new-cycle signal)
system.halt()   -> nil   (HLT -- stops the CPU)
system.date()   -> string, year, month, day
system.time()   -> string, hour, minute, second
```

## system.wait() / system.halt()

`system.wait()` compiles straight to `WAIT` — the same instruction
`ioports.gpu.sync()` uses, and interchangeable with it; both just wait for
the timer's next new-cycle signal. `system.halt()` compiles to `HLT`,
stopping the CPU outright — for a program that's completed its work and
has nothing left to render.

## system.date() / system.time()

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

## system.frames / system.cycles

```lua
local f = system.frames()   -- TIM_FrameCounter -- frames since power-on
local c = system.cycles()   -- TIM_CycleCounter -- CPU cycles since power-on
```

Both are read-only hardware counters, monotonic since boot — unlike
`system.date()`/`system.time()`, these are **not** wall-clock: they measure
the console's own running time, not the real-time clock. `system.frames()`
is the natural fit for "every N frames, do X" timing (this is exactly what
the tilemap scroll demo uses to pace its scroll speed) since it free-runs
regardless of what the program does, unlike a hand-rolled counter variable
that has to be remembered and incremented every frame. Both are also
reachable as raw ports (`ioports.tim.frames`, `ioports.tim.cycles`) — see
[Other raw IO ports](#other-raw-io-ports) — the `system.*` names are
identical, just under the more discoverable namespace.

---

# Graphics: spr()

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
| `blend_mode` | `VIRCON32_BLEND_ALPHA` (`0x20`) | see blend modes below |

An argument can be **omitted** (just stop supplying trailing arguments) or
passed as an **explicit `nil`** to skip it and reach a later one —
`spr(id, x, y, nil, nil, 45)` to rotate without touching scale — both mean
"use the default."

Blend modes:

| Constant | Value |
|---|---|
| `VIRCON32_BLEND_ALPHA` | `0x20` |
| `VIRCON32_BLEND_ADD` | `0x21` |
| `VIRCON32_BLEND_SUBTRACT` | `0x22` |

`spr()` returns nothing (Lua `nil`), matching the console having no
meaningful value to hand back from a draw call. More than 8 arguments is a
compile-time warning; the extras are ignored.

## Runtime dispatch, not compile-time fold

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

`color_mult`'s default of `0xFFFFFFFF` is passed through the calling
convention as a Lua float, and `4294967295.0` is not exactly representable
in a 32-bit float — it rounds up to `4294967296.0`. The runtime converts it
through `CFI` (float → integer bit pattern) rather than using it directly,
which recovers the correct `0xFFFFFFFF` regardless.

An explicitly-passed `nil` for an optional argument (e.g.
`spr(id, x, y, nil, nil, 45)`) is treated identically to that argument
being omitted entirely — both fall back to the default. A call sitting in
an expression context (`local unused = spr(1, 10, 10)`) correctly gets
`nil` assigned, matching every other intrinsic in this file.

## ioports.gpu.clear([color])

Clears the screen: writes `GPU_ClearColor` (if a color argument is given)
then issues `GPUCommand_ClearScreen`. `color` accepts either a packed RGBA
integer or one of five preset name strings — `"black"`, `"white"`,
`"blue"`, `"red"`, `"green"` — resolved at compile time when it's a string
literal. Omit the argument to clear with whatever `GPU_ClearColor`
currently holds.

```lua
ioports.gpu.clear("black")
ioports.gpu.clear(0xFF202020)   -- packed RGBA, not a preset name
ioports.gpu.clear()             -- reuses the last ClearColor set
```

## Defining texture regions

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

### Region HotSpot considerations and compiler behaviours

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

# Input: btn() / btnp()

```
btn(id [, player])   -> boolean, currently held down
btnp(id [, player])  -> boolean, true only on the frame it was first pressed
```

`player` selects a gamepad 0–3 (`INP_SelectedGamepad`); omitted or `nil`
uses whichever gamepad is already selected without writing the port.

## Button IDs

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

## btn(): direct polling

`__builtin_vircon32_btn` reads the mapped `INP_Gamepad*` port for the
selected gamepad and returns `true` when the hardware reports it pressed
(`>= 1`).

## btnp(): edge detection

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

## ioports.inp.inputs — one-word bitmask

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

## What's intentionally NOT here

- No bitfield/"any button" form (`btn()` with no arguments) the way
  PICO-8's does — every call names a specific button.
- No analog stick or trigger-pressure reporting; Vircon32's gamepad model
  is digital per the IOPort list above.
- No rumble/vibration output port exists on the console to expose.

These match the underlying Vircon32 hardware rather than PICO-8/TIC-80
conventions; that emulation lives entirely in the `--#api pico8`/`--#api tic80`
compatibility layers, not here.

---

# Tilemap: tilemap.\*

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

## --#tilemap NAME "file" and the CSV format

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

## tilemap.get() / tilemap.set()

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

## Lazy ROM-to-RAM promotion

A tilemap starts life read-only, sitting wherever the compiler placed its
data in the program image — `tilemap.get()` before any write reads directly
from there, at no RAM cost. The **first** `tilemap.set()` against a given
tilemap promotes it: allocates a private RAM copy and copies every cell
across, and only after that does the tilemap become mutable. Every read or
write to a *different* tilemap that hasn't been promoted is unaffected —
promotion is tracked per tilemap, not globally. A second and later
`tilemap.set()` on an already-promoted tilemap writes straight through,
without re-copying or disturbing earlier writes.

## tilemap.render()

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

## What's intentionally NOT here

- No sub-pixel/smooth scrolling — see above.
- No `mget()`/`mset()`/`map()` naming — those names belong to the TIC-80
  compatibility layer; this is a distinct, native surface, not an
  extension of it.
- No multi-layer support — one `--#tilemap` hint is one flat grid. Layering
  is a caller-side concern (declare several tilemaps, render them in order).
- No collision/query helpers beyond `tilemap.get()` itself — checking "is
  this a wall" is just comparing the returned tile id.

---

# Memory card: memcard.\*

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

## memcard.save() / memcard.load()

There are two distinct forms, chosen by whether a `position` is given:

**With an explicit `position`** — the low-level primitive. Writes (or
reads) exactly one raw word at `position`, with no bookkeeping of any
kind. `position 0` is the first word of the data region; see
[Address layout](#address-layout) below for the full range, including how
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
[Type tags](#type-tags-auto-append-form-only)), not just a raw pointer.

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
yourself at a known position (see [Type tags](#type-tags-auto-append-form-only)),
or simply knowing what you wrote there.

## memcard[position]

`memcard[position]` and `memcard[position] = value` are shorthand for the
explicit-position form of `load`/`save` above — never the auto-append
form, since Lua's bracket syntax has no "no index" spelling.

```lua
memcard[0] = 1234
local hi = memcard[0]        -- 1234
memcard[-1]                  -- reads the auto-append cursor
```

## memcard.title(str) -> nil

Sets the memory card's title — up to 20 characters, one word per
character, matching this VM's internal string representation. Longer
strings are truncated; shorter strings are zero-padded. This is
independent of any `--#title` cart hint, which names the *cartridge*, not
the *save data* — a single cart can have many memory cards in circulation,
each with its own title.

```lua
memcard.title("My Save File")
```

## Tables: memcard.save() / memcard.load_table()

`memcard.save(a_table)` — the no-position auto-append form **only** —
writes a **raw dump** of the table's contents: a straight walk of its
internal hash-bucket storage, the same way you'd `fwrite()` a struct to a
file in C. It is not a general recursive serializer.

```lua
local highscores = { alice = 500, bob = 350, carol = 900 }
memcard.save(highscores)

local restored = memcard.load_table(0)
print(restored.alice)   -- 500
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
already draws (see [Safety note](#safety-note)) — a table dump doesn't
cross it, it just applies it per-entry instead of once.

**`memcard.load_table(position)`** rebuilds a fresh table from a dump
written this way. `position` is **required** — unlike `memcard.load()`,
there's no sensible "position 0" default for something whose size in
words isn't known until the entry itself is read. It validates the tag
word before trusting anything after it; reading at a position that
doesn't hold a table dump returns `nil` rather than misreading unrelated
words as a pair count and garbage keys/values.

## Address layout

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

## Type tags (auto-append form only)

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
[Tables](#tables-memcardsave--memcardload_table) above.

### Safety note

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

## What's intentionally NOT here

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

# Other raw IO ports

Every `ioports.*` port lives in one table (`core.c`'s `IOPortMap`),
organized under six categories: `tim`, `rng`, `gpu`, `spu`, `inp`, `car`,
`mem`. The sound (`spu`), graphics (`gpu`, partially — see
[Defining texture regions](#defining-texture-regions)), and input (`inp`,
partially — see [btn()/btnp()](#input-btn--btnp)) categories are covered
above where they have a higher-level wrapper. What's left is either raw
hardware with no wrapper at all, or a wrapper that only covers part of a
category.

An unknown category or property name is a compile error listing the valid
categories, not a silent no-op or an undeclared-global read — see
`validate_ioports_path()`.

## ioports.tim.\* — raw timer

```lua
ioports.tim.date     -- TIM_CurrentDate,   read-only, packed integer
ioports.tim.time     -- TIM_CurrentTime,   read-only, packed integer
ioports.tim.frames    -- TIM_FrameCounter, read-only -- same as system.frames()
ioports.tim.cycles    -- TIM_CycleCounter, read-only -- same as system.cycles()
```

`ioports.tim.date`/`ioports.tim.time` are the packed raw registers
`system.date()`/`system.time()` decode into a formatted string and three
separate numbers — reach for `system.date()`/`system.time()` unless the
packed representation itself is what's needed (e.g. storing one word to a
memory card instead of three separate fields).

## ioports.rng.\* — hardware RNG

```lua
ioports.rng.value            -- RNG_CurrentValue, read: the current random value
ioports.rng.seed = 12345      -- RNG_CurrentValue, write: reseed the generator
```

Same underlying hardware register for both directions — reading returns the
current random value (and advances the generator), writing reseeds it.
This is the console's own hardware RNG, independent of `math.random()`
(which is a software PRNG in the runtime, seeded separately) — the two do
not share state and will not produce the same sequence from the same seed.

## ioports.car.\* — cartridge info

```lua
ioports.car.connected  -- CAR_Connected,          boolean, read-only
ioports.car.romsize    -- CAR_ProgramROMSize,     integer, read-only
ioports.car.numvtex    -- CAR_NumberOfTextures,   integer, read-only
ioports.car.numvsnd    -- CAR_NumberOfSounds,     integer, read-only
```

Read-only introspection of the currently-inserted cartridge itself — its
program ROM size in words, and how many textures/sounds its cart-XML
declared. Since a running program's own cart is always connected,
`ioports.car.connected` reading `false` is not a case normal cart code needs
to handle; it exists for completeness of the port table rather than a
practical branch condition; really only something transacted in the BIOS.

## ioports.mem.connected — memory card presence

```lua
if ioports.mem.connected then
    memcard.save(highscore)
end
```

`MEM_Connected`, boolean, read-only — whether a memory card is actually
present before `memcard.*` calls touch it.
