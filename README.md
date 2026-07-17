# v32lua: Vircon32 Lua Compiler

[Spanish version / en español](README.es.md) | [Dutch version / Nederlandse versie](README.nl.md) | [French version / en francais](README.fr.md)

**Target Architecture:** Vircon32 Fantasy Console (32-bit)

**Implementation Language:** C (Flex/Bison + Custom Semantic Emitter)

**Repository:** [github.com/wedge1020/v32lua](https://github.com/wedge1020/v32lua)

`v32lua` is  a Lua compiler  written in  C that targets  the **Vircon32**
fantasy  console.  Instead of  embedding  a  heavy bytecode  interpreter,
`v32lua`  parses Lua  source code  and compiles  it directly  into native
Vircon32 assembly and also produces XML cartridge definitions.

While it is not yet complete, one  aim of development is to make `v32lua`
a substitute  (by no  means a  replacement) for  the Vircon32  C Compiler
in  the Vircon32  development  stack. Basically,  select  your choice  of
language- C or lua, then once it  is compiled, you have assembly, and can
proceed  with  the build  regardless  of  implementation language.  As  a
result,  efforts  have been  made  to  mimic  various behaviours  of  the
Vircon32 C Compiler to make compiler substitution more transparent.

Designed from  the ground  up with retro  fantasy console  constraints in
mind,  this  compiler  features  zero-cost  hardware  intrinsics,  custom
NaN-boxing, algebraic peephole optimizations,  and rich developer tooling
designed to facilitate your lua game development endeavours.

```
+------------------+     +-------------------+     +------------------+
| Source (.lua)    | --> | Lexer & Parser    | --> | AST Construction |
+------------------+     | (Flex / Bison)    |     +------------------+
                         +-------------------+              |
                                                            v
+------------------+     +-------------------+     +------------------+
| Cartridge Config | <-- | Vircon32 Assembly | <-- | Semantic Emitter |
| (.xml)           |     | Emitter (.asm)    |     | & Peephole Opt   |
+------------------+     +-------------------+     +------------------+
```

---

## AI interaction

NOTE: There was extensive AI  use and interaction throughout this effort.
A distinction should be made from  "vibe coding", but there is definitely
a  blur  between  human and  AI.  In  the  end,  both benefit  and  could
compensate for the other's deficiencies.

This endeavour actually was not primarily about developing a compiler, it
began as an honest attempt to get a  feel for AI and its impact: its role
and detriment  to human thinking  and education.  That it has  a compiler
theme was merely to accentuate a point of interest. It has certainly been
a  learning experience.  If sufficient  compiler concepts  and background
knowledge wasn't  known going into this,  the effort would have  ended in
less successfully. 

---

## 🚀 Key Features & New Developments

### Flexible Execution Models: `main()` vs. `game_loop()`

To accommodate different game  architecture styles, the compiler supports
two distinct entry point paradigms:

* **The Auto-Ticking  Harness (`game_loop`)**:  If your  program declares
  a  `game_loop()`  function,  the  compiler  automatically  generates  a
  continuous  runtime   harness.  The  CPU  calls   `game_loop()`,  stays
  execution for the current frame  using the hardware `WAIT` instruction,
  and  loops infinitely.  This is  ideal  for standard  arcade games  and
  demos. This mimicks the behaviour of various other fantasy consoles.

* **Manual  Control  (`main`)**:  If  your program  declares  a  `main()`
  function,  control is  handed directly  to `__function_main`.  You take
  full  ownership of  the frame  cycle and  must manually  execute inline
  assembly  or  hardware waits.  The  compiler  tracks whether  a  `WAIT`
  instruction  is emitted  inside `main()`;  if it  is missing,  `v32lua`
  issues a semantic warning at compile time.

* **Initialization Hook**:  In both  models, if  an `init()`  function is
  present,  it is  guaranteed  to execute  exactly  once after  top-level
  global RAM allocations and before the main loop begins.

### Enhanced NaN-Boxing: RAM vs. ROM Elements

`v32lua` uses a 32-bit tagging  architecture that packs type metadata and
payload  pointers  into  unified  values.  Recent  enhancements  strictly
separate immutable **ROM elements** from  dynamic **RAM heap objects** to
ensure memory safety and zero-copy literal referencing:

| Data Type | Hex Mask / Tag | Architecture Description |
| --- | --- | --- |
| **Nil** | `0xFFC00000` | Canonical representation for undefined/missing values. |
| **Boolean False** | `0xFFC00001` | Short-circuit falsy value. |
| **Boolean True** | `0xFFC00002` | Short-circuit truthy value. |
| **ROM String** | `0x7FC00000` | Pointers to read-only string data sections (`__string_%d`) in ROM. |
| **Function / Closure** | `0xFF800000` | Boxed function memory addresses (Bit 31=1, Bit 22=0). |
| **Number** | IEEE 754 Float | Unboxed native Vircon32 floating-point values for direct math. |

### Expanded Hardware Intrinsics & I/O Mapping

High-performance  Vircon32 games  cannot  afford  hash-table lookups  for
hardware   manipulation.  `v32lua`   intercepts  specific   table  member
expressions  and   compiles  them  directly  into   native  hardware  I/O
instructions:

* **Zero-Cost    Hardware    Access**:    Accessing    namespaces    like
  `ioports.gpu.*`, `ioports.spu.*`, `ioports.tim.*`, or `system.*` (e.g.,
  `ioports.gpu.x  =  100`  or   `system.frames`)  bypasses  table  lookup
  routines entirely.  They compile  directly to hardware  port operations
  (such as `GPU_DrawingPointX` or `TIM_FrameCounter`).

* **Consolidated  Gamepad  Polling   and  traditional  inputs**:  Polling
  controller  input  is  optimized   into  a  single  variable  intrinsic
  (`ioports.inp.inputs`).  The compiler  polls `INP_GamepadLeft`  through
  `INP_GamepadButtonR`,  collates   the  active  button  states   into  a
  bitshifted  32-bit integer  mask, and  casts  it to  a Lua  float in  a
  single  register.  The standalone  gamepad  inputs  are also  available
  (`ioports.inp.left`, `ioports.inp.A`, etc.)  as variable intrinsics for
  use.

* **Built-in   Fast  Paths**:   Standard  Lua   operations  like   string
  concatenation (`..`), length (`#`), and  unary minus (`-`) map directly
  to optimized runtime  subroutines (`__builtin_strcat`, `__builtin_len`,
  `__builtin_unm`).

### Optimizing Compiler Pipeline (`-O1`)

NOTE:  compiler optimizations  are very  much a  work in  progress. While
infrastructure  has  been laid  out,  extensive  testing  has yet  to  be
done,  and will  likely break  things  (and badly).  Only the  **peephole
optimization** and **frame pointer omission** have gotten any significant
testing,  and both  may currently  be broken  with other  recent compiler
changes. Probably best not to enable optimizations at this point if you'd
like working outputs.

When optimization is  enabled via command-line flags  (`o_optflag >= 1`),
`v32lua` applies multi-stage code transformations:

* **Peephole   Optimization**:  Scans   emitted  assembly   to  eliminate
  redundant  self-moves (`MOV  R0, R0`)  and unnecessary  memory re-loads
  (`MOV A, B` followed immediately by `MOV B, A`).

* **Algebraic Simplification**:  Folds neutral  floating-point operations
  at compile time. Expressions like `x +  0.0`, `x * 1.0`, `x - 0.0`, and
  `x / 1.0` simplify directly to `x`. Pure expressions multiplied by zero
  (`x * 0.0`) optimize directly to `0.000000` without evaluating the left
  operand if it carries no side effects.

* **Frame  Pointer Omission  (Leaf  Functions)**: Functions  that do  not
  declare local variables, accept parameters,  or push stack frames strip
  the standard `PUSH  BP` / `MOV BP, SP` prologue  and epilogue entirely,
  executing as bare jumps.

* **Dead Store  & Branch  Elimination**: Integrates  constant propagation
  and DSE tracking tables  (`DeadStoreCandidate`, `ConstSymbol`) to prune
  unreachable conditional branches and unused variable writes.

### Developer Experience & Debug Tooling

* **Visual  ASCII  Error  Reporting**:  Lexical,  syntax,  semantic,  and
  internal  compiler  errors  print highlighted,  multi-line  ASCII  code
  snippets pointing  directly to  the offending line  in the  source file
  (`yyin`).

* **Source-to-Assembly  Mapping (`-g`)**:  Passing  the  `-g` debug  flag
  generates  a companion  `.debug`  file alongside  the output  assembly.
  This  file maps  relative Vircon32  assembly line  offsets to  original
  Lua  source lines  and functional  entry points,  enabling step-through
  debugging. This should be identical to the C compiler's `-g` option.

* **Inline  &  Raw Assembly  Bubbles**:  You  can write  native  assembly
  directly inside Lua using `__asm__("your ASM")` (which safely snapshots
  and  restores  stack  pointers  and locked  General  Purpose  Registers
  `R0`-`R13`) or `__rawasm__("your ASM")` for unprotected execution. Both
  modes  support string  interpolation of  Lua variables  using the  same
  `{var_name}` syntax present  in the C compiler  (inline assembly works,
  interpolation still needs testing).

---

## 🛠️ Cartridge Resource Hints

`v32lua` allows you to embed Vircon32 cartridge metadata directly in your
Lua source code  using special block comments. The  compiler parses these
hints to  auto-generate the  project's `.xml`  ROM definition  and assign
sequential hardware resource IDs.

Supported hints include:

  * `--#version "X.Y"` influences the cartridge version field in the XML
  * `--#title "TITLE"` sets the CART title
  * `--#texture var "path/image.png"` configure in-game texture
  * `--#sound var "path/sound.wav"` configure in-game sound (not done)

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
data, you can proceed to the `packrom` step.

---

## 💻 Technical Demo: Sample Program

Here  is a  complete example  demonstrating `v32lua`  features, including
hardware intrinsics and the auto-ticking game loop:

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

---

## 📦 Compiler Pipeline & Usage

### Compilation Flow

1. **Lexical & Syntax Analysis**: Flex/Bison parses the Lua source into a
typed Abstract Syntax Tree (AST).

2.  **Symbol  & Scope  Resolution**:  Resolves  variables across  lexical
scopes, mapping globals  to sequential RAM addresses starting  at `1` and
locals to `[BP - offset]` stack frame positions.

3. **Code  Generation & Peephole Optimization**:  Emits Vircon32 assembly
instructions while applying `-O1`  transformations and hardware intrinsic
substitutions.

4. **Cartridge  Assembly**: Emits the  final `.asm` file,  embeds runtime
support  libraries,  generates the  read-only  string  data section,  and
outputs the `.xml` cartridge definition.

### Command-Line Integration

```bash
# Compile with optimizations and symbol generation for debugging
$ v32lua -O1 -g -o program.asm program.lua
```

Available options:

* `-O0`: Disables compiler optimizations (default)
* `-O1`: Enables peephole optimizations, algebraic folding, and frame pointer omission
* `-g`: Generates the `program.asm.debug` line-mapping text file
* `-o`: Specifies the assembly output filename (defaults to stdout if omitted)
* `-v`: More verbose output
* `-w`: Suppress any compiler warnings
* `--version`: Displays compiler version and author information
* `--help`, `-h`: Displays command-line usage instructions

### Compilation Stages

When `-v`  is enabled,  `v32lua` reports its  progress through  five core
pipeline stages:

1. **Stage  1: Lexer** —  Tokenizes the Lua source,  stripping standard
comments and processing string escape  sequences (`\n`, `\t`, `\r`, `\\`,
`\"`).

2. **Stage 2: Preprocessor** — Evaluates cartridge hints (`--#...`) and
custom comment syntaxes.

3. **Stage  3: Parser**  — Constructs a  complete Abstract  Syntax Tree
(AST)  using a  LALR(1)  Bison grammar  with  strict operator  precedence
(PEMDAS + logic core).

4. **Stage  4: Semantic  Analyzer** — Executes  a function  pre-pass to
register  global  function  symbols,  initialize the  global  scope,  and
resolve type annotations.

5.  **Stage 5:  Emitter**  —  Traverses the  AST  to generate  Vircon32
assembly,  applying  register  allocation, scope  offsets,  and  peephole
optimizations. Finally, it outputs the cartridge XML configuration file.

---

## Build Instructions & Makefile Targets

The repository includes  a root-level Makefile to  manage the compilation
of  the   compiler  binary,  automated  testing,   deployment,  and  code
maintenance.

### Compilation Instructions

To build  the main compiler  binary from  source, run the  default target
from the root directory:

```bash
make
```

### Reference Table of Makefile Targets

| Target | Description | Core Actions & Dependencies |
| --- | --- | --- |
| **`all`** | **Default Target.** Builds the main compiler executable.  | Invokes the compilation process natively inside the `src/` subdirectory.  |
| **`clean`** | Standard workspace cleanup utility.  | Recursively wipes intermediate build artifacts out of `src/` and removes generated files from `testing/` and `demos/`.  |
| **`install`** | Installs the compiler binary onto the host system.  | Passes the target down to the `src/` directory's localized installation scripts.  |
| **`tests`** | Executes the automated compilation testing suite.  | Explicitly depends on the compiler binary (`bin/v32lua`) being built first, then triggers the test routines inside `testing/`.  |
| **`demos`** | Builds the collection of available demos.  | Explicitly depends on the compiler binary (`bin/v32lua`) being built first, then builds each demo under `demos/`.  |
| **`asmcheck`** | Validates assembly correctness.  | Requires `bin/v32lua` to be present, then processes assembly validations via the `testing/` suite.  |
| **`monofiles`** | Builds streamlined monolithic file variants.  | Runs the `monofile` creation workflow sequentially inside both `src/` and `testing/`.  |

### Truthy & Falsy Short-Circuit Evaluation

In  Lua,  only  `nil`  and  `false`  evaluate  to  false  in  conditional
expressions;  every other  value  (including `0`  and  empty strings)  is
**truthy**. `v32lua` implements this via two high-speed assembly emission
primitives:

* **`emit_falsy_jump(reg, label)`**: Tests  if `reg` matches `0xFFC00000`
  (Nil) or  `0xFFC00001` (False). If  either matches, execution  jumps to
  target label.

* **`emit_truthy_jump(reg,  label)`**: Tests  against Nil  and False;  if
  neither matches, execution short-circuits to target label.

When logical operators (`and`, `or`)  are evaluated, the evaluated result
is left  intact in  the destination register,  preserving Lua's  idiom of
returning the actual operand value rather than a strict boolean.

## Supported Lua Language Features

`v32lua`  implements a  subset  of Lua,  tailored  specifically for  game
development on embedded hardware.

### Variables & Scoping

* **Global  Variables:** Automatically  registered  in  RAM (starting  at
  address  `1`, as  address `0`  is reserved  for the  heap pointer)  and
  accessed via symbols (`[var_name]`, `[func_name]`).

* **Local  Variables:**   Declared  with  the  `local`   keyword.  Scoped
  lexically to the enclosing block (`do ... end`, function bodies, loops,
  or conditionals) and mapped to stack offsets (`[BP - offset]`).

In  Lua   parlance,  functions   are  "first-class  citizens",   and  are
effectively variables.  That is borne  out in  `v32lua` as they  both are
transacted within the NaN-boxing scheme.

### Multiple Assignment

The compiler natively supports  multiple assignment and variable swapping
without requiring explicit user temporaries:

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Synthesizes temporary register chains to safely swap values
```

### Object-Oriented Programming & Tables

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

### Control Flow

* **Loops:**  `while <cond>  do ... end`  statements supported  with full
block scoping.

* **Loop Control:** `break` statements  jump immediately to the end label
of the current  innermost loop (tracked via an  internal compilation loop
stack).

* **Conditionals:** `if  <cond> then ... elseif <cond> then  ... else ...
end` structures with short-circuit branching.

### Operators & Expressions

* **Arithmetic:** `+`,  `-`, `*`, `/` (mapped  to Vircon32 floating-point
hardware instructions  `FADD`, `FSUB`,  `FMUL`, `FDIV`), and  unary minus
(`-` via `__builtin_unm`).

* **Relational:** `==`, `~=` (via `__builtin_eq` with NaN unboxing), `<`,
`>`, `<=`, `>=` (via hardware `FLT`, `FLE`, `FGT`, `FGE`).

* **Logical:** `and`, `or`, `not` (with short-circuit evaluation).

* **String  Concatenation:** `..` operator automatically  pushes operands
and invokes the runtime subroutine `__builtin_strcat`.

* **Length  Operator:** `#`  operator invokes `__builtin_len`  to resolve
string or table lengths.

### Functions & Multi-Value Returns

Functions  can   return  multiple  values  simultaneously.   The  calling
convention optimizes the first three returned expressions by placing them
directly  into registers  `R0`,  `R2`, and  `R3`.  Any additional  return
values  (4th and  beyond) are  spilled directly  onto the  caller's stack
frame at `[BP + 2 + arg_count + offset]`.

### String Literal Pooling

All string  literals declared  in source code  (e.g., `"GAME  OVER"`) are
collected during compilation, deduplicated,  and emitted into a dedicated
data section  at the end of  the ROM (`__string_0: string  "GAME OVER"`),
preventing redundant ROM consumption.

---

## Hardware I/O & Compiler Intrinsics

One  of  the   most  powerful  features  of  `v32lua`   is  its  **static
intrinsic  interception  engine**.  When the  compiler  encounters  table
accesses  or  function  calls   matching  specific  system  paths  (e.g.,
`ioports.gpu.clear()`),  it **bypasses  dynamic table  lookups entirely**
and emits direct Vircon32 hardware I/O instructions (`IN`, `OUT`).

### Automatic Type Casting Across I/O Boundaries

Because  Lua variables  are stored  as  NaN-boxed IEEE  754 floats  while
Vircon32  hardware ports  expect  32-bit integers  or booleans,  `v32lua`
automatically injects hardware conversion  instructions during port reads
and writes:

* **`CFI` (Cast  Float to Integer):** Emitted  automatically when writing
numeric values to integer GPU/Input ports.

* **`CFB` (Cast  Float to Boolean):** Emitted when  writing boolean flags
to hardware registers.

* **`CIF` (Cast Integer to  Float):** Emitted immediately after executing
an `IN`  instruction from integer  hardware ports, ensuring the  value is
immediately usable as a Lua number.

---

### Comprehensive Intrinsics Reference Table

#### GPU Control & Drawing (`ioports.gpu.*`)

| Lua Path / Intrinsic | Vircon32 Port / Command | Access | Description & Behavior |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Read / Write | Sets or reads the active texture ID used for drawing operations.  |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Read / Write | Selects the texture sub-region (sprite frame) to render.  |
| **`ioports.gpu.x`** | `GPU_DrawingPointX` | Read / Write | X screen coordinate for drawing placement.  |
| **`ioports.gpu.y`** | `GPU_DrawingPointY` | Read / Write | Y screen coordinate for drawing placement.  |
| **`ioports.gpu.minX`** | `GPU_RegionMinX` | Read / Write | Defines the left pixel boundary of the active texture region.  |
| **`ioports.gpu.minY`** | `GPU_RegionMinY` | Read / Write | Defines the top pixel boundary of the active texture region.  |
| **`ioports.gpu.maxX`** | `GPU_RegionMaxX` | Read / Write | Defines the right pixel boundary of the active texture region.  |
| **`ioports.gpu.maxY`** | `GPU_RegionMaxY` | Read / Write | Defines the bottom pixel boundary of the active texture region.  |
| **`ioports.gpu.hotX`** | `GPU_RegionHotSpotX` | Read / Write | Sets the X drawing origin (hotspot) relative to the sprite region.  |
| **`ioports.gpu.hotY`** | `GPU_RegionHotSpotY` | Read / Write | Sets the Y drawing origin (hotspot) relative to the sprite region.  |
| **`ioports.gpu.draw([mode])`** | `GPU_Command` | Function Call | Executes a hardware draw command. Accepts an optional string mode: `"zoom"` (`GPUCommand_DrawRegionZoomed`), `"rotate"` (`GPUCommand_DrawRegionRotated`), `"rotozoom"` (`GPUCommand_DrawRegionRotozoomed`), or default (`GPUCommand_DrawRegion`).  |
| **`ioports.gpu.clear([color])`** | `GPU_ClearColor` + `GPU_Command` | Function Call | Sets the clear color and wipes the screen (`GPUCommand_ClearScreen`). Supports preset color strings: `"black"` (`0x000000FF`), `"white"` (`0xFFFFFFFF`), `"blue"` (`0x0000FFFF`), `"red"` (`0xFF0000FF`), `"green"` (`0x00FF00FF`), or numeric hex values.  |

#### Gamepad & Input (`ioports.inp.*`)

| Lua Path / Intrinsic | Vircon32 Port / Command | Access | Description & Behavior |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Read / Write | Selects the active controller index (`0` to `3`) for input polling.  |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Read Only | Returns `1` if the selected gamepad is connected, `0` otherwise.  |
| **`ioports.inp.left`** | `INP_GamepadLeft` | Read Only | D-Pad Left directional state (`> 0` pressed, `< 0` released).  |
| **`ioports.inp.right`** | `INP_GamepadRight` | Read Only | D-Pad Right directional state (`> 0` pressed, `< 0` released).  |
| **`ioports.inp.up`** | `INP_GamepadUp` | Read Only | D-Pad Up directional state (`> 0` pressed, `< 0` released).  |
| **`ioports.inp.down`** | `INP_GamepadDown` | Read Only | D-Pad Down directional state (`> 0` pressed, `< 0` released).  |
| **`ioports.inp.start`** | `INP_GamepadButtonStart` | Read Only | Start button state (`> 0` pressed, `< 0` released).  |
| **`ioports.inp.A`** | `INP_GamepadButtonA` | Read Only | Action Button A state (`> 0` pressed, `< 0` released).  |
| **`ioports.inp.B`** | `INP_GamepadButtonB` | Read Only | Action Button B state (`> 0` pressed, `< 0` released).  |
| **`ioports.inp.X`** | `INP_GamepadButtonX` | Read Only | Action Button X state (`> 0` pressed, `< 0` released).  |
| **`ioports.inp.Y`** | `INP_GamepadButtonY` | Read Only | Action Button Y state (`> 0` pressed, `< 0` released).  |
| **`ioports.inp.L`** | `INP_GamepadButtonL` | Read Only | Left Shoulder Bumper state (`> 0` pressed, `< 0` released).  |
| **`ioports.inp.R`** | `INP_GamepadButtonR` | Read Only | Right Shoulder Bumper state (`> 0` pressed, `< 0` released).  |
| **`ioports.inp.inputs`** | *Custom Action Subroutine* | Read Only | **Collation Intrinsic:** Executes a rapid multi-port polling sequence across all 11 gamepad buttons/axes, shifting and combining their boolean states into a single 32-bit integer bitmask before casting to float (`CIF`). Highly efficient for button state snapshots!  |

#### System & Runtime Utilities

| Lua Path / Intrinsic | Vircon32 Instruction | Access | Description & Behavior |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Function Call | Emits the hardware `HLT` instruction, immediately terminating CPU execution or freezing the frame until the next interrupt/frame cycle. |
| **`system.wait()`** | `WAIT` | Function Call | Emits the hardware `WAIT` instruction, pausing execution until the next interrupt/frame cycle.  |
| **`print(x, y, ...)`** | `__builtin_tostring` + `__builtin_print` | Function Call | Coerces arguments to string representation via runtime conversion subroutines and outputs them to the console debug terminal. First two parameters are the X, Y position on the screen, in pixels. |

---

## Inline Assembly (`__asm__` & `__rawasm__`)

For  performance-critical  inner  loops  or  advanced  Vircon32  hardware
manipulation, `v32lua` provides direct inline assembly injection.

### Standard Inline Assembly (`__asm__`)

The `__asm__`  directive allows  embedding raw Vircon32  assembly strings
directly  inside   Lua  functions.  Crucially,  it   supports  **variable
interpolation**, enabling seamless bridging between Lua scope symbols and
assembly registers:

```lua
local speed = 5.0
__asm__( "MOV R0, {speed}\n" ..
         "FADD R0, 1.5\n" ..
         "MOV {speed}, R0" )
```

* **How  it works:** Any  identifier wrapped in braces  (e.g., `{speed}`)
is  dynamically  resolved  by `emit_interpolated_asm`  at  compile  time.
If  `speed`  is  a  local  variable  at  stack  offset  1,  `{speed}`  is
automatically replaced with `[BP - 1]`. If it is a global, it resolves to
`[var_speed]`.

* Each  line of  interpolated assembly is  passed through  the compiler's
formatting engine, ensuring consistent  indentation and comment alignment
in the output `.asm` file.

*  This  standard  inline  assembly  applies  some  mild  guardrails  and
protections, in the form of backing  up any existing used registers along
with the stack.  While it doesn't prevent problems, it  may help mitigate
some caused by accident. Of note,  any register changes made here will be
lost outside the inline "bubble".

### Raw Assembly (`__rawasm__`)

The `__rawasm__`  directive outputs  the literal  string directly  to the
assembly stream  without safeties applied.  This can be  quite dangerous,
and should  only be  used by  the most  knowledgeable and  experienced of
assembly users.

---
## 🧠 Memory Map Reference

| RAM Address Range | Designation | Usage |
| --- | --- | --- |
| `0` | `heap_pointer` | Stores the dynamic starting address for runtime table allocations. |
| `1` to `N` | Global RAM | Sequentially allocated slots for global Lua variables and resource IDs. |
| `N + 1`+ | Dynamic Heap | Runtime memory managed by `__builtin_table_new` and string allocators. |
| Stack Top (`SP`) | Call Stack | Function activation records, local variables, and saved register states. |

---

## Compiler quirks and assumptions

While `v32lua` attempts  to be a functional lua compiler,  it by no means
is  a full-to-specifications  implementation  of the  language. For  one,
there's no bytecode virtual machine, nor interpreter.

Further, there are some explicit  deviations to a standard implementation
of the language to better suit the freestanding environment of Vircon32:

  * `print()`  requires, as  its first  two parameters,  the `x`  and `y`
    position on the screen.

  * standalone `return`  statements do not  work (will generate  a syntax
    error). Give it something (`nil`, 0, etc.) to make it happy.

  * program  execution  MUST reside  within  a  function. While  you  can
    declare  functions,  you must  use  one  of the  designated  starting
    points to  begin the  chain of  execution (in  the form  of `init()`,
    `game_loop()`, or  `main()`. Not  having a `main()`  or `game_loop()`
    function  will   lead  to  an  error.   Further,  `game_loop()`  will
    automatically issue a  `WAIT` before calling itself  again, making it
    your natural  game loop location. This  is intended to be  similar to
    other fantasy consoles (like the  `TIC()` function in TIC-80 which is
    similarly required).

Clearly,  this effort  is focused  on making  a tool  for development  on
Vircon32, and not to be  some fully-compliant lua implementation. Efforts
will  be made  to come  an  close as  is possible  and feasible,  without
sacrificing significant performance  or veering away from  being the tool
it is intended to be.
