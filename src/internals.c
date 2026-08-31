#include "v32lua.h"

int  w_mainwait  = -1;

// ============================================================================
// --#include preprocessing textual inclusion pass
//
// See inc/internals.h for the design rationale. This file is intentionally
// self-contained C (no flex/bison dependency) so it can be unit tested on
// its own.
// ============================================================================

// ----------------------------------------------------------------------------
// Small growable string buffer
// ----------------------------------------------------------------------------
typedef struct {
    char  *buf;
    size_t len;
    size_t cap;
} StrBuf;

static void sb_init (StrBuf *sb)
{
    sb->cap = 4096;
    sb->len = 0;
    sb->buf = (char *) malloc (sb->cap);
    if (sb->buf == NULL) {
        compiler_error (ERR_INTERNAL, -1, "Out of memory in --#include preprocessor");
    }
    sb->buf[0] = '\0';
}

static void sb_append_n (StrBuf *sb, const char *text, size_t n)
{
    if (sb->len + n + 1 > sb->cap) {
        while (sb->len + n + 1 > sb->cap) {
            sb->cap *= 2;
        }
        sb->buf = (char *) realloc (sb->buf, sb->cap);
        if (sb->buf == NULL) {
            compiler_error (ERR_INTERNAL, -1, "Out of memory in --#include preprocessor");
        }
    }
    memcpy (sb->buf + sb->len, text, n);
    sb->len += n;
    sb->buf[sb->len] = '\0';
}

static void sb_append_str (StrBuf *sb, const char *text)
{
    sb_append_n (sb, text, strlen (text));
}

// ----------------------------------------------------------------------------
// Line map builder
// ----------------------------------------------------------------------------
typedef struct {
    LineMapEntry *entries;
    int           count;
    int           cap;
} LineMapBuilder;

static void lmb_init (LineMapBuilder *b)
{
    b->cap     = 16;
    b->count   = 0;
    b->entries = (LineMapEntry *) malloc (sizeof (LineMapEntry) * b->cap);
    if (b->entries == NULL) {
        compiler_error (ERR_INTERNAL, -1, "Out of memory in --#include preprocessor");
    }
}

static void lmb_push (LineMapBuilder *b, int combined_start, int combined_end,
                       const char *file, int source_start)
{
    if (combined_end < combined_start) {
        return; // empty run, nothing to record
    }
    if (b->count == b->cap) {
        b->cap    *= 2;
        b->entries = (LineMapEntry *) realloc (b->entries, sizeof (LineMapEntry) * b->cap);
        if (b->entries == NULL) {
            compiler_error (ERR_INTERNAL, -1, "Out of memory in --#include preprocessor");
        }
    }
    b->entries[b->count].combined_start_line = combined_start;
    b->entries[b->count].combined_end_line   = combined_end;
    b->entries[b->count].source_file         = strdup (file);
    b->entries[b->count].source_start_line   = source_start;
    b->count++;
}

// ----------------------------------------------------------------------------
// Cycle-detection stack / include-once dedup list
// ----------------------------------------------------------------------------
typedef struct IncludeStackNode {
    char                      *resolved_path;
    struct IncludeStackNode   *next;
} IncludeStackNode;

typedef struct DoneListNode {
    char                  *resolved_path;
    struct DoneListNode   *next;
} DoneListNode;

// ----------------------------------------------------------------------------
// Path helpers
// ----------------------------------------------------------------------------

// Returns a malloc'd copy of the directory portion of path ("." if path has
// no '/'). Never returns NULL.
static char *dir_of (const char *path)
{
    const char *slash = strrchr (path, '/');
    if (slash == NULL) {
        return strdup (".");
    }
    size_t len   = (size_t) (slash - path);
    char  *out   = (char *) malloc (len + 1);
    if (out == NULL) {
        compiler_error (ERR_INTERNAL, -1, "Out of memory in --#include preprocessor");
    }
    memcpy (out, path, len);
    out[len] = '\0';
    return out;
}

