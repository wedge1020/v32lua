#include "v32lua.h"

// ============================================================================
// PICO-8 side panels ("bezel")
// ----------------------------------------------------------------------------
// The 352x352 PICO-8 canvas leaves two 144x360 strips on the 640x360 screen.
// __builtin_pico8_present() used to mask them with black after every frame
// (PICO-8 clips its drawing; the Vircon32 GPU has no clip rectangle). With
// the bezel, the masks are these two panels instead -- same number of draws.
//
// Each panel is 48x120 pixel art in the PICO-8 palette, drawn at 3x; both
// live in texture 0 below the swatch row (PICO8_BEZEL_Y), regions 272-273.
// All art is original: plain-text labels (not the platforms' logos), a
// starfield with a ship and a ringed planet, a sunset-and-grid landscape, a
// controls legend, and the cart's title.
// ============================================================================

bool pico8_bezel_enabled = true;
bool g_cli_bezel_set     = false;        // --no-bezel given: the hint is ignored

static uint8_t bz[PICO8_BEZEL_H][PICO8_BEZEL_W];   // palette indexes

static int clip_x0 = 0, clip_x1 = PICO8_BEZEL_W;   // the panel being drawn

static void px (int x, int y, int c)
{
    if (x >= clip_x0 && x < clip_x1 && y >= 0 && y < PICO8_BEZEL_H) bz[y][x] = (uint8_t) c;
}

static void fill (int x0, int y0, int w, int h, int c)
{
    for (int y = y0; y < y0 + h; y++) for (int x = x0; x < x0 + w; x++) px (x, y, c);
}

// 3x5 font: 15 characters per glyph, row by row
static const struct { char ch; const char *rows; } glyphs[] = {
    { 'A', ".#.#.#####.##.#" },
    { 'B', "##.#.###.#.###." },
    { 'C', ".###..#..#...##" },
    { 'D', "##.#.##.##.###." },
    { 'E', "####..##.#..###" },
    { 'F', "####..##.#..#.." },
    { 'G', ".###..#.##.#.##" },
    { 'H', "#.##.#####.##.#" },
    { 'I', "###.#..#..#.###" },
    { 'J', "..#..#..##.#.#." },
    { 'K', "#.##.###.#.##.#" },
    { 'L', "#..#..#..#..###" },
    { 'M', "#.########.##.#" },
    { 'N', "##.#.##.##.##.#" },
    { 'O', ".#.#.##.##.#.#." },
    { 'P', "##.#.###.#..#.." },
    { 'Q', ".#.#.##.###..##" },
    { 'R', "##.#.###.#.##.#" },
    { 'S', ".###...#...###." },
    { 'T', "###.#..#..#..#." },
    { 'U', "#.##.##.##.####" },
    { 'V', "#.##.##.#.#..#." },
    { 'W', "#.##.########.#" },
    { 'X', "#.##.#.#.#.##.#" },
    { 'Y', "#.##.#.#..#..#." },
    { 'Z', "###..#.#.#..###" },
    { '0', "####.##.##.####" },
    { '1', ".#.##..#..#.###" },
    { '2', "##...#.#.#..###" },
    { '3', "##...#.#...###." },
    { '4', "#.##.####..#..#" },
    { '5', "####..##...###." },
    { '6', ".###..####.####" },
    { '7', "###..#.#..#..#." },
    { '8', "####.#####.####" },
    { '9', "####.####..###." },
    { '-', "......###......" },
    { '=', "...###...###..." },
    { ':', "....#.....#...." },
    { '.', ".............#." },
    { '!', ".#..#..#.....#." },
    { '?', "##...#.#.....#." },
    { '\'', ".#..#.........." },
    { '/', "..#..#.#.#..#.." },
    { '+', "....#.###.#...." },
    { '&', ".#.#.#.#.#.#.##" },
};

static const char *glyph (char c)
{
    if (c >= 'a' && c <= 'z') c = (char) (c - 'a' + 'A');
    for (size_t i = 0; i < sizeof glyphs / sizeof glyphs[0]; i++)
        if (glyphs[i].ch == c) return glyphs[i].rows;
    return NULL;
}

