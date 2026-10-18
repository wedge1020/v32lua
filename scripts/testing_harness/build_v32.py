#!/usr/bin/env python3
"""
Batch-convert PICO-8 carts (*.p8, *.p8.png) and TIC-80 carts (*.tic) to Vircon32
ROMs (*.v32).

For each cart in the source folder (the originals are only read, never modified):
  1. clean the "work" folder and copy the cart into it (as cart.p8 / cart.tic, so
     odd characters in filenames can't break the tools or the generated XML).
     PNG-format PICO-8 carts (*.p8.png, or a .p8.png renamed to .p8) are copied as
     cart.p8.png and decoded to a UTF-8 text cart.p8 inside the work folder.
     TIC-80 carts are compiled as-is (v32lua reads plain binary Lua .tic carts).
  2. v32lua --api pico8 cart.p8   /   v32lua --api tic80 cart.tic
  3. on success: assemble cart.asm, then packrom cart.xml
  4. copy cart.v32 to v32\\<name>.v32 (name without .p8 / .p8.png / .tic)

Results go to v32\\results.csv; full tool output of every failure goes to
v32\\logs\\<name>.log.

Usage:
  python build_v32.py                            # all *.p8, *.p8.png and *.tic next to this script
  python build_v32.py -filter "c*.p8" "c*.p8.png"  # a subset
  python build_v32.py -filter "*.tic"            # only TIC-80 carts
  python build_v32.py -skipexisting              # don't rebuild carts that already have a .v32
  python build_v32.py -start "Celeste.p8"        # begin at this cart (alphabetical order), .p8 optional
  python build_v32.py -max 10                    # build at most 10 carts (skipped ones don't count)
  python build_v32.py -jobs 4                    # carts built in parallel (default: CPU cores;
                                                 # -jobs 1 builds one at a time)
  python build_v32.py -rate 44100               # pass --rate (sound sample rate) to v32lua,
                                                 # PICO-8 and TIC-80 carts (not passed by default)
  python build_v32.py -fastcircles               # pass --fast-circles: big filled circles as one
                                                 # scaled disc, faster (not passed by default)
  python build_v32.py -nobezel                   # pass --no-bezel: PICO-8 without side panels
  python build_v32.py -png2p8 in.p8.png out.p8   # only convert one PNG cart to text

Title: v32lua titles a PICO-8 cart "[PICO8] <first comment line>" and a TIC-80 cart
"[TIC80] <-- title: tag>". Only when a cart has no such title does the script pass
--title "[PICO8] <original file name>" / "[TIC80] <original file name>" (the carts
are compiled as work/cart.p8 / cart.tic, so v32lua's own fallback would say "cart").

Tools: -v32lua is the path to the v32lua executable, -devtools the folder holding
assemble and packrom (with or without .exe). Paths may be relative or use ~.
On Windows they default to C:\\github\\v32lua\\bin\\v32lua.exe and
C:\\utils\\vircon32\\devtools; on Linux / macOS the tools are looked up on the PATH
unless given, e.g.:
  python3 build_v32.py -v32lua ~/github/v32lua/bin/v32lua -devtools ~/vircon32/devtools
"""

import argparse
import csv
import fnmatch
import functools
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
import zlib

# =========================================================================
# PICO-8 PNG cart (.p8.png) -> text .p8 converter
#
# Cart data is steganographically stored in the low 2 bits of each ARGB
# channel (160x205 pixels = 0x8020 bytes). Uses its own PNG reader so no
# library can alter the pixel bits (gamma / colour management).
# =========================================================================


class CartError(Exception):
    pass


