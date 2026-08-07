#include "v32lua.h"

// =============================================================================
// Generate a single VTEX texture with optional color keying
// =============================================================================
// texture_idx: 0-15 = make that palette color transparent, 16 = all opaque
// =============================================================================

void generate_vtex_from_tic80_with_colorkey(const char *output_path, int texture_idx) {
    FILE *f = fopen(output_path, "wb");
    if (!f) {
        fprintf(stderr, "Error: Could not create VTEX file '%s'\n", output_path);
        return;
    }

    VTEXHeader hdr = { .width = TEX_WIDTH, .height = TEX_HEIGHT };
    memcpy(hdr.magic, "V32-VTEX", 8);
    fwrite(&hdr, sizeof(hdr), 1, f);

    uint32_t *palette = get_tic80_palette();
    uint32_t *pixels = calloc(TEX_WIDTH * TEX_HEIGHT, sizeof(uint32_t));
    if (!pixels) {
        fclose(f);
        return;
    }

    for (int y = 0; y < TEX_HEIGHT; y++) {
        for (int x = 0; x < TEX_WIDTH; x++) {
            uint8_t color_idx = get_tic80_tile_pixel(x, y);
            uint32_t color = palette[color_idx % 16];

            // Palette is AABBGGRR: extract components
            uint8_t alpha = (color >> 24) & 0xFF;    // AA
            uint8_t blue  = (color >> 16) & 0xFF;    // BB
            uint8_t green = (color >> 8)  & 0xFF;    // GG
            uint8_t red   = color & 0xFF;          // RR

            // Convert to RGBA (0xRRGGBBAA)
            uint32_t rgba_color = (red << 24) | (green << 16) | (blue << 8) | alpha;

            // FIX: Color keying - make MATCHING color transparent
            if (texture_idx < 16 && color_idx == texture_idx) {
                rgba_color = rgba_color & 0xFFFFFF00;  // Clear alpha for KEYED color
            } else {
                rgba_color = (rgba_color & 0xFFFFFF00) | 0x000000FF;  // Full alpha for others
            }

            pixels[y * TEX_WIDTH + x] = rgba_color;
        }
    }

    fwrite(pixels, sizeof(uint32_t), TEX_WIDTH * TEX_HEIGHT, f);
    free(pixels);
    fclose(f);
}

// =============================================================================
// Generate all 17 TIC80 colorkey textures
// =============================================================================

void generate_all_tic80_colorkey_textures(const char *base_path) {
    for (int texture_idx = 0; texture_idx < 17; texture_idx++) {
        char vtex_path[256];
        snprintf(vtex_path, sizeof(vtex_path), "%s_colorkey_%d.vtex", base_path, texture_idx);
        generate_vtex_from_tic80_with_colorkey(vtex_path, texture_idx);
    }
}

// =============================================================================
// Original function - now calls the new multi-texture version
// =============================================================================

void generate_vtex_from_tic80(const char *output_path) {
    // For backward compatibility, generate just the opaque version
    // Extract base path without extension
    char base_path[256];
    strncpy(base_path, output_path, sizeof(base_path));
    char *last_dot = strrchr(base_path, '.');
    if (last_dot) {
        *last_dot = '\0';
    }
    generate_vtex_from_tic80_with_colorkey(output_path, 16);  // Opaque version
}

// =============================================================================
// Utility: Generate VTEX path from output filename
// =============================================================================

void generate_vtex_path(const char *asm_path, char *vtex_path, size_t vtex_path_size) {
    strncpy(vtex_path, asm_path, vtex_path_size);
    char *last_dot = strrchr(vtex_path, '.');
    if (last_dot) {
        strncpy(last_dot, ".vtex", vtex_path_size - (last_dot - vtex_path));
    } else {
        strncat(vtex_path, ".vtex", vtex_path_size - strlen(vtex_path) - 1);
    }
}