// Text in the 3x5 font (4 px per character), with a 1-pixel drop shadow
// when shadow >= 0. Returns the width drawn.
static int text (int x, int y, const char *s, int c, int shadow)
{
    int x0 = x;
    for (; *s; s++, x += 4) {
        const char *g = glyph (*s);
        if (g == NULL) continue;
        for (int r = 0; r < 5; r++)
            for (int k = 0; k < 3; k++)
                if (g[r * 3 + k] == '#') {
                    if (shadow >= 0) px (x + k + 1, y + r + 1, shadow);
                    px (x + k, y + r, c);
                }
    }
    return x - x0 - 1;
}

static void text_centered (int cx, int y, const char *s, int c, int shadow)
{
    int w = (int) strlen (s) * 4 - 1;
    text (cx - w / 2, y, s, c, shadow);
}

// Pixel art from rows of hex palette digits ('.' = transparent).
static void sprite (int x, int y, const char *const rows[], int n)
{
    for (int r = 0; r < n; r++)
        for (int k = 0; rows[r][k]; k++) {
            char ch = rows[r][k];
            if (ch == '.') continue;
            int v = (ch >= '0' && ch <= '9') ? ch - '0' : ch - 'a' + 10;
            px (x + k, y + r, v);
        }
}

static void disc (int cx, int cy, int r, int c)
{
    for (int y = -r; y <= r; y++)
        for (int x = -r; x <= r; x++)
            if (x * x + y * y <= r * r + r) px (cx + x, cy + y, c);
}

static uint32_t rng_state;
static int rnd (int n) { rng_state = rng_state * 1103515245u + 12345u; return (int) ((rng_state >> 16) % (uint32_t) n); }

// Dark background: navy fading into black with a 4x4 ordered dither.
static void background (int x0)
{
    static const int bayer[4][4] = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } };
    for (int y = 0; y < PICO8_BEZEL_H; y++)
        for (int x = x0; x < x0 + 48; x++) {
            int level = 16 - (y * 16) / 70;          // navy at the top, black from y = 70
            px (x, y, bayer[y & 3][x & 3] < level ? 1 : 0);
        }
}

static void stars (int x0, int y0, int w, int h, int count)
{
    for (int i = 0; i < count; i++) {
        int x = x0 + rnd (w), y = y0 + rnd (h);
        int c = (i % 5 == 0) ? 7 : (i % 3 == 0) ? 13 : 6;
        px (x, y, c);
    }
}

static void twinkle (int x, int y, int c)
{
    px (x, y, 7); px (x - 1, y, c); px (x + 1, y, c); px (x, y - 1, c); px (x, y + 1, c);
}

