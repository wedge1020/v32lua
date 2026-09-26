#include "v32lua.h"
#include <ctype.h>

// ============================================================================
// TIC-80 <WAVES> / <SFX> / <PATTERNS> / <TRACKS> playback
// ----------------------------------------------------------------------------
// Same approach as the PICO-8 layer (pico8_audio.c): the SPU only plays
// sampled sound, so the cart's sound is synthesized HERE, at compile time,
// into ordinary .vsnd resources. The synthesizer is a port of TIC-80's own
// sound engine (src/core/sound.c): the per-tick (60 Hz) sfx envelope
// machine -- volume / wave / chord / pitch envelopes with their loops and
// speed -- the music sequencer with its commands (M C J S P V D), and the
// register synthesis: a 32-step 4-bit waveform stepped every
// CLOCKRATE*2/32/(2*freq) - 1 clocks, or the LFSR noise channel, box-
// filtered down to the output rate and high-passed like TIC-80's blip_buf.
//
//   * music(track): each track the program can play is rendered as ONE
//     looping sound (all four channels mixed, in stereo) -- from frame 0
//     until the sequencer comes back to a frame/row it has already played
//     (the end of the track, an empty frame, or a J jump), which becomes the
//     sound's loop point. music(track, frame, row) starts at that frame's
//     offset; loop=false turns the channel loop off. SPU channel 0.
//   * sfx(id, note, ...): an SFX is an instrument played at a note, so it is
//     rendered once per note the program uses: the SFX's own default note,
//     every literal note found at an sfx() call, and -- when a call passes a
//     computed note (warm_wheels' engine) -- one reference render per octave
//     (at F#), played at the SPU speed that gives the requested pitch. Each
//     render loops over the SFX's sustained part (TIC-80 plays an SFX until
//     its duration runs out or it is replaced); a sustain that is silent
//     ends the sound instead. TIC-80 channel c -> SPU channel 4 + c.
//
// Rate: --rate / --#rate (default 22050 Hz), shared with the PICO-8 layer.
// Differences from TIC-80: an sfx() on a channel does not silence that
// channel of the music (music is pre-mixed); a computed note is up to half
// an octave away from its render, so its envelope runs up to 1.41x faster
// or slower; the sfx() speed argument and music() tempo/speed/sustain
// arguments are not reproduced.
// ============================================================================

#define T80_CLOCKRATE   (255 << 13)                 // TIC-80 core clock
#define T80_ENDTIME     (T80_CLOCKRATE / 60)        // clocks per tick
#define T80_RATE        synth_audio_rate
#define T80_MAX_TICKS   (60 * 60 * 10)              // 10 minutes per track
#define T80_GAIN        2.0

static const uint16_t NoteFreqs[] = { 0x10, 0x11, 0x12, 0x13, 0x15, 0x16, 0x17, 0x18, 0x1a, 0x1c, 0x1d, 0x1f, 0x21, 0x23, 0x25, 0x27, 0x29, 0x2c, 0x2e, 0x31, 0x34, 0x37, 0x3a, 0x3e, 0x41, 0x45, 0x49, 0x4e, 0x52, 0x57, 0x5c, 0x62, 0x68, 0x6e, 0x75, 0x7b, 0x83, 0x8b, 0x93, 0x9c, 0xa5, 0xaf, 0xb9, 0xc4, 0xd0, 0xdc, 0xe9, 0xf7, 0x106, 0x115, 0x126, 0x137, 0x14a, 0x15d, 0x172, 0x188, 0x19f, 0x1b8, 0x1d2, 0x1ee, 0x20b, 0x22a, 0x24b, 0x26e, 0x293, 0x2ba, 0x2e4, 0x310, 0x33f, 0x370, 0x3a4, 0x3dc, 0x417, 0x455, 0x497, 0x4dd, 0x527, 0x575, 0x5c8, 0x620, 0x67d, 0x6e0, 0x749, 0x7b8, 0x82d, 0x8a9, 0x92d, 0x9b9, 0xa4d, 0xaea, 0xb90, 0xc40, 0xcfa, 0xdc0, 0xe91, 0xf6f, 0x105a, 0x1153, 0x125b, 0x1372, 0x149a, 0x15d4, 0x1720, 0x1880 };
#define T80_NOTE_COUNT ((int)(sizeof (NoteFreqs) / sizeof (NoteFreqs[0])))

// ---------------------------------------------------------------------------
// Cart data (bank 0), filled from the text sections by tic80_assets.c
// ---------------------------------------------------------------------------
static uint8_t t80_waves[16 * 16];
static uint8_t t80_samples[64 * 66];
static uint8_t t80_patterns[60 * 192];
static uint8_t t80_tracks[8 * 51];
static bool    t80_have_sfx = false, t80_have_music = false;

// TIC-80 writes these sections with each byte's two hex digits swapped.
void tic80_audio_store_row (const char *section, int row, const char *hex)
{
    uint8_t *dst = NULL;
    int rows = 0, size = 0;
    if      (strcmp (section, "WAVES")    == 0) { dst = t80_waves;    rows = 16; size = 16;  }
    else if (strcmp (section, "SFX")      == 0) { dst = t80_samples;  rows = 64; size = 66;  t80_have_sfx = true; }
    else if (strcmp (section, "PATTERNS") == 0) { dst = t80_patterns; rows = 60; size = 192; t80_have_music = true; }
    else if (strcmp (section, "TRACKS")   == 0) { dst = t80_tracks;   rows = 8;  size = 51;  t80_have_music = true; }
    if (dst == NULL || row < 0 || row >= rows) return;
    for (int i = 0; i < size && hex[i * 2] && hex[i * 2 + 1]; i++) {
        char pair[3] = { hex[i * 2 + 1], hex[i * 2], 0 };
        dst[row * size + i] = (uint8_t) strtoul (pair, NULL, 16);
    }
}

