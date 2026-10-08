// ============================================================================
// v32mouse.c -- mouse support through a v32mouse device (mouse(), mouse.*,
// PICO-8 stat(32..34))
// ----------------------------------------------------------------------------
// A v32mouse device is a USB mouse that the console sees as a gamepad (see
// the v32io project's PROTOCOLS.md / lib/mouse.h):
//
//   Start = middle button, A = left, B = right (held as they are)
//   X counter: trit Left(-)/Right(+), Gray code X(high) Y(low)
//   Y counter: trit Up(-)/Down(+),    Gray code L(high) R(low)
//
// Each counter goes around 12 positions, one control changing per step;
// the movement is the change of position since the previous frame, -5..+5
// (6 is ambiguous: no movement). The runtime (runtime/v32mouse.s, on top of
// the v32io.s group read) keeps a pointer, in the active API's own screen
// units, moved by steps * scale and kept within bounds.
//
// Lua surface:
//   mouse()                    -> x, y, left, middle, right, scrollx, scrolly
//                                 (TIC-80's shape, in every API; no wheel: 0)
//   mouse.pressed([b])         -> a button in b went down this frame
//   mouse.released([b])        -> a button in b went up this frame
//   mouse.buttons()            -> buttons held (1 left, 2 right, 4 middle)
//   mouse.delta()              -> dx, dy this frame
//   mouse.position([x, y])     -> x, y (and moves the pointer)
//   mouse.bounds(x1, y1, x2, y2)  pointer limits
//   mouse.scale([n])           -> pixels (API units) per step
//   mouse.port([n])            -> gamepad port of the mouse
//   mouse.connected()          -> device plugged in
//   PICO-8: stat(32) x, stat(33) y, stat(34) buttons (its devkit mouse)
//
// Read on every frame, like the keyboard: lazily by every call, and by the
// frame hooks (v32io_emit_frame_*_hooks) -- only when the source uses the
// mouse (v32mouse_prescan).
// ============================================================================

#include "v32lua.h"

bool v32mouse_wanted       = false;
int  v32mouse_default_port = V32LUA_DEFAULT_MOUSE_PORT;
bool g_cli_mouse_set       = false;
static int v32mouse_ram_base = -1;

// RAM layout (words from v32mouse_ram_base)
#define MSE_OFF_PORT     0     // gamepad port of the mouse (int 0-3)
#define MSE_OFF_POLLED   1     // frame of the last read (-1: none yet)
#define MSE_OFF_CONN     2     // connected at the last read (0 / 1)
#define MSE_OFF_COUNTX   3     // last X counter position (-1: unknown)
#define MSE_OFF_COUNTY   4     // last Y counter position
#define MSE_OFF_X        5     // pointer (ints, API units)
#define MSE_OFF_Y        6
#define MSE_OFF_MINX     7     // pointer bounds, inclusive
#define MSE_OFF_MINY     8
#define MSE_OFF_MAXX     9
#define MSE_OFF_MAXY    10
#define MSE_OFF_SCALE   11     // units per step
#define MSE_OFF_BUTTONS 12     // held: 1 left, 2 right, 4 middle
#define MSE_OFF_PRESSF  13     // 3 words: frame each button's press is visible
#define MSE_OFF_RELF    16     // 3 words: frame each button's release is visible
#define MSE_OFF_DFRAME  19     // frame the movement below belongs to
#define MSE_OFF_DX      20     // movement in that frame (API units)
#define MSE_OFF_DY      21
#define MSE_RAM_WORDS   22

// ----------------------------------------------------------------------------
// Is the mouse intrinsic `mouse` / `mouse.*` in effect? A function or global
// of the program's own named mouse replaces it.
// ----------------------------------------------------------------------------
static bool mouse_shadowed (void)
{
    SymbolNode *s = resolve_function_symbol ("mouse");
    if (s == NULL) s = resolve_symbol ("mouse");
    return s != NULL;
}

