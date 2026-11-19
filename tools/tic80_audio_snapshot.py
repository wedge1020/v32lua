#!/usr/bin/env python3
"""tic80_audio_snapshot.py -- give v32lua the sound a cart defines at run time.

v32lua renders a TIC-80 cart's <WAVES> / <SFX> sections to SPU samples at
compile time. A cart that instead POKEs its waveforms and SFX into RAM while
it runs (BlasTIC: initAudio() -> putSfx(...)) has no such sections, so its
sfx() calls would play the placeholder tones. This tool runs the cart
headless for a few frames with the functions that do the poking called, reads
the waveform and SFX RAM back, and writes a copy of the cart with matching
<WAVES> and <SFX> sections. Compile that copy as usual.

  tic80_audio_snapshot.py cart.lua -o cart_audio.lua --call initAudio
         [--frames 60] [--keep] [--v32lua CMD]

--call NAME[,NAME]  global functions to call (once, in order, at the end of
                    the program's top-level code, so every local they use is
                    already defined) before the RAM is read. Repeatable.
Needs v32lua, assemble and v32orun in PATH.
"""
import argparse, os, re, subprocess, sys, tempfile

WAVES, SFX = 0x0FFE4, 0x100E4          # TIC-80 RAM addresses
SPAN = (0x11164 - WAVES)               # waveforms + 64 SFX


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    return r


def split_cart(src):
    """(code, sections text): the sections start at the first '-- <NAME>' line."""
    m = re.search(r'^-- <[A-Z0-9]+>\s*$', src, re.M)
    if m is None:
        return src, ""
    return src[:m.start()], src[m.start():]


def drop_section(sections, name):
    return re.sub(r'^-- <%s>\n.*?^-- </%s>\n\n?' % (name, name), '', sections, flags=re.M | re.S)


def section_text(tag, data, count, size):
    """TIC-80 text form: 3-digit row numbers, empty rows skipped, nibbles flipped."""
    rows = []
    for r in range(count):
        row = data[r * size:(r + 1) * size]
        if any(row):
            hexs = "".join("%x%x" % (b & 15, b >> 4) for b in row)
            rows.append("-- %03d:%s\n" % (r, hexs))
    if not rows:
        return ""
    return "-- <%s>\n%s-- </%s>\n\n" % (tag, "".join(rows), tag)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cart")
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("--call", action="append", default=[])
    ap.add_argument("--frames", type=int, default=60)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--v32lua", default="v32lua")
    a = ap.parse_args()

    src = open(a.cart, encoding="utf-8", errors="replace").read()
    code, sections = split_cart(src)
    calls = [c.strip() for item in a.call for c in item.split(",") if c.strip()]
    inst = code.rstrip("\n") + "\n" + "".join("%s()\n" % c for c in calls)

    tmp = tempfile.mkdtemp(prefix="t80snap_")
    lua, asm, vbin = (os.path.join(tmp, "snap" + e) for e in (".lua", ".asm", ".vbin"))
    open(lua, "w", encoding="utf-8").write("--#api tic80\n" + inst + ("\n" + sections if sections else ""))

    def step(cmd):
        r = run(cmd)
        if r.returncode != 0:
            sys.exit("tic80_audio_snapshot: %s failed:\n%s%s" % (cmd[0], r.stdout[-1500:], r.stderr[-1500:]))
        return r

    step([a.v32lua, "--api", "tic80", "--no-build-scripts", "-o", asm, lua])
    step(["assemble", asm, "-o", vbin, "-g", "program"])
    r = step(["v32orun", vbin, "-f", str(a.frames), "-q", "-D", "-a", asm])
    m = re.search(r'^RAW TIC80_RAM_PTR ([0-9A-Fa-f]+)', r.stdout, re.M)
    if m is None:
        sys.exit("tic80_audio_snapshot: the program never touched TIC-80 RAM (no poke/peek reached); "
                 "check --call and --frames")
    base = int(m.group(1), 16)
    r = step(["v32orun", vbin, "-f", str(a.frames), "-q", "-m", "%X,%d" % (base + WAVES, SPAN)])
    words = []
    for ln in r.stdout.splitlines():
        mm = re.match(r'^MEM [0-9A-Fa-f]+ = ([0-9A-Fa-f]+)', ln)
        if mm:
            words.append(int(mm.group(1), 16) & 255)
    if len(words) != SPAN:
        sys.exit("tic80_audio_snapshot: read %d words, expected %d" % (len(words), SPAN))
    waves, sfx = words[:SFX - WAVES], words[SFX - WAVES:]

    new = drop_section(drop_section(sections, "WAVES"), "SFX")
    add = section_text("WAVES", waves, 16, 16) + section_text("SFX", sfx, 64, 66)
    n_sfx = sum(1 for r_ in range(64) if any(sfx[r_ * 66:(r_ + 1) * 66]))
    # the sections go with the others, before the first remaining one
    out = code.rstrip("\n") + "\n\n" + add + new
    open(a.output, "w", encoding="utf-8").write(out)
    print("%s: %d SFX, waveforms %s" % (a.output, n_sfx, "yes" if any(waves) else "none"))
    if a.keep:
        print("kept", tmp)


if __name__ == "__main__":
    main()
