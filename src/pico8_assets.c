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
// The real PICO-8 16-color palette. (This table -- and __pico8_palette in
// pico8.s -- previously held TIC-80's Sweetie-16 palette by mistake.)
// MUST stay in lockstep with __pico8_palette in pico8.s: the asm table is
// read at runtime (cls()/print() color lookups) while this copy bakes the
// VTEX swatch row and atlas colors at build time.
// ============================================================================
unsigned int pico8_palette[16] = {
    0xFF000000,  // 0  black        #000000
    0xFF532B1D,  // 1  dark-blue    #1D2B53
    0xFF53257E,  // 2  dark-purple  #7E2553
    0xFF518700,  // 3  dark-green   #008751
    0xFF3652AB,  // 4  brown        #AB5236
    0xFF4F575F,  // 5  dark-grey    #5F574F
    0xFFC7C3C2,  // 6  light-grey   #C2C3C7
    0xFFE8F1FF,  // 7  white        #FFF1E8
    0xFF4D00FF,  // 8  red          #FF004D
    0xFF00A3FF,  // 9  orange       #FFA300
    0xFF27ECFF,  // 10 yellow       #FFEC27
    0xFF36E400,  // 11 green        #00E436
    0xFFFFAD29,  // 12 blue         #29ADFF
    0xFF9C7683,  // 13 lavender     #83769C
    0xFFA877FF,  // 14 pink         #FF77A8
    0xFFAACCFF,  // 15 light-peach  #FFCCAA
};

int   pico8_tone_base_id      = -1;
int   pico8_frame_step        = 2;   // Vircon32 frames per PICO-8 tick (1 = _update60)
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

// Writes a placeholder tone as a real VSND file (header "V32-VSND" + sample
// count, then 16-bit stereo samples at 44.1 kHz) unless the file already
// exists -- a cart's own pico8_toneN.vsnd always wins. Tone k: a square
// wave stepping up a minor third per tone from C4, 0.18 s, linear decay.
static void write_placeholder_tone (const char *path, int k)
{
    FILE *f = fopen (path, "rb");
    if (f != NULL) { fclose (f); return; }
    f = fopen (path, "wb");
    if (f == NULL) {
        compiler_warning (ERR_SEMANTIC, -1, "could not create placeholder tone '%s'", path);
        return;
    }
    const uint32_t rate = 44100, samples = (uint32_t)(rate * 0.18);
    double freq = 261.63 * pow (2.0, (3.0 * k) / 12.0);
    fwrite ("V32-VSND", 1, 8, f);
    fwrite (&samples, 4, 1, f);
    for (uint32_t i = 0; i < samples; i++) {
        double env   = 1.0 - (double) i / samples;
        double phase = fmod (i * freq / rate, 1.0);
        int16_t v    = (int16_t)((phase < 0.5 ? 1.0 : -1.0) * env * 6000.0);
        fwrite (&v, 2, 1, f);   // left
        fwrite (&v, 2, 1, f);   // right
    }
    fclose (f);
}

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

    // Resolve the tone files next to the generated .asm/.xml -- the same
    // place the generated textures go -- and create any that are missing,
    // so sfx()/music() work out of the box (they used to have to be made
    // by hand). Shared by the PICO-8 and TIC-80 layers.
    char dir[512] = "";
    if (g_asm_filename != NULL) {
        const char *slash = strrchr (g_asm_filename, '/');
        if (slash != NULL) {
            snprintf (dir, sizeof (dir), "%.*s/", (int)(slash - g_asm_filename), g_asm_filename);
        }
    }

    for (int i = 0; i < PICO8_TONE_COUNT; i++) {
        char path[600];
        snprintf (path, sizeof (path), "%spico8_tone%d.vsnd", dir, i);
        write_placeholder_tone (path, i);

        int assigned_id = next_sound_id++;
        if (pico8_tone_base_id < 0) {
            pico8_tone_base_id = assigned_id;
        }
        cart_resource_append (&sounds_head, &sounds_tail, assigned_id,
                              tone_names[i], path);
    }
}

