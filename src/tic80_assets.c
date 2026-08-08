// =============================================================================
// tic80_assets.c - TIC-80 Asset Processing with Debug Output
// =============================================================================
// Handles parsing of TIC-80 cartridge assets (tiles, palette) from Lua comments
// and converts them into Vircon32-compatible pixel data.

#include "v32lua.h"
#include <stdlib.h>
#include <string.h>

// =============================================================================
// Global State
// =============================================================================

char *current_tic80_section = NULL;      // Current section being parsed (TILES, PALETTE, etc.)
TIC80AssetData *current_tic80_assets = NULL; // Linked list of asset data for current section
uint32_t tic80_palette[16] = {0};         // 16-color palette in AABBGGRR format
bool tic80_use_custom_palette = false;    // Flag: using custom palette from cartridge
bool tic80_has_any_assets = false;        // Flag: any TIC-80 assets were found

// Storage for tile pixel data (128x256 pixels, each is a palette index 0-15)
uint8_t tic80_tile_pixels[TIC80_SHEET_WIDTH * TIC80_SHEET_HEIGHT] = {0};
uint8_t tic80_map_data[TIC80_MAP_MAX_WIDTH * TIC80_MAP_MAX_HEIGHT] = {0};
int tic80_map_width = 0;
int tic80_map_height = 0;
bool tic80_has_map = false;

// =============================================================================
// Helper Functions
// =============================================================================

/// Count TIC80 assets in the linked list (for debugging)
/// @param head Pointer to first asset in the list
/// @return Number of assets
int  count_tic80_assets (TIC80AssetData *head)
{
    int count    = 0;
    while (head != NULL)
	{
        count++;
        head     = head -> next;
    }
    return (count);
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

    // Calculate position in the 128x256 tilesheet
    // TIC-80: 16 columns, 32 rows, each tile is 8x8 pixels
    int x = (tile_index % 16) * 8;  // Column: 0-15, times 8 pixels
    int y = (tile_index / 16) * 8;  // Row: 0-31, times 8 pixels

    // Parse 64 hex characters (one per pixel in 8x8 tile)
    for (int i = 0; i < 64 && hex_data[i] != '\0'; i++) {
        char c = hex_data[i];
        int color_idx;

        // Convert hex character to 4-bit color index (0-15)
        if (c >= '0' && c <= '9') color_idx = c - '0';
        else if (c >= 'a' && c <= 'f') color_idx = 10 + (c - 'a');
        else if (c >= 'A' && c <= 'F') color_idx = 10 + (c - 'A');
        else {
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

    if (line == NULL || *line == '\0') {
        return NULL;
    }

    TIC80AssetData *data = malloc(sizeof(TIC80AssetData));
    if (!data) {
        return NULL;
    }

    // Find the colon separator between index and hex data
    char *colon = strchr(line, ':');
    if (!colon) {
        free(data);
        return NULL;
    }

    // Split at colon: index before, hex_data after
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

// =============================================================================
// Section Processing
// =============================================================================

/// Process all accumulated TIC-80 sections (called after parsing)
void process_all_tic80_sections(void) {

    if (current_tic80_section == NULL) {
        return;
    }

    // Process the current section with its assets
    process_tic80_section(current_tic80_section, current_tic80_assets);

    // Clean up: free section string and asset list
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

    if (strcmp(section, "PALETTE") == 0) {
        if (assets != NULL) {
            TIC80AssetData *data = assets;
            // Parse the 96-char hex string (16 colors x 6 chars each: RRGGBB)
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
	else if (strcmp(section, "MAP") == 0) {
		// Initialize map width from first row in the list
		if (assets != NULL) {
			tic80_map_width = strlen(assets->hex_data) / 2;
			tic80_map_height = 0;  // Will be updated by parse_tic80_map_row
		}

		// Process all map rows
		for (TIC80AssetData *item = assets; item != NULL; item = item->next) {
			parse_tic80_map_row(item->index, item->hex_data);
		}
	}
    // Add other sections (WAVES, SFX, TRACKS) here if needed
}

// =============================================================================
// Accessor Functions
// =============================================================================

/// Check if any TIC-80 assets were found
bool tic80_has_assets(void) {
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

/// Check if map data was loaded
bool tic80_has_map_data(void) {
    return tic80_has_map;
}

/// Get map width
int tic80_get_map_width(void) {
    return tic80_map_width;
}

/// Get map height
int tic80_get_map_height(void) {
    return tic80_map_height;
}

/// Get tile at map position
/// @param x X coordinate
/// @param y Y coordinate
/// @return Tile index (0-511), or 0 if out of bounds
uint8_t tic80_get_map_tile(int x, int y) {
    if (x >= 0 && x < tic80_map_width && y >= 0 && y < tic80_map_height) {
        return tic80_map_data[y * TIC80_MAP_MAX_WIDTH + x];
    }
    return 0;
}

/// Parse a single TIC-80 map row
/// @param row_index Row number (0-255)
/// @param hex_data Hex string of tile indices
/// Parse a single TIC-80 map row
/// @param row_index Row number (0-255)
/// @param hex_data  Hex string of packed bytes (each pair = one nibble-swapped tile ID)
void parse_tic80_map_row(int row_index, const char *hex_data) {
    int hex_len = strlen(hex_data);
    int num_bytes = hex_len / 2;

    // Determine map width from first row (in tiles = bytes)
    if (row_index == 0) {
        tic80_map_width = num_bytes;
        //tic80_map_height = 0;
    }

    // Parse hex pairs into bytes, then nibble-swap
    for (int i = 0; i < hex_len; i += 2) {
        if (i + 1 >= hex_len) break;

        char hex_byte[3] = {hex_data[i], hex_data[i+1], '\0'};
        int byte_val = strtoul(hex_byte, NULL, 16) & 0xFF;

        // Nibble-swap: TIC-80 stores tile IDs as (high_nibble, low_nibble) → (low_nibble, high_nibble)
        int tile_idx = ((byte_val & 0xF0) >> 4) | ((byte_val & 0x0F) << 4);

        int col = i / 2;
        if (col < tic80_map_width && row_index < TIC80_MAP_MAX_HEIGHT) {
            tic80_map_data[row_index * tic80_map_width + col] = (uint8_t)tile_idx;
        }
    }

    // Track max row index
    if (row_index + 1 > tic80_map_height) {
        tic80_map_height = row_index + 1;
    }

    tic80_has_map = true;
}
