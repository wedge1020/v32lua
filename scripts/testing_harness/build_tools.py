#!/usr/bin/env python3
"""
Compile (or just check) the tools the *_v32.py scripts need.

  v32lua             required: C:\\github\\v32lua\\bin\\v32lua.exe   (the Lua -> Vircon32 compiler)
  assemble, packrom  required: C:\\utils\\vircon32\\devtools        (official Vircon32 DevTools;
                     download, not built here -- see below)
  v32orun            test_v32.py / screenshot_v32.py / bench_v32.py: C:\\github\\v32sim\\tools\\oracle\\bin\\v32orun.exe
                     (v32sim's headless runner on the official Vircon32 CPU core; v32lua no longer carries one,
                     and v32bench is now its -b option)
  StandardBios.v32   screenshot_v32.py / test_v32.py -blank (BIOS font), from ComputerSoftware
  Pillow             screenshot_v32.py, test_v32.py -blank, make_site_v32.py covers
  emulator           make_site_v32.py: C:\\github\\vircon32_games (Vircon32Web.*)

v32orun is built from v32sim (tools/oracle/orun.cpp) and the official Vircon32 sources (ComputerSoftware), the BIOS comes from those;
-clone fetches them from https://github.com/vircon32/ComputerSoftware when they're missing.
The DevTools (assemble.exe, packrom.exe and their DLLs) are the prebuilt Windows download
from https://github.com/vircon32/ComputerSoftware/releases ("DevTools"), unzipped into
C:\\utils\\vircon32\\devtools.

After building, a smoke test compiles a tiny PICO-8 cart with v32lua, assembles and packs
it with the DevTools, and runs it on v32orun.

Needs MSYS2 (C:\\msys64) with the mingw64 gcc/g++/make:
  pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-make
v32lua's Makefile also uses sed / uname, which come from MSYS2's own C:\\msys64\\usr\\bin.

Usage:
  python build_tools.py                 # build everything that can be built, then smoke test
  python build_tools.py -check          # only report which tools are found
  python build_tools.py -only v32lua    # only these: v32lua v32orun
  python build_tools.py -clone          # also git clone ComputerSoftware if it's missing
"""

import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

IS_WINDOWS = os.name == "nt"
EXE = ".exe" if IS_WINDOWS else ""
BASE = r"C:\github" if IS_WINDOWS else os.path.expanduser("~/github")
CS_URL = "https://github.com/vircon32/ComputerSoftware"
DEVTOOLS_URL = "https://github.com/vircon32/ComputerSoftware/releases"
GREEN, RED, YELLOW, RESET = "\033[32m", "\033[31m", "\033[33m", "\033[0m"

# smallest useful PICO-8 cart: clears the screen and prints, every frame
TEST_CART = "pico-8 cartridge // http://www.pico-8.com\nversion 41\n__lua__\n-- smoke test\n" \
            "function _draw()\n cls(1)\n print(\"hello\", 40, 60, 7)\nend\n"


def msys_paths():
    """[mingw64\\bin, usr\\bin] that exist: gcc/g++/mingw32-make, and the sed/uname/sh
    v32lua's Makefile runs. The PATH's gcc wins over C:\\msys64."""
    out = []
    gcc = shutil.which("gcc")
    if gcc:
        out.append(os.path.dirname(gcc))
    elif IS_WINDOWS and os.path.isfile(r"C:\msys64\mingw64\bin\gcc.exe"):
        out.append(r"C:\msys64\mingw64\bin")
    if IS_WINDOWS and os.path.isdir(r"C:\msys64\usr\bin"):
        out.append(r"C:\msys64\usr\bin")
    return out


def tool_env(paths):
    env = dict(os.environ)
    env["PATH"] = os.pathsep.join(paths + [env.get("PATH", "")])
    return env


def run(cmd, cwd, env, show=True):
    if show:
        print("> " + " ".join('"%s"' % c if " " in c else c for c in cmd), flush=True)
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, errors="replace")
    return p.returncode, p.stdout + p.stderr


def locked(path):
    """True when the file exists but can't be opened for writing -- on Windows that's an
    exe that is running (e.g. build_v32.py is busy), so the linker couldn't replace it."""
    if not os.path.exists(path):
        return False
    try:
        with open(path, "r+b"):
            return False
    except PermissionError:
        return True


