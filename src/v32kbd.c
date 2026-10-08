// ============================================================================
// v32kbd.c -- keyboard support through a v32kbd device (key(), keyp(), kbd.*)
// ----------------------------------------------------------------------------
// A v32kbd device is a USB keyboard that the console sees as an ordinary
// gamepad: its 11 controls carry one key event per frame (see the v32kbd
// README). The runtime side is two layers, mirroring the C library split:
//
//   runtime/v32io.s   __v32io_read: every control of one gamepad packed
//                     into one word (bit 0 Left ... bit 10 R). Shared by
//                     any decoder of a gamepad-tunnelled device (v32kbd
//                     now; v32mouse later).
//   runtime/v32kbd.s  the decoder: strobe tracking, held keys, the event
//                     queue, shift/caps lock, and the Lua-facing builtins.
//
// Lua surface:
//   key([k])                     -- is key k held (any key, without k)
//   keyp([k [, hold, period]])   -- was k pressed this frame (+ autorepeat)
//   kbd.read()                   -- next typed character (number) or nil
//   kbd.event()                  -- next event: +code press, -code release, nil
//   kbd.port([n])                -- gamepad port of the keyboard (get / set)
//   kbd.capslock()               -- caps lock state
//   kbd.connected()              -- is a device plugged in that port
//   kbd.clear()                  -- drop unread events
//
// In native mode k is a v32kbd key code, or a string literal naming a key
// ("a", "enter", "f1", "shift", ...) folded here at compile time. In TIC-80
// mode key()/keyp() take TIC-80's own key codes (1-94), translated by a
// table in v32kbd.s.
//
// The device holds each event until the next one, so it must be read on
// every frame: __v32kbd_update runs lazily from every builtin (once per
// frame), the native game_loop()/TIC-80 TIC() drivers call it before every
// frame, and system.wait()/ioports.gpu.sync() call __v32kbd_frame_end just
// before their WAIT. All of that is only emitted when the source uses the
// keyboard (v32kbd_prescan), since the hooks precede the calls in codegen.
// ============================================================================

#include "v32lua.h"

bool v32kbd_wanted       = false;
int  v32kbd_default_port = V32LUA_DEFAULT_KEYBOARD_PORT;
bool g_cli_keyboard_set  = false;
static int v32kbd_ram_base = -1;

// RAM layout (words from v32kbd_ram_base)
#define KBD_OFF_PORT    0      // gamepad port of the keyboard (int 0-3)
#define KBD_OFF_STROBE  1      // last strobe side seen (0 none, 1 left, 2 right)
#define KBD_OFF_POLLED  2      // frame of the last poll (-1: none yet)
#define KBD_OFF_CAPS    3      // caps lock (0 / 1)
#define KBD_OFF_HELD    4      // number of keys held
#define KBD_OFF_ANYP    5      // frame on which the last press is visible
#define KBD_OFF_QHEAD   6      // event queue: index of the oldest entry
#define KBD_OFF_QCOUNT  7      // event queue: entries waiting
#define KBD_OFF_DOWN    8      // 128 words: frame each key went down, -1 up
#define KBD_OFF_QUEUE   (KBD_OFF_DOWN + 128)    // 64 words: the event queue
#define KBD_RAM_WORDS   (KBD_OFF_QUEUE + V32KBD_QUEUE_SIZE)

// ----------------------------------------------------------------------------
// Prescan: does the source use the keyboard? key / keyp called (followed by
// "(", a string or a table constructor), or the kbd.* namespace.
// ----------------------------------------------------------------------------
static bool ident_char (char c) { return isalnum ((unsigned char) c) || c == '_'; }

// Length of the long bracket opening at p ("[[", "[==[" ...), 0 if none;
// *level gets its number of '='.
static int long_bracket (const char *p, int *level)
{
    if (p[0] != '[') return 0;
    int n = 1;
    while (p[n] == '=') n++;
    if (p[n] != '[') return 0;
    *level = n - 1;
    return n + 1;
}

