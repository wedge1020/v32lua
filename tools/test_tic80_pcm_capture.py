#!/usr/bin/env python3
"""Test for tic80_pcm_capture.py with a small synthetic synth cart: a mixer that
writes a square wave into a PCM buffer, a music function that calls itself for the
next song 150 frames in (a follow-up) and a game call that interrupts. Checks the
captured sound lengths, the recorded follow-up, and -- on the console logic with the
real BIOS -- that the follow-up starts on the next channel 150 frames after the
first song (+-1), that a game call fades the playing sound (volume ramps down, then a
stop) and cancels its follow-up. Needs v32lua, assemble, packrom, v32orun, numpy;
BIOS=path/to/StandardBios.v32."""
import os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BIOS = os.environ.get("BIOS", "/home/claude/ext/v32sim-user/tools/oracle/bin/StandardBios.v32")
CART = """--#api tic80
local PCM = 0x14E24
cur = nil
function startM(n, loud)
  cur = {n = n, t = 0}
end
function mix()
  if cur == nil then for i = 0, 127 do poke(PCM + i, 128) end return end
  cur.t = cur.t + 1
  for i = 0, 127 do poke(PCM + i, 128 + ((i // 8) % 2 == 0 and 40 or -40)) end
  if cur.t == 150 and cur.n < 3 then startM(cur.n + 1) end
  if cur.t >= 300 then cur = nil end
end
local f = 0
function TIC()
  f = f + 1
  if f == 400 then startM(1) end            -- the first song
  if f == 500 then startM(5) end            -- a game call: interrupts it
  if f == 700 then startM(2) end            -- plays out: its follow-up (song 3) starts 150 frames in
  mix()
  cls(0)
end
-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>
"""
def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    assert r.returncode == 0, "%s\n%s%s" % (cmd, r.stdout[-2000:], r.stderr[-2000:])
    return r
with tempfile.TemporaryDirectory() as d:
    src = os.path.join(d, "c.lua")
    open(src, "w").write(CART)
    out = os.path.join(d, "o")
    r = run([sys.executable, os.path.join(HERE, "tic80_pcm_capture.py"), src, "-o", out, "--mixer", "mix",
             "--pcm", "0x14E24,128", "--rate", "7680", "--music-fn", "startM", "--upsample", "1",
             "--fade", "0.5", "--silence-frames", "20", "--max-seconds", "30",
             "--event", "startM(1)", "--event", "startM(2)", "--event", "startM(3)", "--event", "startM(5)"])
    # captured: 300 calls of sound, the follow-up while call 150 runs
    lens = {}
    for m in re.finditer(r"event\s+(\d+) \S+\s+(\d+) samples.*?(\d+) follow-up\(s\)( @(\d+)->(\d+))?", r.stdout):
        lens[int(m.group(1))] = (int(m.group(2)), int(m.group(3)), m.group(5), m.group(6))
    assert lens[1] == (300 * 128, 1, str(149 * 128), "2"), lens
    assert lens[2] == (300 * 128, 1, str(149 * 128), "3"), lens
    assert lens[3][1] == 0 and lens[4][1] == 0, lens
    main = os.path.join(out, "c_pcm_main.lua")
    run(["v32lua", "--api", "tic80", "--no-build-scripts", main, "-o", os.path.join(out, "m.asm")])
    run(["assemble", os.path.join(out, "m.asm"), "-o", os.path.join(out, "m.vbin"), "-g", "program"])
    run(["packrom", os.path.join(out, "m.xml"), "-o", os.path.join(out, "m.v32")])
    r = run(["v32orun", "--bios", BIOS, "--cart", os.path.join(out, "m.v32"), "-f", "1600", "-s", "-q"])
    ch, ev, vol = None, [], {}
    for l in r.stdout.splitlines():
        m = re.match(r"F(\d+) SPU (\w+) = (-?[\d.e+-]+)", l)
        if not m: continue
        f, n, v = int(m.group(1)), m.group(2), float(m.group(3))
        if n == "SelectedChannel": ch = int(v)
        elif ch is not None and ch >= 8:
            if n == "ChannelAssignedSound": ev.append((f, ch, int(v)))
            if n == "ChannelVolume": vol.setdefault(ch, []).append((f, v))
            if n == "Command" and int(v) == 49 - 1 + 1 and False: pass
    # the first song at game frame 400 on channel 8 (sound 0); the game call at 500 on channel 9 (sound 3)
    assert [(c, s) for (_, c, s) in ev] == [(8, 0), (9, 3), (10, 1), (11, 2)], ev
    f0, f1 = ev[0][0], ev[1][0]
    assert 99 <= f1 - f0 <= 101, ev                     # the interrupting call came 100 frames later
    assert 149 <= ev[3][0] - ev[2][0] <= 151, ev        # the recorded follow-up, 150 frames into song 2
    # no follow-up of the first song (it would have started 150 frames in): no extra play between them; the old one fades
    v8 = vol[8]
    assert v8[0][1] == 1.0 and v8[-1][1] < 0.1 and len(v8) > 15, v8[:3] + v8[-3:]
    assert all(a[1] >= b[1] for a, b in zip(v8[1:], v8[2:])), "fade must only go down"
    print("PASS")
