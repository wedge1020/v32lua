// v32run -- headless Vircon32 test runner for v32lua audits.
//
// Uses the REAL CPU / memory / bus / timer / RNG cores from the official
// SimplifiedEmulator, with logging stand-ins for GPU, SPU, gamepad,
// cartridge and memory card controllers. No rendering, no audio.
//
// usage: v32run prog.vbin [-a prog.asm] [-f frames] [-g] [-s] [-d names]
//                        [-p "frame:port=value,..."] [-q]
//   -a  asm file to read %define symbols from (for -d)
//   -f  max frames to run (default 10)
//   -g  log GPU commands          -s  log SPU writes
//   -d  comma list of global names to dump at exit (or "all")
//   -p  gamepad script: e.g. "0:A=1;5:A=-1"  (port names Left Right Up Down
//       Start A B X Y L R; value >0 pressed)
//   -q  quiet: don't print per-frame summary
//   -c  max cycles total (default frames*CyclesPerFrame)
//   -t  comma list of hex addresses to trap at (prints trail + call stack)
//   -G  start like after the BIOS: RAM, registers and stack not clean
//   -P  file [frame]  per-address cycle profile (see profile.py)
//   -m  addr,n  dump n words of memory at exit
//   env V32_CFI=arm  CFI of NaN/out-of-range floats as on ARM64 hosts
//                    (default: x86-64 behaviour); V32_CFI_LOG=1 reports them

#include "VirconCPU.hpp"
#include "VirconMemory.hpp"
#include "VirconTimer.hpp"
#include "VirconRNG.hpp"
#include "VirconNullController.hpp"
#include "../VirconDefinitions/VirconDefinitions.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <fstream>
#include <map>
#include <string>
#include <vector>
#include <sstream>
using namespace std;

static int  g_frame = 0;
static int  g_overruns = 0;
static string memdump;
static const char* profpath = nullptr; static int profstart = 0;
static map<uint32_t, long long> g_prof;

// Host-independent CFI (see build.sh). NaN / out-of-range conversions are
// undefined behaviour in the real emulator: x86-64 hosts produce 0x80000000,
// ARM64 hosts produce 0 for NaN and saturate to INT32_MIN/INT32_MAX.
static int g_cfi_arm = -1, g_cfi_log = 0;
int32_t v32run_cfi(float f, int32_t ip)
{
    if (g_cfi_arm < 0) {
        const char* m = getenv("V32_CFI"); g_cfi_arm = (m && !strcmp(m, "arm"));
        g_cfi_log = getenv("V32_CFI_LOG") != nullptr;
    }
    bool bad = std::isnan(f) || f >= 2147483648.0f || f < -2147483648.0f;
    if (!bad) return (int32_t) f;
    if (g_cfi_log) {
        VirconWord w; w.AsFloat = f;
        printf("CFI-UB F%d ip=%08X in=%08X\n", g_frame, (uint32_t)(ip - 1), w.AsBinary);
    }
    if (!g_cfi_arm) return INT32_MIN;
    if (std::isnan(f)) return 0;
    return f > 0 ? INT32_MAX : INT32_MIN;
}
static bool g_log_gpu = false, g_log_spu = false;

static string fmtword(VirconWord w)
{
    char b[128];
    uint32_t u = w.AsBinary;
    if (u == 0xFFC00000u) return "nil";
    if (u == 0xFFC00001u) return "false";
    if (u == 0xFFC00002u) return "true";
    if ((u & 0xFFC00000u) == 0x7FC00000u) { snprintf(b, sizeof b, "romstr@%X", u & 0x3FFFFF); return b; }
    if ((u & 0xFFC00000u) == 0xFF800000u) { snprintf(b, sizeof b, "table@%X", u & 0x3FFFFF); return b; }
    if ((u & 0xFFC00000u) == 0xFFC00000u) { snprintf(b, sizeof b, "ramstr@%X", u & 0x3FFFFF); return b; }
    if ((u & 0xFFC00000u) == 0x7F800000u && u != 0x7F800000u) { snprintf(b, sizeof b, "func@%X", u & 0x3FFFFF); return b; }
    snprintf(b, sizeof b, "%.9g", w.AsFloat);
    return b;
}

