#!/usr/bin/env python3
"""
Smoke-test built carts for runtime crashes, headless, with random button mashing.

For each cart that has a ROM in v32/ (or every cart with -all), the cart is
rebuilt in its own work folder with debug info (v32lua -g, assemble -g program)
and run on v32run -- the official Vircon32 CPU core with logging stand-ins for
the GPU, SPU and gamepad (tools/headless in the v32lua repo). Each cart gets
-runs runs of -frames frames with a different random pad script (every button
but Start, which opens v32lua's PICO-8 pause screen), and the first failure is
reported:

  PANIC       the red "V32LUA PANIC" screen (a v32lua runtime error handler was
              reached: calling a non-function, indexing a non-table, out of memory, ...)
  CPU_ERROR   the blue Vircon32 hardware error screen (invalid port write,
              invalid memory read, division error, stack overflow, ...)
  HALT        the program stopped (HLT) without an error
  TIMEOUT     v32run itself took longer than -timeoutsec
  BUILD_FAILED  the cart no longer compiles/assembles with the current tools
  BLACK_SCREEN  (with -blank) no crash, but the game area stayed black -- or one
              flat colour -- in every sampled frame of run 1
  OK          all runs finished all frames

-blank rebuilds a frame every -blankstep frames (default: every second) from
run 1's GPU log, with screenshot_v32.py's renderer, and looks only at the game's
own screen area: PICO-8's 352x352 square at (144,4), so v32lua's side bezels
don't count, and TIC-80's 630x357 area at (0,0). Needs Pillow.

Works for PICO-8 (.p8 / .p8.png) and TIC-80 (.tic) carts alike.

For errors, the Lua function and the source line are looked up from the debug
files: for PICO-8 the line in the cart's text .p8 (see build_v32.py -png2p8),
for TIC-80 the line in the cart's Lua code.

Results: v32/test_results.csv (merged across runs, like results.csv) and
v32/test_logs/<name>.log for every cart that did not pass.

Usage:
  python test_v32.py                         # all carts that have a ROM in v32/
  python test_v32.py -max 20 -start "Celeste"
  python test_v32.py -frames 3600 -runs 5    # longer / more runs per cart
  python test_v32.py -jobs 4                 # parallel carts (default: CPU count)
  python test_v32.py -all                    # also carts without a ROM
  python test_v32.py -blank                  # also detect carts that only show a black screen

Needs build_v32.py in the same folder, and v32run (build it with
tools/headless/build.sh from the v32lua repo). On Windows it defaults to
C:\\github\\v32lua\\tools\\headless\\v32run.exe; elsewhere v32run on the PATH,
or next to v32lua in ../tools/headless/.
"""

import argparse
import bisect
import csv
import functools
import os
import random
import re
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

sys.dont_write_bytecode = True  # no __pycache__ next to the carts
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_v32 as b  # noqa: E402

PANIC_LABELS = {
    "__runtime_error_not_callable": "attempt to call a non-function value",
    "__runtime_error_not_table": "attempt to index a non-table value",
    "__runtime_error_hash_overflow": "table hash overflow",
    "__oom_handler": "out of memory",
    "__panic_halt": "panic",
}
CPU_ERRORS = ["InvalidMemoryRead", "InvalidMemoryWrite", "InvalidPortRead", "InvalidPortWrite",
              "StackOverflow", "StackUnderflow", "DivisionError", "ArcCosineError",
              "ArcTangent2Error", "LogarithmError", "PowerError"]
# Start is left out: v32lua opens its PICO-8 pause screen on Start, and neither PICO-8
# nor TIC-80 games use it -- pressing it would leave carts paused for part of the test.
BUTTONS = ["Left", "Right", "Up", "Down", "A", "B", "X", "Y", "L", "R"]
FIELDS = ["Cart", "Format", "Result", "Error", "Frame", "Run", "Function", "Line", "Code", "Overruns"]


