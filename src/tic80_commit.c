#include "v32lua.h"

// ---------------------------------------------------------------------------
// TIC-80 frame commit (--tic80-commit)
//
// The GPU draws straight into the displayed image, so a TIC() that spans
// several hardware frames shows the cleared / half-drawn screen in between
// (flicker). With frame commit the drawing calls (cls, rect, rectb, circ,
// circb, line, tri, pix, spr, map, print) do not draw while TIC() runs: they
// copy their arguments into a display list (the stub `<name>_dl` in front of
// each routine). When TIC() returns, __tic80_dl_commit replays the list in
// one burst -- right away if the rest of the hardware frame can hold it (judged
// by the last replay's cost plus 1/8, as pico8's _draw()), otherwise at the
// start of the next frame -- so the previous complete frame stays on screen
// until the new one is ready.
//
// Anything that could observe or change what a queued call depends on
// (peek/poke/memcpy/memset/sync, mset, fset, a cls() with a raw color) replays
// the list first (peek/poke/memcpy/memset only when an address is below
// 0x10000), so the order of effects is exactly the program's. A queued
// print() still returns its width, computed when it is queued.
// ---------------------------------------------------------------------------

bool g_tic80_commit = false;

#define DL_CAPACITY 16384          // words of display list

typedef struct { const char *name; int args; } DeferredCall;
static const DeferredCall deferred[] = {
    { "cls", 1 }, { "rect", 5 }, { "rectb", 5 }, { "circ", 4 }, { "circb", 4 },
    { "line", 5 }, { "tri", 7 }, { "pix", 3 }, { "spr", 9 }, { "map", 8 }, { "print", 7 },
};
#define N_DEFERRED ((int) (sizeof (deferred) / sizeof (deferred[0])))

int tic80_dl_capacity (void) { return DL_CAPACITY; }

// the routine to CALL for a drawing builtin: its deferring stub in commit mode
const char *tic80_callee (const char *builtin)
{
    static char name[8][96];
    static int  slot = 0;
    if (!g_tic80_commit) return builtin;
    for (int i = 0; i < N_DEFERRED; i++)
    {
        char full[96];
        snprintf (full, sizeof (full), "__builtin_tic80_%s", deferred[i].name);
        if (strcmp (full, builtin) == 0)
        {
            slot = (slot + 1) & 7;
            snprintf (name[slot], sizeof (name[slot]), "%s_dl", builtin);
            return name[slot];
        }
    }
    return builtin;
}

