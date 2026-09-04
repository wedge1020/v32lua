#ifndef __V32LUA_H
#define __V32LUA_H

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdbool.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

#include "enums.h"
#include "vtex_generator.h"
#include "vsnd_generator.h"
#include "tic80_assets.h"
#include "emit.h"
#include "ast.h"
#include "context.h"
#include "table.h"
#include "intrinsics.h"
#include "generate.h"
#include "internals.h"
#include "register.h"
#include "closures.h"

#define  VERSION             "20260904-dev"
#define  AUTHOR              "Matthew Haas"
#define  URL                 "https://github.com/wedge1020/v32lua"

#define  MATH_PI             3.14159265358979323846
#define  MATH_HUGE           (1.0 / 0.0)  // Infinity in IEEE 754

#define  V32_CART_PAGE       0x20000000
#define  NAN_VALUE           0x7F800000
#define  BOXED_CATEGORY      0x80000000 // sign bit used for RAM (1) vs ROM (0)
#define  BOXED_TYPE          0x00400000 // quiet-NaN used for TABLE/FUNCTION (0) vs STRING (1)
#define  BOXED_DATA          0xFFC00000 // common bitmask to indicate boxed data
#define  BOXED_FUNCTION      0x7F800000 // bitmask for boxed lua function (ROM)
#define  BOXED_ROMSTRING     0x7FC00000 // bitmank for boxed lua string literal (ROM)
#define  BOXED_TABLE         0xFF800000 // bitmask for boxed lua table (RAM)
#define  BOXED_RAMSTRING     0xFFC00000 // starting at offset 4 (includes nil/false/true)
#define  BOXED_NIL           0xFFC00000
#define  BOXED_FALSE         0xFFC00001
#define  BOXED_BOOLEAN       0xFFC00001 // mathing our way to true/false
#define  BOXED_TRUE          0xFFC00002
#define  BOXED_TOMBSTONE     0xFFC00003 // future feature
#define  BOXED_PAYLOAD       0x003FFFFF
#define  TABLE_ARRAYSIZE     0x0000FFFF

// One spare bit inside a BOXED_FUNCTION payload. Ordinary functions leave it
// 0 (payload = ROM code address, exactly as before). A closure sets it, and
// the remaining payload bits become a RAM address of a closure record
// instead. This keeps closures indistinguishable from plain functions to
// type()/print()/everything else -- only __builtin_exec needs to know.
//
// ASSUMPTION TO VERIFY: this steals bit 21, leaving 21 bits (~2MB) of heap
// address space for closure records. Check that against Vircon32's actual
// RAM size before relying on it -- if RAM is larger than that, pick a
// different bit or widen the check.
#define  BOXED_CLOSURE_FLAG  0x00200000
#define  CLOSURE_ADDR_MASK   0x001FFFFF

// Vircon32 hardware memory card. Word-addressed, exactly like the rest of
// this VM's memory (an address unit is one 4-byte word, not one byte --
// see the note on [Rd+N] addressing next to __builtin_vircon32_btnp in
// vircon32.s). A fixed physical range entirely outside the compiler-
// managed RAM pool -- next_ram_address never touches it -- same category
// as V32_CART_PAGE above, not a reservation like VIRCON32_SFX_CURSOR.
//
// Layout: the title block is VIRCON32_MEMCARD_TITLE_WORDS words
// (0x30000000..0x30000013), but memcard.title() itself may only write the
// first VIRCON32_MEMCARD_TITLE_DISPLAY_WORDS of those (16) -- the last 4
// are reserved for compiler-managed metadata, not free-form title text.
// Word VIRCON32_MEMCARD_CURSOR_ADDR (the very last title word, position
// -1) holds the persistent on-card auto-append cursor used by
// memcard.save(value) with NO position argument -- see
// __builtin_vircon32_memcard_append in vircon32.s. It lives ON THE CARD
// ITSELF, not in Vircon32 RAM, so it survives a reboot: repeated
// no-position saves keep appending rather than overwriting position 0
// every run. The remaining 3 reserved words (positions -4..-2) are
// currently unused -- reserved so a future feature has somewhere to grow
// without colliding with hand-picked title/data positions a program
// might already be using.
//
// Everything from VIRCON32_MEMCARD_DATA_BASE onward is free for
// memcard.save()/memcard.load()/memcard[pos] -- position 0 is the first
// data word; positions -1..-20 reach back into the title/metadata region
// (reachable, but you have to consciously go negative to get there).
// VIRCON32_MEMCARD_END is the last valid word address, inclusive.
#define  VIRCON32_MEMCARD_BASE                0x30000000
#define  VIRCON32_MEMCARD_TITLE_WORDS         20
#define  VIRCON32_MEMCARD_TITLE_DISPLAY_WORDS 16
#define  VIRCON32_MEMCARD_DATA_BASE           (VIRCON32_MEMCARD_BASE + VIRCON32_MEMCARD_TITLE_WORDS)
#define  VIRCON32_MEMCARD_CURSOR_ADDR         (VIRCON32_MEMCARD_DATA_BASE - 1)
#define  VIRCON32_MEMCARD_END                 0x3003FFFF

// GPU Commands
#define  GPUCommand_DrawRegion           0x11
#define  GPUCommand_DrawRegionZoomed     0x12
#define  GPUCommand_DrawRegionRotated    0x13
#define  GPUCommand_DrawRegionRotozoomed 0x14

// Blending Modes
#define  GPUBlendingMode_Alpha           0x20
#define  GPUBlendingMode_Add             0x21
#define  GPUBlendingMode_Subtract        0x22

extern int g_verbose_debug;      // verbose real-time debug output

// Prototypes for functions generated by Flex/Bison
int  yyparse (void);
extern FILE *yyin;

extern LineMapEntry *g_line_map;
extern int           g_line_map_count;

#endif
