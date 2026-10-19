# Using v32lua: from a .lua file to a cartridge

This page walks through building a cartridge: the command line, the
`--#` hints that describe the cartridge, the XML file the compiler writes,
and the Vircon32 tools that finish the job. The language and API are in
the [README](../README.md) and [API.md](API.md).

*Also in: [Español](USAGE.es.md) | [Français](USAGE.fr.md)*

---

## 1. Compile

```bash
v32lua -o obj/game.asm game.lua
```

This writes three files next to each other (plus the build scripts, [section 6](#6-build-scripts-makesh-and-makebat)):

* `obj/game.asm` — the program, in Vircon32 assembly;
* `obj/game.xml` — the cartridge definition that `packrom` reads;
* `obj/gameOpt.xml` — the same cartridge for a build through the
  [optimizer](#5-optional-the-optimizer) (it points at `gameOpt.vbin`).

Without `-o`, the output is `game.asm` (and `game.xml`, `gameOpt.xml`)
beside the source.
Run `v32lua --help` for every option; the common ones:

| Option | Effect |
|---|---|
| `-o FILE` | Output assembly file. |
| `-b` | Build a Vircon32 **BIOS** instead of a cartridge: needs `function error_handler()` (run by the console on a CPU hardware error), exactly one `--#texture` and at most one `--#sound`; the XML gets `<rom type="bios">` and the build scripts get `v32lua -b` / `assemble -b`. Native vircon32 API only. |
| `-g` | Also write `FILE.debug`, mapping assembly lines to Lua lines (for v32sim). |
| `-w` | No warnings. |
| `-v` | Show the compiler's stages as it runs. |
| `--api pico8\|tic80\|vircon32` | Choose the API; by default it is detected from the file (`.p8`, `.tic`) or the source. |
| `--title "TEXT"` | Cartridge title. |
| `--titleopt "TEXT"` | Title of the optimized cartridge (`gameOpt.xml`); default: the title followed by ` [optimized]`. |
| `--no-diff-opt-title` | Give the optimized cartridge the same title as the regular one. |
| `--no-build-scripts` | Don't write `Make.sh` / `Make.bat` ([section 6](#6-build-scripts-makesh-and-makebat)). |
| `--rate 11025\|22050\|44100` | Sample rate of the sound made from a PICO-8 or TIC-80 cart. |
| `--bezel FILE`, `--no-bezel` | PICO-8 side panels: your own art, or none. |
| `--fast-circles` | PICO-8/TIC-80: draw big filled circles faster (slightly different edges). |
| `--allow-float-as-clearcolor` | A Lua number given to `ioports.gpu.clear` or TIC-80 `cls()` keeps its float32 bits as the clear color, as in older versions (translucent clear = motion-blur streak). Off by default. |
| `--xml-preserve-paths` | Keep the `--#texture`/`--#sound` paths in the XML as written and write the XML in the project folder, beside the source or in its parent when the source is in `src/` and the output in a sibling like `obj/` ([section 3](#3-the-cartridge-xml)). |
| `--keyboard 0-3` | Gamepad port of a v32kbd keyboard (`key()`, `keyp()`, `kbd.*`); default 2. Needs a v32io device (below). |
| `--mouse 0-3` | Gamepad port of a v32mouse mouse (`mouse()`, `mouse.*`, PICO-8 `stat(32..34)`); default 3. Needs a v32io device (below). |
| `--version`, `--help` | Version, usage. |

> **Keyboard and mouse need a v32io device.** Vircon32 has only gamepads.
> A program using the keyboard or mouse functions only gets input when run
> with the **v32io hardware adapter** (a USB keyboard or mouse that the
> computer sees as a gamepad; any Vircon32 emulator) or a **modified
> emulator** that reads the computer's own keyboard and mouse (the
> [`v32io` branch](https://github.com/wedge1020/ComputerSoftware/tree/v32io)
> of wedge1020/ComputerSoftware, or the stock emulator with the v32io
> patches). Otherwise it runs with no keyboard or mouse input at all. See
> [API.md](API.md#keyboard-and-mouse-what-you-need-v32io).

## 2. Describe the cartridge with `--#` hints

Lines starting with `--#` are ordinary Lua comments, which the compiler
reads as cartridge settings. Put them at the top of the file.

| Hint | Meaning |
|---|---|
| `--#title "Text"` | Cartridge title. |
| `--#titleopt "Text"` | Title of the optimized cartridge. Without it: the title followed by ` [optimized]`. |
| `--#no-diff-opt-title` | Optimized cartridge keeps the same title as the regular one (an explicit `--#titleopt` still wins). |
| `--#version "1.2"` | Cartridge version. |
| `--#texture NAME "path/image.png"` | Adds a texture. `NAME` becomes a global holding its texture number (0, 1, 2, … in order). |
| `--#sound NAME "path/sound.wav"` | Adds a sound. `NAME` holds its sound number (0, 1, 2, …). |
| `--#tilemap NAME "path/map.csv"` | Embeds a tile map in the program (see [API.md](API.md#tilemap-tilemap)). |
| `--#include "file.lua"` | Inserts another source file here. |
| `--#api "pico8"` / `"tic80"` | Chooses a compatibility API. |
| `--#p8 "cart.p8"` | PICO-8: use the sprites, flags and map of a `.p8` file. |
| `--#rate 22050`, `--#bezel off`, `--#fast-circles`, `--#keyboard 2`, `--#mouse 3` | Same as the command-line options, which take precedence. |
| `--#allow-float-as-clearcolor` | Same as the command-line option. |

```lua
--#title "Space Invaders Vircon32"
--#version "1.2"

--#texture bg_space   "assets/textures/background.png"   -- texture 0
--#texture spr_player "assets/textures/ship.png"         -- texture 1

--#sound sfx_laser  "assets/sounds/laser.wav"             -- sound 0
--#sound bgm_stage1 "assets/music/stage1.wav"             -- sound 1

function main()
    ioports.gpu.texture = bg_space
    ioports.gpu.clear()
    music.play(bgm_stage1, 0, true)          -- channel 0, looping
    while true do
        if btnp(5) then sfx.play(sfx_laser) end   -- button A
        system.wait()
    end
end
```

The resource names are set before `init()` or `main()` runs.

## 3. The cartridge XML

`packrom` reads every path in the XML **relative to the XML file itself**.
So `v32lua` writes the XML beside the `-o` file, and puts only file names
in it. For the example above, `obj/game.xml` is:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<rom-definition version="1.0">
    <rom type="cartridge" title="Space Invaders Vircon32" version="1.2" />
<binary path="game.vbin" />
<textures>
    <texture path="background.vtex" /> <!-- bg_space -->
    <texture path="ship.vtex" /> <!-- spr_player -->
</textures>
<sounds>
    <sound path="laser.vsnd" /> <!-- sfx_laser -->
    <sound path="stage1.vsnd" /> <!-- bgm_stage1 -->
</sounds>
</rom-definition>
```

The XML names the converted files: `.vtex` for each texture and `.vsnd`
for each sound, with the name of the file in the hint and its folder
dropped. The order of the entries is the order of the hints, which is
what makes `bg_space` texture 0 and so on. The `.vbin`, `.vtex` and
`.vsnd` files are expected **beside the XML**, in `obj/` here (the next
section converts them there). Because everything is relative to the XML,
the project can be built from any folder, and nothing needs to be moved
or edited by hand.

**Same names in different folders.** If two assets collapse to the same
name, the first keeps it and each later one keeps just enough of its
folders to be unique: `textures/ship.png` followed by
`textures/extra/ship.png` gives `ship.vtex` and `extra/ship.vtex`, the
second expected in `obj/extra/`. Only two assets whose whole paths
collapse to one name (differing just by extension, say) still draw a
warning.

**The optimizer's twin.** Beside `obj/game.xml` the compiler also writes
`obj/gameOpt.xml`, identical except for `<binary path="gameOpt.vbin" />`
and the title, for the optimized build in
[section 5](#5-optional-the-optimizer). It is written whether or not you
use the optimizer.

**The optimized cart's title.** So the two cartridges can be told apart
on a memory card or in a menu, the twin's title is the regular title with
` [optimized]` added (`Space Invaders Vircon32 [optimized]`). Choose your
own with `--#titleopt "Text"` (or `--titleopt "Text"`, which wins over the
hint), or keep the two titles identical with `--no-diff-opt-title` (or the
hint `--#no-diff-opt-title`). An explicit `titleopt` always beats
`no-diff-opt-title`.

**`--xml-preserve-paths`** restores the paths as written in the hints
(`assets/textures/ship.vtex`) and writes the XML into the *project folder*
instead of beside the output: the directory of the *source* file (the hints'
own point of reference) — or its parent, when the source is in a folder named
`src` and the output in a sibling such as `obj/`. So `-o obj/game.asm
src/game.lua` gives `game.xml` and `gameOpt.xml` beside `src/` and `obj/`,
the same place the [build scripts](#6-build-scripts-makesh-and-makebat) go.
`<binary>` becomes the `.vbin` path relative to the XML (`obj/game.vbin`),
and, since the XML moved up a level, the hint paths are re-based onto it
(`src/assets/textures/ship.vtex`). Assets the compiler generates itself
(PICO-8 and TIC-80 carts, below) sit beside the output file, so they are
named relative to the XML too (`obj/game_pico8.vtex`). When the source is not
in `src/` (or the output is not in a sibling of it), the XML goes in the
source's own directory, and the paths stay exactly as written
(`../obj/game.vbin`). Use it when your assets already live next to the
source and you want the XML there.

With `-b` (a BIOS build) the `<rom>` element says `type="bios"` instead of
`type="cartridge"`; the rest of the XML is the same. A BIOS needs exactly one
`--#texture` and at most one `--#sound`.

## 4. Convert the assets, assemble and pack

With the [Vircon32 DevTools](https://github.com/vircon32/ComputerSoftware/releases):

```bash
png2vircon assets/textures/background.png -o obj/background.vtex
png2vircon assets/textures/ship.png       -o obj/ship.vtex
wav2vircon assets/sounds/laser.wav        -o obj/laser.vsnd
wav2vircon assets/music/stage1.wav        -o obj/stage1.vsnd

assemble -o obj/game.vbin obj/game.asm
packrom obj/game.xml -o bin/game.v32
```

`bin/game.v32` runs in the Vircon32 emulator or
[v32sim](https://github.com/g7n-org/v32sim). Sounds must be 44100 Hz
16-bit stereo WAV files for `wav2vircon`.

PICO-8 and TIC-80 carts need no assets of their own: the compiler writes
their textures and sounds itself, beside the output (`obj/game_pico8.vtex`,
`obj/game_sfx00.vsnd`, ...), and names them in the XML.

## 5. Optional: the optimizer

[v32opt](https://github.com/wedge1020/v32opt) rewrites the assembly to
run faster; it goes between compiling and assembling:

```bash
v32opt -O3 -o obj/gameOpt.asm obj/game.asm
assemble -o obj/gameOpt.vbin obj/gameOpt.asm
packrom obj/gameOpt.xml -o bin/gameOpt.v32
```

`obj/gameOpt.xml` is the twin the compiler already wrote (section 3), so
nothing has to be edited by hand. The demo Makefiles (`demos/*/Makefile`,
`demos/pico8/*/Makefile`, `demos/tic80/*/Makefile`) do all of the above, and build the optimized cart as well when `v32opt`
is installed; a failure in the optimized steps doesn't stop the regular
cart from being built. Copy one as a starting point for your own project.

## 6. Build scripts: `Make.sh` and `Make.bat`

Along with the XML, `v32lua` writes the traditional Vircon32 build scripts,
`Make.sh` (Linux/macOS) and `Make.bat` (Windows), so a project builds with
one command even if you don't use a Makefile:

```bash
./Make.sh        # or: Make.bat
```

They repeat every step of sections 1 to 5 for this project, from the same
information the XML is made from: they create `obj/` and `bin/` (and any
folder an asset needs), run `v32lua` again with the options you gave,
convert each `--#texture` / `--#sound` with `png2vircon` / `wav2vircon`
into the place the XML expects it, `assemble`, and `packrom` into
`bin/game.v32`. Every command is followed by `|| abort_build`
(`|| goto :failed` in the batch file), ending with `BUILD FAILED` or
`BUILD SUCCESSFUL`.

* **They check for the tools.** If `v32lua` is not in the `PATH`, the script
  says it is needed to build the project and stops. The optimized build
  (`v32opt`, `assemble`, `packrom` of `gameOpt.xml` into `bin/gameOpt.v32`)
  runs only if `v32opt` is found; otherwise it is skipped and the script
  still succeeds. A failure inside the optimized steps is only a warning.
* **Where they go.** Beside the source file, or in its parent when the
  source is in a folder named `src` and the output is in a sibling folder
  (`src/game.lua`, `-o obj/game.asm` puts them in the project folder, not
  `src/`). All paths in them are relative to the script's folder, and the
  script changes into that folder first, so it can be run from anywhere.
* **Your own scripts are safe.** The first lines say `Generated by v32lua`.
  A `Make.sh` or `Make.bat` without that mark is never overwritten (a
  warning says so). The generated ones are rewritten on every compile, so
  copy one and remove the mark to keep your edits. The `v32lua` command
  inside them passes `--no-build-scripts`, so building from the script
  doesn't rewrite it.
* **Options carry over.** `--api`, `--title`, `--titleopt`,
  `--no-diff-opt-title`, `--rate`, `--bezel`, `--no-bezel`, `--fast-circles`,
  `--allow-float-as-clearcolor`, `--keyboard`, `--mouse`,
  `--xml-preserve-paths` and `-w` are repeated in the script's `v32lua`
  line; `-g` also gives `assemble -g program`, and `-b`
  (a BIOS build) is repeated too and gives `assemble -b` (with both:
  `assemble -b -g program`).
* **Tiled maps** (`tiled2vircon`) aren't covered; use `--#tilemap`, or add
  those lines to your own copy.

`--no-build-scripts` turns all of this off (the default can also be changed
in `inc/config.h`, `V32LUA_DEFAULT_BUILD_SCRIPTS`). The demo Makefiles and
the test suites pass it, because they build their own way.
