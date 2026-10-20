#!/usr/bin/env python3
# kbd_text.py -- v32kbd typed characters (extended characters) on the
# headless harness. Compiles read.lua / event.lua, plays a scripted v32kbd
# event stream (tools/headless/kbdscript.py) through gamepad 0 and checks what
# kbd.read() / kbd.glyph() / kbd.event() / key() report.
#   ./kbd_text.py            (needs bin/v32lua and tools/headless built)
import os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
H = os.path.join(HERE, "..", "..", "..", "tools", "headless")
sys.path.insert(0, H)
from kbdscript import Script

def run(prog, tokens, tail=40):
    s = Script().play(tokens)
    frames = s.frame + tail
    out = subprocess.run([os.path.join(H, "runlua"), os.path.join(HERE, prog), "-f", str(frames), "-q",
                          "-d", "var_LOG,var_GLY,var_N,var_HELD_A", "-p", s.text()],
                         capture_output=True, text=True).stdout
    tables, cur, vals = {}, None, {}
    for line in out.splitlines():
        m = re.match(r"SYM var_(\w+) @\w+ = \w+\s+(.*)", line)
        if m:
            cur = m.group(1); tables[cur] = {}
            vals[cur] = m.group(2).strip()
            continue
        m = re.match(r"\s+\[(\d+)\] = (-?[\d.e+-]+)", line)
        if m and cur: tables[cur][int(m.group(1))] = float(m.group(2))
        m = re.match(r"\s+slot \d+: (-?\d+) = (-?[\d.e+-]+)", line)
        if m and cur: tables[cur][int(m.group(1))] = float(m.group(2))
    n = int(float(vals.get("N", "0").split()[0]))
    listing = lambda name: [int(tables[name].get(i, -999)) for i in range(n)] if name in tables else []
    return listing("LOG"), listing("GLY"), vals.get("HELD_A", "").startswith("true")

def held(prog, tokens):
    return run(prog, tokens)[2]

fails = 0
def check(name, got, want):
    global fails
    ok = got == want
    fails += not ok
    print("%-62s %s%s" % (name, "ok" if ok else "FAIL", "" if ok else "   got %r want %r" % (got, want)))

R = lambda toks: run("read.lua", toks)
E = lambda toks: run("event.lua", toks)

# --- keys as before (modifier keys are reported too: 6 = left shift, ignored here) ---
check("read: a key press is its character",            R(["+a", "-a"])[0], [97])
check("read: shift applies",                            [c for c in R(["+lshift", "+a", "-a", "-lshift"])[0] if c > 32], [65])
check("event: presses and releases",                    E(["+a", "-a"])[0], [97, -97])
check("key(): held until released",                     (held("read.lua", ["+a"]), held("read.lua", ["+a", "-a"])), (True, False))

# --- typed characters: the high page (128-255) ---
check("read: e acute (233)",                            R(["T233"])[0], [233])
check("read: glyph of e acute",                         R(["T233"])[1], [233])
check("read: euro sign (high page, payload 0 -> 128)",  R(["T128"])[0], [128])
check("read: y diaeresis (255)",                        R(["T255"])[0], [255])
check("read: several in a row",                         R(["T233", "T252", "T241"])[0], [233, 252, 241])

# --- the low page (0-127): box drawing below 32 gets +256 ---
check("read: box drawing 14 is 270",                    R(["T14"])[0], [270])
check("read: glyph of 270 is 14",                       R(["T14"])[1], [14])
check("read: box drawing 31 is 287, glyph 31",          (R(["T31"])[0], R(["T31"])[1]), ([287], [31]))
check("read: ASCII through the low page",               R(["T65"])[0], [65])
check("read: low page payload 0 is nothing",            R(["T0"])[0], [])
check("read: key codes under 32 are not shifted",       R(["+enter", "-enter", "+up", "-up"])[0], [13, 1])
check("read: glyph of a key code is nil (-1 here)",     R(["+enter", "-enter"])[1], [-1])

# --- typed characters leave keys alone ---
check("read: key and typed character, in order",        R(["+a", "T233", "-a"])[0], [97, 233])
check("key(): a typed 'a' (low page 97) doesn't release a held a", held("read.lua", ["+a", "T97"]), True)
check("event: typed characters are not events",         E(["+a", "T233", "T14", "-a"])[0], [97, -97])
check("event: no -30/-31 release events (old decoders saw them)", E(["T233", "T65"])[0], [])

# --- the payload is taken whatever it is ---
check("read: payload 31 on the high page (159)",        R(["raw:30:r", "raw:31:r"])[0], [159])
check("read: payload 30 on the low page (30 -> 286)",   R(["raw:31:r", "raw:30:r"])[0], [286])
check("read: payload sent as a press is accepted",      R(["raw:30:p", "raw:105:p"])[0], [233])

# --- prefix timeout ---
check("read: a prefix with no payload for 30+ frames is dropped",
      R(["raw:30:r", "wait:35", "+b", "-b"])[0], [98])
check("read: a payload inside the timeout is taken",
      R(["raw:30:r", "wait:20", "raw:105:r"])[0], [233])

# --- plugging the device in again ---
check("read: replug forgets a waiting prefix and the strobe",
      R(["raw:30:r", "plug:0", "plug:1", "+b", "-b"])[0], [98])

print("\n%s" % ("all ok" if not fails else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
