#include "v32lua.h"

// ============================================================================
// PICO-8 __sfx__ / __music__ playback
// ----------------------------------------------------------------------------
// Vircon32's SPU plays sampled sounds; it has no synthesizer. So the cart's
// tracker data is synthesized HERE, at compile time, into ordinary .vsnd
// sound resources:
//
//   * every one of the cart's 64 SFX -> <out>_sfxNN.vsnd, registered as 64
//     contiguous sound ids (pico8_sfx_base_id + n), so sfx(n) with a
//     dynamic n is still just base + n at runtime;
//   * every music(n) start pattern the program uses -> <out>_musicNN.vsnd,
//     the whole song from pattern n to its loop-end/stop pattern, with the
//     loop-start pattern's sample offset returned so music() can set the
//     sound's loop points and loop it on one SPU channel.
//
// The synth follows PICO-8's documented behavior (8 waveforms, 8 effects,
// speed = ticks per note, 1 tick = 183 samples at 22050 Hz, A4 = pitch 33),
// with waveform shapes modelled on the zepto8 reimplementation. It is an
// approximation, not a bit-exact PICO-8: the SFX editor's filter switches
// (noiz/buzz/detune/reverb/dampen) are ignored.
// ============================================================================

#define P8A_RATE        44100
#define P8A_TICK        366                 // 183 samples @ 22050 Hz
#define P8A_MAX_SECONDS 300                 // safety cap per rendered sound

int pico8_sfx_base_id = -1;

typedef struct {
    int pitch, wave, vol, fx;
} P8Note;

typedef struct {
    int     speed, loop_start, loop_end;
    P8Note  notes[32];
    bool    present;
} P8Sfx;

static P8Sfx p8a_sfx[64];
static bool  p8a_parsed = false;

static int p8a_hex (char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}

static void p8a_parse (void)
{
    if (p8a_parsed) return;
    p8a_parsed = true;
    for (int n = 0; n < 64; n++) {
        const char *l = pico8_sfx_line (n);
        P8Sfx *s = &p8a_sfx[n];
        memset (s, 0, sizeof (*s));
        s->speed = 1;
        if (l == NULL || strlen (l) < 8) continue;
        s->present    = true;
        s->speed      = p8a_hex (l[2]) * 16 + p8a_hex (l[3]);
        s->loop_start = p8a_hex (l[4]) * 16 + p8a_hex (l[5]);
        s->loop_end   = p8a_hex (l[6]) * 16 + p8a_hex (l[7]);
        if (s->speed < 1) s->speed = 1;
        size_t len = strlen (l);
        for (int i = 0; i < 32; i++) {
            size_t o = 8 + (size_t) i * 5;
            if (o + 5 > len) break;
            s->notes[i].pitch = p8a_hex (l[o]) * 16 + p8a_hex (l[o + 1]);
            s->notes[i].wave  = p8a_hex (l[o + 2]);   // 8..15 = custom instrument
            s->notes[i].vol   = p8a_hex (l[o + 3]) & 7;
            s->notes[i].fx    = p8a_hex (l[o + 4]) & 7;
        }
    }
}

// Length in notes of one pass through an SFX, and whether it loops.
// PICO-8: loop_start < loop_end -> loops back to loop_start after loop_end;
// loop_end == 0 with loop_start > 0 -> the SFX is loop_start notes long.
static int p8a_sfx_notes (const P8Sfx *s, bool *loops)
{
    if (s->loop_end == 0 && s->loop_start > 0) {
        *loops = false;
        return s->loop_start > 32 ? 32 : s->loop_start;
    }
    if (s->loop_start < s->loop_end) {
        *loops = true;
        return s->loop_end > 32 ? 32 : s->loop_end;
    }
    *loops = false;
    return 32;
}

// ---------------------------------------------------------------------------
// One voice: plays SFX data note by note into a float buffer.
// ---------------------------------------------------------------------------
typedef struct {
    double phase;          // oscillator phase, in cycles (not wrapped)
    double noise, noise_t; // noise generator state
    uint32_t rng;
    double last_freq;      // for slides
    double last_vol;
} P8Voice;