// Joins a base directory and a (possibly-absolute) path the way an #include
// directive would. Returns a malloc'd string.
static char *join_path (const char *base_dir, const char *rel_path)
{
    char *joined;
    if (rel_path[0] == '/') {
        joined = strdup (rel_path);
    } else {
        size_t need = strlen (base_dir) + 1 + strlen (rel_path) + 1;
        joined = (char *) malloc (need);
        if (joined == NULL) {
            compiler_error (ERR_INTERNAL, -1, "Out of memory in --#include preprocessor");
        }
        snprintf (joined, need, "%s/%s", base_dir, rel_path);
    }
    return joined;
}

// Canonicalizes a path for cycle/dedup comparison. Falls back to a plain
// strdup if the file doesn't exist yet (shouldn't happen -- callers resolve
// only after confirming the file opens) or realpath is unavailable.
static char *canonicalize (const char *path)
{
    char resolved[PATH_MAX];
    if (realpath (path, resolved) != NULL) {
        return strdup (resolved);
    }
    return strdup (path);
}

// Reads an entire file into a NUL-terminated malloc'd buffer. Calls
// compiler_error() (which exits) on failure.
static char *read_whole_file (const char *path, const char *referenced_from)
{
    FILE *f = fopen (path, "rb");
    if (f == NULL) {
        if (referenced_from != NULL) {
            compiler_error (ERR_INTERNAL, -1,
                "--#include: could not open '%s' (referenced from '%s')",
                path, referenced_from);
        } else {
            compiler_error (ERR_INTERNAL, -1, "Could not open input file '%s'", path);
        }
    }
    fseek (f, 0, SEEK_END);
    long size = ftell (f);
    fseek (f, 0, SEEK_SET);
    if (size < 0) {
        compiler_error (ERR_INTERNAL, -1, "Could not determine size of '%s'", path);
    }
    char *buf = (char *) malloc ((size_t) size + 1);
    if (buf == NULL) {
        compiler_error (ERR_INTERNAL, -1, "Out of memory reading '%s'", path);
    }
    size_t read_bytes = fread (buf, 1, (size_t) size, f);
    buf[read_bytes] = '\0';
    fclose (f);
    return buf;
}

// ----------------------------------------------------------------------------
// Directive recognition
//
// Matches (after skipping leading spaces/tabs):
//   --#include "path"
//   --#include 'path'
// Trailing whitespace after the closing quote is tolerated; anything else
// trailing is tolerated too (treated as an end-of-line comment) so a stray
// "-- reason" note after the path doesn't break the match.
// Returns a malloc'd copy of the path on match, NULL otherwise.
// ----------------------------------------------------------------------------
static char *match_include_directive (const char *line)
{
    const char *p = line;
    while (*p == ' ' || *p == '\t') p++;

    const char *prefix = "--#include";
    size_t      plen   = strlen (prefix);
    if (strncmp (p, prefix, plen) != 0) {
        return NULL;
    }
    p += plen;

    if (*p != ' ' && *p != '\t') {
        return NULL; // e.g. "--#includes_foo" -- not our directive
    }
    while (*p == ' ' || *p == '\t') p++;

    char quote = *p;
    if (quote != '"' && quote != '\'') {
        return NULL;
    }
    p++;
    const char *start = p;
    while (*p != '\0' && *p != quote && *p != '\n' && *p != '\r') p++;
    if (*p != quote) {
        return NULL; // unterminated -- let it fall through and lex as-is
    }
    size_t len  = (size_t) (p - start);
    char  *path = (char *) malloc (len + 1);
    if (path == NULL) {
        compiler_error (ERR_INTERNAL, -1, "Out of memory in --#include preprocessor");
    }
    memcpy (path, start, len);
    path[len] = '\0';
    return path;
}

