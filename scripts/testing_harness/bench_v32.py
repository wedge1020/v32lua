#!/usr/bin/env python3
"""
Benchmark built carts: how much of the Vircon32 CPU each game uses.

The Vircon32 CPU runs a fixed 250,000 cycles per frame (15 MHz at 60 fps). A game
does its frame's work and then WAITs for the next frame; the cycles it used before
the WAIT are its CPU load for that frame. A frame that never reaches WAIT used
the whole budget: an overrun, where the game slows down on real hardware.

Each cart that has a ROM in v32/ (or every cart with -all) is rebuilt with debug
info (like test_v32.py) and run on v32bench (v32run plus per-frame cycle counts;
build it with C:/github/v32bench/build_v32bench.py) for -frames frames. Input is
the same for every cart, so results compare fairly (-input fixed, the default):
A then B once at 4 s (the usual start buttons, like screenshot_v32.py), then from
6 s cycling through every button in a fixed order: Right, Left, Up, Down (held
0.5 s), A, B, X, Y, L, R (tapped), over and over. Start is left out: it opens
v32lua's PICO-8 pause screen.
-input random uses test_v32.py's button mashing instead, -input none no buttons.
The first -warmup frames (loading) are left out.

Per cart: average, median, 95th percentile and maximum CPU load, the number of
overrun frames, and the 3 routines that used the most cycles (Lua functions by
name, v32lua runtime routines as __builtin_...), from v32run's cycle profiler.
Cycle counts come from the emulated CPU, so results don't depend on how fast
this PC is, and runs in parallel don't disturb each other.

At the end of the run: the heaviest carts, and where the CPU time goes over all
carts of the run -- the v32lua runtime routines (map, spr, print, number
conversion, ...) ranked by their share of all cycles, over all carts and over
the carts that had overrun frames. Those are the routines whose optimisation in
v32lua would benefit the most games. The carts' own Lua functions differ per
cart and are counted together as one "game code" line.

Each cart also gets a severity, shown as its colour on screen and counted at the
end (for the run and for every cart in bench_results.csv):
  green         never over the CPU budget
  yellow        occasional overrun frames (at most 5%, p95 under 100%)
  red           often too slow (over 5% overrun frames, or p95 at 100%)
  not measured  didn't build, or stopped before the warm-up ended

Results: v32/bench_results.csv (per cart incl. Severity, merged across runs) and
v32/bench_routines.csv (the across-carts summary of this run).

Usage:
  python bench_v32.py                         # all carts with a ROM in v32/
  python bench_v32.py -start "Celeste" -max 10
  python bench_v32.py -frames 3600 -warmup 120
  python bench_v32.py -input none             # title screens / attract modes only
  python bench_v32.py -input random -seed 2   # button mashing instead of the fixed script
Works for PICO-8 (.p8 / .p8.png) and TIC-80 (.tic) carts.
"""

import argparse
import bisect
import csv
import functools
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.dont_write_bytecode = True  # no __pycache__ next to the carts
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_v32 as b     # noqa: E402
import test_v32 as t      # noqa: E402

CYCLES_PER_FRAME = 250000
FIELDS = ["Cart", "Format", "Result", "Severity", "Frames", "AvgCPU", "MedianCPU", "P95CPU", "MaxCPU",
          "Overruns", "OverrunPct", "Hot1", "Hot2", "Hot3"]


def routine_map(work_dir):
    """(addresses, names): each code address belongs to the routine that starts at the
    nearest preceding label that begins a routine, so loop/branch labels roll up into
    their routine. A routine starts at a Lua function (__function_), a label that is
    CALLed somewhere, or a label followed by PUSH BP (as in v32lua's
    tools/headless/profile.py). CALL targets catch runtime helpers such as
    __pico8_to_int that don't set up a stack frame; labels that are only jumped to
    (..._loop, ..._done) stay part of their routine."""
    asm = []
    path = os.path.join(work_dir, "cart.asm")
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as fh:
            asm = fh.read().split("\n")
    called = set(re.findall(r"^\s*CALL\s+([A-Za-z_]\w*)", "\n".join(asm), re.M))
    rows = []
    with open(os.path.join(work_dir, "cart.vbin.debug"), encoding="utf-8", errors="replace") as fh:
        for row in fh:
            p = row.rstrip("\r\n").split(",")
            if len(p) >= 3:
                rows.append((int(p[0], 16), int(p[2]), p[3] if len(p) >= 4 else ""))
    addrs, names, last = [], [], "?"
    for addr, ln, label in rows:
        if label:
            nxt = asm[ln - 1].strip() if 0 < ln <= len(asm) else ""
            if (nxt.startswith("PUSH") and "BP" in nxt) or label.startswith("__function_") \
                    or label in called or last == "?":
                last = label
        addrs.append(addr)
        names.append(last)
    return addrs, names


