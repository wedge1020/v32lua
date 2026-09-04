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
load-bearing and every sound emitter here depends on it.

---

## Table of Contents

- [Sound: music.\* / sfx.\*](#sound-music--sfx)
  - [music.volume() / sfx.volume()](#musicvolumevol--channel--sfxvolumevol--channel)
  - [Why the bare names went away](#why-the-bare-names-went-away)
  - [Compile-time aliases](#compile-time-aliases)
  - [music.playing()](#musicplaying-and-why-a-lua-flag-is-the-wrong-toggle)
  - [Codegen: hybrid fold](#codegen-hybrid-fold)
- [ioports.spu.cmd() — the raw escape hatch](#ioportsspucmd--the-raw-escape-hatch)
- [Boolean IO ports](#boolean-io-ports)
- [Graphics: spr()](#graphics-spr)
  - [Runtime dispatch](#runtime-dispatch-not-compile-time-fold)
- [Input: btn() / btnp()](#input-btn--btnp)
  - [Button IDs](#button-ids)
  - [btn(): direct polling](#btn-direct-polling)
  - [btnp(): edge detection](#btnp-edge-detection)
  - [What's intentionally not here](#whats-intentionally-not-here)
- [Memory card: memcard.\*](#memory-card-memcard)
  - [memcard.save() / memcard.load()](#memcardsave--memcardload)
  - [memcard[position]](#memcardposition)
  - [memcard.title()](#memcardtitlestr---nil)
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
`ioports.inp.status`, `ioports.car.connect`, `ioports.mem.connec`.

Boolean ports return `true`/`false`, not `1.0`/`0.0`. Arithmetic on one
needs rewriting as `if p then 1 else 0`.

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

# Memory card: memcard.\*

```
memcard.save(value, position)   -> value   (raw write, exactly 1 word)
memcard.save(value)             -> value   (auto-append; see below)
memcard.load(position)          -> value   (raw read, exactly 1 word)
memcard.load()                  -> value   (position 0)
memcard.title(str)              -> nil     (sets the 16-word title)

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

Sets the memory card's title — up to 16 characters, one word per
character, matching this VM's internal string representation. Longer
strings are truncated; shorter strings are zero-padded. This is
independent of any `--#title` cart hint, which names the *cartridge*, not
the *save data* — a single cart can have many memory cards in circulation,
each with its own title.

```lua
memcard.title("My Save File")
```

## Address layout

```
0x30000000  +-----------------------------------+  position -20
            |  title: 16 characters               |
            |  (memcard.title() writes here)      |  position -5
            +-------------------------------------+
            |  reserved (3 words, unused)          |  position -4 .. -2
            +-------------------------------------+
            |  auto-append cursor                  |  position -1
0x30000014  +-------------------------------------+  position 0
            |  data region                         |
            |  (memcard.save()/.load()/[pos])     |
            |  ...                                 |
0x3003FFFF  +-------------------------------------+  last valid word
```

`position` is always relative to the start of the data region
(`0x30000014`). Negative positions reach backward into the title/metadata
block — reachable, but only by consciously going negative.

| Constant | Value | Meaning |
|---|---|---|
| `VIRCON32_MEMCARD_BASE` | `0x30000000` | start of the card; position `-20` |
| `VIRCON32_MEMCARD_DATA_BASE` | `0x30000014` | position `0` |
| `VIRCON32_MEMCARD_CURSOR_ADDR` | `0x30000013` | the auto-append cursor; position `-1` |
| `VIRCON32_MEMCARD_END` | `0x3003FFFF` | last valid word, inclusive |

## Type tags (auto-append form only)

`memcard.save(value)` with no position writes one of two shapes at the
cursor, then advances the cursor by however many words that shape used:

| Value type | Layout | Words used |
|---|---|---|
| Real Lua string | `[TAG_STRING][length][char 0][char 1]...` | `2 + length` |
| Number / boolean / nil / table / function | `[TAG_SCALAR][raw value]` | `2` |

`TAG_SCALAR` is `0`, `TAG_STRING` is `1`. A table or function saved this
way is stored as its raw boxed pointer under `TAG_SCALAR` — see the safety
note below, this is not a general serialization.

The explicit-`position` form (`memcard.save(value, position)` /
`memcard[position] = value`) never writes a tag — it is always exactly one
raw word, regardless of value type.

### Safety note

A number, boolean, or nil round-trips correctly forever — that bit pattern
means the same thing on any run. A real Lua string saved through the
auto-append form round-trips correctly too. A table, a string saved via
the *explicit-position* form (which stores a raw pointer, not real string
contents), or a function value round-trips fine **within the same run** —
its pointer is still valid — but is meaningless after a fresh boot reads
it back from a real memory card, since heap/ROM layout is not guaranteed
to match between runs. Stick to numbers/booleans/nil (or real strings via
the auto-append form) for anything meant to survive an actual
save/reload cycle.

## What's intentionally NOT here

- No table serialization. A table is always saved as a raw pointer,
  meaningful only within the current run.
- `memcard.load()`'s no-position default does not follow the auto-append
  cursor the way `memcard.save()`'s does — it always reads word 0.
- No format/erase call — a card is formatted by writing to it, not by a
  separate call.

Both PICO-8's `dget()`/`dset()` and TIC-80's `pmem()` are unrelated APIs
that also use this same physical address range under their own layouts —
`memcard.*` is unavailable (a compile error) under `--#api pico8`/
`--#api tic80` to prevent a program from mixing the two and corrupting
whichever one it isn't currently addressing.
