#ifndef __V32LUA_CONFIG_H
#define __V32LUA_CONFIG_H

// ============================================================================
// v32lua build-time configuration
// ----------------------------------------------------------------------------
// Installation-dependent defaults live here. Every value is wrapped in an
// #ifndef guard so it can be overridden at build time without editing this
// file, e.g.:
//     make CFLAGS="-Wall -Wextra -g -I ../inc -DV32LUA_INCLUDE_PATH='\"/opt/v32lua/include\"'"
// ============================================================================

// ----------------------------------------------------------------------------
// --#include search path
// ----------------------------------------------------------------------------
// A --#include "name" directive whose target is not found next to the file
// that wrote it (see inc/internals.h for the full search order) falls back
// to the directories configured here. This is where an installed copy of
// the v32lua standard-library ports (lib/audio.lua, lib/math.lua, ...) is
// expected to live, so a program can --#include "string.lua" from any
// project directory without copying the library around.
//
// The environment variable named by V32LUA_INCLUDE_ENV_VAR (a colon-
// separated list of directories) is searched BEFORE this default, letting
// individual projects point at their own library copies without installing
// anything system-wide.
#ifndef V32LUA_INCLUDE_PATH
#define V32LUA_INCLUDE_PATH "/usr/local/Vircon32/v32lua/include"
#endif

#ifndef V32LUA_INCLUDE_ENV_VAR
#define V32LUA_INCLUDE_ENV_VAR "V32LUA_INCLUDE"
#endif

// ============================================================================
// Compiler defaults
// ----------------------------------------------------------------------------
// What the compiler does when neither the command line nor a --# hint in
// the source says otherwise. Precedence, highest first:
//     command-line option  >  --# hint in the source  >  these defaults
// Change a value here and rebuild (make clean; make), or override one at
// build time without editing this file, e.g.:
//     make CFLAGS="-Wall -Wextra -g -I ../inc -DV32LUA_DEFAULT_PICO8_RATE=11025"
// ============================================================================

// Sample rate (Hz) of the sounds synthesized from a PICO-8 cart's
// __sfx__/__music__ and from a TIC-80 cart's <SFX>/<WAVES>/<PATTERNS>/
// <TRACKS>: 11025, 22050 or 44100. Lower rates make much smaller carts
// (22050 is about half of 44100); the sounds are played back at the right
// pitch either way. Overridden by --rate / --#rate.
#ifndef V32LUA_DEFAULT_PICO8_RATE
#define V32LUA_DEFAULT_PICO8_RATE   22050
#endif
#ifndef V32LUA_DEFAULT_TIC80_RATE
#define V32LUA_DEFAULT_TIC80_RATE   22050
#endif

// TIC-80 / PICO-8: draw filled circles larger than the shape atlas (radius
// 31) as the largest disc scaled up -- one draw instead of about 1.2 per
// unit of radius, with about 1.5% of the edge pixels differing from the
// console's. 0 = exact (default), 1 = fast. --fast-circles / --#fast-circles
// turn it on for one cart.
#ifndef V32LUA_DEFAULT_FAST_CIRCLES
#define V32LUA_DEFAULT_FAST_CIRCLES 0
#endif

// PICO-8: the side panels ("bezel") beside the 128x128 screen. 1 = on
// (default), 0 = black margins. --no-bezel / --#bezel off, --bezel FILE.
#ifndef V32LUA_DEFAULT_PICO8_BEZEL
#define V32LUA_DEFAULT_PICO8_BEZEL  1
#endif

// PICO-8: custom side-panel art used when a cart doesn't name its own
// (--bezel FILE / --#bezel "FILE"): a path to a PNG or .vtex with both
// panels side by side (see doc/PICO8.md, "Side panels"), or NULL for the
// built-in panels. A relative path is taken from the directory the
// compiler runs in.
#ifndef V32LUA_DEFAULT_PICO8_BEZEL_FILE
#define V32LUA_DEFAULT_PICO8_BEZEL_FILE NULL
#endif

// Print compiler warnings (1, default) or not (0, as with -w).
#ifndef V32LUA_DEFAULT_WARNINGS
#define V32LUA_DEFAULT_WARNINGS     1
#endif

#if V32LUA_DEFAULT_PICO8_RATE != 11025 && V32LUA_DEFAULT_PICO8_RATE != 22050 && V32LUA_DEFAULT_PICO8_RATE != 44100
#error "V32LUA_DEFAULT_PICO8_RATE must be 11025, 22050 or 44100"
#endif
#if V32LUA_DEFAULT_TIC80_RATE != 11025 && V32LUA_DEFAULT_TIC80_RATE != 22050 && V32LUA_DEFAULT_TIC80_RATE != 44100
#error "V32LUA_DEFAULT_TIC80_RATE must be 11025, 22050 or 44100"
#endif

#endif
