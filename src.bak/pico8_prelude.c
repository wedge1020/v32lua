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
} PreludeFunc;

static const PreludeFunc prelude[] = {
    { "split", "__p8_conv",
      "function split(s, sep, conv)\n"
      "  if sep == nil then sep = \",\" end\n"
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
      "end\n" },
    { "__p8_conv", NULL,
      "function __p8_conv(v, conv)\n"
      "  if conv ~= false then local x = tonumber(v) if x ~= nil then return x end end\n"
      "  return v\n"
      "end\n" },
    { "unpack", NULL,
      // up to 8 values (the calling convention has no return count)
      "function unpack(t, i)\n"
      "  if i == nil then i = 1 end\n"
      "  return t[i], t[i + 1], t[i + 2], t[i + 3], t[i + 4], t[i + 5], t[i + 6], t[i + 7]\n"
      "end\n" },
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
      "end\n" },
    { "tonum", NULL,
      "function tonum(v) return tonumber(v) end\n" },
    { "stat", NULL,
      // no system state to report; carts also use `stat` as a no-op function
      "function stat(n) return 0 end\n" },
    { "printh", NULL,
      "function printh(s) end\n" },
    { "ord", NULL,
      "function ord(s, i) if i == nil then i = 1 end return string.byte(s, i) end\n" },
    { "chr", NULL,
      "function chr(n) return string.char(n) end\n" },
    { NULL, NULL, NULL }
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

char *pico8_append_prelude (char *src)
{
    bool want[32] = { false };
    int  count = 0;
    for (int i = 0; prelude[i].name; i++) count++;

    for (int i = 0; i < count; i++) {
        if (prelude[i].name[0] != '_' && mentions (src, prelude[i].name) &&
            !defines (src, prelude[i].name)) {
            want[i] = true;
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
