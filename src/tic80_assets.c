// =============================================================================
// tic80_assets.c - TIC-80 Asset Processing with Debug Output
// =============================================================================
// Handles parsing of TIC-80 cartridge assets (tiles, palette) from Lua comments
// and converts them into Vircon32-compatible pixel data.

#include "v32lua.h"
#include <stdlib.h>
#include <string.h>

 // =============================================================================
// Configuration Constants
// =============================================================================

// TIC-80 tilesheet is 128x256 pixels (16 columns x 32 rows of 8x8 tiles)
#define TIC80_SHEET_WIDTH  128
#define TIC80_SHEET_HEIGHT 256

// =============================================================================
// Global State
// =============================================================================

char *current_tic80_section = NULL;      // Current section being parsed (TILES, PALETTE, etc.)
TIC80AssetData *current_tic80_assets = NULL; // Linked list of asset data for current section
uint32_t tic80_palette[16] = {0};         // 16-color palette in AABBGGRR format
bool tic80_use_custom_palette = false;    // Flag: using custom palette from cartridge
bool tic80_has_any_assets = false;        // Flag: any TIC-80 assets were found

// Storage for tile pixel data (128x256 pixels, each is a palette index 0-15)
static uint8_t tic80_tile_pixels[TIC80_SHEET_WIDTH * TIC80_SHEET_HEIGHT] = {0};

// =============================================================================
// Helper Functions
// =============================================================================

/// Count assets in the linked list (for debugging)
static int count_tic80_assets(TIC80AssetData *head) {
    int count = 0;
    while (head != NULL) {
        count++;
        head = head->next;
    }
    return count;
}

// =============================================================================
// Color Conversion
// =============================================================================

/// Convert RRGGBB hex string to Vircon32 AABBGGRR format
/// @param hex_rgb 6-character RRGGBB string (e.g., "FF0000" = red)
/// @return 32-bit color in AABBGGRR format with alpha=0xFF
static uint32_t hex_to_v32_color(const char *hex_rgb) {
    uint32_t r = (strtoul(hex_rgb, NULL, 16) >> 16) & 0xFF;
    uint32_t g = (strtoul(hex_rgb, NULL, 16) >> 8) & 0xFF;
    uint32_t b = strtoul(hex_rgb, NULL, 16) & 0xFF;
    return 0xFF000000 | (b << 16) | (g << 8) | r;
}

// =============================================================================
// Tile Parsing
// =============================================================================

/// Parse a single TIC-80 tile (8x8 pixels, 64 hex characters)
/// Each hex char represents one pixel's 4-bit color index (0-15)
/// @param tile_index Tile number (0-511 for 16x32 sheet)
/// @param hex_data 64-character hex string
static void parse_tic80_tile(int tile_index, const char *hex_data) {
    fprintf(stderr, "DEBUG TILE: Processing tile_index=%d, hex_data[0..7]='%.8s'\n",
            tile_index, hex_data);

    // Calculate position in the 128x256 tilesheet
    // TIC-80: 16 columns, 32 rows, each tile is 8x8 pixels
    int x = (tile_index % 16) * 8;  // Column: 0-15, times 8 pixels
    int y = (tile_index / 16) * 8;  // Row: 0-31, times 8 pixels
    fprintf(stderr, "DEBUG TILE: Position x=%d, y=%d\n", x, y);

    // Parse 64 hex characters (one per pixel in 8x8 tile)
    for (int i = 0; i < 64 && hex_data[i] != '\0'; i++) {
        char c = hex_data[i];
        int color_idx;

        // Convert hex character to 4-bit color index (0-15)
        if (c >= '0' && c <= '9') color_idx = c - '0';
        else if (c >= 'a' && c <= 'f') color_idx = 10 + (c - 'a');
        else if (c >= 'A' && c <= 'F') color_idx = 10 + (c - 'A');
        else {
            fprintf(stderr, "DEBUG TILE: Invalid hex char '%c' at position %d\n", c, i);
            continue;
        }

        // Calculate pixel position within tile (row-major)
        int px = x + (i % 8);   // X within tile: 0-7
        int py = y + (i / 8);   // Y within tile: 0-7

        // Write to global pixel buffer if in bounds
        if (px < TIC80_SHEET_WIDTH && py < TIC80_SHEET_HEIGHT) {
            tic80_tile_pixels[py * TIC80_SHEET_WIDTH + px] = (uint8_t)color_idx;
        }
    }
    fprintf(stderr, "DEBUG TILE: Finished parsing tile %d\n", tile_index);
}

// =============================================================================
// Pixel Access
// =============================================================================

/// Get pixel color index from the tilesheet
/// @param x X coordinate (0-127)
/// @param y Y coordinate (0-255)
/// @return Palette index (0-15), or 0 if out of bounds
uint8_t get_tic80_tile_pixel(int x, int y) {
    if (x >= 0 && x < TIC80_SHEET_WIDTH && y >= 0 && y < TIC80_SHEET_HEIGHT) {
        return tic80_tile_pixels[y * TIC80_SHEET_WIDTH + x];
    }
    return 0;  // Default to black (palette index 0)
}

// =============================================================================
// Asset Line Parsing
// =============================================================================

