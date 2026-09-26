#include "v32lua.h"
#include "vsnd_generator.h"
#include "tic80_assets.h"

// Global sound data storage
uint8_t tic80_waves[TIC80_NUM_WAVES][TIC80_WAVE_SIZE] = {0};
bool tic80_has_waves = false;
bool tic80_has_sfx = false;
bool tic80_has_tracks = false;

// ============================================================================
// Wave Parsing
// ============================================================================
///
/// Parse a single TIC-80 waveform
///
/// @param wave_index Waveform number (0-31)
/// @param hex_data   Hex string of waveform data (64 chars = 32 bytes)
///
/// TIC-80 waveforms are 32 bytes of 8-bit signed samples
/// Stored in cartridge as hex pairs: "00ff8040..." (64 hex chars)
///
void parse_tic80_wave(int wave_index, const char *hex_data)
{
    if (wave_index < 0 || wave_index >= TIC80_NUM_WAVES) {
        fprintf(stderr, "Warning: Wave index %d out of range (0-%d)\n",
                wave_index, TIC80_NUM_WAVES - 1);
        return;
    }

    size_t hex_len = strlen(hex_data);

    // Each byte = 2 hex chars, so max 64 chars for 32 bytes
    size_t num_bytes = hex_len / 2;
    if (num_bytes > TIC80_WAVE_SIZE) {
        num_bytes = TIC80_WAVE_SIZE;
    }

    for (size_t i = 0; i < num_bytes; i++) {
        char hex_byte[3] = {hex_data[i*2], hex_data[i*2+1], '\0'};
        tic80_waves[wave_index][i] = (uint8_t)strtoul(hex_byte, NULL, 16);
    }

    tic80_has_waves = true;
}

// ============================================================================
// SFX Data Parsing
// ============================================================================

typedef struct {
    uint8_t speed;
    uint8_t volume;
    uint8_t wave_index;
    uint8_t effect;
} TIC80SFXNote;

typedef struct {
    TIC80SFXNote notes[256];  // Max pattern length
    int length;
} TIC80SFX;

static TIC80SFX tic80_sfx[TIC80_NUM_SFX];

// ============================================================================
// SFX Parsing
// ============================================================================
///
/// TIC-80 SFX Note structure (16 bits per note)
/// Bit layout: [speed:4][volume:4][waveform:6][effect:2]
/// Stored as 4 hex chars per note: "0123" = one note
///
/// @param sfx_index SFX number (0-31)
/// @param hex_data  Hex string of SFX pattern data
///
void parse_tic80_sfx(int sfx_index, const char *hex_data)
{
    if (sfx_index < 0 || sfx_index >= TIC80_NUM_SFX) {
        fprintf(stderr, "Warning: SFX index %d out of range (0-%d)\n",
                sfx_index, TIC80_NUM_SFX - 1);
        return;
    }

    size_t hex_len = strlen(hex_data);

    // Each note = 4 hex chars (2 bytes), max 256 notes per SFX
    int num_notes = hex_len / 4;
    if (num_notes > 256) num_notes = 256;

    for (int i = 0; i < num_notes; i++) {
        char hex_note[5] = {0};
        strncpy(hex_note, hex_data + (i * 4), 4);
        uint16_t note_data = (uint16_t)strtoul(hex_note, NULL, 16);

        // Extract note fields
        uint8_t speed    = (note_data >> 12) & 0x0F;   // Bits 15-12
        uint8_t volume   = (note_data >> 8) & 0x0F;    // Bits 11-8
        uint8_t wave_idx = (note_data >> 2) & 0x3F;    // Bits 7-2
        uint8_t effect   = note_data & 0x03;           // Bits 1-0

        // TODO: Store SFX note data for later synthesis
        // tic80_sfx[sfx_index].notes[i] = {speed, volume, wave_idx, effect};
    }

    tic80_has_sfx = true;
}

/*
void parse_tic80_sfx(int sfx_index, const char *hex_data) {
    if (sfx_index < 0 || sfx_index >= TIC80_NUM_SFX) return;

    // TIC-80 SFX format: each note is 4 hex chars (2 bytes)
    // Format: [speed:4][volume:4][wave:6][effect:2]
    size_t hex_len = strlen(hex_data);
    int num_notes = hex_len / 4;

    for (int i = 0; i < num_notes && i < 256; i++) {
        char hex_note[5] = {hex_data[i*4], hex_data[i*4+1],
                           hex_data[i*4+2], hex_data[i*4+3], '\0'};
        uint16_t note_data = (uint16_t)strtoul(hex_note, NULL, 16);

        tic80_sfx[sfx_index].notes[i].speed = (note_data >> 12) & 0x0F;
        tic80_sfx[sfx_index].notes[i].volume = (note_data >> 8) & 0x0F;
        tic80_sfx[sfx_index].notes[i].wave_index = (note_data >> 2) & 0x3F;
        tic80_sfx[sfx_index].notes[i].effect = note_data & 0x03;
    }
    tic80_sfx[sfx_index].length = num_notes;
    tic80_has_sfx = true;
}*/

// ============================================================================
// VSND Generation
// ============================================================================

void generate_vsnd_from_tic80_sounds(const char *output_path) {
    FILE *f = fopen(output_path, "wb");
    if (!f) {
        fprintf(stderr, "Error: Could not create VSND file '%s'\n", output_path);
        return;
    }

    // Write VSND header
    VSNDHeader hdr = {
        .magic = {"V32-VSND"},
        .sample_rate = 44100,
        .num_samples = 0,  // Will calculate
        .num_channels = 1   // Mono for now
    };

    // TODO: Convert TIC-80 sound data to VSND format
    // This involves synthesizing waveform samples from the pattern data

    fwrite(&hdr, sizeof(hdr), 1, f);

    // For now, write placeholder data
    // In a real implementation, you'd:
    // 1. Synthesize each SFX by playing its waveform pattern
    // 2. Convert to 32-bit interleaved stereo format
    // 3. Write sample data

    fclose(f);

    // Register in global sounds list for XML generation
    cart_resource_append (&sounds_head, &sounds_tail,
                              next_sound_id++, "tic80_sounds", output_path);
}

// ============================================================================
// Section Processing Integration
// ============================================================================

void process_tic80_sound_sections(void) {
    if (!tic80_has_waves && !tic80_has_sfx && !tic80_has_tracks) {
        return;
    }

    // Generate VSND file from accumulated sound data
    generate_vsnd_from_tic80_sounds("tic80_sounds.vsnd");
}