// ---------------------------------------------------------------------------
struct LogGPU : VirconControlInterface {
    int32_t P[18] = {0};
    struct R { int32_t v[6]; };
    map<long, R> regions;
    LogGPU() { P[3] = (int32_t)0xFFFFFFFF; P[4] = 0x20; P[9] = 0; P[10] = 0; memcpy(&P[9], "\0\0\x80\x3f", 4); memcpy(&P[10], "\0\0\x80\x3f", 4); }
    long key() { return (long)P[5] * 100000 + P[6]; }
    bool ReadPort(int32_t p, VirconWord& r) override {
        if (p > 17) return false;
        if (p == 1) { r.AsInteger = 1000000; return true; }
        if (p >= 12) { r.AsInteger = regions[key()].v[p - 12]; return true; }
        r.AsInteger = P[p]; return true;
    }
    bool WritePort(int32_t p, VirconWord v) override {
        if (p > 17 || p == 1) return false;
        if (p >= 12) {
            R& rg = regions[key()]; rg.v[p - 12] = v.AsInteger;
            // real HW clamps: Min/Max to 0..TextureSize-1, hotspot to -1024..2047
            if (p < 16) { if (rg.v[p-12] < 0) rg.v[p-12] = 0; if (rg.v[p-12] > 1023) rg.v[p-12] = 1023; }
            return true;
        }
        if (p == 0) {
            if (!g_log_gpu) return true;
            VirconWord sx, sy, an; sx.AsInteger = P[9]; sy.AsInteger = P[10]; an.AsInteger = P[11];
            const char* n = "?";
            switch (v.AsInteger) {
                case 0x10: n = "ClearScreen"; break; case 0x11: n = "DrawRegion"; break;
                case 0x12: n = "DrawZoomed"; break;  case 0x13: n = "DrawRotated"; break;
                case 0x14: n = "DrawRotozoomed"; break;
            }
            if (v.AsInteger == 0x10)
                printf("F%d GPU %s color=%08X\n", g_frame, n, (uint32_t)P[2]);
            else {
                R& rg = regions[key()];
                bool zoom = (v.AsInteger == 0x12 || v.AsInteger == 0x14);
                float fx = zoom ? sx.AsFloat : 1.0f, fy = zoom ? sy.AsFloat : 1.0f;
                float x0 = P[7] + fx * (rg.v[0] - rg.v[4]);
                float y0 = P[8] + fy * (rg.v[1] - rg.v[5]);
                float w = fx * (rg.v[2] - rg.v[0] + 1), h = fy * (rg.v[3] - rg.v[1] + 1);
                if (w < 0) { x0 += w; w = -w; }
                if (h < 0) { y0 += h; h = -h; }
                printf("F%d GPU %s tex=%d reg=%d pt=(%d,%d) sx=%g sy=%g ang=%g mul=%08X blend=%X src=(%d,%d)-(%d,%d) hot=(%d,%d) SCREEN=(%.2f,%.2f %.2fx%.2f)\n",
                       g_frame, n, P[5], P[6], P[7], P[8], sx.AsFloat, sy.AsFloat, an.AsFloat,
                       (uint32_t)P[3], P[4], rg.v[0], rg.v[1], rg.v[2], rg.v[3], rg.v[4], rg.v[5], x0, y0, w, h);
            }
            return true;
        }
        P[p] = v.AsInteger; return true;
    }
};

struct LogSPU : VirconControlInterface {
    int32_t P[14] = {0};
    bool ReadPort(int32_t p, VirconWord& r) override { if (p > 13) return false; r.AsInteger = P[p]; return true; }
    bool WritePort(int32_t p, VirconWord v) override {
        static const char* names[] = {"Command","GlobalVolume","SelectedSound","SelectedChannel","SoundLength",
            "SoundPlayWithLoop","SoundLoopStart","SoundLoopEnd","ChannelState","ChannelAssignedSound",
            "ChannelVolume","ChannelSpeed","ChannelLoopEnabled","ChannelPosition"};
        if (p > 13) return false;
        P[p] = v.AsInteger;
        if (g_log_spu) {
            if (p == 1 || p == 10 || p == 11) printf("F%d SPU %s = %g\n", g_frame, names[p], v.AsFloat);
            else printf("F%d SPU %s = %d (0x%X)\n", g_frame, names[p], v.AsInteger, v.AsInteger);
        }
        return true;
    }
};

