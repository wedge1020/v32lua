#!/usr/bin/env python3
"""make_tic.py OUT.tic -- a minimal binary TIC-80 cart with two map banks:
bank 0's cell (0,0) = 3, bank 1's = 9. The code syncs bank 1 and clears the
screen to the color mget(0,0) names (palette index 9)."""
import struct, sys
def chunk(ctype, bank, data):
    return bytes([ctype | (bank << 5)]) + struct.pack('<H', len(data) & 0xFFFF) + b'\0' + data
code = b"""-- script: lua
function TIC()
  sync(4, 1)
  cls(mget(0, 0))
end
"""
m0 = bytearray(240 * 136); m0[0] = 3
m1 = bytearray(240 * 136); m1[0] = 9
out = chunk(5, 0, code) + chunk(4, 0, bytes(m0)) + chunk(4, 1, bytes(m1))
open(sys.argv[1], 'wb').write(out)
