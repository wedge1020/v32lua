// =============================================================================
// tic80_cart.c - read a binary TIC-80 cartridge (.tic)
// =============================================================================
// A .tic file is a list of chunks, each a 4-byte header followed by its data:
//
//   byte 0   bits 0-4 chunk type, bits 5-7 bank (0-7)
//   byte 1-2 data size, little-endian (0 means 64 KiB for CODE / BINARY)
//   byte 3   reserved
//
// (TIC-80 src/cart.c, tic_cart_load). Trailing zero bytes of a chunk are not
// stored, so every chunk is copied into a zero-filled buffer of its full size.
//
// Rather than teach the rest of the compiler a second asset path, the cart is
// turned into exactly the text TIC-80 itself writes when a cart is saved as a
// .lua project (src/studio/project.c, tic_project_save): the code, followed by
// "-- <TILES>" ... "-- </TILES>" sections of hex rows. That text then goes
// through the same lexer / tic80_assets.c path as any .lua export, so a .tic
// and its .lua export compile to the same program. Only bank 0 is emitted --
// the only bank the TIC-80 layer uses -- plus the code from every bank.
// =============================================================================

#include "v32lua.h"
#include <ctype.h>

enum {
    TIC_CHUNK_TILES     = 1,
    TIC_CHUNK_SPRITES   = 2,
    TIC_CHUNK_COVER_DEP = 3,
    TIC_CHUNK_MAP       = 4,
    TIC_CHUNK_CODE      = 5,
    TIC_CHUNK_FLAGS     = 6,
    TIC_CHUNK_SAMPLES   = 9,
    TIC_CHUNK_WAVEFORM  = 10,
    TIC_CHUNK_PALETTE   = 12,
    TIC_CHUNK_PATTERNS  = 15,
    TIC_CHUNK_MUSIC     = 14,
    TIC_CHUNK_CODE_ZIP  = 16,
    TIC_CHUNK_DEFAULT   = 17,
    TIC_CHUNK_SCREEN    = 18,
    TIC_CHUNK_BINARY    = 19,
    TIC_CHUNK_LANG      = 20,
};

#define TIC_BANK_SIZE   65536
#define TIC_LANG_LUA    10      // tic_script.id of the Lua backend (src/api/lua.c)

// Bank-0 asset buffers, sized like TIC-80's own structs.
static uint8_t t_tiles[8192], t_sprites[8192], t_map[240 * 136], t_waves[16 * 16];
static uint8_t t_sfx[64 * 66], t_patterns[60 * 192], t_tracks[8 * 51], t_flags[512];
static uint8_t t_palette[2 * 48];

// TIC-80's defaults for a bank saved as CHUNK_DEFAULT (src/cart.c).
static const uint8_t Sweetie16[48] = {
    0x1a, 0x1c, 0x2c, 0x5d, 0x27, 0x5d, 0xb1, 0x3e, 0x53, 0xef, 0x7d, 0x57, 0xff, 0xcd, 0x75, 0xa7,
    0xf0, 0x70, 0x38, 0xb7, 0x64, 0x25, 0x71, 0x79, 0x29, 0x36, 0x6f, 0x3b, 0x5d, 0xc9, 0x41, 0xa6,
    0xf6, 0x73, 0xef, 0xf7, 0xf4, 0xf4, 0xf4, 0x94, 0xb0, 0xc2, 0x56, 0x6c, 0x86, 0x33, 0x3c, 0x57 };
static const uint8_t DefaultWaves[48] = {
    0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff,
    0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe, 0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0x01,
    0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe, 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe };

bool tic80_is_binary_cart_path (const char *path)
{
    size_t n = strlen (path);
    return n > 4 && strcasecmp (path + n - 4, ".tic") == 0;
}

// --- growable output buffer ---------------------------------------------------
typedef struct { char *s; size_t len, cap; } TBuf;

static void tb_put (TBuf *b, const char *text, size_t n)
{
    if (b->len + n + 1 > b->cap) {
        size_t cap = b->cap ? b->cap : 65536;
        while (b->len + n + 1 > cap) cap *= 2;
        char *s = realloc (b->s, cap);
        if (s == NULL) compiler_error (ERR_INTERNAL, -1, "Out of memory reading .tic cartridge");
        b->s = s; b->cap = cap;
    }
    memcpy (b->s + b->len, text, n);
    b->len += n;
    b->s[b->len] = '\0';
}
static void tb_puts (TBuf *b, const char *text) { tb_put (b, text, strlen (text)); }

static bool all_zero (const uint8_t *p, size_t n)
{
    for (size_t i = 0; i < n; i++) if (p[i]) return false;
    return true;
}

