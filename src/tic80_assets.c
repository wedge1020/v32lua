#include "v32lua.h"
#include <stdlib.h>
#include <string.h>

// TIC80 tilesheet is 128x256 pixels (16x32 tiles of 8x8 each)
#define TIC80_SHEET_WIDTH  128   // CHANGED from 256
#define TIC80_SHEET_HEIGHT 256

// =============================================================================
// Global State (defined here, declared in tic80_assets.h)
// =============================================================================

char *current_tic80_section = NULL;
TIC80AssetData *current_tic80_assets = NULL;
uint32_t tic80_palette[16] = {0};
bool tic80_use_custom_palette = false;
bool tic80_has_any_assets = false;

// Storage for tile pixel data (256x256, each pixel is palette index 0-15)
static uint8_t tic80_tile_pixels[TIC80_SHEET_WIDTH * TIC80_SHEET_HEIGHT] = {0};

// =============================================================================
// Tile Parsing
// =============================================================================
static void parse_tic80_tile(int tile_index, const char *hex_data) {
    // TIC80 sheet is 16 tiles wide, 32 rows
    int x = (tile_index % 16) * 8;   // FIXED: 16 columns
    int y = (tile_index / 16) * 8;   // FIXED: 16 columns

    for (int i = 0; i < 64 && hex_data[i] != '\0'; i++) {
        char c = hex_data[i];
        int color_idx;

        // Convert hex character to 4-bit color index (0-15)
        if (c >= '0' && c <= '9') color_idx = c - '0';
        else if (c >= 'a' && c <= 'f') color_idx = 10 + (c - 'a');
        else if (c >= 'A' && c <= 'F') color_idx = 10 + (c - 'A');
        else continue;

        int px = x + (i % 8);
        int py = y + (i / 8);

        if (px < TIC80_SHEET_WIDTH && py < TIC80_SHEET_HEIGHT) {
            tic80_tile_pixels[py * TIC80_SHEET_WIDTH + px] = (uint8_t)color_idx;
        }
    }
}

// =============================================================================
// Color Conversion
// =============================================================================

// Convert RRGGBB hex string to Vircon32 AABBGGRR format
static uint32_t hex_to_v32_color(const char *hex_rgb) {
    uint32_t r = (strtoul(hex_rgb, NULL, 16) >> 16) & 0xFF;
    uint32_t g = (strtoul(hex_rgb, NULL, 16) >> 8) & 0xFF;
    uint32_t b = strtoul(hex_rgb, NULL, 16) & 0xFF;
    return 0xFF000000 | (b << 16) | (g << 8) | r;
}

// Get pixel color index from tile sheet
uint8_t get_tic80_tile_pixel(int x, int y) {
    if (x >= 0 && x < TIC80_SHEET_WIDTH && y >= 0 && y < TIC80_SHEET_HEIGHT) {
        return tic80_tile_pixels[y * TIC80_SHEET_WIDTH + x];
    }
    return 0;  // Default to black (palette index 0)
}

// =============================================================================
// Asset Line Parsing
// =============================================================================

// Parse a single TIC80 asset line (e.g., "001:eccccccccc888888...")
// Make parse_tic80_asset_line more defensive
TIC80AssetData *parse_tic80_asset_line(const char *line) {
    if (line == NULL || *line == '\0') {
        return NULL;
    }

    TIC80AssetData *data = malloc(sizeof(TIC80AssetData));
    if (!data) return NULL;

    char *colon = strchr(line, ':');
    if (!colon) {
        free(data);
        return NULL;
    }

    *colon = '\0';
    data->index = atoi(line);
    data->hex_data = strdup(colon + 1);
    if (data->hex_data == NULL) {
        free(data);
        return NULL;
    }
    data->next = NULL;

    return data;
}

void process_all_tic80_sections(void) {
    if (current_tic80_section == NULL) {
        return;
    }

    // Process ONCE here
    process_tic80_section(current_tic80_section, current_tic80_assets);

    // Clean up
    free(current_tic80_section);
    current_tic80_section = NULL;

    TIC80AssetData *item = current_tic80_assets;
    current_tic80_assets = NULL;

    while (item != NULL) {
        TIC80AssetData *next = item->next;
        if (item->hex_data != NULL) {
            free(item->hex_data);
        }
        free(item);
        item = next;
    }
}

// =============================================================================
// Section Processing
// =============================================================================

// Process a single TIC80 section
void process_tic80_section(const char *section, TIC80AssetData *assets) {
    if (strcmp(section, "PALETTE") == 0) {
        if (assets != NULL) {
            TIC80AssetData *data = assets;
            // Parse the 96-char hex string (16 colors × 6 chars each: RRGGBB)
            if (strlen(data->hex_data) >= 96) {
                for (int i = 0; i < 16; i++) {
                    char color_hex[7] = {0};
                    strncpy(color_hex, data->hex_data + (i * 6), 6);
                    tic80_palette[i] = hex_to_v32_color(color_hex);
                }
                tic80_use_custom_palette = true;
            }
        }
    }
    else if (strcmp(section, "TILES") == 0) {
        // Process all tile data
        for (TIC80AssetData *item = assets; item != NULL; item = item->next) {
            parse_tic80_tile(item->index, item->hex_data);
        }
        tic80_has_any_assets = true;
    }
    // Add other sections (WAVES, SFX, TRACKS) here if needed
}

// =============================================================================
// Accessor Functions
// =============================================================================

bool tic80_has_assets(void) {
    return tic80_has_any_assets;
}

bool tic80_has_custom_palette(void) {
    return tic80_use_custom_palette;
}

uint32_t tic80_get_palette_color(int index) {
    if (index >= 0 && index < 16) {
        return tic80_palette[index];
    }
    return 0xFF000000;  // Black
}

// Get the entire palette (for VTEX generation)
uint32_t *get_tic80_palette(void) {
    return tic80_palette;
}

// Initialize with default TIC-80 palette
void tic80_init_default_palette(void) {
    static const uint32_t default_palette[16] = {
        0xFF2C1C1A, 0xFF5D275D, 0xFF533EB1, 0xFF577DEF,
        0xFF75CDFF, 0xFF70F0A7, 0xFF64B738, 0xFF797125,
        0xFF6F3629, 0xFFC95D3B, 0xFFF6A641, 0xFFF7EF73,
        0xFFF4F4F4, 0xFFC2B094, 0xFF866C56, 0xFF573C33
    };
    for (int i = 0; i < 16; i++) {
        tic80_palette[i] = default_palette[i];
    }
}