// ----------------------------------------------------------------------------
// Core recursive expansion
// ----------------------------------------------------------------------------
static void expand_file (const char *path, const char *referenced_from, int wrap_in_do_end,
                          StrBuf *out, LineMapBuilder *lm, int *combined_line,
                          IncludeStackNode **stack, DoneListNode **done)
{
    char *resolved = canonicalize (path);

    for (IncludeStackNode *s = *stack; s != NULL; s = s->next) {
        if (strcmp (s->resolved_path, resolved) == 0) {
            compiler_error (ERR_INTERNAL, -1,
                "Circular --#include: '%s' includes itself, directly or indirectly", path);
        }
    }

    if (wrap_in_do_end) {
        for (DoneListNode *d = *done; d != NULL; d = d->next) {
            if (strcmp (d->resolved_path, resolved) == 0) {
                // Already spliced in once elsewhere -- include-once by
                // default. Silently skip; this is the common "shared
                // helper file pulled in from two places" case.
                free (resolved);
                return;
            }
        }
    }

    char *text = read_whole_file (path, referenced_from);

    IncludeStackNode frame = { resolved, *stack };
    *stack = &frame;

    if (wrap_in_do_end) {
        DoneListNode *dn = (DoneListNode *) malloc (sizeof (DoneListNode));
        dn->resolved_path = strdup (resolved);
        dn->next          = *done;
        *done             = dn;

        sb_append_str (out, "do\n");
        (*combined_line)++;
    }

    char *base_dir = dir_of (path);

    int source_line         = 1;
    int run_start_combined  = *combined_line + 1;
    int run_start_source    = source_line;

    const char *p = text;
    while (*p != '\0') {
        const char *line_start = p;
        while (*p != '\0' && *p != '\n') p++;
        int has_newline = (*p == '\n');
        const char *line_end = p; // exclusive, before '\n'
        if (has_newline) p++;     // consume '\n' for next iteration

        size_t raw_len = (size_t) (line_end - line_start);
        char  *line    = (char *) malloc (raw_len + 1);
        memcpy (line, line_start, raw_len);
        line[raw_len] = '\0';

        char *inc_path = match_include_directive (line);
        if (inc_path != NULL) {
            // Close off the run of plain lines emitted so far from this file.
            lmb_push (lm, run_start_combined, *combined_line, path, run_start_source);

            char *child_path = join_path (base_dir, inc_path);
            expand_file (child_path, path, /*wrap=*/1, out, lm, combined_line, stack, done);
            free (child_path);
            free (inc_path);

            source_line++;
            run_start_combined = *combined_line + 1;
            run_start_source   = source_line;
        } else {
            sb_append_n (out, line, raw_len);
            sb_append_str (out, "\n");
            (*combined_line)++;
            source_line++;
        }

        free (line);
    }

    lmb_push (lm, run_start_combined, *combined_line, path, run_start_source);
    free (base_dir);
    free (text);

    if (wrap_in_do_end) {
        sb_append_str (out, "end\n");
        (*combined_line)++;
    }

    *stack = frame.next;
    free (resolved);
}

char *expand_includes (const char *entry_path, LineMapEntry **out_map, int *out_map_count)
{
    StrBuf out;
    sb_init (&out);
    LineMapBuilder lm;
    lmb_init (&lm);

    int               combined_line = 0;
    IncludeStackNode *stack         = NULL;
    DoneListNode     *done          = NULL;

    expand_file (entry_path, NULL, /*wrap=*/0, &out, &lm, &combined_line, &stack, &done);

    while (done != NULL) {
        DoneListNode *next = done->next;
        free (done->resolved_path);
        free (done);
        done = next;
    }

    *out_map       = lm.entries;
    *out_map_count = lm.count;
    return out.buf;
}

void free_line_map (LineMapEntry *map, int count)
{
    if (map == NULL) return;
    for (int i = 0; i < count; i++) {
        free (map[i].source_file);
    }
    free (map);
}

