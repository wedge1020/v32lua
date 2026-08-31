# Native Vircon32 sound API: music.* / sfx.*

Status: implemented, pending integration into the tree.
Files: `v32lua_sound_intrinsics.c`, `v32lua_sound_namespaces.c`,
`v32lua_spu_cmd_intrinsic.c`, `v32lua_ioport_boolean.c`,
`runtime_vircon32_sound.s`, `runtime_vircon32_sfx.s`, `PATCHES.md`,
`PATCH_spu_ordering.md`, `PATCH_namespaces.md`.

See also `vircon32-spu-port-ordering.md` — the port write order is
load-bearing and every emitter here depends on it.

## Surface

```
music.play(SOUND [, CHANNEL [, LOOP [, VOL [, START]]]])  -> channel used
music.pause  ([CHANNEL])
music.resume ([CHANNEL])
music.stop   ([CHANNEL])
music.playing([CHANNEL])                                  -> boolean

sfx.play(SOUND [, CHANNEL [, VOL [, SPEED]]])             -> channel used
sfx.stop([CHANNEL])

ioports.spu.cmd(MODE)   -- raw escape hatch, see below
```

`music` defaults to channel 0. `sfx.play()` with no channel round-robins
over channels 1–15 via one compiler-reserved RAM word
(`VIRCON32_SFX_CURSOR`), so an effect never cuts the music off. `sfx` never
loops — anything sustained is `music.play(..., true)` on its own channel.

`sfx.stop()` with no channel stops channels 1–15 only, deliberately NOT
`StopAllChannels`, which would silence the music too. That is
`__builtin_vircon32_sfx_stop_all`.

The cursor advances unconditionally rather than searching for an idle
channel: searching would cost up to 15 `IN` + compare on the hot path
(`sfx.play()` runs on every jump and footstep) to protect against a case
that only arises when 15 effects overlap, where the oldest is the right one
to lose anyway.

## Why the bare names went away

`play` / `pause` / `resume` / `stop` were the four most collision-prone
identifiers a game could want for itself, which is what the old
`resolve_symbol()` step-aside guard in the dispatcher was working around.
They are gone; the namespaces replace them, and the alias mechanism restores
them by choice rather than by default.

## Compile-time aliases

`play = music.play` records an alias and emits nothing. Later `play(...)`
calls compile to the identical inline OUT sequence — no runtime value, no
CALL, no RAM.

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
cannot drift. This is also the diagnostic that would have caught the lost
loop flag in one run instead of three.

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

Note the two AST walks default in opposite directions, on purpose:
`spu_name_is_rebound()` is exhaustive and its default returns "rebound",
because a missed rebind silently folds the wrong resource id.
`spu_alias_scan()` recurses into nothing by default, because a missed alias
produces a loud "Undeclared function" at the call site.

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

Three fixes went in with the hookup:

1. The dispatcher only matched `ioports.spu.command`; `cmd` fell through to
   "Unknown ioports method".
2. An unrecognized mode silently fell back to `"play"`, so
   `ioports.spu.cmd("stopAll")` started playback. Now a compile error
   listing the valid modes.
3. The dynamic path OUT'd the index raw — 0–5 to a port whose commands are
   0x30–0x35 — so every runtime-valued call sent an undefined command while
   the literal paths worked. Now a compare chain against the `SPUCommand_*`
   symbols.

---

# Boolean IO ports: both directions were broken

A Lua boolean is not a float. `true`/`false`/`nil` are NaN-boxed bit
patterns (`0xFFC00002`, `0xFFC00001`, `0xFFC00000`); the hardware ports
trade in integers 0 and 1. `CFB` and `CIF` know nothing about the boxing:

- **WRITE:** `CFB` asks "is this float non-zero?" — `BOXED_FALSE` and
  `BOXED_NIL` are both non-zero NaNs, so it answered 1 for false and nil
  alike. `ioports.spu.chanloop = false` enabled looping.
- **READ:** `CIF` produced the float `0.0`/`1.0` rather than a Lua boolean,
  and `0.0` is truthy in Lua, so `if ioports.inp.status then` was true
  whether or not a gamepad was connected.

Both fixed. Writes decode Lua truthiness (only nil and false are falsy),
with literals folding to a bare 0/1 immediate. Reads branch to
`BOXED_TRUE`/`BOXED_FALSE`, reusing `dest_reg` as its own scratch since
`IEQ` is destructive.

Affects `ioports.spu.chanloop`, `ioports.spu.soundloop`,
`ioports.inp.status`, `ioports.car.connect`, `ioports.mem.connec`.

**Behaviour change:** boolean ports now return `true`/`false` rather than
`1.0`/`0.0`. Arithmetic on one needs rewriting as `if p then 1 else 0`.
