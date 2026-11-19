#include "v32lua.h"
#include <ctype.h>

// ============================================================================
// PICO-8 prelude: builtins written in (plain) Lua
// ----------------------------------------------------------------------------
// PICO-8 functions that are easiest to express in Lua itself, or that carts
// use as VALUES (`(obj.type.init or stat)(obj)` needs a real function in a
// variable, not an intrinsic that only exists at call sites). The ones a
// PICO-8 program mentions, and doesn't define itself, are appended to the
// end of the source before parsing -- appended, so line numbers of the
// program's own code don't move. Only plain Lua here: this text is parsed
// with the program, so it must not depend on PICO-8-only syntax.
// ============================================================================

typedef struct {
    const char *name;
    const char *needs;      // another prelude function this one calls, or NULL
    const char *code;
    const char *trigger;    // also included when the source contains this text
} PreludeFunc;

// _ENV["rectfill"]: carts that look builtins up by name (a picture-drawing
// interpreter: `_ENV[modes[cmd]](unpack(args))`). Builtins are intrinsics,
// not globals, so these wrappers are; emit_env_table() lists each one under
// the builtin's own name.
#define P8ENV(name, params) \
    { "__p8env_" name, NULL, \
      "function __p8env_" name "(" params ") " name "(" params ") end\n", "_ENV[" }

