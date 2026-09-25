#ifndef __PICO8_H
#define __PICO8_H

#define PICO8_SWATCH_REGION_BASE 256
#define PICO8_SWATCH_TEX_HEIGHT  132

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
bool         pico8_load_cart_assets (const char *, const char *);
uint8_t      pico8_gfx_pixel        (int, int);
bool         pico8_has_gfx          (void);
void         emit_pico8_cart_data   (FILE *);

#endif
