#ifndef __PICO8_H
#define __PICO8_H

#define PICO8_SWATCH_REGION_BASE 256
#define PICO8_SWATCH_TEX_HEIGHT  132

// PICO-8 sound: sfx()/music(), via a small bank of generic placeholder
// tones layered on the native music.play/sfx.play/sfx.stop machinery --
// see the block above emit_pico8_sfx_intrinsic() in pico8.c.
#define PICO8_TONE_COUNT 8

extern int   pico8_tone_base_id;
extern bool  pico8_tones_registered;
void         register_pico8_tone_bank (void);
void         generate_vtex_from_pico8 (const char *, uint8_t (*) (int, int), int);

#endif