void resolve_source_location (const LineMapEntry *map, int map_count,
                               int combined_line, const char *fallback_file,
                               const char **out_file, int *out_line)
{
    if (map == NULL || map_count == 0) {
        *out_file = fallback_file;
        *out_line = combined_line;
        return;
    }

    for (int i = 0; i < map_count; i++) {
        if (combined_line >= map[i].combined_start_line &&
            combined_line <= map[i].combined_end_line) {
            *out_file = map[i].source_file;
            *out_line = map[i].source_start_line + (combined_line - map[i].combined_start_line);
            return;
        }
    }

    // Landed on a synthetic line (a "do"/"end" wrapper, or an --#include
    // directive line itself, neither of which appears in the map). Fall
    // back to the closest preceding run so the error still points somewhere
    // useful instead of an unmapped combined-buffer line number.
    const LineMapEntry *best = NULL;
    for (int i = 0; i < map_count; i++) {
        if (map[i].combined_end_line < combined_line) {
            if (best == NULL || map[i].combined_end_line > best->combined_end_line) {
                best = &map[i];
            }
        }
    }
    if (best != NULL) {
        *out_file = best->source_file;
        *out_line = best->source_start_line + (best->combined_end_line - best->combined_start_line);
    } else {
        *out_file = fallback_file;
        *out_line = combined_line;
    }
}

void compiler_error (ErrorType type, int line_num, const char* format, ...)
{
    // 1. Print the Error Type Prefix
    fprintf (stderr, "\n");
    switch (type)
    {
        case ERR_LEXICAL:
            fprintf (stderr, "[Lexical Error]");
            break;

        case ERR_SYNTAX:
            fprintf (stderr, "[Syntax Error]");
            break;

        case ERR_SEMANTIC:
            fprintf (stderr, "[Semantic Error]");
            break;

        case ERR_INTERNAL:
            fprintf (stderr, "[Internal Compiler Error]");
            break;

        default:
            fprintf (stderr, "[Unknown Error]");
            break;
    }

    // When --#include has been used, line_num is a position in the
    // combined buffer that actually became yyin -- translate it back to
    // the original source file/line for display. For a plain single-file
    // compile g_line_map_count is 0 and this is a no-op: disp_file always
    // equals g_lua_filename, so the message is byte-identical to before.
    const char *disp_file = g_lua_filename;
    int         disp_line = line_num;
    if (line_num > 0 && g_line_map_count > 0)
    {
        resolve_source_location (g_line_map, g_line_map_count, line_num,
                                  g_lua_filename, &disp_file, &disp_line);
    }
    
    if (line_num >  0)
    {
        if (disp_file != NULL && g_lua_filename != NULL && strcmp (disp_file, g_lua_filename) != 0)
        {
            fprintf (stderr, " in %s on line %d: ", disp_file, disp_line);
        }
        else
        {
            fprintf (stderr, " on line %d: ", disp_line);
        }
    }
    else
    {
        fprintf (stderr, ": ");
    }

    // 2. Format and print the custom message
    va_list args;
    va_start (args, format);
    vfprintf (stderr, format, args);
    va_end (args);
    fprintf (stderr, "\n");

    // 3. Highlight the line of code (if we have a valid line number and file).
    // yyin holds whatever was actually parsed -- the combined buffer when
    // --#include was used -- so this still seeks by the raw line_num; only
    // the printed line-number label uses the translated disp_line.
    if (line_num > 0 && yyin != NULL)
    {
        rewind (yyin);
        char  line_buffer[1024];
        int   current_line    = 1;
        while (fgets(line_buffer, sizeof(line_buffer), yyin))
        {
            if (current_line == line_num)
            {
                fprintf (stderr, "      |\n");
                fprintf (stderr, " %4d | %s", disp_line, line_buffer);
                if (strchr(line_buffer, '\n') == NULL)
                {
                    fprintf (stderr, "\n");
                }
                fprintf (stderr, "      |\n\n");
                break;
            }
            current_line++;
        }
    }

    // 4. Halt compilation
    exit (1);
}