static const PreludeFunc prelude[] = {
    { "split", "__p8_conv",
      "function split(s, sep, conv)\n"
      "  if sep == nil then sep = \",\" end\n"
      // the common case in one native pass (pico8.s __builtin_pico8_split1)
      "  if type(s) == \"string\" and type(sep) == \"string\" and #sep == 1 then\n"
      "    return __p8_split1(s, sep, conv)\n"
      "  end\n"
      "  local t, n, start, len = {}, 0, 1, #s\n"
      "  if sep == \"\" then\n"
      "    for i = 1, len do n = n + 1 t[n] = __p8_conv(sub(s, i, i), conv) end\n"
      "    return t\n"
      "  end\n"
      "  for i = 1, len do\n"
      "    if sub(s, i, i) == sep then\n"
      "      n = n + 1 t[n] = __p8_conv(sub(s, start, i - 1), conv) start = i + 1\n"
      "    end\n"
      "  end\n"
      "  n = n + 1 t[n] = __p8_conv(sub(s, start, len), conv)\n"
      "  return t\n"
      "end\n", NULL },
    { "__p8_conv", NULL,
      "function __p8_conv(v, conv)\n"
      "  if conv ~= false then local x = tonumber(v) if x ~= nil then return x end end\n"
      "  return v\n"
      "end\n", NULL },
    { "cursor", NULL,
      // cursor([x, y [, col]]): a real function, so the three previous
      // values can be returned; the state is the runtime's (pico8.s)
      "function cursor(x, y, col)\n"
      "  local px, py, pc = __p8_cursor_get(0), __p8_cursor_get(1), __p8_cursor_get(2)\n"
      "  __p8_cursor_set(x, y, col)\n"
      "  return px, py, pc\n"
      "end\n", NULL },
    { "unpack", NULL,
      // every value from t[i] to t[j] (a multi-value list, node/multivalue.c;
      // calls and constructors ending in unpack(...) spread it inline)
      "function unpack(t, i, j)\n"
      "  return __mv_unpack(t, i, j)\n"
      "end\n", NULL },
    { "tostr", NULL,
      "function tostr(v, hex)\n"
      "  if hex and type(v) == \"number\" then\n"
      "    local x = flr(v * 65536 + 0.5)\n"
      "    if x < 0 then x = x + 4294967296 end\n"
      "    local s, digits = \"\", \"0123456789abcdef\"\n"
      "    for k = 1, 8 do\n"
      "      local d = x % 16 x = flr(x / 16)\n"
      "      s = sub(digits, d + 1, d + 1) .. s\n"
      "      if k == 4 then s = \".\" .. s end\n"
      "    end\n"
      "    return \"0x\" .. s\n"
      "  end\n"
      "  if v == nil then return \"[nil]\" end\n"
      "  return tostring(v)\n"
      "end\n", NULL },
    { "tonum", NULL,
      "function tonum(v) return tonumber(v) end\n", NULL },
    { "stat", NULL,
      // The ids whose value is a string or nil (or a boolean with nothing
      // to report) are answered here; every number and the devkit mouse
      // (32-34, v32mouse.c) by __p8_stat -> pico8.s __builtin_pico8_stat.
      // A real function, so carts can also use `stat` as a value.
      "function stat(n)\n"
      "  if n == 4 or n == 6 or n == 31 then return \"\" end\n"
      "  if n == 100 or n == 101 then return nil end\n"
      "  if n == 30 or n == 110 then return false end\n"
      "  return __p8_stat(n)\n"
      "end\n", NULL },
    // all(t) as a VALUE: PICO-8's iterator function. `for v in all(t)` never
    // gets here -- node/loop.c lowers it inline without allocating (this
    // closure costs a heap block per call, and nothing is ever freed) -- see
    // all_needs_function() below for when the prelude includes this at all.
    { "all", NULL,
      "function all(c)\n"
      "  local i, prev = 1, nil\n"
      "  if c == nil then return function() return nil end end\n"
      "  return function()\n"
      "    if c[i] == prev then i = i + 1 end\n"
      "    while c[i] == nil and i <= #c do i = i + 1 end\n"
      "    prev = c[i]\n"
      "    return prev\n"
      "  end\n"
      "end\n", NULL },
    { "printh", NULL,
      "function printh(s) end\n", NULL },
    { "ord", NULL,
      "function ord(s, i) if i == nil then i = 1 end return string.byte(s, i) end\n", NULL },
    { "chr", NULL,
      "function chr(n) return string.char(n) end\n", NULL },
    // Function forms of the bitwise operators (node/bitops.c): same 16.16
    // results as the operators, and usable as values.
    { "band", NULL, "function band(a, b) return a & b end\n", NULL },
    { "bor",  NULL, "function bor(a, b) return a | b end\n", NULL },
    { "bxor", NULL, "function bxor(a, b) return a ^^ b end\n", NULL },
    { "bnot", NULL, "function bnot(a) return ~a end\n", NULL },
    { "shl",  NULL, "function shl(a, n) return a << n end\n", NULL },
    { "shr",  NULL, "function shr(a, n) return a >> n end\n", NULL },
    { "lshr", NULL, "function lshr(a, n) return a >>> n end\n", NULL },
    { "rotl", NULL, "function rotl(a, n) return a <<> n end\n", NULL },
    { "rotr", NULL, "function rotr(a, n) return a >>< n end\n", NULL },
    // peek(a, n) / peek2(a, n) / peek4(a, n): n values, up to 8 (the
    // calling convention has no return count, as for unpack()); the
    // intrinsics handle the single-value form, see pico8mem.c
    { "__p8_peekn", NULL,
      "function __p8_peekn(a, n, w)\n"
      "  local v = {}\n"
      "  if n > 8 then n = 8 end\n"
      "  for i = 1, n do\n"
      "    if w == 1 then v[i] = peek(a) elseif w == 2 then v[i] = peek2(a) else v[i] = peek4(a) end\n"
      "    a = a + w\n"
      "  end\n"
      "  return v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8]\n"
      "end\n", NULL },
    // deli(t [, i]): removes t[i] (default: the last), closing the gap, and
    // returns it
    { "deli", NULL,
      "function deli(t, i)\n"
      "  local n = #t\n"
      "  if i == nil then i = n end\n"
      "  if i < 1 or i > n then return nil end\n"
      "  local v = t[i]\n"
      "  for k = i, n - 1 do t[k] = t[k + 1] end\n"
      "  t[n] = nil\n"
      "  return v\n"
      "end\n", NULL },
    // assert(v [, msg]): as PICO-8, a failure stops the cart with the
    // message on screen
    { "assert", NULL,
      "function assert(v, msg)\n"
      "  if not v then\n"
      "    cls(0)\n"
      "    print(\"assertion failed\", 0, 0, 8)\n"
      "    if msg ~= nil then print(tostring(msg), 0, 8, 7) end\n"
      "    while true do flip() end\n"
      "  end\n"
      "  return v\n"
      "end\n", NULL },
    // menuitem(index [, label, callback]): PICO-8's custom pause-menu
    // entries, slots 1-5. The first call registers __p8_pausemenu as the
    // pause screen (pico8.s __builtin_pico8_pause_check runs it on Start).
    { "menuitem", "__p8_pausemenu",
      // (the table is made on first use: the prelude runs after the cart's
      // own top-level code, which may already call menuitem())
      "function menuitem(i, label, cb)\n"
      "  if i == nil or i < 1 or i > 5 then return end\n"
      "  if __p8_menuitems == nil then __p8_menuitems = {} end\n"
      "  if label == nil then __p8_menuitems[i] = nil\n"
      "  else __p8_menuitems[i] = {label, cb} end\n"
      "  __p8_menu_hook(__p8_pausemenu)\n"
      "end\n", NULL },
    // The pause menu: continue, the cart's items, reset cart. Up/down
    // choose; O/X pick (an item's callback gets 32, and the menu stays open
    // only if it returns true); left/right on an item call it with 1 / 2
    // and keep the menu open; Start closes it. Runs its own frames (a raw
    // WAIT -- flip() would re-enter the pause check).
    { "__p8_pausemenu", NULL,
      "function __p8_pausemenu()\n"
      "  local items = {{\"continue\"}}\n"
      "  for i = 1, 5 do\n"
      "    local m = __p8_menuitems[i]\n"
      "    if m ~= nil then items[#items + 1] = {m[1], m[2]} end\n"
      "  end\n"
      "  items[#items + 1] = {\"reset cart\", nil, true}\n"
      "  local cx, cy, pen = peek2(0x5f28), peek2(0x5f2a), peek(0x5f25)\n"
      "  camera()\n"
      "  local sel, prev = 1, 63\n"
      "  while true do\n"
      "    local h = #items * 8 + 7\n"
      "    local y0 = 64 - flr(h / 2)\n"
      "    rectfill(20, y0, 107, y0 + h, 0)\n"
      "    rect(20, y0, 107, y0 + h, 7)\n"
      "    for k = 1, #items do\n"
      "      local y = y0 + 4 + (k - 1) * 8\n"
      "      if k == sel then\n"
      "        print(\">\", 25, y, 7)\n"
      "        print(items[k][1], 31, y, 7)\n"
      "      else\n"
      "        print(items[k][1], 31, y, 6)\n"
      "      end\n"
      "    end\n"
      "    __rawasm__(\"WAIT\")\n"
      "    if __p8_start_pressed() then break end\n"
      "    local b = btn()\n"
      "    local p = b & ~prev\n"
      "    prev = b\n"
      "    if p & 4 ~= 0 then sel = sel - 1 if sel < 1 then sel = #items end end\n"
      "    if p & 8 ~= 0 then sel = sel + 1 if sel > #items then sel = 1 end end\n"
      "    local it = items[sel]\n"
      "    if it[2] ~= nil and p & 3 ~= 0 then it[2](p & 3) end\n"
      "    if p & 48 ~= 0 then\n"
      "      if it[3] then run() end\n"
      "      if it[2] == nil then break end\n"
      "      if not it[2](32) then break end\n"
      "    end\n"
      "  end\n"
      "  camera(cx, cy)\n"
      "  color(pen)\n"
      "end\n", NULL },
    // poke(a, unpack(t)) with a run-time table -- see core.c
    { "__p8_pokeu", NULL,
      "function __p8_pokeu(w, a, t)\n"
      "  for i = 1, #t do\n"
      "    if w == 1 then poke(a, t[i]) elseif w == 2 then poke2(a, t[i]) else poke4(a, t[i]) end\n"
      "    a = a + w\n"
      "  end\n"
      "end\n", "unpack" },
    // oval(x0, y0, x1, y1 [, col]) / ovalfill: the ellipse inscribed in the
    // box, one horizontal span per row
    { "__p8_oval", NULL,
      "function __p8_oval(x0, y0, x1, y1, col, fill)\n"
      "  x0 = flr(x0) y0 = flr(y0) x1 = flr(x1) y1 = flr(y1)\n"
      "  if x0 > x1 then x0, x1 = x1, x0 end\n"
      "  if y0 > y1 then y0, y1 = y1, y0 end\n"
      "  local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2\n"
      "  local rx, ry = (x1 - x0) / 2 + 0.5, (y1 - y0) / 2 + 0.5\n"
      "  local a = {}\n"
      "  for y = y0, y1 do\n"
      "    local d = (y - cy) / ry\n"
      "    local w = rx * sqrt(1 - d * d)\n"
      "    a[y - y0] = flr(cx - w + 0.5)\n"
      "  end\n"
      "  for y = y0, y1 do\n"
      "    local xa = a[y - y0]\n"
      "    local xb = x0 + x1 - xa\n"
      "    if fill then rectfill(xa, y, xb, y, col)\n"
      "    else\n"
      "      local up, dn = a[y - y0 - 1], a[y - y0 + 1]\n"
      "      if up == nil then up = xb + 1 end\n"
      "      if dn == nil then dn = xb + 1 end\n"
      "      local la = min(up, dn) - 1\n"
      "      if la < xa then la = xa end\n"
      "      if la > xb then la = xb end\n"
      "      rectfill(xa, y, la, y, col)\n"
      "      rectfill(x0 + x1 - la, y, xb, y, col)\n"
      "    end\n"
      "  end\n"
      "end\n", NULL },
    { "oval", "__p8_oval",
      "function oval(x0, y0, x1, y1, col) __p8_oval(x0, y0, x1, y1, col, false) end\n", NULL },
    { "ovalfill", "__p8_oval",
      "function ovalfill(x0, y0, x1, y1, col) __p8_oval(x0, y0, x1, y1, col, true) end\n", NULL },
    P8ENV ("rect",     "a, b, c, d, e"),
    P8ENV ("rectfill", "a, b, c, d, e"),
    P8ENV ("line",     "a, b, c, d, e"),
    P8ENV ("pset",     "a, b, c"),
    P8ENV ("circ",     "a, b, c, d"),
    P8ENV ("circfill", "a, b, c, d"),
    P8ENV ("spr",      "a, b, c, d, e, f, g"),
    P8ENV ("sspr",     "a, b, c, d, e, f, g, h, i, j"),
    P8ENV ("map",      "a, b, c, d, e, f, g"),
    P8ENV ("print",    "a, b, c, d"),
    P8ENV ("pal",      "a, b, c"),
    P8ENV ("palt",     "a, b"),
    P8ENV ("clip",     "a, b, c, d, e"),
    P8ENV ("fillp",    "a"),
    P8ENV ("camera",   "a, b"),
    P8ENV ("color",    "a"),
    P8ENV ("cls",      "a"),
    { "peek",  "__p8_peekn", "", NULL },
    { "peek2", "__p8_peekn", "", NULL },
    { "peek4", "__p8_peekn", "", NULL },
    { NULL, NULL, NULL, NULL }
};


