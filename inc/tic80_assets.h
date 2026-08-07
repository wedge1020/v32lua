#ifndef __TIC80_ASSETS_H
#define __TIC80_ASSETS_H

// =============================================================================
// TIC-80 Asset Data Structures
// =============================================================================

typedef struct TIC80AssetData TIC80AssetData;
struct TIC80AssetData {
    int index;
    char *hex_data;
    TIC80AssetData *next;
};

void      tic80_init_default_palette (void);
void      process_all_tic80_sections (void);
uint32_t *get_tic80_palette (void);
uint8_t   get_tic80_tile_pixel (int, int);
int       count_tic80_assets (TIC80AssetData *);

#endif
