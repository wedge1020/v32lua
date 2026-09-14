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

#endif
