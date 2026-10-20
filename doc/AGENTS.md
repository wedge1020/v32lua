# v32lua -- notes for agents

(`AGENTS.md` is the shared agent-instruction file; `CLAUDE.md` only imports it.)

v32lua is a Lua-subset compiler written in C (Flex/Bison + a hand-written
emitter): **Lua in, Vircon32 assembly (`.asm`) plus a cartridge `.xml` out.**
There is no VM and no interpreter; Lua compiles straight to native assembly.
It is a *substitute* for the Vircon32 C compiler, not a Lua implementation:
when real Lua and the console disagree, the console wins. Assembling
(`assemble`), asset conversion (`png2vircon`, `wav2vircon`) and packing
(`packrom`) are separate Vircon32 DevTools steps v32lua does not run.

## Writing Lua for v32lua

**Just write it, these work:** `local`/global variables; multiple assignment
and swaps; `while`, `repeat`, numeric and generic `for` (`pairs`/`ipairs`/your
own iterator); `break`, `goto`/`::label::`; closures with shared upvalues;
recursion; variadics `...` and multi-value returns (up to 32 values);
tables with the `:` method sugar; `setmetatable` with `__index`,
`__newindex`, `__call`, `__tostring`, `__len`, `__metatable`; string
methods (`s:sub()`, `rep`, `byte`, `find`, `lower`, `reverse`, `gsub`...);
long `[[strings]]`; `1e-3` literals; `& | ~ << >>` bitwise operators (and
PICO-8's extras in that mode); `__asm__("...{var}...")` / `__rawasm__`.

**Not ordinary Lua -- the mistakes agents make most:**
- **Every number is a float32.** No integer subtype; integers above 2^24 are
  inexact, bitwise results with more than 24 significant bits are rounded.
  Keep test arithmetic inside 2^24. Values are NaN-boxed (`doc/NaN_boxing.md`),
  so a raw 32-bit word can read back as `nil`.
- **`print(x, y, value)`** takes screen coordinates first and draws with the
  BIOS font. It is not stdout and not a function value (`type(print)` fails).
- **A program must define `main()` or `game_loop()`** (missing = compile
  error); `init()` is optional and runs once first. Top-level statements
  (globals, calls) run once at start via `__global_scope_initialization`,
  before `main()`/`game_loop()`. `game_loop()` gets a `WAIT` for free; in
  `main()` you must call `system.wait()` yourself (the compiler only warns).
- A top-level `local` is **promoted to a global**; a `local` in a top-level
  `do`/`if`/`for` block read from a function is *not* diagnosed (known gap).
- A bare `return` is accepted (in `main()`, other functions, `if` and loops;
  it returns `nil`). The README's quirks section says so.
- **No** `require`/`dofile` (use `--#include`), `pcall`/`error`/`assert`,
  `select`, callable `next`, `string.match`/`gmatch`, `("%d"):format()`,
  arithmetic/comparison/concat metamethods (`__add`, `__eq`, `__lt`,
  `__concat`...), coroutines (`coroutine.create` is not rejected at compile
  time, so a missing feature can fail silently), or garbage collection (bump
  allocator: build tables once, not per frame; `s = s .. c` in a loop is
  quadratic).
- Arithmetic on non-numbers (`nil + 1`, `"abc" + 1`) raises nothing; the
  result is meaningless. Division by zero / `log(0)` give finite answers.
- **Keyboard and mouse need extra hardware** (v32io adapter or the modified
  emulator); the console has only gamepads. Everything compiles and runs
  without them, but no key is ever down, so neither `make tests` nor the
  headless harness can show those paths working.

**API modes** are chosen by `--api`, else `--#api`, else detected (`.p8` =
PICO-8, `.tic` = TIC-80, entry points `TIC()` / `_draw()`/`_update()`). Picking
`pico8` or `tic80` **replaces** the native surface, it does not add to it.
Both layers' known gaps are listed in the README roadmap and `doc/PICO8.md`,
`doc/TIC80.md`; `pal()`/`palt()` in PICO-8 are warned no-ops.

## Hints, assets and the XML (read before touching this)

- `--#title`, `--#texture NAME "path.png"`, `--#sound NAME "path.wav"`,
  `--#tilemap NAME "map.csv"`, `--#include "f.lua"`, `--#api` etc. are plain
  Lua comments the compiler reads. `NAME` becomes a global holding the
  resource number, assigned **in source order** (including across includes),
  and that order *is* the order in the XML. Never reorder them casually.
- Precedence: command-line option > `--#` hint > `inc/config.h` default.
- `--#include` is a textual paste before lexing, once per file, cycle-checked.
  Search order: including file's dir, cwd, `$V32LUA_INCLUDE`, built-in
  install path, then `include/v32lua` beside the executable. `lib/*.lua`
  holds the standard-library ports.
- **XML paths (read this before touching `emit_cart_xml`).** `packrom` resolves
  every path in the XML relative to the XML itself. Default: the XML lands
  **next to the `-o` file** (`-o obj/game.asm` gives `obj/game.xml`) and holds
  **bare file names**: `<binary path="game.vbin" />`, and `--#texture S
  "textures/ship.png"` becomes `ship.vtex`, so the converted `.vbin`/`.vtex`/
  `.vsnd` belong **beside the XML** (demo Makefiles run `png2vircon ... -o
  obj/ship.vtex`). Two assets that collapse to one name keep just enough
  directories to be unique (`ship.vtex`, then `extra/ship.vtex`); only a whole-
  path collision warns. `--xml-preserve-paths` restores the hint paths as
  written, puts the XML in the **project folder** (`path_project_dir`: the source's
  directory, or its parent when the source is in `src/` and the output in a
  sibling such as `obj/`, the same folder the build scripts use) under the
  output's base name (`game.xml`), re-bases hint paths onto it
  (`src/textures/ship.vtex`, `emit.c` keeps the source dir in `g_xml_src_dir`)
  and makes `<binary>` relative to it (`obj/game.vbin`). It mirrors v32c++'s option of the same name (same
  collision rule, same `Opt` twin); keep the two in step.