struct StubPad : VirconControlInterface {
    int32_t sel = 0;
    int32_t state[4][12];
    StubPad() { for (auto& g : state) { g[0] = 1; for (int i = 1; i < 12; i++) g[i] = -1; } }
    bool ReadPort(int32_t p, VirconWord& r) override {
        if (p > 12) return false;
        if (p == 0) { r.AsInteger = sel; return true; }
        r.AsInteger = state[sel & 3][p - 1]; return true;
    }
    bool WritePort(int32_t p, VirconWord v) override { if (p != 0) return false; if (v.AsInteger >= 0 && v.AsInteger < 4) sel = v.AsInteger; return true; }
    void frame() { for (auto& g : state) for (int i = 1; i < 12; i++) { if (g[i] > 0) g[i]++; else g[i]--; } }
};

struct StubCar : VirconControlInterface, VirconROM {
    int32_t words = 0;
    bool ReadPort(int32_t p, VirconWord& r) override {
        switch (p) { case 0: r.AsInteger = 1; return true; case 1: r.AsInteger = words; return true;
                     case 2: case 3: r.AsInteger = 0; return true; }
        return false;
    }
    bool WritePort(int32_t, VirconWord) override { return false; }
};

struct StubMem : VirconControlInterface, VirconRAM {
    bool ReadPort(int32_t p, VirconWord& r) override { if (p) return false; r.AsInteger = 1; return true; }
    bool WritePort(int32_t, VirconWord) override { return false; }
};

// ---------------------------------------------------------------------------
static vector<uint32_t> load_vbin(const char* path)
{
    ifstream f(path, ios::binary);
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(2); }
    char sig[8]; uint32_t n;
    f.read(sig, 8); f.read((char*)&n, 4);
    if (memcmp(sig, "V32-VBIN", 8)) { fprintf(stderr, "bad vbin\n"); exit(2); }
    vector<uint32_t> w(n);
    f.read((char*)w.data(), n * 4);
    return w;
}