static void left_panel (void)
{
    const int x0 = 0;
    clip_x0 = x0; clip_x1 = x0 + 48;
    background (x0);
    rng_state = 0x5EED0001u;
    stars (x0 + 2, 20, 42, 62, 34);
    twinkle (x0 + 9, 30, 12);
    twinkle (x0 + 38, 58, 14);

    // platform label and a palette strip
    text_centered (x0 + 24, 5, "PICO-8", 7, 5);
    static const int strip[6] = { 8, 9, 10, 11, 12, 14 };
    for (int i = 0; i < 6; i++) fill (x0 + 12 + i * 4, 13, 3, 1, strip[i]);

    // ringed planet
    disc (x0 + 33, 36, 7, 12);
    for (int y = -7; y <= 7; y++)
        for (int x = -7; x <= 7; x++)
            if (x * x + y * y <= 56 && x + y > 5) px (x0 + 33 + x, 36 + y, 13);
    px (x0 + 30, 32, 7); px (x0 + 31, 32, 6); px (x0 + 30, 33, 6);
    for (int x = -11; x <= 11; x++) {
        int y = 36 + (x * 3) / 11 - 1;
        if (!(x > -7 && x < 7 && x * 3 / 11 < 0)) px (x0 + 33 + x, y, 9);
    }

    // ship with exhaust
    static const char *const ship[] = {
        "...7...",
        "..676..",
        "..6c6..",
        ".66c66.",
        "6666666",
        "6.585.6",
        "..8.8..",
        "..9.9..",
        "..a.a..",
    };
    sprite (x0 + 11, 54, ship, 9);
    px (x0 + 13, 64, 10); px (x0 + 15, 64, 10); px (x0 + 13, 66, 9); px (x0 + 15, 67, 9);
    // its shots
    px (x0 + 14, 47, 11); px (x0 + 14, 46, 11); px (x0 + 14, 41, 11); px (x0 + 14, 40, 11);

    // controls legend
    fill (x0 + 3, 80, 42, 1, 5);
    static const char *const dpad[] = {
        "..666..",
        "..656..",
        "6665666",
        "6555556",
        "6665666",
        "..656..",
        "..666..",
    };
    sprite (x0 + 4, 85, dpad, 7);
    text (x0 + 14, 86, "MOVE", 6, -1);
    static const char *const obtn[] = { ".888.", "8...8", "8...8", "8...8", ".888." };
    static const char *const xbtn[] = { "c...c", ".c.c.", "..c..", ".c.c.", "c...c" };
    sprite (x0 + 5, 95, obtn, 5);
    text (x0 + 14, 95, "= A", 6, -1);
    sprite (x0 + 5, 103, xbtn, 5);
    text (x0 + 14, 103, "= B", 6, -1);
    text_centered (x0 + 24, 112, "START:PAUSE", 13, -1);
}

static void right_panel (const char *title)
{
    const int x0 = 48;
    clip_x0 = x0; clip_x1 = x0 + 48;
    background (x0);
    rng_state = 0x5EED0002u;
    stars (x0 + 2, 18, 44, 22, 18);

    text_centered (x0 + 24, 5, "VIRCON32", 7, 5);
    static const int strip[6] = { 14, 12, 11, 10, 9, 8 };
    for (int i = 0; i < 6; i++) fill (x0 + 12 + i * 4, 13, 3, 1, strip[i]);

    // striped sunset sun behind mountains, over a perspective grid
    const int sx = x0 + 24, sy = 46, sr = 12;
    for (int y = -sr; y <= 0; y++) {
        int band = (y + sr) * 4 / (sr + 1);             // 0..3 from the top
        static const int col[4] = { 10, 9, 8, 14 };
        if (y > -6 && ((y + sr) % 3 == 2)) continue;     // cut stripes, lower half
        for (int x = -sr; x <= sr; x++)
            if (x * x + y * y <= sr * sr + sr) px (sx + x, sy + y, col[band]);
    }
    // mountains
    static const int peaks[][3] = { { x0 + 6, 38, 9 }, { x0 + 16, 34, 8 }, { x0 + 34, 36, 10 }, { x0 + 44, 40, 7 } };
    for (size_t i = 0; i < sizeof peaks / sizeof peaks[0]; i++) {
        int px0 = peaks[i][0], py = peaks[i][1], hw = peaks[i][2];
        for (int y = py; y <= 46; y++) {
            int half = (y - py) * hw / (46 - py + 1);
            for (int x = px0 - half; x <= px0 + half; x++)
                px (x, y, (x == px0 - half || x == px0 + half) ? 13 : 2);
        }
    }
    // horizon and grid
    fill (x0, 47, 48, 1, 14);
    for (int y = 48; y < 76; y++) fill (x0, y, 48, 1, 0);
    static const int rows[] = { 49, 51, 54, 58, 63, 69, 75 };
    for (size_t i = 0; i < sizeof rows / sizeof rows[0]; i++) fill (x0, rows[i], 48, 1, i < 2 ? 2 : 14);
    for (int k = -6; k <= 6; k++)
        for (int y = 48; y < 76; y++) {
            int x = sx + (k * 4 * (y - 47)) / 6;
            px (x, y, (y < 54) ? 2 : 14);
        }

    // the cart's title, word-wrapped to 11 characters, up to 4 lines
    fill (x0 + 3, 80, 42, 1, 5);
    char line[12];
    int lines = 0, y = 86;
    const char *p = title;
    while (*p && lines < 4) {
        while (*p == ' ') p++;
        int n = (int) strlen (p), take = n > 11 ? 11 : n;
        if (n > 11) {                                     // break at the last space
            int k = take;
            while (k > 0 && p[k] != ' ') k--;
            if (k > 0) take = k;
        }
        snprintf (line, sizeof line, "%.*s", take, p);
        text_centered (x0 + 24, y, line, lines == 0 ? 7 : 6, lines == 0 ? 5 : -1);
        p += take;
        y += 7;
        lines++;
    }
    text_centered (x0 + 24, 113, "V32LUA", 5, -1);
}