def pad_script(seed, frames):
    """Random presses of all buttons but Start (like v32lua's padrand.py): A, B and X
    early to get past title screens, then a random button every 2-20 frames, held 3-40."""
    rnd = random.Random(seed)
    ev = ["60:A=1", "64:A=0", "90:B=1", "94:B=0", "120:X=1", "124:X=0"]
    f = 150
    while f < frames:
        btn = rnd.choice(BUTTONS)
        hold = rnd.randint(3, 40)
        ev += ["%d:%s=1" % (f, btn), "%d:%s=0" % (f + hold, btn)]
        f += rnd.randint(2, 20)
    return ";".join(ev)


class DebugInfo:
    """Maps CPU addresses to asm lines, Lua functions and .p8 source lines."""

    def __init__(self, work_dir, cart_file):
        self.addrs, self.asm_lines, self.labels = [], [], []   # vbin.debug rows
        with open(os.path.join(work_dir, "cart.vbin.debug"), encoding="utf-8", errors="replace") as fh:
            for row in fh:
                parts = row.rstrip("\r\n").split(",")
                if len(parts) >= 3:
                    self.addrs.append(int(parts[0], 16))
                    self.asm_lines.append(int(parts[2]))
                    self.labels.append(parts[3] if len(parts) >= 4 else "")
        self.label_addr = {l: a for a, l in zip(self.addrs, self.labels) if l}
        # Lua code sits before the runtime: anything past the first runtime handler is runtime
        runtime = [self.label_addr[l] for l in PANIC_LABELS if l in self.label_addr]
        self.runtime_start = min(runtime) if runtime else 1 << 40
        # function labels, ordered by address
        funcs = sorted((a, l) for a, l in zip(self.addrs, self.labels) if l.startswith("__function_"))
        self.func_addrs = [a for a, _ in funcs]
        self.func_names = [l[len("__function_"):] for _, l in funcs]
        # asm line -> cart line (v32lua -g); 0 = not Lua
        self.map_asm, self.map_src = [], []
        path = os.path.join(work_dir, "cart.asm.debug")
        if os.path.exists(path):
            with open(path, encoding="utf-8", errors="replace") as fh:
                for row in fh:
                    parts = row.rstrip("\r\n").split(",")
                    if len(parts) >= 4 and parts[1].isdigit() and parts[3].isdigit():
                        self.map_asm.append(int(parts[1]))
                        self.map_src.append(int(parts[3]))
        self.source = []
        src = os.path.join(work_dir, cart_file)
        if cart_file.endswith(".p8") and os.path.exists(src):
            with open(src, encoding="utf-8", errors="replace") as fh:
                self.source = fh.read().split("\n")
        elif cart_file.endswith(".tic") and os.path.exists(src):
            # v32lua numbers a .tic's lines in its extracted code (which comes first)
            self.source = b.tic80_code(src).replace("\r\n", "\n").split("\n")

    def is_lua(self, addr):
        return addr < self.runtime_start and self.function(addr) is not None

    def function(self, addr):
        i = bisect.bisect_right(self.func_addrs, addr) - 1
        return self.func_names[i] if i >= 0 else None

    def source_line(self, addr):
        i = bisect.bisect_right(self.addrs, addr) - 1
        if i < 0 or not self.map_asm:
            return 0, ""
        asm_line = self.asm_lines[i]
        j = bisect.bisect_right(self.map_asm, asm_line) - 1
        if j < 0 or self.map_src[j] == 0:
            return 0, ""
        line = self.map_src[j]
        text = self.source[line - 1].strip() if 0 < line <= len(self.source) else ""
        return line, text

    def locate(self, candidates):
        """First candidate address inside compiled Lua code -> (function, line, code)."""
        for addr in candidates:
            if self.is_lua(addr):
                line, text = self.source_line(addr)
                return self.function(addr), line, text
        # not traceable to Lua code (e.g. inside a runtime routine): name that routine
        for addr in candidates:
            i = bisect.bisect_right(self.addrs, addr) - 1
            while i >= 0 and not self.labels[i]:
                i -= 1
            if i >= 0:
                return "(runtime) " + self.labels[i], 0, ""
        return "", 0, ""


