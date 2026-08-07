#include "v32lua.h"

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

// =============================================================================
// VTEX Generation
// =============================================================================

void generate_vtex_from_tic80(const char *output_path) {
	fprintf(stderr, "DEBUG VTEX: Generating to '%s'\n", output_path);
    FILE *f = fopen(output_path, "wb");
    if (!f) {
        fprintf(stderr, "Error: Could not create VTEX file '%s'\n", output_path);
        return;
    }

    // Write MINIMAL VTEX header: magic + width + height
    VTEXHeader hdr = {
        .width = TEX_WIDTH,
        .height = TEX_HEIGHT
    };
    memcpy(hdr.magic, "V32-VTEX", 8);
    fwrite(&hdr, sizeof(hdr), 1, f);  // 16 bytes total

    // Get the palette
    uint32_t *palette = get_tic80_palette();

    // Generate texture data - only what we need
    uint32_t *pixels = calloc(TEX_WIDTH * TEX_HEIGHT, sizeof(uint32_t));
    if (!pixels) {
        fclose(f);
        return;
    }

	fprintf(stderr, "DEBUG VTEX: Sampling pixels: (0,0)=%02x, (8,0)=%02x, (16,0)=%02x\n",
		get_tic80_tile_pixel(0, 0),
		get_tic80_tile_pixel(8, 0),
		get_tic80_tile_pixel(16, 0));

    // Render TIC80 tilesheet (128x256)
    for (int y = 0; y < TEX_HEIGHT; y++) {
        for (int x = 0; x < TEX_WIDTH; x++) {
            uint8_t color_idx = get_tic80_tile_pixel(x, y);
            pixels[y * TEX_WIDTH + x] = (color_idx < 16) ? palette[color_idx] : 0xFF000000;
        }
    }

    // Write pixel data immediately after header
    fwrite(pixels, sizeof(uint32_t), TEX_WIDTH * TEX_HEIGHT, f);

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