// Skips past the long bracket closing "]" + level '=' + "]".
static const char *skip_long (const char *p, int level)
{
    for (; *p; p++) {
        if (*p != ']') continue;
        int n = 1;
        while (p[n] == '=') n++;
        if (n - 1 == level && p[n] == ']') return p + n + 1;
    }
    return p;
}

// Does the source call any of the names (key, keyp: followed by "(", a
// string or a table constructor), or use kbd.<field>? Comments and the
// insides of strings are skipped -- "key" is a common word in both.
static bool source_uses_keyboard (const char *src, bool key_calls)
{
    const char *p = src;
    while (*p) {
        int level, open;
        if (p[0] == '-' && p[1] == '-') {                       // comment
            p += 2;
            if ((open = long_bracket (p, &level)) > 0) p = skip_long (p + open, level);
            else while (*p && *p != '\n') p++;
            continue;
        }
        if ((open = long_bracket (p, &level)) > 0) {            // [[string]]
            p = skip_long (p + open, level);
            continue;
        }
        if (*p == '"' || *p == '\'') {                         // "string"
            char q = *p++;
            while (*p && *p != q && *p != '\n') {
                if (*p == '\\' && p[1]) p++;
                p++;
            }
            if (*p == q) p++;
            continue;
        }
        if (ident_char (*p) && !isdigit ((unsigned char) *p)) {
            const char *b = p;
            while (ident_char (*p)) p++;
            size_t n = (size_t) (p - b);
            bool member = b > src && (b[-1] == '.' || b[-1] == ':');
            const char *q = p;
            while (*q == ' ' || *q == '\t') q++;
            if (!member && n == 3 && strncmp (b, "kbd", 3) == 0 && *q == '.') return true;
            if (!member && key_calls &&
                ((n == 3 && strncmp (b, "key", 3) == 0) || (n == 4 && strncmp (b, "keyp", 4) == 0)) &&
                (*q == '(' || *q == '"' || *q == '\'' || *q == '{' ||
                 (*q == '[' && (q[1] == '[' || q[1] == '='))))
                return true;
            continue;
        }
        p++;
    }
    return false;
}

void v32kbd_prescan (const char *src)
{
    if (src == NULL) return;
    // key()/keyp() are intrinsics in native and TIC-80 mode; kbd.* in all
    v32kbd_wanted = source_uses_keyboard (src, !runtime_req.needs_pico8);
}

// ----------------------------------------------------------------------------
// RAM and %defines (from emit_variable_map(), after codegen). Returns the
// number of lines printed.
// ----------------------------------------------------------------------------
int v32kbd_emit_defines (FILE *f)
{
    if (!v32kbd_wanted) return 0;
    v32kbd_ram_base  = next_ram_address;
    next_ram_address = next_ram_address + KBD_RAM_WORDS;
    fprintf (f, "%%define  V32KBD_DEFAULT_PORT      %d\n", v32kbd_default_port);
    fprintf (f, "%%define  V32KBD_QUEUE_SIZE        %d\n", V32KBD_QUEUE_SIZE);
    fprintf (f, "%%define  V32KBD_PORT              0x%.8X\n", v32kbd_ram_base + KBD_OFF_PORT);
    fprintf (f, "%%define  V32KBD_STROBE            0x%.8X\n", v32kbd_ram_base + KBD_OFF_STROBE);
    fprintf (f, "%%define  V32KBD_POLLED            0x%.8X\n", v32kbd_ram_base + KBD_OFF_POLLED);
    fprintf (f, "%%define  V32KBD_CAPS              0x%.8X\n", v32kbd_ram_base + KBD_OFF_CAPS);
    fprintf (f, "%%define  V32KBD_HELD              0x%.8X\n", v32kbd_ram_base + KBD_OFF_HELD);
    fprintf (f, "%%define  V32KBD_ANYP              0x%.8X\n", v32kbd_ram_base + KBD_OFF_ANYP);
    fprintf (f, "%%define  V32KBD_QHEAD             0x%.8X\n", v32kbd_ram_base + KBD_OFF_QHEAD);
    fprintf (f, "%%define  V32KBD_QCOUNT            0x%.8X\n", v32kbd_ram_base + KBD_OFF_QCOUNT);
    fprintf (f, "%%define  V32KBD_DOWN              0x%.8X\n", v32kbd_ram_base + KBD_OFF_DOWN);
    fprintf (f, "%%define  V32KBD_QUEUE             0x%.8X\n", v32kbd_ram_base + KBD_OFF_QUEUE);
    return 12;
}

