#!/usr/bin/env python3
"""
Copy built Vircon32 ROMs (*.v32) into a destination folder, filtered and sorted into
subfolders by their test result (test_v32.py's test_results.csv) and/or their
benchmark colour (bench_v32.py's bench_results.csv). The ROMs are COPIED: the
originals stay where they are.

  -tests test_results.csv    test results: OK, PANIC, CPU_ERROR, BLACK_SCREEN, HALT, ...
  -bench bench_results.csv   benchmark colours: green, yellow, red, not measured
  -dest  folder              where the copies go (created if needed)

At least one of -tests / -bench is needed. The ROMs are looked up in the folder of the
first CSV given (normally v32/), or in the -roms folder(s), searched in the order
given (add -recursive to also search their subfolders, e.g. after ROMs were moved
into colour folders):  -roms v32 v32_ok -recursive

Filters (combine as you like; results / colours are case-insensitive):
  -results OK BLACK_SCREEN CPU_ERROR   only carts with one of these test results
  -colors green yellow                 only carts with one of these benchmark colours

Subfolders (-by):
  result        dest/ok/, dest/black_screen/, dest/cpu_error/, ...
  color         dest/green/, dest/yellow/, dest/red/, dest/not_measured/
  result-color  dest/ok/green/, dest/ok/red/, dest/cpu_error/green/, ...   (default with both CSVs)
  color-result  dest/green/ok/, dest/red/cpu_error/, ...
  none          all ROMs directly in dest/
A cart that is missing from the other CSV goes to "untested" / "unbenchmarked".

Existing files in dest are skipped unless -overwrite is given; -dryrun only shows what
would be copied. A list of the copied ROMs is written to dest/copied.csv.

Examples:
  python sort_v32.py -tests v32/test_results.csv -bench v32/bench_results.csv -dest sorted
      every ROM, in dest/<result>/<colour>/
  python sort_v32.py -tests v32/test_results.csv -bench v32/bench_results.csv -dest good \\
                     -results OK -by color
      only the carts that tested OK, in dest/green|yellow|red/
  python sort_v32.py -tests v32/test_results.csv -dest problems -results BLACK_SCREEN CPU_ERROR -by result
  python sort_v32.py -bench v32/bench_results.csv -dest fast -colors green -by none
"""

import argparse
import csv
import os
import re
import shutil
import sys
from collections import Counter

CART_EXT = re.compile(r"(?i)\.(p8(\.png)?|tic)$")


def rom_name(cart):
    """Cart file name (as in the CSVs) -> ROM file name: 'Game.p8.png' -> 'Game.v32'."""
    return CART_EXT.sub("", cart) + ".v32"


def load_csv(path, column):
    """{cart: value of `column`} from a test / bench CSV."""
    out = {}
    with open(path, newline="", encoding="utf-8-sig") as fh:
        for row in csv.DictReader(fh):
            if "Cart" not in row or column not in row:
                sys.exit("%s has no '%s' column -- is it the right CSV?" % (path, column))
            out[row["Cart"]] = (row[column] or "").strip()
    return out


def bench_colour(path):
    """{cart: colour}; older bench CSVs without a Severity column get it worked out."""
    with open(path, newline="", encoding="utf-8-sig") as fh:
        rows = list(csv.DictReader(fh))
    out = {}
    for r in rows:
        sev = (r.get("Severity") or "").strip()
        if not sev:   # same rules as bench_v32.py
            try:
                ovr, p95, n = float(r["OverrunPct"]), float(r["P95CPU"]), int(r["Overruns"])
                sev = "red" if (ovr > 5 or p95 >= 100) else ("yellow" if n else "green")
            except (KeyError, TypeError, ValueError):
                sev = "not measured"
        out[r["Cart"]] = sev
    return out


def folder_name(value):
    return value.strip().lower().replace(" ", "_") or "unknown"


def index_roms(folder, recursive):
    """{rom file name (lower case): path}; with -recursive the shallowest match wins."""
    found = {}
    if recursive:
        for root, dirs, files in os.walk(folder):
            dirs.sort()
            for f in files:
                if f.lower().endswith(".v32"):
                    found.setdefault(f.lower(), os.path.join(root, f))
    else:
        for f in os.listdir(folder):
            p = os.path.join(folder, f)
            if f.lower().endswith(".v32") and os.path.isfile(p):
                found[f.lower()] = p
    return found