def read_rom(path):
    with open(path, "rb") as fh:
        f = fh.read()
    if len(f) < 8 or f[:8] != b"\x89PNG\r\n\x1a\n":
        raise CartError("not a PNG file")

    w = h = depth = ctype = interlace = 0
    idat = bytearray()
    p = 8
    while p + 8 <= len(f):
        length = int.from_bytes(f[p:p + 4], "big")
        ctype_name = f[p + 4:p + 8]
        d = p + 8
        if ctype_name == b"IHDR":
            w = int.from_bytes(f[d:d + 4], "big")
            h = int.from_bytes(f[d + 4:d + 8], "big")
            depth, ctype, interlace = f[d + 8], f[d + 9], f[d + 12]
        elif ctype_name == b"IDAT":
            idat += f[d:d + length]
        elif ctype_name == b"IEND":
            break
        p = d + length + 4

    if w != 160 or h != 205:
        raise CartError("PNG is %dx%d, not a 160x205 PICO-8 cart" % (w, h))
    if depth != 8 or interlace != 0 or ctype not in (2, 6):
        raise CartError("unsupported PNG format (depth %d, colour type %d, interlace %d)" % (depth, ctype, interlace))

    bpp = 4 if ctype == 6 else 3
    stride = w * bpp
    try:
        raw = zlib.decompressobj().decompress(bytes(idat))
    except zlib.error as e:
        raise CartError("corrupt PNG image data (%s)" % e)
    if len(raw) < (stride + 1) * h:
        raise CartError("truncated PNG image data")

    px = bytearray(stride * h)
    prev = bytearray(stride)
    for y in range(h):
        ft = raw[y * (stride + 1)]
        src = y * (stride + 1) + 1
        line = bytearray(raw[src:src + stride])
        if ft == 0:
            pass
        elif ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xff
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xff
        elif ft == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xff
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                line[i] = (line[i] + (a if (pa <= pb and pa <= pc) else (b if pb <= pc else c))) & 0xff
        else:
            raise CartError("bad PNG filter type %d" % ft)
        px[y * stride:(y + 1) * stride] = line
        prev = line

    rom = bytearray(w * h)
    for i in range(w * h):
        o = i * bpp
        r, g, b = px[o], px[o + 1], px[o + 2]
        a = px[o + 3] if bpp == 4 else 255
        rom[i] = ((a & 3) << 6) | ((r & 3) << 4) | ((g & 3) << 2) | (b & 3)
    return rom


CODE, CODE_END = 0x4300, 0x8000


def code_bytes(rom):
    if rom[CODE:CODE + 4] == b"\x00pxa":
        return pxa(rom)
    if rom[CODE:CODE + 4] == b":c:\x00":
        return old_compressed(rom)
    end = CODE
    while end < CODE_END and rom[end] != 0:
        end += 1
    return bytes(rom[CODE:end])


def old_compressed(rom):
    """Pre-0.2.0 ":c:" format."""
    lut = "#\n 0123456789abcdefghijklmnopqrstuvwxyz!#%(){}[]<>+=/*:;.,~_"
    length = (rom[CODE + 4] << 8) | rom[CODE + 5]
    i = CODE + 8
    o = bytearray()
    while len(o) < length:
        if i >= CODE_END:
            raise CartError("corrupt :c: code (overrun)")
        b = rom[i]
        i += 1
        if b == 0:
            o.append(rom[i])
            i += 1
        elif b < 0x3C:
            o.append(ord(lut[b]))
        else:
            n = rom[i]
            i += 1
            off = (b - 0x3C) * 16 + (n & 0xF)
            cnt = (n >> 4) + 2
            s = len(o) - off
            if s < 0:
                raise CartError("corrupt :c: code (bad offset)")
            for k in range(cnt):
                o.append(o[s + k])
    return bytes(o[:length])


def pxa(rom):
    """0.2.0+ PXA format (LSB-first bitstream, move-to-front literals + back references)."""
    length = (rom[CODE + 4] << 8) | rom[CODE + 5]
    pos = (CODE + 8) * 8

    def bits(n):
        nonlocal pos
        v = 0
        for k in range(n):
            if (pos >> 3) >= CODE_END:
                raise CartError("corrupt pxa code (overrun)")
            v |= ((rom[pos >> 3] >> (pos & 7)) & 1) << k
            pos += 1
        return v

    mtf = list(range(256))
    o = bytearray()
    while len(o) < length:
        if bits(1) == 1:
            unary = 0
            while bits(1) == 1:
                unary += 1
            idx = bits(4 + unary) + (((1 << unary) - 1) << 4)
            if idx > 255:
                raise CartError("corrupt pxa code (bad literal)")
            c = mtf.pop(idx)
            mtf.insert(0, c)
            o.append(c)
        else:
            offlen = (5 if bits(1) == 1 else 10) if bits(1) == 1 else 15
            off = bits(offlen) + 1
            if offlen == 10 and off == 1:
                while True:
                    c = bits(8)
                    if c == 0:
                        break
                    o.append(c)
            else:
                cnt = 3
                while True:
                    part = bits(3)
                    cnt += part
                    if part != 7:
                        break
                s = len(o) - off
                if s < 0:
                    raise CartError("corrupt pxa code (bad offset)")
                for k in range(cnt):
                    o.append(o[s + k])
    return bytes(o[:length])