// How many values a call returns, for the multi-value machinery: 7 for
// mouse(), 2 for mouse.delta()/mouse.position(), 0 if `path` is none of
// them (or the program has its own `mouse`).
int v32mouse_call_values (const char *path)
{
    if (path == NULL || mouse_shadowed ()) return 0;
    if (strcmp (path, "mouse") == 0) return 7;
    if (strcmp (path, "mouse.delta") == 0 || strcmp (path, "mouse.position") == 0) return 2;
    return 0;
}

// ----------------------------------------------------------------------------
// Prescan: mouse called, mouse.<one of ours>(...), or -- PICO-8 -- its
// devkit mouse: stat(32/33/34), or poke(0x5f2d, ...) turning it on.
// ----------------------------------------------------------------------------
static const char *mouse_fields[] = {
    "pressed", "released", "buttons", "delta", "position", "bounds", "scale",
    "port", "connected", NULL
};

static bool mouse_match (const char *b, size_t n, const char *q, bool member, bool number)
{
    if (number) {
        return runtime_req.needs_pico8 && n == 6 && strncasecmp (b, "0x5f2d", 6) == 0;
    }
    if (member) return false;
    if (n == 5 && strncmp (b, "mouse", 5) == 0) {
        if (*q == '(') return true;
        if (*q == '.') {
            const char *f = q + 1;
            size_t len = 0;
            while (isalnum ((unsigned char) f[len]) || f[len] == '_') len++;
            const char *a = f + len;
            while (*a == ' ' || *a == '\t') a++;
            if (*a != '(') return false;
            for (int i = 0; mouse_fields[i] != NULL; i++)
                if (strlen (mouse_fields[i]) == len && strncmp (f, mouse_fields[i], len) == 0)
                    return true;
        }
        return false;
    }
    if (runtime_req.needs_pico8 && n == 4 && strncmp (b, "stat", 4) == 0 && *q == '(') {
        const char *a = q + 1;
        while (*a == ' ' || *a == '\t') a++;
        return a[0] == '3' && (a[1] == '2' || a[1] == '3' || a[1] == '4') &&
               !isalnum ((unsigned char) a[2]) && a[2] != '.';
    }
    return false;
}

void v32mouse_prescan (const char *src)
{
    if (src == NULL) return;
    v32mouse_wanted = v32io_source_find (src, mouse_match);
}

