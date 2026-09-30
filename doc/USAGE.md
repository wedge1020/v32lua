# Using v32lua: from a .lua file to a cartridge

This page walks through building a cartridge: the command line, the
`--#` hints that describe the cartridge, the XML file the compiler writes,
and the Vircon32 tools that finish the job. The language and API are in
the [README](../README.md) and [API.md](API.md).

---

## 1. Compile

```bash
v32lua -o obj/game.asm game.lua
```

This writes two files next to each other:

* `obj/game.asm` — the program, in Vircon32 assembly;
* `obj/game.xml` — the cartridge definition that `packrom` reads.

Without `-o`, the output is `game.asm` (and `game.xml`) beside the source.
Run `v32lua --help` for every option; the common ones:

| Option | Effect |
|---|---|
| `-o FILE` | Output assembly file. |
| `-g` | Also write `FILE.debug`, mapping assembly lines to Lua lines (for v32sim). |
| `-w` | No warnings. |
| `-v` | Show the compiler's stages as it runs. |
| `--api pico8\|tic80\|vircon32` | Choose the API; by default it is detected from the file (`.p8`, `.tic`) or the source. |
| `--title "TEXT"` | Cartridge title. |
| `--rate 11025\|22050\|44100` | Sample rate of the sound made from a PICO-8 or TIC-80 cart. |
| `--bezel FILE`, `--no-bezel` | PICO-8 side panels: your own art, or none. |
| `--fast-circles` | PICO-8/TIC-80: draw big filled circles faster (slightly different edges). |
| `--version`, `--help` | Version, usage. |

## 2. Describe the cartridge with `--#` hints

Lines starting with `--#` are ordinary Lua comments, which the compiler
reads as cartridge settings. Put them at the top of the file.

| Hint | Meaning |
|---|---|
| `--#title "Text"` | Cartridge title. |
| `--#version "1.2"` | Cartridge version. |
| `--#texture NAME "path/image.png"` | Adds a texture. `NAME` becomes a global holding its texture number (0, 1, 2, … in order). |
| `--#sound NAME "path/sound.wav"` | Adds a sound. `NAME` holds its sound number (0, 1, 2, …). |
| `--#tilemap NAME "path/map.csv"` | Embeds a tile map in the program (see [API.md](API.md#tilemap-tilemap)). |
| `--#include "file.lua"` | Inserts another source file here. |
| `--#api "pico8"` / `"tic80"` | Chooses a compatibility API. |
| `--#p8 "cart.p8"` | PICO-8: use the sprites, flags and map of a `.p8` file. |
| `--#rate 22050`, `--#bezel off`, `--#fast-circles` | Same as the command-line options, which take precedence. |

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

For the example above, `obj/game.xml` is:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<rom-definition version="1.0">
    <rom type="cartridge" title="Space Invaders Vircon32" version="1.2" />
<binary path="obj/game.vbin" />
<textures>
    <texture path="assets/textures/background.vtex" /> <!-- bg_space -->
    <texture path="assets/textures/ship.vtex" /> <!-- spr_player -->
</textures>
<sounds>
    <sound path="assets/sounds/laser.vsnd" /> <!-- sfx_laser -->
    <sound path="assets/music/stage1.vsnd" /> <!-- bgm_stage1 -->
</sounds>
</rom-definition>
```

The XML names the converted files: `.vtex` for each texture and `.vsnd`
for each sound, in the same folder and with the same name as the file in
the hint. The order of the entries is the order of the hints, which is
what makes `bg_space` texture 0 and so on. Paths are used as written, so
write them relative to the folder you run `packrom` in.

## 4. Convert the assets, assemble and pack

With the [Vircon32 DevTools](https://github.com/vircon32/ComputerSoftware/releases):

```bash
png2vircon assets/textures/background.png -o assets/textures/background.vtex
png2vircon assets/textures/ship.png       -o assets/textures/ship.vtex
wav2vircon assets/sounds/laser.wav        -o assets/sounds/laser.vsnd
wav2vircon assets/music/stage1.wav        -o assets/music/stage1.vsnd

assemble -o obj/game.vbin obj/game.asm
packrom obj/game.xml -o bin/game.v32
```

`bin/game.v32` runs in the Vircon32 emulator or
[v32sim](https://github.com/g7n-org/v32sim). Sounds must be 44100 Hz
16-bit stereo WAV files for `wav2vircon`.

PICO-8 and TIC-80 carts need no assets of their own: the compiler writes
their textures and sounds itself and names them in the XML.

## 5. Optional: the optimizer

[v32opt](https://github.com/wedge1020/v32opt) rewrites the assembly to
run faster; it goes between compiling and assembling:

```bash
v32opt -O3 -o obj/gameOpt.asm obj/game.asm
assemble -o obj/gameOpt.vbin obj/gameOpt.asm
sed 's/\.vbin/Opt.vbin/g' obj/game.xml > obj/gameOpt.xml
packrom obj/gameOpt.xml -o bin/gameOpt.v32
```

The demo Makefiles (`demos/pico8/*/Makefile`, `demos/tic80/*/Makefile`)
do all of the above, and build the optimized cart as well when `v32opt`
is installed; a failure in the optimized steps doesn't stop the regular
cart from being built. Copy one as a starting point for your own project.
