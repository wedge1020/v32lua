#include "v32lua.h"
#include <ctype.h>

// ============================================================================
// Circle shape atlas (TIC-80 circ/circb, PICO-8 circfill/circ)
// ----------------------------------------------------------------------------
// Drawing a circle pixel by pixel (or span by span) costs dozens to hundreds
// of GPU draws, each with its CPU setup. Instead, every filled circle and
// every outline of radius 0..SHAPES_MAX_R is rendered here, at compile time,
// in white, exactly as the console itself rasterizes it; a circle is then
// ONE zoomed region draw, tinted with the GPU multiply color.
//
//   region r                    filled circle of radius r
//   region SHAPES_MAX_R + 1 + r outline of radius r
//
// Each region is (2r+1) x (2r+1) with its hotspot at the top-left, like the
// sprite regions. Larger circles are drawn by the runtime from the same
// algorithms (tic80.s / pico8.s).
//
// Rasterizers (both checked pixel for pixel against the reference code):
//   TIC-80  core/draw.c drawEllipse() -- Alois Zingl's ellipse-in-rectangle
//           algorithm -- on (x-r, y-r, x+r, y+r); circ() fills between the
//           leftmost and rightmost outline pixel of each row.
//   PICO-8  the midpoint circle of zepto8 (api_circ/api_circfill): err
//           starts at 0, x steps when err >= r - 1; circfill draws the same
//           rows' spans.
// ============================================================================

#define SHAPES_GAP 1                       // transparent pixel between regions

int  shapes_texture_id = -1;               // texture index, -1: no atlas
bool shapes_fast       = false;            // --fast-circles: scale the largest disc
static int shapes_regions[SHAPES_REGIONS][4];   // min x, min y, max x, max y

// Marks the outline of radius r in a (2r+1)^2 grid (row-major, 1 = set).
static void outline_tic80 (int r, uint8_t *g)
{
    int n = 2 * r + 1;
    long long x0 = 0, y0 = 0, x1 = 2 * r, y1 = 2 * r;   // grid coordinates
    long long a = x1 - x0, b = y1 - y0, b1 = b & 1;
    long long dx = 4 * (1 - a) * b * b, dy = 4 * (b1 + 1) * a * a;
    long long err = dx + dy + b1 * a * a, e2;
    y0 += (b + 1) / 2; y1 = y0 - b1;
    a *= 8 * a; b1 = 8 * b * b;
    do {
        g[y0 * n + x1] = 1; g[y0 * n + x0] = 1;
        g[y1 * n + x0] = 1; g[y1 * n + x1] = 1;
        e2 = 2 * err;
        if (e2 <= dy) { y0++; y1--; err += dy += a; }
        if (e2 >= dx || 2 * err > dy) { x0++; x1--; err += dx += b1; }
    } while (x0 <= x1);
    while (y0 - y1 < b && y0 < n && y1 >= 0) {   // never taken for circles
        if (x0 - 1 >= 0) { g[y0 * n + x0 - 1] = 1; g[y1 * n + x0 - 1] = 1; }
        if (x1 + 1 < n)  { g[y0 * n + x1 + 1] = 1; g[y1 * n + x1 + 1] = 1; }
        y0++; y1--;
    }
}

static void outline_pico8 (int r, uint8_t *g)
{
    int n = 2 * r + 1, c = r;
    for (int dx = r, dy = 0, err = 0; dx >= dy; ) {
        int pts[8][2] = { { dx, dy }, { dy, dx }, { -dy, dx }, { -dx, dy },
                          { -dx, -dy }, { -dy, -dx }, { dy, -dx }, { dx, -dy } };
        for (int i = 0; i < 8; i++) g[(c + pts[i][1]) * n + c + pts[i][0]] = 1;
        dy += 1;
        if (err < r - 1) err += 1 + 2 * dy;
        else { dx -= 1; err += 1 + 2 * (dy - dx); }
    }
}

// Fills each row between its leftmost and rightmost set pixel.
static void fill_rows (int r, uint8_t *g)
{
    int n = 2 * r + 1;
    for (int y = 0; y < n; y++) {
        int lo = -1, hi = -1;
        for (int x = 0; x < n; x++) if (g[y * n + x]) { if (lo < 0) lo = x; hi = x; }
        for (int x = lo; lo >= 0 && x <= hi; x++) g[y * n + x] = 1;
    }
}

// Is `name` used as a whole identifier in src?
static bool mentions (const char *src, const char *name)
{
    size_t n = strlen (name);
    for (const char *p = strstr (src, name); p != NULL; p = strstr (p + 1, name)) {
        bool left  = (p == src) || !(isalnum ((unsigned char) p[-1]) || p[-1] == '_');
        bool right = !(isalnum ((unsigned char) p[n]) || p[n] == '_');
        if (left && right) return true;
    }
    return false;
}

bool shapes_wanted (const char *src, bool tic80)
{
    if (src == NULL) return false;
    return mentions (src, "circ") || mentions (src, tic80 ? "circb" : "circfill");
}