def parse_run(out):
    """-> dict(status, frames, overruns, trap, hw_code, hw_ip, trail, stack)"""
    r = {"trail": [], "stack": [], "trap": None, "hw_code": None, "hw_ip": None}
    m = re.search(r"^STATUS (.*?) frames=(\d+) cycles=\d+ ip=\w+ overruns=(\d+)", out, re.M)
    r["status"] = m.group(1) if m else "NO_STATUS"
    r["frames"] = int(m.group(2)) if m else 0
    r["overruns"] = int(m.group(3)) if m else 0
    m = re.search(r"^TRAP at ([0-9A-F]+)", out, re.M)
    if m:
        r["trap"] = int(m.group(1), 16)
    m = re.search(r"HWERROR code=(\d+) ip=([0-9A-F]+)", out)
    if m:
        r["hw_code"], r["hw_ip"] = int(m.group(1)), int(m.group(2), 16)
    for key, pat in (("trail", r"^(?:HALT )?TRAIL(.*)$"), ("stack", r"^STACK(.*)$")):
        m = re.search(pat, out, re.M)
        if m:
            r[key] = [int(x, 16) for x in m.group(1).split()]
    return r


def build_for_test(full, name, work_dir, tools, timeout, extra=()):
    """Rebuilds one cart in work_dir with debug info; `extra` are further v32lua options
    (build_v32.cart_option_args). -> (cart_file, fmt, error or '')"""
    b.clear_dir(work_dir)
    if name.lower().endswith(".tic"):
        fmt, api, cart_file = "tic", "tic80", "cart.tic"
        shutil.copyfile(full, os.path.join(work_dir, cart_file))
    else:
        api, cart_file = "pico8", "cart.p8"
        fmt = "png" if b.is_png(full) else "text"
        if fmt == "png":
            png_copy = os.path.join(work_dir, "cart.p8.png")
            shutil.copyfile(full, png_copy)
            try:
                b.png2p8(png_copy, os.path.join(work_dir, cart_file))
            except Exception as e:
                return cart_file, fmt, "png2p8: %s" % e
        else:
            shutil.copyfile(full, os.path.join(work_dir, cart_file))
    steps = [(tools["v32lua"], ["-w", "-g", "--api", api] + list(extra) + [cart_file], "cart.asm"),
             (tools["assemble"], ["cart.asm", "-o", "cart.vbin", "-g", "program"], "cart.vbin.debug")]
    for exe, args, product in steps:
        code, out = b.run_tool(exe, args, work_dir, timeout)
        if code != 0 or not os.path.exists(os.path.join(work_dir, product)):
            return cart_file, fmt, "%s: %s" % (os.path.basename(exe), b.first_error(out))
    return cart_file, fmt, ""


# Where the game's own screen is on the 640x360 Vircon32 screen (from v32lua's runtime):
# PICO-8's 128x128 at scale 2.75 from (144, 4) -- the side bezels are outside it --
# and TIC-80's 240x136 at scale 2.625 from (0, 0).
GAME_AREA = {"pico8": (144, 4, 144 + 352, 4 + 352), "tic80": (0, 0, 630, 357)}