// Startup (generate_global_setup): state reset, strobe baseline.
void v32kbd_emit_setup (void)
{
    if (!v32kbd_wanted) return;
    emit_asm ("CALL __v32kbd_init ; v32kbd keyboard: state, strobe baseline\n");
}

// Before a WAIT in program code (system.wait(), ioports.gpu.sync()):
// events read here become visible on the next frame. Preserves every
// register, since the WAIT it precedes is inline code.
void v32kbd_emit_frame_end_hook (void)
{
    if (!v32kbd_wanted) return;
    emit_asm ("CALL __v32kbd_frame_end ; v32kbd: read the keyboard every frame\n");
}

// At the top of a frame in the game_loop()/TIC() drivers.
void v32kbd_emit_frame_start_hook (void)
{
    if (!v32kbd_wanted) return;
    emit_asm ("CALL __v32kbd_update ; v32kbd: read the keyboard every frame\n");
}

// ----------------------------------------------------------------------------
// Native key names -> key spec (compile time)
// ----------------------------------------------------------------------------
// A spec is what the runtime takes: 1-127 a v32kbd key code, 128-131 a
// "either side" modifier (shift, ctrl, alt, gui -- see __v32kbd_virtual).
static const struct { const char *name; int spec; } v32kbd_names[] = {
    { "up", 1 }, { "down", 2 }, { "left", 3 }, { "right", 4 },
    { "capslock", 5 }, { "lshift", 6 }, { "rshift", 7 }, { "backspace", 8 },
    { "tab", 9 }, { "lctrl", 10 }, { "rctrl", 11 }, { "lalt", 12 },
    { "enter", 13 }, { "return", 13 },
    { "f1", 14 }, { "f2", 15 }, { "f3", 16 }, { "f4", 17 }, { "f5", 18 }, { "f6", 19 },
    { "f7", 20 }, { "f8", 21 }, { "f9", 22 }, { "f10", 23 }, { "f11", 24 }, { "f12", 25 },
    { "ralt", 26 }, { "escape", 27 }, { "esc", 27 }, { "lgui", 28 }, { "rgui", 29 },
    { "space", 32 }, { "delete", 127 }, { "del", 127 },
    { "shift", 128 }, { "ctrl", 129 }, { "alt", 130 }, { "gui", 131 },
    { NULL, 0 }
};

// The shifted character of each key (US layout) -> the key itself, so
// key("!") is the 1 key and key("A") the a key.
static const char *shifted_from = "!@#$%^&*()_+{}|:\"<>?~";
static const char *shifted_to   = "1234567890-=[]\\;',./`";

static int v32kbd_name_spec (const char *s)
{
    size_t n = strlen (s);
    if (n == 1) {
        unsigned char c = (unsigned char) s[0];
        if (c >= 'A' && c <= 'Z') return c + 32;
        const char *p = strchr (shifted_from, c);
        if (p != NULL && c != '\0') return (unsigned char) shifted_to[p - shifted_from];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
            (c != '\0' && strchr (" `-=[]\\;',./", c) != NULL)) return c;
        if (c == '\t') return 9;
        if (c == '\n' || c == '\r') return 13;
        if (c == 8)    return 8;
        if (c == 27)   return 27;
        return -1;
    }
    for (int i = 0; v32kbd_names[i].name != NULL; i++)
        if (strcasecmp (s, v32kbd_names[i].name) == 0) return v32kbd_names[i].spec;
    return -1;
}