// Renders the atlas to `vtex_path` (white shapes on transparent) and records
// the regions. Returns false if the file can't be written.
bool shapes_build (const char *vtex_path, bool tic80)
{
    // Shelf packing, largest first; filled and outline of a radius side by side.
    const int width = 256;
    int x = 0, y = 0, shelf = 0;
    for (int r = SHAPES_MAX_R; r >= 0; r--) {
        int size = 2 * r + 1;
        for (int k = 0; k < 2; k++) {
            if (x + size > width) { y += shelf + SHAPES_GAP; x = 0; shelf = 0; }
            int id = k == 0 ? r : SHAPES_MAX_R + 1 + r;
            shapes_regions[id][0] = x;
            shapes_regions[id][1] = y;
            shapes_regions[id][2] = x + size - 1;
            shapes_regions[id][3] = y + size - 1;
            if (size > shelf) shelf = size;
            x += size + SHAPES_GAP;
        }
    }
    int height = y + shelf;

    uint8_t *pix = calloc ((size_t) width * height, 4);
    uint8_t *g   = malloc ((size_t) (2 * SHAPES_MAX_R + 1) * (2 * SHAPES_MAX_R + 1));
    if (pix == NULL || g == NULL) { free (pix); free (g); return false; }

    for (int id = 0; id < SHAPES_REGIONS; id++) {
        int r = id % (SHAPES_MAX_R + 1), filled = id <= SHAPES_MAX_R, n = 2 * r + 1;
        memset (g, 0, (size_t) n * n);
        if (tic80) outline_tic80 (r, g); else outline_pico8 (r, g);
        if (filled) fill_rows (r, g);
        for (int py = 0; py < n; py++)
            for (int px = 0; px < n; px++) {
                if (!g[py * n + px]) continue;
                uint8_t *o = pix + ((size_t) (shapes_regions[id][1] + py) * width +
                                    shapes_regions[id][0] + px) * 4;
                o[0] = o[1] = o[2] = o[3] = 0xFF;
            }
    }
    free (g);

    FILE *f = fopen (vtex_path, "wb");
    if (f == NULL) { free (pix); return false; }
    VTEXHeader hdr = { .width = (uint32_t) width, .height = (uint32_t) height };
    memcpy (hdr.magic, "V32-VTEX", 8);
    fwrite (&hdr, sizeof hdr, 1, f);
    fwrite (pix, 4, (size_t) width * height, f);
    fclose (f);
    free (pix);
    return true;
}

// Builds and registers the atlas as the next texture when the program draws
// circles (`src` mentions them). base_path: output name minus extension.
void register_shapes_texture (const char *src, const char *base_path, bool tic80)
{
    if (!shapes_wanted (src, tic80)) return;
    char path[300], vtex[310];
    snprintf (path, sizeof path, "%s_shapes", base_path);
    snprintf (vtex, sizeof vtex, "%s.vtex", path);
    if (!shapes_build (vtex, tic80)) {
        compiler_warning (ERR_INTERNAL, -1,
            "could not write '%s'; circles are drawn without the shape atlas", vtex);
        return;
    }
    shapes_texture_id = next_texture_id;
    cart_resource_append (&textures_head, &textures_tail, next_texture_id++, "shapes", path);
}

// __shapes_init (called by the API's init) sets up the regions; without an
// atlas it only returns. SHAPES_TEXTURE / SHAPES_MAX_R are %defines (emit.c).
void emit_shapes_runtime (FILE *out)
{
    fprintf (out, "\n;; --- circle shape atlas (shapes.c): %s ---\n",
             shapes_texture_id >= 0 ? "texture " : "none");
    fprintf (out, "__shapes_init:\n");
    if (shapes_texture_id < 0) {
        fprintf (out, "    RET\n");
        return;
    }
    fprintf (out,
        "    PUSH  R1\n"
        "    PUSH  R2\n"
        "    PUSH  R3\n"
        "    OUT   GPU_SelectedTexture, SHAPES_TEXTURE\n"
        "    MOV   R1, 0\n"
        "    MOV   R2, __shapes_regions\n"
        "_shapes_init_loop:\n"
        "    OUT   GPU_SelectedRegion, R1\n"
        "    MOV   R3, [R2]\n"
        "    OUT   GPU_RegionMinX, R3\n"
        "    OUT   GPU_RegionHotspotX, R3\n"
        "    MOV   R3, [R2+1]\n"
        "    OUT   GPU_RegionMinY, R3\n"
        "    OUT   GPU_RegionHotspotY, R3\n"
        "    MOV   R3, [R2+2]\n"
        "    OUT   GPU_RegionMaxX, R3\n"
        "    MOV   R3, [R2+3]\n"
        "    OUT   GPU_RegionMaxY, R3\n"
        "    IADD  R2, 4\n"
        "    IADD  R1, 1\n"
        "    MOV   R3, R1\n"
        "    ILT   R3, %d\n"
        "    JT    R3, _shapes_init_loop\n"
        "    POP   R3\n"
        "    POP   R2\n"
        "    POP   R1\n"
        "    RET\n"
        "__shapes_regions:\n", SHAPES_REGIONS);
    for (int id = 0; id < SHAPES_REGIONS; id++)
        fprintf (out, "    integer %d, %d, %d, %d\n", shapes_regions[id][0], shapes_regions[id][1],
                 shapes_regions[id][2], shapes_regions[id][3]);
}
