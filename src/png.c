#include "v32lua.h"

// ============================================================================
// A small PNG reader (for custom PICO-8 bezel art, --bezel)
// ----------------------------------------------------------------------------
// Decodes non-interlaced PNGs of every standard color type -- grayscale,
// RGB, palette (with tRNS transparency), gray+alpha, RGBA -- at bit depth 8
// (palette and grayscale also 1, 2 and 4; 16-bit samples are reduced to
// their high byte) into 8-bit RGBA. zlib's inflate (stored, fixed and
// dynamic Huffman blocks) is implemented here, so the compiler still needs
// no libraries.
// ============================================================================

typedef struct {
    const uint8_t *src;
    size_t         len, pos;
    uint32_t       bitbuf;
    int            bitcnt;
    uint8_t       *out;
    size_t         out_len, out_cap;
    bool           error;
} Inflate;

static int getbit (Inflate *s)
{
    if (s->bitcnt == 0) {
        if (s->pos >= s->len) { s->error = true; return 0; }
        s->bitbuf = s->src[s->pos++];
        s->bitcnt = 8;
    }
    int b = (int) (s->bitbuf & 1);
    s->bitbuf >>= 1;
    s->bitcnt--;
    return b;
}

static int getbits (Inflate *s, int n)
{
    int v = 0;
    for (int i = 0; i < n; i++) v |= getbit (s) << i;
    return v;
}

static void put (Inflate *s, uint8_t b)
{
    if (s->out_len >= s->out_cap) { s->error = true; return; }
    s->out[s->out_len++] = b;
}

typedef struct { short count[16]; short symbol[288]; } Huffman;

static void build (Huffman *h, const uint8_t *lengths, int n)
{
    memset (h->count, 0, sizeof h->count);
    for (int i = 0; i < n; i++) h->count[lengths[i]]++;
    h->count[0] = 0;
    short offs[16];
    offs[1] = 0;
    for (int i = 1; i < 15; i++) offs[i + 1] = (short) (offs[i] + h->count[i]);
    for (int i = 0; i < n; i++)
        if (lengths[i]) h->symbol[offs[lengths[i]]++] = (short) i;
}

static int decode (Inflate *s, const Huffman *h)
{
    int code = 0, first = 0, index = 0;
    for (int len = 1; len < 16; len++) {
        code |= getbit (s);
        int count = h->count[len];
        if (code - count < first) return h->symbol[index + (code - first)];
        index += count;
        first += count;
        first <<= 1;
        code <<= 1;
        if (s->error) return -1;
    }
    s->error = true;
    return -1;
}

static const short len_base[29]  = { 3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258 };
static const short len_extra[29] = { 0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0 };
static const short dist_base[30] = { 1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577 };
static const short dist_extra[30]= { 0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13 };

static void codes (Inflate *s, const Huffman *lit, const Huffman *dist)
{
    for (;;) {
        int sym = decode (s, lit);
        if (s->error || sym < 0) return;
        if (sym < 256) { put (s, (uint8_t) sym); continue; }
        if (sym == 256) return;
        sym -= 257;
        if (sym >= 29) { s->error = true; return; }
        int len = len_base[sym] + getbits (s, len_extra[sym]);
        int ds = decode (s, dist);
        if (ds < 0 || ds >= 30) { s->error = true; return; }
        size_t d = (size_t) (dist_base[ds] + getbits (s, dist_extra[ds]));
        if (d > s->out_len) { s->error = true; return; }
        for (int i = 0; i < len; i++) put (s, s->out[s->out_len - d]);
        if (s->error) return;
    }
}