static bool v32kbd_require (ASTNode *node, const char *what)
{
    if (v32kbd_wanted) return true;
    // v32kbd_prescan() decides from the source text; a call it can't see
    // (built by some other route) can't get the per-frame hooks
    compiler_error (ERR_INTERNAL, node->line_number,
        "%s: keyboard support was not enabled for this program (call it as %s(...))",
        what, what);
    return false;
}

// Pushes the key spec argument (or nil for "any key").
static bool v32kbd_push_spec (ASTNode *arg, const char *func_name, bool tic80, int line)
{
    if (arg == NULL || arg->type == NODE_NIL) {
        emit_asm ("MOV R0, BOXED_NIL ; no key: any key\n");
        emit_asm ("PUSH R0\n");
        return true;
    }
    if (!tic80 && arg->type == NODE_STRING) {
        int spec = v32kbd_name_spec (arg->as.string_val.value);
        if (spec < 0) {
            compiler_error (ERR_SEMANTIC, line,
                "%s(): unknown key \"%s\" (a character such as \"a\" or \"/\", or one of: "
                "up down left right enter tab space backspace delete escape capslock "
                "shift lshift rshift ctrl lctrl rctrl alt lalt ralt gui lgui rgui f1-f12)",
                func_name, arg->as.string_val.value);
            return false;
        }
        emit_asm ("MOV R0, %d.000000 ; key \"%s\"\n", spec, arg->as.string_val.value);
        emit_asm ("PUSH R0\n");
        return true;
    }
    int reg = allocate_register ();
    register_pinned[reg] = 1;
    generate_asm (arg, reg);
    emit_asm ("PUSH R%d ; key\n", reg);
    register_pinned[reg] = 0;
    unlock_register (reg);
    return true;
}

// ----------------------------------------------------------------------------
// key([k]) / keyp([k [, hold, period]]) -- native (tic80 = false) or TIC-80
// ----------------------------------------------------------------------------
bool emit_v32kbd_key_intrinsic (ASTNode *node, int dest_reg, const char *func_name, bool tic80)
{
    bool is_keyp = strcmp (func_name, "keyp") == 0;
    if (!v32kbd_require (node, func_name)) return false;
    emit_asm ("    ;; --- %s %s() Intrinsic (v32kbd) ---\n", tic80 ? "TIC-80" : "Vircon32", func_name);

    ASTNode *args[3] = { NULL };
    int arg_count = 0;
    ASTNode *curr = node->as.call.args_head;
    while (curr != NULL && arg_count < 3) {
        args[arg_count++] = curr;
        curr = curr->next;
    }
    int max_args = is_keyp ? 3 : 1;
    if (curr != NULL || arg_count > max_args) {
        compiler_warning (ERR_SEMANTIC, node->line_number,
            "%s() takes at most %d argument%s; extra arguments ignored",
            func_name, max_args, max_args == 1 ? "" : "s");
    }

    emit_asm ("MOV R0, %d\n", tic80 ? 1 : 0);
    emit_asm ("PUSH R0 ; key code set: %s\n", tic80 ? "TIC-80" : "v32kbd");

    if (is_keyp) {
        // period, hold: -1 (no autorepeat) unless given
        for (int i = 2; i >= 1; i--) {
            if (i < arg_count && args[i] != NULL && args[i]->type != NODE_NIL) {
                int reg = allocate_register ();
                register_pinned[reg] = 1;
                generate_asm (args[i], reg);
                emit_asm ("PUSH R%d ; %s\n", reg, i == 2 ? "period" : "hold");
                register_pinned[reg] = 0;
                unlock_register (reg);
            } else {
                emit_asm ("MOV R0, -1.000000 ; no %s\n", i == 2 ? "period" : "hold");
                emit_asm ("PUSH R0\n");
            }
        }
    }

    if (!v32kbd_push_spec (arg_count > 0 ? args[0] : NULL, func_name, tic80, node->line_number))
        return false;

    if (is_keyp) {
        emit_asm ("CALL __builtin_v32kbd_keyp\n");
        emit_asm ("IADD SP, 4 ; clean up keyp() arguments\n");
    } else {
        emit_asm ("CALL __builtin_v32kbd_key\n");
        emit_asm ("IADD SP, 2 ; clean up key() arguments\n");
    }
    if (dest_reg != 0) {
        emit_asm ("MOV R%d, R0\n", dest_reg);
    }
    return true;
}

