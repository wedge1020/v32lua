#!/usr/bin/env python3
"""
Build a static website of tested Vircon32 ROMs, like C:/github/vircon32_games: one page
with a card per cart, search, tag filters, a download button, and a Play button that
opens the ROM in the Vircon32 web emulator in an overlay.

Every card is tagged with its test result from test_v32.py's test_results.csv
  OK, Black screen, CPU error, Halt, Panic (and Timeout / Build failed when present)
and, when a benchmark CSV is given, with bench_v32.py's colour
  green (never over the CPU budget), yellow (occasional slow frames), red (often too slow)
plus its platform (PICO-8 / TIC-80). The tags are also the filter buttons: filters in
the same group combine with OR (Panic or CPU error), different groups with AND.

  -v32 folder [folder ...]   result folder(s) to merge into one site, e.g. your PICO-8 and
                             TIC-80 v32 folders. From each: test_results.csv (required),
                             bench_results.csv (if there), the .v32 ROMs, screenshots/ and,
                             one level up, the carts themselves
  -tests / -bench csv        a single set given by its CSV files (instead of / besides -v32)
  -out   folder              (required) where the site is written: index.html, the ROMs
                             in games/, 315x250 covers in covers/, the full title and
                             in-game screenshots in screenshots/title|game/ (linked from
                             each card), and the emulator files
  -roms  folder(s)           extra ROM folders, searched after each set's own folder (e.g.
                             ROMs moved into colour folders); -recursive searches subfolders
  -shots folder              one screenshot folder for all sets (default: each set's
                             <folder>/screenshots). Covers are cropped to the game area, so
                             the PICO-8 side bezel is left out
  (missing screenshots)      carts without a screenshot are shot with screenshot_v32.py
                             (next to this script), into the set's screenshots folder;
                             -noshots skips that, -sourcedir says where the carts are (one
                             folder per set), -fastcircles / -nobezel shoot the same build
                             as your ROMs
  -emulator folder           folder with Vircon32Web.html/.js/.wasm/.data, favicon.ico and
                             icons/ (default: C:/github/vircon32_games)
  -results / -colors         only carts with these test results / benchmark colours
  -title "text"              page title (default: Vircon32 test results)
  -link                      hard-link the ROMs into the site instead of copying them
                             (same drive only; saves space for thousands of ROMs)
  -clean                     empty the site's games/ and covers/ first
  -jobs N                    covers made in parallel (default: CPU cores)

Re-running updates the site: ROMs and covers that are already there and unchanged are
kept. The page's own title comes from each ROM's header (the cart title v32lua gave it).

The emulator loads ROMs over HTTP, so open the site through a web server, e.g.
  python -m http.server 8000 --directory <out folder>     then  http://localhost:8000/
(opening index.html straight from disk shows the page, but Play can't load the ROMs).

Examples:
  python make_site_v32.py -v32 v32 -out site
  python make_site_v32.py -v32 "E:/Emulation/pico8 downloader/pico8_carts/v32" E:/Emulation/TIC-80_new/v32 -out site
Needs Pillow for proper covers (without it the screenshots are copied as they are).
"""

import argparse
import csv
import datetime
import html
import os
import re
import shutil
import subprocess
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

try:
    from PIL import Image, ImageEnhance, ImageFilter
    HAVE_PIL = True
except ImportError:
    HAVE_PIL = False

CART_EXT = re.compile(r"(?i)\.(p8(\.png)?|tic)$")
COVER_W, COVER_H = 315, 250
# the game's own screen on the 640x360 Vircon32 screen (from v32lua's runtime):
# PICO-8 128x128 at 2.75x from (144,4) -- the side bezels are outside it -- and TIC-80 at 2.625x
GAME_AREA = {"pico-8": (144, 4, 496, 356), "tic-80": (0, 0, 630, 357)}

# test result -> (tag, filter label, chip colour)
RESULTS = {
    "OK": ("ok", "OK", "#7cfc00"),
    "BLACK_SCREEN": ("black-screen", "Black screen", "#9aa3a8"),
    "CPU_ERROR": ("cpu-error", "CPU error", "#6f97f2"),
    "HALT": ("halt", "Halt", "#ffb347"),
    "PANIC": ("panic", "Panic", "#ff5c5c"),
    "TIMEOUT": ("timeout", "Timeout", "#ffb347"),
    "BUILD_FAILED": ("build-failed", "Build failed", "#c080ff"),
}
OTHER_RESULT = ("other", "Other", "#c0c0c0")
COLOURS = {  # benchmark colour -> (tag, filter label, chip colour, tooltip)
    "green": ("green", "Green", "#4cd964", "never over the CPU budget"),
    "yellow": ("yellow", "Yellow", "#ffd23f", "occasional overrun frames (at most 5%, p95 under 100%)"),
    "red": ("red", "Red", "#ff5c5c", "often too slow (over 5% overrun frames, or p95 at 100%)"),
    "not measured": ("not-measured", "Not measured", "#9aa3a8", "didn't build, or stopped before the warm-up"),
}
PLATFORMS = {"pico-8": ("pico-8", "PICO-8", "#ff77a8"), "tic-80": ("tic-80", "TIC-80", "#41a6f6")}


# ------------------------------------------------------------------ inputs

