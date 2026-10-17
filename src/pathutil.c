#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "pathutil.h"

// The last '/' or '\' in `path`, or NULL.
static const char *last_separator (const char *path)
{
    const char *fwd  = strrchr (path, '/');
    const char *back = strrchr (path, '\\');
    if (fwd == NULL)  return back;
    if (back == NULL) return fwd;
    return (back > fwd) ? back : fwd;
}

char *replace_extension (const char *path, const char *new_ext)
{
    const char *dot       = strrchr (path, '.');
    const char *slash     = last_separator (path);
    size_t      base_len  = (dot != NULL && (slash == NULL || dot > slash))
                          ? (size_t) (dot - path)
                          : strlen (path);
    size_t      ext_len   = strlen (new_ext);
    char       *result    = malloc (base_len + ext_len + 1);

    if (result == NULL) { fprintf (stderr, "Compiler Error: out of memory\n"); exit (2); }
    memcpy (result,            path,    base_len);
    memcpy (result + base_len, new_ext, ext_len);
    result[base_len + ext_len] = '\0';
    return result;
}

const char *path_basename (const char *path)
{
    const char *slash = last_separator (path);
    return (slash != NULL) ? slash + 1 : path;
}

char *path_dirname (const char *path)
{
    const char *slash = last_separator (path);

    if (slash == NULL)  return strdup (".");
    if (slash == path)  return strdup ("/");     // "/foo" -> "/"

    size_t len    = (size_t) (slash - path);
    char  *result = malloc (len + 1);
    if (result == NULL) { fprintf (stderr, "Compiler Error: out of memory\n"); exit (2); }
    memcpy (result, path, len);
    result[len] = '\0';
    return result;
}

// Splits `path` (made absolute against the current directory when it is
// relative) into normalized components. "." is dropped and ".." pops the
// previous component. Returns the count; the caller frees each part.
static int split_normalized (const char *path, char **parts, int max_parts)
{
    char    cwd[4096];
    size_t  cap    = strlen (path) + sizeof (cwd) + 2;
    char   *full   = malloc (cap);
    int     is_abs = (path[0] == '/' || path[0] == '\\' ||
                      (path[0] != '\0' && path[1] == ':'));
    int     count  = 0;

    if (full == NULL) { fprintf (stderr, "Compiler Error: out of memory\n"); exit (2); }
    full[0] = '\0';
    if (!is_abs && getcwd (cwd, sizeof (cwd)) != NULL)
    {
        strcat (full, cwd);
        strcat (full, "/");
    }
    strcat (full, path);

    for (char *tok = full; *tok != '\0'; )
    {
        char *end = tok;
        while (*end != '\0' && *end != '/' && *end != '\\') end++;
        char saved = *end;
        *end = '\0';

        if (tok[0] == '\0' || strcmp (tok, ".") == 0)
        {
            // skip
        }
        else if (strcmp (tok, "..") == 0)
        {
            if (count > 0) free (parts[--count]);
        }
        else if (count < max_parts)
        {
            parts[count++] = strdup (tok);
        }

        if (saved == '\0') break;
        tok = end + 1;
    }
    free (full);
    return count;
}

char *path_relative_to (const char *from_dir, const char *target)
{
    enum { MAXP = 256 };
    char *from_parts[MAXP], *to_parts[MAXP];
    int   nf     = split_normalized (from_dir, from_parts, MAXP);
    int   nt     = split_normalized (target,   to_parts,   MAXP);
    int   common = 0;

    while (common < nf && common < nt - 1 &&
           strcmp (from_parts[common], to_parts[common]) == 0)
    {
        common++;
    }

    size_t cap = 4;
    for (int i = common; i < nt; i++) cap += strlen (to_parts[i]) + 1;
    cap += (size_t) (nf - common) * 3;

    char *result = malloc (cap);
    if (result == NULL) { fprintf (stderr, "Compiler Error: out of memory\n"); exit (2); }
    result[0] = '\0';
    for (int i = common; i < nf; i++) strcat (result, "../");
    for (int i = common; i < nt; i++)
    {
        strcat (result, to_parts[i]);
        if (i + 1 < nt) strcat (result, "/");
    }
    for (int i = 0; i < nf; i++) free (from_parts[i]);
    for (int i = 0; i < nt; i++) free (to_parts[i]);
    return result;
}