// TIC-80 fills an empty cart's waveforms with its defaults (tic_cart_load:
// CHUNK_DEFAULT). A .lua export omits a <WAVES> section equal to them.
static void t80_default_waves_if_empty (void)
{
    static const uint8_t def[48] = {
        0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff,
        0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe, 0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0x01,
        0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe, 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe };
    for (size_t i = 0; i < sizeof t80_waves; i++) if (t80_waves[i]) return;
    memcpy (t80_waves, def, sizeof def);
}

// ---------------------------------------------------------------------------
// Decoded structures (tic.h, little-endian bitfield layout)
// ---------------------------------------------------------------------------
typedef struct { int start, size; } T80Loop;
typedef struct {
    int volume[30], wave[30], chord[30], pitch[30];
    int octave, pitch16x, speed, reverse, note, stereo_left, stereo_right;
    T80Loop loops[4];        // wave, volume, chord, pitch (tic_sfx_pos order)
} T80Sample;

static void t80_sample (int n, T80Sample *s)
{
    const uint8_t *b = t80_samples + n * 66;
    for (int i = 0; i < 30; i++) {
        s->volume[i] = b[i * 2] & 15;
        s->wave[i]   = b[i * 2] >> 4;
        s->chord[i]  = b[i * 2 + 1] & 15;
        int p = b[i * 2 + 1] >> 4;
        s->pitch[i]  = p >= 8 ? p - 16 : p;            // s8 pitch:4
    }
    s->octave   = b[60] & 7;
    s->pitch16x = (b[60] >> 3) & 1;
    int sp      = (b[60] >> 4) & 7;
    s->speed    = sp >= 4 ? sp - 8 : sp;               // s8 speed:3
    s->reverse  = (b[60] >> 7) & 1;
    s->note     = b[61] & 15;
    s->stereo_left  = (b[61] >> 4) & 1;
    s->stereo_right = (b[61] >> 5) & 1;
    for (int i = 0; i < 4; i++) {
        s->loops[i].start = b[62 + i] & 15;
        s->loops[i].size  = b[62 + i] >> 4;
    }
}

static bool t80_sample_present (int n)
{
    const uint8_t *b = t80_samples + n * 66;
    for (int i = 0; i < 30; i++) if (((b[i * 2] & 15) != 15)) return true;  // any audible tick
    return false;
}

typedef struct { int note, param1, param2, command, sfx, octave; } T80Row;

static void t80_row (int pattern, int row, T80Row *r)
{
    // A track's 6-bit pattern field can name patterns 61-63, which don't
    // exist (TIC-80 has 60): read them as empty rather than past the table.
    if (pattern < 0 || pattern >= 60 || row < 0 || row >= 64) {
        memset (r, 0, sizeof *r);
        return;
    }
    const uint8_t *b = t80_patterns + pattern * 192 + row * 3;
    r->note    = b[0] & 15;
    r->param1  = b[0] >> 4;
    r->param2  = b[1] & 15;
    r->command = (b[1] >> 4) & 7;
    r->sfx     = ((b[1] >> 7) << 5) | (b[2] & 31);
    r->octave  = b[2] >> 5;
}

static int t80_pattern_id (int track, int frame, int channel)
{
    const uint8_t *d = t80_tracks + track * 51 + frame * 3;
    uint32_t v = d[0] | (d[1] << 8) | (d[2] << 16);
    return (v >> (channel * 6)) & 63;
}
static int t80_track_tempo (int t) { return (int8_t) t80_tracks[t * 51 + 48] + 150; }
static int t80_track_rows  (int t)             // stored as 64 - rows; keep 1..64
{
    int rows = 64 - t80_tracks[t * 51 + 49];
    return rows < 1 ? 1 : (rows > 64 ? 64 : rows);
}
static int t80_track_speed (int t) { return (int8_t) t80_tracks[t * 51 + 50] + 6; }

static bool t80_track_present (int t)
{
    for (int f = 0; f < 16; f++)
        for (int c = 0; c < 4; c++)
            if (t80_pattern_id (t, f, c)) return true;
    return false;
}

enum { NoteNone = 0, NoteStop = 1, NoteStart = 4 };
enum { CmdEmpty, CmdVolume, CmdChord, CmdJump, CmdSlide, CmdPitch, CmdVibrato, CmdDelay };

// ---------------------------------------------------------------------------
// Engine state (sound.c)
// ---------------------------------------------------------------------------
typedef struct {
    int tick, pos[4], index, note, duration, speed, vol_l, vol_r;
} T80Channel;

typedef struct {
    struct { int tick, note1, note2; } chord;
    struct { int tick, period, depth; } vibrato;
    struct { int tick, note, duration; } slide;
    int finepitch;
    struct { bool has; T80Row row; int ticks; } delay;
} T80Command;

typedef struct {              // one register: what the synthesizer plays
    int freq, volume, stereo_l, stereo_r;
    uint8_t wave[16];
} T80Register;

typedef struct {
    int track, frame, row, status, loop;     // status: 0 stop, 2 play
    int ticks;
    bool jump_active; int jump_frame, jump_beat;
    T80Channel ch[4];
    T80Command cmd[4];
} T80Music;

static int t80_sfx_pos (int speed, int ticks)
{
    return speed > 0 ? ticks * (1 + speed) : ticks / (1 - speed);
}