void emit_tic80_commit_runtime (void)
{
    if (!g_tic80_commit) return;
    emit_asm ("\n;; =========================================================\n");
    emit_asm (";; TIC-80 frame commit: display list, deferring stubs, replay\n");
    emit_asm (";; =========================================================\n\n");

    emit_asm ("__tic80_dl_init:\n");
    emit_asm ("    MOV   R0, 0\n");
    emit_asm ("    MOV   [TIC80_DL_FILL], R0\n");
    emit_asm ("    MOV   [TIC80_DL_ON], R0\n");
    emit_asm ("    MOV   [TIC80_DL_FRAME], R0\n");
    emit_asm ("    MOV   [TIC80_DL_CYCLE], R0\n");
    emit_asm ("    MOV   R0, 60000\n");
    emit_asm ("    MOV   [TIC80_DL_COST], R0\n");
    emit_asm ("    RET\n\n");

    // one stub per deferred builtin: [SP] = return address, [SP+1..n] = its
    // arguments. Entry: [live routine, n, args...] (the words as they are
    // in memory, so the replay pushes them back in the same layout).
    for (int i = 0; i < N_DEFERRED; i++)
    {
        const char *nm = deferred[i].name;
        int         n  = deferred[i].args;
        emit_asm ("__builtin_tic80_%s_dl:\n", nm);
        emit_asm ("    MOV   R0, [TIC80_DL_ON]\n");
        emit_asm ("    IEQ   R0, 1\n");
        emit_asm ("    JF    R0, __builtin_tic80_%s\n", nm);
        emit_asm ("    PUSH  R1\n");
        emit_asm ("    PUSH  R2\n");
        emit_asm ("    MOV   R1, [TIC80_DL_FILL]\n");
        emit_asm ("    MOV   R2, R1\n");
        emit_asm ("    IADD  R2, %d\n", n + 2);
        emit_asm ("    IGT   R2, %d\n", DL_CAPACITY);
        emit_asm ("    JF    R2, __tic80_dl_rec_%s\n", nm);
        emit_asm ("    CALL  __tic80_dl_flush ; list full: replay it, then go on\n");
        emit_asm ("    MOV   R1, 0\n");
        emit_asm ("__tic80_dl_rec_%s:\n", nm);
        emit_asm ("    MOV   R2, TIC80_DL_BUF\n");
        emit_asm ("    IADD  R2, R1\n");
        emit_asm ("    MOV   R0, __builtin_tic80_%s\n", nm);
        emit_asm ("    MOV   [R2], R0\n");
        emit_asm ("    MOV   R0, %d\n", n);
        emit_asm ("    MOV   [R2+1], R0\n");
        for (int a = 0; a < n; a++)
        {
            emit_asm ("    MOV   R0, [SP+%d]\n", 3 + a);
            emit_asm ("    MOV   [R2+%d], R0\n", 2 + a);
        }
        emit_asm ("    IADD  R1, %d\n", n + 2);
        emit_asm ("    MOV   [TIC80_DL_FILL], R1\n");
        if (strcmp (nm, "print") == 0)
        {
            // print() returns its width: len * 6 px * scale (small font: 4 px),
            // as the routine itself does -- so a queued print answers at once
            emit_asm ("    MOV   R1, [SP+9] ; text\n");
            emit_asm ("    PUSH  R1\n");
            emit_asm ("    CALL  __builtin_len ; 0 for non-strings\n");
            emit_asm ("    IADD  SP, 1\n");
            emit_asm ("    MOV   R1, [SP+4] ; scale\n");
            emit_asm ("    FMUL  R0, 6.0\n");
            emit_asm ("    MOV   R2, [SP+3] ; small font?\n");
            emit_asm ("    IEQ   R2, BOXED_TRUE\n");
            emit_asm ("    JF    R2, __tic80_dl_print_w\n");
            emit_asm ("    FMUL  R0, 0.6666667\n");
            emit_asm ("__tic80_dl_print_w:\n");
            emit_asm ("    FMUL  R0, R1\n");
        }
        emit_asm ("    POP   R2\n");
        emit_asm ("    POP   R1\n");
        emit_asm ("    RET\n\n");
    }

    // __tic80_dl_flush: draw every queued call now, in order. Keeps every
    // register; a no-op when nothing is queued.
    emit_asm ("__tic80_dl_flush:\n");
    emit_asm ("    MOV   R0, [TIC80_DL_FILL]\n");
    emit_asm ("    JF    R0, __tic80_dl_flush_ret\n");
    for (int r = 1; r <= 13; r++) emit_asm ("    PUSH  R%d\n", r);
    emit_asm ("    MOV   R1, [TIC80_DL_ON]\n");
    emit_asm ("    PUSH  R1\n");
    emit_asm ("    MOV   R0, 0\n");
    emit_asm ("    MOV   [TIC80_DL_ON], R0 ; the routines below draw for real\n");
    emit_asm ("    MOV   [TIC80_DL_POS], R0\n");
    emit_asm ("__tic80_dl_flush_loop:\n");
    emit_asm ("    MOV   R1, [TIC80_DL_POS]\n");
    emit_asm ("    MOV   R0, [TIC80_DL_FILL]\n");
    emit_asm ("    MOV   R2, R1\n");
    emit_asm ("    ILT   R2, R0\n");
    emit_asm ("    JF    R2, __tic80_dl_flush_done\n");
    emit_asm ("    MOV   R2, TIC80_DL_BUF\n");
    emit_asm ("    IADD  R2, R1\n");
    emit_asm ("    MOV   R3, [R2]\n");
    emit_asm ("    MOV   R4, [R2+1]\n");
    emit_asm ("    MOV   [TIC80_DL_N], R4\n");
    emit_asm ("    IADD  R1, R4\n");
    emit_asm ("    IADD  R1, 2\n");
    emit_asm ("    MOV   [TIC80_DL_POS], R1\n");
    emit_asm ("    MOV   R6, R2\n");
    emit_asm ("    IADD  R6, 2\n");
    emit_asm ("    IADD  R6, R4 ; one past the last argument\n");
    emit_asm ("__tic80_dl_flush_push:\n");
    emit_asm ("    JF    R4, __tic80_dl_flush_call\n");
    emit_asm ("    ISUB  R6, 1\n");
    emit_asm ("    MOV   R0, [R6]\n");
    emit_asm ("    PUSH  R0\n");
    emit_asm ("    ISUB  R4, 1\n");
    emit_asm ("    JMP   __tic80_dl_flush_push\n");
    emit_asm ("__tic80_dl_flush_call:\n");
    emit_asm ("    CALL  R3\n");
    emit_asm ("    MOV   R4, [TIC80_DL_N]\n");
    emit_asm ("    IADD  SP, R4\n");
    emit_asm ("    JMP   __tic80_dl_flush_loop\n");
    emit_asm ("__tic80_dl_flush_done:\n");
    emit_asm ("    MOV   R0, 0\n");
    emit_asm ("    MOV   [TIC80_DL_FILL], R0\n");
    emit_asm ("    POP   R1\n");
    emit_asm ("    MOV   [TIC80_DL_ON], R1\n");
    for (int r = 13; r >= 1; r--) emit_asm ("    POP   R%d\n", r);
    emit_asm ("__tic80_dl_flush_ret:\n");
    emit_asm ("    RET\n\n");

    // peek/poke/memset(addr, ...) and memcpy(dest, src, ...): replay the queue
    // first only when an address is below 0x10000 (screen, palette, tiles,
    // sprites, map -- what queued drawing reads). The addresses are the
    // routine's first arguments, [SP+1] and [SP+2]; tail-jumps keep the return.
    emit_asm ("__tic80_dl_flush_mem1:\n");
    emit_asm ("    MOV   R0, [TIC80_DL_FILL]\n");
    emit_asm ("    JF    R0, __tic80_dl_flush_mem_ret\n");
    emit_asm ("    MOV   R0, [SP+1]\n");
    emit_asm ("    FLT   R0, 65536.0\n");
    emit_asm ("    JT    R0, __tic80_dl_flush\n");
    emit_asm ("    RET\n");
    emit_asm ("__tic80_dl_flush_mem2:\n");
    emit_asm ("    MOV   R0, [TIC80_DL_FILL]\n");
    emit_asm ("    JF    R0, __tic80_dl_flush_mem_ret\n");
    emit_asm ("    MOV   R0, [SP+1]\n");
    emit_asm ("    FLT   R0, 65536.0\n");
    emit_asm ("    JT    R0, __tic80_dl_flush\n");
    emit_asm ("    MOV   R0, [SP+2]\n");
    emit_asm ("    FLT   R0, 65536.0\n");
    emit_asm ("    JT    R0, __tic80_dl_flush\n");
    emit_asm ("__tic80_dl_flush_mem_ret:\n");
    emit_asm ("    RET\n\n");

    // __tic80_dl_commit: TIC() returned. Replay now if the rest of this
    // hardware frame can hold the replay, else on a fresh frame.
    emit_asm ("__tic80_dl_commit:\n");
    emit_asm ("    MOV   R0, [TIC80_DL_FILL]\n");
    emit_asm ("    JF    R0, __tic80_dl_commit_ret\n");
    emit_asm ("    IN    R0, TIM_CycleCounter\n");
    emit_asm ("    MOV   R1, [TIC80_DL_COST]\n");
    emit_asm ("    IADD  R0, R1\n");
    emit_asm ("    SHL   R1, -3\n");
    emit_asm ("    IADD  R0, R1 ; + 1/8 margin\n");
    emit_asm ("    IGT   R0, 250000 ; would the replay run past the frame?\n");
    emit_asm ("    JF    R0, __tic80_dl_commit_now\n");
    emit_asm ("    WAIT  ; show the previous frame; replay on a fresh one\n");
    emit_asm ("__tic80_dl_commit_now:\n");
    emit_asm ("    IN    R0, TIM_FrameCounter\n");
    emit_asm ("    MOV   [TIC80_DL_FRAME], R0\n");
    emit_asm ("    IN    R0, TIM_CycleCounter\n");
    emit_asm ("    MOV   [TIC80_DL_CYCLE], R0\n");
    emit_asm ("    CALL  __tic80_dl_flush\n");
    emit_asm ("    IN    R0, TIM_FrameCounter\n");
    emit_asm ("    MOV   R1, [TIC80_DL_FRAME]\n");
    emit_asm ("    ISUB  R0, R1\n");
    emit_asm ("    IMUL  R0, 250000\n");
    emit_asm ("    IN    R1, TIM_CycleCounter\n");
    emit_asm ("    IADD  R0, R1\n");
    emit_asm ("    MOV   R1, [TIC80_DL_CYCLE]\n");
    emit_asm ("    ISUB  R0, R1 ; cycles the replay took\n");
    emit_asm ("    MOV   [TIC80_DL_COST], R0\n");
    emit_asm ("__tic80_dl_commit_ret:\n");
    emit_asm ("    RET\n\n");
}