static double p8a_freq (double pitch)
{
    return 440.0 * pow (2.0, (pitch - 33.0) / 12.0);
}

static double p8a_rand (P8Voice *v)
{
    v->rng = v->rng * 1664525u + 1013904223u;
    return ((v->rng >> 8) & 0xFFFF) / 32768.0 - 1.0;
}

static double p8a_wave (P8Voice *v, int wave, double freq)
{
    double adv = v->phase;
    double t = adv - floor (adv);
    switch (wave & 7) {
    case 0:  return 0.5 * (fabs (4.0 * t - 2.0) - 1.0);                      // triangle
    case 1: { const double a = 0.9;                                            // tilted saw
              double r = t < a ? 2.0 * t / a - 1.0 : 2.0 * (1.0 - t) / (1.0 - a) - 1.0;
              return r * 0.5; }
    case 2:  return 0.653 * (t < 0.5 ? t : t - 1.0);                           // saw
    case 3:  return t < 0.5 ? 0.25 : -0.25;                                    // square
    case 4:  return t < 1.0 / 3.0 ? 0.25 : -0.25;                              // pulse
    case 5: { double r = t < 0.5 ? 3.0 - fabs (24.0 * t - 6.0)                 // organ
                                 : 1.0 - fabs (16.0 * t - 12.0);
              return r / 9.0; }
    case 6: { // noise: sample-and-hold white noise, rate tied to the note,
              // smoothed -- brownish, brighter for higher notes.
              v->noise_t += freq / P8A_RATE * 8.0;
              if (v->noise_t >= 1.0) { v->noise_t -= floor (v->noise_t); v->noise = p8a_rand (v); }
              return v->noise * 0.3; }
    default: { double k = fabs (2.0 * fmod (adv / 128.0, 1.0) - 1.0);          // phaser
               double u = fmod (t + 0.5 * k, 1.0);
               return (fabs (4.0 * u - 2.0) - fabs (8.0 * t - 4.0)) / 6.0; }
    }
}

static void p8a_play_sfx (float *out, long out_len, long start, long max_samples,
                          int sfx_index, double pitch_shift, double vol_scale,
                          P8Voice *v, int depth);