def ok(msg):
    print("%sOK%s  %s" % (GREEN, RESET, msg))


def bad(msg):
    print("%sFAILED%s  %s" % (RED, RESET, msg))


def warn(msg):
    print("%s%s%s" % (YELLOW, msg, RESET))


# ------------------------------------------------------------------ builds

def build_v32lua(args, env):
    src = args.v32lua
    if not os.path.isfile(os.path.join(src, "Makefile")):
        bad("v32lua sources not found in %s (-v32lua)" % src)
        return False
    exe = os.path.join(src, "bin", "v32lua" + EXE)
    if locked(exe):
        bad("%s is in use (is build_v32.py / test_v32.py running?): wait for it to finish, then run this again" % exe)
        return False
    if IS_WINDOWS and not shutil.which("sed", path=env["PATH"]):
        bad("sed not found: v32lua's Makefile needs MSYS2's C:\\msys64\\usr\\bin")
        return False
    make = shutil.which("mingw32-make", path=env["PATH"]) or shutil.which("make", path=env["PATH"])
    if not make:
        bad("mingw32-make / make not found (pacman -S mingw-w64-x86_64-make)")
        return False
    code, out = run([make, "CC=gcc"], src, env)
    if code != 0 or not os.path.isfile(exe):
        print("\n".join(line for line in out.splitlines() if "error" in line.lower()) or out[-2000:])
        bad("v32lua build")
        return False
    code, out = run([exe, "--version"], src, env, show=False)
    ok("v32lua built: %s (%s)" % (exe, out.split("\n")[0].split(" ", 1)[-1].strip()))
    return True


def computer_software(args, env):
    cs = args.cs
    if os.path.isdir(os.path.join(cs, "DesktopEmulator", "ConsoleLogic")):
        return cs
    if not args.clone:
        bad("Vircon32 sources not found in %s (-cs); run with -clone to fetch %s" % (cs, CS_URL))
        return None
    git = shutil.which("git")
    if not git:
        bad("git not found, can't clone %s" % CS_URL)
        return None
    code, out = run([git, "clone", "--depth", "1", CS_URL, cs], os.path.dirname(cs) or ".", env)
    if code != 0:
        print(out[-1500:])
        bad("git clone %s" % CS_URL)
        return None
    return cs


def build_runner(args, env, cs):
    """v32orun, from v32sim's tools/oracle/orun.cpp and the official ConsoleLogic in ComputerSoftware
    (what v32sim's tools/oracle/build.sh does, without needing bash). The one change to the official
    sources: V32CPUProcessors.cpp is compiled from a copy whose float -> int conversion calls
    v32orun_cfi() (--cfi=arm, --cfi-log). Linked statically on Windows: runs without MSYS2 on the PATH."""
    src = os.path.join(args.v32sim, "tools", "oracle", "orun.cpp")
    if not os.path.isfile(src):
        bad("orun.cpp not found in %s (-v32sim: a v32sim checkout)" % args.v32sim)
        return False
    out_dir = os.path.join(args.v32sim, "tools", "oracle", "bin")
    os.makedirs(out_dir, exist_ok=True)
    out_exe = os.path.join(out_dir, "v32orun" + EXE)
    if locked(out_exe):
        bad("%s is in use (is a test / bench / screenshot script running?)" % out_exe)
        return False
    gen = os.path.join(out_dir, ".gen")
    os.makedirs(gen, exist_ok=True)
    cl = os.path.join(cs, "DesktopEmulator", "ConsoleLogic")
    with open(os.path.join(cl, "V32CPUProcessors.cpp"), encoding="utf-8") as fh:
        cpu = fh.read()
    old = "Register->AsInteger = (int32_t)Register->AsFloat;"
    if cpu.count(old) != 1:
        bad("V32CPUProcessors.cpp changed upstream; can't apply the CFI patch")
        return False
    cpu = "#include <cstdint>\nextern int32_t v32orun_cfi(float f, int32_t ip);\n" + \
          cpu.replace(old, "Register->AsInteger = ::v32orun_cfi(Register->AsFloat, CPU.InstructionPointer.AsInteger);")
    with open(os.path.join(gen, "V32CPUProcessors.cpp"), "w", encoding="utf-8") as fh:
        fh.write(cpu)
    gxx = shutil.which("g++", path=env["PATH"])
    if not gxx:
        bad("g++ not found (pacman -S mingw-w64-x86_64-gcc)")
        return False
    others = sorted(os.path.join(cl, f) for f in os.listdir(cl) if f.endswith(".cpp") and f != "V32CPUProcessors.cpp")
    cmd = [gxx, "-std=c++17", "-O2", "-w", "-I" + cl, "-I" + os.path.join(cs, "DesktopEmulator"),
           "-I" + os.path.join(cs, "VirconDefinitions"), src, os.path.join(gen, "V32CPUProcessors.cpp")] + others + ["-o", out_exe]
    if IS_WINDOWS:
        cmd.insert(1, "-static")
    code, out = run(cmd, out_dir, env)
    shutil.rmtree(gen, ignore_errors=True)
    if code != 0:
        print(out[-2000:])
        bad("v32orun build")
        return False
    ok("v32orun built: %s" % out_exe)
    return True