# P8SCII -> Unicode, exactly as PICO-8 itself writes .p8 files (UTF-8).
# 0x00-0x1f control glyphs (tab / newline / carriage return stay as-is)
_P8_LOW = [
    "", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "\t", "\n", "ᵇ", "ᶜ", "\r", "ᵉ", "ᶠ",
    "▮", "■", "□", "⁙", "⁘", "‖", "◀", "▶", "「", "」", "¥", "•", "、", "。", "゛", "゜",
]
# 0x80-0xff
_P8_HIGH = [
    "█", "▒", "🐱", "⬇️", "░", "✽", "●", "♥", "☉", "웃", "⌂", "⬅️", "😐", "♪", "🅾️", "◆",
    "…", "➡️", "★", "⧗", "⬆️", "ˇ", "∧", "❎", "▤", "▥", "あ", "い", "う", "え", "お", "か",
    "き", "く", "け", "こ", "さ", "し", "す", "せ", "そ", "た", "ち", "つ", "て", "と", "な", "に",
    "ぬ", "ね", "の", "は", "ひ", "ふ", "へ", "ほ", "ま", "み", "む", "め", "も", "や", "ゆ", "よ",
    "ら", "り", "る", "れ", "ろ", "わ", "を", "ん", "っ", "ゃ", "ゅ", "ょ", "ア", "イ", "ウ", "エ",
    "オ", "カ", "キ", "ク", "ケ", "コ", "サ", "シ", "ス", "セ", "ソ", "タ", "チ", "ツ", "テ", "ト",
    "ナ", "ニ", "ヌ", "ネ", "ノ", "ハ", "ヒ", "フ", "ヘ", "ホ", "マ", "ミ", "ム", "メ", "モ", "ヤ",
    "ユ", "ヨ", "ラ", "リ", "ル", "レ", "ロ", "ワ", "ヲ", "ン", "ッ", "ャ", "ュ", "ョ", "◜", "◝",
]
assert len(_P8_LOW) == 32 and len(_P8_HIGH) == 128
P8SCII = _P8_LOW + [chr(c) for c in range(0x20, 0x7F)] + ["○"] + _P8_HIGH


def _hex_bytes(data):
    return data.hex()


def _section(out, name, rows, empty):
    """Emit rows, dropping trailing all-empty rows (as PICO-8 does); nothing if all empty."""
    last = len(rows) - 1
    while last >= 0 and empty[last]:
        last -= 1
    if last < 0:
        return
    out.append(name)
    out.extend(rows[:last + 1])


