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
    { "unpack", NULL,
      // up to 8 values (the calling convention has no return count)
      "function unpack(t, i)\n"
      "  if i == nil then i = 1 end\n"
      "  return t[i], t[i + 1], t[i + 2], t[i + 3], t[i + 4], t[i + 5], t[i + 6], t[i + 7]\n"
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
      // no system state to report; carts also use `stat` as a no-op function
      "function stat(n) return 0 end\n", NULL },
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
        if (used && !defines (src, prelude[i].name)) {
            want[i] = true;
            prelude_builtin[i] = true;
            for (int j = 0; j < count; j++)
                if (prelude[i].needs && strcmp (prelude[j].name, prelude[i].needs) == 0)
                    want[j] = true;
        }
    }

    size_t extra = 64;
    for (int i = 0; i < count; i++) if (want[i]) extra += strlen (prelude[i].code) + 1;
    if (extra == 64) return src;

    size_t len = strlen (src);
    char *out = malloc (len + extra);
    if (out == NULL) return src;
    memcpy (out, src, len);
    char *o = out + len;
    o += sprintf (o, "\n-- v32lua PICO-8 prelude\n");
    for (int i = 0; i < count; i++) {
        if (want[i]) o += sprintf (o, "%s", prelude[i].code);
    }
    *o = '\0';
    free (src);
    return out;
}
