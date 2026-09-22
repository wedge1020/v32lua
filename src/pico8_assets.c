#include "v32lua.h"

// ============================================================================
// PICO-8 spritesheet texture geometry
// ----------------------------------------------------------------------------
// The PICO-8 sheet is 128x128 (16x16 tiles of 8x8). The swatch row extends
// it to 128x132: 16 solid-color cells of 3x3 px with 1px gaps, at
// y = 128..130, cell c occupying x in [c*4, c*4+2]. Runtime regions
// 256-271 point at these cells (see __builtin_pico8_init in pico8.s.txt);
// the shape primitives (rectfill/circfill/line via __pico8_draw_swatch)
// stretch them to arbitrary sizes.
//
// Swatch pixels are ALWAYS OPAQUE and never subject to any colorkeying --
// same rule as the TIC-80 swatch bank: filled shapes must draw reliably
// no matter what transparency scheme the sprite atlas uses.
// ============================================================================
#define PICO8_SHEET_WIDTH        128
#define PICO8_SHEET_HEIGHT       128
#define PICO8_SWATCH_ROW_Y       128   // first swatch row (below the atlas)
#define PICO8_SWATCH_TEX_HEIGHT  132   // 128 atlas + 3 swatch + 1 pad
#define PICO8_SWATCH_CELL        3     // 3x3 px cells
#define PICO8_SWATCH_STRIDE      4     // 3px cell + 1px gap
#define PICO8_SWATCH_REGION_BASE 256   // region IDs 256-271

// ============================================================================
// PICO-8 default palette (AABBGGRR, 32-bit)
// ----------------------------------------------------------------------------
// MUST stay in lockstep with __pico8_palette in pico8.s.txt: the asm table
// is read at runtime (cls() palette lookup) while this copy bakes the VTEX
// swatch row and atlas colors at build time. If they ever disagree, a given
// palette index renders as different colors through spr() vs cls() vs the
// swatch primitives. Do NOT alias this to tic80_palette -- the values look
// similar but are the PICO-8 set.
// ============================================================================
unsigned int pico8_palette[16] = {
    0xFF2C1C1A,  // 0  black
    0xFF5D275D,  // 1  dark blue   (called "dark-blue" in pico8, it's magenta-ish)
    0xFF533EB1,  // 2  dark purple
    0xFF577DEF,  // 3  dark green... (pico8 "dark_gray" slot, keep EXACT asm order)
    0xFF75CDFF,  // 4
    0xFF70F0A7,  // 5
    0xFF64B738,  // 6
    0xFF797125,  // 7
    0xFF6F3629,  // 8
    0xFFC95D3B,  // 9
    0xFFF6A641,  // 10
    0xFFF7EF73,  // 11
    0xFFF4F4F4,  // 12
    0xFFC2B094,  // 13
    0xFF866C56,  // 14
    0xFF573C33,  // 15
};

int   pico8_tone_base_id      = -1;
bool  pico8_tones_registered  = false;

// ============================================================================
// Generate the PICO-8 spritesheet VTEX (atlas + swatch row)
// ============================================================================
// pixel_fn(x, y) returns the palette index (0-15) for atlas pixels; wire
// this to your existing __gfx__ sheet accessor. colorkey < 16 makes that
// palette index transparent in the ATLAS ONLY -- never in the swatch row.
void generate_vtex_from_pico8 (const char *output_path,
                               uint8_t (*pixel_fn) (int, int),
                               int         colorkey)
{
    FILE *f = fopen (output_path, "wb");
    if (!f) {
        fprintf (stderr, "Error: Could not create VTEX file '%s'\n", output_path);
        return;
    }

    VTEXHeader hdr = { .width = PICO8_SHEET_WIDTH,
                       .height = PICO8_SWATCH_TEX_HEIGHT };
    memcpy (hdr.magic, "V32-VTEX", 8);
    fwrite (&hdr, sizeof (hdr), 1, f);

    uint8_t *pixel_bytes = malloc (PICO8_SHEET_WIDTH * PICO8_SWATCH_TEX_HEIGHT * 4);
    if (!pixel_bytes) {
        fclose (f);
        return;
    }

    for (int y = 0; y < PICO8_SWATCH_TEX_HEIGHT; y++) {
        for (int x = 0; x < PICO8_SHEET_WIDTH; x++) {
            uint8_t red, green, blue, alpha;

            if (y >= PICO8_SWATCH_ROW_Y) {
                // --- Swatch row: 16 solid 3x3 cells, regions 256-271 ---
                // cell c occupies x in [c*4, c*4+2]; x%4==3 is the gap.
                int col   = x / PICO8_SWATCH_STRIDE;
                int col_x = x % PICO8_SWATCH_STRIDE;

                if (col >= 16 || col_x == 3 || y >= PICO8_SWATCH_ROW_Y + PICO8_SWATCH_CELL) {
                    red = green = blue = alpha = 0x00;   // gap / pad pixel
                } else {
                    // pico8_palette[]: AABBGGRR, same layout the asm
                    // __pico8_palette table uses (keep the two in sync!)
                    uint32_t color = pico8_palette [col];
                    blue  = (color >> 16) & 0xFF;
                    green = (color >> 8)  & 0xFF;
                    red   =  color        & 0xFF;
                    alpha = 0xFF;   // always opaque, never colorkeyed
                }
            } else {
                // --- Sprite atlas: unchanged ---
                uint8_t  color_idx = pixel_fn (x, y);
                uint32_t color     = pico8_palette [color_idx % 16];

                alpha = 0xFF;
                if (colorkey >= 0 && colorkey < 16 && color_idx == colorkey) {
                    alpha = 0x00;   // transparent
                }
                blue  = (color >> 16) & 0xFF;
                green = (color >> 8)  & 0xFF;
                red   =  color        & 0xFF;
            }

            int offset = (y * PICO8_SHEET_WIDTH + x) * 4;
            pixel_bytes[offset + 0] = red;
            pixel_bytes[offset + 1] = green;
            pixel_bytes[offset + 2] = blue;
            pixel_bytes[offset + 3] = alpha;
        }
    }

    fwrite (pixel_bytes, 1, PICO8_SHEET_WIDTH * PICO8_SWATCH_TEX_HEIGHT * 4, f);
    free (pixel_bytes);
    fclose (f);
}

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

void register_pico8_tone_bank (void)
{
    if (pico8_tones_registered) {
        return;
    }
    pico8_tones_registered    = true;

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