class BlankChecker:
    """-blank: fed the GPU log of a run line by line while v32run is still running, it
    keeps the picture on one canvas -- every frame's commands are drawn onto it once, as
    the frame completes -- and every -blankstep frames looks only at the game area.
    Memory and time stay small: the log is never stored, nothing is replayed, and once
    the game area has shown something (normally at the first sample) the rest of the log
    is ignored."""

    def __init__(self, work_dir, api, args, shot, bios):
        self.shot, self.bios = shot, bios
        self.texs = shot.cart_textures(work_dir)
        self.area = GAME_AREA[api]
        self.samples = list(range(args.blank_step, args.frames, args.blank_step))
        self.k = 0                  # next sample to check
        self.canvas = None          # the screen so far (None: nothing drawn yet = black)
        self.cur = None             # frame whose lines are being collected
        self.pending = []           # its lines
        self.colours = set()
        self.shown = False          # decided: something was shown
        self.error = None           # set if the check itself failed; the cart's test goes on

    def _apply(self):
        """Draws the collected frame onto the canvas."""
        if self.pending:
            if self.canvas is None:
                self.canvas = self.shot.Image.new("RGBA", (self.shot.SCREEN_W, self.shot.SCREEN_H), (0, 0, 0, 255))
            self.canvas = self.shot.apply_lines(self.canvas, self.pending, self.texs, self.bios)
            self.pending = []

    def _check(self):
        if self.canvas is None:     # nothing drawn yet: the screen is still black
            self.colours.add((0, 0, 0))
            return
        ext = self.canvas.crop(self.area).getextrema()[:3]
        if any(lo != hi for lo, hi in ext):
            self.shown = True       # more than one colour in the game area: something is shown
            return
        self.colours.add(tuple(lo for lo, _ in ext))
        if len(self.colours) > 1:
            self.shown = True       # the colour changed over time: something is happening

    def _done(self):
        self.canvas, self.pending = None, []

    def feed(self, line):
        """One 'F<n> GPU ...' line of v32run -g output. Never raises: an error in the
        check (e.g. an odd GPU log) only disables the check for this cart."""
        if self.shown or self.error:
            return
        try:
            self._feed(line)
        except Exception as e:
            self.error = repr(e)
            self._done()

    def _feed(self, line):
        f = int(line[1:line.index(" ")])
        if f != self.cur:
            self._apply()           # the previous frame is complete
            self.cur = f
            # every frame up to each passed sample is on the canvas now
            while self.k < len(self.samples) and f > self.samples[self.k]:
                self._check()
                self.k += 1
                if self.shown:
                    self._done()
                    return
        self.pending.append(line)

    def result(self):
        """"" if something was shown, else "only black" / "only one colour #rrggbb";
        None if the check failed (see .error)."""
        try:
            if not self.error and not self.shown:
                self._apply()
                while not self.shown and self.k < len(self.samples):   # samples after the last logged frame
                    self._check()
                    self.k += 1
        except Exception as e:
            self.error = repr(e)
        self._done()
        if self.error:
            return None
        if self.shown:
            return ""
        colour = self.colours.pop() if self.colours else (0, 0, 0)
        return "only black" if colour == (0, 0, 0) else "only one colour #%02x%02x%02x" % colour


