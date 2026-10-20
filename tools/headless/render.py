#!/usr/bin/env python3
# render.py prog.run FRAME out.png [texture0.vtex [texture1.vtex ...]]
# Rebuild one frame from a v32run -g GPU log: clears and region draws (with
# scale/mirroring, multiply color, alpha/add/subtract blending). Rotation is
# ignored. Textures are given in cartridge order (texture 0 first); the BIOS
# texture (-1) is drawn as a magenta box. For looking at layout problems,
# not a pixel-exact GPU.
import re, struct, sys
from PIL import Image

run, frame, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
texs = []
for p in sys.argv[4:]:
    d = open(p, 'rb').read()
    assert d[:8] == b'V32-VTEX', p
    w, h = struct.unpack('<II', d[8:16])
    texs.append(Image.frombytes('RGBA', (w, h), d[16:16 + w * h * 4]))

img = Image.new('RGBA', (640, 360), (0, 0, 0, 255))
pat = re.compile(r'F(\d+) GPU (\w+) tex=(-?\d+) reg=\d+ pt=\(-?\d+,-?\d+\) sx=(\S+) sy=(\S+) ang=\S+ '
                 r'mul=([0-9A-F]+) blend=([0-9A-F]+) src=\((\d+),(\d+)\)-\((\d+),(\d+)\) hot=\(-?\d+,-?\d+\) '
                 r'SCREEN=\((\S+),(\S+) (\S+)x(\S+)\)')
clr = re.compile(r'F(\d+) GPU ClearScreen color=([0-9A-F]+)')

def color(word):
    v = int(word, 16)
    return (v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255)

for line in open(run):
    m = clr.match(line)
    if m and int(m.group(1)) == frame:
        img = Image.new('RGBA', (640, 360), color(m.group(2))[:3] + (255,))
        continue
    m = pat.match(line)
    if not m or int(m.group(1)) != frame:
        continue
    tex = int(m.group(3)); sx, sy = float(m.group(4)), float(m.group(5))
    mul = color(m.group(6)); blend = int(m.group(7), 16)
    x0, y0, x1, y1 = (int(m.group(i)) for i in range(8, 12))
    X, Y, W, H = (float(m.group(i)) for i in range(12, 16))
    W, H = max(1, round(W)), max(1, round(H))
    if 0 <= tex < len(texs):
        piece = texs[tex].crop((x0, y0, x1 + 1, y1 + 1))
    else:
        piece = Image.new('RGBA', (x1 - x0 + 1, y1 - y0 + 1), (255, 0, 255, 255))
    if sx < 0: piece = piece.transpose(Image.FLIP_LEFT_RIGHT)
    if sy < 0: piece = piece.transpose(Image.FLIP_TOP_BOTTOM)
    piece = piece.resize((W, H), Image.NEAREST)
    px = piece.load()
    for yy in range(H):
        for xx in range(W):
            r, g, b, a = px[xx, yy]
            px[xx, yy] = (r * mul[0] // 255, g * mul[1] // 255, b * mul[2] // 255, a * mul[3] // 255)
    pos = (round(X), round(Y))
    if blend == 0x20:
        img.alpha_composite(piece, pos) if pos[0] >= 0 and pos[1] >= 0 else img.paste(piece, pos, piece)
    else:
        base = img.crop((pos[0], pos[1], pos[0] + W, pos[1] + H)); bp = base.load()
        for yy in range(H):
            for xx in range(W):
                r, g, b, a = px[xx, yy]; R, G, B, A = bp[xx, yy]; f = a / 255
                if blend == 0x21: bp[xx, yy] = (min(255, R + int(r * f)), min(255, G + int(g * f)), min(255, B + int(b * f)), A)
                else: bp[xx, yy] = (max(0, R - int(r * f)), max(0, G - int(g * f)), max(0, B - int(b * f)), A)
        img.paste(base, pos)
img.convert('RGB').save(out)
