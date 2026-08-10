#ifndef __VSND_GENERATOR_H
#define __VSND_GENERATOR_H

#include <stdint.h>

// VSND File Header
typedef struct
{
    char      magic[9];     // "V32-VSND"
    uint32_t  sample_rate;  // 44100
    uint32_t  num_samples;
    uint32_t  num_channels; // 1=mono, 2=stereo
} VSNDHeader;

// TIC-80 Sound Constants
#define  TIC80_NUM_WAVES    32
#define  TIC80_NUM_SFX      32
#define  TIC80_NUM_TRACKS   8
#define  TIC80_WAVE_SIZE    32

void  generate_vsnd_from_tic80_sounds (const char *);
void  process_tic80_sound_sections    (void);
void  parse_tic80_wave                (int,  const char *);
void  parse_tic80_sfx                 (int,  const char *);

#endif
