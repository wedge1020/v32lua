#ifndef _SHAPES_H
#define _SHAPES_H

// Circle shape atlas (src/shapes.c): filled circles and outlines of radius
// 0..SHAPES_MAX_R, pre-rendered for the TIC-80 / PICO-8 layers.
#define SHAPES_MAX_R    31
#define SHAPES_REGIONS  (2 * (SHAPES_MAX_R + 1))

extern int   shapes_texture_id;

bool  shapes_wanted       (const char *, bool);
bool  shapes_build        (const char *, bool);
void  emit_shapes_runtime (FILE *);
void  register_shapes_texture (const char *, const char *, bool);

#endif
