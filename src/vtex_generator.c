#include "v32lua.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// =============================================================================
// VTEX File Header Structure
// =============================================================================

typedef struct {
    char magic[8];           // "V32-VTEX"
    uint32_t version;        // 1
    uint32_t texture_count;  // 1 (we're generating one texture)
    uint32_t width;          // 1024
    uint32_t height;         // 1024
    uint32_t reserved[4];
} VTEXHeader;

// =============================================================================
// VTEX Generation
// =============================================================================

void generate_vtex_from_tic80(const char *output_path) {
    FILE *f = fopen(output_path, "wb");
    if (!f) {
        fprintf(stderr, "Error: Could not create VTEX file '%s'\n", output_path);
        return;
    }

    // Write VTEX header
    VTEXHeader hdr = {
        .version = 1,
        .texture_count = 1,
        .width = 1024,
        .height = 1024
    };
    memcpy(hdr.magic, "V32-VTEX", 8);
    fwrite(&hdr, sizeof(hdr), 1, f);

    // Get the palette (either custom or default)
    uint32_t *palette = get_tic80_palette();

    // Generate 1024x1024 texture data
    uint32_t *pixels = calloc(1024 * 1024, sizeof(uint32_t));
    if (!pixels) {
        fclose(f);
        return;
    }

    // Render TIC80 tilesheet (256x256) at top-left
    // TIC80 sheet: 32x32 tiles = 256x256 pixels
    for (int y = 0; y < 256; y++) {
        for (int x = 0; x < 256; x++) {
            uint8_t color_idx = get_tic80_tile_pixel(x, y);
            if (color_idx < 16) {
                pixels[y * 1024 + x] = palette[color_idx];
            } else {
                pixels[y * 1024 + x] = 0xFF000000;  // Black for invalid indices
            }
        }
    }

    // Write texture pixel data
    fwrite(pixels, sizeof(uint32_t), 1024 * 1024, f);

    free(pixels);
    fclose(f);
}

// =============================================================================
// Utility: Generate VTEX path from output filename
// =============================================================================

void generate_vtex_path(const char *asm_path, char *vtex_path, size_t vtex_path_size) {
    // Replace .asm with .vtex
    strncpy(vtex_path, asm_path, vtex_path_size);
    char *last_dot = strrchr(vtex_path, '.');
    if (last_dot) {
        strncpy(last_dot, ".vtex", vtex_path_size - (last_dot - vtex_path));
    } else {
        strncat(vtex_path, ".vtex", vtex_path_size - strlen(vtex_path) - 1);
    }
}