// Draws both panels for the cart titled `title` (a [PICO8] prefix is
// dropped). Call before pico8_bezel_index().
void pico8_bezel_build (const char *title)
{
    memset (bz, 0, sizeof bz);
    if (title == NULL) title = "";
    if (strncmp (title, "[PICO8] ", 8) == 0) title += 8;
    left_panel ();
    right_panel (title);
    // inner frame edges, next to the canvas
    clip_x0 = 0; clip_x1 = PICO8_BEZEL_W;
    fill (47, 0, 1, PICO8_BEZEL_H, 5);
    fill (48, 0, 1, PICO8_BEZEL_H, 5);
    fill (46, 0, 1, PICO8_BEZEL_H, 0);
    fill (49, 0, 1, PICO8_BEZEL_H, 0);
}

// Palette index of panel pixel (x, y): x 0-47 left panel, 48-95 right.
int pico8_bezel_index (int x, int y)
{
    if (x < 0 || x >= PICO8_BEZEL_W || y < 0 || y >= PICO8_BEZEL_H) return 0;
    return bz[y][x];
}


// ============================================================================
// P8SCII glyphs 128-153
// ----------------------------------------------------------------------------
// A .p8 file stores PICO-8's glyph characters as Unicode (the button glyphs
// as emoji). pico8_fold_glyphs() turns each into its single P8SCII byte in
// string literals, as PICO-8 does -- so #"\U+1F17E" is 1, sub()/ord()
// see one character -- and print() draws bytes 128-153 as these 7x5 icons
// (original pixel art; white, tinted by the pen like the text), in a cell
// two characters wide as PICO-8's wide glyphs are. Kana (154-253) and the
// rest are left as their UTF-8 bytes.
// ============================================================================

static const struct { uint32_t cp; const char *rows[5]; } p8_glyphs[PICO8_GLYPH_COUNT] = {
    { 0x2588,  { "#######", "#######", "#######", "#######", "#######" } },   // 128 block
    { 0x2592,  { "#.#.#.#", ".#.#.#.", "#.#.#.#", ".#.#.#.", "#.#.#.#" } },   // 129 checker
    { 0x1F431, { "#.....#", "##...##", "#.#.#.#", "#######", ".#####." } },   // 130 cat
    { 0x2B07,  { "..###..", "..###..", "#######", ".#####.", "...#..." } },   // 131 down
    { 0x2591,  { "#.#.#.#", ".......", "#.#.#.#", ".......", "#.#.#.#" } },   // 132 dots
    { 0x273D,  { "#..#..#", ".#.#.#.", "..###..", ".#.#.#.", "#..#..#" } },   // 133 sparkle
    { 0x25CF,  { ".#####.", "#######", "#######", "#######", ".#####." } },   // 134 ball
    { 0x2665,  { ".##.##.", "#######", "#######", ".#####.", "...#..." } },   // 135 heart
    { 0x2609,  { ".#####.", "#.....#", "#..#..#", "#.....#", ".#####." } },   // 136 eye
    { 0xC6C3,  { "..###..", "..###..", ".#####.", "...#...", "..#.#.." } },   // 137 person
    { 0x2302,  { "...#...", "..###..", ".#####.", ".##.##.", ".##.##." } },   // 138 house
    { 0x2B05,  { "..#....", ".######", "#######", ".######", "..#...." } },   // 139 left
    { 0x1F610, { ".#####.", "##.#.##", "#######", "##...##", ".#####." } },   // 140 face
    { 0x266A,  { "...##..", "...#.#.", "...#...", ".###...", ".###..." } },   // 141 note
    { 0x1F17E, { ".#####.", "##...##", "##...##", "##...##", ".#####." } },   // 142 O button
    { 0x25C6,  { "...#...", "..###..", ".#####.", "..###..", "...#..." } },   // 143 diamond
    { 0x2026,  { ".......", ".......", ".......", ".......", "#..#..#" } },   // 144 ellipsis
    { 0x27A1,  { "....#..", "######.", "#######", "######.", "....#.." } },   // 145 right
    { 0x2605,  { "...#...", "..###..", "#######", ".#####.", ".#...#." } },   // 146 star
    { 0x29D7,  { "#######", ".#####.", "..###..", ".#####.", "#######" } },   // 147 hourglass
    { 0x2B06,  { "...#...", ".#####.", "#######", "..###..", "..###.." } },   // 148 up
    { 0x02C7,  { ".......", ".#...#.", "..#.#..", "...#...", "......." } },   // 149 caron
    { 0x2227,  { "...#...", "..#.#..", ".#...#.", "#.....#", "......." } },   // 150 wedge
    { 0x274E,  { "##...##", ".##.##.", "..###..", ".##.##.", "##...##" } },   // 151 X button
    { 0x25A4,  { "#######", ".......", "#######", ".......", "#######" } },   // 152 h-lines
    { 0x25A5,  { "#.#.#.#", "#.#.#.#", "#.#.#.#", "#.#.#.#", "#.#.#.#" } },   // 153 v-lines
};