static bool inflate_zlib (const uint8_t *src, size_t len, uint8_t *out, size_t cap, size_t *out_len)
{
    if (len < 2 || (src[0] & 15) != 8) return false;
    Inflate s = { .src = src, .len = len, .pos = 2, .out = out, .out_cap = cap };
    int last;
    do {
        last = getbit (&s);
        int type = getbits (&s, 2);
        if (type == 0) {
            s.bitcnt = 0;
            if (s.pos + 4 > s.len) return false;
            unsigned n = s.src[s.pos] | (unsigned) s.src[s.pos + 1] << 8;
            s.pos += 4;
            if (s.pos + n > s.len) return false;
            for (unsigned i = 0; i < n; i++) put (&s, s.src[s.pos++]);
        } else if (type == 1) {
            static Huffman lit, dist;
            uint8_t l[288];
            int i = 0;
            for (; i < 144; i++) l[i] = 8;
            for (; i < 256; i++) l[i] = 9;
            for (; i < 280; i++) l[i] = 7;
            for (; i < 288; i++) l[i] = 8;
            build (&lit, l, 288);
            for (i = 0; i < 30; i++) l[i] = 5;
            build (&dist, l, 30);
            codes (&s, &lit, &dist);
        } else if (type == 2) {
            int nlen = getbits (&s, 5) + 257, ndist = getbits (&s, 5) + 1, ncode = getbits (&s, 4) + 4;
            static const uint8_t order[19] = { 16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15 };
            uint8_t l[320] = { 0 };
            for (int i = 0; i < ncode; i++) l[order[i]] = (uint8_t) getbits (&s, 3);
            Huffman lencode, lit, dist;
            build (&lencode, l, 19);
            int idx = 0;
            memset (l, 0, sizeof l);
            while (idx < nlen + ndist) {
                int sym = decode (&s, &lencode);
                if (s.error || sym < 0) return false;
                if (sym < 16) { l[idx++] = (uint8_t) sym; continue; }
                int rep = 0; uint8_t v = 0;
                if (sym == 16) { if (idx == 0) return false; v = l[idx - 1]; rep = 3 + getbits (&s, 2); }
                else if (sym == 17) rep = 3 + getbits (&s, 3);
                else rep = 11 + getbits (&s, 7);
                if (idx + rep > nlen + ndist) return false;
                while (rep--) l[idx++] = v;
            }
            build (&lit, l, nlen);
            build (&dist, l + nlen, ndist);
            codes (&s, &lit, &dist);
        } else {
            return false;
        }
        if (s.error) return false;
    } while (!last);
    *out_len = s.out_len;
    return true;
}

static uint32_t be32 (const uint8_t *p) { return (uint32_t) p[0] << 24 | (uint32_t) p[1] << 16 | (uint32_t) p[2] << 8 | p[3]; }

static int paeth (int a, int b, int c)
{
    int p = a + b - c, pa = abs (p - a), pb = abs (p - b), pc = abs (p - c);
    return (pa <= pb && pa <= pc) ? a : (pb <= pc) ? b : c;
}