def read_csv(path):
    with open(path, newline="", encoding="utf-8-sig") as fh:
        return {r["Cart"]: r for r in csv.DictReader(fh)}


def bench_colour(row):
    sev = (row.get("Severity") or "").strip()
    if sev:
        return sev
    try:   # older bench CSVs: same rules as bench_v32.py
        ovr, p95, n = float(row["OverrunPct"]), float(row["P95CPU"]), int(row["Overruns"])
        return "red" if (ovr > 5 or p95 >= 100) else ("yellow" if n else "green")
    except (KeyError, TypeError, ValueError):
        return "not measured"


def index_roms(folders, recursive):
    """{rom file name (lower case): path}; earlier folders win, then shallower paths."""
    found = {}
    for folder in folders:
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
                    found.setdefault(f.lower(), p)
    return found


def rom_title(path):
    """The cart title from the ROM header (64 bytes at offset 16, zero-terminated)."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(80)
    except OSError:
        return ""
    if head[:8] != b"V32-CART":
        return ""
    raw = head[16:80].split(b"\0", 1)[0]
    try:
        return raw.decode("utf-8").strip()
    except UnicodeDecodeError:
        return raw.decode("latin-1").strip()


def display_title(title, base):
    t = re.sub(r"^\[(PICO8|TIC80)\]\s*", "", title or "").strip()
    return t or base


def slugify(text, used):
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "rom"
    slug = slug[:80].rstrip("-")
    final, n = slug, 2
    while final in used:
        final, n = "%s-%d" % (slug, n), n + 1
    used.add(final)
    return final


def find_shot(shots, base, prefer):
    """screenshot_v32.py's <shots>/game|title/<base>.png, the preferred kind first."""
    if not shots:
        return None
    order = ("game", "title") if prefer == "game" else ("title", "game")
    return next((os.path.join(shots, k, base + ".png") for k in order
                 if os.path.isfile(os.path.join(shots, k, base + ".png"))), None)


def natural_key(text):
    return [int(p) if p.isdigit() else p for p in re.split(r"(\d+)", text.lower())]


# ------------------------------------------------------------------ files

def same_file(src, dst):
    try:
        a, b = os.stat(src), os.stat(dst)
    except OSError:
        return False
    return a.st_size == b.st_size and int(a.st_mtime) == int(b.st_mtime)


def put_rom(src, dst, link):
    if same_file(src, dst) or (link and os.path.exists(dst) and os.path.samefile(src, dst)):
        return "kept"
    if os.path.exists(dst):
        os.remove(dst)
    if link:
        try:
            os.link(src, dst)
            return "linked"
        except OSError:
            pass   # different drive: fall back to copying
    shutil.copy2(src, dst)
    return "copied"


