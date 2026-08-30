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
uint32_t hex_to_v32_color(const char *hex_rgb) {
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
void parse_tic80_tile(int tile_index, const char *hex_data) {

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

    // Skip the "-- " prefix if present
    if (line[0] == '-' && line[1] == '-' && line[2] == ' ') {
        line += 3;
    }

    TIC80AssetData *data = malloc(sizeof(TIC80AssetData));
    if (!data) {
        return NULL;
    }

    char *colon = strchr(line, ':');
    if (!colon) {
        free(data);
        return NULL;
    }

    *colon = '\0';
    data->index = atoi(line);  // Now correctly parses "015" as 15
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

// ============================================================================
// Process all accumulated TIC-80 sections (called after parsing)
// ============================================================================
void process_all_tic80_sections(void)
{
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

    // ========================================================================
    // Generate VSND from sound sections - NEW
    // ========================================================================
    if (tic80_has_waves || tic80_has_sfx || tic80_has_tracks) {
        // Generate VSND file from accumulated sound data
        generate_vsnd_from_tic80_sounds("tic80_sounds.vsnd");

        // Register in global sounds list for XML generation
        CARTresource* res = (CARTresource*)malloc(sizeof(CARTresource));
        res->id = next_sound_id++;
        res->var_name = strdup("tic80_sounds");
        res->filename = strdup("tic80_sounds.vsnd");
        res->next = sounds_head;
        sounds_head = res;
    }
}

// ============================================================================
// Process a single TIC-80 section (PALETTE, TILES, MAP, WAVES, SFX, TRACKS)
// ============================================================================
///
/// @param section Section name ("PALETTE", "TILES", "WAVES", etc.)
/// @param assets Linked list of asset data for this section
///
void process_tic80_section(const char *section, TIC80AssetData *assets)
{
    // ========================================================================
    // PALETTE SECTION
    // Format: single line with 96 hex chars (16 colors x RRGGBB)
    // Example: -- 0:2C1C1A5D275D533EB1... (96 chars total)
    // ========================================================================
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
    // ========================================================================
    // TILES SECTION
    // Format: multiple lines, each: index:64_hex_chars (8x8 tile)
    // Example: -- 000:0123456789abcdef... (64 chars = 32 bytes)
    // ========================================================================
    else if (strcmp(section, "TILES") == 0) {
        // Process all tile data
        for (TIC80AssetData *item = assets; item != NULL; item = item->next) {
            parse_tic80_tile(item->index, item->hex_data);
        }
        tic80_has_any_assets = true;
    }
    // ========================================================================
    // MAP SECTION
    // Format: multiple lines, each: index:hex_pairs (nibble-swapped tile IDs)
    // Example: -- 000:0123456789... (variable length)
    // ========================================================================
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
    // ========================================================================
    // WAVES SECTION - NEW
    // Format: multiple lines, each: index:32_hex_bytes (32-byte waveform)
    // Example: -- 000:00000000ffffffff00000000ffffffff
    // TIC-80 has 32 waveforms, each 32 bytes
    // ========================================================================
    else if (strcmp(section, "WAVES") == 0) {
        for (TIC80AssetData *item = assets; item != NULL; item = item->next) {
            parse_tic80_wave(item->index, item->hex_data);
        }
        tic80_has_waves = true;
    }
    // ========================================================================
    // SFX SECTION - NEW
    // Format: multiple lines, each: index:hex_data (SFX pattern)
    // Example: -- 000:0000111122223333...
    // TIC-80 SFX format: [speed:4][volume:4][wave:6][effect:2] per note
    // ========================================================================
    else if (strcmp(section, "SFX") == 0) {
        for (TIC80AssetData *item = assets; item != NULL; item = item->next) {
            parse_tic80_sfx(item->index, item->hex_data);
        }
        tic80_has_sfx = true;
    }
    // ========================================================================
    // TRACKS SECTION - NEW
    // Format: multiple lines, each: index:hex_data (music track pattern)
    // Example: -- 000:00010203...
    // TIC-80 has 8 music tracks
    // ========================================================================
    else if (strcmp(section, "TRACKS") == 0) {
        for (TIC80AssetData *item = assets; item != NULL; item = item->next) {
            parse_tic80_track(item->index, item->hex_data);
        }
        tic80_has_tracks = true;
    }
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

// ============================================================================
// TIC-80 Sound Constants
// ============================================================================
#define TIC80_NUM_WAVES    32    // Maximum waveforms
#define TIC80_NUM_SFX      32    // Maximum sound effects
#define TIC80_NUM_TRACKS   8     // Maximum music tracks
#define TIC80_WAVE_SIZE    32    // Waveform size in bytes

// ============================================================================
// Sound Data Storage (add to global state)
// ============================================================================
//uint8_t tic80_waves[TIC80_NUM_WAVES][TIC80_WAVE_SIZE] = {0};

// ============================================================================
// Track Parsing
// ============================================================================
///
/// Parse a single TIC-80 music track
///
/// @param track_index Track number (0-7)
/// @param hex_data   Hex string of track pattern data
///
/// TIC-80 track format is similar to SFX but with additional
/// channel/tempo information
///
void parse_tic80_track(int track_index, const char *hex_data)
{
    if (track_index < 0 || track_index >= TIC80_NUM_TRACKS) {
        fprintf(stderr, "Warning: Track index %d out of range (0-%d)\n",
                track_index, TIC80_NUM_TRACKS - 1);
        return;
    }

    // TODO: Implement track parsing
    // Similar to SFX but with multi-channel data

    tic80_has_tracks = true;
}

// ============================================================================
// TIC-80 Section Detection - Handle <WAVES>, <SFX>, <TRACKS> tags
// ============================================================================

// Check if line is a TIC-80 section start tag: -- <SECTION>
bool is_tic80_section_start(const char *line, char *section_name, size_t name_size) {
    if (strncmp(line, "-- <", 4) != 0) return false;

    char *start = strchr(line, '<');
    char *end = strchr(line, '>');
    if (!start || !end) return false;

    size_t len = end - start - 1;
    if (len >= name_size) return false;

    strncpy(section_name, start + 1, len);
    section_name[len] = '\0';

    return true;
}

// Check if line is a TIC-80 section end tag: -- </SECTION>
bool is_tic80_section_end(const char *line, const char *section_name) {
    char expected[64];
    snprintf(expected, sizeof(expected), "-- </%s>", section_name);
    return strncmp(line, expected, strlen(expected)) == 0;
}