// Returns an RGBA buffer (malloc'd; *w, *h set) or NULL with *err set.
uint8_t *png_load_rgba (const char *path, int *w, int *h, const char **err)
{
    *err = NULL;
    FILE *f = fopen (path, "rb");
    if (f == NULL) { *err = "cannot open the file"; return NULL; }
    fseek (f, 0, SEEK_END);
    long n = ftell (f);
    rewind (f);
    uint8_t *file = malloc ((size_t) n);
    if (file == NULL || fread (file, 1, (size_t) n, f) != (size_t) n) { fclose (f); free (file); *err = "cannot read the file"; return NULL; }
    fclose (f);

    uint8_t *idat = NULL, *raw = NULL, *rgba = NULL;
    size_t idat_len = 0;
    uint8_t plte[256][4];
    int plte_n = 0;
    int width = 0, height = 0, depth = 0, ctype = 0, interlace = 0;
    bool have_trns_gray = false; int trns_gray = 0;
    bool have_trns_rgb = false;  int trns_r = 0, trns_g = 0, trns_b = 0;
    for (int i = 0; i < 256; i++) plte[i][3] = 255;

    if (n < 8 || memcmp (file, "\x89PNG\r\n\x1a\n", 8) != 0) { *err = "not a PNG file"; goto fail; }
    for (size_t p = 8; p + 12 <= (size_t) n; ) {
        uint32_t len = be32 (file + p);
        const uint8_t *type = file + p + 4, *data = file + p + 8;
        if (p + 12 + len > (size_t) n) { *err = "truncated PNG"; goto fail; }
        if (memcmp (type, "IHDR", 4) == 0) {
            width = (int) be32 (data); height = (int) be32 (data + 4);
            depth = data[8]; ctype = data[9]; interlace = data[12];
        } else if (memcmp (type, "PLTE", 4) == 0) {
            plte_n = (int) (len / 3);
            for (int i = 0; i < plte_n && i < 256; i++) {
                plte[i][0] = data[i * 3]; plte[i][1] = data[i * 3 + 1]; plte[i][2] = data[i * 3 + 2];
            }
        } else if (memcmp (type, "tRNS", 4) == 0) {
            if (ctype == 3) for (uint32_t i = 0; i < len && i < 256; i++) plte[i][3] = data[i];
            else if (ctype == 0 && len >= 2) { have_trns_gray = true; trns_gray = data[1]; }
            else if (ctype == 2 && len >= 6) { have_trns_rgb = true; trns_r = data[1]; trns_g = data[3]; trns_b = data[5]; }
        } else if (memcmp (type, "IDAT", 4) == 0) {
            uint8_t *t = realloc (idat, idat_len + len);
            if (t == NULL) { *err = "out of memory"; goto fail; }
            idat = t;
            memcpy (idat + idat_len, data, len);
            idat_len += len;
        } else if (memcmp (type, "IEND", 4) == 0) {
            break;
        }
        p += 12 + len;
    }
    if (width <= 0 || height <= 0 || width > 4096 || height > 4096) { *err = "bad image size"; goto fail; }
    if (interlace) { *err = "interlaced PNGs are not supported (save it without interlacing)"; goto fail; }
    int channels = ctype == 0 ? 1 : ctype == 2 ? 3 : ctype == 3 ? 1 : ctype == 4 ? 2 : ctype == 6 ? 4 : 0;
    if (channels == 0 || !(depth == 1 || depth == 2 || depth == 4 || depth == 8 || depth == 16) ||
        (depth < 8 && ctype != 0 && ctype != 3) || (depth == 16 && ctype == 3)) {
        *err = "unsupported PNG color type or bit depth"; goto fail;
    }
    int bpp_bits = channels * depth;
    size_t stride = ((size_t) width * bpp_bits + 7) / 8;
    int bpp = (bpp_bits + 7) / 8;            // bytes per pixel for filtering
    size_t raw_cap = (stride + 1) * (size_t) height, raw_len = 0;
    raw = malloc (raw_cap);
    if (raw == NULL) { *err = "out of memory"; goto fail; }
    if (!inflate_zlib (idat, idat_len, raw, raw_cap, &raw_len) || raw_len < raw_cap) {
        *err = "corrupt PNG data"; goto fail;
    }
    // undo the row filters in place
    for (int y = 0; y < height; y++) {
        uint8_t *row = raw + (size_t) y * (stride + 1);
        uint8_t *cur = row + 1, *prev = y > 0 ? raw + (size_t) (y - 1) * (stride + 1) + 1 : NULL;
        for (size_t x = 0; x < stride; x++) {
            int a = x >= (size_t) bpp ? cur[x - bpp] : 0;
            int b = prev ? prev[x] : 0;
            int c = (prev && x >= (size_t) bpp) ? prev[x - bpp] : 0;
            switch (row[0]) {
                case 0: break;
                case 1: cur[x] = (uint8_t) (cur[x] + a); break;
                case 2: cur[x] = (uint8_t) (cur[x] + b); break;
                case 3: cur[x] = (uint8_t) (cur[x] + ((a + b) >> 1)); break;
                case 4: cur[x] = (uint8_t) (cur[x] + paeth (a, b, c)); break;
                default: *err = "corrupt PNG filter"; goto fail;
            }
        }
    }
    rgba = malloc ((size_t) width * height * 4);
    if (rgba == NULL) { *err = "out of memory"; goto fail; }
    for (int y = 0; y < height; y++) {
        const uint8_t *row = raw + (size_t) y * (stride + 1) + 1;
        for (int x = 0; x < width; x++) {
            uint8_t *o = rgba + ((size_t) y * width + x) * 4;
            int s[4];
            for (int c = 0; c < channels; c++) {
                if (depth == 8)       s[c] = row[x * channels + c];
                else if (depth == 16) s[c] = row[(x * channels + c) * 2];
                else {
                    int bit = x * depth, v = (row[bit / 8] >> (8 - depth - bit % 8)) & ((1 << depth) - 1);
                    s[c] = v;
                }
            }
            int r, g, b, a = 255;
            if (ctype == 3) {
                int i = s[0];
                r = plte[i][0]; g = plte[i][1]; b = plte[i][2]; a = plte[i][3];
            } else if (ctype == 0 || ctype == 4) {
                int v = s[0];
                if (have_trns_gray && v == trns_gray) a = 0;
                if (depth < 8) v = v * 255 / ((1 << depth) - 1);
                r = g = b = v;
                if (ctype == 4) a = s[1];
            } else {
                r = s[0]; g = s[1]; b = s[2];
                if (ctype == 6) a = s[3];
                else if (have_trns_rgb && r == trns_r && g == trns_g && b == trns_b) a = 0;
            }
            o[0] = (uint8_t) r; o[1] = (uint8_t) g; o[2] = (uint8_t) b; o[3] = (uint8_t) a;
        }
    }
    free (file); free (idat); free (raw);
    *w = width; *h = height;
    return rgba;
fail:
    free (file); free (idat); free (raw); free (rgba);
    return NULL;
}
