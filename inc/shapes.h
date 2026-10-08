#ifndef _SHAPES_H
#define _SHAPES_H

// Circle shape atlas (src/shapes.c): filled circles and outlines of radius
// 0..SHAPES_MAX_R, pre-rendered for the TIC-80 / PICO-8 layers.
#define SHAPES_MAX_R    31
#define SHAPES_REGIONS  (2 * (SHAPES_MAX_R + 1))

extern int   shapes_texture_id;
extern bool  shapes_fast;

bool  shapes_wanted       (const char *, bool);
bool  shapes_build        (const char *, bool);
void  emit_shapes_runtime (FILE *);
void  register_shapes_texture (const char *, const char *, bool);

// Native rect()/rectfill() fill texture (src/shapes.c): 4x4 opaque white,
// region 0 = the pixel at (1, 1). -1 when the program draws no rectangles.
#define FILL_TEXTURE_SIZE 4
extern int   fill_texture_id;
bool  fill_texture_wanted     (const char *);
void  register_fill_texture   (const char *, const char *);
void  emit_fill_texture_setup (void);

#endif
