# PICO-8 sfx()/music(): generic placeholder tone bank

> **Superseded when cart data is available.** A `.p8` compiled directly,
> or a `.lua` with `--#p8 "cart.p8"`, now plays the cart's own
> `__sfx__`/`__music__`, synthesized at compile time — see "Sound" in
> [PICO8.md](PICO8.md). This placeholder bank is only used when no such
> data exists (plain `--#api pico8`), and by the TIC-80 layer. A looped
> placeholder tone is what made `music()` sound like the same short
> sound repeating.

## Problem

`celeste.lua` (and any stripped `.lua` export of a PICO-8 cart, as opposed to
a full `.p8` file) carries none of the original `__music__`/`__sfx__`
tracker data. There is no asset data to play back faithfully, at all.

## Approach (per Matthew's suggestion)

Since both consoles' audio is closer to a tone generator than a tracker,
PICO-8's `sfx()`/`music()` don't try to reproduce the original cart -- they
select from a small bank of generic placeholder tones instead:

- `PICO8_TONE_COUNT` (8) native Vircon32 sound resources, auto-registered
  exactly like a hand-written `--#sound`, the moment `--#api pico8` is seen
  (`register_pico8_tone_bank()` in `pico8.c`, called from
  `make_node_cart_hint()` in `v32lua.c`).
- Registered as one contiguous run of resource ids (`next_sound_id++` back
  to back, nothing else can interleave), so the whole bank is addressable
  from just its first id (`pico8_tone_base_id`) -- no lookup table needed,
  compile-time or runtime. Tone `k` is `pico8_tone_base_id + k`.
- A PICO-8 index `n` maps onto tone `n & (PICO8_TONE_COUNT-1)` -- same index
  always plays the same placeholder tone.
- These are still real `--#sound` resources, `pico8_tone0.vsnd` ..
  `pico8_tone7.vsnd`, referenced from the cart XML. **The compiler now
  generates them** next to the output `.asm` (square-wave blips a minor
  third apart from C4, 0.18 s, linear decay) the first time a cart uses
  `sfx()`/`music()` -- but never overwrites an existing file, so a
  hand-made tone set always wins. (They used to have to be made by hand.)
- The bank is registered on first use of `sfx()`/`music()`, not when
  `--#api pico8` is seen.

## sfx(n [, channel[, offset[, length]]])

- `offset`/`length` (sub-clip playback) have no native equivalent --
  accepted, ignored, one `compiler_warning()` if supplied.
- `n < 0` is PICO-8's stop form (`sfx(-1[, channel])`) -- forwarded to
  `sfx.stop()`'s own emitter.
- Literal `n` folds entirely at compile time: the resolved tone id is
  handed to `emit_vircon32_sfx_play_intrinsic()` as a synthetic
  `NODE_NUMBER`, so it takes that emitter's own static-fold path.
- Dynamic `n` (celeste's `psfx` wrapper: `sfx(num)`, `num` a parameter)
  goes through a runtime routine, `__builtin_tonebank_sfx` (`vircon32.s`;
  formerly `__builtin_pico8_sfx` in `pico8.s`, moved so TIC-80 can share
  it), which does the `AND`-mapping in assembly and then mirrors
  `__builtin_vircon32_sfx_play` exactly (channel resolution, cursor
  auto-advance, channel-ownership masks).

## music(n [, fade_len[, channel_mask]])

- `fade_len`/`channel_mask` describe multi-channel pattern playback with no
  equivalent once a "track" is one placeholder tone -- accepted, silently
  ignored (not warned: every real call site passes them).
- Every `music()` call site actually seen in `celeste.lua` uses a literal
  track number, so only the static-fold path is implemented. A dynamic
  track number is a compile error naming the limitation, not a silent
  wrong-tone result -- a dynamic choice of cue can still go through
  `sfx()`/`psfx()`, which does support it.
- `n < 0` stops channel 0 specifically (an explicit literal channel-0 node,
  not an omitted arg -- an omitted channel means "every channel" to
  `emit_vircon32_channel_cmd_intrinsic()`, which would also cut any
  playing `sfx()`).
- `n >= 0` plays the mapped tone on channel 0, looped (PICO-8 patterns loop
  by default) via `emit_vircon32_play_intrinsic()` -- as
  `music.play(tone, 0, true)`. (Until the 2026-09 audit the loop flag was
  passed in the CHANNEL position, so music never actually looped.)

## Known limitations

- Not a reproduction of the original soundtrack/SFX -- impossible without
  the missing tracker data. This trades fidelity for "something plays, and
  it's consistent," which is the most that's achievable here.
- `music()`'s per-call fade and channel-mask arguments are accepted but
  inert.
- `music()` requires a compile-time-constant track number.

## TIC-80

TIC-80's `sfx()`/`music()` (previously empty stubs) now use the same bank:

- `sfx(id [, note, duration, channel, volume, speed])`: `id` -> tone
  `id & 7`; `channel` (TIC-80's 4th argument) passed through, absent ->
  auto channel; `sfx(-1, ...)` stops that channel (or every sfx channel).
  Literal ids fold at compile time; dynamic ids use `__builtin_tonebank_sfx`.
  `note`/`duration`/`volume`/`speed` are accepted and not reproduced.
- `music(track)` loops tone `track & 7` on channel 0; `music()` /
  `music(-1)` stops it. The track must be a compile-time constant.
- A TIC-80 cart's own `WAVES`/`SFX`/`MUSIC` sections are still not
  synthesized.
