#ifndef __INTERNALS_H
#define __INTERNALS_H

#include <limits.h>
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

// In compiler headers (e.g., compiler.h)
typedef struct {
    const char *name;
    int return_count;  // Number of return values
} BuiltinFunctionInfo;

// In compiler source (e.g., builtins.c)
static const BuiltinFunctionInfo builtin_return_counts[] = {
    { "math.modf",   2 },
    { "math.frexp",  2 },
    { "math.ldexp",  1 },
    { "system.date", 4 },
    { "system.time", 4 },
    { NULL,          1 }  // Default: single return value
};

extern int  w_mainwait;

void  compiler_error   (ErrorType, int, const char *, ...);
void  compiler_warning (ErrorType, int, const char *, ...);
int   get_builtin_return_count (const char *);
char *derive_cart_title_from_filename (const char *);
TilemapAsset *parse_tilemap_csv                   (const char *, const char *);

// ============================================================================
// --#include preprocessing pass
//
// Runs entirely on raw source TEXT, before yyin is ever opened for the real
// lexer/parser. It never introduces a new token: a "--#include "file.lua""
// line is recognized and consumed by this pass and never reaches lex.
//
// Behavior:
//   - Recognizes a line (after leading whitespace) of the form
//         --#include "path/to/file.lua"
//     or with single quotes. The target is resolved by searching, in
//     order: (1) the DIRECTORY OF THE FILE CONTAINING THE DIRECTIVE (so
//     includes nest naturally regardless of where the compiler is invoked
//     from), (2) the compiler's current working directory, (3) each entry
//     of the V32LUA_INCLUDE environment variable when set (colon-
//     separated), (4) the compile-time default V32LUA_INCLUDE_PATH
//     (inc/config.h), where an installed standard-library port is expected
//     to live. An absolute path is used verbatim, skipping the search.
//     Resolution failure is a hard compiler error listing the locations
//     searched.
//   - Recursive: an included file may itself contain --#include lines.
//   - Cycle detection: A including B including A is a hard compiler error,
//     not infinite recursion.
//   - Include-once by default: the same resolved file is only ever spliced
//     in once for the whole compilation, no matter how many other files
//     include it. This matches the common case of a shared helper file
//     pulled in from several places.
//   - An included file's body lands at the chunk's genuine top level,
//     exactly as if its text had been pasted into the including file by
//     hand. (An earlier version wrapped each included body in `do ... end`
//     for block scoping; that was actively harmful -- prepass_walk()
//     treats a do-block as non-top-level, so a top-level `local` inside
//     the wrapper lost its global promotion and ended up in a stack frame
//     that dies before init()/game_loop() ever run. See the comment in
//     src/internals.c's expand_file().)
//
// Known limitation: the scan is line-oriented and does not track whether a
// line is inside a --[[ ... ]] block comment or a string literal. Keep
// --#include on its own line and don't nest it inside those constructs.
// ============================================================================

typedef struct {
    int   combined_start_line; // first line (1-based) in the combined buffer
    int   combined_end_line;   // last line (inclusive) covered by this run
    char *source_file;         // original file this run of lines came from
    int   source_start_line;   // corresponding first line number in that file
} LineMapEntry;

// Expands entry_path and all of its (transitive) --#include directives into
// one heap-allocated buffer, suitable for writing straight into the file
// that becomes yyin. *out_map / *out_map_count receive the line map used to
// translate a combined-buffer line number back to (file, line) for error
// reporting. Returns NULL and calls compiler_error() (which exits) on any
// failure -- callers can treat a non-NULL return as always-succeeded.
char *expand_includes (const char *entry_path, LineMapEntry **out_map, int *out_map_count);

// Frees a line map returned by expand_includes().
void  free_line_map (LineMapEntry *map, int count);

// Translates a combined-buffer line number back to the original source
// file/line it came from, using a map built by expand_includes(). Falls
// back to the closest preceding run (then to fallback_file) for combined
// lines that came from a directive line rather than any spliced file.
void  resolve_source_location (const LineMapEntry *map, int map_count,
                               int combined_line, const char *fallback_file,
                               const char **out_file, int *out_line);

#endif
