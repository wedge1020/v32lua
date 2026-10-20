#ifndef __PICO8_H
#define __PICO8_H

#define PICO8_SWATCH_REGION_BASE 256
#define PICO8_SWATCH_TEX_HEIGHT  132

// Side panels (pico8_bezel.c): 2 x 48x120 at texture 0 row PICO8_BEZEL_Y,
// regions PICO8_BEZEL_REGION (left) and + 1 (right), drawn at 3x.
#define PICO8_BEZEL_Y            132
#define PICO8_BEZEL_W            96
#define PICO8_BEZEL_H            120
#define PICO8_BEZEL_REGION       272
// P8SCII glyphs 128-153 (pico8_bezel.c): 7x5 each, 16 per 6-pixel row at
// texture 0 row PICO8_GLYPH_Y, regions PICO8_GLYPH_REGION + (code - 128)
#define PICO8_GLYPH_Y            (PICO8_BEZEL_Y + PICO8_BEZEL_H)
#define PICO8_GLYPH_COUNT        26
#define PICO8_GLYPH_REGION       274
#define PICO8_TEX_HEIGHT         (PICO8_GLYPH_Y + 12)
int          pico8_glyph_pixel      (int, int);
void         pico8_fold_glyphs      (char *);
extern bool  pico8_bezel_enabled;
extern bool  g_cli_bezel_set;
void         pico8_bezel_build      (const char *);
int          pico8_bezel_index      (int, int);

// Custom side-panel art (--bezel FILE / --#bezel "FILE", pico8_bezel.c)
extern char *pico8_bezel_file;
extern int   pico8_bezel_texture_id;
extern int   pico8_bezel_panel_w, pico8_bezel_panel_h;
extern bool  pico8_bezel_has_alpha;
bool         pico8_bezel_register_custom (const char *base_path);
uint8_t     *png_load_rgba          (const char *, int *, int *, const char **);

// PICO-8 sound: sfx()/music(), via a small bank of generic placeholder
// tones layered on the native music.play/sfx.play/sfx.stop machinery --
// see the block above emit_pico8_sfx_intrinsic() in pico8.c.
#define PICO8_TONE_COUNT 8

extern int   pico8_tone_base_id;
extern int   pico8_frame_step;
extern bool  pico8_tones_registered;
void         register_pico8_tone_bank (void);
void         generate_vtex_from_pico8 (const char *, uint8_t (*) (int, int), int);

// PICO-8 map geometry (cells). Rows 32..63 share memory with the lower half
// of the sprite sheet on real PICO-8; pico8_assets.c reproduces that.
#define PICO8_MAP_WIDTH   128
#define PICO8_MAP_HEIGHT  64

// .p8 cartridge support -- see pico8_assets.c
bool         pico8_is_cart_text     (const char *);
char        *pico8_split_cart       (const char *);
char        *pico8_expand_shorthand (const char *);   // pico8_shorthand.c
bool         pico8_load_cart_assets (const char *, const char *);
uint8_t      pico8_gfx_pixel        (int, int);
bool         pico8_has_gfx          (void);
void         emit_pico8_cart_data   (FILE *);
const char  *pico8_sfx_line         (int);
const char  *pico8_music_line       (int);
bool         pico8_has_audio        (void);

// Real __sfx__/__music__ playback -- see pico8_audio.c
extern int   pico8_sfx_base_id;
bool         register_pico8_sfx_sounds (void);
void         emit_pico8_audio_tables   (FILE *);
extern long  pico8_audio_bytes;
extern int   synth_audio_rate;

char        *pico8_append_prelude   (char *);
bool         pico8_prelude_builtin  (const char *);

#endif