def make_cover(shot, dst, platform):
    """315x250 cover: the game area of the screenshot, fitted over a blurred, darkened
    copy of itself (like vircon32_games' covers)."""
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(shot):
        return "kept"
    if not HAVE_PIL:
        shutil.copy2(shot, dst)
        return "copied"
    img = Image.open(shot).convert("RGB")
    if img.size == (640, 360) and platform in GAME_AREA:
        img = img.crop(GAME_AREA[platform])
    w, h = img.size
    fill = max(COVER_W / w, COVER_H / h)
    bg = img.resize((max(1, round(w * fill)), max(1, round(h * fill))), Image.Resampling.BILINEAR)
    left, top = (bg.width - COVER_W) // 2, (bg.height - COVER_H) // 2
    bg = bg.crop((left, top, left + COVER_W, top + COVER_H)).filter(ImageFilter.GaussianBlur(10))
    bg = ImageEnhance.Brightness(bg).enhance(0.55)
    fit = min(COVER_W / w, COVER_H / h)
    fg = img.resize((max(1, round(w * fit)), max(1, round(h * fit))),
                    Image.Resampling.NEAREST if fit >= 1 else Image.Resampling.LANCZOS)
    bg.paste(fg, ((COVER_W - fg.width) // 2, (COVER_H - fg.height) // 2))
    bg.save(dst, optimize=True)
    return "made"


PLACEHOLDER_SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="315" height="250" viewBox="0 0 315 250">
<rect width="315" height="250" fill="#0e120d"/>
<text x="157.5" y="118" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="30"
 font-weight="700"><tspan fill="#5fce87">V</tspan><tspan fill="#2fd8e8">ircon</tspan><tspan fill="#6f97f2">32</tspan></text>
<text x="157.5" y="150" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="14"
 fill="#9db296">no screenshot</text>
</svg>
"""


# ------------------------------------------------------------------ page

CSS = """
  :root {
    color-scheme: dark;
    --bg: #0b0e0b;
    --panel: #141813;
    --panel-border: #263323;
    --text: #e8f2e4;
    --muted: #9db296;
    --accent: #7cfc00;
    --accent-dim: #4c8f14;
    --link: #7fd4ff;
  }
  * { box-sizing: border-box; }
  html, body {
    margin: 0; padding: 0; background: var(--bg); color: var(--text);
    font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }
  a { color: var(--link); }
  header {
    padding: 3em 1.5em 1.5em; text-align: center;
    background: radial-gradient(ellipse at top, rgba(124, 252, 0, 0.08), transparent 60%), var(--bg);
    border-bottom: 1px solid var(--panel-border);
  }
  header h1 { margin: 0 0 0.2em; font-size: 2em; letter-spacing: 0.02em; }
  header h1 .logo { display: inline-block; padding-bottom: 0.08em; border-bottom: 0.09em solid #7cfc00; }
  header h1 .logo .v { color: #5fce87; }
  header h1 .logo .ircon { color: #2fd8e8; }
  header h1 .logo .n32 { color: #6f97f2; }
  header p { margin: 0.3em 0; color: var(--muted); }
  header .summary { margin-top: 0.9em; display: flex; flex-wrap: wrap; gap: 0.4em; justify-content: center; }
  main { max-width: 1200px; margin: 0 auto; padding: 2em 1.5em 4em; }
  .toolbar { margin: 0 0 2.2em; }
  .toolbar .search-row { display: flex; align-items: center; gap: 0.8em; flex-wrap: wrap; }
  .toolbar input[type="search"] {
    flex: 1 1 260px; min-width: 0; padding: 0.6em 0.9em; border-radius: 6px;
    border: 1px solid var(--panel-border); background: var(--panel); color: var(--text); font: inherit;
  }
  .toolbar input[type="search"]:focus { outline: none; border-color: var(--accent-dim); }
  .toolbar input[type="search"]::placeholder { color: var(--muted); }
  .toolbar .result-count { color: var(--muted); font-size: 0.9em; white-space: nowrap; }
  .filters { display: flex; flex-wrap: wrap; align-items: center; gap: 0.45em; margin-top: 0.9em; }
  .filters .group-label { color: var(--muted); font-size: 0.8em; min-width: 7.5em; }
  .filters button {
    background: var(--panel); border: 1px solid var(--panel-border); color: var(--muted);
    border-radius: 999px; padding: 0.3em 0.85em; font: inherit; font-size: 0.85em; cursor: pointer;
  }
  .filters button:hover { color: var(--text); border-color: var(--accent-dim); }
  .filters button .dot { display: inline-block; width: 0.6em; height: 0.6em; border-radius: 50%; margin-right: 0.4em; }
  .filters button[aria-pressed="true"] { background: var(--accent-dim); border-color: var(--accent); color: #0b0e0b; font-weight: 600; }
  .filters button .n { opacity: 0.7; margin-left: 0.3em; }
  .filters button.zero { opacity: 0.4; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(330px, 1fr)); gap: 1.4em; }
  .card {
    background: var(--panel); border: 1px solid var(--panel-border); border-radius: 8px; overflow: hidden;
    display: flex; flex-direction: column; transition: transform 0.15s ease, border-color 0.15s ease;
  }
  .card:hover { transform: translateY(-3px); border-color: var(--accent-dim); }
  .card[hidden] { display: none; }
  .card .cover { width: 100%; aspect-ratio: 315 / 250; object-fit: cover; display: block; background: #000; }
  .card .body { padding: 0.9em 1em 1.1em; display: flex; flex-direction: column; flex: 1; }
  .card h2 { margin: 0 0 0.3em; font-size: 1.05em; }
  .card h2 a { color: var(--text); text-decoration: none; }
  .card h2 a:hover { color: var(--accent); }
  .card .file { color: var(--muted); font-size: 0.78em; margin: 0 0 0.6em; word-break: break-word; }
  .card .desc { color: var(--muted); font-size: 0.85em; margin: 0 0 0.5em; }
  .card .desc strong { color: var(--text); font-weight: 600; }
  .card code {
    display: block; font-size: 0.78em; color: #d7e3d2; background: #0e120d; border: 1px solid var(--panel-border);
    border-radius: 4px; padding: 0.3em 0.5em; margin: 0 0 0.6em; white-space: pre-wrap; word-break: break-word;
  }
  .card .spacer { flex: 1; }
  .chip, .card .tags span {
    font-size: 0.7em; white-space: nowrap; letter-spacing: 0.03em; text-transform: uppercase;
    border-radius: 999px; padding: 0.15em 0.6em; border: 1px solid; background: #0e120d;
  }
  .card .tags { display: flex; flex-wrap: wrap; gap: 0.3em; margin: 0.4em 0 0.9em; }
  .card .actions { display: flex; gap: 0.6em; align-items: center; flex-wrap: wrap; row-gap: 0.5em; }
  .play-button {
    display: inline-block; background: var(--accent); color: #0b0e0b; font-weight: 600; text-decoration: none;
    padding: 0.45em 0.9em; border-radius: 5px; font-size: 0.9em;
  }
  .play-button:hover { background: #96ff33; }
  .download-button {
    flex: 0 0 auto; display: inline-flex; align-items: center; justify-content: center; width: 2em; height: 2em;
    border-radius: 6px; border: 1px solid var(--panel-border); background: var(--panel); color: var(--muted);
    text-decoration: none; font-size: 0.95em; line-height: 1;
  }
  .download-button:hover { color: var(--accent); border-color: var(--accent-dim); }
  .shot-link { font-size: 0.85em; color: var(--muted); text-decoration: none; }
  .shot-link:hover { color: var(--link); }
  #no-results { color: var(--muted); text-align: center; padding: 2em 0 4em; }
  #no-results[hidden] { display: none; }
  footer { max-width: 1200px; margin: 0 auto; padding: 0 1.5em 3em; color: var(--muted); font-size: 0.85em; }
  footer .controls-table { display: inline-grid; grid-template-columns: repeat(4, auto); gap: 0.2em 1.2em; margin: 0.6em 0 0; font-family: monospace; }
  footer .controls-table span.key { color: var(--accent); }
  footer hr { border: none; border-top: 1px solid var(--panel-border); margin: 2em 0 1.2em; }
  #game-overlay {
    position: fixed; inset: 0; z-index: 10; display: flex; align-items: center; justify-content: center;
    background: rgba(0, 0, 0, 0.88); padding: 3vh 3vw;
  }
  #game-overlay.hidden { display: none; }
  #game-modal {
    position: relative; width: 640px; height: 360px; max-width: 100%; max-height: 100%; aspect-ratio: 16 / 9;
    background: #000; border: 1px solid rgba(255, 255, 255, 0.25); border-radius: 6px; overflow: hidden;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.6);
  }
  #game-frame { width: 100%; height: 100%; border: 0; display: block; }
  #game-close-button {
    position: absolute; top: 0.4em; right: 0.5em; z-index: 1; background: rgba(0, 0, 0, 0.6);
    border: 1px solid rgba(255, 255, 255, 0.4); color: #eee; border-radius: 4px; width: 1.8em; height: 1.8em;
    line-height: 1.6em; text-align: center; padding: 0; font-size: 1em; cursor: pointer;
  }
  #game-close-button:hover { background: rgba(0, 0, 0, 0.85); }
"""

SCRIPT = """
<script>
  // Play/title links stay real <a href> targets (new tab / no-JS still work); a plain
  // left-click opens the same URL in an overlay. Closing resets the iframe so the
  // emulator (and its audio) stops.
  var gameOverlay = document.getElementById('game-overlay');
  var gameFrame = document.getElementById('game-frame');
  function openGame(url) { gameFrame.src = url; gameOverlay.classList.remove('hidden'); }
  function closeGame() { gameOverlay.classList.add('hidden'); gameFrame.src = 'about:blank'; }
  document.addEventListener('click', function (e) {
    var link = e.target.closest ? e.target.closest('a[href^="Vircon32Web.html?rom="]') : null;
    if (!link || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    openGame(link.getAttribute('href'));
  });
  document.getElementById('game-close-button').addEventListener('click', closeGame);
  gameOverlay.addEventListener('click', function (e) { if (e.target === gameOverlay) closeGame(); });
  window.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !gameOverlay.classList.contains('hidden')) closeGame();
  });

  // Search + tag filters: buttons in the same group are OR-ed, groups are AND-ed.
  (function () {
    var searchInput = document.getElementById('search');
    var resultCount = document.getElementById('result-count');
    var noResults = document.getElementById('no-results');
    var buttons = Array.prototype.slice.call(document.querySelectorAll('#filters button'));
    var cards = Array.prototype.slice.call(document.querySelectorAll('.card')).map(function (el) {
      return { el: el, haystack: el.getAttribute('data-search'), tags: el.getAttribute('data-tags').split(' ') };
    });
    var active = {};   // group -> [tags]

    var allGroups = buttons.map(function (b) { return b.getAttribute('data-group'); })
      .filter(function (g, i, a) { return a.indexOf(g) === i; });

    function applyFilter() {
      var terms = searchInput.value.toLowerCase().split(/\\s+/).filter(Boolean);
      var groups = Object.keys(active).filter(function (g) { return active[g].length; });
      var counts = {};   // group -> tag -> cards
      var shown = 0;
      cards.forEach(function (card) {
        if (!terms.every(function (t) { return card.haystack.indexOf(t) !== -1; })) {
          card.el.hidden = true;
          return;
        }
        // the active groups this card doesn't match
        var failed = groups.filter(function (g) {
          return !active[g].some(function (t) { return card.tags.indexOf(t) !== -1; });
        });
        card.el.hidden = failed.length !== 0;
        if (!failed.length) shown++;
        // faceted counts: a button's number is how many cards match the search and every
        // OTHER group's selection -- what you'd see after (also) picking that button
        allGroups.forEach(function (g) {
          if (failed.length > 1 || (failed.length === 1 && failed[0] !== g)) return;
          var c = counts[g] = counts[g] || {};
          card.tags.forEach(function (t) { c[t] = (c[t] || 0) + 1; });
        });
      });
      buttons.forEach(function (b) {
        var g = b.getAttribute('data-group'), t = b.getAttribute('data-tag');
        var n = (counts[g] && counts[g][t]) || 0;
        b.querySelector('.n').textContent = n;
        b.classList.toggle('zero', n === 0 && b.getAttribute('aria-pressed') !== 'true');
      });
      noResults.hidden = shown !== 0;
      resultCount.textContent = (terms.length || groups.length)
        ? shown + ' of ' + cards.length + ' ROMs' : cards.length + ' ROMs';
    }

    buttons.forEach(function (button) {
      button.addEventListener('click', function () {
        var g = button.getAttribute('data-group'), t = button.getAttribute('data-tag');
        active[g] = active[g] || [];
        var i = active[g].indexOf(t);
        if (i === -1) active[g].push(t); else active[g].splice(i, 1);
        button.setAttribute('aria-pressed', i === -1 ? 'true' : 'false');
        applyFilter();
      });
    });
    searchInput.addEventListener('input', applyFilter);
    searchInput.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && searchInput.value) { e.stopPropagation(); searchInput.value = ''; applyFilter(); }
    });
    window.addEventListener('keydown', function (e) {
      if (e.key === '/' && document.activeElement !== searchInput) { e.preventDefault(); searchInput.focus(); }
    });
    applyFilter();
  })();