def run_streaming(cmd, work_dir, env, timeout, checker):
    """Runs v32run, handing GPU lines to checker.feed() as they arrive instead of keeping
    them. -> (the other output lines as text, timed out?)"""
    p = subprocess.Popen(cmd, cwd=work_dir, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    timed_out = []

    def kill():
        timed_out.append(True)
        p.kill()
    timer = threading.Timer(timeout, kill)
    timer.start()
    keep = []
    try:
        for raw in p.stdout:
            line = raw.decode("utf-8", "replace").rstrip("\r\n")
            if line.startswith("F") and " GPU " in line[:16]:
                checker.feed(line)
            elif line.strip():
                keep.append(line)
        p.wait()
    finally:
        timer.cancel()
        # whatever happened, never leave v32run behind: a process nobody reads from any
        # more blocks on its full output pipe forever (and so did the whole test run)
        if p.poll() is None:
            p.kill()
        try:
            p.wait(timeout=30)
        except subprocess.TimeoutExpired:
            pass
        p.stdout.close()
    return "\n".join(keep), bool(timed_out)


def test_cart(full, name, work_dir, tools, args, blank=None):
    res = {"Cart": name, "Format": "", "Result": "OK", "Error": "", "Frame": "", "Run": "",
           "Function": "", "Line": "", "Code": "", "Overruns": 0}
    cart_file, res["Format"], err = build_for_test(full, name, work_dir, tools, args.timeout_sec,
                                                   b.cart_option_args(args))
    if err:
        res.update(Result="BUILD_FAILED", Error=err)
        return res, err
    dbg = DebugInfo(work_dir, cart_file)
    traps = ",".join("%X" % dbg.label_addr[l] for l in PANIC_LABELS if l in dbg.label_addr)
    env = dict(os.environ, V32_FIXED_TIME="1")   # repeatable runs for the same seed
    log = []
    checker = None
    for run in range(1, args.runs + 1):
        pad = pad_script(run, args.frames)
        cmd = [tools["v32run"], "cart.vbin", "-f", str(args.frames), "-q", "-p", pad]
        if traps:
            cmd += ["-t", traps]
        if blank and run == 1:
            # GPU log of the first run, checked for a black screen while it streams in
            shot, bios = blank
            checker = BlankChecker(work_dir, "tic80" if cart_file.endswith(".tic") else "pico8", args, shot, bios)
            out, timed_out = run_streaming(cmd + ["-g"], work_dir, env, args.timeout_sec, checker)
        else:
            try:
                p = subprocess.run(cmd, cwd=work_dir, capture_output=True, timeout=args.timeout_sec, env=env,
                                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                out = p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")
                timed_out = False
            except subprocess.TimeoutExpired:
                timed_out = True
        if timed_out:
            res.update(Result="TIMEOUT", Error="v32run took over %d s" % args.timeout_sec, Run=run)
            log.append("run %d (seed %d): TIMEOUT" % (run, run))
            checker = None
            break
        r = parse_run(out)
        res["Overruns"] = max(res["Overruns"], r["overruns"])
        log.append("run %d (seed %d): %s" % (run, run, out.strip()))
        if r["status"] == "FRAMES_EXHAUSTED":
            continue
        res.update(Frame=r["frames"], Run=run)
        if r["trap"] is not None:
            label = next((l for l, a in dbg.label_addr.items() if a == r["trap"] and l in PANIC_LABELS), "")
            res.update(Result="PANIC", Error=PANIC_LABELS.get(label, "panic"))
            where = dbg.locate(list(reversed(r["trail"])) + r["stack"])
        elif r["hw_code"] is not None:
            code = r["hw_code"]
            res.update(Result="CPU_ERROR", Error=CPU_ERRORS[code] if 0 <= code < len(CPU_ERRORS) else "code %d" % code)
            where = dbg.locate([r["hw_ip"] - 1, r["hw_ip"] - 2] + list(reversed(r["trail"])))
        else:
            res.update(Result="HALT" if r["status"] == "HALT" else r["status"], Error=r["status"])
            where = dbg.locate(list(reversed(r["trail"])))
        res["Function"], line, res["Code"] = where
        res["Line"] = line or ""
        break
    if checker is not None and res["Result"] == "OK":
        what = checker.result()
        if what:
            res.update(Result="BLACK_SCREEN", Error="game area showed %s in every sampled frame (run 1)" % what)
            log.append("black screen check: game area %s at every %d frames" % (what, args.blank_step))
        elif what is None:    # the check itself failed: keep the crash-test result, note why
            res["Error"] = "black screen check skipped: %s" % checker.error
            log.append("black screen check skipped: %s" % checker.error)
    return res, "\n\n".join(log)


# ---- worker processes: each loads its tools once and works in its own folder
_WORKER = {}


def _init_worker(tools, args, work_root, bios_path):
    blank = None
    if args.blank:
        import screenshot_v32 as shot
        blank = (shot, shot.load_bios_font(bios_path))
    work_dir = os.path.join(work_root, "p%d" % os.getpid())
    os.makedirs(work_dir, exist_ok=True)
    _WORKER.update(tools=tools, args=args, blank=blank, work_dir=work_dir)


def _run_one(item):
    """Tests one cart in this worker process. -> (result row, log text); never raises."""
    full, name = item
    w = _WORKER
    try:
        b.clear_dir(w["work_dir"])
    except OSError:
        pass
    try:
        return test_cart(full, name, w["work_dir"], w["tools"], w["args"], w["blank"])
    except Exception as e:   # keep going; report the cart
        return {"Cart": name, "Result": "SCRIPT_ERROR", "Error": repr(e)}, repr(e)
    finally:
        try:
            b.clear_dir(w["work_dir"])
        except OSError:
            pass


# running totals on each progress line: letter, results counted, colour, always shown
STATS = [("O", ("OK",), "GREEN", True), ("P", ("PANIC",), "RED", True), ("C", ("CPU_ERROR",), "RED", True),
         ("B", ("BLACK_SCREEN",), "RED", False), ("H", ("HALT",), "YELLOW", False),
         ("T", ("TIMEOUT",), "YELLOW", False), ("F", ("BUILD_FAILED",), "YELLOW", False)]


def stats_text(counts, blank):
    """'O:35 P:4 C:1 ...' in colour: O ok, P panic, C cpu error, B black screen (with -blank),
    H halt, T timeout, F build failed, E anything else. Rare ones only once they occur."""
    parts, known = [], set()
    for letter, results, colour, always in STATS:
        known.update(results)
        n = sum(counts.get(r, 0) for r in results)
        if always or n or (letter == "B" and blank):
            parts.append("%s%s:%d%s" % (getattr(b, colour), letter, n, b.RESET))
    other = sum(v for k, v in counts.items() if k not in known)
    if other:
        parts.append("%sE:%d%s" % (b.YELLOW, other, b.RESET))
    return " ".join(parts)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="Headless crash test of built Vircon32 carts.", allow_abbrev=False)
    ap.add_argument("-sourcedir", "--source-dir", default=here)
    ap.add_argument("-filter", "--filter", nargs="+", default=["*.p8", "*.p8.png", "*.tic"])
    ap.add_argument("-start", "--start", default="")
    ap.add_argument("-max", "--max", type=int, default=0)
    ap.add_argument("-all", "--all", action="store_true", help="also test carts without a ROM in v32/")
    ap.add_argument("-frames", "--frames", type=int, default=1800, help="frames per run (60 = 1 s; default 1800)")
    ap.add_argument("-runs", "--runs", type=int, default=3, help="runs per cart, each a different pad script")
    ap.add_argument("-jobs", "--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("-timeoutsec", "--timeout-sec", type=int, default=120)
    b.add_cart_options(ap)   # -fastcircles / -nobezel: test the same build as the ROMs
    ap.add_argument("-blank", "--blank", action="store_true",
                    help="also detect carts whose game area stays black (or one flat colour) in every "
                         "sampled frame of run 1: result BLACK_SCREEN. Needs Pillow and screenshot_v32.py")
    ap.add_argument("-blankstep", "--blank-step", type=int, default=60,
                    help="-blank: check a frame every N frames (default 60 = every second)")
    ap.add_argument("-bios", "--bios", default=r"C:\github\ComputerSoftware\SimplifiedEmulator\Data\Bios\StandardBios.v32"
                    if b.IS_WINDOWS else None, help="-blank: StandardBios.v32, so BIOS-font text counts as shown")
    ap.add_argument("-v32lua", "--v32lua", default=r"C:\github\v32lua\bin\v32lua.exe" if b.IS_WINDOWS else None)
    ap.add_argument("-devtools", "--devtools", default=r"C:\utils\vircon32\devtools" if b.IS_WINDOWS else None)
    ap.add_argument("-v32run", "--v32run", default=r"C:\github\v32lua\tools\headless\v32run.exe" if b.IS_WINDOWS else None)
    args = ap.parse_args()

    if b.IS_WINDOWS:
        os.system("")
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    tools = {"v32lua": b.find_tool("v32lua", path=args.v32lua),
             "assemble": b.find_tool("assemble", folder=args.devtools)}
    v32run = b.find_tool("v32run", path=args.v32run) if args.v32run else b.find_tool("v32run")
    if not v32run and tools["v32lua"]:   # repo layout: bin/v32lua -> tools/headless/v32run
        v32run = b.find_tool("v32run", folder=os.path.join(os.path.dirname(tools["v32lua"]), "..", "tools", "headless"))
    tools["v32run"] = v32run
    for name, exe in tools.items():
        if not exe:
            sys.exit("Tool not found: %s" % name)
    bios_path = None
    if args.blank:
        # the screenshot renderer rebuilds the frames (needs Pillow; exits with a hint if missing);
        # each worker process loads it itself -- here it's only checked once
        import screenshot_v32 as shot
        bios_path = b.full_path(args.bios) if args.bios else None
        if shot.load_bios_font(bios_path) is None:
            print("%sBIOS not found (-bios): text drawn with the BIOS font won't count as shown%s"
                  % (b.YELLOW, b.RESET))

    source_dir = b.full_path(args.source_dir)
    out_dir = os.path.join(source_dir, "v32")
    log_dir = os.path.join(out_dir, "test_logs")
    # a private folder per run, so two runs in the same folder can't clear each other's files
    work_parent = os.path.join(source_dir, "work_test")
    work_root = os.path.join(work_parent, "run%d" % os.getpid())
    os.makedirs(log_dir, exist_ok=True)

    # same cart list and order as build_v32.py
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
        carts = [(f, n) for f, n in carts if os.path.exists(os.path.join(out_dir, b.cart_base(n) + ".v32"))]
    if args.max > 0:
        carts = carts[:args.max]
    total = len(carts)
    print("Testing %d carts: %d run(s) x %d frames each, %d parallel" % (total, args.runs, args.frames, args.jobs))

    results, counts, done = [], {}, [0]
    start_time = time.time()
    os.makedirs(work_root, exist_ok=True)

    # separate worker processes (not threads), so the Python work per cart -- above all the
    # -blank frame checks -- runs on all cores at once instead of taking turns on one.
    # A worker that dies (e.g. out of memory) only costs its own cart: see run_with_recovery.
    def new_pool(n):
        return ProcessPoolExecutor(n, initializer=_init_worker, initargs=(tools, args, work_root, bios_path))

    def error_result(item, message):
        return {"Cart": item[1], "Result": "SCRIPT_ERROR", "Error": message}, message

    def handle(item, value):
        """Log file, counts and progress line for one finished cart (in this process)."""
        full, name = item
        res, log = value
        log_path = os.path.join(log_dir, b.cart_base(name) + ".log")
        if res["Result"] == "OK":
            if os.path.exists(log_path):
                os.remove(log_path)
        else:
            with open(log_path, "w", encoding="utf-8") as fh:
                fh.write(log + "\n")
        results.append(res)
        counts[res["Result"]] = counts.get(res["Result"], 0) + 1
        done[0] += 1
        colour = b.GREEN if res["Result"] == "OK" else (b.YELLOW if res["Result"] == "BUILD_FAILED" else b.RED)
        detail = "" if res["Result"] == "OK" else " %s" % res["Error"]
        if res.get("Function"):
            detail += " in %s" % res["Function"]
            if res.get("Line"):
                detail += " (line %s)" % res["Line"]
        if res.get("Frame"):
            detail += " at frame %s" % res["Frame"]
        print("[%d/%d %s] %s ... %s%s%s%s" % (done[0], total, stats_text(counts, args.blank), name,
                                              colour, res["Result"], detail, b.RESET), flush=True)

    b.run_with_recovery(carts, args.jobs, new_pool, _run_one, handle, error_result)

    shutil.rmtree(work_root, ignore_errors=True)
    try:
        os.rmdir(work_parent)   # only when no other run is still using it
    except OSError:
        pass

    csv_path = os.path.join(out_dir, "test_results.csv")
    merged = {}
    if os.path.exists(csv_path):
        with open(csv_path, newline="", encoding="utf-8-sig") as fh:
            for row in csv.DictReader(fh):
                merged[row["Cart"].lower()] = row
    for r in results:
        merged[r["Cart"].lower()] = r
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, quoting=csv.QUOTE_ALL, extrasaction="ignore")
        w.writeheader()
        for row in sorted(merged.values(), key=functools.cmp_to_key(lambda x, y: b.compare(x["Cart"], y["Cart"]))):
            w.writerow(row)

    elapsed = int(time.time() - start_time)
    print()
    print("Done in %02d:%02d:%02d: %s" % (elapsed // 3600, elapsed // 60 % 60, elapsed % 60,
                                          ", ".join("%d %s" % (v, k) for k, v in sorted(counts.items()))))
    print("Results: %s" % csv_path)
    print("Logs:    %s" % log_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
