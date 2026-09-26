#!/usr/bin/env python3
# circles.py [tic80|pico8 ...] -- pixel-check circ/circb (TIC-80) and
# circfill/circ (PICO-8) against the consoles' own rasterizers.
#
# Builds a cart that draws one circle per frame (filled and outline, radius
# 0-45 plus a few large ones -- the shape-atlas path up to SHAPES_MAX_R, the
# octant-run path above), runs it headless with a GPU log, rebuilds each
# frame with render.py and compares every console pixel with the reference
# below. Also prints the GPU draws per circle.
#   TIC-80  core/draw.c drawEllipse() (Zingl) on the bounding square; circ()
#           fills each row between its outermost outline pixels.
#   PICO-8  the midpoint circle as zepto8 draws it (err from 0, x steps when
#           err >= r - 1); circfill() fills the same rows' spans.
import os, re, subprocess, sys, tempfile
from PIL import Image
T = os.path.dirname(os.path.abspath(__file__))
def zingl(x0, y0, x1, y1):
    pts = []
    if x0 > x1 or y0 > y1: return pts
    a = abs(x1 - x0); b = abs(y1 - y0); b1 = b & 1
    dx = 4 * (1 - a) * b * b; dy = 4 * (b1 + 1) * a * a
    err = dx + dy + b1 * a * a
    y0 += (b + 1) // 2; y1 = y0 - b1
    a *= 8 * a; b1 = 8 * b * b
    while True:
        pts += [(x1, y0), (x0, y0), (x0, y1), (x1, y1)]
        e2 = 2 * err
        if e2 <= dy: y0 += 1; y1 -= 1; dy += a; err += dy
        if e2 >= dx or 2 * err > dy: x0 += 1; x1 -= 1; dx += b1; err += dx
        if not x0 <= x1: break
    tail = False
    while y0 - y1 < b:
        tail = True
        pts += [(x0 - 1, y0), (x1 + 1, y0)]; y0 += 1
        pts += [(x0 - 1, y1), (x1 + 1, y1)]; y1 -= 1
    return pts, tail

def tic80_outline(r):
    if r < 0: return set()
    p, _ = zingl(-r, -r, r, r); return set(p)

def tic80_filled(r):
    s = set()
    rows = {}
    for x, y in tic80_outline(r):
        lo, hi = rows.get(y, (x, x)); rows[y] = (min(lo, x), max(hi, x))
    for y, (lo, hi) in rows.items():
        for x in range(lo, hi + 1): s.add((x, y))
    return s

def p8_outline(r):
    s = set(); dx, dy, err = r, 0, 0
    while dx >= dy:
        for (a, b) in [(dx, dy), (dy, dx), (-dy, dx), (-dx, dy), (-dx, -dy), (-dy, -dx), (dy, -dx), (dx, -dy)]: s.add((a, b))
        dy += 1
        if err < r - 1: err += 1 + 2 * dy
        else: dx -= 1; err += 1 + 2 * (dy - dx)
    return s

def p8_filled(r):
    s = set(); dx, dy, err = r, 0, 0
    while dx >= dy:
        for (h, y) in [(dx, -dy), (dx, dy), (dy, -dx), (dy, dx)]:
            for x in range(-h, h + 1): s.add((x, y))
        dy += 1
        if err < r - 1: err += 1 + 2 * dy
        else: dx -= 1; err += 1 + 2 * (dy - dx)
    return s

RADII = list(range(0, 46)) + [60, 67, 100, 150, 282, 283, 300]
CASES = [(m, r) for r in RADII for m in (1, 0)]
CART = {
 'tic80': '''-- title: circle check
cases = {}
for r = 0, 45 do cases[#cases + 1] = { 1, r } cases[#cases + 1] = { 0, r } end
for _, r in ipairs({ 60, 67, 100, 150, 282, 283, 300 }) do cases[#cases + 1] = { 1, r } cases[#cases + 1] = { 0, r } end
function TIC()
  f = (f or 0) + 1
  local c = cases[f]
  cls(0)
  if c then
    if c[1] == 1 then circ(120, 68, c[2], 12) else circb(120, 68, c[2], 12) end
    rect(0, 0, 3, 2 + c[1], 7)
  end
end
''',
 'pico8': '''--#api pico8
cases = {}
for r = 0, 45 do cases[#cases + 1] = { 1, r } cases[#cases + 1] = { 0, r } end
for _, r in ipairs({ 60, 67, 100, 150, 282, 283, 300 }) do cases[#cases + 1] = { 1, r } cases[#cases + 1] = { 0, r } end
function _draw()
  f = (f or 0) + 1
  local c = cases[f]
  cls(0)
  if c then
    camera(-10, -20)
    if c[1] == 1 then circfill(54, 44, c[2], 12) else circ(54, 44, c[2], 12) end
    camera()
    rectfill(0, 0, 2, 1 + c[1], 7)
  end
end
'''}

def check(api):
    d = tempfile.mkdtemp(prefix='circles_')
    open(os.path.join(d, 'c.lua'), 'w').write(CART[api])
    env = dict(os.environ, V32_FIXED_TIME='1')
    subprocess.run([T + '/runlua', 'c.lua', '-f', '240', '-q', '-g'], cwd=d, env=env,
                   capture_output=True, check=True)
    run = open(os.path.join(d, 'c.run')).read().split('\n')
    frames = sorted({int(m.group(1)) for l in run for m in [re.match(r'F(\d+) GPU Draw', l)] if m})
    if api == 'tic80':
        texs = ['c_colorkey_%d.vtex' % i for i in range(17)] + ['c_shapes.vtex']
        W, H, S, OX, OY, CX, CY, fil, out = 240, 136, 2.625, 0, 0, 120, 68, tic80_filled, tic80_outline
    else:
        texs = ['c_pico8.vtex', 'c_shapes.vtex']
        W, H, S, OX, OY, CX, CY, fil, out = 128, 128, 2.75, 144, 4, 64, 64, p8_filled, p8_outline
    bad, draws, ink = 0, {}, None
    for i, (mode, r) in enumerate(CASES):
        fr = frames[i]
        subprocess.run(['python3', T + '/render.py', 'c.run', str(fr), 'f.png'] + texs, cwd=d, check=True)
        im = Image.open(os.path.join(d, 'f.png')).convert('RGB')
        px = lambda x, y: im.getpixel((int(OX + (x + 0.5) * S), int(OY + (y + 0.5) * S)))
        if mode: ink = px(CX, CY)                 # a filled circle's centre
        ref = {(CX + x, CY + y) for x, y in (fil(r) if mode else out(r))}
        ref = {(x, y) for x, y in ref if 0 <= x < W and 0 <= y < H and not (x < 4 and y < 4)}
        got = {(x, y) for y in range(H) for x in range(W) if not (x < 4 and y < 4) and px(x, y) == ink}
        draws[(mode, r)] = sum(1 for l in run if l.startswith('F%d GPU Draw' % fr))
        if got != ref:
            bad += 1
            print('%s %s r=%d: %d missing, %d extra' % (api, 'filled' if mode else 'outline', r,
                                                      len(ref - got), len(got - ref)))
    print('%s: %d circles, %d pixel mismatches' % (api, len(CASES), bad))
    print('  GPU draws (filled / outline):', ', '.join('r=%d %d/%d' % (r, draws[(1, r)], draws[(0, r)])
                                                      for r in (5, 31, 32, 45, 100)))
    return bad

if __name__ == '__main__':
    apis = sys.argv[1:] or ['tic80', 'pico8']
    sys.exit(1 if sum(check(a) for a in apis) else 0)