static int t80_loop_pos (const T80Loop *l, int pos)
{
    int offset = 0;
    if (l->size > 0) {
        for (int i = 0; i < pos; i++) {
            if (offset < (l->start + l->size - 1)) offset++;
            else offset = l->start;
        }
    } else {
        offset = pos >= 30 ? 29 : pos;
    }
    return offset;
}

static void t80_reset_pos (T80Channel *c)
{
    for (int i = 0; i < 4; i++) c->pos[i] = -1;
    c->tick = -1;
}

// sfx(): advance one channel by one tick and fill its register.
static void t80_sfx_tick (int index, int note, int pitch, T80Channel *c, T80Register *reg)
{
    if (c->duration > 0) c->duration--;
    if (index < 0 || c->duration == 0) { t80_reset_pos (c); return; }

    T80Sample s;
    t80_sample (index, &s);
    int pos = t80_sfx_pos (c->speed, ++c->tick);
    for (int i = 0; i < 4; i++) c->pos[i] = t80_loop_pos (&s.loops[i], pos);

    int volume = 15 - s.volume[c->pos[1]];
    if (volume > 0) {
        int arp = s.chord[c->pos[2]] * (s.reverse ? -1 : 1);
        if (arp) note += arp;
        if (note < 0) note = 0;
        if (note > T80_NOTE_COUNT - 1) note = T80_NOTE_COUNT - 1;
        reg->freq   = (NoteFreqs[note] + s.pitch[c->pos[3]] * (s.pitch16x ? 16 : 1) + pitch) & 0xFFFF;
        reg->volume = volume;
        memcpy (reg->wave, t80_waves + s.wave[c->pos[0]] * 16, 16);
        reg->stereo_l = c->vol_l * !s.stereo_left;
        reg->stereo_r = c->vol_r * !s.stereo_right;
    }
}

static void t80_set_channel (T80Channel *c, int index, int note, int octave, int duration,
                             int vol_l, int vol_r, int speed)
{
    c->vol_l = vol_l;
    c->vol_r = vol_r;
    if (index >= 0) {
        T80Sample s;
        t80_sample (index, &s);
        c->speed = (speed >= -4 && speed <= 3) ? speed : s.speed;
    }
    c->note     = note + octave * 12;
    c->duration = duration;
    c->index    = index;
    t80_reset_pos (c);
}

static void t80_set_music_channel (T80Music *m, int c, int index, int note, int octave, int l, int r)
{
    t80_set_channel (&m->ch[c], index, note, octave, -1, l, r, 8);   // SFX_DEF_SPEED: out of range -> sample's
}

static void t80_reset_music_channels (T80Music *m)
{
    for (int c = 0; c < 4; c++) t80_set_music_channel (m, c, -1, 0, 0, 0, 0);
    memset (m->cmd, 0, sizeof m->cmd);
    m->jump_active = false;
}

static int t80_tick2row (int track, int tick)
{
    int speed = t80_track_speed (track);
    return speed ? tick * t80_track_tempo (track) * 6 / speed / 900 : 0;
}
static int t80_row2tick (int track, int row)
{
    int tempo = t80_track_tempo (track);
    return tempo ? row * t80_track_speed (track) * 900 / tempo / 6 : 0;
}