def profile_routines(work_dir, prof_path):
    """Cycles per routine from v32run's profile (-P). -> Counter {routine: cycles}"""
    per = Counter()
    if not os.path.exists(prof_path):
        return per
    addrs, names = routine_map(work_dir)
    with open(prof_path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) != 2:
                continue
            a, c = int(parts[0], 16), int(parts[1])
            i = bisect.bisect_right(addrs, a) - 1
            per[names[i] if i >= 0 else "?"] += c
    return per


def display_name(name):
    return name[len("__function_"):] + "()" if name.startswith("__function_") else name


def hot_spots(per, n=3):
    total = sum(per.values())
    if not total:
        return []
    return ["%s %.1f%%" % (display_name(name), 100.0 * c / total) for name, c in per.most_common(n)]


GAME_CODE = "(game code: the carts' own Lua functions)"


def runtime_totals(results):
    """Cycles per v32lua runtime routine summed over all measured carts, over the carts
    with overrun frames, and in how many carts each routine ran. The carts' own Lua
    functions differ per cart, so they are counted together as GAME_CODE."""
    all_c, slow_c, carts = Counter(), Counter(), Counter()
    for r in results:
        per = r.get("_routines")
        if not per:
            continue
        slow = bool(r["Overruns"])
        keys = set()
        for name, c in per.items():
            key = GAME_CODE if name.startswith("__function_") else name
            all_c[key] += c
            keys.add(key)
            if slow:
                slow_c[key] += c
        for key in keys:        # count each cart once per routine
            carts[key] += 1
    return all_c, slow_c, carts


FIXED_START = [("A", 240, 6), ("B", 270, 6)]            # the usual start buttons, once
# every button in turn: directions held 0.5 s, buttons tapped. Start is left out: it
# opens v32lua's PICO-8 pause screen, which would then be what gets measured.
FIXED_CYCLE = [("Right", 30), ("Left", 30), ("Up", 30), ("Down", 30),
               ("A", 6), ("B", 6), ("X", 6), ("Y", 6), ("L", 6), ("R", 6)]
FIXED_GAP = 10                                            # frames between presses in the cycle


def fixed_pad_script(frames):
    """Same presses for every cart: A then B once to start the game, then from 6 s on
    cycling through every button in a fixed order (Right, Left, Up, Down held 0.5 s;
    A, B, X, Y, L, R tapped), over and over."""
    ev = []
    for btn, at, hold in FIXED_START:
        ev += ["%d:%s=1" % (at, btn), "%d:%s=0" % (at + hold, btn)]
    f = 360
    while f < frames:
        for btn, hold in FIXED_CYCLE:
            ev += ["%d:%s=1" % (f, btn), "%d:%s=0" % (f + hold, btn)]
            f += hold + FIXED_GAP
    return ";".join(ev)


def pad_for(args):
    if args.input == "fixed":
        return fixed_pad_script(args.frames)
    if args.input == "random":
        return t.pad_script(args.seed, args.frames)
    return ""


SEVERITIES = ["green", "yellow", "red", "not measured"]
SEVERITY_TEXT = {"green": "never over the CPU budget",
                 "yellow": "occasional overrun frames (at most 5%, p95 under 100%)",
                 "red": "often too slow (over 5% overrun frames, or p95 at 100%)",
                 "not measured": "didn't build, or stopped before the warm-up ended"}
SEVERITY_COLOURS = {"green": lambda: b.GREEN, "yellow": lambda: b.YELLOW,
                    "red": lambda: b.RED, "not measured": lambda: b.YELLOW}