/// Parse a single TIC-80 asset line (format: "001:ecccccc...")
/// @param line String in format "<index>:<hex_data>"
/// @return Allocated TIC80AssetData, or NULL on error
TIC80AssetData *parse_tic80_asset_line(const char *line) {
    fprintf(stderr, "DEBUG ASSET: parse_tic80_asset_line called with line='%s'\n", line);

    if (line == NULL || *line == '\0') {
        fprintf(stderr, "DEBUG ASSET: Empty line, returning NULL\n");
        return NULL;
    }

    TIC80AssetData *data = malloc(sizeof(TIC80AssetData));
    if (!data) {
        fprintf(stderr, "DEBUG ASSET: malloc failed\n");
        return NULL;
    }

    // Find the colon separator between index and hex data
    char *colon = strchr(line, ':');
    if (!colon) {
        fprintf(stderr, "DEBUG ASSET: No colon found in line '%s'\n", line);
        free(data);
        return NULL;
    }

    // Split at colon: index before, hex_data after
    *colon = '\0';
    data->index = atoi(line);
    data->hex_data = strdup(colon + 1);
    if (data->hex_data == NULL) {
        fprintf(stderr, "DEBUG ASSET: strdup failed for hex_data\n");
        free(data);
        return NULL;
    }
    data->next = NULL;

    fprintf(stderr, "DEBUG ASSET: Parsed asset: index=%d, hex_data_len=%zu\n",
            data->index, strlen(data->hex_data));
    return data;
}

// =============================================================================
// Section Processing
// =============================================================================

/// Process all accumulated TIC-80 sections (called after parsing)
void process_all_tic80_sections(void) {
    fprintf(stderr, "DEBUG PROCESS: process_all_tic80_sections called\n");
    fprintf(stderr, "DEBUG PROCESS: current_tic80_section=%p ('%s'), current_tic80_assets=%p\n",
            (void*)current_tic80_section,
            current_tic80_section ? current_tic80_section : "NULL",
            (void*)current_tic80_assets);

    if (current_tic80_section == NULL) {
        fprintf(stderr, "DEBUG PROCESS: No section to process, returning\n");
        return;
    }

    // Process the current section with its assets
    fprintf(stderr, "DEBUG PROCESS: Calling process_tic80_section\n");
    process_tic80_section(current_tic80_section, current_tic80_assets);

    // Clean up: free section string and asset list
    fprintf(stderr, "DEBUG PROCESS: Freeing section and assets\n");
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

/// Process a single TIC-80 section (PALETTE, TILES, etc.)
/// @param section Section name ("PALETTE", "TILES", etc.)
/// @param assets Linked list of asset data for this section
void process_tic80_section(const char *section, TIC80AssetData *assets) {
    fprintf(stderr, "DEBUG PROCESS: process_tic80_section called with section='%s', assets=%p\n",
            section, (void*)assets);

    if (strcmp(section, "PALETTE") == 0) {
        fprintf(stderr, "DEBUG PROCESS: Processing PALETTE section\n");
        if (assets != NULL) {
            TIC80AssetData *data = assets;
            // Parse the 96-char hex string (16 colors x 6 chars each: RRGGBB)
            if (strlen(data->hex_data) >= 96) {
                fprintf(stderr, "DEBUG PROCESS: PALETTE has valid 96-char hex string\n");
                for (int i = 0; i < 16; i++) {
                    char color_hex[7] = {0};
                    strncpy(color_hex, data->hex_data + (i * 6), 6);
                    tic80_palette[i] = hex_to_v32_color(color_hex);
                    fprintf(stderr, "DEBUG PROCESS: Palette[%d] = 0x%08X (from '%s')\n",
                            i, tic80_palette[i], color_hex);
                }
                tic80_use_custom_palette = true;
            } else {
                fprintf(stderr, "DEBUG PROCESS: PALETTE hex string too short: %zu chars\n",
                        strlen(data->hex_data));
            }
        } else {
            fprintf(stderr, "DEBUG PROCESS: PALETTE section has no assets\n");
        }
    }
    else if (strcmp(section, "TILES") == 0) {
        fprintf(stderr, "DEBUG PROCESS: Processing TILES section with %d assets\n",
                count_tic80_assets(assets));
        if (assets == NULL) {
            fprintf(stderr, "DEBUG PROCESS: WARNING: TILES section has NULL assets list!\n");
        } else {
            // Process all tile data
            for (TIC80AssetData *item = assets; item != NULL; item = item->next) {
                fprintf(stderr, "DEBUG PROCESS: Calling parse_tic80_tile for tile %d\n", item->index);
                parse_tic80_tile(item->index, item->hex_data);
            }
        }
        tic80_has_any_assets = true;
        fprintf(stderr, "DEBUG PROCESS: TILES processing complete, tic80_has_any_assets=true\n");
    }
    else {
        fprintf(stderr, "DEBUG PROCESS: Unknown section '%s'\n", section);
    }
    // Add other sections (WAVES, SFX, TRACKS) here if needed
}

// =============================================================================
// Accessor Functions
// =============================================================================

/// Check if any TIC-80 assets were found
bool tic80_has_assets(void) {
    fprintf(stderr, "DEBUG ACCESSOR: tic80_has_assets() returning %d\n", tic80_has_any_assets);
    return tic80_has_any_assets;
}

/// Check if a custom palette was loaded
bool tic80_has_custom_palette(void) {
    return tic80_use_custom_palette;
}

/// Get a specific palette color
/// @param index Color index (0-15)
/// @return 32-bit color in AABBGGRR format
uint32_t tic80_get_palette_color(int index) {
    if (index >= 0 && index < 16) {
        return tic80_palette[index];
    }
    return 0xFF000000;  // Black
}

/// Get the entire palette array (for VTEX generation)
uint32_t *get_tic80_palette(void) {
    return tic80_palette;
}

/// Initialize with default TIC-80 palette
void tic80_init_default_palette(void) {
    // Default TIC-80 16-color palette (32-bit AABBGGRR for Vircon32 GPU)
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