// ============================================================================
// .p8 CARTRIDGE SUPPORT (__lua__ / __gfx__ / __gff__ / __map__)
// ----------------------------------------------------------------------------
// Two entry points share one parser:
//
//   v32lua cart.p8          -- pico8_split_cart(): the __lua__ section
//                              becomes the program source and the asset
//                              sections are parsed from the same file.
//   --#p8 "cart.p8"         -- a .lua program pulls just the ASSETS from a
//                              .p8 (e.g. a stripped celeste.lua + the
//                              original cart's gfx/flags/map).
//
// Formats (all hex text, one nibble or byte per character pair):
//   __gfx__  up to 128 rows x 128 chars; char = palette index of 1 pixel.
//            PICO-8 omits trailing all-zero rows, so fewer rows is normal.
//   __gff__  up to 2 rows x 256 chars; 2 chars = flag byte of 1 sprite.
//   __map__  up to 32 rows x 256 chars; 2 chars = tile id of 1 cell.
//            Map rows 32..63 live in the LOWER HALF OF __gfx__ (shared
//            memory 0x1000-0x1FFF): cell (x, y>=32) is the byte at offset
//            (y-32)*128 + x, i.e. gfx row 64 + ofs/64, pixel pair
//            (ofs%64)*2 -- low nibble = left pixel.
// ============================================================================

static uint8_t p8_gfx[128][128];
static uint8_t p8_gff[256];
static uint8_t p8_map[PICO8_MAP_HEIGHT][PICO8_MAP_WIDTH];
static bool    p8_have_gfx = false;
static bool    p8_have_gff = false;
static bool    p8_have_map = false;

