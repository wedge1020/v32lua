# v32lua: Vircon32 Lua Compiler

[Spanish version / en español](README.es.md) | [French version / en francais](README.fr.md)

**Target Architecture:** Vircon32 Fantasy Console (32-bit)

**Implementation Language:** C (Flex/Bison + Custom Semantic Emitter)

**Repository:** [github.com/wedge1020/v32lua](https://github.com/wedge1020/v32lua)

**API Reference:** [doc/API.md](doc/API.md) —  the full native Vircon32
API (sound, graphics, input, tilemaps, memory card, and raw I/O ports).

`v32lua` is  a Lua compiler  written in  C that targets  the **Vircon32**
fantasy console. Instead of embedding a heavyweight bytecode interpreter,
`v32lua`  parses Lua  source code  and compiles  it directly  into native
Vircon32 assembly,  and also  produces the  XML cartridge  definition the
console's toolchain needs to package a ROM.

While it is not yet complete, one  aim of development is to make `v32lua`
a substitute (by  no means a replacement) for the  Vircon32 C Compiler in
the Vircon32 development  stack. Basically, pick your  choice of language
— C  or Lua —  and once it's compiled  down to assembly,  you proceed
with  the  build regardless  of  implementation  language. As  a  result,
efforts have  been made  to mimic  various behaviours  of the  Vircon32 C
Compiler to make compiler substitution more transparent.

Designed from  the ground  up with  retro fantasy-console  constraints in
mind, `v32lua` features zero-cost low-level "hardware" intrinsics, custom
[NaN-boxing](doc/NaN_boxing.md), and  — beyond the native  Vircon32 API
— two API compatibility layers so that carts written for **TIC-80** and
**PICO-8** can compile and run in the Vircon32 environment with little to
no source modification.

```
+------------------+     +-------------------+     +------------------+
| Source (.lua)    | --> | Lexer & Parser    | --> | AST Construction |
+------------------+     | (Flex / Bison)    |     +------------------+
                         +-------------------+              |
                                                            v
+------------------+     +-------------------+     +------------------+
| Cartridge Config | <-- | Vircon32 Assembly | <-- | Semantic Emitter |
| (.xml)           |     | Emitter (.asm)    |     |                  |
+------------------+     +-------------------+     +------------------+
```

---

## Table of Contents

- [Getting Started](#getting-started)
- [API Compatibility Layers](#api-compatibility-layers)
- [Cartridge Resource Hints (`--#...`)](#cartridge-resource-hints)
- [Compilation Pipeline](#compilation-pipeline)
- [Key Language & Compiler Features](#key-language--compiler-features)
- [Supported Lua Language Features](#supported-lua-language-features)
- [Hardware I/O & Compiler Intrinsics](#hardware-io--compiler-intrinsics)
- [Inline Assembly (`__asm__` & `__rawasm__`)](#inline-assembly-__asm__--__rawasm__)
- [Memory Map Reference](#memory-map-reference)
- [Compiler Quirks, Assumptions & Known Limitations](#compiler-quirks-and-assumptions)
- [Compiler Optimization](#compiler-optimization)
- [Roadmap / Not Yet Implemented](#roadmap--not-yet-implemented)
- [AI Utilization](#ai-utilization)

---

## Getting Started

**Requirements**

* A C toolchain (`gcc`/`clang` + `make`)
* If changes are made to the lexer/parser, the `flex` and `bison` tools are
  needed to regenerate the lexer/parser C routines. The existing `flex` and
  `bison` C routines are included in the repository to simplify the building
  process, reducing some dependency on actually needing `flex`/`bison` in
  most scenarios
* The [Vircon32 DevTools](https://github.com/vircon32/ComputerSoftware/releases) toolchain (assembler and `packrom`) if you intend to go all
  the way from `.lua` to a runnable `.v32` cartridge, plus
  [v32sim](https://github.com/g7n-org/v32sim) if you want to run or debug
  the results (also used for unit tests).

**Building the Compiler**

The repository includes  a root-level Makefile that  manages building the
compiler binary, running  the test suite, and general  project upkeep. To
build the main  compiler binary from source, run the  default target from
the repository root:

```bash
make
```

This  will   compile  the  individual   source  files  and   produce  the
`v32lua`  binary  (under  `bin/`),  which  turns  a  `.lua`  source  file
into  a  Vircon32 `.asm`  file  plus  an accompanying  cartridge  `.xml`.
From  there,   assembling  and   packing  follows   the  same   steps  as
any  other  Vircon32  project  (assemble  →  `packrom`  →  run  under
[v32sim](https://github.com/g7n-org/v32sim) or on the official emulator).

*Reference Table of Makefile Targets*

| Target | Description | Core Actions & Dependencies |
| --- | --- | --- |
| **`all`** | **Default target.** Builds the main compiler executable. | Invokes the compilation process natively inside the `src/` subdirectory. |
| **`clean`** | Standard workspace cleanup utility. | Recursively wipes intermediate build artifacts out of `src/` and removes generated files from `testing/` and `demos/`. |
| **`install`** | Installs the compiler binary onto the host system. | Passes the target down to the `src/` directory's localized installation scripts. |
| **`tests`** | Executes the automated compilation testing suite. | Depends on the compiler binary (`bin/v32lua`) being built first, then triggers the test routines inside `testing/`. |
| **`demos`** | Builds the collection of available demos. | Depends on the compiler binary (`bin/v32lua`) being built first, then builds each demo under `demos/`. |
| **`asmcheck`** | Validates assembly correctness. | Requires `bin/v32lua` to be present, then processes assembly validations via the `testing/` suite. |
| **`monofiles`** | Builds streamlined monolithic file variants (used for pasting the whole project into a single-file conversation). | Runs the `monofile` creation workflow sequentially inside both `src/` and `testing/`. |

**Your First Cartridge**

```lua
--#title "v32lua Tech Demo"
--#version "1.0"
--#texture tex_logo "logo.png"

x_pos = 160.0
y_pos = 120.0
speed = 2.5

function init()
    -- Set background clear color using zero-cost GPU port mappings
    ioports.gpu.bgcolor = 0xFF003366
    ioports.gpu.texture = tex_logo -- set texture
    ioports.gpu.region  = 0 -- set region

    -- define the region
    ioports.gpu.minX    = 0
    ioports.gpu.minY    = 0
    ioports.gpu.maxX    = 100
    ioports.gpu.maxY    = 50
    ioports.gpu.hotX    = 0
    ioports.gpu.hotY    = 0
end

function game_loop()

    -- Update state using pure floating-point math
    if ioports.inp.left > 1 then
        x_pos = x_pos - speed
    else if ioports.inp.right > 1 then
        x_pos = x_pos + speed
    end

    -- Direct hardware drawing
    ioports.gpu.x = x_pos
    ioports.gpu.y = y_pos
    ioports.gpu.draw()

    -- Table access and built-in string concatenation
    local frame = system.frames
    if frame > 1000 then
        local msg = "Demo Running: Frame " .. frame
        print(msg)
    end
end
```

Compile it with:

```bash
$ v32lua -o program.asm program.lua
```

`v32lua` emits  `program.asm` and `program.xml` alongside  it; hand those
to the Vircon32 assembler and `packrom` to produce a runnable cartridge.

**Command-Line Usage**

```bash
$ v32lua [options] file
```

Available options:

* `-o <file>`: Specifies the assembly output filename. Defaults to the
  input filename with its extension replaced by `.asm`.
* `-g`: Generates a companion `.debug` file mapping assembly line offsets
  back to original Lua source lines and function entry points.
* `-v`, `--verbose`: Reports progress through the compiler's internal
  pipeline stages as it runs.
* `-d`, `--debug`: Displays additional internal/operational debug
  information.
* `-w`: Suppresses all compiler warnings.
* `--version`: Displays compiler version and author information.
* `--help`, `-h`: Displays command-line usage instructions.

Cartridge options — each overrides the matching `--#` hint in the source,
so a PICO-8 or TIC-80 cart compiles without editing it (`--opt=value` also
works):

* `--api pico8|tic80|vircon32`: Selects the API layer. Without it the API
  is detected: a `.p8` is PICO-8, a `.tic` is TIC-80, and a `.lua` uses its
  own `--#api`/`--#p8` hint — or, with none, its entry points (`TIC()` →
  tic80; `_draw()`/`_update()`/`_update60()` → pico8; otherwise native).
* `--title "text"`: Cartridge title, used as is. Without it: the `--#title`
  hint, else the cart's own title (TIC-80's `-- title:` metadata, PICO-8's
  first comment line) or the file name — prefixed with `[PICO8] ` or
  `[TIC80] ` in those API modes.
* `--p8rate 11025|22050|44100`: Sample rate of PICO-8 sounds synthesized
  from the cart (default 22050; see [doc/PICO8.md](doc/PICO8.md)).

```bash
$ v32lua celeste.p8 --title "celeste" --p8rate 11025   # API detected from .p8
$ v32lua game.tic                                        # TIC-80 binary cart
```

Input files: `.lua`, `.p8` (PICO-8 cartridge), `.tic` (TIC-80 cartridge,
Lua carts only; the code and bank 0's tiles, sprites, map, flags, palette,
waveforms and SFX are read — the same data a TIC-80 `.lua` export carries).

---

## API Compatibility Layers

`v32lua` supports three distinct API surfaces, selected with the `--#api`
cartridge hint (native  Vircon32 is the default when no  `--#api` hint is
present):

```lua
--#api "tic80"   -- opt into the TIC80-compatible API surface
--#api "pico8"   -- opt into the PICO8-compatible API surface
```

* **Native Vircon32 API** (default) — direct, zero-cost access to the
  console's own IOPorts: `ioports.gpu.*`, `ioports.spu.*`, `ioports.inp.*`,
  `music.*`/`sfx.*`, `system.*`, and the native `tilemap.*` API. Fully
  documented in [doc/API.md](doc/API.md).
* **TIC-80 compatibility layer** (`--#api "tic80"`) — TIC-80-shaped calls
  (`spr()`, `btn()`/`btnp()`, `map()`/`mset()`/`mget()`, sound/music
  functions, and the fantasy-console-style asset sections) compiled down to
  native Vircon32 instructions, including the coordinate scaling needed to
  map TIC-80's 240×136 logical screen onto Vircon32's physical resolution.
  `sfx()`/`music()` play from the same generated placeholder tone bank as
  the PICO-8 layer; `print()` honours its color and returns the text width.
  `map()` takes all of TIC-80's optional arguments including `scale`
  (not the remap callback); `fget()` returns a boolean and `fset()` takes
  one. `peek`/`peek1`/`peek2`/`peek4`, `poke`/`poke1`/`poke2`/`poke4`,
  `memcpy` and `memset` work on an emulated 96 KB TIC-80 RAM, created on
  first use with the cart's palette, tiles, sprites and map in it; the map
  (0x08000), gamepad (0x0FF80) and sprite-flag (0x14404) areas are live
  views of `mget`/`mset`, the buttons and `fget`/`fset`. Other writes are
  stored but don't change the screen or sound. A function the program
  defines itself (`function pal(...)`) replaces the built-in of that name,
  as in Lua.
* **PICO-8 compatibility layer** (`--#api "pico8"`) — the PICO-8-shaped
  equivalent: `spr`/`map`/`mget`/`mset`/`fget`/`fset`, `cls`, `rectfill`/
  `rect`/`circfill`/`circ`/`line`/`pset`/`print` (with color),
  `camera`/`color`, `btn`/`btnp` (PICO-8 autorepeat), `add`/`del`/
  `count`/`foreach`/`for v in all(t)` (deletion-safe), PICO-8 math
  (`flr`, `rnd`, `mid`, turn-based `sin`/`cos`, ...), `sspr`, `split`,
  `tostr`/`tonum`, `_ENV[name]`, the PICO-8 syntax shortcuts (`?`, `\`,
  `f"str"`, button glyphs, ...), `sfx`/`music` playing the cart's own
  `__sfx__`/`__music__` (synthesized at compile time), and
  `_init`/`_update` (30 fps)/
  `_update60`/`_draw`. The 128×128 screen is scaled 2.75× and centered;
  drawing outside it is masked. A **`.p8` cart compiles directly**
  (`v32lua game.p8`): its `__lua__` section is the program and its
  `__gfx__`/`__gff__`/`__map__` sections become the sprite sheet, sprite
  flags and map. A plain `.lua` can take those assets from a cart with
  `--#p8 "game.p8"`. See [doc/PICO8.md](doc/PICO8.md).

Only  one API  surface  is  active per  cartridge;  selecting `tic80`  or
`pico8` replaces the native call surface rather than adding to it.

---

## Cartridge Resource Hints

`v32lua` allows you to embed Vircon32 cartridge metadata directly in your
Lua source  code using special  `--#` line comments. The  compiler parses
these  hints to  auto-generate the  project's `.xml`  ROM definition  and
assign sequential hardware resource IDs.

Supported hints:

| Hint | Purpose |
| --- | --- |
| `--#version "X.Y"` | Sets the cartridge version field in the XML. |
| `--#title "TITLE"` | Sets the cart title. |
| `--#api "tic80"` / `--#api "pico8"` | Selects a compatibility API layer (see above). |
| `--#p8 "cart.p8"` | PICO-8: take the sprite sheet, sprite flags and map from a `.p8` cart (implies `--#api pico8`). |
| `--#p8rate 11025` \| `22050` \| `44100` | PICO-8: sample rate of the sounds synthesized from the cart's `__sfx__` (default 22050; see [doc/PICO8.md](doc/PICO8.md#sound)). |
| `--#texture NAME "path/image.png"` | Registers a texture resource and binds it to a compile-time constant `NAME`. |
| `--#sound NAME "path/sound.vsnd"` | Registers a sound resource and binds it to a compile-time constant `NAME`. |
| `--#tilemap NAME "path/map.csv"` | Registers a tilemap from a CSV file, embedded directly into the ROM image (see [doc/API.md](doc/API.md#tilemap-tilemap)). |
| `--#include "file.lua"` | Textually splices another Lua file in at this point, before parsing begins (see below). |

```lua
--#version "1.1"
--#title "Space Grinder: Tech Demo"

-- Register textures (automatically binds 'bg_space' to ID 0, 'spr_ship' to ID 1)
--#texture bg_space "assets/background.png"
--#texture spr_ship "assets/player.png"

function init()
    -- Variables declared in hints are globally available in Lua at runtime!
    ioports.gpu.texture = bg_space
end
```

When compiled, `v32lua`  outputs both the compiled `.asm`  assembly and a
complete  Vircon32  XML cartridge  definition  file  linking `.vtex`  and
`.vsnd` assets. With  this, and the proper processing of  any PNG and WAV
data, you can proceed to the `packrom` step. Resource IDs are assigned in
source order and are guaranteed to  match their position in the generated
XML.

**Multi-File Projects (`--#include`)**

Because Vircon32 carts  are a fixed ROM assembled entirely  at build time
— there  is no runtime  filesystem —  `v32lua` does not  support real
Lua's dynamic  `require`/`dofile`. Instead, `--#include "file.lua"`  is a
compile-time textual paste,  resolved by a preprocessing  pass before the
lexer ever sees the file, exactly like C's `#include`:

```lua
--#include "src/physics.lua"
--#include "src/entities.lua"
```

* Included files are spliced in at the chunk's genuine top level — no
  wrapping in `do...end` or a function body — so a top-level `local` in an
  included file behaves identically to one declared in the entry file.
* Include targets are resolved by searching, in order: the directory of the
  including file; the compiler's current working directory; each entry of
  the `V32LUA_INCLUDE` environment variable when set (a colon-separated
  list); and finally the built-in default include path
  `/usr/local/Vircon32/v32lua/include` (override at build time with
  `-DV32LUA_INCLUDE_PATH=...`, see `inc/config.h`). This is where an
  installed copy of the standard-library ports in `lib/` is expected to
  live, so any project can `--#include "string.lua"` without copying the
  library around. Absolute paths are used verbatim.
* Cyclic includes are detected, and each resolved file is included at most
  once across the whole expansion.
* Cart resource hints (`--#texture`, `--#sound`, `--#tilemap`) declared
  inside an included file get correct resource IDs and XML ordering.
* Error messages inside an included file report the correct source file
  and line number, via an internal line-remapping table.
* Two included files that each declare a top-level `local` of the same
  name share one global — identical to what the equivalent monolithic code
  would do.

---

## Compilation Pipeline

**Compilation Flow**

1. **Lexical & Syntax Analysis**: Flex/Bison parses the Lua source into a
   typed Abstract Syntax Tree (AST).
2. **Symbol & Scope Resolution**: Resolves variables across lexical
   scopes, mapping globals to sequential RAM addresses and locals to
   `[BP - offset]` stack frame positions.
3. **Code Generation**: Emits Vircon32 assembly instructions, applying
   hardware intrinsic substitutions as it walks the AST.
4. **Cartridge Assembly**: Emits the final `.asm` file, embeds runtime
   support routines, generates the read-only string data section, and
   outputs the `.xml` cartridge definition.

**Compilation Stages (`-v`)**

When `-v` is enabled, `v32lua` reports its progress through its pipeline
stages:

1. **Stage 1: Lexer** — Tokenizes the Lua source, stripping standard
   comments and processing string escape sequences (`\n`, `\t`, `\r`, `\\`,
   `\"`).
2. **Stage 2: Preprocessor** — Expands `--#include` directives and
   evaluates cartridge hints (`--#...`) and custom comment syntaxes.
3. **Stage 3: Parser** — Constructs a complete Abstract Syntax Tree (AST)
   using a LALR(1) Bison grammar with strict operator precedence
   (PEMDAS + logic core).
4. **Stage 4: Semantic Analyzer** — Executes a pre-pass to register
   global function and variable symbols and initialize the global scope.
5. **Stage 5: Emitter** — Traverses the AST to generate Vircon32
   assembly, applying register allocation and scope offsets, and finally
   outputs the cartridge XML configuration file.

---

## Key Language & Compiler Features

**Flexible Execution Models: `main()` vs. `game_loop()`**

To accommodate different game  architecture styles, the compiler supports
two distinct function entry points:

* **The Auto-Waiting  Function (`game_loop`)**: If your  program declares
  a  `game_loop()`  function,  the  compiler  automatically  generates  a
  continuous  runtime  harness.  The   CPU  calls  `game_loop()`,  stalls
  execution for the current frame using the CPU's `WAIT` instruction, and
  loops infinitely.  This is ideal  for standard arcade games  and demos,
  and mimics the behaviour of various other fantasy consoles.

* **Manual  Control  (`main`)**:  If  your program  declares  a  `main()`
  function, the CPU  will halt upon completion of  the `main()` function,
  mimicking behaviour similar to C's  `main()` function. If you desire to
  maintain execution, you must establish some  sort of game loop, and you
  must  perform  the  needed  `WAIT` instructions  to  ensure  continuous
  processing and smooth display of  on-screen assets. The compiler tracks
  whether  a `WAIT`  instruction is  emitted  inside `main()`;  if it  is
  missing, `v32lua` issues a semantic warning at compile time.

Additionally, as a precursor to either of the above:

* **Initialization Hook**:  In both  models, if  an `init()`  function is
  present,  it is  guaranteed  to execute  exactly  once after  top-level
  global RAM allocations and before the main loop begins.

A program must declare at least one of `main()` or `game_loop()` — this
is the designated entry point and its absence is a compile error.

**NaN-Boxing: RAM vs. ROM Elements**

`v32lua` uses a 32-bit tagging  architecture that packs type metadata and
payload pointers into unified  values, keeping immutable **ROM elements**
(string  literals, function  pointers) distinct  from dynamic  **RAM heap
objects** (tables):

| Data Type | Hex Mask / Tag | Architecture Description |
| --- | --- | --- |
| **Nil** | `0xFFC00000` | Canonical representation for undefined/missing values. |
| **Boolean False** | `0xFFC00001` | Short-circuit falsy value. |
| **Boolean True** | `0xFFC00002` | Short-circuit truthy value. |
| **ROM String** | `0x7FC00000` | Pointers to read-only string data sections (`__string_%d`) in ROM. |
| **Table / Boxed Object** | `0xFF800000` | Boxed heap memory addresses (Bit 31=1, Bit 22=0). |
| **Number** | IEEE 754 Float | Unboxed native Vircon32 floating-point values for direct math. |

**Hardware Intrinsics & I/O Mapping**

High-performance  Vircon32 games  cannot  afford  hash-table lookups  for
hardware   manipulation.  `v32lua`   intercepts  specific   table  member
expressions and  function calls  and compiles  them directly  into native
hardware I/O instructions:

* **Zero-Cost    Hardware    Access**:    Accessing    namespaces    like
  `ioports.gpu.*`,  `ioports.spu.*`,   `ioports.tim.*`,  `ioports.rng.*`,
  `ioports.car.*`, `ioports.mem.*`,  or `system.*` bypasses  table lookup
  routines entirely.  They compile  directly to hardware  port operations
  (such as `GPU_DrawingPointX` or `TIM_FrameCounter`).

* **`music.*`  / `sfx.*`**:  The  native sound  API  compiles calls  like
  `music.play(SOUND,  channel,  loop)`  down  to  a  straight-line  `OUT`
  sequence  when  every  argument  is  compile-time-known,  falling  back
  to  a  small runtime  routine  only  when  arguments are  dynamic.  See
  [doc/API.md](doc/API.md)  for  the  full  surface,  including  why  the
  SPU  port  write  order  (stop  → assign  →  volume  →  play  →
  loop/position) is important.

* **`tilemap.*`**:    A    native     tilemap    API    (`tilemap.get()`,
  `tilemap.set()`,  `tilemap.render()`)  backed  by a  `--#tilemap`  cart
  hint. Tilemap data  ships read-only in ROM and is  lazily promoted to a
  private RAM copy the first time a given map is written to.

* **Consolidated Gamepad Polling**: Polling controller input is optimized
  into a  single variable intrinsic (`ioports.inp.inputs`).  The compiler
  polls all gamepad axes/buttons, collates  the active button states into
  a  bitshifted 32-bit  integer mask,  and  casts it  to a  Lua float  in
  a  single  register.  Standalone  gamepad  inputs  are  also  available
  (`ioports.inp.left`, `ioports.inp.A`, etc.) as variable intrinsics.

* **Built-in   Fast  Paths**:   Standard  Lua   operations  like   string
  concatenation (`..`), length (`#`), and  unary minus (`-`) map directly
  to optimized runtime  subroutines (`__builtin_strcat`, `__builtin_len`,
  `__builtin_unm`).

See  [doc/API.md](doc/API.md) for  the complete,  authoritative reference
— this README highlights the ideas, the API doc covers every call.

**Developer Experience & Debug Tooling**

* **Visual  ASCII  Error  Reporting**:  Lexical,  syntax,  semantic,  and
  internal  compiler  errors  print highlighted,  multi-line  ASCII  code
  snippets pointing directly to the offending line in the source file.

* **Source-to-Assembly  Mapping (`-g`)**:  Passing  the  `-g` debug  flag
  generates  a companion  `.debug`  file alongside  the output  assembly.
  This  file maps  relative Vircon32  assembly line  offsets to  original
  Lua  source lines  and functional  entry points,  enabling step-through
  debugging under [v32sim](https://github.com/g7n-org/v32sim).

* **Inline  &  Raw Assembly  Bubbles**:  You  can write  native  assembly
  directly inside  Lua using  `__asm__("your ASM")` (which  snapshots and
  restores registers  and the stack pointer)  or `__rawasm__("your ASM")`
  for unprotected  execution. Both modes support  string interpolation of
  Lua variables using `{var_name}` syntax.

---

## Supported Lua Language Features

`v32lua`  implements a  subset  of Lua,  tailored  specifically for  game
development on embedded hardware.

**Variables & Scoping**

* **Global Variables:** Automatically registered  in RAM and accessed via
  symbols (`[var_name]`, `[func_name]`). Address  `0` is reserved for the
  heap pointer and  addresses `1`/`2` are reserved scratch  words used by
  the float-to-string routine; ordinary global variables begin at address
  `3`.

* **Local  Variables:**   Declared  with  the  `local`   keyword.  Scoped
  lexically  to   the  enclosing   block  (function  bodies,   loops,  or
  conditionals) and mapped to stack  offsets (`[BP - offset]`). A `local`
  declared at  a chunk's own  top level —  outside any function  — is
  promoted to a global instead, since its storage would otherwise live in
  a stack  frame that  returns before  any game  code runs;  this applies
  equally to `local`s pulled in via `--#include`.

In  Lua   parlance,  functions   are  "first-class  citizens",   and  are
effectively variables.  That is borne  out in  `v32lua` as they  both are
transacted within the NaN-boxing scheme.

**Multiple Assignment**

The compiler natively supports  multiple assignment and variable swapping
without requiring explicit user temporaries:

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Synthesizes temporary register chains to safely swap values
```

**Bitwise operators**

Lua 5.3/5.4's `&`, `|`, `~` (xor), `<<`, `>>` and unary `~` (not). Every
number is a float32, so each operation takes its operands as 32-bit words
and converts the result back:

* **Native / TIC-80:** integers. Operands are floored and taken modulo
  2^32, so `0xFFFFFFFF` and `-1` are the same word. The sign of the full
  value is carried along, so `&`, `|`, `~` match 64-bit Lua for operands in
  [-2^31, 2^32): `-1 & 0xFF` is 255, `~0` is -1, `0xFF << 24` is
  4278190080. `>>` is logical; a shift of 32 or more gives 0.
* **PICO-8:** 16.16 fixed point, exactly as PICO-8 does it — fractions take
  part (`0.5 | 1` is 1.5, `~0` is -1/65536), `>>` is arithmetic, and
  PICO-8's `^^` (xor), `>>>` (logical right), `<<>` / `>><` (rotate), the
  compound forms (`&= |= ^^= <<= >>= >>>= <<>= >><=`), the `band`/`bor`/
  `bxor`/`bnot`/`shl`/`shr`/`lshr`/`rotl`/`rotr` functions and `0b1010`
  binary literals are all accepted. Hex literals `0x8000`–`0xffff` are
  negative, as in PICO-8 (`0xffff == -1`).

Limit: a float32 holds 24 significant bits, so a result such as
`0xDEADBEEF` comes back rounded; masks and packed fields with fewer
significant bits (`0xFF000000`, `0xF0F0`) are exact. Expressions of
literals (`1 << 4`) are folded at compile time.

**Object-Oriented Programming & Tables**

`v32lua` provides seamless syntactic sugar for table-based OOP models:

* **Method  Definition  Desugaring:**  Defining  a function  on  a  table
  automatically generates a mangled label  and links the function pointer
  property:

```lua
function Player.move(dx, dy) ... end
-- Desugars to: Player["move"] = __function_Player_move
```

* **Method  Call Desugaring  (`:` operator):**  Using the  colon operator
  automatically  evaluates the  table  expression and  injects  it as  an
  implicit `self` parameter:

```lua
Player:move(5, -2)
-- Desugars to: Player.move(Player, 5, -2)
```

**Control Flow**

* **Loops:** `while <cond> do ... end` statements supported with full
  block scoping.

* **Loop Control:** `break` statements jump immediately to the end label
  of the current innermost loop (tracked via an internal compilation loop
  stack).

* **`goto` / `::label::`:** Lua 5.2-style labels, block-scoped, with
  forward references — the usual `goto continue` / `::continue::` idiom
  works, including the same label name in several loops of one function.

* **Conditionals:** `if <cond> then ... elseif <cond> then ... else ...
  end` structures with short-circuit branching.

**Operators & Expressions**

* **Arithmetic:** `+`, `-`, `*`, `/` (mapped to Vircon32 floating-point
  hardware instructions `FADD`, `FSUB`, `FMUL`, `FDIV`), and unary minus
  (`-` via `__builtin_unm`).

* **Relational:** `==`, `~=` (via `__builtin_eq` with NaN unboxing), `<`,
  `>`, `<=`, `>=` (via hardware `FLT`, `FLE`, `FGT`, `FGE`).

* **Logical:** `and`, `or`, `not` (with short-circuit evaluation).

* **String Concatenation:** `..` operator automatically pushes operands
  and invokes the runtime subroutine `__builtin_strcat`.

* **String literals & methods:** `"double"`, `'single'` and long
  `[[bracket]]` strings (no escapes; a newline right after `[[` is
  dropped). Number literals accept exponents (`1e-3`, `2.5E4`). String
  library calls work as methods on string values — `s:sub(2, #s)`,
  `("abc"):upper()`, `s:len()`, `rep`, `byte`, `find`, `lower`,
  `reverse`, `gsub` — and strings used as table keys compare by content,
  so `t["a" .. "b"]` finds `t.ab`.

* **Numbers → strings:** whole numbers print without a decimal point
  (`"5"`), others with up to 6 significant fractional digits and no
  trailing zeros (`"0.5"`, `"2.25"`) — float32 precision.

* **Length Operator:** `#` operator invokes `__builtin_len` to resolve
  string or table lengths.

**Functions & Multi-Value Returns**

Functions  can   return  multiple  values  simultaneously.   The  calling
convention optimizes the first three returned expressions by placing them
directly  into registers  `R0`,  `R2`, and  `R3`.  Any additional  return
values  (4th and  beyond) are  spilled directly  onto the  caller's stack
frame.

**String Literal Pooling**

All string  literals declared  in source code  (e.g., `"GAME  OVER"`) are
collected during compilation, deduplicated,  and emitted into a dedicated
data section  at the end of  the ROM (`__string_0: string  "GAME OVER"`),
preventing redundant ROM consumption.

**Truthy & Falsy Short-Circuit Evaluation**

In  Lua,  only  `nil`  and  `false`  evaluate  to  false  in  conditional
expressions;  every other  value  (including `0`  and  empty strings)  is
**truthy**. `v32lua` implements this via two high-speed assembly emission
primitives:

* **`emit_falsy_jump(reg, label)`**: Tests if `reg` matches `0xFFC00000`
  (Nil) or `0xFFC00001` (False). If either matches, execution jumps to the
  target label.

* **`emit_truthy_jump(reg, label)`**: Tests against Nil and False; if
  neither matches, execution short-circuits to the target label.

When logical operators (`and`, `or`)  are evaluated, the evaluated result
is left  intact in  the destination register,  preserving Lua's  idiom of
returning the actual operand value rather than a strict boolean.

---

## Hardware I/O & Compiler Intrinsics

One  of  the   most  powerful  features  of  `v32lua`   is  its  **static
intrinsic  interception  engine**.  When the  compiler  encounters  table
accesses  or  function  calls   matching  specific  system  paths  (e.g.,
`ioports.gpu.clear()`),  it **bypasses  dynamic table  lookups entirely**
and emits direct Vircon32 hardware I/O instructions (`IN`, `OUT`).

**Automatic Type Casting Across I/O Boundaries**

Because  Lua variables  are stored  as  NaN-boxed IEEE  754 floats  while
Vircon32  hardware ports  expect  32-bit integers  or booleans,  `v32lua`
automatically injects hardware conversion  instructions during port reads
and writes:

* **`CFI` (Cast Float to Integer):** Emitted automatically when writing
  numeric values to integer GPU/Input ports.

* **`CFB` (Cast Float to Boolean):** Emitted when writing boolean flags to
  hardware registers, decoding Lua truthiness (only `nil`/`false` are
  falsy) rather than a raw non-zero test.

* **`CIF` (Cast Integer to Float):** Emitted immediately after executing
  an `IN` instruction from integer hardware ports, ensuring the value is
  immediately usable as a Lua number.

* **Boolean port reads:** decoded into the boxed `true`/`false`
  representation rather than a raw `0.0`/`1.0` float, since `0.0` is
  truthy in Lua and would otherwise make a disconnected gamepad or memory
  card read as "connected".

**Comprehensive Intrinsics Reference Table**

The full, authoritative reference for every intrinsic — `ioports.gpu.*`,
`ioports.inp.*`, `ioports.spu.*`, `ioports.tim.*`, `ioports.rng.*`,
`ioports.car.*`, `ioports.mem.*`, `music.*`/`sfx.*`, `tilemap.*`,
`memcard.*`, and `system.*` — lives in [doc/API.md](doc/API.md), including
port-ordering caveats, call signatures, and worked examples. A short
sample of the most commonly used entries:

*GPU Control & Drawing (`ioports.gpu.*`)*

| Lua Path / Intrinsic | Vircon32 Port / Command | Access | Description & Behavior |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Read / Write | Sets or reads the active texture ID used for drawing operations. |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Read / Write | Selects the texture sub-region (sprite frame) to render. |
| **`ioports.gpu.x`** / **`ioports.gpu.y`** | `GPU_DrawingPointX/Y` | Read / Write | Screen coordinates for drawing placement. |
| **`ioports.gpu.minX/minY/maxX/maxY`** | `GPU_RegionMin/MaxX/Y` | Read / Write | Defines the pixel boundaries of the active texture region. |
| **`ioports.gpu.hotX/hotY`** | `GPU_RegionHotSpotX/Y` | Read / Write | Sets the drawing origin (hotspot) relative to the sprite region. |
| **`ioports.gpu.draw([mode])`** | `GPU_Command` | Function Call | Executes a hardware draw command: `"zoom"`, `"rotate"`, `"rotozoom"`, or default. |
| **`ioports.gpu.clear([color])`**<br>**`ioports.gpu.clear(r, g, b [, a])`** | `GPU_ClearColor` + `GPU_Command` | Function Call | Sets the clear color and wipes the screen. Supports preset color strings (`"black"`, `"white"`, `"blue"`, `"red"`, `"green"`), a packed `0xAABBGGRR` value (a literal, or `hex()` for a variable), or separate components: `clear(r, g, b [, a])`, each `0`–`255`, alpha defaulting to opaque. |

*Gamepad & Input (`ioports.inp.*`)*

| Lua Path / Intrinsic | Vircon32 Port / Command | Access | Description & Behavior |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Read / Write | Selects the active controller index (`0`-`3`) for input polling. |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Read Only | Returns a Lua boolean: is the selected gamepad connected. |
| **`ioports.inp.left/right/up/down`** | `INP_Gamepad*` | Read Only | D-Pad directional state (`> 0` pressed, `< 0` released). |
| **`ioports.inp.A/B/X/Y/L/R/START`** | `INP_GamepadButton*` | Read Only | Action/shoulder button state (`> 0` pressed, `< 0` released). |
| **`ioports.inp.inputs`** | *Custom Action Subroutine* | Read Only | **Collation intrinsic:** polls all gamepad buttons/axes in one pass, collates them into a single 32-bit bitmask, and casts it to a Lua float. |

*System & Runtime Utilities*

| Lua Path / Intrinsic | Vircon32 Instruction | Access | Description & Behavior |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Function Call | Emits the hardware `HLT` instruction, immediately terminating CPU execution or freezing the frame until the next interrupt/frame cycle. |
| **`system.wait()`** | `WAIT` | Function Call | Emits the hardware `WAIT` instruction, pausing execution until the next interrupt/frame cycle. |
| **`system.frames`** / **`system.cycles`** | `TIM_FrameCounter` / `TIM_CycleCounter` | Read Only | Running frame/cycle counters. |
| **`print(x, y, ...)`** | `__builtin_tostring` + `__builtin_print` | Function Call | Coerces arguments to string representation and outputs them to the console debug terminal. First two parameters are the X, Y position on screen, in pixels. |

---

## Inline Assembly (`__asm__` & `__rawasm__`)

For performance-critical inner loops or advanced Vircon32 hardware
manipulation, `v32lua` provides direct inline assembly injection.

**Standard Inline Assembly (`__asm__`)**

The `__asm__` directive allows embedding raw Vircon32 assembly strings
directly inside Lua functions. Crucially, it supports **variable
interpolation**, enabling seamless bridging between Lua scope symbols and
assembly registers:

```lua
local speed = 5.0
__asm__( "MOV R0, {speed}\n" ..
         "FADD R0, 1.5\n" ..
         "MOV {speed}, R0" )
```

* **How it works:** Any identifier wrapped in braces (e.g., `{speed}`) is
  dynamically resolved by `emit_interpolated_asm` at compile time. If
  `speed` is a local variable at stack offset 1, `{speed}` is
  automatically replaced with `[BP - 1]`. If it is a global, it resolves
  to `[var_speed]`.

* Each line of interpolated assembly is passed through the compiler's
  formatting engine, ensuring consistent indentation and comment alignment
  in the output `.asm` file.

* This standard inline assembly applies some mild guardrails and
  protections, in the form of backing up any existing used registers along
  with the stack. While it doesn't prevent problems, it may help mitigate
  some caused by accident. Any register changes made here are lost outside
  the inline "bubble".

**Raw Assembly (`__rawasm__`)**

The `__rawasm__` directive outputs the literal string directly to the
assembly stream without safeties applied. This can be quite dangerous, and
should only be used by the most knowledgeable and experienced of assembly
users. It is also the basis of the compiler's own unit-test harness: a
test file is typically a `function main() ... end` wrapper around a
sequence of `__rawasm__` blocks with `__debugN:` labels for breakpointing
under [v32sim](https://github.com/g7n-org/v32sim)

---

## Memory Map Reference

| RAM Address | Designation | Usage |
| --- | --- | --- |
| `0` | `HEAP_POINTER` | Stores the dynamic starting address for runtime table/string allocations. |
| `1`, `2` | `FTOA_SCRATCH_PTR_A`/`B` | Reserved scratch words used by the float-to-string conversion routine. |
| `3` to `HEAP_START - 1` | Global RAM | Sequentially allocated slots for global Lua variables, resource IDs, and promoted top-level `local`s. |
| `HEAP_START` and up | Dynamic Heap | Runtime memory managed by the table allocator and string routines. |
| Stack Top (`SP`) | Call Stack | Function activation records, local variables, and saved register states. |

`HEAP_START` is computed after all code generation has finished, so
top-level statement codegen that registers late globals can never collide
with the heap.

---

## Compiler quirks and assumptions

While `v32lua` attempts to be a functional Lua compiler, it by no means is
a full-to-specification implementation of the language. For one, there's
no bytecode virtual machine, nor interpreter — Lua compiles straight down
to native assembly.

Further, there are some explicit deviations from a standard implementation
of the language to better suit the freestanding environment of Vircon32:

* `print()` requires, as its first two parameters, the `x` and `y`
  position on the screen.

* Standalone `return` statements do not work (will generate a syntax
  error). Give it something (`nil`, `0`, etc.) to make it happy.

* Program execution MUST reside within a function. While you can declare
  functions, you must use one of the designated starting points to begin
  the chain of execution (`init()`, `game_loop()`, or `main()`). Not
  having a `main()` or `game_loop()` function leads to a compile error.
  `game_loop()` automatically issues a `WAIT` before calling itself again,
  making it your natural game-loop location — similar to other fantasy
  consoles (like the `TIC()` function in TIC-80, which is similarly
  required).

* `v32lua` is a **float-only** implementation: there is no Lua 5.3+
  integer/float dual-number type. All numbers are IEEE-754 float32, so
  integers above 2^24 cannot be represented exactly — worth keeping in
  mind for bit-manipulation-heavy code.

* A `local` declared in a block lexically outside any function (a bare
  `do...end`, or an `if`/`while`/`for` body at chunk level) currently has
  no compiler-level guardrail if a function later reads that name — see
  the roadmap item below.

Clearly, this effort is focused on making a tool for development on
Vircon32, and not on being a fully-compliant Lua implementation. Efforts
will be made to come as close as is possible and feasible, without
sacrificing significant performance or veering away from being the tool it
is intended to be.

## Compiler Optimization

Early on in compiler development, all optimization code was removed and 
factored into a separate tool, [v32opt](https://github.com/wedge1020/v32opt).
This is designed as a general purpose Vircon32 assembly optimizer, meant
for use with the C compiler and lua compiler (along with handwritten assembly).
Early tests have shown some mild improvements to performance, and potential
space savings by eliminating redundant instructions.

At time of writing this tool is still very much in development, but is showing
promise and will likely work for standard scenarios under the `-O1`, `-O2`, 
and even `-O3` optimization levels. It is meant to be inserted into the build
chain after the compiling and before assembling.

## Roadmap / Not Yet Implemented

The following are known, deliberate gaps rather than bugs — either
deferred to keep initial development moving, or awaiting a design
decision:

* `pcall`/`error`/`assert`
* `string.match`/`gmatch`, `setmetatable`
* `select()`, and `next()` as a callable function (`pairs()` works)
* Expanding a trailing multi-value call into a table constructor or an
  argument list: `{f()}` and `g(f())` keep only `f()`'s first value
  (`{...}` and `local a, b = f()` do expand). The calling convention
  carries no return count; this needs one.
* Arithmetic on numeric strings (`"10" + 5`): Lua coerces the string; here
  the result is not a number. Convert with `tonumber()` first.
* Bitwise operators work on 32-bit words (numbers are float32): `x << 32`
  and wider results, and `>>` of a negative number, differ from Lua's
  64-bit integers, and a result with more than 24 significant bits
  (`0xDEADBEEF`) is rounded. See **Bitwise operators** above.
* `string.format` as a method (`("%d"):format(x)`) — use
  `string.format(...)`.
* Garbage collection: the heap is a bump allocator, so every table,
  closure and runtime string lives until reset. Long-running games should
  reuse tables rather than create them per frame.
* Smaller PICO-8 audio, further: a cart's sound is now its 64 SFX at
  22050 Hz (Celeste: 18 MB, from 66 MB). Sequencing single notes instead
  of whole SFX would roughly halve that again (about half of Celeste's
  notes repeat), at the cost of a note-level sequencer.
* PICO-8: `pal`/`palt` (compile to no-ops with a warning), `clip`,
  `peek`/`poke` and the `@ % $` peek shorthands, `cartdata`/`dget`/`dset`,
  real `stat` values, fractional `spr` widths; the SFX editor's filter
  switches in synthesized sound
* TIC-80: `tri`/`trib`, `elli`/`ellib`, `clip`, `mouse`, `font`, `spr`
  rotation, `map()`'s remap callback, and synthesis of a cart's own
  `WAVES`/`SFX`/`MUSIC` data (placeholder tones are used). `peek`/`poke`
  work on an emulated RAM, but writing the screen, palette, tiles or sound
  registers has no visible or audible effect. `key`/`keyp` always report
  no key (there is no keyboard); `trace` does nothing.
* TIC-80 `circ`/`circb`/`rectb` draw one GPU quad per pixel: a cart that
  draws many large outlines each frame (witchem_up's title screen) runs
  below full speed
* `tonumber(s, base)` — the two-argument, explicit-base form
* A diagnostic (warn/error) for reading, from inside a function, a
  `local` declared in a block lexically outside any function at chunk
  level (see above)

---

## AI utilization

NOTE: There was extensive AI use and interaction throughout this effort. A
distinction should be made from "vibe coding", but there is definitely a
blur between human and AI. In the end, both benefit and could compensate
for the other's deficiencies.

This endeavour actually was not primarily about developing a compiler, it
began as an honest attempt to get a feel for AI and its impact: its role
and detriment to human thinking and education. That it has a compiler
theme was merely to accentuate a point of interest. It has certainly been
a learning experience. If sufficient compiler concepts and background
knowledge weren't sufficiently known going into this, the effort would have
ended far less successfully.
