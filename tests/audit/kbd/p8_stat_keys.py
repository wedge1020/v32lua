#!/usr/bin/env python3
# p8_stat_keys.py -- PICO-8 stat(30) / stat(31) through the v32kbd layer.
# Only keys whose code is even are played: gamepad 0 is the keyboard here, and
# an odd code sets the Start bit, which pauses a PICO-8 cart.
import os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
H = os.path.join(HERE, "..", "..", "..", "tools", "headless")
sys.path.insert(0, H)
from kbdscript import Script

def run(tokens):
    s = Script().play(tokens)
    out = subprocess.run([os.path.join(H, "runlua"), os.path.join(HERE, "p8_stat_keys.lua"),
                          "-f", str(s.frame + 90), "-q", "-D", "-p", s.text()],
                         capture_output=True, text=True).stdout
    g = {}
    for l in out.splitlines():
        m = re.match(r"ESTR (\w+) (.*)", l)
        if m: g[m.group(1)] = ("s", m.group(2))
        m = re.match(r"CANON (\w+) bool (\w+)", l)
        if m: g[m.group(1)] = ("b", m.group(2) == "true")
    return g

fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print("%-58s %s%s" % (name, "ok" if got == want else "FAIL", "" if got == want else "   got %r want %r" % (got, want)))

g = run(["+b", "-b", "+d", "-d", "+lshift", "+f", "-f", "-lshift", "+backspace", "-backspace", "+l", "-l"])
check("nothing typed yet: stat(30) false",  g.get("idle_waiting"), ("b", False))
check("typed: stat(30) true",               g.get("waiting1"), ("b", True))
check("stat(30) does not consume",          g.get("waiting2"), ("b", True))
check("stat(31) reads the typed text",      g.get("text"), ("s", "bdF\\x08l"))
check("queue empty: stat(30) false",        g.get("after_waiting"), ("b", False))
check("queue empty: stat(31) is \"\"",      g.get("after_char"), ("s", ""))
g = run([])
check("no keys at all: stat(30) false",     g.get("waiting1"), ("b", False))
print("FAILED" if fails else "ALL PASS"); sys.exit(1 if fails else 0)