// ----------------------------------------------------------------------------
// kbd.* -- available in every API mode
// ----------------------------------------------------------------------------
static bool kbd_no_args (ASTNode *node, const char *func_name)
{
    if (node->as.call.args_head != NULL) {
        compiler_error (ERR_SEMANTIC, node->line_number, "%s() takes no arguments", func_name);
        return false;
    }
    return true;
}

bool try_emit_kbd_namespace_intrinsic (ASTNode *node, int dest_reg, const char *func_name)
{
    if (!v32kbd_require (node, func_name)) return false;

    if (strcmp (func_name, "kbd.read") == 0 || strcmp (func_name, "kbd.event") == 0) {
        if (!kbd_no_args (node, func_name)) return false;
        bool event = func_name[4] == 'e';
        emit_asm ("    ;; --- %s() (v32kbd) ---\n", func_name);
        emit_asm ("MOV R0, %d\n", event ? 1 : 0);
        emit_asm ("PUSH R0 ; %s\n", event ? "every event, signed key code" : "presses, typed character");
        emit_asm ("CALL __builtin_v32kbd_read\n");
        emit_asm ("IADD SP, 1\n");
        if (dest_reg != 0) emit_asm ("MOV R%d, R0\n", dest_reg);
        return true;
    }

    if (strcmp (func_name, "kbd.port") == 0) {
        ASTNode *arg = node->as.call.args_head;
        if (arg != NULL && arg->next != NULL) {
            compiler_warning (ERR_SEMANTIC, node->line_number,
                "kbd.port() takes at most 1 argument; extra arguments ignored");
        }
        emit_asm ("    ;; --- kbd.port() (v32kbd) ---\n");
        if (arg == NULL || arg->type == NODE_NIL) {
            emit_asm ("MOV R0, BOXED_NIL ; get only\n");
            emit_asm ("PUSH R0\n");
        } else {
            int reg = allocate_register ();
            register_pinned[reg] = 1;
            generate_asm (arg, reg);
            emit_asm ("PUSH R%d ; port\n", reg);
            register_pinned[reg] = 0;
            unlock_register (reg);
        }
        emit_asm ("CALL __builtin_v32kbd_port\n");
        emit_asm ("IADD SP, 1\n");
        if (dest_reg != 0) emit_asm ("MOV R%d, R0\n", dest_reg);
        return true;
    }

    if (strcmp (func_name, "kbd.capslock") == 0 || strcmp (func_name, "kbd.connected") == 0) {
        if (!kbd_no_args (node, func_name)) return false;
        emit_asm ("    ;; --- %s() (v32kbd) ---\n", func_name);
        emit_asm ("CALL %s\n", func_name[4] == 'c' && func_name[5] == 'a'
                               ? "__builtin_v32kbd_capslock" : "__builtin_v32kbd_connected");
        if (dest_reg != 0) emit_asm ("MOV R%d, R0\n", dest_reg);
        return true;
    }

    if (strcmp (func_name, "kbd.clear") == 0) {
        if (!kbd_no_args (node, func_name)) return false;
        emit_asm ("    ;; --- kbd.clear() (v32kbd) ---\n");
        emit_asm ("CALL __builtin_v32kbd_clear\n");
        if (dest_reg != 0) emit_asm ("MOV R%d, BOXED_NIL\n", dest_reg);
        return true;
    }

    compiler_error (ERR_SEMANTIC, node->line_number,
        "Unknown keyboard function '%s' (kbd.read, kbd.event, kbd.port, kbd.capslock, "
        "kbd.connected, kbd.clear)", func_name);
    return false;
}
