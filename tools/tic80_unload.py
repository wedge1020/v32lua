#!/usr/bin/env python3
"""tic80_unload.py -- inline a TIC-80 cart's packed-code blob before compiling.

Some TIC-80 carts keep part of their code compressed in cart memory (in the
music pattern area, say) and run it at startup:

    do local a,o,n=69988,{},0 ... assert(load(table.concat(o),"story"))() end

v32lua compiles ahead of time, so it cannot run load(). This tool does the
unpacking beforehand: it rebuilds the cart's RAM image from the -- <TILES> /
-- <PATTERNS> ... sections, decodes the blob at the address the loader reads,
and replaces the loader with the code it would have loaded.

    tic80_unload.py game.lua                 # writes game.unpacked.lua
    tic80_unload.py game.lua -o out.lua
    tic80_unload.py game.lua --dump-code     # just print the decoded code(s)

The decoder implements the common length-prefixed LZ stream
  [u16 length] then: c < 128 -> copy c+1 literal bytes;
                     c >= 128 -> u16 distance d, copy c-125 bytes from d back.
A loader that does something else is reported and left alone.
"""
import argparse, re, sys

# section name -> (RAM base address, nibble-swapped in the text form?)
# Section lines are "-- III:HEX" where III is a decimal line number; each line
# holds one record, so line n starts at base + n * record_bytes.
SECTIONS = {
    "TILES":    (0x04000, True),
    "SPRITES":  (0x06000, True),
    "MAP":      (0x08000, False),
    "WAVES":    (0x0FFE4, False),
    "SFX":      (0x100E4, False),
    "PATTERNS": (0x11164, True),
    "TRACKS":   (0x13E64, False),
    "PALETTE":  (0x03FC0, False),
}
RAM_SIZE = 0x18000

LOADER = re.compile(
    r'do\s+local\s+a\s*,\s*o\s*,\s*n\s*=\s*(\d+)\s*,\s*\{\}\s*,\s*0\b'
    r'.*?assert\s*\(\s*load\s*\(\s*table\.concat\s*\(\s*o\s*\)\s*,\s*"([^"]*)"\s*\)\s*\)\s*\(\s*\)\s*end',
    re.S)


def build_ram(text, swap_override=None):
    ram = bytearray(RAM_SIZE)
    for m in re.finditer(r'^-- <([A-Z0-9]+)>\s*\n(.*?)^-- </\1>', text, re.S | re.M):
        name, body = m.group(1), m.group(2)
        base_name = re.sub(r'\d+$', '', name)       # MAP1 -> MAP
        if name not in SECTIONS and base_name not in SECTIONS:
            continue
        base, swapped = SECTIONS.get(name) or SECTIONS[base_name]
        if swap_override and (name in swap_override or base_name in swap_override):
            swapped = swap_override.get(name, swap_override.get(base_name))
        rec = None
        for line in body.splitlines():
            lm = re.match(r'--\s*([0-9]+):([0-9a-fA-F]+)\s*$', line)
            if not lm:
                continue
            idx, hx = int(lm.group(1), 10), lm.group(2)
            if rec is None:
                rec = len(hx) // 2
            raw = bytes.fromhex(hx)
            if swapped:
                raw = bytes(((b & 15) << 4) | (b >> 4) for b in raw)
            at = base + idx * rec
            ram[at:at + len(raw)] = raw
    return ram


def lz_decode(ram, addr):
    """Decode the stream at addr; return the bytes it produces."""
    end = addr + 2 + (ram[addr] | ram[addr + 1] << 8)
    a, out = addr + 2, bytearray()
    while a < end:
        c = ram[a]; a += 1
        if c < 128:
            out += ram[a:a + c + 1]; a += c + 1
        else:
            d = ram[a] | ram[a + 1] << 8; a += 2
            for _ in range(c - 125):
                out.append(out[-d])
    return bytes(out)


def looks_like_code(b):
    """Decoded bytes are source text: mostly printable ASCII / whitespace."""
    if not b:
        return False
    good = sum(1 for c in b if 32 <= c < 127 or c in (9, 10, 13))
    return good >= 0.97 * len(b)


def decode_blob(text, addr):
    """Rebuild RAM and decode the blob at addr. The nibble order of the cart
    text differs per section kind, so try the known layout first, then every
    data section swapped, then none swapped; the first result that reads as
    source text wins."""
    tries = [None,
             {n: True for n in SECTIONS},
             {n: False for n in SECTIONS}]
    for override in tries:
        ram = build_ram(text, override)
        try:
            raw = lz_decode(ram, addr)
        except IndexError:
            continue
        if looks_like_code(raw):
            try:
                return raw.decode('utf-8')
            except UnicodeDecodeError:
                return raw.decode('latin-1')
    return None


def unwrap(code):
    """';(function() BODY end)()' -> BODY. Functions declared inside an IIFE
    are invisible to v32lua's global prepass, so the wrapper is removed
    (its locals become top-level variables, which behave the same)."""
    s = code.strip()
    m = re.match(r';?\s*\(\s*function\s*\(\s*\)(.*)end\s*\)\s*\(\s*\)\s*;?$', s, re.S)
    return m.group(1) if m else code


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('cart')
    ap.add_argument('-o', '--output')
    ap.add_argument('--dump-code', action='store_true', help='print decoded code, write nothing')
    ap.add_argument('--keep-wrapper', action='store_true', help='do not strip a (function() ... end)() wrapper')
    args = ap.parse_args()

    text = open(args.cart, encoding='utf-8').read()
    found = list(LOADER.finditer(text))
    if not found:
        print(f"{args.cart}: no packed-code loader found; nothing to do", file=sys.stderr)
        if not args.dump_code:
            open(args.output or re.sub(r'\.lua$', '', args.cart) + '.unpacked.lua', 'w', encoding='utf-8').write(text)
        return 0

    out, last, ok = [], 0, 0
    for m in found:
        addr, chunk = int(m.group(1)), m.group(2)
        code = decode_blob(text, addr)
        if code is None:
            print(f'  chunk "{chunk}" at {addr}: could not decode a code blob there; left as is', file=sys.stderr)
            continue
        if not args.keep_wrapper:
            code = unwrap(code)
        print(f'  chunk "{chunk}" at {addr}: {len(code)} bytes', file=sys.stderr)
        if args.dump_code:
            print(code); continue
        out.append(text[last:m.start()])
        out.append(f'-- [tic80_unload] chunk "{chunk}" (was loaded from address {addr})\n' + code + '\n')
        last = m.end(); ok += 1
    if args.dump_code:
        return 0
    out.append(text[last:])
    dest = args.output or re.sub(r'\.lua$', '', args.cart) + '.unpacked.lua'
    open(dest, 'w', encoding='utf-8').write(''.join(out))
    print(f'{args.cart}: inlined {ok} of {len(found)} chunk(s) -> {dest}', file=sys.stderr)
    return 0 if ok == len(found) else 1


if __name__ == '__main__':
    sys.exit(main())