def png2p8(png_path, p8_path):
    rom = read_rom(png_path)
    out = ["pico-8 cartridge // http://www.pico-8.com", "version %d" % rom[0x8000], "__lua__"]
    out.append("".join(P8SCII[c] for c in code_bytes(rom)))

    # __gfx__: 128 rows of 128 pixels, low nibble = left pixel
    rows, empty = [], []
    for y in range(128):
        row = rom[y * 64:(y + 1) * 64]
        rows.append("".join("%x%x" % (b & 15, b >> 4) for b in row))
        empty.append(not any(row))
    _section(out, "__gfx__", rows, empty)

    # __gff__: 256 sprite flags, 2 rows of 128
    rows, empty = [], []
    for y in range(2):
        row = rom[0x3000 + y * 128:0x3000 + (y + 1) * 128]
        rows.append(_hex_bytes(row))
        empty.append(not any(row))
    _section(out, "__gff__", rows, empty)

    # __map__: top 32 rows (rows 32-63 share memory with the lower __gfx__)
    rows, empty = [], []
    for y in range(32):
        row = rom[0x2000 + y * 128:0x2000 + (y + 1) * 128]
        rows.append(_hex_bytes(row))
        empty.append(not any(row))
    _section(out, "__map__", rows, empty)

    # __sfx__: 64 x (mode speed loopstart loopend + 32 notes of ppwve)
    rows, empty = [], []
    for s in range(64):
        o = 0x3200 + s * 68
        r = [_hex_bytes(rom[o + 64:o + 68])]
        for n in range(32):
            v = rom[o + n * 2] | (rom[o + n * 2 + 1] << 8)
            pitch = v & 0x3F
            wave = ((v >> 6) & 7) | ((v >> 12) & 8)
            vol = (v >> 9) & 7
            fx = (v >> 12) & 7
            r.append("%02x%x%x%x" % (pitch, wave, vol, fx))
        rows.append("".join(r))
        empty.append(not any(rom[o:o + 68]))
    _section(out, "__sfx__", rows, empty)

    # __music__: 64 x "flags ch0ch1ch2ch3"
    rows, empty = [], []
    for m in range(64):
        o = 0x3100 + m * 4
        chans = rom[o:o + 4]
        flags = sum(((chans[ch] >> 7) & 1) << ch for ch in range(4))
        rows.append("%02x %s" % (flags, "".join("%02x" % (b & 0x7F) for b in chans)))
        # all channels disabled (0x41-0x44 is PICO-8's blank pattern)
        empty.append(all((b & 0xC0) == 0x40 or b == 0 for b in chans))
    _section(out, "__music__", rows, empty)

    with open(p8_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out) + "\n\n")


# =========================================================================
# Batch build
# =========================================================================

CRLF = chr(13) + chr(10)  # logs use Windows line endings, like the PowerShell version
GREEN, RED, YELLOW, RESET = "\033[32m", "\033[31m", "\033[33m", "\033[0m"


def _make_compare():
    """Case-insensitive, culture-aware string compare, same as PowerShell's Sort-Object."""
    try:
        import ctypes
        f = ctypes.windll.kernel32.CompareStringEx
        f.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_wchar_p, ctypes.c_int,
                      ctypes.c_wchar_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        NORM_IGNORECASE = 0x1

        def cmp(a, b):
            r = f(None, NORM_IGNORECASE, a, len(a), b, len(b), None, None, None)  # None = user locale
            return r - 2  # CSTR_LESS_THAN=1, CSTR_EQUAL=2, CSTR_GREATER_THAN=3
        return cmp
    except (AttributeError, OSError):
        return lambda a, b: (a.lower() > b.lower()) - (a.lower() < b.lower())


compare = _make_compare()


