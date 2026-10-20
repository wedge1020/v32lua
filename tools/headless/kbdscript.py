#!/usr/bin/env python3
# kbdscript.py [--start N] TOKEN... -> a v32run -p script that plays a v32kbd
# keyboard on gamepad 0, one event per frame, the way the v32io adapter
# shows it (strobe on Left/Right, Up = pressed, Down = released, key code on
# Start A B X Y L R, bit 0 first). Use it with a program that has
# --#keyboard 0 (or kbd.port(0)):
#   runlua prog.lua -f 40 -q -p "$(kbdscript.py +a T233 -a)"
#
# Tokens (a KEY is a character, a name -- enter, up, lshift... -- or #code):
#   +KEY / -KEY   press / release a key
#   T<n>          type character n (0-255, a BIOS font code) the extended way:
#                 a codepage prefix event (30 = high page, 31 = low page) and
#                 then the payload event, both as key releases
#   raw:<code>:<p|r>   one event with this key code (0-127), pressed or released
#   wait:<n>      n frames with no event
#   plug:<0|1>    unplug / plug in the gamepad (a plugged-in one shows every
#                 control released; the strobe is not touched)
# Prints the script and, with --frames, the frame to run until.
import sys

NAMES = {"up": 1, "down": 2, "left": 3, "right": 4, "capslock": 5, "lshift": 6, "rshift": 7,
         "backspace": 8, "tab": 9, "lctrl": 10, "rctrl": 11, "lalt": 12, "enter": 13,
         "ralt": 26, "escape": 27, "lgui": 28, "rgui": 29, "space": 32, "delete": 127}
for i in range(1, 13): NAMES["f%d" % i] = 13 + i
BITS = ["Start", "A", "B", "X", "Y", "L", "R"]

def keycode(k):
    if k.startswith("#"): return int(k[1:])
    if k.lower() in NAMES: return NAMES[k.lower()]
    if len(k) == 1: return ord(k)
    raise SystemExit("kbdscript: unknown key %r" % k)

class Script:
    def __init__(self, start=6):
        self.frame, self.side, self.ev = start, 0, []
    def event(self, code, pressed):
        self.side = 2 if self.side == 1 else 1          # Left first
        c = {"Left": int(self.side == 1), "Right": int(self.side == 2),
             "Up": int(pressed), "Down": int(not pressed)}
        for i, b in enumerate(BITS): c[b] = (code >> i) & 1
        self.ev.append("%d:%s" % (self.frame, ",".join("%s=%d" % kv for kv in c.items())))
        self.frame += 1
    def typed(self, ch):
        if ch >= 128: self.event(30, False); self.event(ch - 128, False)
        else:         self.event(31, False); self.event(ch, False)
    def wait(self, n): self.frame += n
    def plug(self, on):
        c = {"Conn": int(on)}
        if on: c.update({k: 0 for k in ["Left", "Right", "Up", "Down"] + BITS})   # shows everything released
        self.ev.append("%d:%s" % (self.frame, ",".join("%s=%d" % kv for kv in c.items())))
        self.frame += 1
    def play(self, tokens):
        for t in tokens:
            if t[0] == "+" and len(t) > 1: self.event(keycode(t[1:]), True)
            elif t[0] == "-" and len(t) > 1: self.event(keycode(t[1:]), False)
            elif t[0] == "T" and t[1:].isdigit(): self.typed(int(t[1:]))
            elif t.startswith("raw:"): _, c, a = t.split(":"); self.event(int(c), a == "p")
            elif t.startswith("wait:"): self.wait(int(t[5:]))
            elif t.startswith("plug:"): self.plug(t[5:] == "1")
            else: raise SystemExit("kbdscript: bad token %r" % t)
        return self
    def text(self): return ";".join(self.ev)

if __name__ == "__main__":
    a = sys.argv[1:]; start = 6
    if a[:1] == ["--start"]: start = int(a[1]); a = a[2:]
    print(Script(start).play(a).text())