def severity(res):
    """green / yellow / red / not measured, from a result row (numbers or CSV strings)."""
    try:
        overrun_pct, p95, overruns = float(res["OverrunPct"]), float(res["P95CPU"]), int(res["Overruns"])
    except (KeyError, TypeError, ValueError):
        return "not measured"
    if overrun_pct > 5 or p95 >= 100:
        return "red"
    return "yellow" if overruns else "green"


def pct(v):
    return round(100.0 * v / CYCLES_PER_FRAME, 1)


def bench_cart(full, name, work_dir, tools, args):
    res = dict.fromkeys(FIELDS, "")
    res["Cart"] = name
    cart_file, res["Format"], err = t.build_for_test(full, name, work_dir, tools, args.timeout_sec,
                                                     b.cart_option_args(args))
    if err:
        res.update(Result="BUILD_FAILED")
        return res, err
    dbg = t.DebugInfo(work_dir, cart_file)
    traps = ",".join("%X" % dbg.label_addr[l] for l in t.PANIC_LABELS if l in dbg.label_addr)
    prof = os.path.join(work_dir, "cart.prof")
    cmd = [tools["v32bench"], "cart.vbin", "-f", str(args.frames), "-q", "-b", "-P", prof, str(args.warmup)]
    if traps:
        cmd += ["-t", traps]
    pad = pad_for(args)
    if pad:
        cmd += ["-p", pad]
    env = dict(os.environ, V32_FIXED_TIME="1")
    try:
        p = subprocess.run(cmd, cwd=work_dir, capture_output=True, timeout=args.timeout_sec, env=env,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        out = p.stdout.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        res.update(Result="TIMEOUT")
        return res, "v32bench took over %d s" % args.timeout_sec

    loads, overruns = [], 0
    for m in re.finditer(r"^FC (\d+) (\d+) (\d)", out, re.M):
        if int(m.group(1)) >= args.warmup:
            loads.append(int(m.group(2)))
            overruns += int(m.group(3))
    r = t.parse_run(out)
    if r["trap"] is not None:
        res["Result"] = "PANIC"
    elif r["hw_code"] is not None:
        res["Result"] = "CPU_ERROR"
    elif r["status"] == "FRAMES_EXHAUSTED":
        res["Result"] = "OK"
    else:
        res["Result"] = r["status"]
    if not loads:
        return res, "stopped before frame %d (%s)" % (args.warmup, res["Result"])
    s = sorted(loads)
    res.update(Frames=len(s), AvgCPU=pct(sum(s) / len(s)), MedianCPU=pct(s[len(s) // 2]),
               P95CPU=pct(s[min(len(s) - 1, int(len(s) * 0.95))]), MaxCPU=pct(s[-1]),
               Overruns=overruns, OverrunPct=round(100.0 * overruns / len(s), 1))
    per = profile_routines(work_dir, prof)
    res["_routines"] = per      # full breakdown, for the across-carts summary (not in the CSV)
    for k, h in enumerate(hot_spots(per)):
        res["Hot%d" % (k + 1)] = h
    note = "" if res["Result"] == "OK" else " [stopped: %s at frame %d]" % (res["Result"], r["frames"])
    return res, note


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="CPU load benchmark of built Vircon32 carts.", allow_abbrev=False)
    ap.add_argument("-sourcedir", "--source-dir", default=here)
    ap.add_argument("-filter", "--filter", nargs="+", default=["*.p8", "*.p8.png", "*.tic"])
    ap.add_argument("-start", "--start", default="")
    ap.add_argument("-max", "--max", type=int, default=0)
    ap.add_argument("-all", "--all", action="store_true", help="also carts without a ROM in v32/")
    ap.add_argument("-frames", "--frames", type=int, default=1800, help="frames to run, 60 = 1 s (default 1800)")
    ap.add_argument("-warmup", "--warmup", type=int, default=60, help="first frames left out (default 60)")
    ap.add_argument("-input", "--input", choices=("fixed", "random", "none"), default="fixed",
                    help="fixed: the same scripted presses for every cart (default); "
                         "random: test_v32.py's button mashing; none: no buttons")
    ap.add_argument("-seed", "--seed", type=int, default=1, help="pattern for -input random (default 1)")
    ap.add_argument("-top", "--top", type=int, default=15, help="heaviest carts listed at the end (default 15)")
    ap.add_argument("-routines", "--routines", type=int, default=20,
                    help="runtime routines listed in the across-carts summary (default 20)")
    ap.add_argument("-jobs", "--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("-timeoutsec", "--timeout-sec", type=int, default=180)
    b.add_cart_options(ap)   # -fastcircles / -nobezel: benchmark the same build as the ROMs
    ap.add_argument("-v32lua", "--v32lua", default=r"C:\github\v32lua\bin\v32lua.exe" if b.IS_WINDOWS else None)
    ap.add_argument("-devtools", "--devtools", default=r"C:\utils\vircon32\devtools" if b.IS_WINDOWS else None)
    ap.add_argument("-v32bench", "--v32bench", default=r"C:\github\v32bench\v32bench.exe" if b.IS_WINDOWS else None)
    args = ap.parse_args()
    if args.warmup >= args.frames:
        ap.error("-warmup must be smaller than -frames")

    if b.IS_WINDOWS:
        os.system("")
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    tools = {"v32lua": b.find_tool("v32lua", path=args.v32lua),
             "assemble": b.find_tool("assemble", folder=args.devtools),
             "v32bench": b.find_tool("v32bench", path=args.v32bench) if args.v32bench else b.find_tool("v32bench")}
    for name, exe in tools.items():
        if not exe:
            sys.exit("Tool not found: %s%s" % (name, " (build it with build_v32bench.py)" if name == "v32bench" else ""))

    source_dir = b.full_path(args.source_dir)
    out_dir = os.path.join(source_dir, "v32")
    os.makedirs(out_dir, exist_ok=True)
    work_parent = os.path.join(source_dir, "work_bench")
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
        carts = [(f, n) for f, n in carts if os.path.exists(os.path.join(out_dir, b.cart_base(n) + ".v32"))]
    if args.max > 0:
        carts = carts[:args.max]
    total = len(carts)
    inputs = {"fixed": "fixed button script", "none": "no buttons",
              "random": "random buttons (seed %d)" % args.seed}[args.input]
    print("Benchmarking %d carts: %d frames (first %d left out), %s, %d parallel" % (
        total, args.frames, args.warmup, inputs, args.jobs))

    lock = threading.Lock()
    free_dirs = [os.path.join(work_root, "j%d" % k) for k in range(args.jobs)]
    results, done = [], [0]
    start_time = time.time()

    def worker(item):
        full, name = item
        with lock:
            work_dir = free_dirs.pop()
        try:
            os.makedirs(work_dir, exist_ok=True)
            return bench_cart(full, name, work_dir, tools, args)
        finally:
            try:
                b.clear_dir(work_dir)
            except OSError:
                pass
            with lock:
                free_dirs.append(work_dir)

    with ThreadPoolExecutor(args.jobs) as ex:
        futures = {ex.submit(worker, c): c for c in carts}
        for fut in as_completed(futures):
            _, name = futures[fut]
            try:
                res, note = fut.result()
            except Exception as e:
                res, note = dict.fromkeys(FIELDS, ""), repr(e)
                res.update(Cart=name, Result="SCRIPT_ERROR")
            res["Severity"] = severity(res)
            results.append(res)
            done[0] += 1
            if res["AvgCPU"] != "":
                colour = SEVERITY_COLOURS[res["Severity"]]()
                text = "avg %s%% p95 %s%% max %s%%, overruns %s (%s%%)" % (
                    res["AvgCPU"], res["P95CPU"], res["MaxCPU"], res["Overruns"], res["OverrunPct"])
                hot = ", ".join(h for h in (res["Hot1"], res["Hot2"], res["Hot3"]) if h)
                if hot:
                    text += " | " + hot
            else:
                colour, text = b.YELLOW, res["Result"] + " "
            with lock:
                sev = Counter(r["Severity"] for r in results)
                stats = " ".join("%s%s:%d%s" % (SEVERITY_COLOURS[s](), letter, sev[s], b.RESET)
                                 for letter, s in (("G", "green"), ("Y", "yellow"), ("R", "red"), ("N", "not measured")))
                print("[%d/%d %s] %s ... %s%s%s%s" % (done[0], total, stats, name, colour, text, note, b.RESET),
                      flush=True)

    shutil.rmtree(work_root, ignore_errors=True)
    try:
        os.rmdir(work_parent)
    except OSError:
        pass

    csv_path = os.path.join(out_dir, "bench_results.csv")
    merged = {}
    if os.path.exists(csv_path):
        with open(csv_path, newline="", encoding="utf-8-sig") as fh:
            for row in csv.DictReader(fh):
                merged[row["Cart"].lower()] = row
    for r in results:
        merged[r["Cart"].lower()] = r
    for r in merged.values():   # rows from runs before the Severity column existed
        if not r.get("Severity"):
            r["Severity"] = severity(r)
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, quoting=csv.QUOTE_ALL, extrasaction="ignore")
        w.writeheader()
        for row in sorted(merged.values(), key=functools.cmp_to_key(lambda x, y: b.compare(x["Cart"], y["Cart"]))):
            w.writerow(row)

    measured = [r for r in results if r["AvgCPU"] != ""]
    elapsed = int(time.time() - start_time)
    print()
    print("Done in %02d:%02d:%02d: %d carts measured, %d not" % (
        elapsed // 3600, elapsed // 60 % 60, elapsed % 60, len(measured), len(results) - len(measured)))
    print("\nSeverity           this run   all carts in bench_results.csv")
    run_counts = Counter(r["Severity"] for r in results)
    all_counts = Counter(r.get("Severity") or severity(r) for r in merged.values())
    for sev in SEVERITIES:
        print("  %s%-15s%s  %6d   %6d%s" % (SEVERITY_COLOURS[sev](), sev, b.RESET, run_counts[sev], all_counts[sev],
                                           "   " + SEVERITY_TEXT[sev]))
    print("  %-15s  %6d   %6d" % ("total", len(results), len(merged)))
    if measured:
        slow = [r for r in measured if r["Overruns"]]
        print("%d carts had overrun frames (would slow down on real hardware)" % len(slow))
        print("\nHeaviest by overrun frames:")
        for r in sorted(measured, key=lambda r: (-r["OverrunPct"], -r["AvgCPU"]))[:args.top]:
            if r["Overruns"]:
                print("  %5s%% overruns, avg %5s%%  %s" % (r["OverrunPct"], r["AvgCPU"], r["Cart"]))
        print("\nHeaviest by average load:")
        for r in sorted(measured, key=lambda r: -r["AvgCPU"])[:args.top]:
            print("  avg %5s%%, max %5s%%  %s  (%s)" % (r["AvgCPU"], r["MaxCPU"], r["Cart"], r["Hot1"]))

    # which v32lua runtime routines would pay off most if made faster, across all carts
    all_c, slow_c, carts = runtime_totals(results)
    routines_path = os.path.join(out_dir, "bench_routines.csv")
    if all_c:
        total_all, total_slow = sum(all_c.values()), sum(slow_c.values())
        n_slow = sum(1 for r in measured if r["Overruns"])
        rows = []
        for name, c in all_c.most_common():
            rows.append({"Routine": display_name(name), "AllCartsPct": round(100.0 * c / total_all, 2),
                         "SlowCartsPct": round(100.0 * slow_c[name] / total_slow, 2) if total_slow else "",
                         "Carts": carts[name]})
        with open(routines_path, "w", newline="", encoding="utf-8-sig") as fh:
            w = csv.DictWriter(fh, fieldnames=["Routine", "AllCartsPct", "SlowCartsPct", "Carts"],
                               quoting=csv.QUOTE_ALL)
            w.writeheader()
            w.writerows(rows)
        print("\nWhere the CPU time goes, over all %d measured carts (and the %d with overrun frames):"
              % (len(measured), n_slow))
        print("making the top v32lua routines faster helps the most carts")
        print("  all carts  slow carts  carts  routine")
        for row in rows[:args.routines]:
            print("  %8.1f%%  %9s  %5d  %s" % (row["AllCartsPct"],
                                               "%.1f%%" % row["SlowCartsPct"] if row["SlowCartsPct"] != "" else "-",
                                               row["Carts"], row["Routine"]))
    print("\nResults:  %s" % csv_path)
    if all_c:
        print("Routines: %s" % routines_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