- **An `Opt` twin is always written** beside every XML (`gameOpt.xml`, same
  content but `<binary path="gameOpt.vbin" />`) for builds through `v32opt`.
  Demo Makefiles must not `mv` or `sed` XML any more; they pack
  `obj/$(DEMO).xml` / `obj/$(DEMO)Opt.xml` directly. Never hand-edit these.
- **v32lua also writes assets itself**: PICO-8/TIC-80 carts get
  `<out>_pico8.vtex`, `<out>_shapes.vtex`, `<out>_sfxNN.vsnd`, a `_bezel.vtex`,
  `pico8_toneN.vsnd`, etc., beside the output (the `-o` directory). They are
  registered with `cart_resource_append_generated` (the `generated` flag on
  `CARTresource`), which is how `--xml-preserve-paths` knows to name them
  relative to the XML rather than to the source. Use it for any new file the
  compiler writes; plain `cart_resource_append` is for `--#` hints. Generated
  names get their extension *appended*, hint names get theirs *swapped*.
  Hint-declared assets are only *named*, never converted; the user runs
  `png2vircon`/`wav2vircon`.
- **The `Opt` twin has its own title**: `--#titleopt` / `--titleopt` (CLI
  wins), else the title + `" [optimized]"`, unless `--#no-diff-opt-title` /
  `--no-diff-opt-title` (an explicit titleopt still beats it). The logic is
  `cart_title_for_variant` in `emit.c`; the state is in `ast.c`.
- **`Make.sh` / `Make.bat` are generated too** (`src/buildscript.c`, called
  right after `emit_cart_xml`; `--no-build-scripts` or `V32LUA_DEFAULT_BUILD_SCRIPTS`
  turns them off). They go beside the source, or one level up when the source
  is in `src/` and the output in a sibling (`obj/`); they reuse
  `cart_xml_resolve_names` so asset names match the XML, repeat the CLI
  options recorded in `main.c` (`RECORD_OPT`: add new output-affecting
  options there), check for `v32lua`, and run the `v32opt` path only when
  `v32opt` exists. A script lacking the `Generated by v32lua` mark is never
  overwritten. **Every harness that runs v32lua must pass `--no-build-scripts`**
  (demo/testing Makefiles, CMake tests, `tools/headless/runlua`), or it litters
  source directories with scripts. `tests/xml/build_scripts.sh` runs the
  generated scripts against stub tools.
- **`-b` builds a BIOS** (`g_bios_mode`): the output starts with the hardware
  error vector (`generator.c`), `V32_CART_PAGE` is `0x10000000` instead of
  `0x20000000` (`emit.c`; runtime code must use the symbol, never the
  literal), the XML `<rom>` is `type="bios"`, and the build scripts repeat
  `-b` for `v32lua` and `assemble`. `main.c` enforces the three constraints
  (native API, one texture, at most one sound, plus `error_handler`).
  `tests/xml/bios.sh bin/v32lua` (`xml/bios`) covers it and needs no DevTools.
- A texture/sound id that disagrees with its XML position is an internal
  warning, not a feature: ids must equal position.

## Working on the project

- Build: `make` (recurses into `src/`, writes `bin/v32lua`). `make clean`
  also cleans `testing/` and `demos/`. CMake is an alternative build over the
  same sources; `ctest` only checks that tests compile (and that
  `testing/fail/` programs are refused).