def run_tool(exe, args, work_dir, timeout):
    """Runs a tool inside the work folder with a timeout. Returns (exit code, combined output)."""
    shown = " ".join('"%s"' % a if (" " in a or not a) else a for a in args)
    header = "> %s %s" % (os.path.basename(exe), shown) + CRLF
    try:
        p = subprocess.run([exe] + args, cwd=work_dir, capture_output=True, timeout=timeout,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        text = p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")
        return p.returncode, header + text
    except subprocess.TimeoutExpired as e:
        text = (e.stdout or b"").decode("utf-8", "replace") + (e.stderr or b"").decode("utf-8", "replace")
        return -1, header + text + CRLF + "*** TIMED OUT after %d s ***" % timeout


def first_error(text):
    """First meaningful error line, for the CSV summary."""
    lines = text.splitlines()
    for line in lines:
        if re.search(r"error|fail|TIMED OUT", line, re.I):
            return line.strip()
    for line in lines:
        if line.strip() and not line.startswith("> "):
            return line.strip()
    return ""


CART_EXT = re.compile(r"(?i)\.(p8(\.png)?|tic)$")


def cart_base(name):
    """Cart name without .p8 / .p8.png, used for the .v32 / .log names and -start."""
    return CART_EXT.sub("", name)


def clear_dir(path):
    for entry in os.listdir(path):
        full = os.path.join(path, entry)
        if os.path.isdir(full) and not os.path.islink(full):
            shutil.rmtree(full)
        else:
            os.remove(full)


def has_embedded_title(p8_path):
    """True when the cart names itself the way v32lua reads it: the first line of the
    __lua__ section that isn't blank or a --# hint is a non-empty "--" comment."""
    with open(p8_path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
    in_lua = False
    for line in lines:
        if not in_lua:
            in_lua = line.strip() == "__lua__"
            continue
        if re.match(r"^__[a-z0-9]+__\s*$", line):
            return False
        q = line.lstrip(" \t\r")
        if not q or q.startswith("--#"):
            continue
        return q.startswith("--") and not q.startswith("--[[") and q[2:].strip(" \t\r") != ""
    return False


def tic80_code(tic_path):
    """The Lua code of a binary .tic cart, as v32lua reads it: the CODE chunks (type 5)
    of banks 7..0, each up to its first zero byte. Empty if there are none."""
    with open(tic_path, "rb") as fh:
        buf = fh.read()
    code = [b""] * 8
    pos = 0
    while pos + 4 <= len(buf):
        ctype, bank = buf[pos] & 0x1F, buf[pos] >> 5
        size = buf[pos + 1] | (buf[pos + 2] << 8)
        if size == 0 and ctype in (5, 19):   # CODE / BINARY: 0 means 64 KiB
            size = 65536
        pos += 4
        if pos + size > len(buf):
            break
        if ctype == 5:
            code[bank] = buf[pos:pos + size].split(b"\0", 1)[0]
        pos += size
    return b"".join(code[b] for b in range(7, -1, -1)).decode("utf-8", "replace")


def has_tic80_title(tic_path):
    """True when the cart has a non-empty "-- title:" tag (TIC-80's tic_tool_metatag,
    which v32lua uses: the first occurrence anywhere in the code)."""
    code = tic80_code(tic_path).replace("\r\n", "\n")
    i = code.find("-- title:")
    if i < 0:
        return False
    return code[i + 9:].split("\n", 1)[0].strip(" \t\n\r\v\f") != ""


def is_png(path):
    with open(path, "rb") as fh:
        hdr = fh.read(4)
    return len(hdr) == 4 and hdr[1:4] == b"PNG"


IS_WINDOWS = os.name == "nt"


def full_path(path):
    """Expands ~ and makes the path absolute (tools run with the work folder as cwd)."""
    return os.path.abspath(os.path.expanduser(path))


def find_tool(name, path=None, folder=None):
    """Locates a tool: an explicit file path, else <folder>/<name>[.exe], else <name> on the PATH.
    Returns an absolute path or None."""
    if path:
        p = full_path(path)
        if os.path.isfile(p):
            return p
        if IS_WINDOWS and os.path.isfile(p + ".exe"):
            return p + ".exe"
        return None
    if folder:
        for candidate in (name, name + ".exe"):
            p = os.path.join(full_path(folder), candidate)
            if os.path.isfile(p):
                return p
        return None
    found = shutil.which(name)
    return os.path.abspath(found) if found else None


def run_with_recovery(items, jobs, new_pool, fn, handle, error_result):
    """Runs fn(item) for every item on a process pool of `jobs` workers (new_pool(n) makes
    one), calling handle(item, value) in this process as the results come in.

    A worker process that dies abruptly (e.g. Windows ran out of memory) breaks the whole
    pool. Then the items that were in progress -- one of them caused it -- are retried one
    at a time, each in its own fresh single-worker pool: an item that kills its worker
    again gets handle(item, error_result(item, message)), the innocent ones get their real
    result, and the run goes on with a fresh pool. Items are handed out as workers free up,
    so it's always known which ones were in progress."""
    from collections import deque
    from concurrent.futures import FIRST_COMPLETED, wait
    from concurrent.futures.process import BrokenProcessPool

    def run_alone(item):
        single = new_pool(1)
        try:
            return single.submit(fn, item).result()
        except BrokenProcessPool:
            return error_result(item, "worker process died while running this cart "
                                      "(likely out of memory)")
        except Exception as e:
            return error_result(item, repr(e))
        finally:
            single.shutdown(wait=False, cancel_futures=True)

    queue, jobs = deque(items), max(1, jobs)
    pool, inflight = new_pool(jobs), {}
    try:
        while queue or inflight:
            while queue and len(inflight) < jobs:
                item = queue.popleft()
                inflight[pool.submit(fn, item)] = item
            finished, _ = wait(inflight, return_when=FIRST_COMPLETED)
            broken = []
            for fut in finished:
                item = inflight.pop(fut)
                try:
                    value = fut.result()
                except BrokenProcessPool:
                    broken.append(item)
                    continue
                except Exception as e:
                    value = error_result(item, repr(e))
                handle(item, value)
            if broken:
                suspects = broken + list(inflight.values())   # all of these were in progress
                inflight.clear()
                pool.shutdown(wait=False, cancel_futures=True)
                print("%sA worker process died (likely out of memory): retrying the %d carts that were "
                      "in progress one at a time%s" % (YELLOW, len(suspects), RESET), flush=True)
                for item in suspects:
                    handle(item, run_alone(item))
                pool = new_pool(jobs)
    finally:
        pool.shutdown(wait=False, cancel_futures=True)


def add_cart_options(ap):
    """v32lua cart options shared by build_v32 / test_v32 / screenshot_v32 / bench_v32, so
    tests, screenshots and benchmarks are made from the same build as the ROMs.
    Off by default: nothing is passed unless asked for."""
    ap.add_argument("-fastcircles", "--fast-circles", action="store_true",
                    help="pass --fast-circles: filled circles above radius 31 drawn as one scaled disc "
                         "(faster; about 1.5%% of edge pixels differ)")
    ap.add_argument("-nobezel", "--no-bezel", action="store_true",
                    help="pass --no-bezel: PICO-8 carts get black side margins instead of the side panels")


def cart_option_args(args):
    """The v32lua arguments for the options of add_cart_options()."""
    out = []
    if getattr(args, "fast_circles", False):
        out.append("--fast-circles")
    if getattr(args, "no_bezel", False):
        out.append("--no-bezel")
    return out


def build_cart(full, name, work_dir, tools, args, out_dir, log_dir):
    """Builds one cart in work_dir: (PNG ->) .p8 / .tic -> v32lua -> assemble -> packrom,
    then copies the ROM to out_dir (or writes the tool output to log_dir). -> result row"""
    v32lua, assemble, packrom = tools
    base = cart_base(name)
    target = os.path.join(out_dir, base + ".v32")
    log = os.path.join(log_dir, base + ".log")

    # TIC-80 carts by extension; PICO-8 PNG-format carts by content, not extension
    if name.lower().endswith(".tic"):
        fmt, api, cart_file, prefix = "tic", "tic80", "cart.tic", "[TIC80] "
    else:
        fmt = "png" if is_png(full) else "text"
        api, cart_file, prefix = "pico8", "cart.p8", "[PICO8] "
    cart_path = os.path.join(work_dir, cart_file)

    # Only the copy in the work folder is used from here on; the original is never modified
    stage = ""
    all_output = ""
    last_output = ""
    if fmt == "png":
        png_copy = os.path.join(work_dir, "cart.p8.png")
        shutil.copyfile(full, png_copy)
        try:
            png2p8(png_copy, os.path.join(work_dir, "cart.p8"))
            all_output += "> png2p8 cart.p8.png" + CRLF + "OK" + CRLF
        except Exception as e:  # CartError, or anything unexpected from a damaged file
            last_output = "> png2p8 cart.p8.png" + CRLF + "error: %s" % e
            all_output += last_output
            stage = "png2p8"
    else:
        shutil.copyfile(full, cart_path)

    # v32lua options: the cart's API; --rate only when asked for; --title only when
    # the cart has no title of its own, so the fallback is the original name
    # instead of "cart"
    v32lua_args = ["--api", api]
    if not stage:
        if args.rate:
            v32lua_args += ["--rate", str(args.rate)]
        v32lua_args += cart_option_args(args)   # --fast-circles / --no-bezel when asked for
        titled = has_tic80_title(cart_path) if api == "tic80" else has_embedded_title(cart_path)
        if not titled:
            v32lua_args += ["--title", prefix + base]

    steps = [
        ("v32lua", v32lua, v32lua_args + [cart_file], "cart.asm"),
        ("assemble", assemble, ["cart.asm"], "cart.vbin"),
        ("packrom", packrom, ["cart.xml"], "cart.v32"),
    ]
    for step, exe, step_args, product in steps:
        if stage:
            break
        code, last_output = run_tool(exe, step_args, work_dir, args.timeout_sec)
        all_output += CRLF + last_output
        if code != 0 or not os.path.exists(os.path.join(work_dir, product)):
            stage = step

    if not stage:
        shutil.copyfile(os.path.join(work_dir, "cart.v32"), target)
        if os.path.exists(log):
            os.remove(log)
        return {"Cart": name, "Format": fmt, "Result": "OK", "FailedAt": "", "Error": ""}
    with open(log, "w", encoding="utf-8-sig", newline="") as fh:  # BOM + CRLF, like Set-Content
        fh.write(all_output + CRLF)
    return {"Cart": name, "Format": fmt, "Result": "FAILED", "FailedAt": stage, "Error": first_error(last_output)}


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    # Windows defaults for this machine; elsewhere the tools are looked up on the PATH
    default_v32lua = r"C:\github\v32lua\bin\v32lua.exe" if IS_WINDOWS else None
    default_devtools = r"C:\utils\vircon32\devtools" if IS_WINDOWS else None
    ap = argparse.ArgumentParser(description="Batch-convert PICO-8 carts to Vircon32 ROMs.",
                                 allow_abbrev=False)
    ap.add_argument("-sourcedir", "--source-dir", default=script_dir)
    ap.add_argument("-filter", "--filter", nargs="+", default=["*.p8", "*.p8.png", "*.tic"])
    ap.add_argument("-start", "--start", default="")
    ap.add_argument("-max", "--max", type=int, default=0)
    ap.add_argument("-v32lua", "--v32lua", default=default_v32lua,
                    help="path to the v32lua executable (default: %s)" % (default_v32lua or "v32lua on the PATH"))
    ap.add_argument("-devtools", "--devtools", default=default_devtools,
                    help="folder with assemble and packrom (default: %s)" % (default_devtools or "found on the PATH"))
    ap.add_argument("-timeoutsec", "--timeout-sec", type=int, default=120)
    ap.add_argument("-rate", "--rate", "-p8rate", "--p8rate", dest="rate", type=int,
                    choices=(11025, 22050, 44100), default=None,
                    help="sample rate of the sounds v32lua synthesizes from PICO-8 / TIC-80 carts "
                         "(default: not passed, v32lua uses 22050; -p8rate is the old name)")
    add_cart_options(ap)
    ap.add_argument("-skipexisting", "--skip-existing", action="store_true")
    ap.add_argument("-jobs", "--jobs", type=int, default=os.cpu_count() or 4,
                    help="carts built in parallel (default: number of CPU cores; 1 = one at a time)")
    ap.add_argument("-png2p8", "--png2p8", nargs=2, metavar=("PNG", "P8"),
                    help="only convert one PNG cart to a text .p8 and exit")
    args = ap.parse_args()

    if args.png2p8:
        png2p8(args.png2p8[0], args.png2p8[1])
        return 0

    if IS_WINDOWS:
        os.system("")  # enables ANSI colours in the Windows console
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    source_dir = full_path(args.source_dir)
    work_dir = os.path.join(source_dir, "work")
    out_dir = os.path.join(source_dir, "v32")
    log_dir = os.path.join(out_dir, "logs")

    v32lua = find_tool("v32lua", path=args.v32lua)
    assemble = find_tool("assemble", folder=args.devtools)
    packrom = find_tool("packrom", folder=args.devtools)
    for name, exe, where in (("v32lua", v32lua, args.v32lua),
                             ("assemble", assemble, args.devtools),
                             ("packrom", packrom, args.devtools)):
        if not exe:
            sys.exit("Tool not found: %s (looked in: %s)" % (name, where or "PATH"))
    for d in (work_dir, out_dir, log_dir):
        os.makedirs(d, exist_ok=True)

    found = {}
    for name in os.listdir(source_dir):
        full = os.path.join(source_dir, name)
        if not os.path.isfile(full) or not CART_EXT.search(name):
            continue
        if any(fnmatch.fnmatch(name.lower(), pat.lower()) for pat in args.filter):
            found[full] = name
    def cart_order(x, y):
        return compare(cart_base(x[1]), cart_base(y[1])) or compare(x[1], y[1])
    carts = sorted(found.items(), key=functools.cmp_to_key(cart_order))

    # Game.p8 and Game.p8.png would both produce v32\Game.v32: keep the .p8
    seen = {}
    unique = []
    for full, name in carts:
        b = cart_base(name).lower()  # PowerShell hashtables are case-insensitive
        if b in seen:
            print("%sSkipping %s: same name as %s%s" % (YELLOW, name, seen[b], RESET))
        else:
            seen[b] = name
            unique.append((full, name))
    carts = unique

    if args.start:
        idx = next((k for k, (_, name) in enumerate(carts)
                    if name.lower() == args.start.lower()
                    or cart_base(name).lower() == cart_base(args.start).lower()), -1)
        if idx < 0:
            sys.exit("Start cart not found: %s" % args.start)
        carts = carts[idx:]

    # -skipexisting / -max first, so -max counts carts that are really built
    skipped = 0
    if args.skip_existing:
        todo = [(f, n) for f, n in carts if not os.path.exists(os.path.join(out_dir, cart_base(n) + ".v32"))]
        skipped = len(carts) - len(todo)
        carts = todo
    if args.max > 0:
        carts = carts[:args.max]

    total = len(carts)
    results = []
    ok = fail = 0
    start_time = time.time()
    if args.jobs > 1:
        print("Building %d carts, %d parallel" % (total, args.jobs))

    # every parallel job gets its own work folder (work/run<pid>/j<n>), so jobs -- and
    # two runs in the same folder -- never clear each other's files
    work_root = os.path.join(work_dir, "run%d" % os.getpid())
    lock = threading.Lock()
    free_dirs = [os.path.join(work_root, "j%d" % k) for k in range(args.jobs)]
    done = [0]

    def worker(item):
        full, name = item
        with lock:
            job_dir = free_dirs.pop()
        try:
            os.makedirs(job_dir, exist_ok=True)
            clear_dir(job_dir)
            return build_cart(full, name, job_dir, (v32lua, assemble, packrom), args, out_dir, log_dir)
        finally:
            try:
                clear_dir(job_dir)
            except OSError:
                pass
            with lock:
                free_dirs.append(job_dir)   # always hand the folder back

    with ThreadPoolExecutor(max(1, args.jobs)) as ex:
        futures = {ex.submit(worker, c): c for c in carts}
        for fut in as_completed(futures):
            _, name = futures[fut]
            try:
                res = fut.result()
            except Exception as e:   # keep going; report the cart
                res = {"Cart": name, "Format": "", "Result": "FAILED", "FailedAt": "script", "Error": repr(e)}
            results.append(res)
            done[0] += 1
            if res["Result"] == "OK":
                ok += 1
                status = GREEN + "OK" + RESET
            else:
                fail += 1
                status = "%sFAILED (%s) %s%s" % (RED, res["FailedAt"], res["Error"], RESET)
            with lock:
                stats = "%sO:%d%s %sF:%d%s" % (GREEN, ok, RESET, RED, fail, RESET)   # built OK / failed so far
                print("[%d/%d %s] %s ... %s" % (done[0], total, stats, name, status), flush=True)

    shutil.rmtree(work_root, ignore_errors=True)

    # Merge with earlier runs (e.g. batches via -start/-max); this run's result wins per cart
    csv_path = os.path.join(out_dir, "results.csv")
    fields = ["Cart", "Format", "Result", "FailedAt", "Error"]
    merged = {}
    if os.path.exists(csv_path):
        with open(csv_path, newline="", encoding="utf-8-sig") as fh:
            for row in csv.DictReader(fh):
                merged[row["Cart"].lower()] = row
    for r in results:
        merged[r["Cart"].lower()] = r
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, quoting=csv.QUOTE_ALL, extrasaction="ignore")
        w.writeheader()
        for row in sorted(merged.values(), key=functools.cmp_to_key(lambda a, b: compare(a["Cart"], b["Cart"]))):
            w.writerow(row)

    elapsed = int(time.time() - start_time)
    print()
    print("Done in %02d:%02d:%02d: %d OK, %d failed, %d skipped"
          % (elapsed // 3600, elapsed // 60 % 60, elapsed % 60, ok, fail, skipped))
    groups = {}
    for r in results:
        if r["Result"] == "FAILED":
            key = "%s, %s" % (r["FailedAt"], r["Format"])
            groups[key] = groups.get(key, 0) + 1
    for key, count in groups.items():
        print("  failed at %s: %d" % (key, count))
    print("Results: %s" % csv_path)
    print("Logs:    %s" % log_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