</script>
"""


def chip(label, colour, title=""):
    t = ' title="%s"' % html.escape(title, quote=True) if title else ""
    return '<span style="color:%s;border-color:%s"%s>%s</span>' % (colour, colour, t, html.escape(label))


def test_text(row):
    """One line about the test result, from the CSV's Error / Function / Line / Frame / Run."""
    res = row.get("Result", "")
    if res == "OK":
        return "<strong>Test:</strong> ran without errors."
    what = {"PANIC": "Panic", "CPU_ERROR": "CPU error", "HALT": "Halted", "BLACK_SCREEN": "Black screen",
            "TIMEOUT": "Timeout", "BUILD_FAILED": "Build failed"}.get(res, res.title())
    parts = ["<strong>%s:</strong> %s" % (html.escape(what), html.escape(row.get("Error", "") or ""))]
    if row.get("Function"):
        loc = "in %s" % row["Function"]
        if row.get("Line"):
            loc += " (line %s)" % row["Line"]
        parts.append(html.escape(loc))
    if row.get("Frame") not in (None, "", "0") and res not in ("BLACK_SCREEN", "BUILD_FAILED"):
        parts.append("at frame %s%s" % (html.escape(row["Frame"]),
                                        " of run %s" % html.escape(row["Run"]) if row.get("Run") else ""))
    return " ".join(parts) + "."