# ------------------------------------------------------------------ smoke test

def devtool(args, name):
    for n in (name + EXE, name):
        p = os.path.join(args.devtools, n)
        if os.path.isfile(p):
            return p
    return None


def smoke_test(args, env):
    """tiny .p8 -> v32lua -> assemble -> packrom (-> v32run): the chain build_v32.py runs."""
    v32lua = os.path.join(args.v32lua, "bin", "v32lua" + EXE)
    assemble, packrom = devtool(args, "assemble"), devtool(args, "packrom")
    if not (os.path.isfile(v32lua) and assemble and packrom):
        warn("smoke test skipped: needs v32lua and the DevTools (assemble, packrom)")
        return None
    tmp = tempfile.mkdtemp(prefix="v32lua_test_")
    try:
        with open(os.path.join(tmp, "cart.p8"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(TEST_CART)
        steps = [(v32lua, ["--api", "pico8", "cart.p8"], "cart.asm"), (assemble, ["cart.asm"], "cart.vbin"),
                 (packrom, ["cart.xml"], "cart.v32")]
        for exe, a, product in steps:
            code, out = run([exe] + a, tmp, env)
            if code != 0 or not os.path.isfile(os.path.join(tmp, product)):
                print(out[-1500:])
                bad("smoke test: %s" % os.path.basename(exe))
                return False
        v32run = os.path.join(args.v32sim, "tools", "oracle", "bin", "v32orun" + EXE)
        if os.path.isfile(v32run):
            code, out = run([v32run, "cart.vbin", "-f", "30", "-q"], tmp, env)
            if "STATUS FRAMES_EXHAUSTED" not in out:
                print(out[-1500:])
                bad("smoke test: the cart didn't run 30 frames on v32orun")
                return False
            ok("smoke test: .p8 -> v32lua -> assemble -> packrom -> 30 frames on v32orun")
        else:
            ok("smoke test: .p8 -> v32lua -> assemble -> packrom (v32orun not built: not run)")
        return True
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ------------------------------------------------------------------ check

def check(args):
    def line(found, name, where, note=""):
        colour = GREEN if found else (RED if note.startswith("required") else YELLOW)
        print("  %s%-8s%s  %-17s %s%s" % (colour, "found" if found else "missing", RESET, name, where,
                                          "" if found or not note else "  (%s)" % note))

    print("\nTools:")
    missing_required = False
    rows = [("v32lua", os.path.join(args.v32lua, "bin", "v32lua" + EXE), "required: python build_tools.py -only v32lua"),
            ("assemble", devtool(args, "assemble") or os.path.join(args.devtools, "assemble" + EXE),
             "required: download the DevTools from " + DEVTOOLS_URL),
            ("packrom", devtool(args, "packrom") or os.path.join(args.devtools, "packrom" + EXE),
             "required: download the DevTools from " + DEVTOOLS_URL),
            ("v32orun", os.path.join(args.v32sim, "tools", "oracle", "bin", "v32orun" + EXE),
             "test_v32.py / screenshot_v32.py / bench_v32.py / make_site_v32.py screenshots"),
            ("StandardBios.v32", args.bios, "screenshot_v32.py BIOS-font text; -clone fetches it")]
    for name, path, note in rows:
        found = os.path.isfile(path)
        line(found, name, path, note)
        missing_required |= not found and note.startswith("required")
    emu = [f for f in ("Vircon32Web.html", "Vircon32Web.js", "Vircon32Web.wasm", "Vircon32Web.data")
           if not os.path.isfile(os.path.join(args.emulator, f))]
    line(not emu, "emulator", args.emulator, "make_site_v32.py Play button")
    line(importlib.util.find_spec("PIL") is not None, "Pillow", "",
         "screenshot_v32.py, test_v32.py -blank, site covers: pip install -r requirements.txt")
    paths = msys_paths()
    gcc = next((p for p in paths if os.path.isfile(os.path.join(p, "gcc" + EXE))), "")
    line(bool(gcc), "gcc", gcc, "needed to compile: install MSYS2 mingw64")
    return not missing_required


def main():
    ap = argparse.ArgumentParser(description="Compile / check the tools the *_v32.py scripts need.",
                                 allow_abbrev=False)
    ap.add_argument("-check", "--check", action="store_true", help="only report which tools are found")
    ap.add_argument("-only", "--only", nargs="+", choices=("v32lua", "v32orun"),
                    help="build only these (default: all)")
    ap.add_argument("-clone", "--clone", action="store_true",
                    help="git clone ComputerSoftware (Vircon32 sources + BIOS) when -cs is missing")
    ap.add_argument("-notest", "--no-test", action="store_true", help="skip the smoke test")
    ap.add_argument("-v32lua", "--v32lua", default=os.path.join(BASE, "v32lua"), help="v32lua checkout")
    ap.add_argument("-v32sim", "--v32sim", default=os.path.join(BASE, "v32sim"),
                    help="v32sim checkout (v32orun is built from its tools/oracle/orun.cpp into tools/oracle/bin)")
    ap.add_argument("-cs", "--cs", default=os.path.join(BASE, "ComputerSoftware"),
                    help="checkout of %s (for v32orun / the BIOS)" % CS_URL)
    ap.add_argument("-devtools", "--devtools", default=r"C:\utils\vircon32\devtools" if IS_WINDOWS
                    else os.path.expanduser("~/vircon32/devtools"), help="Vircon32 DevTools folder (checked only)")
    ap.add_argument("-bios", "--bios", default=None,
                    help="StandardBios.v32 (default: <cs>/DesktopEmulator/Data/Bios/StandardBios.v32)")
    ap.add_argument("-emulator", "--emulator", default=os.path.join(BASE, "vircon32_games"),
                    help="web emulator files (checked only)")
    args = ap.parse_args()
    for k in ("v32lua", "v32sim", "cs", "devtools", "emulator"):
        setattr(args, k, os.path.abspath(os.path.expanduser(getattr(args, k))))
    args.bios = os.path.abspath(args.bios) if args.bios else \
        os.path.join(args.cs, "DesktopEmulator", "Data", "Bios", "StandardBios.v32")
    if IS_WINDOWS:
        os.system("")  # ANSI colours

    if args.check:
        return 0 if check(args) else 1

    paths = msys_paths()
    if not paths or not any(os.path.isfile(os.path.join(p, "gcc" + EXE)) for p in paths):
        bad("gcc not found: install MSYS2 (https://www.msys2.org) and run "
            "pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-make")
        return 1
    env = tool_env(paths)
    want = args.only or ["v32lua", "v32orun"]
    results = {}
    if "v32lua" in want:
        results["v32lua"] = build_v32lua(args, env)
    if "v32orun" in want:
        cs = computer_software(args, env)
        results["v32orun"] = build_runner(args, env, cs) if cs else False
    tested = None if args.no_test else smoke_test(args, env)
    required_ok = check(args)
    if results.get("v32lua") is False or tested is False or not required_ok:
        return 1
    if not all(results.values()):
        warn("\nOptional tools that failed: the scripts that need them won't run (see the list above).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
