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
    {"math.modf",  2},
    {"math.frexp", 2},
    {"math.ldexp", 1},
    // Add other multi-return functions here
    {NULL, 1}  // Default: single return value
};

extern int  w_mainwait;

void  compiler_error   (ErrorType, int, const char *, ...);
void  compiler_warning (ErrorType, int, const char *, ...);
int   get_builtin_return_count (const char *);
char *derive_cart_title_from_filename (const char *);

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
//     or with single quotes. The path is resolved relative to the
//     DIRECTORY OF THE FILE CONTAINING THE DIRECTIVE (so includes nest
//     naturally regardless of where the compiler is invoked from).
//   - Recursive: an included file may itself contain --#include lines.
//   - Cycle detection: A including B including A is a hard compiler error,
//     not infinite recursion.
//   - Include-once by default: the same resolved file is only ever spliced
//     in once for the whole compilation, no matter how many other files
//     include it. This matches the common case of a shared helper file
//     pulled in from several places.
//   - Every INCLUDED file's body is wrapped in `do ... end`. This gives its
//     top-level `local` declarations real block scoping (register_all_
//     globals_prepass() only promotes a bare top-level `local` to a global;
//     a `do...end` body is walked with is_chunk_top_level = 0), while any
//     `function` it defines still comes out as an ordinary global exactly
//     as it would in a single file, since mark_global_as_function() doesn't
//     care what scope it's textually inside. The entry file itself is never
//     wrapped.
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

#endif