def bench_text(row):
    if not row or row.get("AvgCPU", "") == "":
        return ""
    txt = "<strong>CPU:</strong> avg %s%% &middot; p95 %s%% &middot; max %s%% &middot; %s%% slow frames" % tuple(
        html.escape(str(row.get(k, ""))) for k in ("AvgCPU", "P95CPU", "MaxCPU", "OverrunPct"))
    if row.get("Hot1"):
        txt += " &middot; most time in %s" % html.escape(row["Hot1"])
    return txt


def build_page(entries, args, stats):
    today = datetime.date.today().isoformat()
    groups = [("result", "Test result", [(v[0], v[1], v[2], "") for v in list(RESULTS.values()) + [OTHER_RESULT]]),
              ("color", "Benchmark", [(v[0], v[1], v[2], v[3]) for v in COLOURS.values()]),
              ("platform", "Platform", [(v[0], v[1], v[2], "") for v in PLATFORMS.values()])]
    count = Counter(t for e in entries for t in e["tags"])
    rows = []
    for gid, glabel, tags in groups:
        used = [t for t in tags if count[t[0]]]
        if not used:
            continue
        btns = "".join('<button type="button" data-group="%s" data-tag="%s" aria-pressed="false"%s>'
                       '<span class="dot" style="background:%s"></span>%s<span class="n">%d</span></button>'
                       % (gid, tag, ' title="%s"' % html.escape(tip, quote=True) if tip else "", colour,
                          html.escape(label), count[tag]) for tag, label, colour, tip in used)
        rows.append('      <div class="filters" role="group" aria-label="%s"><span class="group-label">%s</span>%s</div>'
                    % (glabel, glabel, btns))
    summary = " ".join(chip("%s %d" % (label, count[tag]), colour, tip) for gid, _, tags in groups[:2]
                       for tag, label, colour, tip in tags if count[tag])

    cards = []
    for e in entries:
        href = "Vircon32Web.html?rom=games/" + e["slug"] + ".v32"
        title = html.escape(e["title"])
        chips = "".join(chip(*c) for c in e["chips"])
        code = '<code>%s</code>' % html.escape(e["code"][:160]) if e["code"] else ""
        bench = '<p class="desc">%s</p>' % e["bench"] if e["bench"] else ""
        hay = html.escape(" ".join([e["title"], e["cart"], e["error"], e["function"]] + e["tags"]).lower(), quote=True)
        cards.append(
            '      <div class="card" data-tags="%s" data-search="%s">\n'
            '        <img class="cover" src="covers/%s" alt="%s cover" loading="lazy">\n'
            '        <div class="body">\n'
            '          <h2><a href="%s">%s</a></h2>\n'
            '          <p class="file">%s</p>\n'
            '          <p class="desc">%s</p>\n'
            '          %s%s<div class="spacer"></div>\n'
            '          <p class="tags">%s</p>\n'
            '          <div class="actions">\n'
            '            <a class="play-button" href="%s">&#9654; Play</a>\n'
            '            <a class="download-button" href="games/%s.v32" download title="Download the ROM" '
            'aria-label="Download the %s ROM">&#11015;</a>\n'
            '%s'
            '          </div>\n        </div>\n      </div>'
            % (" ".join(e["tags"]), hay, e["cover"], html.escape(e["title"], quote=True), href, title,
               html.escape(e["cart"]), e["test"], bench, code, chips, href, e["slug"],
               html.escape(e["title"], quote=True),
               "".join('            <a class="shot-link" href="%s" target="_blank" rel="noopener" '
                       'title="%s screenshot">%s</a>\n' % (e["full_shots"][k], k.title(), k.title())
                       for k in ("title", "game") if k in e.get("full_shots", {}))))

    head_title = html.escape(args.title)
    return """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%(title)s</title>
<meta name="description" content="%(n)d Vircon32 ROMs with their test results and CPU benchmark, playable in the browser.">
<meta name="robots" content="noindex">
<meta name="theme-color" content="#0b0e0b">
<meta name="color-scheme" content="dark">
<link rel="icon" href="favicon.ico" sizes="any">
<link rel="icon" type="image/png" sizes="32x32" href="icons/icon-32.png">
<style>%(css)s</style>
</head>
<body>

<header>
  <h1><span class="logo"><span class="v">V</span><span class="ircon">ircon</span><span class="n32">32</span></span> %(title_rest)s</h1>
  <p>%(n)d ROMs built with v32lua, with their headless test result%(bench_note)s. Generated %(today)s.</p>
  <div class="summary">%(summary)s</div>
</header>

<main>
  <div class="toolbar">
    <div class="search-row">
      <input id="search" type="search" placeholder="Search by title, file name, error or function&hellip;"
        autocomplete="off" spellcheck="false" aria-label="Search">
      <span class="result-count" id="result-count">%(n)d ROMs</span>
    </div>
    <div id="filters">
%(filters)s
    </div>
  </div>

    <div class="grid">

%(cards)s

    </div>

  <p id="no-results" hidden>Nothing matches that search.</p>
</main>

<footer>
  <hr>
  <p><strong>Test result</strong>: each ROM ran headless on the official Vircon32 CPU core with random button
  presses (test_v32.py). OK = no errors; Panic = the red v32lua panic screen; CPU error = the blue Vircon32
  error screen; Halt = the program stopped; Black screen = the game area never showed anything.%(bench_foot)s</p>
  <p>All ROMs run in the same Vircon32 web emulator, with the console's default keyboard mapping:</p>
  <div class="controls-table">
    <span><span class="key">Arrows</span></span><span>D-pad</span>
    <span><span class="key">X</span></span><span>Button A</span>
    <span><span class="key">Z</span></span><span>Button B</span>
    <span><span class="key">S</span></span><span>Button X</span>
    <span><span class="key">A</span></span><span>Button Y</span>
    <span><span class="key">Q</span></span><span>Button L</span>
    <span><span class="key">W</span></span><span>Button R</span>
    <span><span class="key">Enter</span></span><span>Start</span>
  </div>
  <p>Vircon32 and its emulator were created by Carra &mdash; <a href="https://www.vircon32.com" target="_blank" rel="noopener">www.vircon32.com</a></p>
</footer>

<div id="game-overlay" class="hidden">
  <div id="game-modal">
    <button id="game-close-button" aria-label="Close">&times;</button>
    <iframe id="game-frame" allow="autoplay; fullscreen" allowfullscreen></iframe>
  </div>
</div>
%(script)s
</body>
</html>
""" % {"title": head_title, "n": len(entries), "css": CSS, "today": today, "summary": summary,
       "title_rest": html.escape(re.sub(r"^\s*vircon32\s*", "", args.title, flags=re.I) or args.title),
       "bench_note": " and CPU benchmark" if stats["bench"] else "",
       "filters": "\n".join(rows), "cards": "\n\n".join(cards), "script": SCRIPT,
       "bench_foot": (" <strong>Benchmark</strong> (bench_v32.py): green = never over the CPU budget, yellow = "
                      "occasional slow frames, red = often too slow on real hardware.") if stats["bench"] else ""}