int main(int argc, char** argv)
{
    bool dirty = false;
    const char* vbin = nullptr; const char* asmf = nullptr; string dump; string padscript;
    int frames = 10; bool quiet = false; long long maxcycles = -1; bool canon = false;
    vector<long long> traps;
    for (int i = 1; i < argc; i++) {
        string a = argv[i];
        if (a == "-a") asmf = argv[++i];
        else if (a == "-f") frames = atoi(argv[++i]);
        else if (a == "-g") g_log_gpu = true;
        else if (a == "-s") g_log_spu = true;
        else if (a == "-d") dump = argv[++i];
        else if (a == "-D") { dump = "all"; canon = true; }
        else if (a == "-p") padscript = argv[++i];
        else if (a == "-q") quiet = true;
        else if (a == "-P") { profpath = argv[++i]; if (i + 1 < argc && argv[i+1][0] != '-') profstart = atoi(argv[++i]); }
        else if (a == "-m") { memdump = argv[++i]; }
        else if (a == "-G") dirty = true;
        else if (a == "-c") maxcycles = atoll(argv[++i]);
        else if (a == "-t") { stringstream ts(argv[++i]); string t; while (getline(ts, t, ',')) if (!t.empty()) traps.push_back(strtoll(t.c_str(), nullptr, 16)); }
        else vbin = argv[i];
    }
    if (!vbin) { fprintf(stderr, "usage: v32run prog.vbin [options]\n"); return 2; }

    // BIOS: word 0 = HLT (hardware error vector lands here)
    // HLT encoding: opcode 0 in bits 31..26, rest 0
    static uint32_t bios[16] = {0};

    VirconMemoryBus MB; VirconControlBus CB; VirconCPU CPU;
    VirconRAM RAM; VirconROM BIOS; StubCar CAR; StubMem MEMC;
    VirconTimer TIM; VirconRNG RNG; LogGPU GPU; LogSPU SPU; StubPad PAD; VirconNullController NUL;

    vector<uint32_t> prog = load_vbin(vbin);
    RAM.Connect(Constants::RAMSize);
    BIOS.Connect(bios, 16);
    CAR.Connect(prog.data(), prog.size()); CAR.words = prog.size();
    MEMC.Connect(Constants::MemoryCardSize);
    MB.Slaves[0] = &RAM; MB.Slaves[1] = &BIOS; MB.Slaves[2] = &CAR; MB.Slaves[3] = &MEMC;
    CB.Slaves[0] = &TIM; CB.Slaves[1] = &RNG; CB.Slaves[2] = &GPU; CB.Slaves[3] = &SPU;
    CB.Slaves[4] = &PAD; CB.Slaves[5] = &CAR; CB.Slaves[6] = &MEMC; CB.Slaves[7] = &NUL;
    MB.Master = &CPU; CB.Master = &CPU; CPU.MemoryBus = &MB; CPU.ControlBus = &CB;
    CPU.Reset(); TIM.Reset(); RNG.Reset();
    if (dirty) {
        // -G: start the cart the way the real BIOS leaves the machine:
        // RAM NOT zeroed (the BIOS's globals and stack are left behind),
        // BIOS texture (-1) still selected. Uses a pseudo-random fill.
        uint32_t x = 0x12345678;
        for (int a = 0; a < Constants::RAMSize; a++) {
            x ^= x << 13; x ^= x >> 17; x ^= x << 5;
            VirconWord w; w.AsBinary = x; RAM.WriteAddress(a, w);
        }
        GPU.P[5] = -1;
        // registers hold whatever the BIOS left; it jumps from inside main()
        for (int r = 0; r < 14; r++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; CPU.Registers[r].AsBinary = x; }
        CPU.StackPointer.AsInteger = Constants::RAMSize - 7;
        CPU.BasePointer.AsInteger = Constants::RAMSize - 3;
    }
    CPU.InstructionPointer.AsInteger = Constants::CartridgeProgramROMFirstAddress;

    // pad script
    map<int, vector<pair<int,int>>> pad;
    {
        static const char* bn[] = {"Left","Right","Up","Down","Start","A","B","X","Y","L","R"};
        stringstream ss(padscript); string ev;
        while (getline(ss, ev, ';')) {
            if (ev.empty()) continue;
            int fr = atoi(ev.c_str()); string rest = ev.substr(ev.find(':') + 1);
            stringstream s2(rest); string kv;
            while (getline(s2, kv, ',')) {
                string k = kv.substr(0, kv.find('=')); int v = atoi(kv.substr(kv.find('=') + 1).c_str());
                for (int b = 0; b < 11; b++) if (k == bn[b]) pad[fr].push_back({b + 1, v});
            }
        }
    }

    long long cyc = 0;
    static int32_t hist[48]; long long hpos = 0;
    string status = "FRAMES_EXHAUSTED";
    for (g_frame = 0; g_frame < frames; g_frame++) {
        TIM.ChangeFrame(); CPU.ChangeFrame();
        PAD.frame();
        if (pad.count(g_frame)) for (auto& e : pad[g_frame]) PAD.state[0][e.first] = e.second > 0 ? 1 : -1;
        for (int i = 0; i < Constants::CyclesPerFrame; i++) {
            if (profpath && g_frame >= profstart) g_prof[(uint32_t) CPU.InstructionPointer.AsInteger]++;
            if (!traps.empty()) {
                hist[hpos++ % 48] = CPU.InstructionPointer.AsInteger;
                bool hit = false;
                for (long long t : traps) if (CPU.InstructionPointer.AsInteger == (int32_t) t) hit = true;
                if (hit) {
                    status = "TRAPPED";
                    printf("TRAP at %08X\nTRAIL", (uint32_t) CPU.InstructionPointer.AsInteger);
                    for (int k = 48; k >= 1; k--) if (hpos - k >= 0) printf(" %08X", (uint32_t) hist[(hpos - k) % 48]);
                    printf("\nSTACK");
                    int32_t bp = CPU.BasePointer.AsInteger;
                    for (int d = 0; d < 32 && bp > 0 && bp < Constants::RAMSize - 1; d++) {
                        VirconWord ret, nbp; RAM.ReadAddress(bp + 1, ret); RAM.ReadAddress(bp, nbp);
                        printf(" %08X", ret.AsBinary);
                        if (nbp.AsInteger <= bp) break;
                        bp = nbp.AsInteger;
                    }
                    printf("\n");
                    CPU.Halted = true; break;
                }
            }
            TIM.RunNextCycle(); CPU.RunNextCycle(); cyc++;
            if (CPU.Halted || CPU.Waiting) break;
            if (maxcycles > 0 && cyc >= maxcycles) break;
        }
        if (CPU.Halted) break;
        if (maxcycles > 0 && cyc >= maxcycles) { status = "CYCLE_LIMIT"; break; }
        if (!CPU.Waiting) { g_overruns++; if (!quiet) printf("F%d: frame budget exhausted without WAIT\n", g_frame); }
    }
    if (CPU.Halted && status != "TRAPPED" && !traps.empty()) {
        printf("HALT TRAIL");
        for (int k = 48; k >= 1; k--) if (hpos - k >= 0) printf(" %08X", (uint32_t) hist[(hpos - k) % 48]);
        printf("\n");
    }
    if (CPU.Halted && status != "TRAPPED") {
        if (CPU.InstructionPointer.AsInteger == Constants::BiosProgramROMFirstAddress + 1) {
            char b[160];
            snprintf(b, sizeof b, "HWERROR code=%d ip=%08X instr=%08X imm=%08X",
                     CPU.Registers[0].AsInteger, CPU.Registers[1].AsBinary,
                     CPU.Registers[2].AsBinary, CPU.Registers[3].AsBinary);
            status = b;
        } else status = "HALT";
    }
    if (!memdump.empty()) { unsigned a0 = 0, n = 16; sscanf(memdump.c_str(), "%x,%u", &a0, &n);
        for (unsigned k = 0; k < n; k++) { VirconWord v; bool ok = a0 >= 0x20000000 ? CAR.ReadAddress(a0 - 0x20000000 + k, v) : RAM.ReadAddress(a0 + k, v);
            printf("MEM %08X = %08X %s\n", a0 + k, ok ? v.AsBinary : 0, ok ? fmtword(v).c_str() : "?"); } }
    if (profpath) { FILE* pf = fopen(profpath, "w"); if (pf) { for (auto& e : g_prof) fprintf(pf, "%08X %lld\n", e.first, e.second); fclose(pf); } }
    printf("STATUS %s frames=%d cycles=%lld ip=%08X overruns=%d\n", status.c_str(), g_frame, cyc, (uint32_t) CPU.InstructionPointer.AsInteger, g_overruns);
    printf("REGS");
    VirconWord* regs = (VirconWord*)&CPU.Registers[0];
    for (int r = 0; r < 16; r++) { VirconWord w; memcpy(&w, (char*)regs + r * 4, 4); printf(" R%d=%08X", r, w.AsBinary); }
    printf("\n");

    if (!dump.empty() && asmf) {
        map<string, uint32_t> sym;
        ifstream f(asmf); string line;
        while (getline(f, line)) {
            char n[256]; unsigned v;
            if (sscanf(line.c_str(), "%%define %255s 0x%x", n, &v) == 2) sym[n] = v;
        }
        vector<string> names;
        if (dump == "all") { for (auto& s : sym) if (s.second < 0x10000 && s.first.rfind("func_", 0) && s.first.find("BOXED") == string::npos) names.push_back(s.first); }
        else { stringstream ss(dump); string n; while (getline(ss, n, ',')) names.push_back(n); }
        for (auto& n : names) {
            if (!sym.count(n)) { printf("SYM %s ?\n", n.c_str()); continue; }
            VirconWord w; RAM.ReadAddress(sym[n], w);
            if (canon) {
                // machine-readable: CANON <name> <kind> <value>
                uint32_t u = w.AsBinary; string nm = n.rfind("var_", 0) == 0 ? n.substr(4) : n;
                auto rdstr = [&](bool rom, uint32_t addr) { string r; for (int k = 0; k < 4000; k++) { VirconWord c;
                        bool ok = rom ? CAR.ReadAddress(addr + k, c) : RAM.ReadAddress(addr + k, c);
                        if (!ok || c.AsInteger == 0) break; r += (char) c.AsInteger; } return r; };
                if (u == 0xFFC00000u) printf("CANON %s nil\n", nm.c_str());
                else if (u == 0xFFC00001u) printf("CANON %s bool false\n", nm.c_str());
                else if (u == 0xFFC00002u) printf("CANON %s bool true\n", nm.c_str());
                else if ((u & 0xFFC00000u) == 0x7FC00000u) printf("CANON %s str %s\n", nm.c_str(), rdstr(true, u & 0x3FFFFF).c_str());
                else if ((u & 0xFFC00000u) == 0xFFC00000u) printf("CANON %s str %s\n", nm.c_str(), rdstr(false, u & 0x3FFFFF).c_str());
                else if ((u & 0xFFC00000u) == 0xFF800000u) printf("CANON %s table\n", nm.c_str());
                else if ((u & 0x7F800000u) == 0x7F800000u && (u & 0x007FFFFF) != 0) printf("CANON %s function\n", nm.c_str());
                else printf("CANON %s num %.9g\n", nm.c_str(), w.AsFloat);
                continue;
            }
            string extra;
            if ((w.AsBinary & 0xFFC00000u) == 0x7FC00000u) {
                // ROM string: one char per word, NUL-terminated, at cart page + payload
                extra = " \"";
                for (int k = 0; k < 200; k++) {
                    VirconWord c;
                    if (!CAR.ReadAddress((w.AsBinary & 0x3FFFFF) + k, c) || c.AsInteger == 0) break;
                    extra += (char) c.AsInteger;
                }
                extra += "\"";
            }
            printf("SYM %s @%X = %08X  %s%s\n", n.c_str(), sym[n], w.AsBinary, fmtword(w).c_str(), extra.c_str());
            if ((w.AsBinary & 0xFFC00000u) == 0xFF800000u) {
                // table: header [cap, length, array, hash] + contents
                uint32_t t = w.AsBinary & 0x3FFFFF; VirconWord h[4];
                for (int k = 0; k < 4; k++) RAM.ReadAddress(t + k, h[k]);
                int cap = h[0].AsInteger & 0xFFFF;
                printf("    cap=%d len=%d array@%X hash@%X\n", cap, h[1].AsInteger, h[2].AsBinary, h[3].AsBinary);
                for (int k = 0; k < cap; k++) { VirconWord v; RAM.ReadAddress(h[2].AsInteger + k, v);
                    if (v.AsBinary != 0xFFC00000u) printf("    [%d] = %s\n", k + 1, fmtword(v).c_str()); }
                if (h[3].AsInteger) { VirconWord hc, hu; RAM.ReadAddress(h[3].AsInteger, hc); RAM.ReadAddress(h[3].AsInteger + 1, hu);
                    printf("    hash cap=%d used=%d\n", hc.AsInteger, hu.AsInteger);
                    for (int k = 0; k < hc.AsInteger && k < 4096; k++) { VirconWord kk, vv;
                        RAM.ReadAddress(h[3].AsInteger + 2 + 2 * k, kk); RAM.ReadAddress(h[3].AsInteger + 3 + 2 * k, vv);
                        if (kk.AsBinary != 0xFFC00000u) printf("    slot %d: %s = %s\n", k, fmtword(kk).c_str(), fmtword(vv).c_str()); } }
            }
        }
    }
    return 0;
}