// stat() when the cart reads the devkit keyboard (stat(30) / stat(31), or it
// enables devkit input with poke(0x5f2d, ...)): the same function plus the
// typed-character queue, from the v32kbd layer (kbd.read()). Included only
// then, because mentioning kbd.* turns the keyboard decoder on, and with it
// a device poll on every frame. One character of lookahead is kept in
// __p8_kc so stat(30) can answer without consuming it.
static const char *stat_keys_code =
      "local __p8_kc\n"
      "function __p8_kchar()\n"
      "  while __p8_kc == nil do\n"
      "    local c = kbd.read()\n"
      "    if c == nil then return nil end\n"
      "    local glyph = c >= 256\n"
      "    if glyph then c = c - 256 end\n"
      // typed text: printable characters, and the control characters a text
      // box needs (backspace, tab, enter). Arrows, F-keys, shifts... are keys,
      // not characters.
      "    if glyph or (c >= 32 and c < 127) or c == 8 or c == 9 or c == 13 then\n"
      "      __p8_kc = string.char(c)\n"
      "    end\n"
      "  end\n"
      "  return __p8_kc\n"
      "end\n"
      "function stat(n)\n"
      "  if n == 30 then return __p8_kchar() ~= nil end\n"
      "  if n == 31 then\n"
      "    local c = __p8_kchar()\n"
      "    __p8_kc = nil\n"
      "    if c == nil then return \"\" end\n"
      "    return c\n"
      "  end\n"
      "  if n == 4 or n == 6 then return \"\" end\n"
      "  if n == 100 or n == 101 then return nil end\n"
      "  if n == 110 then return false end\n"
      "  return __p8_stat(n)\n"
      "end\n";