// ----------------------------------------------------------------------------
// RAM and %defines (from emit_variable_map(), after codegen)
// ----------------------------------------------------------------------------
int v32mouse_emit_defines (FILE *f)
{
    if (!v32mouse_wanted) return 0;

    // the pointer's units: the screen of the active API
    int w = 640, h = 360, scale = 2;
    if (runtime_req.needs_tic80)      { w = 240; h = 136; scale = 1; }
    else if (runtime_req.needs_pico8) { w = 128; h = 128; scale = 1; }

    v32mouse_ram_base = next_ram_address;
    next_ram_address  = next_ram_address + MSE_RAM_WORDS;
    fprintf (f, "%%define  V32MOUSE_DEFAULT_PORT    %d\n", v32mouse_default_port);
    fprintf (f, "%%define  V32MOUSE_DEF_MAXX        %d\n", w - 1);
    fprintf (f, "%%define  V32MOUSE_DEF_MAXY        %d\n", h - 1);
    fprintf (f, "%%define  V32MOUSE_DEF_X           %d\n", w / 2);
    fprintf (f, "%%define  V32MOUSE_DEF_Y           %d\n", h / 2);
    fprintf (f, "%%define  V32MOUSE_DEF_SCALE       %d\n", scale);
    fprintf (f, "%%define  V32MOUSE_PORT            0x%.8X\n", v32mouse_ram_base + MSE_OFF_PORT);
    fprintf (f, "%%define  V32MOUSE_POLLED          0x%.8X\n", v32mouse_ram_base + MSE_OFF_POLLED);
    fprintf (f, "%%define  V32MOUSE_CONN            0x%.8X\n", v32mouse_ram_base + MSE_OFF_CONN);
    fprintf (f, "%%define  V32MOUSE_COUNTX          0x%.8X\n", v32mouse_ram_base + MSE_OFF_COUNTX);
    fprintf (f, "%%define  V32MOUSE_COUNTY          0x%.8X\n", v32mouse_ram_base + MSE_OFF_COUNTY);
    fprintf (f, "%%define  V32MOUSE_X               0x%.8X\n", v32mouse_ram_base + MSE_OFF_X);
    fprintf (f, "%%define  V32MOUSE_Y               0x%.8X\n", v32mouse_ram_base + MSE_OFF_Y);
    fprintf (f, "%%define  V32MOUSE_MINX            0x%.8X\n", v32mouse_ram_base + MSE_OFF_MINX);
    fprintf (f, "%%define  V32MOUSE_MINY            0x%.8X\n", v32mouse_ram_base + MSE_OFF_MINY);
    fprintf (f, "%%define  V32MOUSE_MAXX            0x%.8X\n", v32mouse_ram_base + MSE_OFF_MAXX);
    fprintf (f, "%%define  V32MOUSE_MAXY            0x%.8X\n", v32mouse_ram_base + MSE_OFF_MAXY);
    fprintf (f, "%%define  V32MOUSE_SCALE           0x%.8X\n", v32mouse_ram_base + MSE_OFF_SCALE);
    fprintf (f, "%%define  V32MOUSE_BUTTONS         0x%.8X\n", v32mouse_ram_base + MSE_OFF_BUTTONS);
    fprintf (f, "%%define  V32MOUSE_PRESSF          0x%.8X\n", v32mouse_ram_base + MSE_OFF_PRESSF);
    fprintf (f, "%%define  V32MOUSE_RELF            0x%.8X\n", v32mouse_ram_base + MSE_OFF_RELF);
    fprintf (f, "%%define  V32MOUSE_DFRAME          0x%.8X\n", v32mouse_ram_base + MSE_OFF_DFRAME);
    fprintf (f, "%%define  V32MOUSE_DX              0x%.8X\n", v32mouse_ram_base + MSE_OFF_DX);
    fprintf (f, "%%define  V32MOUSE_DY              0x%.8X\n", v32mouse_ram_base + MSE_OFF_DY);
    return 23;
}

void v32mouse_emit_setup (void)
{
    if (!v32mouse_wanted) return;
    emit_asm ("CALL __v32mouse_init ; v32mouse: pointer, counter baseline\n");
}

void v32mouse_emit_frame_end_hook (void)
{
    if (!v32mouse_wanted) return;
    emit_asm ("CALL __v32mouse_frame_end ; v32mouse: read the mouse every frame\n");
}

void v32mouse_emit_frame_start_hook (void)
{
    if (!v32mouse_wanted) return;
    emit_asm ("CALL __v32mouse_update ; v32mouse: read the mouse every frame\n");
}

// Both devices' hooks, for the drivers and system.wait()
void v32io_emit_frame_end_hooks (void)
{
    v32kbd_emit_frame_end_hook ();
    v32mouse_emit_frame_end_hook ();
}

void v32io_emit_frame_start_hooks (void)
{
    v32kbd_emit_frame_start_hook ();
    v32mouse_emit_frame_start_hook ();
}

// ----------------------------------------------------------------------------
// Emitters
// ----------------------------------------------------------------------------
static bool mouse_require (ASTNode *node, const char *what)
{
    if (v32mouse_wanted) return true;
    compiler_error (ERR_INTERNAL, node->line_number,
        "%s: mouse support was not enabled for this program (call it as %s(...))", what, what);
    return false;
}

// Pushes up to nargs arguments right to left ([BP+2] = the first), nil for
// the missing ones; extra arguments are evaluated and dropped, with a
// warning.
static void push_args (ASTNode *node, int nargs, const char *what)
{
    ASTNode *args[8] = { NULL };
    int n = 0;
    for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next) {
        if (n < nargs) {
            args[n++] = a;
        } else {
            compiler_warning (ERR_SEMANTIC, node->line_number,
                "%s() takes at most %d argument%s; extra arguments ignored",
                what, nargs, nargs == 1 ? "" : "s");
            break;
        }
    }
    for (int i = nargs - 1; i >= 0; i--) {
        if (args[i] == NULL) {
            emit_asm ("MOV R0, BOXED_NIL\n");
            emit_asm ("PUSH R0 ; %s() argument %d: absent\n", what, i + 1);
            continue;
        }
        int reg = allocate_register ();
        register_pinned[reg] = 1;
        generate_asm (args[i], reg);
        emit_asm ("PUSH R%d ; %s() argument %d\n", reg, what, i + 1);
        register_pinned[reg] = 0;
        unlock_register (reg);
    }
}

