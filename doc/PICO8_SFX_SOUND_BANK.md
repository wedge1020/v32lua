# PICO-8 sfx()/music(): generic placeholder tone bank

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
- These are still real `--#sound` resources: `pico8_tone0.vsnd` ..
  `pico8_tone7.vsnd` must exist alongside the cart at build time, same as
  any texture/sound a cart declares by hand. The compiler references a
  sound resource; it cannot fabricate the sample data inside one.

## sfx(n [, channel[, offset[, length]]])

- `offset`/`length` (sub-clip playback) have no native equivalent --
  accepted, ignored, one `compiler_warning()` if supplied.
- `n < 0` is PICO-8's stop form (`sfx(-1[, channel])`) -- forwarded to
  `sfx.stop()`'s own emitter.
- Literal `n` folds entirely at compile time: the resolved tone id is
  handed to `emit_vircon32_sfx_play_intrinsic()` as a synthetic
  `NODE_NUMBER`, so it takes that emitter's own static-fold path.
- Dynamic `n` (celeste's `psfx` wrapper: `sfx(num)`, `num` a parameter)
  needs a new runtime routine, `__builtin_pico8_sfx` (`runtime.s`), which
  does the `AND`-mapping in assembly and then mirrors
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
  by default) via `emit_vircon32_play_intrinsic()`.

## Known limitations

- Not a reproduction of the original soundtrack/SFX -- impossible without
  the missing tracker data. This trades fidelity for "something plays, and
  it's consistent," which is the most that's achievable here.
- `music()`'s per-call fade and channel-mask arguments are accepted but
  inert.
- `music()` requires a compile-time-constant track number.
- TIC-80's `sfx()`/`music()` are still stub/TODO placeholders in
  `v32lua.c` (`emit_tic80_sfx_intrinsic`/`emit_tic80_music_intrinsic`) --
  not touched by this change. The same tone-bank treatment would carry over
  directly if/when that's wanted.