// Does the cart read the keyboard? (stat(30), stat(31), poke(0x5f2d...))
static bool stat_keys_wanted (const char *src)
{
    for (const char *p = strstr (src, "stat"); p != NULL; p = strstr (p + 1, "stat")) {
        if (p > src && (isalnum ((unsigned char) p[-1]) || p[-1] == '_' || p[-1] == '.')) continue;
        const char *a = p + 4;
        while (*a == ' ' || *a == '\t') a++;
        if (*a != '(') continue;
        a++;
        while (*a == ' ' || *a == '\t') a++;
        if (a[0] == '3' && (a[1] == '0' || a[1] == '1') &&
            !isalnum ((unsigned char) a[2]) && a[2] != '.') return true;
    }
    return strcasestr (src, "0x5f2d") != NULL;
}

// Is `name` used as a whole identifier in src?
static bool mentions (const char *src, const char *name)
{
    size_t n = strlen (name);
    for (const char *p = strstr (src, name); p != NULL; p = strstr (p + 1, name)) {
        bool left  = (p == src) || !(isalnum ((unsigned char) p[-1]) || p[-1] == '_');
        bool right = !(isalnum ((unsigned char) p[n]) || p[n] == '_');
        if (left && right) return true;
    }
    return false;
}

// Does the program need the prelude's all() function? `for v in all(t) do`
// is lowered inline by the compiler (node/loop.c) and needs none; every
// other use of the word all in code -- `local it = all(t)`, `f = all`,
// `for v in all(t), x do` -- does. Occurrences after a `--` on their line
// are comments ("all" is a common word in them), not code.
static bool all_needs_function (const char *src)
{
    for (const char *p = strstr (src, "all"); p != NULL; p = strstr (p + 1, "all")) {
        bool left  = (p == src) || !(isalnum ((unsigned char) p[-1]) || p[-1] == '_');
        bool right = !(isalnum ((unsigned char) p[3]) || p[3] == '_');
        if (!left || !right) continue;

        const char *ls = p;                       // start of the line
        while (ls > src && ls[-1] != '\n') ls--;
        bool comment = false;
        for (const char *c = ls; c + 1 < p; c++)
            if (c[0] == '-' && c[1] == '-') { comment = true; break; }
        if (comment) continue;

        const char *q = p;                        // is the word preceded by `in`?
        while (q > src && (q[-1] == ' ' || q[-1] == '\t')) q--;
        bool after_in = (q - src >= 2) && q[-2] == 'i' && q[-1] == 'n' &&
                        (q - src == 2 || !(isalnum ((unsigned char) q[-3]) || q[-3] == '_'));
        if (!after_in) return true;

        const char *a = p + 3;                    // and followed by `(` or `{`
        while (*a == ' ' || *a == '\t') a++;
        if (*a != '(' && *a != '{') return true;
        char open = *a, close = (open == '(') ? ')' : '}';
        int depth = 0;
        const char *c = a;
        for (; *c != '\0'; c++) {
            if (*c == open) depth++;
            else if (*c == close && --depth == 0) { c++; break; }
        }
        while (*c == ' ' || *c == '\t' || *c == '\r' || *c == '\n') c++;
        if (*c == ',') return true;               // more iterator expressions follow
    }
    return false;
}