void compiler_warning (ErrorType type, int line_num, const char* format, ...)
{
    // 1. Print the Error Type Prefix
    fprintf (stderr, "\n");
    switch (type)
    {
        case ERR_LEXICAL:
            fprintf (stderr, "[Lexical Warning]");
            break;

        case ERR_SYNTAX:
            fprintf (stderr, "[Syntax Warning]");
            break;

        case ERR_SEMANTIC:
            fprintf (stderr, "[Semantic Warning]");
            break;

        case ERR_INTERNAL:
            fprintf (stderr, "[Internal Compiler Warning]");
            break;

        default:
            fprintf (stderr, "[Unknown Warning]");
            break;
    }

    // See compiler_error() above for why this translation is a no-op
    // (disp_file == g_lua_filename) unless --#include was used.
    const char *disp_file = g_lua_filename;
    int         disp_line = line_num;
    if (line_num > 0 && g_line_map_count > 0)
    {
        resolve_source_location (g_line_map, g_line_map_count, line_num,
                                  g_lua_filename, &disp_file, &disp_line);
    }

    if (line_num >  0)
    {
        if (disp_file != NULL && g_lua_filename != NULL && strcmp (disp_file, g_lua_filename) != 0)
        {
            fprintf (stderr, " in %s on line %d: ", disp_file, disp_line);
        }
        else
        {
            fprintf (stderr, " on line %d: ", disp_line);
        }
    }
    else
    {
        fprintf (stderr, ": ");
    }
    
    // 2. Format and print the custom message
    va_list args;
    va_start (args, format);
    vfprintf (stderr, format, args);
    va_end (args);
    fprintf (stderr, "\n");

    // 3. Highlight the line of code (if we have a valid line number and file).
    // yyin holds whatever was actually parsed -- the combined buffer when
    // --#include was used -- so this still seeks by the raw line_num; only
    // the printed line-number label uses the translated disp_line.
    if (line_num > 0 && yyin != NULL)
    {
        rewind (yyin);
        char  line_buffer[1024];
        int   current_line    = 1;
        while (fgets(line_buffer, sizeof(line_buffer), yyin))
        {
            if (current_line == line_num)
            {
                fprintf (stderr, "      |\n");
                fprintf (stderr, " %4d | %s", disp_line, line_buffer);
                if (strchr(line_buffer, '\n') == NULL)
                {
                    fprintf (stderr, "\n");
                }
                fprintf (stderr, "      |\n\n");
                break;
            }
            current_line++;
        }
    }
}

// Helper function to look up return count
int get_builtin_return_count(const char *func_name) {
    for (int i = 0; builtin_return_counts[i].name != NULL; i++) {
        if (strcmp(func_name, builtin_return_counts[i].name) == 0) {
            return builtin_return_counts[i].return_count;
        }
    }
    return 1;  // Default to single return value
}

// Derives a fallback cart title from the input filename: strips any
// directory path (handles both '/' and '\' separators defensively,
// since command-line invocation could come from either) and strips a
// trailing ".lua" extension if present. Returns a pointer into a static
// buffer -- caller should copy out before calling this again.
char *derive_cart_title_from_filename(const char *path)
{
    const char *base = strrchr(path, '/');
    const char *base_bs = strrchr(path, '\\');
    if (base_bs != NULL && (base == NULL || base_bs > base)) {
        base = base_bs;
    }
    base = (base != NULL) ? base + 1 : path;

    static char title_buf[256];
    strncpy(title_buf, base, sizeof(title_buf) - 1);
    title_buf[sizeof(title_buf) - 1] = '\0';

    char *dot = strrchr(title_buf, '.');
    if (dot != NULL && strcmp(dot, ".lua") == 0) {
        *dot = '\0';
    }
    return title_buf;
}