static int p8_hex (char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

// Identifies a "__name__" section header line; returns the name length
// written to out (0 if the line is not a header).
static int p8_section_header (const char *line, size_t len, char *out, size_t out_size)
{
    if (len < 5 || line[0] != '_' || line[1] != '_') return 0;
    size_t i = 2;
    while (i < len && (isalnum ((unsigned char) line[i]))) i++;
    if (i + 2 > len || line[i] != '_' || line[i + 1] != '_') return 0;
    // rest of line must be whitespace
    for (size_t j = i + 2; j < len; j++)
        if (!isspace ((unsigned char) line[j])) return 0;
    size_t n = i - 2;
    if (n + 1 > out_size) n = out_size - 1;
    memcpy (out, line + 2, n);
    out[n] = '\0';
    return (int) n;
}

static void p8_parse_asset_line (const char *section, int row, const char *line, size_t len)
{
    if (strcmp (section, "gfx") == 0 && row < 128) {
        for (int x = 0; x < 128 && (size_t) x < len; x++) {
            int v = p8_hex (line[x]);
            if (v >= 0) p8_gfx[row][x] = (uint8_t) v;
        }
        p8_have_gfx = true;
    } else if (strcmp (section, "gff") == 0 && row < 2) {
        for (int i = 0; i < 128 && (size_t)(i * 2 + 1) < len; i++) {
            int hi = p8_hex (line[i * 2]), lo = p8_hex (line[i * 2 + 1]);
            if (hi >= 0 && lo >= 0) p8_gff[row * 128 + i] = (uint8_t)((hi << 4) | lo);
        }
        p8_have_gff = true;
    } else if (strcmp (section, "map") == 0 && row < 32) {
        for (int x = 0; x < PICO8_MAP_WIDTH && (size_t)(x * 2 + 1) < len; x++) {
            int hi = p8_hex (line[x * 2]), lo = p8_hex (line[x * 2 + 1]);
            if (hi >= 0 && lo >= 0) p8_map[row][x] = (uint8_t)((hi << 4) | lo);
        }
        p8_have_map = true;
    }
}

// Walks a whole .p8 text. Asset sections are always parsed. When lua_out is
// non-NULL, it receives a copy of the text with EVERY line outside __lua__
// blanked (newlines kept, so line numbers in errors still match the .p8),
// and the __lua__ header line itself replaced by "--#api pico8".
static void p8_walk (const char *text, char *lua_out)
{
    char section[32] = "";
    int  row = 0;
    const char *p = text;
    char *o = lua_out;

    while (*p) {
        const char *eol = strchr (p, '\n');
        size_t len = eol ? (size_t)(eol - p) : strlen (p);
        size_t tlen = len;
        if (tlen > 0 && p[tlen - 1] == '\r') tlen--;

        char name[32];
        if (p8_section_header (p, tlen, name, sizeof (name))) {
            snprintf (section, sizeof (section), "%s", name);
            row = 0;
            if (o && strcmp (section, "lua") == 0) {
                memcpy (o, "--#api pico8", 12);
                o += 12;
            }
        } else if (strcmp (section, "lua") == 0) {
            if (o) { memcpy (o, p, len); o += len; }
        } else if (section[0] != '\0') {
            p8_parse_asset_line (section, row++, p, tlen);
        }
        if (o && eol) *o++ = '\n';
        p = eol ? eol + 1 : p + len;
    }
    if (o) *o = '\0';

    // Map rows 32..63 are the shared lower half of the sprite sheet.
    if (p8_have_gfx) {
        for (int y = 32; y < PICO8_MAP_HEIGHT; y++) {
            for (int x = 0; x < PICO8_MAP_WIDTH; x++) {
                int ofs = (y - 32) * 128 + x;
                int gy  = 64 + ofs / 64;
                int gx  = (ofs % 64) * 2;
                p8_map[y][x] = (uint8_t)(p8_gfx[gy][gx] | (p8_gfx[gy][gx + 1] << 4));
            }
        }
        p8_have_map = true;
    }
}

bool pico8_is_cart_text (const char *text)
{
    return strncmp (text, "pico-8 cartridge", 16) == 0;
}

char *pico8_split_cart (const char *text)
{
    char *lua = malloc (strlen (text) + 16);
    if (lua == NULL) return NULL;
    p8_walk (text, lua);
    return lua;
}

bool pico8_load_cart_assets (const char *path, const char *relative_to)
{
    FILE *f = fopen (path, "rb");
    if (f == NULL && relative_to != NULL) {
        // retry relative to the source file's directory
        char buf[1024];
        const char *slash = strrchr (relative_to, '/');
        if (slash != NULL) {
            snprintf (buf, sizeof (buf), "%.*s/%s", (int)(slash - relative_to), relative_to, path);
            f = fopen (buf, "rb");
        }
    }
    if (f == NULL) return false;
    fseek (f, 0, SEEK_END);
    long n = ftell (f);
    rewind (f);
    char *text = malloc ((size_t) n + 1);
    if (text == NULL) { fclose (f); return false; }
    size_t got = fread (text, 1, (size_t) n, f);
    text[got] = '\0';
    fclose (f);
    p8_walk (text, NULL);
    free (text);
    return true;
}

uint8_t pico8_gfx_pixel (int x, int y)
{
    if (x < 0 || x >= 128 || y < 0 || y >= 128) return 0;
    return p8_gfx[y][x];
}

bool pico8_has_gfx (void) { return p8_have_gfx; }

// ROM data the runtime reads at init: packed map (4 cells per word, cell
// x at byte x%4 -- the same layout __builtin_pico8_mget/mset/map use) and
// one word per sprite of fget() flags. Always emitted, zero-filled when the
// cart has no such section, so the runtime never special-cases absence.
void emit_pico8_cart_data (FILE *out)
{
    fprintf (out, "\n;; --- PICO-8 cart data (%s map, %s flags) ---\n",
             p8_have_map ? "cart" : "empty", p8_have_gff ? "cart" : "empty");
    fprintf (out, "__pico8_map_rom:\n");
    for (int y = 0; y < PICO8_MAP_HEIGHT; y++) {
        fprintf (out, "    integer ");
        for (int w = 0; w < PICO8_MAP_WIDTH / 4; w++) {
            uint32_t word = (uint32_t) p8_map[y][w * 4]
                          | ((uint32_t) p8_map[y][w * 4 + 1] << 8)
                          | ((uint32_t) p8_map[y][w * 4 + 2] << 16)
                          | ((uint32_t) p8_map[y][w * 4 + 3] << 24);
            fprintf (out, "0x%08X%s", word, (w < PICO8_MAP_WIDTH / 4 - 1) ? ", " : "\n");
        }
    }
    fprintf (out, "__pico8_flags_rom:\n");
    for (int r = 0; r < 16; r++) {
        fprintf (out, "    integer ");
        for (int i = 0; i < 16; i++)
            fprintf (out, "%d%s", p8_gff[r * 16 + i], (i < 15) ? ", " : "\n");
    }
}