// Returns false when the music stopped. *wrapped is set when the sequencer
// moved to a new frame this tick (for loop detection / frame offsets).
static bool t80_process_music (T80Music *m, T80Register *regs, bool *new_row)
{
    *new_row = false;
    if (m->status == 0) return false;
    int t = m->track;
    int row = t80_tick2row (t, m->ticks);

    if (row != m->row && m->jump_active) {
        m->frame = m->jump_frame;
        row = m->jump_beat * 4;
        m->ticks = t80_row2tick (t, row);
        m->jump_active = false;
    }

    int rows = t80_track_rows (t);
    if (row >= rows) {
        row = 0;
        m->ticks = 0;
        t80_reset_music_channels (m);
        for (int c = 0; c < 4; c++) t80_set_music_channel (m, c, -1, 0, 0, 15, 15);
        m->frame++;
        if (m->frame >= 16) {
            if (m->loop) m->frame = 0; else { m->status = 0; return false; }
        } else {
            int val = 0;
            for (int c = 0; c < 4; c++) val += t80_pattern_id (t, m->frame, c);
            if (!val) {
                if (m->loop) m->frame = 0; else { m->status = 0; return false; }
            }
        }
    }

    if (row != m->row) {
        m->row = row;
        *new_row = true;
        for (int c = 0; c < 4; c++) {
            int pid = t80_pattern_id (t, m->frame, c);
            if (!pid) continue;
            T80Row r, *tr = &r;
            t80_row (pid - 1, m->row, &r);
            T80Channel *ch = &m->ch[c];
            T80Command *cd = &m->cmd[c];

            if (tr->command == CmdDelay) {
                cd->delay.has = true;
                cd->delay.row = r;
                cd->delay.ticks = (r.param1 << 4) | r.param2;
                tr = NULL;
            }
            if (cd->delay.has && cd->delay.ticks == 0) {
                r = cd->delay.row;
                tr = &r;
                cd->delay.has = false;
            }
            if (tr) {
                if (tr->note) {
                    cd->slide.tick = 0;
                    cd->slide.note = ch->note;
                }
                if (tr->note == NoteStop)
                    t80_set_music_channel (m, c, -1, 0, 0, ch->vol_l, ch->vol_r);
                else if (tr->note >= NoteStart)
                    t80_set_music_channel (m, c, tr->sfx, tr->note - NoteStart, tr->octave, ch->vol_l, ch->vol_r);

                switch (tr->command) {
                case CmdVolume:  ch->vol_l = tr->param1; ch->vol_r = tr->param2; break;
                case CmdChord:   cd->chord.tick = 0; cd->chord.note1 = tr->param1; cd->chord.note2 = tr->param2; break;
                case CmdJump:    m->jump_active = true; m->jump_frame = tr->param1; m->jump_beat = tr->param2; break;
                case CmdVibrato: cd->vibrato.tick = 0; cd->vibrato.period = tr->param1; cd->vibrato.depth = tr->param2; break;
                case CmdSlide:   cd->slide.duration = (tr->param1 << 4) | tr->param2; break;
                case CmdPitch:   cd->finepitch = ((tr->param1 << 4) | tr->param2) - 128; break;
                default: break;
                }
            }
        }
    }

    for (int i = 0; i < 4; i++) {
        T80Channel *ch = &m->ch[i];
        T80Command *cd = &m->cmd[i];
        if (ch->index >= 0) {
            int note = ch->note, pitch = 0;
            int chord[3] = { 0, cd->chord.note1, cd->chord.note2 };
            note += chord[cd->chord.tick % (cd->chord.note2 == 0 ? 2 : 3)];
            if (cd->vibrato.period && cd->vibrato.depth) {
                static const int32_t Vib[32] = { 0x0, 0x31f1, 0x61f8, 0x8e3a, 0xb505, 0xd4db, 0xec83, 0xfb15, 0x10000, 0xfb15, 0xec83, 0xd4db, 0xb505, 0x8e3a, 0x61f8, 0x31f1, 0x0, (int32_t)0xffffce0f, (int32_t)0xffff9e08, (int32_t)0xffff71c6, (int32_t)0xffff4afb, (int32_t)0xffff2b25, (int32_t)0xffff137d, (int32_t)0xffff04eb, (int32_t)0xffff0000, (int32_t)0xffff04eb, (int32_t)0xffff137d, (int32_t)0xffff2b25, (int32_t)0xffff4afb, (int32_t)0xffff71c6, (int32_t)0xffff9e08, (int32_t)0xffffce0f };
                int p = cd->vibrato.period << 1;
                pitch += (int)(((int64_t) Vib[(cd->vibrato.tick % p) * 32 / p] * cd->vibrato.depth) >> 16);
            }
            if (cd->slide.tick < cd->slide.duration) {
                int sn = cd->slide.note;
                if (sn < 0) sn = 0;
                if (sn > T80_NOTE_COUNT - 1) sn = T80_NOTE_COUNT - 1;
                int cn = ch->note < 0 ? 0 : (ch->note > T80_NOTE_COUNT - 1 ? T80_NOTE_COUNT - 1 : ch->note);
                pitch += (NoteFreqs[cn] - NoteFreqs[sn]) * cd->slide.tick / cd->slide.duration;
                note = sn;
            }
            pitch += cd->finepitch;
            t80_sfx_tick (ch->index, note, pitch, ch, &regs[i]);
        }
        cd->chord.tick++;
        cd->vibrato.tick++;
        cd->slide.tick++;
        if (cd->delay.ticks) cd->delay.ticks--;
    }
    m->ticks++;
    return true;
}

// ---------------------------------------------------------------------------
// Synthesizer: registers -> samples
// ---------------------------------------------------------------------------
typedef struct {
    int    time, phase;      // clocks into the current tick, waveform step / LFSR
    double amp;              // current output level of this channel (mono)
} T80Synth;

typedef struct {
    float *l, *r;
    long   len, cap;
} T80Buf;

static void t80_buf_grow (T80Buf *b, long need)
{
    if (need <= b->cap) return;
    long cap = b->cap ? b->cap : 65536;
    while (cap < need) cap *= 2;
    b->l = realloc (b->l, (size_t) cap * sizeof (float));
    b->r = realloc (b->r, (size_t) cap * sizeof (float));
    if (b->l == NULL || b->r == NULL) compiler_error (ERR_INTERNAL, -1, "Out of memory rendering TIC-80 sound");
    memset (b->l + b->cap, 0, (size_t)(cap - b->cap) * sizeof (float));
    memset (b->r + b->cap, 0, (size_t)(cap - b->cap) * sizeof (float));
    b->cap = cap;
}

// Adds level a (stereo gains gl, gr) over clocks [g0, g1) of absolute time,
// box-filtered into the output samples.
static void t80_add (T80Buf *b, double g0, double g1, double a, double gl, double gr)
{
    if (a == 0.0 || g1 <= g0) return;
    const double w = (double) T80_CLOCKRATE / T80_RATE;     // clocks per output sample
    double s0 = g0 / w, s1 = g1 / w;
    long i0 = (long) floor (s0), i1 = (long) floor (s1);
    t80_buf_grow (b, i1 + 2);
    if (i1 >= b->len) b->len = i1 + 1;
    if (i0 == i1) {
        double v = a * (s1 - s0);
        b->l[i0] += (float)(v * gl); b->r[i0] += (float)(v * gr);
        return;
    }
    double v = a * (i0 + 1 - s0);
    b->l[i0] += (float)(v * gl); b->r[i0] += (float)(v * gr);
    for (long i = i0 + 1; i < i1; i++) { b->l[i] += (float)(a * gl); b->r[i] += (float)(a * gr); }
    v = a * (s1 - i1);
    b->l[i1] += (float)(v * gl); b->r[i1] += (float)(v * gr);
}

static int t80_freq2period (int freq)
{
    const int rate = T80_CLOCKRATE * 2 / 32;
    if (freq == 0) return 4096;
    int p = rate / freq - 1;
    return p < 10 ? 10 : (p > 4096 ? 4096 : p);
}

static bool t80_is_noise (const uint8_t *w)
{
    uint8_t first = w[0] & 15;
    first |= first << 4;
    for (int i = 0; i < 16; i++) if (w[i] != first) return false;
    return (w[0] % 0xff) == 0;
}