def main():
    ap = argparse.ArgumentParser(description="Copy Vircon32 ROMs into subfolders by test result and/or "
                                             "benchmark colour.", allow_abbrev=False)
    ap.add_argument("-tests", "--tests", help="test_results.csv from test_v32.py")
    ap.add_argument("-bench", "--bench", help="bench_results.csv from bench_v32.py")
    ap.add_argument("-dest", "--dest", required=True, help="destination folder")
    ap.add_argument("-roms", "--roms", nargs="+", metavar="FOLDER",
                    help="folder(s) with the .v32 ROMs, searched in this order "
                         "(default: the folder of the first CSV)")
    ap.add_argument("-recursive", "--recursive", action="store_true", help="also search the -roms subfolders")
    ap.add_argument("-results", "--results", nargs="+", metavar="RESULT",
                    help="only these test results, e.g. OK BLACK_SCREEN CPU_ERROR (needs -tests)")
    ap.add_argument("-colors", "--colors", "-colours", nargs="+", metavar="COLOR",
                    help="only these benchmark colours: green yellow red 'not measured' (needs -bench)")
    ap.add_argument("-by", "--by", choices=("result", "color", "result-color", "color-result", "none"),
                    help="subfolders (default: result-color with both CSVs, else result or color)")
    ap.add_argument("-overwrite", "--overwrite", action="store_true", help="replace files already in -dest")
    ap.add_argument("-dryrun", "--dry-run", action="store_true", help="only show what would be copied")
    args = ap.parse_args()

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not args.tests and not args.bench:
        ap.error("give -tests and/or -bench")
    if args.results and not args.tests:
        ap.error("-results needs -tests")
    if args.colors and not args.bench:
        ap.error("-colors needs -bench")
    by = args.by or ("result-color" if args.tests and args.bench else ("result" if args.tests else "color"))
    if "result" in by and not args.tests:
        ap.error("-by %s needs -tests" % by)
    if "color" in by and not args.bench:
        ap.error("-by %s needs -bench" % by)

    tests = load_csv(args.tests, "Result") if args.tests else {}
    colours = bench_colour(args.bench) if args.bench else {}
    roms_dirs = [os.path.abspath(os.path.expanduser(d)) for d in
                 (args.roms or [os.path.dirname(os.path.abspath(args.tests or args.bench))])]
    for d in roms_dirs:
        if not os.path.isdir(d):
            sys.exit("ROM folder not found: %s" % d)
    dest = os.path.abspath(os.path.expanduser(args.dest))
    roms = {}
    for d in roms_dirs:                      # earlier folders win
        for k, v in index_roms(d, args.recursive).items():
            roms.setdefault(k, v)
    roms_dir = "; ".join(roms_dirs)

    want_results = {r.upper() for r in args.results} if args.results else None
    want_colours = {c.lower() for c in args.colors} if args.colors else None

    carts = sorted(set(tests) | set(colours), key=str.lower)
    copied, counts, skipped, missing, filtered = [], Counter(), 0, [], 0
    for cart in carts:
        result = tests.get(cart, "UNTESTED") if args.tests else ""
        colour = colours.get(cart, "unbenchmarked") if args.bench else ""
        if want_results is not None and result.upper() not in want_results:
            filtered += 1
            continue
        if want_colours is not None and colour.lower() not in want_colours:
            filtered += 1
            continue
        parts = {"result": [folder_name(result)], "color": [folder_name(colour)],
                 "result-color": [folder_name(result), folder_name(colour)],
                 "color-result": [folder_name(colour), folder_name(result)], "none": []}[by]
        sub = os.path.join(*parts) if parts else ""
        name = rom_name(cart)
        src = roms.get(name.lower())
        if not src:
            missing.append(name)
            continue
        target = os.path.join(dest, sub, name)
        if os.path.exists(target) and not args.overwrite:
            skipped += 1
            continue
        if not args.dry_run:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(src, target)
        counts[sub or "."] += 1
        copied.append({"Rom": name, "Cart": cart, "Result": result, "Color": colour,
                       "Folder": sub or ".", "Source": src})

    if copied and not args.dry_run:
        with open(os.path.join(dest, "copied.csv"), "w", newline="", encoding="utf-8-sig") as fh:
            w = csv.DictWriter(fh, fieldnames=list(copied[0]), quoting=csv.QUOTE_ALL)
            w.writeheader()
            w.writerows(copied)

    print("%s %d ROMs from %s to %s (subfolders: %s)" % (
        "Would copy" if args.dry_run else "Copied", len(copied), roms_dir, dest, by))
    for sub, n in sorted(counts.items()):
        print("  %5d  %s" % (n, sub))
    if filtered:
        print("  %d carts left out by -results / -colors" % filtered)
    if skipped:
        print("  %d already in the destination (skipped; -overwrite to replace)" % skipped)
    if missing:
        print("  %d carts have no ROM in %s%s, e.g. %s" % (
            len(missing), roms_dir, "" if args.recursive else " (try -recursive or -roms)", ", ".join(missing[:3])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