// saveBinarySection() / saveBinaryBuffer() / tic_tool_buf2str() from TIC-80:
// empty rows and empty sections are skipped; "flip" swaps each byte's nibbles.
static void emit_section (TBuf *b, const char *tag, const uint8_t *data, int count, int size, bool flip)
{
    if (all_zero (data, (size_t) count * size)) return;

    char line[64];
    snprintf (line, sizeof (line), "-- <%s>\n", tag);
    tb_puts (b, line);
    char *hex = malloc ((size_t) size * 2 + 16);
    if (hex == NULL) compiler_error (ERR_INTERNAL, -1, "Out of memory reading .tic cartridge");
    for (int r = 0; r < count; r++) {
        const uint8_t *row = data + (size_t) r * size;
        if (all_zero (row, size)) continue;
        snprintf (line, sizeof (line), "-- %03d:", r);
        tb_puts (b, line);
        static const char digits[] = "0123456789abcdef";
        for (int i = 0; i < size; i++) {
            char hi = digits[row[i] >> 4], lo = digits[row[i] & 15];
            hex[i * 2]     = flip ? lo : hi;
            hex[i * 2 + 1] = flip ? hi : lo;
        }
        hex[size * 2] = '\n';
        tb_put (b, hex, (size_t) size * 2 + 1);
    }
    free (hex);
    snprintf (line, sizeof (line), "-- </%s>\n\n", tag);
    tb_puts (b, line);
}

