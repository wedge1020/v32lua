#!/usr/bin/env python3
"""Self-test for tic80_unload.py: builds a tiny cart whose code is packed with the
loader idiom (one literal run + one back-reference), unpacks it, checks the result.
Run: python3 -I tools/test_tic80_unload.py"""
import os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIT = b"local aa = 1\n"
TAIL = b"function helper() return aa end\n"
FULL = LIT + LIT + TAIL     # the second copy of LIT is a back-reference

def pack():
    stream = bytes([len(LIT) - 1]) + LIT                              # literal run
    stream += bytes([125 + len(LIT), len(LIT) & 255, len(LIT) >> 8])   # copy len(LIT) bytes from len(LIT) back
    stream += bytes([len(TAIL) - 1]) + TAIL
    return stream

def hexline(idx, data, swap):
    if swap:
        data = bytes(((b & 15) << 4) | (b >> 4) for b in data)
    return "-- %03d:%s" % (idx, data.hex())

def main():
    stream = pack()
    full = FULL
    blob = len(stream).to_bytes(2, "little") + stream
    blob += bytes(192 - len(blob) % 192)
    lines = [hexline(i, blob[i * 192:(i + 1) * 192], True) for i in range(len(blob) // 192)]
    cart = ("-- title: t\n"
            "do local a,o,n=69988,{},0 local e=a+2+(peek(a)|peek(a+1)<<8)a=a+2 while a<e do local c=peek(a)a=a+1 "
            "if c<128 then for i=0,c do n=n+1 o[n]=string.char(peek(a+i))end a=a+c+1 else local d=peek(a)|peek(a+1)<<8 "
            "a=a+2 for _=1,c-125 do n=n+1 o[n]=o[n-d]end end end assert(load(table.concat(o),\"story\"))()end\n"
            "function TIC() cls(0) end\n\n-- <PATTERNS>\n" + "\n".join(lines) + "\n-- </PATTERNS>\n")
    with tempfile.TemporaryDirectory() as d:
        src, dst = os.path.join(d, "c.lua"), os.path.join(d, "o.lua")
        open(src, "w").write(cart)
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "tic80_unload.py"), src, "-o", dst],
                           capture_output=True, text=True)
        out = open(dst).read()
    ok = r.returncode == 0 and full.decode() in out and "load(" not in out
    print("PASS" if ok else "FAIL", "tic80_unload self-test")
    if not ok:
        print(r.stderr); print(out)
    return 0 if ok else 1

sys.exit(main())