// A runtime call; a multi-value one (values > 1) leaves its values the way
// a Lua call does (R0/R2/R3, MV_BUF[3..], RET_COUNT), so g_last_exec_call
// marks it for the multi-value consumers. Returns the number of values.
static int mouse_call (ASTNode *node, int dest_reg, int nargs, const char *routine,
                       const char *what, int values)
{
    emit_asm ("    ;; --- %s() (v32mouse) ---\n", what);
    push_args (node, nargs, what);
    emit_asm ("CALL %s\n", routine);
    if (nargs > 0) emit_asm ("IADD SP, %d\n", nargs);
    if (dest_reg != 0) emit_asm ("MOV R%d, R0\n", dest_reg);
    if (values > 1) {
        g_last_exec_call = node;
        node->as.call.return_count = values;
    }
    return values;
}

// mouse() -- every API
int emit_v32mouse_intrinsic (ASTNode *node, int dest_reg)
{
    if (!mouse_require (node, "mouse")) return 0;
    if (node->as.call.args_head != NULL) {
        compiler_warning (ERR_SEMANTIC, node->line_number,
            "mouse() takes no arguments; arguments ignored");
    }
    return mouse_call (node, dest_reg, 0, "__builtin_v32mouse_mouse", "mouse", 7);
}

// mouse.* -- every API; 0 if func_name isn't one (caller reports it)
int try_emit_mouse_namespace_intrinsic (ASTNode *node, int dest_reg, const char *func_name)
{
    static const struct { const char *name; int nargs; const char *routine; int values; } fns[] = {
        { "mouse.pressed",   1, "__builtin_v32mouse_pressed",   1 },
        { "mouse.released",  1, "__builtin_v32mouse_released",  1 },
        { "mouse.buttons",   0, "__builtin_v32mouse_buttons",   1 },
        { "mouse.delta",     0, "__builtin_v32mouse_delta",     2 },
        { "mouse.position",  2, "__builtin_v32mouse_position",  2 },
        { "mouse.bounds",    4, "__builtin_v32mouse_bounds",    1 },
        { "mouse.scale",     1, "__builtin_v32mouse_scale",     1 },
        { "mouse.port",      1, "__builtin_v32mouse_port",      1 },
        { "mouse.connected", 0, "__builtin_v32mouse_connected", 1 },
        { NULL, 0, NULL, 0 }
    };
    for (int i = 0; fns[i].name != NULL; i++) {
        if (strcmp (func_name, fns[i].name) != 0) continue;
        if (!mouse_require (node, func_name)) return 0;
        return mouse_call (node, dest_reg, fns[i].nargs, fns[i].routine, func_name, fns[i].values);
    }
    compiler_error (ERR_SEMANTIC, node->line_number,
        "Unknown mouse function '%s' (mouse(), mouse.pressed, mouse.released, mouse.buttons, "
        "mouse.delta, mouse.position, mouse.bounds, mouse.scale, mouse.port, mouse.connected)",
        func_name);
    return 0;
}

// __p8_stat(n) -- the PICO-8 prelude's stat(): the devkit mouse (32-34)
// when the program uses it, 0 for everything else
int emit_pico8_stat_intrinsic (ASTNode *node, int dest_reg)
{
    if (!v32mouse_wanted) {
        for (ASTNode *a = node->as.call.args_head; a != NULL; a = a->next) {
            int r = allocate_register ();
            generate_asm (a, r);
            unlock_register (r);
        }
        if (dest_reg != 0) emit_asm ("MOV R%d, 0.0 ; stat(): no state to report\n", dest_reg);
        return 1;
    }
    return mouse_call (node, dest_reg, 1, "__builtin_v32mouse_stat", "stat", 1);
}
