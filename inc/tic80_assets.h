#ifndef __TIC80_ASSETS_H
#define __TIC80_ASSETS_H

// =============================================================================
// Configuration Constants
// =============================================================================

#define TIC80_SHEET_WIDTH      128
#define TIC80_SHEET_HEIGHT     256
#define TIC80_MAP_MAX_WIDTH    240
#define TIC80_MAP_MAX_HEIGHT   136

// =============================================================================
// TIC-80 Asset Data Structures
// =============================================================================

typedef struct TIC80AssetData TIC80AssetData;
struct TIC80AssetData {
    int index;
    char *hex_data;
    TIC80AssetData *next;
};

// In the TIC80 assets section
extern bool  tic80_has_map;
extern uint8_t tic80_sprite_flags[512];
extern bool  tic80_has_waves;
extern bool  tic80_has_sfx;
extern bool  tic80_has_tracks;
extern int   tic80_map_width;
extern int   tic80_map_height;
extern uint8_t tic80_tile_pixels[TIC80_SHEET_WIDTH * TIC80_SHEET_HEIGHT];
extern uint8_t tic80_map_data[TIC80_MAP_MAX_WIDTH * TIC80_MAP_MAX_HEIGHT];

void      tic80_init_default_palette (void);
void      process_all_tic80_sections (void);
uint32_t *get_tic80_palette          (void);
uint8_t   get_tic80_tile_pixel       (int, int);
int       count_tic80_assets         (TIC80AssetData *);

bool      tic80_has_map_data         (void);
int       tic80_get_map_width        (void);
int       tic80_get_map_height       (void);
uint8_t   tic80_get_map_tile         (int, int);
void      parse_tic80_map_row        (int, const char *);

// ============================================================================
// Sound Function Declarations
// ============================================================================
void parse_tic80_wave(int wave_index, const char *hex_data);
void parse_tic80_sfx(int sfx_index, const char *hex_data);
void parse_tic80_track(int track_index, const char *hex_data);

// tic80_cart.c -- binary .tic cartridges
bool        tic80_is_binary_cart_path (const char *path);
char       *tic80_cart_to_text (const char *path);     // malloc'd .lua-project text
const char *tic80_metatag (const char *code, const char *tag);

#endif
