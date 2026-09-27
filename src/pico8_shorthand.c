// ============================================================================
// pico8_shorthand.c - PICO-8's then-less `if (c) ...` / do-less `while (c) ...`
// ============================================================================
//
// PICO-8 (z8lua) accepts
//
//     if (cond) stmt stmt ... [else stmt ...]
//     while (cond) stmt ...
//
// when the condition is parenthesized and `then` / `do` is left out: the
// body is THE REST OF THE LINE. That is line-based, which the grammar can't
// express without ambiguity (parser.y's then-less `if` took one statement
// and a bare return/break; `if (n==1) return 12` was a syntax error).
// So PICO-8 source is rewritten before lexing, on the same lines (line
// numbers in errors don't move):
//
//     if (n==1) return 12           ->  if (n==1) then return 12 end
//     if (a) x=1 else x=2 -- c      ->  if (a) then x=1 else x=2 end -- c
//     while (busy()) flip()         ->  while (busy()) do flip() end
//
// What counts as the shorthand: `if`/`while`, then `(`, the matching `)`,
// and then, on the same line, a token that can START a statement -- not
// `then`/`do`, not a binary operator, `and`/`or`, `.` `:` `[` `(` `{` or a
// string (all of which continue the condition: `if (a) > (b) then`).
//
// Where the body ends: at the end of the line -- unless a bracket or a
// block opened in it is still open there (`if (x) foo(function()` ...),
// in which case at the end of the line where those close. And an `end`
// (or `until`) that closes a block opened BEFORE the shorthand ends it
// first: `function f() if (x) return 1 end` -> `... then return 1 end end`.
// The inserted `end` goes before a trailing `--` comment.
// ============================================================================

#include <ctype.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef struct { size_t pos; const char *text; } Insert;
typedef struct { int blocks, parens; } Pending;

typedef struct {
    Insert *ins;  int nins, capins;
    Pending *pend; int npend, cappend;
} ShState;

static void add_insert (ShState *s, size_t pos, const char *text)
{
    if (s->nins == s->capins) {
        s->capins = s->capins ? s->capins * 2 : 64;
        s->ins = realloc (s->ins, sizeof (Insert) * (size_t) s->capins);
    }
    s->ins[s->nins].pos  = pos;
    s->ins[s->nins].text = text;
    s->nins++;
}

static void push_pending (ShState *s, int blocks, int parens)
{
    if (s->npend == s->cappend) {
        s->cappend = s->cappend ? s->cappend * 2 : 16;
        s->pend = realloc (s->pend, sizeof (Pending) * (size_t) s->cappend);
    }
    s->pend[s->npend].blocks = blocks;
    s->pend[s->npend].parens = parens;
    s->npend++;
}

static bool is_name_start (char c) { return isalpha ((unsigned char) c) || c == '_'; }
static bool is_name_char  (char c) { return isalnum ((unsigned char) c) || c == '_'; }

// A long bracket `[[`, `[=[`, ... at p: returns its level (number of '='),
// or -1 when p isn't one.
static int long_bracket_level (const char *p)
{
    if (p[0] != '[') return -1;
    int n = 0;
    while (p[1 + n] == '=') n++;
    return p[1 + n] == '[' ? n : -1;
}

// Skips a long string/comment body starting at its opening bracket.
static const char *skip_long (const char *p, int level)
{
    p += level + 2;
    while (*p) {
        if (*p == ']') {
            int n = 0;
            while (p[1 + n] == '=') n++;
            if (n == level && p[1 + n] == ']') return p + level + 2;
        }
        p++;
    }
    return p;
}

// Skips a quoted string starting at its quote.
static const char *skip_quoted (const char *p)
{
    char q = *p++;
    while (*p && *p != q && *p != '\n') {
        if (*p == '\\' && p[1]) p++;
        p++;
    }
    return *p == q ? p + 1 : p;
}

// From just after an opening '(' , returns the position of the matching ')'
// (or NULL).
static const char *match_paren (const char *p)
{
    int depth = 1;
    while (*p) {
        int lv;
        if (*p == '-' && p[1] == '-') {
            p += 2;
            if ((lv = long_bracket_level (p)) >= 0) p = skip_long (p, lv);
            else while (*p && *p != '\n') p++;
            continue;
        }
        if (*p == '"' || *p == '\'') { p = skip_quoted (p); continue; }
        if ((lv = long_bracket_level (p)) >= 0) { p = skip_long (p, lv); continue; }
        if (*p == '(') depth++;
        else if (*p == ')' && --depth == 0) return p;
        p++;
    }
    return NULL;
}

static bool word_at (const char *p, const char *w)
{
    size_t n = strlen (w);
    return strncmp (p, w, n) == 0 && !is_name_char (p[n]);
}

// After the condition's ')': does the next token on this line start the
// shorthand's body (true) or continue the condition / start `then` (false)?
static bool body_follows (const char *p)
{
    while (*p == ' ' || *p == '\t') p++;
    if (*p == '\0' || *p == '\n' || *p == '\r') return false;
    if (p[0] == '-' && p[1] == '-') return false;             // comment: body on later lines
    if (is_name_start (*p)) {
        static const char *cont[] = { "then", "do", "and", "or", NULL };
        for (int i = 0; cont[i]; i++) if (word_at (p, cont[i])) return false;
        return true;                                        // a statement: name, keyword
    }
    if (*p == '?') return true;                             // print shorthand
    if (*p == ';') return true;                             // empty statement
    return false;                                           // operator, bracket, string, number
}

