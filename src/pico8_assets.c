#include "v32lua.h"

// celeste.lua (like any stripped .lua export of a PICO-8 cart) carries none
// of the original cart's __music__/__sfx__ tracker data -- that binary asset
// data simply is not part of a .lua export, so there is nothing to play back
// faithfully. Per the agreed approach, every PICO-8 sfx()/music() index is
// mapped onto one of a small bank of generic placeholder tones instead:
// PICO8_TONE_COUNT native Vircon32 sound resources, auto-registered exactly
// like any --#sound the cart could have declared itself, the moment
// --#api pico8 is seen (see register_pico8_tone_bank(), called from
// make_node_cart_hint()). Same PICO-8 index always -> same placeholder tone,
// which is as close to "the right cue at the right moment" as is possible
// without the original asset data.
//
// The bank is registered as ONE contiguous run of ids (they all come from
// next_sound_id++ back to back, with nothing else able to interleave a
// registration in between), so the whole bank is addressable from just its
// first id -- no separate lookup table, compile-time or runtime, is needed.
// pico8_tone_base_id is that first id; tones 1..PICO8_TONE_COUNT-1 are
// base_id+1 .. base_id+(PICO8_TONE_COUNT-1).
//
// These are real --#sound resources: the placeholder .vsnd files themselves
// (pico8_tone0.vsnd .. pico8_toneN.vsnd) still have to exist alongside the
// cart when it builds, the same as any --#texture/--#sound asset the cart
// declares by hand -- the compiler can reference a sound resource, it can't
// fabricate the sample data inside one.
int  pico8_tone_base_id      = -1;
bool pico8_tones_registered = false;

void register_pico8_tone_bank (void)
{
    if (pico8_tones_registered) {
        return;
    }
    pico8_tones_registered = true;

    static const char *tone_names[PICO8_TONE_COUNT] = {
        "__pico8_tone0", "__pico8_tone1", "__pico8_tone2", "__pico8_tone3",
        "__pico8_tone4", "__pico8_tone5", "__pico8_tone6", "__pico8_tone7",
    };
    static const char *tone_files[PICO8_TONE_COUNT] = {
        "pico8_tone0.vsnd", "pico8_tone1.vsnd", "pico8_tone2.vsnd", "pico8_tone3.vsnd",
        "pico8_tone4.vsnd", "pico8_tone5.vsnd", "pico8_tone6.vsnd", "pico8_tone7.vsnd",
    };

    for (int i = 0; i < PICO8_TONE_COUNT; i++) {
        int assigned_id = next_sound_id++;
        if (pico8_tone_base_id < 0) {
            pico8_tone_base_id = assigned_id;
        }
        cart_resource_append (&sounds_head, &sounds_tail, assigned_id,
		                      tone_names[i], tone_files[i]);
	}
}
