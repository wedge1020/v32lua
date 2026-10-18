# TIC-80 → Vircon32

These scripts compile  TIC-80 carts (`.tic`) to  Vircon32 carts (`.v32`) 
with [v32lua](https://github.com/wedge1020/v32lua),  test, benchmark and 
screenshot them  headless, and build a  website where every cart  can be 
played in the browser.                                                   

The  Python  scripts  are  the   same  ones  as  in  `E:\Emulation\pico8 
downloader\pico8_carts`. They handle both  PICO-8 (`.p8`, `.p8.png`) and 
TIC-80 (`.tic`) carts; this README describes them for TIC-80.            

| File | Does |
|---|---|
| `build_v32.py` | Compiles the carts in this folder to `v32/<name>.v32` |
| `test_v32.py` | Runs the built carts headless and reports crashes (panic, CPU error, halt, black screen) |
| `bench_v32.py` | Measures how much of the Vircon32 CPU each cart uses |
| `screenshot_v32.py` | Takes title and in-game PNG screenshots |
| `sort_v32.py` | Copies ROMs into folders by test result and/or benchmark colour |
| `make_site_v32.py` | Builds a static website with covers, filters and a Play button |
| `build_tools.py` | Compiles and checks the tools the scripts above need |
| `requirements.txt` | Python packages (Pillow) |

## Quick start

```
pip install -r requirements.txt         # Pillow (screenshots, covers)
python build_tools.py                    # compile v32lua, v32run, v32bench + smoke test
python build_v32.py -filter "*.tic"      # -> v32/*.v32
python test_v32.py -filter "*.tic" -blank
python bench_v32.py -filter "*.tic"
python screenshot_v32.py -filter "*.tic"
python make_site_v32.py -v32 v32 -out site -link
python -m http.server 8000 --directory site      # then open http://localhost:8000/
```

`-filter "*.tic"` is  optional when the folder only  holds `.tic` carts. 
`The default filter is *.p8 *.p8.png *.tic`.                             

## Requirements

### Software

| What | Needed for | Notes |
|---|---|---|
| Python 3.8+ | all scripts | |
| Pillow (`pip install -r requirements.txt`) | `screenshot_v32.py` (required), `test_v32.py -blank`, `make_site_v32.py` covers | |
| MSYS2 (`C:\msys64`) with mingw64 gcc, g++ and make | compiling the tools below | `pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-make` in an MSYS2 shell |
| Git checkouts in `C:\github` | the tools below | `v32lua`, `v32bench`, `ComputerSoftware` (official Vircon32 sources), `vircon32_games` (web emulator) |

### Prebuilt tools

These have  to be built  or installed before  the scripts can  use them. 
Each script  finds them at  the default path shown,  or at the  path you 
pass with the option in the last column.                                 

| Tool | Required? | Used by | Default path | Option |
|---|---|---|---|---|
| `v32lua` | **yes** | build, test, bench, screenshot (they all compile the cart) | `C:\github\v32lua\bin\v32lua.exe` | `-v32lua PATH` |
| `assemble`, `packrom` | **yes** | build (assemble + pack); test, bench and screenshot (assemble) | `C:\utils\vircon32\devtools` | `-devtools DIR` |
| `v32run` | for test / screenshot | official Vircon32 CPU core, headless | `C:\github\v32lua\tools\headless\v32run.exe` | `-v32run PATH` |
| `v32bench` | for bench | v32run plus per-frame cycle counts | `C:\github\v32bench\v32bench.exe` | `-v32bench PATH` |
| `StandardBios.v32` | screenshot (recommended), `test -blank` | The BIOS font, for text a cart prints with it | `C:\github\ComputerSoftware\SimplifiedEmulator\Data\Bios\StandardBios.v32` | `-bios PATH` |
| Vircon32 web emulator | site | Play button: `Vircon32Web.html/.js/.wasm/.data`, `favicon.ico`, `icons/` | `C:\github\vircon32_games` | `-emulator DIR` |

Test and screenshot need v32run, and bench needs v32bench.               

**The DevTools  are not compiled  here.** Download the  official Windows 
**DevTools**  from https://github.com/vircon32/ComputerSoftware/releases 
and unzip them into  `C:\utils\vircon32\devtools`, keeping the DLLs next 
to the exes. Only `assemble.exe` and `packrom.exe` are used.             

### Compiling

`build_tools.py` compiles  everything and then  checks it. It  runs from 
`any shell and finds C:\msys64` by itself:                               

```
python build_tools.py                   # v32lua, v32run, v32bench, then the smoke test
python build_tools.py -check            # only report what's found / missing
python build_tools.py -only v32lua      # only some: v32lua v32run v32bench
python build_tools.py -clone            # also git clone ComputerSoftware (sources + BIOS) if missing
```

| Option | Default | Meaning |
|---|---|---|
| `-v32lua DIR` | `C:\github\v32lua` | v32lua checkout |
| `-v32bench DIR` | `C:\github\v32bench` | Where `v32bench.exe` is built (created if needed) |
| `-cs DIR` | `C:\github\ComputerSoftware` | Official Vircon32 sources, from https://github.com/vircon32/ComputerSoftware (needed for v32run, v32bench and the BIOS) |
| `-devtools DIR` | `C:\utils\vircon32\devtools` | DevTools (only checked) |
| `-bios FILE` | `<cs>\SimplifiedEmulator\Data\Bios\StandardBios.v32` | BIOS (only checked) |
| `-emulator DIR` | `C:\github\vircon32_games` | Web emulator (only checked) |
| `-notest` | | Skip the smoke test |

The smoke  test compiles a tiny  PICO-8 cart with v32lua,  assembles and 
packs it with the DevTools, and runs  it 30 frames on v32run. That's the 
same chain `build_v32.py` and `test_v32.py` use.                         

> **Close running  scripts first.** Windows  locks a running  `.exe`, so 
> v32lua can't be rebuilt while `build_v32.py` or `test_v32.py` is busy. 
> `build_tools.py` detects this  and stops with "... is  in use" instead 
> of half-rebuilding.                                                    

**Rebuild v32lua after every `git pull`  of v32lua, and then rebuild the 
carts.** The  `.v32` files contain  v32lua's runtime, so old  carts keep 
the old runtime's bugs.                                                  

The manual steps below do the same thing.

**v32lua** needs  make's shell tools  (`sed`, `uname`),  so run it  in an
**MSYS2 MinGW64** shell:

```
cd /c/github/v32lua
mingw32-make CC=gcc            # -> bin/v32lua.exe
```

From cmd or  PowerShell, put both MSYS2 folders on  the PATH first: `set 
PATH=C:\msys64\mingw64\bin;C:\msys64\usr\bin;%PATH%`.                    

**v32run**, in an  MSYS2 MinGW64 shell. It needs `python3`  on the PATH, 
and the exe isn't linked statically, so it needs `C:\msys64\mingw64\bin` 
on the PATH to run:                                                      

```
cd /c/github/v32lua/tools/headless
./build.sh /c/github/ComputerSoftware          # -> v32run.exe (+ Assembler.exe)
```

**v32bench** is v32run plus a `-b`  option that prints the CPU cycles of 
every frame  (`FC <frame> <cycles> <overrun>`).  `build_tools.py` builds 
it  itself, from  the same  `v32run.cpp` and  `ComputerSoftware` sources 
with  that option  patched  in;  nothing else  is  needed.  If you  have 
`C:\github\v32bench\build_v32bench.py`, it  does the same by  hand, from 
any shell:                                                               

```
python C:\github\v32bench\build_v32bench.py C:\github\v32lua C:\github\ComputerSoftware
```

## Folders and files

| Path | Contents |
|---|---|
| `*.tic` | The carts. The scripts read them and never modify them |
| `NOT_LUA/` | Carts set aside because they aren't written in Lua (v32lua only compiles Lua). They aren't scanned, because the scripts only look in this folder, not its subfolders |
| `v32/` | Built carts plus `results.csv`, `test_results.csv`, `bench_results.csv`, `bench_routines.csv` |
| `v32/logs/` | Tool output of failed builds |
| `v32/test_logs/` | Run output of carts that didn't pass the test |
| `v32/screenshots/title`, `v32/screenshots/game` | PNG screenshots |
| `work/`, `work_test/`, `work_bench/` | Temporary folders, one `run<pid>` per running script. A leftover `run<pid>` is from a run that was interrupted and can be deleted when no script is running |

A cart's name  is its file name without the  extension: `8 bit panda.tic`
becomes `v32/8 bit panda.v32`.

## Options common to build, test, bench and screenshot

| Option | Default | Meaning |
|---|---|---|
| `-sourcedir DIR` | this folder | Folder with the carts (not searched recursively) |
| `-filter PAT [PAT ...]` | `*.p8 *.p8.png *.tic` | File name patterns |
| `-start NAME` | | Begin at this cart (alphabetical order); the extension is optional |
| `-max N` | all | Do at most N carts |
| `-jobs N` | CPU cores | Carts processed in parallel |
| `-timeoutsec N` | 120 (bench 180) | Time limit per tool run |
| `-v32lua PATH` | `C:\github\v32lua\bin\v32lua.exe` | |
| `-devtools DIR` | `C:\utils\vircon32\devtools` | |
| `-fastcircles` | | Pass `--fast-circles` to v32lua: big filled circles drawn as one scaled disc (faster; about 1.5% of edge pixels differ) |
| `-nobezel` | | Pass `--no-bezel` (PICO-8 only: no side panels) |

Test,  bench and  screenshot  **recompile** each  cart  with debug  info 
instead  of  using the  `.v32`.  Give  them  the same  `-fastcircles`  / 
`-nobezel` as the build, so they check the same program. By default they 
only do carts that have a ROM in `v32/`; `-all` includes the rest.       

Results are  **merged** into the CSVs:  a run over a  subset only updates
those carts' rows.

---

## build_v32.py — compile carts

For each cart:
1. The cart is copied into a work folder as `cart.tic`.
2. `v32lua --api tic80 cart.tic` compiles it, `assemble` assembles it and `packrom` packs it.
3. The result is copied to `v32/<name>.v32`.

The ROM  title is `[TIC80] <title>`,  taken from the cart's  `-- title:` 
tag, or from the file name when the cart has no title.                   

| Option | Default | Meaning |
|---|---|---|
| `-rate 11025\|22050\|44100` | not passed (v32lua uses 22050) | Sample rate of the sounds v32lua synthesizes |
| `-skipexisting` | | Don't rebuild carts that already have a `.v32` |
| `-png2p8 IN OUT` | | PICO-8 only: convert one `.p8.png` to a text `.p8` and stop |

`v32/results.csv` columns: `Cart`, `Format` (tic/text/png), `Result` (OK/FAILED), `FailedAt` (v32lua,
assemble or packrom), `Error`.

```
python build_v32.py -filter "*.tic" -skipexisting
python build_v32.py -start "8 bit panda" -max 20 -jobs 4
```

## test_v32.py — headless crash test

Each cart is rebuilt with debug info and run `-runs` times for `-frames` 
frames on v32run,  each run with a different random  button pattern. All 
buttons except  Start are  pressed, because  Start opens  v32lua's pause 
screen. The first  failure is reported, along with the  Lua function and 
source line it happened in:                                              

| Result | Meaning |
|---|---|
| `OK` | All runs finished all frames |
| `PANIC` | The red "V32LUA PANIC" screen: a runtime error (calling a non-function, indexing a non-table, out of memory, ...) |
| `CPU_ERROR` | The blue Vircon32 hardware error screen (invalid memory access, stack overflow, division error, ...) |
| `HALT` | The program stopped without an error |
| `TIMEOUT` | v32run took longer than `-timeoutsec` |
| `BUILD_FAILED` | The cart no longer compiles or assembles with the current tools |
| `BLACK_SCREEN` | With `-blank`: no crash, but the game area stayed black (or one flat colour) in every checked frame of run 1 |

| Option | Default | Meaning |
|---|---|---|
| `-frames N` | 1800 | Frames per run (60 = 1 s) |
| `-runs N` | 3 | Runs per cart |
| `-blank` | | Also check for black screens (needs Pillow and `screenshot_v32.py`) |
| `-blankstep N` | 60 | `-blank`: check one frame every N frames |
| `-bios FILE` | `StandardBios.v32` path | `-blank`: so that text in the BIOS font counts as shown |
| `-v32run PATH` | `C:\github\v32lua\tools\headless\v32run.exe` | |
| `-all` | | Also test carts without a ROM |

Output: `v32/test_results.csv` (Cart, Format, Result, Error, Frame, Run, 
OFunction, Line, Code, verruns) and `v32/test_logs/<name>.log`.          

## bench_v32.py — CPU load

The Vircon32 CPU  has 250,000 cycles per frame. A  frame that needs more 
is an  **overrun**: the game slows  down on real hardware.  Each cart is 
rebuilt with  debug info  and run  on v32bench.  With the  default fixed 
input, every  cart gets  the same  presses: A then  B at  4 s,  then all 
buttons in turn. The first `-warmup` frames are left out.                

Per  cart: average,  median, 95th-percentile  and maximum  load; overrun 
frames;  the  three busiest  routines  (Lua  functions by  name,  v32lua 
runtime routines  as `__builtin_...`); and a  severity: **green** (never 
over budget),  **yellow** (occasional  overruns: at  most 5%,  p95 under 
100%), **red** (over 5% overruns, or  p95 at 100%), **not measured**. At 
the end it lists the heaviest carts and the v32lua runtime routines that 
use the most time across all carts (`v32/bench_routines.csv`). Those are 
the routines worth optimising in v32lua.                                 

| Option | Default | Meaning |
|---|---|---|
| `-frames N` | 1800 | Frames to run |
| `-warmup N` | 60 | First frames left out |
| `-input fixed\|random\|none` | fixed | Same script for every cart / random mashing / no buttons |
| `-seed N` | 1 | Pattern for `-input random` |
| `-top N` | 15 | Heaviest carts listed |
| `-routines N` | 20 | Runtime routines listed |
| `-v32bench PATH` | `C:\github\v32bench\v32bench.exe` | |
| `-all` | | Also carts without a ROM |

## screenshot_v32.py — screenshots

Each cart is rebuilt and run once on v32run with GPU logging. The logged 
draws are redrawn  into 640×360 PNGs using the cart's  textures and the 
BIOS font.  The result  is close  for normal sprites  and text,  but not 
pixel-exact.                                                             

- **Title shot** at frame `-title`, before any button is pressed.
- A, then B (half a second later), are pressed once at frame `-press`.
- **In-game shot** at frame `-game`.

A  shot  that  comes  out  as  one flat  colour  (a  fade-in,  say)  is. 
retried at other  frames Output: `v32/screenshots/title/<name>.png` and. 
`v32/screenshots/game/<name>.png`                                      . 

| Option | Default | Meaning |
|---|---|---|
| `-title N` | 180 | Frame of the title shot |
| `-press N` | 240 | Frame where A, then B, are pressed |
| `-game N` | 540 | Frame of the in-game shot |
| `-notitle` / `-nogame` | | Skip one of the shots |
| `-blankretries N` | 3 | Retries for a flat-colour shot |
| `-scale N` | 1 | Enlarge the PNGs N times |
| `-list FILE` | | Only the carts named in this file (one file name per line) |
| `-skipexisting` | | Skip carts that already have screenshots |
| `-outdir DIR` | `v32/screenshots` | |
| `-v32run PATH`, `-bios FILE` | see above | |
| `-all` | | Also carts without a ROM |

## sort_v32.py — sort ROMs into folders

This **copies**  ROMs into  subfolders by  test result  and/or benchmark 
colour; the  originals stay where  they are. A  list of what  was copied 
goes to `<dest>/copied.csv`.                                             

| Option | Meaning |
|---|---|
| `-tests CSV` | `test_results.csv` (at least one of `-tests` / `-bench` is required) |
| `-bench CSV` | `bench_results.csv` |
| `-dest DIR` | Destination (required) |
| `-results R [R ...]` | Only these test results, e.g. `OK PANIC` |
| `-colors C [C ...]` | Only these colours: `green yellow red "not measured"` |
| `-by result\|color\|result-color\|color-result\|none` | Subfolder layout (default: `result-color` with both CSVs). Carts missing from the other CSV go to `untested` / `unbenchmarked` |
| `-roms DIR [DIR ...]` | Where the ROMs are (default: the folder of the first CSV); `-recursive` searches subfolders |
| `-overwrite` | Replace files already in `-dest` |
| `-dryrun` | Only show what would be copied |

```
python sort_v32.py -tests v32/test_results.csv -bench v32/bench_results.csv -dest good -results OK -by color
```

## make_site_v32.py — website

Builds one page with a card for every tested cart. Each card has a cover 
(the screenshot cropped to the TIC-80  screen), the test result with the 
failing  function,  the  benchmark,  a  **Play**  button  (the  Vircon32 
web  emulator in  an  overlay),  a download  button,  and  links to  the 
screenshots. There is a search box,  and filter buttons for test result, 
benchmark colour  and platform. Filters  in the same group  combine with 
OR; different  groups combine  with AND.  Carts without  screenshots are 
shot with `screenshot_v32.py` first.                                     

| Option | Default | Meaning |
|---|---|---|
| `-out DIR` | **required** | Site folder |
| `-v32 DIR [DIR ...]` | | Result folder(s); several are merged into one site, e.g. this `v32` and the PICO-8 one |
| `-tests CSV` / `-bench CSV` | | A single set given by its CSV files (instead of, or besides, `-v32`) |
| `-roms DIR [DIR ...]`, `-recursive` | | Extra ROM folders (e.g. after `sort_v32.py`) |
| `-shots DIR` | each set's `screenshots/` | One screenshot folder for all sets |
| `-sourcedir DIR [DIR ...]` | the folder above each result folder | Where the carts are, for missing screenshots |
| `-noshots` | | Don't make missing screenshots (placeholder covers) |
| `-cover game\|title` | game | Screenshot preferred for the cover |
| `-results` / `-colors` | | Only these test results / benchmark colours |
| `-title "text"` | Vircon32 test results | Page title |
| `-emulator DIR` | `C:\github\vircon32_games` | Web emulator files |
| `-link` | | Hard-link the ROMs instead of copying them (same drive only) |
| `-clean` | | Empty `games/` and `covers/` first |
| `-fastcircles`, `-nobezel` | | Passed to `screenshot_v32.py` |

```
python make_site_v32.py -v32 v32 -out site -link
python make_site_v32.py -v32 v32 "E:/Emulation/pico8 downloader/pico8_carts/v32" -out site -results OK
```

The site  must be opened through  a web server (the  emulator loads ROMs 
over HTTP). In the  web emulator: arrows = D-pad, **X** =  A, **Z** = B, 
**S** = X, **A** = Y, **Q** = L, **W** = R, **Enter** = Start.           