// Synthesizes one tick of one channel starting at absolute clock `base`.
static void t80_synth_tick (T80Buf *b, long long base, const T80Register *reg, T80Synth *st)
{
    double gl = reg->stereo_l / 15.0, gr = reg->stereo_r / 15.0;
    double scale = reg->volume / 15.0 * 0.2 * T80_GAIN;     // getAmp(): / MAX_VOLUME / (channels + 1)
    double prev_t = 0;
    if (t80_is_noise (reg->wave)) {
        if (st->phase == 0) st->phase = 1;
        int period = t80_freq2period (reg->freq);
        int fb = reg->wave[0] ? 0x14 : 0x12000;
        for (; st->time < T80_ENDTIME; st->time += period, st->phase = ((st->phase & 1) * fb) ^ (st->phase >> 1)) {
            t80_add (b, (double)(base + (long long) prev_t), (double)(base + st->time), st->amp, gl, gr);
            prev_t = st->time;
            st->amp = (st->phase & 1) ? scale : 0.0;
        }
    } else {
        int period = t80_freq2period (reg->freq * 2);
        st->phase &= 31;              // coming from the noise LFSR, its state is no step index
        for (; st->time < T80_ENDTIME; st->time += period, st->phase = (st->phase + 1) % 32) {
            t80_add (b, (double)(base + (long long) prev_t), (double)(base + st->time), st->amp, gl, gr);
            prev_t = st->time;
            int w = (reg->wave[st->phase >> 1] >> ((st->phase & 1) * 4)) & 15;
            st->amp = (w / 15.0 - 0.5) * scale;              // centred; blip_buf's high-pass removes DC anyway
        }
    }
    t80_add (b, (double)(base + (long long) prev_t), (double)(base + T80_ENDTIME), st->amp, gl, gr);
    st->time -= T80_ENDTIME;
}

// One tick's worth of samples is T80_RATE / 60 (not always whole).
static long t80_tick_sample (long tick)
{
    return (long) floor ((double) tick * T80_RATE / 60.0 + 1e-9);
}

// ---------------------------------------------------------------------------
// Output (same .vsnd writer shape as pico8_audio.c, stereo)
// ---------------------------------------------------------------------------
static void t80_output_path (char *buf, size_t size, const char *suffix)
{
    const char *asm_name = g_asm_filename ? g_asm_filename : "out.asm";
    const char *dot = strrchr (asm_name, '.');
    int stem = dot ? (int)(dot - asm_name) : (int) strlen (asm_name);
    snprintf (buf, size, "%.*s_%s.vsnd", stem, asm_name, suffix);
}

long tic80_audio_bytes = 0;

// High-pass (blip_buf's bass_shift 9 at 44.1 kHz ~ 13.7 Hz) and write.
static bool t80_write_vsnd (const char *path, T80Buf *b, long len)
{
    FILE *f = fopen (path, "wb");
    if (f == NULL) {
        compiler_warning (ERR_SEMANTIC, -1, "could not write TIC-80 sound '%s'", path);
        return false;
    }
    if (len < 1) len = 1;
    uint32_t n = (uint32_t) len;
    fwrite ("V32-VSND", 1, 8, f);
    fwrite (&n, 4, 1, f);
    const double a = exp (-2.0 * M_PI * 13.7 / T80_RATE);
    double pl = 0, pr = 0, yl = 0, yr = 0;
    for (long i = 0; i < len; i++) {
        double xl = (i < b->len) ? b->l[i] : 0.0, xr = (i < b->len) ? b->r[i] : 0.0;
        yl = a * (yl + xl - pl); pl = xl;
        yr = a * (yr + xr - pr); pr = xr;
        double vl = yl, vr = yr;
        if (vl > 1.0) vl = 1.0;
        if (vl < -1.0) vl = -1.0;
        if (vr > 1.0) vr = 1.0;
        if (vr < -1.0) vr = -1.0;
        int16_t sl = (int16_t) lrint (vl * 32767.0), sr = (int16_t) lrint (vr * 32767.0);
        fwrite (&sl, 2, 1, f);
        fwrite (&sr, 2, 1, f);
    }
    fclose (f);
    tic80_audio_bytes += 12 + 4 * (long) len;
    return true;
}