- Tests: `make tests` compiles, assembles with `assemble`, packs and runs
  every `testing/*/NN_*.lua` on **v32sim**, comparing globals named
  `number_*`/`string_*`/`boolean_*`/`hex_*` to the `=== EXPECTED OUTPUT ===`
  block in the file. It needs the Vircon32 DevTools and v32sim on `PATH`.
  `tests/xml/xml_paths.sh bin/v32lua` (also a `ctest` entry, `xml/paths`)
  checks the cartridge XML in both modes and needs no DevTools. `tests/xml/build_scripts.sh bin/v32lua` (`xml/build_scripts`)
  does the same for the optimized title and the build scripts;
  `tests/xml/bios.sh bin/v32lua` (`xml/bios`) for `-b`.
  `make asmcheck` / `make v32check` only assemble / pack. Passing a bare
  compile proves little.
- Without those: `tools/headless/` runs carts on the official CPU cores
  (`build.sh /path/to/ComputerSoftware` once; then `runlua prog.lua`,
  `unittest.py`). GPU/SPU are logging stand-ins, so rendering and audio are
  not checked. `tests/audit/run_all.sh` diffs plain-Lua programs against a
  reference Lua 5.4 (`$LUA54`); `R_*` globals are compared.
- Fix the compiler, don't bend test or demo source to dodge a bug.
- Add a test: a new `testing/<category>/NN_name.lua` with the expected-output
  block; unit tests are `function main()` wrappers (often `__rawasm__` with
  `__debugN:` labels). Compiler-refusal cases go in `testing/fail/`.
- Layout: `src/node/*.c` AST node codegen, `src/intrinsics/*.c` built-in
  calls and `ioports.*` paths (add new ones here), `src/emit.c` assembly and
  XML printing, `src/pathutil.c` path helpers for the XML, `src/buildscript.c` Make.sh/Make.bat, `src/main.c` options
  and driver, `src/pico8_*.c` /
  `src/tic80_*.c` the compatibility layers. `inc/` holds the headers;
  `src/Makefile` globs `node/` and `intrinsics/` but lists core files by hand.
- **The runtime is assembly**, `src/runtime/*.s`, pulled into the binary by
  `src/runtime_embed.S` (`.incbin`) and appended to output only when used
  (`runtime_req`). Edit the `.s`, rebuild. The `*.s.txt` copies from
  `make context` / `make put` are paste-into-chat snapshots: never edit them.
- Generated `src/lexer.c`, `src/parser.c`, `inc/parser.h` are checked in.
  Editing `lexer.l`/`parser.y` makes `make` call flex/bison (bison 3.x, flex
  2.6.x); if they are not installed the build fails, so regenerate where
  they are and commit the outputs.
- Defaults (sample rates, gamepad ports, include path, bezel, fast circles)
  live in `inc/config.h`.
- Version: the single `#define VERSION` in `inc/v32lua.h`; `make version`
  stamps the three man pages and the `doc/DEBUGGING.md` footer (release
  builds refuse a mismatch: run it after every VERSION change).
  `make sysinstall` needs `PREFIX=`/`DESTDIR=` awareness (it, and cmake,
  install the man page gzipped as `v32lua.1.gz`), and `DEST_LANG=all|en|es|fr`
  picks the installed docs.
- Releases: `.github/workflows/release-builds.yml` ("Generate Global
  Binaries", run by hand) builds every platform; a `release` run then makes
  the GitHub release `v<VERSION>` from `.github/release-notes.md` (`@VERSION@`
  is replaced), a draft unless `publish_release` is ticked. Keep the release
  text's feature list in step with the README. It mirrors v32c++'s workflow
  (the same `release` job); keep the two in step.
- Docs: `README.md`, `doc/API.md` (authoritative intrinsic reference),
  `doc/USAGE.md` (command line, hints, XML, build steps), `doc/PICO8.md`,
  `doc/TIC80.md`, `doc/V32FFI.md`, `doc/NaN_boxing.md`, `doc/FEATURES.md`,
  `doc/DEBUGGING.md`. **Only** README, `doc/API.md` and `doc/USAGE.md` have
  Spanish and French translations (`*.es.md`, `*.fr.md`), as do the man pages
  (`man/v32lua.es.1`, `man/v32lua.fr.1`): when you change an English one,
  update the translations or say they are stale. When a limitation is lifted,
  update the README roadmap / quirks sections and this file.
- Related tools: `v32opt` (assembly optimizer, goes between compile and
  assemble), v32c++ (C++ to Vircon32 C), v32sim, v32io. Sibling projects, not
  part of this tree.