// Does src define `name` itself (function name / name = function)?
static bool defines (const char *src, const char *name)
{
    char pat[128];
    snprintf (pat, sizeof (pat), "function %s(", name);
    if (strstr (src, pat)) return true;
    snprintf (pat, sizeof (pat), "function %s (", name);
    return strstr (src, pat) != NULL;
}

// Which prelude names the program uses as the built-in (mentioned, not
// defined by the program itself) -- set by pico8_append_prelude().
static bool prelude_builtin[96];

bool pico8_prelude_builtin (const char *name)
{
    for (int i = 0; prelude[i].name && i < 96; i++)
        if (strcmp (prelude[i].name, name) == 0) return prelude_builtin[i];
    return false;
}

char *pico8_append_prelude (char *src)
{
    bool want[96] = { false };
    int  count = 0;
    for (int i = 0; prelude[i].name; i++) count++;

    for (int i = 0; i < count; i++) {
        bool used = (prelude[i].name[0] != '_' && mentions (src, prelude[i].name)) ||
                    (prelude[i].trigger != NULL && strstr (src, prelude[i].trigger) != NULL);
        if (strcmp (prelude[i].name, "all") == 0) used = all_needs_function (src);
        if (used && !defines (src, prelude[i].name)) {
            want[i] = true;
            prelude_builtin[i] = true;
            for (int j = 0; j < count; j++)
                if (prelude[i].needs && strcmp (prelude[j].name, prelude[i].needs) == 0)
                    want[j] = true;
        }
    }

    // the keyboard variant of stat() (see stat_keys_code)
    int stat_idx = -1;
    for (int i = 0; i < count; i++) if (strcmp (prelude[i].name, "stat") == 0) stat_idx = i;
    bool stat_keys = stat_idx >= 0 && want[stat_idx] && stat_keys_wanted (src);

    size_t extra = 64;
    for (int i = 0; i < count; i++) if (want[i]) extra += strlen (prelude[i].code) + 1;
    if (stat_keys) extra += strlen (stat_keys_code) + 1;
    if (extra == 64) return src;

    size_t len = strlen (src);
    char *out = malloc (len + extra);
    if (out == NULL) return src;
    memcpy (out, src, len);
    char *o = out + len;
    o += sprintf (o, "\n-- v32lua PICO-8 prelude\n");
    for (int i = 0; i < count; i++) {
        if (want[i]) o += sprintf (o, "%s", (stat_keys && i == stat_idx) ? stat_keys_code : prelude[i].code);
    }
    *o = '\0';
    free (src);
    return out;
}