// Crossfades the last n samples of [start, end) toward the audio just before
// `start`, so jumping from end-1 back to start is continuous.
static void t80_crossfade_loop (T80Buf *b, long start, long end)
{
    long n = (end - start) / 4;
    if (n > 1024) n = 1024;
    if (n > start) n = start;
    if (n < 8) return;
    for (long i = 0; i < n; i++) {
        double w = (double)(i + 1) / n;
        long d = end - n + i, s = start - n + i;
        b->l[d] = (float)(b->l[d] * (1.0 - w) + b->l[s] * w);
        b->r[d] = (float)(b->r[d] * (1.0 - w) + b->r[s] * w);
    }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------
typedef struct {
    int  id;                 // sound id, -1 when not rendered
    bool loops;
    long loop_start, loop_end;
} T80Sound;

typedef struct {
    T80Sound snd;
    int      tempo, speed;
    long     frame_offset[16];
} T80TrackOut;

static T80TrackOut t80_track_out[8];

static void t80_register_sound (const char *suffix, T80Buf *b, long len, T80Sound *snd)
{
    char path[1024], name[64];
    t80_output_path (path, sizeof path, suffix);
    t80_write_vsnd (path, b, len);
    snprintf (name, sizeof name, "__tic80_%s", suffix);
    snd->id = next_sound_id++;
    cart_resource_append (&sounds_head, &sounds_tail, snd->id, name, path);
}

static void t80_render_track (int t)
{
    T80TrackOut *o = &t80_track_out[t];
    o->snd.id = -1;
    o->tempo  = t80_track_tempo (t);
    o->speed  = t80_track_speed (t);
    for (int f = 0; f < 16; f++) o->frame_offset[f] = -1;
    if (!t80_track_present (t) || o->tempo <= 0 || o->speed <= 0) return;

    T80Music m;
    memset (&m, 0, sizeof m);
    for (int c = 0; c < 4; c++) m.ch[c].index = -1;
    m.track = t; m.frame = 0; m.row = -1; m.loop = 1; m.status = 2; m.ticks = 0;
    for (int c = 0; c < 4; c++) t80_set_music_channel (&m, c, -1, 0, 0, 15, 15);

    // first sample of every (frame, row) played, for loop detection
    static long seen[16][64];
    for (int f = 0; f < 16; f++) for (int r = 0; r < 64; r++) seen[f][r] = -1;

    T80Buf b = { 0 };
    T80Synth st[4] = { { 0 } };
    long loop_start = -1, end = 0;
    for (long tick = 0; tick < T80_MAX_TICKS; tick++) {
        T80Register regs[4];
        memset (regs, 0, sizeof regs);
        bool new_row;
        if (!t80_process_music (&m, regs, &new_row)) { end = t80_tick_sample (tick); break; }
        if (new_row) {
            if (seen[m.frame][m.row] >= 0) {
                // back at a frame/row already played (track end, empty frame
                // or J jump): that is the loop point; this tick isn't kept
                loop_start = seen[m.frame][m.row];
                end = t80_tick_sample (tick);
                break;
            }
            seen[m.frame][m.row] = t80_tick_sample (tick);
            if (m.row == 0 && o->frame_offset[m.frame] < 0) o->frame_offset[m.frame] = seen[m.frame][0];
        }
        for (int c = 0; c < 4; c++)
            t80_synth_tick (&b, (long long) tick * T80_ENDTIME, &regs[c], &st[c]);
        end = t80_tick_sample (tick + 1);
    }
    if (end < 1) { free (b.l); free (b.r); return; }
    t80_buf_grow (&b, end + 1);

    if (loop_start >= 0 && loop_start < end - 1) {
        o->snd.loops      = true;
        o->snd.loop_start = loop_start;
        o->snd.loop_end   = end - 1;
        t80_crossfade_loop (&b, loop_start, end);
    }
    char suffix[32];
    snprintf (suffix, sizeof suffix, "track%d", t);
    t80_register_sound (suffix, &b, end, &o->snd);
    free (b.l); free (b.r);
}

// SFX renders: one per (sfx, note) the program can play.
#define T80_MAX_SFX_RENDERS 1024
typedef struct { int sfx, note; T80Sound snd; } T80SfxRender;
static T80SfxRender t80_sfx_renders[T80_MAX_SFX_RENDERS];
static int          t80_sfx_render_count = 0;

static int t80_default_note (int n)
{
    T80Sample s;
    t80_sample (n, &s);
    int note = s.note + s.octave * 12;
    return note > 95 ? 95 : note;
}

static int gcd_i (int a, int b) { while (b) { int t = a % b; a = b; b = t; } return a; }

static void t80_render_sfx (int n, int note)
{
    for (int i = 0; i < t80_sfx_render_count; i++)
        if (t80_sfx_renders[i].sfx == n && t80_sfx_renders[i].note == note) return;
    if (t80_sfx_render_count >= T80_MAX_SFX_RENDERS) return;
    T80SfxRender *r = &t80_sfx_renders[t80_sfx_render_count++];
    r->sfx = n; r->note = note; r->snd.id = -1;

    T80Sample s;
    t80_sample (n, &s);
    // Steady state: every envelope position is periodic once pos >= 30
    // (loop start + size <= 30); the period in positions is the lcm of the
    // looping envelopes' sizes.
    int p = 1;
    for (int i = 0; i < 4; i++) if (s.loops[i].size > 0) p = p / gcd_i (p, s.loops[i].size) * s.loops[i].size;
    int speed = s.speed;
    long t0 = 0;
    while (t80_sfx_pos (speed, (int) t0) < 30) t0++;
    long period = speed > 0 ? p / gcd_i (p, 1 + speed) : (long) p * (1 - speed);
    if (period > 240) period = 240;                     // cap the sustain loop at 4 s
    // a steady tone: loop several ticks so the crossfade is short relative to it
    long loop_ticks = period;
    while (loop_ticks < 16) loop_ticks += period;

    T80Channel ch;
    memset (&ch, 0, sizeof ch);
    t80_set_channel (&ch, n, note % 12, note / 12, -1, 15, 15, 8);
    T80Buf b = { 0 };
    T80Synth st = { 0 };
    long total = t0 + loop_ticks;
    bool sustain_audible = false;
    for (long tick = 0; tick < total; tick++) {
        T80Register reg;
        memset (&reg, 0, sizeof reg);
        t80_sfx_tick (n, ch.note, 0, &ch, &reg);
        if (tick >= t0 && reg.volume > 0) sustain_audible = true;
        t80_synth_tick (&b, (long long) tick * T80_ENDTIME, &reg, &st);
    }
    long end, loop_start = t80_tick_sample (t0);
    if (sustain_audible) {
        end = t80_tick_sample (total);
        t80_buf_grow (&b, end + 1);
        r->snd.loops = true;
        r->snd.loop_start = loop_start;
        r->snd.loop_end = end - 1;
        t80_crossfade_loop (&b, loop_start, end);
    } else {
        // silent sustain: the sound ends; trim trailing silence (+ a 20 ms tail)
        end = loop_start + T80_RATE / 50;
        t80_buf_grow (&b, end + 1);
        while (end > 1 && fabsf (b.l[end - 1]) < 1e-6f && fabsf (b.r[end - 1]) < 1e-6f) end--;
        end += T80_RATE / 100;
        t80_buf_grow (&b, end + 1);
        r->snd.loops = false;
    }
    char suffix[32];
    snprintf (suffix, sizeof suffix, "sfx%02d_n%02d", n, note);
    t80_register_sound (suffix, &b, end, &r->snd);
    free (b.l); free (b.r);
}

// ---------------------------------------------------------------------------
// Which sounds the program needs: scan its sfx()/music() calls
// ---------------------------------------------------------------------------
// A call argument as text: a number, a note name ("C#4"), nil/absent, or
// something computed at run time.
typedef enum { ARG_ABSENT, ARG_NUMBER, ARG_DYNAMIC } T80ArgKind;

static int t80_parse_note_name (const char *s)
{
    // "C-4", "C#4": TIC-80's parse_note()
    static const char *names[] = { "C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-" };
    if (strlen (s) != 3 || s[2] < '0' || s[2] > '8') return -1;
    for (int i = 0; i < 12; i++)
        if (s[0] == names[i][0] && s[1] == names[i][1]) return i + (s[2] - '0') * 12;
    return -1;
}

static T80ArgKind t80_arg (const char *a, size_t n, double *val)
{
    while (n && isspace ((unsigned char) *a)) { a++; n--; }
    while (n && isspace ((unsigned char) a[n - 1])) n--;
    if (n == 0) return ARG_ABSENT;
    char buf[64];
    if (n >= sizeof buf) return ARG_DYNAMIC;
    memcpy (buf, a, n); buf[n] = 0;
    if (strcmp (buf, "nil") == 0) return ARG_ABSENT;
    if ((buf[0] == '"' || buf[0] == '\'') && buf[n - 1] == buf[0] && n >= 2) {
        buf[n - 1] = 0;
        int note = t80_parse_note_name (buf + 1);
        if (note < 0) return ARG_DYNAMIC;
        *val = note;
        return ARG_NUMBER;
    }
    char *end;
    double v = strtod (buf, &end);
    if (*end == 0) { *val = v; return ARG_NUMBER; }
    return ARG_DYNAMIC;
}

static bool t80_ident_char (char c) { return isalnum ((unsigned char) c) || c == '_' || c == '.' || c == ':'; }

// Finds calls NAME( ... ) outside comments and strings; for each, splits
// the top-level arguments and calls fn.
static void t80_scan_calls (const char *src, const char *name,
                            void (*fn)(T80ArgKind *k, double *v, int nargs))
{
    size_t nl = strlen (name);
    const char *p = src;
    while (*p) {
        if (p[0] == '-' && p[1] == '-') {                    // comment
            if (p[2] == '[' && p[3] == '[') { const char *e = strstr (p, "]]"); p = e ? e + 2 : p + strlen (p); }
            else { while (*p && *p != '\n') p++; }
            continue;
        }
        if (*p == '"' || *p == '\'') {                       // string
            char q = *p++;
            while (*p && *p != q && *p != '\n') { if (*p == '\\' && p[1]) p++; p++; }
            if (*p) p++;
            continue;
        }
        if (strncmp (p, name, nl) == 0 && (p == src || !t80_ident_char (p[-1]))) {
            const char *q = p + nl;
            while (*q == ' ' || *q == '\t') q++;
            if (*q == '(') {
                T80ArgKind k[8]; double v[8]; int na = 0;
                const char *a = ++q; int depth = 0;
                for (; *q; q++) {
                    if (*q == '"' || *q == '\'') { char qq = *q++; while (*q && *q != qq) { if (*q == '\\' && q[1]) q++; q++; } if (!*q) break; continue; }
                    if (*q == '(' || *q == '{' || *q == '[') depth++;
                    else if ((*q == ')' || *q == '}' || *q == ']') && depth > 0) depth--;
                    else if ((*q == ',' && depth == 0) || (*q == ')' && depth == 0)) {
                        if (na < 8) { k[na] = t80_arg (a, (size_t)(q - a), &v[na]); na++; }
                        a = q + 1;
                        if (*q == ')') break;
                    }
                }
                if (na == 1 && k[0] == ARG_ABSENT) na = 0;
                fn (k, v, na);
                p = q;
                if (*p) p++;
                continue;
            }
        }
        p++;
    }
}

static bool t80_sfx_all_ids, t80_sfx_all_octaves_for_all;
static bool t80_sfx_used[64], t80_sfx_octaves[64];
static bool t80_sfx_note_used[64][96];
static bool t80_note_any[96];           // literal notes at calls with a computed id
static bool t80_track_used[8], t80_track_all;

static void t80_on_sfx (T80ArgKind *k, double *v, int n)
{
    if (n < 1) return;
    bool id_static = k[0] == ARG_NUMBER;
    int  id = id_static ? (int) floor (v[0]) : -1;
    if (id_static && (id < 0 || id > 63)) return;           // sfx(-1): stop
    T80ArgKind nk = n >= 2 ? k[1] : ARG_ABSENT;
    int note = (nk == ARG_NUMBER) ? (int) floor (v[1]) : -1;
    if (nk == ARG_NUMBER && note < 0) nk = ARG_ABSENT;       // -1: the SFX's own note
    if (note > 95) note = 95;
    if (!id_static) {
        t80_sfx_all_ids = true;
        if (nk == ARG_DYNAMIC) t80_sfx_all_octaves_for_all = true;
        else if (nk == ARG_NUMBER) t80_note_any[note] = true;
        return;
    }
    t80_sfx_used[id] = true;
    if (nk == ARG_DYNAMIC) t80_sfx_octaves[id] = true;
    else if (nk == ARG_NUMBER) t80_sfx_note_used[id][note] = true;
}

static void t80_on_music (T80ArgKind *k, double *v, int n)
{
    if (n < 1) return;                                       // music(): stop
    if (k[0] == ARG_NUMBER) {
        int t = (int) floor (v[0]);
        if (t >= 0 && t < 8) t80_track_used[t] = true;
    } else if (k[0] == ARG_DYNAMIC) {
        t80_track_all = true;
    }
}

bool tic80_audio_rendered = false;

// Called from main() once the cart's sections are parsed. source = the
// program text (to find its sfx()/music() calls).
void register_tic80_audio (const char *source)
{
    if (!t80_have_sfx && !t80_have_music) return;
    if (source == NULL) return;
    t80_default_waves_if_empty ();
    t80_scan_calls (source, "sfx", t80_on_sfx);
    t80_scan_calls (source, "music", t80_on_music);

    for (int t = 0; t < 8; t++) {
        t80_track_out[t].snd.id = -1;
        if (t80_have_music && (t80_track_all || t80_track_used[t])) t80_render_track (t);
    }
    if (t80_have_sfx) {
        for (int n = 0; n < 64; n++) {
            if (!(t80_sfx_all_ids || t80_sfx_used[n]) || !t80_sample_present (n)) continue;
            t80_render_sfx (n, t80_default_note (n));
            for (int note = 0; note < 96; note++)
                if (t80_sfx_note_used[n][note] || t80_note_any[note]) t80_render_sfx (n, note);
            if (t80_sfx_octaves[n] || t80_sfx_all_octaves_for_all)
                for (int o = 0; o < 8; o++) t80_render_sfx (n, o * 12 + 6);
        }
    }
    tic80_audio_rendered = true;
}

// ---------------------------------------------------------------------------
// ROM tables for tic80.s
// ---------------------------------------------------------------------------
//   __tic80_snd_loops: count, then (sound id, loops, loop start, loop end)
//   __tic80_tracks:    8 x (sound id or -1, loops, tempo, speed, 16 frame offsets or -1)
//   __tic80_sfx_map:   64 x 97 x (sound id or -1, SPU speed): note 0-95, then the
//                      SFX's own note (sfx(id) / note -1)
void emit_tic80_audio_tables (FILE *out)
{
    const double base_speed = T80_RATE / 44100.0;
    int count = 0;
    for (int t = 0; t < 8; t++) if (tic80_audio_rendered && t80_track_out[t].snd.id >= 0) count++;
    count += tic80_audio_rendered ? t80_sfx_render_count : 0;
    fprintf (out, "\n;; --- TIC-80 synthesized sound (tic80_audio.c) ---\n");
    fprintf (out, "__tic80_snd_loops:\n    integer %d\n", count);
    if (tic80_audio_rendered) {
        for (int t = 0; t < 8; t++) {
            const T80Sound *s = &t80_track_out[t].snd;
            if (s->id >= 0) fprintf (out, "    integer %d, %d, %ld, %ld\n", s->id, s->loops, s->loop_start, s->loop_end);
        }
        for (int i = 0; i < t80_sfx_render_count; i++) {
            const T80Sound *s = &t80_sfx_renders[i].snd;
            fprintf (out, "    integer %d, %d, %ld, %ld\n", s->id, s->loops, s->loop_start, s->loop_end);
        }
    }
    fprintf (out, "__tic80_tracks:\n");
    for (int t = 0; t < 8; t++) {
        const T80TrackOut *o = &t80_track_out[t];
        bool have = tic80_audio_rendered && o->snd.id >= 0;
        fprintf (out, "    integer %d, %d, %d, %d", have ? o->snd.id : -1, have && o->snd.loops,
                 have ? o->tempo : 150, have ? o->speed : 6);
        for (int f = 0; f < 16; f++) fprintf (out, ", %ld", have ? o->frame_offset[f] : -1L);
        fprintf (out, "\n");
    }
    fprintf (out, "__tic80_sfx_map:\n");
    for (int n = 0; n < 64; n++) {
        bool any = false;
        for (int i = 0; tic80_audio_rendered && i < t80_sfx_render_count; i++) if (t80_sfx_renders[i].sfx == n) any = true;
        if (!any) {
            fprintf (out, "    integer");
            for (int k = 0; k < 97; k++) fprintf (out, "%s -1, 0", k ? "," : "");
            fprintf (out, "\n");
            continue;
        }
        fprintf (out, "    ;; sfx %d\n", n);
        for (int k = 0; k < 97; k++) {
            int note = (k == 96) ? t80_default_note (n) : k;
            // best render: same note, else the nearest reference/other note
            const T80SfxRender *best = NULL;
            int bd = 1 << 30;
            for (int i = 0; i < t80_sfx_render_count; i++) {
                const T80SfxRender *r = &t80_sfx_renders[i];
                if (r->sfx != n) continue;
                int d = abs (r->note - note);
                if (d < bd) { bd = d; best = r; }
            }
            double speed = base_speed;
            if (best && best->note != note)
                speed *= (double) NoteFreqs[note] / NoteFreqs[best->note];
            union { float f; uint32_t u; } cv = { .f = (float) speed };
            fprintf (out, "    integer %d, 0x%08X\n", best ? best->snd.id : -1, cv.u);
        }
    }
}

// Sample offset of a row inside a frame: row2tick() ticks at T80_RATE / 60.
int tic80_audio_rate (void) { return T80_RATE; }