// Renders `notes_to_play` notes (following the SFX's own loop) starting at
// sample `start`, never past `start + max_samples`.
static void p8a_play_sfx (float *out, long out_len, long start, long max_samples,
                          int sfx_index, double pitch_shift, double vol_scale,
                          P8Voice *v, int depth)
{
    const P8Sfx *s = &p8a_sfx[sfx_index & 63];
    if (!s->present) return;
    bool loops;
    int  end = p8a_sfx_notes (s, &loops);
    long note_len = (long) s->speed * P8A_TICK;
    long pos = start, limit = start + max_samples;
    if (limit > out_len) limit = out_len;
    int  i = 0;

    while (pos < limit) {
        const P8Note *n = &s->notes[i];
        double base_freq = p8a_freq (n->pitch + pitch_shift);
        double vol = n->vol / 7.0 * vol_scale;
        double prev_freq = v->last_freq > 0 ? v->last_freq : base_freq;
        double prev_vol  = v->last_vol;

        if (n->wave >= 8 && n->vol > 0 && depth == 0) {
            // Custom instrument: SFX (wave-8) played at this note's pitch.
            P8Voice sub = *v;
            long len = note_len;
            if (pos + len > limit) len = limit - pos;
            p8a_play_sfx (out, out_len, pos, len, n->wave - 8,
                          (n->pitch + pitch_shift) - 24.0, vol, &sub, depth + 1);
            v->phase = sub.phase;
        } else if (n->vol > 0) {
            // Arpeggio group: the 4-note block this note sits in.
            int grp = i & ~3;
            int nx  = (i + 1 < end) ? i + 1 : (loops ? s->loop_start : -1);
            bool next_silent = nx < 0 || s->notes[nx].vol == 0;
            for (long k = 0; k < note_len && pos + k < limit; k++) {
                double u = (double) k / note_len;           // 0..1 through the note
                double f = base_freq, a = vol;
                switch (n->fx) {
                case 1: f = prev_freq + (base_freq - prev_freq) * u;           // slide
                        a = prev_vol  + (vol - prev_vol) * u; break;
                case 2: f = base_freq * pow (2.0, 0.25 / 12.0 *                // vibrato
                            sin (2.0 * M_PI * 7.5 * (pos + k) / P8A_RATE)); break;
                case 3: f = base_freq * (1.0 - u); break;                      // drop
                case 4: a = vol * u; break;                                    // fade in
                case 5: a = vol * (1.0 - u); break;                            // fade out
                case 6: case 7: {                                              // arpeggio
                        int ticks = (n->fx == 6 ? 2 : 4) * (s->speed <= 8 ? 1 : 2) / 2;
                        if (ticks < 1) ticks = 1;
                        int step = (int)((k / P8A_TICK) / ticks) & 3;
                        f = p8a_freq (s->notes[grp + step].pitch + pitch_shift);
                        break; }
                }
                v->phase += f / P8A_RATE;
                double smp = p8a_wave (v, n->wave, f) * a;
                // short ramps into/out of silence, to avoid clicks
                if (k < 64 && prev_vol == 0) smp *= k / 64.0;
                if (next_silent && note_len - 1 - k < 64) smp *= (note_len - 1 - k) / 64.0;
                out[pos + k] += (float) smp;
            }
        }
        v->last_freq = base_freq;
        v->last_vol  = n->vol > 0 ? vol : 0;
        pos += note_len;
        i++;
        if (i >= end) {
            if (!loops) break;
            i = s->loop_start;
        }
    }
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------
static void p8a_output_path (char *buf, size_t size, const char *suffix)
{
    const char *asm_name = g_asm_filename ? g_asm_filename : "out.asm";
    const char *dot = strrchr (asm_name, '.');
    int stem = dot ? (int)(dot - asm_name) : (int) strlen (asm_name);
    snprintf (buf, size, "%.*s_%s.vsnd", stem, asm_name, suffix);
}

static bool p8a_write_vsnd (const char *path, const float *buf, long len)
{
    FILE *f = fopen (path, "wb");
    if (f == NULL) {
        compiler_warning (ERR_SEMANTIC, -1, "could not write PICO-8 sound '%s'", path);
        return false;
    }
    if (len < 1) len = 1;
    uint32_t n = (uint32_t) len;
    fwrite ("V32-VSND", 1, 8, f);
    fwrite (&n, 4, 1, f);
    for (long i = 0; i < len; i++) {
        double x = buf ? buf[i] * 0.7 : 0.0;
        if (x > 1.0) x = 1.0;
        if (x < -1.0) x = -1.0;
        int16_t v = (int16_t) lrint (x * 32767.0);
        fwrite (&v, 2, 1, f);
        fwrite (&v, 2, 1, f);
    }
    fclose (f);
    return true;
}

// Renders SFX n as a one-shot: one pass up to its loop end (sfx() on
// Vircon32 doesn't loop).
static long p8a_render_sfx (int n, float **out)
{
    const P8Sfx *s = &p8a_sfx[n];
    *out = NULL;
    if (!s->present) return 0;
    bool loops;
    int  notes = p8a_sfx_notes (s, &loops);
    long len = (long) notes * s->speed * P8A_TICK;
    if (len > (long) P8A_MAX_SECONDS * P8A_RATE) len = (long) P8A_MAX_SECONDS * P8A_RATE;

    // One pass only (sfx() doesn't loop on Vircon32); trim trailing silence.
    {
        int last = notes - 1;
        while (last >= 0 && s->notes[last].vol == 0) last--;
        if (last < 0) return 0;
        len = (long)(last + 1) * s->speed * P8A_TICK;
    }
    float *buf = calloc ((size_t) len, sizeof (float));
    if (buf == NULL) return 0;
    P8Voice v = { .rng = 0x1234567u + (uint32_t) n };
    p8a_play_sfx (buf, len, 0, len, n, 0.0, 1.0, &v, 0);
    *out = buf;
    return len;
}

bool register_pico8_sfx_sounds (void)
{
    if (pico8_sfx_base_id >= 0) return true;
    if (!pico8_has_audio ()) return false;
    p8a_parse ();

    for (int n = 0; n < 64; n++) {
        char path[1024], name[64], suffix[16];
        snprintf (suffix, sizeof (suffix), "sfx%02d", n);
        p8a_output_path (path, sizeof (path), suffix);
        float *buf;
        long len = p8a_render_sfx (n, &buf);
        p8a_write_vsnd (path, buf, len);
        free (buf);

        snprintf (name, sizeof (name), "__pico8_sfx%02d", n);
        int id = next_sound_id++;
        if (pico8_sfx_base_id < 0) pico8_sfx_base_id = id;
        cart_resource_append (&sounds_head, &sounds_tail, id, name, path);
    }
    return true;
}

// ---------------------------------------------------------------------------
// Music
// ---------------------------------------------------------------------------
typedef struct {
    int  flags;
    int  ch[4];         // sfx index, or -1 when the channel is off
} P8Pattern;

static bool p8a_pattern (int p, P8Pattern *pat)
{
    const char *l = pico8_music_line (p);
    if (l == NULL || strlen (l) < 11) return false;
    pat->flags = p8a_hex (l[0]) * 16 + p8a_hex (l[1]);
    bool any = false;
    for (int c = 0; c < 4; c++) {
        int b = p8a_hex (l[3 + c * 2]) * 16 + p8a_hex (l[4 + c * 2]);
        pat->ch[c] = (b & 0x40) ? -1 : (b & 0x3F);
        if (pat->ch[c] >= 0) any = true;
    }
    return any;
}

// Pattern length in samples: the leftmost non-looping channel decides; if
// every channel loops, the leftmost channel's loop length does.
static long p8a_pattern_len (const P8Pattern *pat)
{
    int first = -1;
    for (int c = 0; c < 4; c++) {
        if (pat->ch[c] < 0) continue;
        const P8Sfx *s = &p8a_sfx[pat->ch[c]];
        bool loops;
        int notes = p8a_sfx_notes (s, &loops);
        if (!loops) return (long) notes * s->speed * P8A_TICK;
        if (first < 0) first = c;
    }
    if (first < 0) return 0;
    const P8Sfx *s = &p8a_sfx[pat->ch[first]];
    bool loops;
    return (long) p8a_sfx_notes (s, &loops) * s->speed * P8A_TICK;
}

typedef struct { int pattern, id; int loop_start, loop_end; bool loops; } P8Song;
static P8Song p8a_songs[64];
static int    p8a_song_count = 0;

int pico8_music_sound (int start, int *loop_start, int *loop_end, bool *loops)
{
    for (int i = 0; i < p8a_song_count; i++) {
        if (p8a_songs[i].pattern == start) {
            *loop_start = p8a_songs[i].loop_start;
            *loop_end   = p8a_songs[i].loop_end;
            *loops      = p8a_songs[i].loops;
            return p8a_songs[i].id;
        }
    }
    if (!pico8_has_audio () || start < 0 || start > 63 || p8a_song_count >= 64) return -1;
    p8a_parse ();

    // Sequence: start .. the first pattern with loop-end (loops back to the
    // nearest loop-start at or before it) or stop, or an empty pattern.
    int  order[64], count = 0, loop_to = -1;
    bool song_loops = false;
    for (int p = start; p < 64 && count < 64; p++) {
        P8Pattern pat;
        if (!p8a_pattern (p, &pat)) break;
        order[count++] = p;
        if (pat.flags & 2) {
            for (int q = p; q >= 0; q--) {
                P8Pattern lp;
                if (p8a_pattern (q, &lp) && (lp.flags & 1)) { loop_to = q; break; }
                if (q == 0) loop_to = 0;
            }
            song_loops = loop_to >= 0;
            break;
        }
        if (pat.flags & 4) break;
    }
    if (count == 0) return -1;

    long total = 0, loop_ofs = 0;
    long lens[64];
    for (int i = 0; i < count; i++) {
        P8Pattern pat;
        p8a_pattern (order[i], &pat);
        lens[i] = p8a_pattern_len (&pat);
        if (song_loops && order[i] == loop_to) loop_ofs = total;
        total += lens[i];
    }
    // A loop back to a pattern before `start`: loop the whole rendered song.
    if (song_loops && loop_to < start) loop_ofs = 0;
    if (total > (long) P8A_MAX_SECONDS * P8A_RATE) total = (long) P8A_MAX_SECONDS * P8A_RATE;

    float *buf = calloc ((size_t)(total > 0 ? total : 1), sizeof (float));
    if (buf == NULL) return -1;
    P8Voice voice[4];
    for (int c = 0; c < 4; c++) memset (&voice[c], 0, sizeof (P8Voice)), voice[c].rng = 0xBEEF + c;
    long pos = 0;
    for (int i = 0; i < count && pos < total; i++) {
        P8Pattern pat;
        p8a_pattern (order[i], &pat);
        for (int c = 0; c < 4; c++) {
            if (pat.ch[c] < 0) continue;
            voice[c].last_freq = 0;
            p8a_play_sfx (buf, total, pos, lens[i], pat.ch[c], 0.0, 1.0, &voice[c], 0);
        }
        pos += lens[i];
    }

    char path[1024], name[64], suffix[16];
    snprintf (suffix, sizeof (suffix), "music%02d", start);
    p8a_output_path (path, sizeof (path), suffix);
    p8a_write_vsnd (path, buf, total);
    free (buf);

    snprintf (name, sizeof (name), "__pico8_music%02d", start);
    int id = next_sound_id++;
    cart_resource_append (&sounds_head, &sounds_tail, id, name, path);

    P8Song *sg = &p8a_songs[p8a_song_count++];
    sg->pattern    = start;
    sg->id         = id;
    sg->loops      = song_loops;
    sg->loop_start = (int) loop_ofs;
    sg->loop_end   = (int)(total - 1);
    *loop_start = sg->loop_start;
    *loop_end   = sg->loop_end;
    *loops      = sg->loops;
    return id;
}

// ---------------------------------------------------------------------------
// Dynamic music(n): every pattern that can start a song is rendered, and a
// 64-entry ROM table maps pattern -> (sound id, loop start, loop end, loop
// flag); __builtin_pico8_music (pico8.s) reads it. Entries are -1 for
// patterns that don't start a song.
// ---------------------------------------------------------------------------
bool pico8_dynamic_music = false;

void pico8_register_all_songs (void)
{
    if (pico8_dynamic_music || !pico8_has_audio ()) return;
    pico8_dynamic_music = true;
    p8a_parse ();
    bool prev_ends = true;               // pattern 0 starts a song
    for (int p = 0; p < 64; p++) {
        P8Pattern pat;
        bool present = p8a_pattern (p, &pat);
        if (present && (prev_ends || (pat.flags & 1))) {
            int ls, le; bool lp;
            pico8_music_sound (p, &ls, &le, &lp);
        }
        prev_ends = !present || (pat.flags & 6);
    }
}

void emit_pico8_music_table (FILE *out)
{
    fprintf (out, "__pico8_music_table:\n");
    for (int p = 0; p < 64; p++) {
        int id = -1, ls = 0, le = 0, lp = 0;
        if (pico8_dynamic_music) {
            for (int i = 0; i < p8a_song_count; i++) {
                if (p8a_songs[i].pattern == p) {
                    id = p8a_songs[i].id; ls = p8a_songs[i].loop_start;
                    le = p8a_songs[i].loop_end; lp = p8a_songs[i].loops ? 1 : 0;
                }
            }
        }
        fprintf (out, "    integer %d, %d, %d, %d\n", id, ls, le, lp);
    }
}
