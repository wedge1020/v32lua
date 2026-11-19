#!/usr/bin/env python3
"""Test for tic80_audio_snapshot.py: a cart that pokes its SFX and a waveform
at run time gets matching <SFX> / <WAVES> sections. Needs v32lua, assemble and
v32orun in PATH."""
import os, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
CART = """-- title: snapshot test
local SFXRAM, WAVERAM = 0x100E4, 0x0FFE4
function setup()
  for i = 0, 15 do poke(WAVERAM + 16 + i, 0x10 + i) end      -- waveform 1
  local b = SFXRAM + 66 * 3                                  -- SFX 3
  poke(b, 0x12) poke(b + 1, 0x34) poke(b + 60, 4) poke(b + 61, 9)
end
function TIC() cls(0) sfx(3, -1, 10, 0, 15) end
-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>
"""
with tempfile.TemporaryDirectory() as d:
    src, out = os.path.join(d, "c.lua"), os.path.join(d, "c_audio.lua")
    open(src, "w").write(CART)
    r = subprocess.run([sys.executable, os.path.join(HERE, "tic80_audio_snapshot.py"), src, "-o", out,
                        "--call", "setup", "--frames", "20"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    t = open(out).read()
    assert "-- <SFX>\n-- 003:2143" in t, t
    assert "-- 001:01112131415161718191a1b1c1d1e1f1\n" in t, t
    assert "<PALETTE>" in t and "function TIC" in t
    assert "setup()" not in t.split("-- <")[0].split("function TIC")[1], "the --call lines must not reach the output"
    print("PASS")
