#!/usr/bin/env python3
"""
Take PNG screenshots of built carts, headless.

Each cart that has a ROM in v32/ (or every cart with -all) is rebuilt in its own
work folder (like test_v32.py) and run once on v32run with GPU logging (-g):

  frame -title (default 180 = 3 s)  title screen shot, no button pressed yet
  frame -press (default 240)        the usual start buttons are pressed once:
                                    A, then B half a second later (PICO-8's O / X
                                    and TIC-80's A / B are Vircon32 A / B)
  frame -game  (default 540 = 9 s)  in-game shot, no further input

The logged GPU commands are then redrawn into 640x360 PNGs: region draws with
zoom, mirroring, rotation, colour multiply and alpha / add / subtract blending,
using the cart's own textures and the Vircon32 BIOS font (for text printed with
the BIOS font; taken from StandardBios.v32).

Screens that stay up for several frames are handled: the picture is rebuilt
from the last full clear before the chosen frame. A shot that comes out as one
flat colour (a fade-in, say) is retried: the title shot at other frames before
the press, the game shot 2 s later, up to -blankretries times. A cart that
crashes shows its panic / error screen (the blue CPU error screen is redrawn
with the BIOS's own texts, since v32run has no BIOS to show it).

Output, named like the ROM (<name>.v32):
  v32/screenshots/title/<name>.png
  v32/screenshots/game/<name>.png
Works for PICO-8 (.p8 / .p8.png) and TIC-80 (.tic) carts. Needs Pillow.

Usage:
  python screenshot_v32.py                        # all carts with a ROM in v32/
  python screenshot_v32.py -start "Celeste" -max 10 -skipexisting
  python screenshot_v32.py -title 120 -press 200 -game 900
  python screenshot_v32.py -notitle               # only the in-game shots
  python screenshot_v32.py -scale 2               # 1280x720 PNGs
  python screenshot_v32.py -all -list carts.txt   # exactly these carts (one file name per line)

The picture is a reconstruction from the GPU command log, not an emulator
capture: it is close for normal sprite/text drawing, but not pixel-exact.
"""

import argparse
import functools
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

sys.dont_write_bytecode = True  # no __pycache__ next to the carts
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_v32 as b     # noqa: E402
import test_v32 as t      # noqa: E402

try:
    from PIL import Image, ImageChops
except ImportError:
    sys.exit("Pillow is needed: python -m pip install pillow")

SCREEN_W, SCREEN_H = 640, 360
DRAW_RE = re.compile(r"^F(\d+) GPU (\w+) tex=(-?\d+) reg=(-?\d+) pt=\((-?\d+),(-?\d+)\) sx=(\S+) sy=(\S+) "
                     r"ang=(\S+) mul=([0-9A-F]+) blend=([0-9A-F]+) src=\((-?\d+),(-?\d+)\)-\((-?\d+),(-?\d+)\) "
                     r"hot=\((-?\d+),(-?\d+)\) SCREEN=\((\S+),(\S+) (\S+)x(\S+)\)")
CLEAR_RE = re.compile(r"^F(\d+) GPU ClearScreen color=([0-9A-F]+)")
FRAME_RE = re.compile(r"^F(\d+) GPU ")


# ----------------------------------------------------------------- textures

def load_vtex(data, offset=0):
    if data[offset:offset + 8] != b"V32-VTEX":
        raise ValueError("not a V32-VTEX texture")
    w, h = struct.unpack("<II", data[offset + 8:offset + 16])
    return Image.frombytes("RGBA", (w, h), data[offset + 16:offset + 16 + w * h * 4])


def load_bios_font(path):
    """The BIOS texture from StandardBios.v32; its magenta guide lines made transparent."""
    if not path or not os.path.isfile(path):
        return None
    with open(path, "rb") as fh:
        data = fh.read()
    i = data.find(b"V32-VTEX")
    if i < 0:
        return None
    tex = load_vtex(data, i)
    r, g, bl, a = tex.split()
    magenta = Image.eval(r, lambda v: 255 if v == 255 else 0)
    magenta = ImageChops.multiply(magenta, Image.eval(g, lambda v: 255 if v == 0 else 0))
    magenta = ImageChops.multiply(magenta, Image.eval(bl, lambda v: 255 if v == 255 else 0))
    a = ImageChops.subtract(a, magenta)
    return Image.merge("RGBA", (r, g, bl, a))