# ------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser(description="Build a static site of tested Vircon32 ROMs.", allow_abbrev=False)
    ap.add_argument("-v32", "--v32", nargs="+", metavar="FOLDER",
                    help="result folder(s) to merge into one site: each has test_results.csv, optionally "
                         "bench_results.csv, the .v32 ROMs and screenshots/, with the carts one level up")
    ap.add_argument("-tests", "--tests", help="a test_results.csv (a single set, instead of / besides -v32)")
    ap.add_argument("-bench", "--bench", help="bench_results.csv for -tests (adds colour tags)")
    ap.add_argument("-out", "--out", required=True, help="output folder for the site")
    ap.add_argument("-roms", "--roms", nargs="+", metavar="FOLDER",
                    help="extra folder(s) with .v32 ROMs, searched after each set's own folder "
                         "(e.g. ROMs moved into colour folders)")
    ap.add_argument("-recursive", "--recursive", action="store_true", help="also search the ROM folders' subfolders")
    ap.add_argument("-shots", "--shots", help="one screenshot folder for all sets (default: each set's "
                                              "<folder>/screenshots)")
    ap.add_argument("-sourcedir", "--source-dir", nargs="+", metavar="FOLDER",
                    help="carts folder(s) for making missing screenshots, one per -v32 folder in the same "
                         "order, then one for -tests (default: the folder above each result folder)")
    ap.add_argument("-noshots", "--no-shots", action="store_true",
                    help="don't run screenshot_v32.py for carts without screenshots (placeholder covers)")
    ap.add_argument("-fastcircles", "--fast-circles", action="store_true",
                    help="passed to screenshot_v32.py: shoot the same build as the ROMs")
    ap.add_argument("-nobezel", "--no-bezel", action="store_true",
                    help="passed to screenshot_v32.py: shoot the same build as the ROMs")
    ap.add_argument("-cover", "--cover", choices=("game", "title"), default="game",
                    help="which screenshot to prefer for the cover (default: game)")
    ap.add_argument("-emulator", "--emulator", default=r"C:\github\vircon32_games" if os.name == "nt"
                    else os.path.expanduser("~/github/vircon32_games"),
                    help="folder with Vircon32Web.html/.js/.wasm/.data, favicon.ico and icons/")
    ap.add_argument("-results", "--results", nargs="+", metavar="RESULT", help="only these test results, e.g. OK PANIC")
    ap.add_argument("-colors", "--colors", "-colours", nargs="+", metavar="COLOR",
                    help="only these benchmark colours (carts without a benchmark are then left out)")
    ap.add_argument("-title", "--title", default="Vircon32 test results", help="page title")
    ap.add_argument("-link", "--link", action="store_true", help="hard-link the ROMs instead of copying them")
    ap.add_argument("-clean", "--clean", action="store_true", help="empty games/ and covers/ first")
    ap.add_argument("-jobs", "--jobs", type=int, default=os.cpu_count() or 4, help="covers made in parallel")
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not args.v32 and not args.tests:
        ap.error("give -v32 folder(s) and/or -tests")
    if args.bench and not args.tests:
        ap.error("-bench goes with -tests (a -v32 folder's bench_results.csv is found by itself)")

    def full(p):
        return os.path.abspath(os.path.expanduser(p))

    # one "set" per result folder: its CSVs, ROM folders, screenshots and carts
    extra_roms = [full(d) for d in (args.roms or [])]
    sources = [full(d) for d in (args.source_dir or [])]
    sets = []
    for d in [full(x) for x in (args.v32 or [])]:
        tests_csv = os.path.join(d, "test_results.csv")
        if not os.path.isfile(tests_csv):
            sys.exit("No test_results.csv in %s" % d)
        bench_csv = os.path.join(d, "bench_results.csv")
        sets.append({"name": d, "tests": tests_csv, "bench": bench_csv if os.path.isfile(bench_csv) else None,
                     "roms": [d] + extra_roms})
    if args.tests:
        t = full(args.tests)
        sets.append({"name": t, "tests": t, "bench": full(args.bench) if args.bench else None,
                     "roms": [os.path.dirname(t)] + extra_roms})
    for k, s in enumerate(sets):
        folder = os.path.dirname(s["tests"])
        s["source"] = sources[k] if k < len(sources) else os.path.dirname(folder)
        s["shots"] = full(args.shots) if args.shots else os.path.join(folder, "screenshots")
        for d in s["roms"]:
            if not os.path.isdir(d):
                sys.exit("ROM folder not found: %s" % d)
        s["rom_index"] = index_roms(s["roms"], args.recursive)
    any_bench = any(s["bench"] for s in sets)

    out = full(args.out)
    games_dir, covers_dir = os.path.join(out, "games"), os.path.join(out, "covers")
    if args.clean:
        for d in (games_dir, covers_dir):
            shutil.rmtree(d, ignore_errors=True)
    os.makedirs(games_dir, exist_ok=True)
    os.makedirs(covers_dir, exist_ok=True)
    if not HAVE_PIL:
        print("Pillow not installed: screenshots are used as covers without cropping/resizing")

    want_results = {r.upper() for r in args.results} if args.results else None
    want_colours = {c.lower() for c in args.colors} if args.colors else None
    entries, used_slugs, filtered = [], set(), 0
    for s in sets:
        tests = read_csv(s["tests"])
        bench = read_csv(s["bench"]) if s["bench"] else {}
        s["missing"] = 0
        for cart, row in tests.items():
            result = (row.get("Result") or "").upper()
            colour = bench_colour(bench[cart]) if cart in bench else ("not measured" if bench else "")
            if want_results is not None and result not in want_results:
                filtered += 1
                continue
            if want_colours is not None and colour not in want_colours:
                filtered += 1
                continue
            base = CART_EXT.sub("", cart)
            src = s["rom_index"].get((base + ".v32").lower())
            if not src:
                s["missing"] += 1
                continue
            platform = "tic-80" if cart.lower().endswith(".tic") else "pico-8"
            title = display_title(rom_title(src), base)
            rtag = RESULTS.get(result, OTHER_RESULT)
            tags, chips = [rtag[0]], [(rtag[1], rtag[2])]
            if colour in COLOURS:
                c = COLOURS[colour]
                tags.append(c[0])
                chips.append((c[1], c[2], c[3]))
            p = PLATFORMS[platform]
            tags.append(p[0])
            chips.append((p[1], p[2]))
            entries.append({"cart": cart, "base": base, "src": src, "set": s,
                            "slug": slugify(title if title != base else base, used_slugs),
                            "title": title, "platform": platform, "tags": tags, "chips": chips,
                            "shot": find_shot(s["shots"], base, args.cover),
                            "test": test_text(row), "bench": bench_text(bench.get(cart)),
                            "code": row.get("Code", "") or "", "error": row.get("Error", "") or "", "full_shots": {},
                            "function": row.get("Function", "") or ""})
    entries.sort(key=lambda e: (natural_key(e["title"]), e["cart"].lower()))

    # carts without a screenshot: let screenshot_v32.py make them (it rebuilds each cart from
    # its source and shoots the title and in-game screen), set by set, then pick them up
    shooter = os.path.join(os.path.dirname(os.path.abspath(__file__)), "screenshot_v32.py")
    for s in sets:
        no_shot = [e for e in entries if e["set"] is s and not e["shot"]]
        if not no_shot or args.no_shots:
            continue
        todo = [e for e in no_shot if os.path.isfile(os.path.join(s["source"], e["cart"]))]
        if not os.path.isfile(shooter):
            print("screenshot_v32.py not found next to this script: %d carts get a placeholder cover" % len(no_shot))
            continue
        if not todo:
            print("%d carts have no screenshot, and their carts aren't in %s (-sourcedir): placeholder covers"
                  % (len(no_shot), s["source"]))
            continue
        os.makedirs(s["shots"], exist_ok=True)
        list_file = os.path.join(out, "_shots_todo.txt")
        with open(list_file, "w", encoding="utf-8") as fh:
            fh.write("\n".join(e["cart"] for e in todo) + "\n")
        print("Making screenshots of %d carts from %s with screenshot_v32.py (into %s) ..."
              % (len(todo), s["source"], s["shots"]))
        cmd = [sys.executable, shooter, "-sourcedir", s["source"], "-all", "-list", list_file,
               "-outdir", s["shots"], "-jobs", str(args.jobs)]
        if args.fast_circles:
            cmd.append("-fastcircles")
        if args.no_bezel:
            cmd.append("-nobezel")
        subprocess.run(cmd)
        os.remove(list_file)
        for e in todo:
            e["shot"] = find_shot(s["shots"], e["base"], args.cover)
        print("  %d of %d got a screenshot" % (sum(1 for e in todo if e["shot"]), len(todo)))

    # ROMs and covers (in parallel: copying / image work)
    with open(os.path.join(covers_dir, "placeholder.svg"), "w", encoding="utf-8") as fh:
        fh.write(PLACEHOLDER_SVG)
    rom_count, cover_count = Counter(), Counter()

    shots_out = os.path.join(out, "screenshots")

    def do(e):
        r = put_rom(e["src"], os.path.join(games_dir, e["slug"] + ".v32"), args.link)
        # the full-size screenshots too, linked from the card
        for kind in ("title", "game"):
            src = os.path.join(e["set"]["shots"], kind, e["base"] + ".png")
            if os.path.isfile(src):
                os.makedirs(os.path.join(shots_out, kind), exist_ok=True)
                dst = os.path.join(shots_out, kind, e["slug"] + ".png")
                if not same_file(src, dst):
                    shutil.copy2(src, dst)
                e["full_shots"][kind] = "screenshots/%s/%s.png" % (kind, e["slug"])
        if e["shot"]:
            e["cover"] = e["slug"] + ".png"
            try:
                c = make_cover(e["shot"], os.path.join(covers_dir, e["cover"]), e["platform"])
            except OSError:
                e["cover"], c = "placeholder.svg", "failed"
        else:
            e["cover"], c = "placeholder.svg", "none"
        return r, c

    with ThreadPoolExecutor(max(1, args.jobs)) as ex:
        for r, c in ex.map(do, entries):
            rom_count[r] += 1
            cover_count[c] += 1

    # emulator, favicon and icons from the vircon32_games site
    emu = os.path.abspath(os.path.expanduser(args.emulator))
    copied_emu = 0
    for f in ("Vircon32Web.html", "Vircon32Web.js", "Vircon32Web.wasm", "Vircon32Web.data", "favicon.ico"):
        s = os.path.join(emu, f)
        if os.path.isfile(s):
            if not same_file(s, os.path.join(out, f)):
                shutil.copy2(s, os.path.join(out, f))
            copied_emu += 1
    if os.path.isdir(os.path.join(emu, "icons")):
        os.makedirs(os.path.join(out, "icons"), exist_ok=True)
        for f in os.listdir(os.path.join(emu, "icons")):
            shutil.copy2(os.path.join(emu, "icons", f), os.path.join(out, "icons", f))

    with open(os.path.join(out, "index.html"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(build_page(entries, args, {"bench": any_bench}))

    count = Counter(t for e in entries for t in e["tags"])
    print("Site written to %s: %d ROMs" % (out, len(entries)))
    print("  test results: " + ", ".join("%s %d" % (v[1], count[v[0]]) for v in list(RESULTS.values()) + [OTHER_RESULT]
                                         if count[v[0]]))
    if any_bench:
        print("  benchmark:    " + ", ".join("%s %d" % (v[1], count[v[0]]) for v in COLOURS.values() if count[v[0]]))
    print("  ROMs: %s" % ", ".join("%d %s" % (n, k) for k, n in sorted(rom_count.items())))
    print("  covers: %s%s" % (", ".join("%d %s" % (n, k) for k, n in sorted(cover_count.items())),
                              ""))
    if filtered:
        print("  %d carts left out by -results / -colors" % filtered)
    for s in sets:
        if s["missing"]:
            print("  %d tested carts from %s have no ROM in %s%s" % (s["missing"], s["name"], "; ".join(s["roms"]),
                                                                     "" if args.recursive else " (try -recursive / -roms)"))
    if copied_emu < 4:
        print("  emulator files not found in %s (-emulator): Play won't work" % emu)
    print("Open it through a web server, e.g.:  python -m http.server 8000 --directory \"%s\"" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