// Pixel (x, y) of the glyph strip in texture 0 (16 glyphs per 6-pixel row,
// 8 pixels apart): 1 if set.
int pico8_glyph_pixel (int x, int y)
{
    int g = (y / 6) * 16 + x / 8, gx = x % 8, gy = y % 6;
    if (g >= PICO8_GLYPH_COUNT || gx >= 7 || gy >= 5) return 0;
    return p8_glyphs[g].rows[gy][gx] == '#';
}

// Decodes one UTF-8 sequence at s -> code point, *n = its length (0: invalid).
static uint32_t utf8 (const unsigned char *s, int *n)
{
    if (s[0] < 0x80) { *n = 1; return s[0]; }
    if ((s[0] & 0xE0) == 0xC0 && (s[1] & 0xC0) == 0x80) { *n = 2; return ((s[0] & 0x1Fu) << 6) | (s[1] & 0x3F); }
    if ((s[0] & 0xF0) == 0xE0 && (s[1] & 0xC0) == 0x80 && (s[2] & 0xC0) == 0x80) {
        *n = 3; return ((s[0] & 0x0Fu) << 12) | ((s[1] & 0x3Fu) << 6) | (s[2] & 0x3F);
    }
    if ((s[0] & 0xF8) == 0xF0 && (s[1] & 0xC0) == 0x80 && (s[2] & 0xC0) == 0x80 && (s[3] & 0xC0) == 0x80) {
        *n = 4; return ((s[0] & 0x07u) << 18) | ((s[1] & 0x3Fu) << 12) | ((s[2] & 0x3Fu) << 6) | (s[3] & 0x3F);
    }
    *n = 0; return 0;
}

// In place: every glyph's UTF-8 (plus an optional U+FE0F variation
// selector) becomes its P8SCII byte 128-153.
void pico8_fold_glyphs (char *str)
{
    unsigned char *r = (unsigned char *) str, *w = (unsigned char *) str;
    while (*r) {
        int n = 0;
        uint32_t cp = (*r >= 0x80) ? utf8 (r, &n) : 0;
        int g = -1;
        if (n > 0)
            for (int i = 0; i < PICO8_GLYPH_COUNT; i++)
                if (p8_glyphs[i].cp == cp) { g = i; break; }
        if (g < 0) { *w++ = *r++; continue; }
        r += n;
        if (r[0] == 0xEF && r[1] == 0xB8 && r[2] == 0x8F) r += 3;   // U+FE0F
        *w++ = (unsigned char) (128 + g);
    }
    *w = 0;
}