// ============================================================================
// TIC-80 prelude: tri() in Lua
// ----------------------------------------------------------------------------
// TIC-80's tri() (core/draw.c drawTri) walks the clipped bounding box and
// writes every pixel whose three barycentric weights are all >= 0. Each
// weight is linear in x, so per row the covered pixels are ONE run: the
// intersection of three half-lines. This computes that run and draws it
// with a single rect() -- the same pixels as the pixel walk, one GPU
// region per row instead of one test per pixel.
// ============================================================================
static const char tic80_tri_code[] =
    "function tri(x1, y1, x2, y2, x3, y3, c)\n"
    "  local area = (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1)\n"
    "  if math.floor(area) == 0 then return end\n"
    "  if area < 0 then\n"
    "    local tx, ty = x2, y2\n"
    "    x2, y2, x3, y3 = x3, y3, tx, ty\n"
    "    area = -area\n"
    "  end\n"
    "  local x0 = math.max(math.floor(math.min(x1, x2, x3)), 0)\n"
    "  local y0 = math.max(math.floor(math.min(y1, y2, y3)), 0)\n"
    "  local xe = math.min(math.ceil(math.max(x1, x2, x3)), 240)\n"
    "  local ye = math.min(math.ceil(math.max(y1, y2, y3)), 136)\n"
    "  if x0 >= xe or y0 >= ye then return end\n"
    "  local px, py = x0 + 0.49999988, y0 + 0.49999988\n"
    "  local inv = 1 / area\n"
    // weight i = b_i + ax_i * k + ay_i * row   (k = pixel column from x0,
    // row = pixel row from y0). The weight is >= 0 for k >= -(b + ay*row)/ax
    // when ax > 0, k <= that when ax < 0: a bound  c + m * row  on k.
    "  local ax1, ay1 = (y2 - y3) * inv, (x3 - x2) * inv\n"
    "  local b1 = ((x3 - x2) * (py - y2) - (y3 - y2) * (px - x2)) * inv\n"
    "  local ax2, ay2 = (y3 - y1) * inv, (x1 - x3) * inv\n"
    "  local b2 = ((x1 - x3) * (py - y3) - (y1 - y3) * (px - x3)) * inv\n"
    "  local ax3, ay3 = (y1 - y2) * inv, (x2 - x1) * inv\n"
    "  local b3 = ((x2 - x1) * (py - y1) - (y2 - y1) * (px - x1)) * inv\n"
    "  local last, r0, r1 = xe - x0 - 1, 0, ye - y0 - 1\n"
    "  local k1, k2, k3, c1, c2, c3, m1, m2, m3 = 0, 0, 0, 0, 0, 0, 0, 0, 0\n"
    // a flat edge (ax == 0) only limits the rows
    "  if ax1 > 0 then k1 = 1 elseif ax1 < 0 then k1 = 2\n"
    "  elseif ay1 > 0 then r0 = math.max(r0, math.ceil(-b1 / ay1))\n"
    "  elseif ay1 < 0 then r1 = math.min(r1, math.floor(-b1 / ay1))\n"
    "  elseif b1 < 0 then return end\n"
    "  if k1 ~= 0 then c1, m1 = -b1 / ax1, -ay1 / ax1 end\n"
    "  if ax2 > 0 then k2 = 1 elseif ax2 < 0 then k2 = 2\n"
    "  elseif ay2 > 0 then r0 = math.max(r0, math.ceil(-b2 / ay2))\n"
    "  elseif ay2 < 0 then r1 = math.min(r1, math.floor(-b2 / ay2))\n"
    "  elseif b2 < 0 then return end\n"
    "  if k2 ~= 0 then c2, m2 = -b2 / ax2, -ay2 / ax2 end\n"
    "  if ax3 > 0 then k3 = 1 elseif ax3 < 0 then k3 = 2\n"
    "  elseif ay3 > 0 then r0 = math.max(r0, math.ceil(-b3 / ay3))\n"
    "  elseif ay3 < 0 then r1 = math.min(r1, math.floor(-b3 / ay3))\n"
    "  elseif b3 < 0 then return end\n"
    "  if k3 ~= 0 then c3, m3 = -b3 / ax3, -ay3 / ax3 end\n"
    "  for row = r0, r1 do\n"
    "    local lo, hi = 0, last\n"
    "    if k1 == 1 then lo = math.max(lo, math.ceil(c1 + m1 * row))\n"
    "    elseif k1 == 2 then hi = math.min(hi, math.floor(c1 + m1 * row)) end\n"
    "    if k2 == 1 then lo = math.max(lo, math.ceil(c2 + m2 * row))\n"
    "    elseif k2 == 2 then hi = math.min(hi, math.floor(c2 + m2 * row)) end\n"
    "    if k3 == 1 then lo = math.max(lo, math.ceil(c3 + m3 * row))\n"
    "    elseif k3 == 2 then hi = math.min(hi, math.floor(c3 + m3 * row)) end\n"
    "    if hi >= lo then rect(x0 + lo, y0 + row, hi - lo + 1, 1, c) end\n"
    "  end\n"
    "end\n";

// Appends tri() when a TIC-80 program calls it and doesn't define it.
char *tic80_append_prelude (char *src)
{
    if (!mentions (src, "tri") || defines (src, "tri")) return src;
    size_t len = strlen (src);
    char *out = malloc (len + sizeof (tic80_tri_code) + 40);
    if (out == NULL) return src;
    memcpy (out, src, len);
    sprintf (out + len, "\n-- v32lua TIC-80 prelude\n%s", tic80_tri_code);
    free (src);
    return out;
}