char *pico8_expand_shorthand (const char *src)
{
    ShState s = { 0 };
    int blocks = 0, parens = 0, loop_do = 0;
    size_t eol_insert = (size_t) -1;    // where this line's `end`s go (before a comment)
    const char *p = src;

    while (*p) {
        int lv;
        char c = *p;

        if (c == '\n') {
            size_t at = eol_insert != (size_t) -1 ? eol_insert : (size_t) (p - src);
            while (s.npend > 0 &&
                   s.pend[s.npend - 1].blocks == blocks &&
                   s.pend[s.npend - 1].parens == parens) {
                add_insert (&s, at, " end");
                s.npend--;
            }
            eol_insert = (size_t) -1;
            p++;
            continue;
        }
        if (c == '-' && p[1] == '-') {
            if (eol_insert == (size_t) -1) eol_insert = (size_t) (p - src);
            p += 2;
            if ((lv = long_bracket_level (p)) >= 0) {
                // A long comment can span lines; the `end`s go before it,
                // at the end of the line it starts on only if it also ends
                // there. Simplest correct choice: before the comment.
                p = skip_long (p, lv);
                // text after a same-line long comment is code again
                const char *q = p;
                while (*q == ' ' || *q == '\t') q++;
                if (*q != '\n' && *q != '\0') eol_insert = (size_t) -1;
            } else {
                while (*p && *p != '\n') p++;
            }
            continue;
        }
        if (c == '"' || c == '\'') { p = skip_quoted (p); continue; }
        if ((lv = long_bracket_level (p)) >= 0) { p = skip_long (p, lv); continue; }
        if (c == '(' || c == '[' || c == '{') { parens++; p++; continue; }
        if (c == ')' || c == ']' || c == '}') { if (parens > 0) parens--; p++; continue; }
        if (isdigit ((unsigned char) c)) {
            while (is_name_char (*p) || *p == '.') p++;     // 0x1f.8, 1e3 ...
            continue;
        }
        if (!is_name_start (c)) { p++; continue; }

        // --- a name or keyword ---
        const char *w = p;
        while (is_name_char (*p)) p++;
        size_t wl = (size_t) (p - w);
        // `a.end`-style field names aren't keywords
        bool after_dot = (w > src && (w[-1] == '.' || w[-1] == ':'));
        if (after_dot) continue;

#define KW(k) (wl == sizeof (k) - 1 && strncmp (w, k, wl) == 0)
        if (KW ("if") || KW ("while")) {
            bool is_if = KW ("if");
            const char *q = p;
            while (*q == ' ' || *q == '\t') q++;
            if (*q == '(') {
                const char *close = match_paren (q + 1);
                if (close != NULL && body_follows (close + 1)) {
                    add_insert (&s, (size_t) (close + 1 - src), is_if ? " then " : " do ");
                    push_pending (&s, blocks, parens);
                    continue;                               // condition scans normally
                }
            }
            if (is_if) blocks++;
            else { blocks++; loop_do++; }
        } else if (KW ("for")) {
            blocks++; loop_do++;
        } else if (KW ("do")) {
            if (loop_do > 0) loop_do--; else blocks++;
        } else if (KW ("function") || KW ("repeat")) {
            blocks++;
        } else if (KW ("end") || KW ("until")) {
            // closes a block opened before an unfinished shorthand: that
            // shorthand's body ends here
            while (s.npend > 0 &&
                   s.pend[s.npend - 1].blocks == blocks &&
                   s.pend[s.npend - 1].parens == parens) {
                add_insert (&s, (size_t) (w - src), "end ");
                s.npend--;
            }
            if (blocks > 0) blocks--;
        }
#undef KW
    }
    // end of input: close whatever is still open
    while (s.npend > 0) { add_insert (&s, (size_t) (p - src), " end"); s.npend--; }

    size_t len = strlen (src), extra = 0;
    for (int i = 0; i < s.nins; i++) extra += strlen (s.ins[i].text);
    char *out = malloc (len + extra + 1);
    if (out == NULL) { free (s.ins); free (s.pend); return NULL; }
    // by position; several at one position keep their recording order
    for (int i = 1; i < s.nins; i++) {
        Insert t = s.ins[i];
        int j = i - 1;
        while (j >= 0 && s.ins[j].pos > t.pos) { s.ins[j + 1] = s.ins[j]; j--; }
        s.ins[j + 1] = t;
    }
    size_t from = 0; char *o = out;
    for (int i = 0; i < s.nins; i++) {
        size_t at = s.ins[i].pos;
        memcpy (o, src + from, at - from); o += at - from; from = at;
        size_t tl = strlen (s.ins[i].text);
        memcpy (o, s.ins[i].text, tl); o += tl;
    }
    memcpy (o, src + from, len - from); o += len - from;
    *o = '\0';
    free (s.ins); free (s.pend);
    return out;
}
