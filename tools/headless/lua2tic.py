#!/usr/bin/env python3
# lua2tic.py game.lua game.tic [--strip-hints]
#
# Packs a TIC-80 .lua project (code + "-- <TILES>" ... sections) into a binary
# .tic cartridge, the way TIC-80 itself does (src/studio/project.c load +
# src/cart.c tic_cart_save): bank 0 only, each chunk a 4-byte header
# (type | bank<<5, 16-bit little-endian size, 0) and its data with trailing
# zero bytes dropped. Test tool for v32lua's .tic reader (src/tic80_cart.c):
# a .lua and the .tic made from it should compile to the same program.
# --strip-hints drops v32lua's own "--#..." lines from the code, so the .tic
# has to rely on --api / --title / auto-detection.
import sys, re, struct

SECTIONS = {  # tag: (chunk type, rows, row size, flip)
    'TILES': (1, 256, 32, True), 'SPRITES': (2, 256, 32, True), 'MAP': (4, 136, 240, True),
    'WAVES': (10, 16, 16, True), 'SFX': (9, 64, 66, True), 'PATTERNS': (15, 60, 192, True),
    'TRACKS': (14, 8, 51, True), 'FLAGS': (6, 2, 256, True), 'SCREEN': (18, 136, 120, True),
    'PALETTE': (12, 2, 48, False),
}
ORDER = ['PALETTE', 'WAVES', 'TILES', 'SPRITES', 'MAP', 'SFX', 'PATTERNS', 'TRACKS', 'FLAGS', 'SCREEN']

src, dst = sys.argv[1], sys.argv[2]
strip = '--strip-hints' in sys.argv
text = open(src, encoding='utf-8', errors='replace').read().replace('\r\n', '\n')
m = re.search(r'^-- <[A-Z]+\d*>$', text, re.M)
code = text[:m.start()] if m else text
if strip:
    code = '\n'.join(l for l in code.split('\n') if not l.startswith('--#'))
code = code.rstrip('\n') + '\n'

bufs = {k: bytearray(v[1] * v[2]) for k, v in SECTIONS.items()}
for sm in re.finditer(r'^-- <([A-Z]+)>\n(.*?)^-- </\1>', text, re.M | re.S):
    tag = sm.group(1)
    if tag not in SECTIONS: continue
    _, rows, size, flip = SECTIONS[tag]
    for rm in re.finditer(r'^-- (\d+):([0-9a-fA-F]+)$', sm.group(2), re.M):
        r, h = int(rm.group(1)), rm.group(2)
        for i in range(min(size, len(h) // 2)):
            pair = h[i * 2:i * 2 + 2]
            if flip: pair = pair[1] + pair[0]
            bufs[tag][r * size + i] = int(pair, 16)

def chunk(ctype, data, bank=0):
    data = bytes(data).rstrip(b'\0')
    if not data: return b''
    return struct.pack('<BHB', ctype | (bank << 5), len(data) & 0xFFFF, 0) + data

out = b''.join(chunk(SECTIONS[t][0], bufs[t]) for t in ORDER)
c = code.encode('utf-8')
assert len(c) <= 65536, 'code over one bank is not handled by this tool'
out += struct.pack('<BHB', 5, len(c) & 0xFFFF, 0) + c
open(dst, 'wb').write(out)
print(f"{dst}: {len(out)} bytes, code {len(c)} bytes")
