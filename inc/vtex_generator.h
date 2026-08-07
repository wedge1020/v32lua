#ifndef __VTEX_GENERATOR_H
#define __VTEX_GENERATOR_H

// =============================================================================
// VTEX File Header Structure - MINIMAL
// =============================================================================

#define TEX_WIDTH  128
#define TEX_HEIGHT 256

typedef struct {
    char magic[8];    // "V32-VTEX" - NO version, NO texture_count
    uint32_t width;   // 128
    uint32_t height;  // 256
} VTEXHeader;

void  generate_vtex_from_tic80_with_colorkey (const char *, int);
void  generate_all_tic80_colorkey_textures   (const char *);
void  generate_vtex_from_tic80               (const char *);
void  generate_vtex_path                     (const char *, char *, size_t);

#endif