char *tic80_cart_to_text (const char *path)
{
    FILE *f = fopen (path, "rb");
    if (f == NULL) {
        compiler_error (ERR_INTERNAL, -1, "Could not open TIC-80 cartridge '%s'", path);
    }
    fseek (f, 0, SEEK_END);
    long fsize = ftell (f);
    fseek (f, 0, SEEK_SET);
    uint8_t *buf = malloc (fsize > 0 ? (size_t) fsize : 1);
    if (buf == NULL || (fsize > 0 && fread (buf, 1, (size_t) fsize, f) != (size_t) fsize)) {
        compiler_error (ERR_INTERNAL, -1, "Could not read TIC-80 cartridge '%s'", path);
    }
    fclose (f);

    if (fsize >= 4 && memcmp (buf, "\x89PNG", 4) == 0) {
        compiler_error (ERR_SEMANTIC, -1,
            "'%s' is a PNG-wrapped TIC-80 cartridge; save it from TIC-80 as a "
            "plain .tic (or a .lua project) first", path);
    }

    memset (t_tiles, 0, sizeof t_tiles);       memset (t_sprites, 0, sizeof t_sprites);
    memset (t_map, 0, sizeof t_map);           memset (t_waves, 0, sizeof t_waves);
    memset (t_sfx, 0, sizeof t_sfx);           memset (t_patterns, 0, sizeof t_patterns);
    memset (t_tracks, 0, sizeof t_tracks);     memset (t_flags, 0, sizeof t_flags);
    memset (t_palette, 0, sizeof t_palette);

    const uint8_t *code[8]      = { 0 };
    long           code_size[8] = { 0 };
    int            lang         = 0;

    long pos = 0;
    while (pos + 4 <= fsize) {
        int  type = buf[pos] & 0x1F;
        int  bank = buf[pos] >> 5;
        long size = buf[pos + 1] | (buf[pos + 2] << 8);
        if (size == 0 && (type == TIC_CHUNK_CODE || type == TIC_CHUNK_BINARY)) size = TIC_BANK_SIZE;
        pos += 4;
        if (pos + size > fsize) {
            compiler_error (ERR_SEMANTIC, -1,
                "'%s' is not a valid TIC-80 cartridge (chunk at offset %ld runs past the end of the file)",
                path, pos - 4);
        }
        const uint8_t *data = buf + pos;

#define TAKE(dst) memcpy (dst, data, (size_t) size < sizeof (dst) ? (size_t) size : sizeof (dst))
        if (type == TIC_CHUNK_CODE) {
            code[bank] = data;
            code_size[bank] = size;
        } else if (type == TIC_CHUNK_CODE_ZIP) {
            compiler_error (ERR_SEMANTIC, -1,
                "'%s' stores its code compressed (an old TIC-80 cartridge format); "
                "load and save it in a current TIC-80, or export it as a .lua project", path);
        } else if (type == TIC_CHUNK_LANG) {
            lang = size > 0 ? data[0] : 0;
        } else if (bank == 0) {
            switch (type) {
            case TIC_CHUNK_TILES:    TAKE (t_tiles);    break;
            case TIC_CHUNK_SPRITES:  TAKE (t_sprites);  break;
            case TIC_CHUNK_MAP:      TAKE (t_map);      break;
            case TIC_CHUNK_SAMPLES:  TAKE (t_sfx);      break;
            case TIC_CHUNK_WAVEFORM: TAKE (t_waves);    break;
            case TIC_CHUNK_PATTERNS: TAKE (t_patterns); break;
            case TIC_CHUNK_MUSIC:    TAKE (t_tracks);   break;
            case TIC_CHUNK_FLAGS:    TAKE (t_flags);    break;
            case TIC_CHUNK_PALETTE:  TAKE (t_palette);  break;
            case TIC_CHUNK_DEFAULT:
                memcpy (t_palette, Sweetie16, sizeof Sweetie16);
                memcpy (t_waves, DefaultWaves, sizeof DefaultWaves);
                break;
            default: break;          // SCREEN (cover image), BINARY, deprecated chunks
            }
        }
#undef TAKE
        pos += size;
    }

    if (lang != 0 && lang != TIC_LANG_LUA) {
        compiler_error (ERR_SEMANTIC, -1,
            "'%s' is not a Lua TIC-80 cartridge (script language id %d); v32lua compiles Lua only",
            path, lang);
    }

    TBuf out = { 0 };

    // Code: TIC-80 concatenates the code chunks from bank 7 down to bank 0.
    bool any_code = false;
    for (int b = 7; b >= 0; b--) {
        if (code[b] == NULL) continue;
        size_t n = strnlen ((const char *) code[b], (size_t) code_size[b]);
        tb_put (&out, (const char *) code[b], n);
        any_code = true;
    }
    if (!any_code) {
        compiler_error (ERR_SEMANTIC, -1, "'%s' contains no code", path);
    }
    if (out.len > 0 && out.s[out.len - 1] != '\n') tb_puts (&out, "\n");

    // Guard: the code must be Lua. Without a LANG chunk TIC-80 goes by the
    // "script:" metadata tag, written in the language's own comment syntax
    // ("-- script: lua", "// script: js", "# script: python", ...).
    {
        static const char *tags[] = { "-- script:", "// script:", "# script:", ";; script:", "; script:" };
        for (size_t t = 0; t < sizeof (tags) / sizeof (tags[0]); t++) {
            const char *s = strstr (out.s, tags[t]);
            if (s == NULL || (s != out.s && s[-1] != '\n')) continue;
            s += strlen (tags[t]);
            while (*s == ' ' || *s == '\t') s++;
            if (strncmp (s, "lua", 3) != 0 || isalnum ((unsigned char) s[3])) {
                char lang_name[32] = { 0 };
                sscanf (s, "%31s", lang_name);
                compiler_error (ERR_SEMANTIC, -1,
                    "'%s' is a TIC-80 '%s' cartridge; v32lua compiles Lua only", path, lang_name);
            }
            break;
        }
    }

    tb_puts (&out, "\n");

    // Sections, in tic_project_save()'s order. PALETTE: only vbank 0's row,
    // the one the TIC-80 layer uses. SCREEN (the cover image) is skipped.
    emit_section (&out, "TILES",    t_tiles,    256, 32,  true);
    emit_section (&out, "SPRITES",  t_sprites,  256, 32,  true);
    emit_section (&out, "MAP",      t_map,      136, 240, true);
    emit_section (&out, "WAVES",    t_waves,    16,  16,  true);
    emit_section (&out, "SFX",      t_sfx,      64,  66,  true);
    emit_section (&out, "PATTERNS", t_patterns, 60,  192, true);
    emit_section (&out, "TRACKS",   t_tracks,   8,   51,  true);
    emit_section (&out, "FLAGS",    t_flags,    2,   256, true);
    emit_section (&out, "PALETTE",  t_palette,  1,   48,  false);

    free (buf);
    return out.s;
}

// TIC-80's own metadata lookup (tic_tool_metatag): the first "-- TAG:" in the
// code, value trimmed. Returns a static buffer; empty string if absent.
const char *tic80_metatag (const char *code, const char *tag)
{
    static char value[128];
    char pattern[64];
    value[0] = '\0';
    snprintf (pattern, sizeof (pattern), "-- %s:", tag);
    const char *start = strstr (code, pattern);
    if (start == NULL) return value;
    start += strlen (pattern);
    const char *end = strchr (start, '\n');
    if (end == NULL) end = start + strlen (start);
    while (start < end && isspace ((unsigned char) *start)) start++;
    while (end > start && isspace ((unsigned char) end[-1])) end--;
    size_t n = (size_t) (end - start);
    if (n > sizeof (value) - 1) n = sizeof (value) - 1;
    memcpy (value, start, n);
    value[n] = '\0';
    return value;
}
