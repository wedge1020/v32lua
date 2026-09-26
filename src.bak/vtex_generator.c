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
    uint8_t *pixel_bytes = malloc(TEX_WIDTH * TEX_HEIGHT * 4); // 4 bytes per pixel (RGBA)
    if (!pixel_bytes) {
        fclose(f);
        return;
    }

    for (int y = 0; y < TEX_HEIGHT; y++) {
        for (int x = 0; x < TEX_WIDTH; x++) {
            uint8_t red, green, blue, alpha;

            if (y >= 256) {
                // --- Palette swatch row: 16 solid 3x3 blocks, regions 512-527 ---
                // swatch c occupies x in [c*4, c*4+2]; x%4==3 is a 1px gap.
                int col   = x / 4;
                int col_x = x % 4;

                if (col >= 16 || col_x == 3) {
                    red = green = blue = alpha = 0x00;   // gap / unused pixel
                } else {
                    uint32_t color = palette[col];
                    blue  = (color >> 16) & 0xFF;
                    green = (color >> 8)  & 0xFF;
                    red   =  color        & 0xFF;
                    // Always opaque -- NOT subject to this texture's colorkey.
                    // pix()/rect()/rectb()/line() must draw reliably regardless
                    // of which sprite-colorkey texture happens to be selected.
                    alpha = 0xFF;
                }
            } else {
                // --- Existing sprite/tile atlas logic, unchanged ---
                uint8_t color_idx = get_tic80_tile_pixel(x, y);
                uint32_t color = palette[color_idx % 16];

                // Palette is AABBGGRR: extract components
                alpha = (color >> 24) & 0xFF;    // AA
                blue  = (color >> 16) & 0xFF;    // BB
                green = (color >> 8)  & 0xFF;    // GG
                red   =  color        & 0xFF;    // RR

                // Apply color keying
                if (texture_idx < 16 && color_idx == texture_idx) {
                    alpha = 0x00;  // Transparent
                } else {
                    alpha = 0xFF;  // Opaque
                }
            }

            // Write RGBA bytes in correct order (R, G, B, A)
            int offset = (y * TEX_WIDTH + x) * 4;
            pixel_bytes[offset + 0] = red;    // R
            pixel_bytes[offset + 1] = green;  // G
            pixel_bytes[offset + 2] = blue;   // B
            pixel_bytes[offset + 3] = alpha;  // A
        }
    }

    fwrite(pixel_bytes, 1, TEX_WIDTH * TEX_HEIGHT * 4, f);
    free(pixel_bytes);
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