def bios_region(reg):
    """BIOS font glyphs: 256 characters of 10x20 in rows of 32, from (1,22); hotspot top-left."""
    if 0 <= reg < 256:
        x, y = 1 + (reg % 32) * 10, 22 + (reg // 32) * 20
        return x, y, x + 9, y + 19, x, y
    return None


def cart_textures(work_dir):
    """The cart's textures in the order of the <textures> list in cart.xml (texture 0 first)."""
    texs = []
    xml = os.path.join(work_dir, "cart.xml")
    if not os.path.exists(xml):
        return texs
    with open(xml, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    section = re.search(r"<textures>(.*?)</textures>", text, re.S)
    for path in re.findall(r'<texture\s+path="([^"]+)"', section.group(1) if section else ""):
        try:
            with open(os.path.join(work_dir, path), "rb") as fh:
                texs.append(load_vtex(fh.read()))
        except (OSError, ValueError):
            texs.append(None)
    return texs


# ------------------------------------------------------------------- render

def word_color(word):
    v = int(word, 16)
    return (v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255)


def paste(canvas, piece, x, y, blend):
    """Draws piece at (x, y) with Vircon32 blending (0x20 alpha, 0x21 add, 0x22 subtract), clipped."""
    x0, y0 = max(x, 0), max(y, 0)
    x1, y1 = min(x + piece.width, canvas.width), min(y + piece.height, canvas.height)
    if x1 <= x0 or y1 <= y0:
        return
    piece = piece.crop((x0 - x, y0 - y, x1 - x, y1 - y))
    if blend == 0x20:
        canvas.alpha_composite(piece, (x0, y0))
        return
    base = canvas.crop((x0, y0, x1, y1))
    alpha = piece.getchannel("A")
    rgb = ImageChops.multiply(piece.convert("RGB"), Image.merge("RGB", (alpha, alpha, alpha)))
    if blend == 0x21:
        out = ImageChops.add(base.convert("RGB"), rgb)
    else:
        out = ImageChops.subtract(base.convert("RGB"), rgb)
    out.putalpha(base.getchannel("A"))
    canvas.paste(out, (x0, y0))


_PIECES = {}   # prepared (cut, mirrored, scaled, tinted) texture pieces, see draw_command
_PIECES_BYTES = [0]            # their total size, so the cache can't grow without bound
PIECES_MAX, PIECES_MAX_BYTES = 4096, 128 * 1024 * 1024
CLIP_OVER = SCREEN_W * SCREEN_H   # draws needing a bigger image than the screen are clipped


def draw_clipped(canvas, source, region, fx, fy, angle, px, py, hot_x, hot_y, w, h, mul, blend):
    """Draws only the part of a (zoomed / mirrored / rotated) region that lands on the screen:
    every visible screen pixel is mapped straight back into the texture with one affine
    transform, so the image made is never bigger than the screen."""
    x0, y0, x1, y1 = region
    c, s = math.cos(angle), math.sin(angle)
    # the piece's corners on screen (rotation about the hotspot, which lands on pt)
    xs, ys = [], []
    for qx, qy in ((0, 0), (w, 0), (0, h), (w, h)):
        dx, dy = qx - hot_x, qy - hot_y
        xs.append(px + c * dx - s * dy)
        ys.append(py + s * dx + c * dy)
    bx0, by0 = max(0, math.floor(min(xs))), max(0, math.floor(min(ys)))
    bx1, by1 = min(SCREEN_W, math.ceil(max(xs))), min(SCREEN_H, math.ceil(max(ys)))
    if bx1 <= bx0 or by1 <= by0:
        return   # entirely off screen
    src = source.crop((x0, y0, x1 + 1, y1 + 1))
    # a mirrored piece starts at the region's far edge. (Where a pixel center falls exactly
    # on a texel boundary, this and the fast path may pick different sides of the tie.)
    ux0 = 0.0 if fx > 0 else float(x1 - x0 + 1)
    vy0 = 0.0 if fy > 0 else float(y1 - y0 + 1)
    # output pixel (X, Y) = screen (bx0 + X, by0 + Y) -> piece q = hot + R^-1 (screen - pt)
    # -> texture u = ux0 + q.x / fx, v = vy0 + q.y / fy   (linear in X and Y)
    ox, oy = bx0 - px, by0 - py
    coeffs = (c / fx, s / fx, ux0 + (hot_x + c * ox + s * oy) / fx,
              -s / fy, c / fy, vy0 + (hot_y - s * ox + c * oy) / fy)
    piece = src.transform((bx1 - bx0, by1 - by0), Image.Transform.AFFINE, coeffs,
                          resample=Image.Resampling.NEAREST, fillcolor=(0, 0, 0, 0))
    if mul != (255, 255, 255, 255):
        piece = ImageChops.multiply(piece, Image.new("RGBA", piece.size, mul))
    paste(canvas, piece, bx0, by0, blend)


def apply_lines(canvas, lines, texs, bios):
    """Draws one frame's GPU log lines onto canvas; a ClearScreen starts a new canvas.
    -> the canvas to keep drawing on."""
    for line in lines:
        m = CLEAR_RE.match(line)
        if m:
            canvas = Image.new("RGBA", (SCREEN_W, SCREEN_H), word_color(m.group(2))[:3] + (255,))
            continue
        m = DRAW_RE.match(line)
        if m:
            draw_command(canvas, m, texs, bios)
    return canvas


def draw_command(canvas, m, texs, bios):
    kind = m.group(2)
    tex, reg = int(m.group(3)), int(m.group(4))
    px, py = int(m.group(5)), int(m.group(6))
    zoom = kind in ("DrawZoomed", "DrawRotozoomed")
    fx, fy = (float(m.group(7)), float(m.group(8))) if zoom else (1.0, 1.0)
    angle = float(m.group(9)) if kind in ("DrawRotated", "DrawRotozoomed") else 0.0
    mul, blend = word_color(m.group(10)), int(m.group(11), 16)
    if not all(math.isfinite(v) for v in (fx, fy, angle)):
        return   # NaN / infinite scale or angle (a cart or v32lua bug): nothing sensible to draw
    if abs(px) > 1 << 20 or abs(py) > 1 << 20:
        return   # position from a NaN converted to an integer (-2147483648): off any screen

    if tex < 0:
        region = bios_region(reg)
        if region is None or bios is None:
            return
        x0, y0, x1, y1, hx, hy = region
        source = bios
    else:
        if tex >= len(texs) or texs[tex] is None:
            return
        x0, y0, x1, y1 = (int(m.group(i)) for i in range(12, 16))
        hx, hy = int(m.group(16)), int(m.group(17))
        source = texs[tex]
    if x1 < x0 or y1 < y0 or fx == 0 or fy == 0:
        return

    w, h = abs(fx) * (x1 - x0 + 1), abs(fy) * (y1 - y0 + 1)
    if not (math.isfinite(w) and math.isfinite(h)) or w < 0.5 or h < 0.5:
        return   # overflowing, or shrunk below a pixel: invisible
    # where the hotspot lands inside the (mirrored, scaled) piece
    hot_x = fx * (hx - x0) if fx > 0 else -fx * (x1 + 1 - hx)
    hot_y = fy * (hy - y0) if fy > 0 else -fy * (y1 + 1 - hy)

    # Large draws (a zoomed-up sprite, a giant rectangle) would need an image far bigger than
    # the screen -- over a gigabyte in extreme cases. Those are clipped instead: only the part
    # that lands on the 640x360 screen is rendered, so they look the same but stay small.
    if angle:
        work = (2 * max(math.hypot(cx - hot_x, cy - hot_y) for cx in (0, w) for cy in (0, h))) ** 2
    else:
        work = w * h
    if work > CLIP_OVER:
        draw_clipped(canvas, source, (x0, y0, x1, y1), fx, fy, angle, px, py, hot_x, hot_y, w, h, mul, blend)
        return

    W, H = int(round(w)), int(round(h))
    # tile maps draw the same few regions thousands of times: reuse the prepared piece.
    # The cache keeps a reference to the source texture, so its id() can't be reused.
    key = (id(source), x0, y0, x1, y1, W, H, fx < 0, fy < 0, mul)
    hit = _PIECES.get(key)
    if hit is not None and hit[0] is source:
        piece = hit[1]
    else:
        piece = source.crop((x0, y0, x1 + 1, y1 + 1))
        if fx < 0:
            piece = piece.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if fy < 0:
            piece = piece.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        if piece.size != (W, H):
            piece = piece.resize((W, H), Image.Resampling.NEAREST)
        if mul != (255, 255, 255, 255):
            piece = ImageChops.multiply(piece, Image.new("RGBA", piece.size, mul))
        if len(_PIECES) >= PIECES_MAX or _PIECES_BYTES[0] > PIECES_MAX_BYTES:
            _PIECES.clear()
            _PIECES_BYTES[0] = 0
        _PIECES[key] = (source, piece)
        _PIECES_BYTES[0] += W * H * 4

    if angle:
        # rotate around the hotspot: centre it in a square, rotate, place the centre at pt
        r = int(math.ceil(max(math.hypot(cx - hot_x, cy - hot_y) for cx in (0, W) for cy in (0, H)))) + 1
        big = Image.new("RGBA", (2 * r, 2 * r), (0, 0, 0, 0))
        big.paste(piece, (int(round(r - hot_x)), int(round(r - hot_y))))
        piece = big.rotate(-math.degrees(angle), resample=Image.Resampling.NEAREST)
        paste(canvas, piece, px - r, py - r, blend)
    else:
        paste(canvas, piece, int(round(px - hot_x)), int(round(py - hot_y)), blend)


def is_clear_frame(lines):
    """A frame that repaints the whole picture: starts with ClearScreen, or with a big
    opaque rectangle (how PICO-8 / TIC-80 cls() is drawn)."""
    for line in lines:
        if CLEAR_RE.match(line):
            return True
        m = DRAW_RE.match(line)
        if m:
            area = float(m.group(20)) * float(m.group(21))
            return area >= 0.25 * SCREEN_W * SCREEN_H and int(m.group(11), 16) == 0x20
    return False


def render_frame(frames, target, texs, bios, max_replay=600):
    """Picture on screen at frame `target`: replay from the last clear up to the last drawing frame."""
    drawn = sorted(f for f in frames if f <= target)
    if not drawn:
        return None, None
    last = drawn[-1]
    start_idx = len(drawn) - 1
    while start_idx > 0 and not is_clear_frame(frames[drawn[start_idx]]) and \
            last - drawn[start_idx - 1] <= max_replay:
        start_idx -= 1
    canvas = Image.new("RGBA", (SCREEN_W, SCREEN_H), (0, 0, 0, 255))
    for f in drawn[start_idx:]:
        canvas = apply_lines(canvas, frames[f], texs, bios)
    return canvas.convert("RGB"), last


BIOS_ERRORS = [   # CPU error code -> the BIOS's error screen texts (from StandardBios.v32)
    ("ERROR: INVALID MEMORY READ", "Program attempted to read from a memory address",
     "that does not exist or is in a write-only device."),
    ("ERROR: INVALID MEMORY WRITE", "Program attempted to write on a memory address",
     "that does not exist or is in a read-only device."),
    ("ERROR: INVALID PORT READ", "Program attempted to read from a port number",
     "that does not exist or is set as write-only."),
    ("ERROR: INVALID PORT WRITE", "Program attempted to write on a port number",
     "that does not exist or is set as read-only."),
    ("ERROR: STACK OVERFLOW", "Program pushed too many values in the stack",
     "and available RAM memory was exhausted."),
    ("ERROR: STACK UNDERFLOW", "Program popped too many values from the stack",
     "and all data stored in stack was exhausted."),
    ("ERROR: DIVISION BY ZERO", "Program attempted to perform a division or",
     "modulus operation where the divisor was zero."),
    ("ERROR: ARC COSINE OUT OF RANGE", "Program attempted to perform an arc cosine",
     "operation when the argument was not in [-1,+1]."),
    ("ERROR: ARC TANGENT NOT DEFINED", "Program attempted to perform an arc tangent",
     "operation when both of the arguments were 0."),
    ("ERROR: LOGARITHM OUT OF RANGE", "Program attempted to perform a logarithm",
     "operation when the argument is not positive."),
    ("ERROR: POWER HAS NO REAL SOLUTION", "Program attempted to perform a power operation",
     "when base was negative and exponent non integer."),
]


def draw_text(canvas, bios, x, y, text, color):
    for i, ch in enumerate(text):
        region = bios_region(ord(ch) if ord(ch) < 256 else ord("?"))
        glyph = bios.crop((region[0], region[1], region[2] + 1, region[3] + 1))
        glyph = ImageChops.multiply(glyph, Image.new("RGBA", glyph.size, color + (255,)))
        paste(canvas, glyph, x + i * 10, y, 0x20)


def bios_error_screen(bios, code, ip, instr, imm):
    """The blue hardware error screen the Vircon32 BIOS shows (v32run has no BIOS to draw it)."""
    blue, yellow, white, red = (47, 63, 141), (255, 255, 64), (255, 255, 255), (255, 120, 120)
    canvas = Image.new("RGBA", (SCREEN_W, SCREEN_H), blue + (255,))
    title, line1, line2 = BIOS_ERRORS[code] if 0 <= code < len(BIOS_ERRORS) else (
        "UNKNOWN ERROR", "Program caused a hardware error with an error",
        "code that was not recognized by the BIOS.")
    if bios is None:
        return canvas.convert("RGB")
    draw_text(canvas, bios, 44, 38, title, yellow)
    canvas.paste(Image.new("RGBA", (SCREEN_W, 2), yellow + (255,)), (0, 62))
    draw_text(canvas, bios, 44, 97, line1, white)
    draw_text(canvas, bios, 44, 120, line2, white)
    draw_text(canvas, bios, 44, 166, "Instruction Pointer = 0x%08X" % ip, red)
    draw_text(canvas, bios, 44, 189, "Instruction = 0x%08X" % instr, red)
    draw_text(canvas, bios, 44, 212, "Immediate Value = 0x%08X" % imm, red)
    return canvas.convert("RGB")


def is_blank(img):
    """One flat colour (every channel's min == max)."""
    return all(lo == hi for lo, hi in img.getextrema())


# --------------------------------------------------------------------- cart

def shot_plan(args):
    """[(suffix, [candidate frames])]: the first candidate that isn't one flat colour is used."""
    plan = []
    if not args.notitle:
        # title: the chosen frame, then later / earlier ones, all before the button press
        later = [f for f in range(args.title + 20, args.press, 20)]
        earlier = [f for f in (args.title - 60, args.title - 120) if f > 0]
        plan.append(("title", ([args.title] + later + earlier)[:args.blank_retries + 1]))
    if not args.nogame:
        plan.append(("game", [args.game + k * 120 for k in range(args.blank_retries + 1)]))
    return plan


def press_script(args):
    """The usual start buttons once each: A (PICO-8 O, TIC-80 A), then B (PICO-8 X, TIC-80 B)."""
    p, h = args.press, 6
    return "%d:A=1;%d:A=0;%d:B=1;%d:B=0" % (p, p + h, p + 30, p + 30 + h)


def shoot_cart(full, name, work_dir, tools, bios, args, out_dir):
    base = b.cart_base(name)
    cart_file, fmt, err = t.build_for_test(full, name, work_dir, tools, args.timeout_sec,
                                           b.cart_option_args(args))
    if err:
        return "BUILD_FAILED", err
    texs = cart_textures(work_dir)
    plan = shot_plan(args)
    last_frame = max(f for _, cands in plan for f in cands) + 1
    cmd = [tools["v32run"], "cart.vbin", "-f", str(last_frame), "-q", "-g"]
    if not args.nogame:
        cmd += ["-p", press_script(args)]
    env = dict(os.environ, V32_FIXED_TIME="1")
    log_path = os.path.join(work_dir, "cart.run")
    try:
        with open(log_path, "wb") as fh:
            subprocess.run(cmd, cwd=work_dir, stdout=fh, stderr=subprocess.STDOUT, timeout=args.timeout_sec,
                           env=env, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except subprocess.TimeoutExpired:
        return "TIMEOUT", "v32run took over %d s" % args.timeout_sec

    frames = {}
    status, hwerror = "", None
    with open(log_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = FRAME_RE.match(line)
            if m:
                frames.setdefault(int(m.group(1)), []).append(line)
            elif line.startswith("STATUS "):
                status = line.split()[1]
                m = re.search(r"HWERROR code=(\d+) ip=([0-9A-F]+) instr=([0-9A-F]+) imm=([0-9A-F]+) frames=(\d+)", line)
                if m:   # CPU error at that frame: from then on the BIOS error screen is shown
                    hwerror = (int(m.group(5)), bios_error_screen(bios, int(m.group(1)), int(m.group(2), 16),
                                                                  int(m.group(3), 16), int(m.group(4), 16)))
    if not frames and not hwerror:
        return "NO_DRAWING", "the cart drew nothing (%s)" % status

    saved = []
    for suffix, candidates in plan:
        img, used = None, None
        for target in candidates:
            if hwerror and target >= hwerror[0]:
                img, used = hwerror[1], hwerror[0]
                break
            shot, shot_frame = render_frame(frames, target, texs, bios)
            if shot is None:
                continue
            img, used = shot, shot_frame
            if not is_blank(shot):
                break
        if img is None:
            saved.append("%s: nothing drawn yet" % suffix)
            continue
        if args.scale != 1:
            img = img.resize((SCREEN_W * args.scale, SCREEN_H * args.scale), Image.Resampling.NEAREST)
        os.makedirs(os.path.join(out_dir, suffix), exist_ok=True)
        img.save(os.path.join(out_dir, suffix, base + ".png"))
        saved.append("%s f%d%s" % (suffix, used, " (blank)" if is_blank(img) else ""))
    if not any("nothing drawn" not in s for s in saved):
        return "NO_DRAWING", "nothing drawn by frame %d (%s)" % (last_frame - 1, status)
    note = "" if status in ("FRAMES_EXHAUSTED", "") else " [run ended: %s]" % status
    return "OK", ", ".join(saved) + note


# ---- worker processes: each loads the BIOS font once and works in its own folder
_WORKER = {}


def _init_worker(tools, args, out_dir, work_root, bios_path):
    work_dir = os.path.join(work_root, "p%d" % os.getpid())
    os.makedirs(work_dir, exist_ok=True)
    _WORKER.update(tools=tools, args=args, out_dir=out_dir, work_dir=work_dir,
                   bios=load_bios_font(bios_path))


def _shoot_one(item):
    """Shoots one cart in this worker process. -> (result, detail); never raises."""
    full, name = item
    w = _WORKER
    try:
        b.clear_dir(w["work_dir"])
    except OSError:
        pass
    try:
        return shoot_cart(full, name, w["work_dir"], w["tools"], w["bios"], w["args"], w["out_dir"])
    except Exception as e:
        return "SCRIPT_ERROR", repr(e)
    finally:
        try:
            b.clear_dir(w["work_dir"])
        except OSError:
            pass


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="Headless PNG screenshots of built Vircon32 carts.", allow_abbrev=False)
    ap.add_argument("-sourcedir", "--source-dir", default=here)
    ap.add_argument("-filter", "--filter", nargs="+", default=["*.p8", "*.p8.png", "*.tic"])
    ap.add_argument("-start", "--start", default="")
    ap.add_argument("-max", "--max", type=int, default=0)
    ap.add_argument("-list", "--list", metavar="FILE",
                    help="only the carts named in this text file, one cart file name per line (as in the CSVs)")
    ap.add_argument("-all", "--all", action="store_true", help="also carts without a ROM in v32/")
    ap.add_argument("-title", "--title", type=int, default=180,
                    help="frame of the title screen shot, 60 = 1 s (default 180)")
    ap.add_argument("-press", "--press", type=int, default=240,
                    help="frame where A, then B (0.5 s later) are pressed once (default 240)")
    ap.add_argument("-game", "--game", type=int, default=540, help="frame of the in-game shot (default 540)")
    ap.add_argument("-notitle", "--notitle", action="store_true", help="no title screen shot")
    ap.add_argument("-nogame", "--nogame", action="store_true", help="no in-game shot (and no button presses)")
    ap.add_argument("-blankretries", "--blank-retries", type=int, default=3,
                    help="if a shot is one flat colour, try other frames up to N times (default 3)")
    ap.add_argument("-scale", "--scale", type=int, default=1, help="enlarge the PNG N times (default 1)")
    ap.add_argument("-skipexisting", "--skip-existing", action="store_true")
    ap.add_argument("-jobs", "--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("-timeoutsec", "--timeout-sec", type=int, default=120)
    b.add_cart_options(ap)   # -fastcircles / -nobezel: shoot the same build as the ROMs
    ap.add_argument("-outdir", "--out-dir", default=None,
                    help="default: v32/screenshots (with title/ and game/ subfolders)")
    ap.add_argument("-v32lua", "--v32lua", default=r"C:\github\v32lua\bin\v32lua.exe" if b.IS_WINDOWS else None)
    ap.add_argument("-devtools", "--devtools", default=r"C:\utils\vircon32\devtools" if b.IS_WINDOWS else None)
    ap.add_argument("-v32run", "--v32run", default=r"C:\github\v32lua\tools\headless\v32run.exe" if b.IS_WINDOWS else None)
    ap.add_argument("-bios", "--bios", default=r"C:\github\ComputerSoftware\SimplifiedEmulator\Data\Bios\StandardBios.v32"
                    if b.IS_WINDOWS else None, help="StandardBios.v32, for text drawn with the BIOS font")
    args = ap.parse_args()
    if args.notitle and args.nogame:
        ap.error("-notitle and -nogame together leave nothing to capture")
    if not args.nogame and not (args.press < args.game):
        ap.error("-press must come before -game")
    if not args.notitle and not args.nogame and not (0 < args.title < args.press):
        ap.error("-title must come before -press")

    if b.IS_WINDOWS:
        os.system("")
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    tools = {"v32lua": b.find_tool("v32lua", path=args.v32lua),
             "assemble": b.find_tool("assemble", folder=args.devtools)}
    v32run = b.find_tool("v32run", path=args.v32run) if args.v32run else b.find_tool("v32run")
    if not v32run and tools["v32lua"]:
        v32run = b.find_tool("v32run", folder=os.path.join(os.path.dirname(tools["v32lua"]), "..", "tools", "headless"))
    tools["v32run"] = v32run
    for name, exe in tools.items():
        if not exe:
            sys.exit("Tool not found: %s" % name)
    bios = load_bios_font(b.full_path(args.bios) if args.bios else None)
    if bios is None:
        print("%sBIOS not found (-bios): text drawn with the BIOS font will be missing%s" % (b.YELLOW, b.RESET))

    source_dir = b.full_path(args.source_dir)
    rom_dir = os.path.join(source_dir, "v32")
    out_dir = b.full_path(args.out_dir) if args.out_dir else os.path.join(rom_dir, "screenshots")
    os.makedirs(out_dir, exist_ok=True)
    work_parent = os.path.join(source_dir, "work_shot")
    work_root = os.path.join(work_parent, "run%d" % os.getpid())

    # same cart list and order as build_v32.py / test_v32.py
    found = {}
    for name in os.listdir(source_dir):
        full = os.path.join(source_dir, name)
        if os.path.isfile(full) and b.CART_EXT.search(name) and \
                any(b.fnmatch.fnmatch(name.lower(), p.lower()) for p in args.filter):
            found[full] = name
    carts = sorted(found.items(), key=functools.cmp_to_key(
        lambda x, y: b.compare(b.cart_base(x[1]), b.cart_base(y[1])) or b.compare(x[1], y[1])))
    seen, unique = set(), []
    for full, name in carts:
        key = b.cart_base(name).lower()
        if key not in seen:
            seen.add(key)
            unique.append((full, name))
    carts = unique
    if args.start:
        idx = next((k for k, (_, n) in enumerate(carts) if n.lower() == args.start.lower()
                    or b.cart_base(n).lower() == b.cart_base(args.start).lower()), -1)
        if idx < 0:
            sys.exit("Start cart not found: %s" % args.start)
        carts = carts[idx:]
    if not args.all:
        carts = [(f, n) for f, n in carts if os.path.exists(os.path.join(rom_dir, b.cart_base(n) + ".v32"))]
    if args.list:
        with open(args.list, encoding="utf-8-sig") as fh:
            wanted = {line.strip().lower() for line in fh if line.strip()}
        carts = [(f, n) for f, n in carts if n.lower() in wanted]
        if len(carts) < len(wanted):
            print("%s%d carts from -list not found in %s%s" % (b.YELLOW, len(wanted) - len(carts), source_dir, b.RESET))
    if args.skip_existing:
        def have(n):
            base = b.cart_base(n)
            return all(os.path.exists(os.path.join(out_dir, suffix, base + ".png"))
                       for suffix, _ in shot_plan(args))
        carts = [(f, n) for f, n in carts if not have(n)]
    if args.max > 0:
        carts = carts[:args.max]
    total = len(carts)
    shots = []
    if not args.notitle:
        shots.append("title at frame %d" % args.title)
    if not args.nogame:
        shots.append("A+B pressed at frame %d, game at frame %d" % (args.press, args.game))
    print("Screenshots of %d carts: %s; %d parallel" % (total, "; ".join(shots), args.jobs))

    counts, done = {}, [0]
    start_time = time.time()
    os.makedirs(work_root, exist_ok=True)

    # separate worker processes (not threads): rebuilding frames is Python work, and
    # processes let it run on all cores at once instead of taking turns on one.
    # A worker that dies (e.g. out of memory) only costs its own cart: see run_with_recovery.
    bios_path = b.full_path(args.bios) if args.bios else None

    def new_pool(n):
        return ProcessPoolExecutor(n, initializer=_init_worker, initargs=(tools, args, out_dir, work_root, bios_path))

    def handle(item, value):
        result, detail = value
        counts[result] = counts.get(result, 0) + 1
        done[0] += 1
        colour = b.GREEN if result == "OK" else b.YELLOW
        print("[%d/%d] %s ... %s%s %s%s" % (done[0], total, item[1], colour, result, detail, b.RESET), flush=True)

    b.run_with_recovery(carts, args.jobs, new_pool, _shoot_one, handle,
                        lambda item, message: ("SCRIPT_ERROR", message))

    shutil.rmtree(work_root, ignore_errors=True)
    try:
        os.rmdir(work_parent)
    except OSError:
        pass
    elapsed = int(time.time() - start_time)
    print()
    print("Done in %02d:%02d:%02d: %s" % (elapsed // 3600, elapsed // 60 % 60, elapsed % 60,
                                          ", ".join("%d %s" % (v, k) for k, v in sorted(counts.items()))))
    print("Screenshots: %s" % out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
