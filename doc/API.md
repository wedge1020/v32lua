# Native Vircon32 sound API: play() / stop() / pause() / resume()

Status: implemented, pending integration into the tree.
Files: `v32lua_sound_intrinsics.c`, `v32lua_spu_cmd_intrinsic.c`,
`v32lua_ioport_boolean.c`, `runtime_vircon32_sound.s`, `PATCHES.md`.

## Surface

```
play(SOUND [, CHANNEL [, CHANLOOP [, CHANVOL [, STARTINDEX]]]])  -> channel used
stop   ([CHANNEL])   -- hard stop, position resets to 0
pause  ([CHANNEL])   -- pause, position retained
resume ([CHANNEL])   -- resume a paused channel

ioports.spu.cmd(MODE)  -- lower-level escape hatch, see below
```

Defaults: `CHANNEL` 0, `CHANLOOP` false, `CHANVOL` 1.0, `STARTINDEX` no seek.
With no argument, `stop`/`pause`/`resume` apply to all 16 channels.
Dispatched in `try_emit_call_intrinsic()` alongside `spr`/`btn`/`btnp`: taken
only when neither `needs_pico8` nor `needs_tic80` is set.

## Codegen: hybrid fold

All arguments compile-time-known -> straight-line `OUT` sequence, no CALL,
no stack traffic (6 instructions for the common case). Anything dynamic ->
push 5 args and `CALL __builtin_vircon32_play`, which does nil-defaulting,
Lua-truthiness decoding and channel clamping. The fold is all-or-nothing:
one dynamic argument sends the whole call down the runtime path.

`--#sound` names count as compile-time-known. `node_cart_hint()` already
assigns `MUSIC` its resource id, so `play(MUSIC, 0)` emits
`OUT SPU_ChannelAssignedSound, 0` instead of reading the RAM global. The
fold is suppressed when `spu_name_is_rebound()` finds the name assigned to,
used as a loop variable, declared as a parameter, or mentioned in inline
asm anywhere in the AST -- that walk's switch is exhaustive and its default
returns "rebound", so a node type added later suppresses the fold rather
than licensing a wrong one.

## Three easy-to-get-wrong hardware details

1. **`SPU_SelectedChannel` must be written first.** `ChannelAssignedSound`,
   `ChannelVolume`, `ChannelLoopEnabled` and `ChannelPosition` all act on
   the currently selected channel.
2. **`SPU_SelectedSound` is not how you assign a sound to a channel.** It
   selects a sound for sound-level queries (`SPU_SoundLength`,
   `SPU_SoundLoopStart`). Channel playback uses
   `SPU_ChannelAssignedSound`. `emit_tic80_play_intrinsic()` currently uses
   `SPU_SelectedSound` and is likely wrong for this reason -- untouched here.
3. **The seek is issued after the play command.** Starting a stopped channel
   resets position to 0, so a `SPU_ChannelPosition` write before
   `SPUCommand_PlaySelectedChannel` is discarded.

Also: Vircon32 has no `ResumeSelectedChannel`. `resume(ch)` issues
`PlaySelectedChannel`, which resumes a PAUSED channel from its current
position (only a STOPPED channel restarts from 0). `resume()` uses
`ResumeAllChannels`.

Float immediates in `OUT` are unproven in this codebase, so `ChannelVolume`
and `ChannelPosition` are staged through a register. Integer immediates in
`OUT` are used throughout and emitted directly.

## Name-collision guard

Unlike `spr`/`btn`/`btnp`, the `play`/`stop`/`pause`/`resume` intrinsics
check `resolve_symbol()` and step aside for a user-defined function of the
same name. These names are far likelier to collide with game code. Globals
are registered by `register_all_globals_prepass()` before
`generate_program()`, so the lookup is reliable at dispatch time.

---

# ioports.spu.cmd() — the lower-level escape hatch

Issues one raw SPU command against whatever `SPU_SelectedChannel` currently
names. No channel selection, no sound assignment, no defaulting of its own —
pair it with the `ioports.spu.*` properties for sequences the intrinsics
don't cover (crossfades, sample-accurate seeking, custom loop points).

```lua
ioports.spu.channel    = 2
ioports.spu.chansound  = MUSIC
ioports.spu.chanloop   = true
ioports.spu.cmd("play")
```

Modes: `"play"` 0, `"pause"` 1, `"stop"` 2, `"pauseall"` 3, `"resume"` 4,
`"allstop"` 5. Aliases `"resumeall"` and `"stopall"` added, since the
originals read oddly beside `"pauseall"`. Omitted or nil -> `"play"`.

Three fixes went in with the hookup:

1. **The dispatcher only matched `ioports.spu.command`.** `cmd` fell through
   to "Unknown ioports method", so the short spelling never worked.
2. **An unrecognized mode was silent.** It fell back to `"play"`, so
   `ioports.spu.cmd("stopAll")` started playback instead of stopping
   anything. Now a compile error listing the valid modes.
3. **The dynamic path OUT'd the index raw.** `CFI` + `OUT SPU_Command, Rmode`
   wrote 0–5 to a port whose commands are 0x30–0x35, so every
   `ioports.spu.cmd(n)` with a runtime `n` sent an undefined command while
   the literal paths worked. Now a compare chain against the `SPUCommand_*`
   symbols, so both paths agree and neither assumes contiguous opcodes.

`emit_spu_cmd_intrinsic()` forward-declares `spu_static_number()`, defined
further down the same translation unit in `v32lua_sound_intrinsics.c`.

---

# Boolean IO ports: both directions were broken

A Lua boolean is not a float. `true`/`false`/`nil` are NaN-boxed bit
patterns (`0xFFC00002`, `0xFFC00001`, `0xFFC00000`), while the hardware
ports trade in the integers 0 and 1. `CFB` and `CIF` convert between
integers and floats and know nothing about the boxing:

- **WRITE:** `CFB` asks "is this float non-zero?" — and `BOXED_FALSE` and
  `BOXED_NIL` are both non-zero NaNs, so it answered 1 for false and nil
  just as readily as for true. `ioports.spu.chanloop = false` enabled
  looping.
- **READ:** `CIF` produced the float `0.0`/`1.0` rather than a Lua boolean,
  and `0.0` is truthy in Lua, so `if ioports.inp.status then` was true
  whether or not a gamepad was connected.

Both fixed. Writes decode Lua truthiness (only nil and false are falsy;
every number including 0 is truthy), with a literal `true`/`false`/`nil`
folding to a bare 0/1 immediate. Reads branch to `BOXED_TRUE`/`BOXED_FALSE`,
reusing `dest_reg` as its own scratch since `IEQ` is destructive and the
port value isn't needed after the test.

Affects `ioports.spu.chanloop`, `ioports.spu.soundloop`,
`ioports.inp.status`, `ioports.car.connect`, `ioports.mem.connec`. Integer
and float ports untouched.

**Behaviour change:** boolean ports now return `true`/`false` rather than
`1.0`/`0.0`. Arithmetic on one (`ioports.car.connect + 0`) needs rewriting
as `if p then 1 else 0`. Comparisons against `true`/`false` and bare
`if p then` now work correctly.
