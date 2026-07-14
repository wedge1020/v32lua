# v32lua: Vircon32 Lua Compiler

**Target Architecture:** Vircon32 Fantasy Console (32-bit)

**Implementation Language:** C (Flex/Bison + Custom Semantic Emitter)

---

## 1. Overview & Architecture

`v32lua`  is  an  optimizing  compiler   written  in  C  that  translates
dynamically typed Lua source code  directly into static Vircon32 assembly
language (`.asm`) and automatically generates cartridge configuration XML
(`.xml`) for the Vircon32 emulator and hardware.

Unlike   traditional   Lua   implementations  that   rely   on   bytecode
interpretation  and  a  heavy  runtime virtual  machine,  `v32lua`  is  a
**true  ahead-of-time (AOT)  compiler**. It  emits lean,  native Vircon32
instructions, leveraging  a custom **NaN-boxing** type  system, automatic
stack-frame optimization, and  zero-overhead **compiler intrinsics** that
map Lua table accesses directly to Vircon32 memory-mapped I/O registers.

```
+------------------+     +-------------------+     +------------------+
| Source (.lua)    | --> | Lexer & Parser    | --> | AST Construction |
+------------------+     | (Flex / Bison)    |     +------------------+
                         +-------------------+              |
                                                            v
+------------------+     +-------------------+     +------------------+
| Cartridge Config | <-- | Vircon32 Assembly | <-- | Semantic Emitter |
| (.xml & .vbin)   |     | Emitter (.asm)    |     | & Peephole Opt   |
+------------------+     +-------------------+     +------------------+

```

---

## 2. Compiler Pipeline & CLI Usage

### Command-Line Interface

The  compiler is  invoked  from  the command  line  and supports  several
diagnostic and build workflow flags:

```bash
v32lua [options] <input_file.lua>
```

| Flag | Description |
| --- | --- |
| `-o <file>` | Specifies the output assembly filename (defaults to `<input>.asm`).  |
| `-v`, `--verbose` | Enables verbose build logging across compilation stages and asset generation.  |
| `-g` | Enables debug tracking mode, generating internal source-to-assembly line mapping files.  |
| `--version` | Displays compiler version and author information.  |
| `--help`, `-h` | Displays command-line usage instructions.  |

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

## 3. Build Instructions & Makefile Targets

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

---

## 4. Cartridge Build Hints (`--#`)

`v32lua` introduces a specialized comment syntax (`--#`) that acts as an inline build script for the Vircon32 ROM builder. During lexical analysis, these directives are intercepted and compiled into a `<rom-definition>` XML file (`.xml`) alongside the output assembly.

### Supported Cartridge Directives

```lua
--#title "Super Space Shooter 32"
--#version 1.2
--#texture background "assets/bg_stars.png"
--#texture player_sprite "assets/ship.png"
```

* **`--#title <"string">`**: Sets the cartridge title metadata in the generated XML.

* **`--#version <string>`**: Sets the version attribute for the ROM definition.

* **`--#texture <var_name> <"path">`**: Registers a texture resource, assigns it an incremental integer ID (starting at `0`), and binds the ID to a global Lua variable (`background`, `player_sprite`, etc.) so it can be passed directly to GPU intrinsics without manual ID bookkeeping.

---

## 5. Target Architecture: Vircon32 & Assembly Design

For developers familiar with C and computer architecture, `v32lua` bridges high-level scripting with raw hardware control by respecting the unique constraints of the Vircon32 CPU.

### Register Allocation Scheme

The Vircon32 CPU provides 16 general-purpose 32-bit registers (`R0` through `R15`). `v32lua` divides these into strict functional roles:

| Register(s) | Role & Allocation Rules |
| --- | --- |
| **`R0` – `R5**` | **General Scratch & Expression Evaluation:** Dynamically allocated during AST traversal for arithmetic, logic, and function return values (`R0`, `R2`, `R3`).  |
| **`R6`** | **Condition Scratch / Non-Destructive Guard:** Reserved specifically to protect against Vircon32's destructive comparison instructions during branching and logical evaluations.  |
| **`R7` – `R10**` | **General Purpose:** Available for extended expression evaluation and complex expression trees.  |
| **`R11` – `R13**` | **String & Memory Helpers:** Used by hardware and runtime subroutines for block memory operations (`MOVS`, `SETS`, `CMPS`).  |
| **`R14` (`BP`)** | **Base Pointer:** Points to the base of the current function's local stack frame.  |
| **`R15` (`SP`)** | **Stack Pointer:** Top of the execution stack.  |

### Handling Destructive Comparisons

A critical architectural peculiarity of Vircon32 is that **comparison instructions are destructive to the destination register**. For example, executing an integer equality check:

```assembly
IEQ R0, R1   ; Evaluates (R0 == R1), stores boolean result (0 or 1) directly back into R0!
```

If `R0` held a variable that needed to be reused later, the comparison would destroy it. To resolve this without manual variable duplication in Lua, `v32lua` uses **`R6` as a dedicated condition scratch register** during conditional branching (`if`, `while`, logical short-circuiting):

```assembly
MOV R6, R0          ; Copy operand to scratch register R6
IEQ R6, 0xFFC00000  ; Perform destructive test against canonical Nil
JT  R6, __target    ; Jump if true (without altering R0)
```

### Stack Frames & Leaf Function Optimization

Functions that declare local variables or perform complex nested calls generate a standard C-style stack frame:

```assembly
__function_my_func:
    PUSH BP
    MOV  BP, SP
    ; ... body ...
    MOV  SP, BP
    POP  BP
    RET
```

* **Local Variables:** Addressed at negative offsets relative to the base pointer: `[BP - 1]`, `[BP - 2]`, etc.

* **Function Parameters:** Pushed by the caller prior to invocation and addressed at positive offsets: `[BP + 2]`, `[BP + 3]`, etc.

**Optimization:** Before emitting prologue instructions, `v32lua` runs an
AST  analysis  pass (`check_needs_stack`).  If  a  function is  a  **Leaf
Function**  (it does  not  call other  functions, declare  stack-spilling
locals, or  perform complex table  allocations), the frame  pointer setup
(`PUSH BP; MOV BP, SP`) is  completely omitted, saving 4 clock cycles and
2 stack slots per call.

---

## 6. The NaN-Boxing Type System

To support Lua's dynamic typing on a 32-bit hardware architecture without
the overhead of heap-allocated type wrappers or multi-word tagged unions,
`v32lua` implements an IEEE 754 **NaN-Boxing** type representation.

In  IEEE  754  single-precision  floating-point,  any  32-bit  word  with
all  8 exponent  bits set  (`0xFF`)  and a  non-zero mantissa  represents
Not-a-Number (NaN). This  leaves 23 bits of payload space  inside the NaN
space to encode type tags, pointers, and special constants.

### Bit-Level Representation Map

```
  31                                  0
  [s | e e e e e e e e | m m m m m ... ]
```

| Type / Value | Hexadecimal Mask | Encoding Details |
| --- | --- | --- |
| **Float (Number)** | `0x00000000` to `0xFF7FFFFF` | Standard IEEE 754 single-precision floating-point numbers.

 |
| **Nil** | `0xFFC00000` | Canonical Quiet NaN with zero payload.

 |
| **Boolean False** | `0xFFC00001` | Quiet NaN + Payload Bit 0 set.

 |
| **Boolean True** | `0xFFC00002` | Quiet NaN + Payload Bit 1 set.

 |
| **String Pointer** | `0x7FC00000` | `address` | Base NaN + Bit 22 set. Lower bits hold the ROM/RAM address of the string literal.

 |
| **Function Pointer** | `0xFF800000` | `address` | Bit 31 set, Bit 22 cleared. Lower 22 bits store the code address (`0x003FFFFF` mask).

 |

### Truthy & Falsy Short-Circuit Evaluation

In  Lua,  only  `nil`  and  `false`  evaluate  to  false  in  conditional
expressions;  every other  value  (including `0`  and  empty strings)  is
**truthy**. `v32lua` implements this via two high-speed assembly emission
primitives:

* **`emit_falsy_jump(reg, label)`**: Tests if `reg` matches `0xFFC00000` (Nil) or `0xFFC00001` (False). If either matches, execution jumps to target label.


* **`emit_truthy_jump(reg, label)`**: Tests against Nil and False; if neither matches, execution short-circuits to target label.



When logical operators (`and`, `or`)  are evaluated, the evaluated result
is left  intact in  the destination register,  preserving Lua's  idiom of
returning the actual operand value rather than a strict boolean.

---

## 7. Supported Lua Language Features

`v32lua` implements a robust subset of Lua 5.1+, tailored specifically for game development on embedded hardware.

### Variables & Scoping

* **Global Variables:** Automatically registered in RAM (starting at address `1`, as address `0` is reserved for the heap pointer) and accessed via symbols (`[var_name]`, `[func_name]`).

* **Local Variables:** Declared with the `local` keyword. Scoped lexically to the enclosing block (`do ... end`, function bodies, loops, or conditionals) and mapped to stack offsets (`[BP - offset]`). Shadowing outer variables is fully supported.

### Multiple Assignment

The compiler natively supports multiple assignment and variable swapping without requiring explicit user temporaries:

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Synthesizes temporary register chains to safely swap values

```

### Object-Oriented Programming & Tables

`v32lua` provides seamless syntactic sugar for table-based OOP models:

* **Method Definition Desugaring:** Defining a function on a table automatically generates a mangled label and links the function pointer property:

```lua
function Player.move(dx, dy) ... end
-- Desugars to: Player["move"] = __function_Player_move
```

* **Method Call Desugaring (`:` operator):** Using the colon operator automatically evaluates the table expression and injects it as an implicit `self` parameter:

```lua
Player:move(5, -2)
-- Desugars to: Player.move(Player, 5, -2)
```

### Control Flow

* **Loops:** `while <cond> do ... end` statements supported with full block scoping.

* **Loop Control:** `break` statements jump immediately to the end label of the current innermost loop (tracked via an internal compilation loop stack).

* **Conditionals:** `if <cond> then ... elseif <cond> then ... else ... end` structures with short-circuit branching.

### Operators & Expressions

* **Arithmetic:** `+`, `-`, `*`, `/` (mapped to Vircon32 floating-point hardware instructions `FADD`, `FSUB`, `FMUL`, `FDIV`), and unary minus (`-` via `__builtin_unm`).

* **Relational:** `==`, `~=` (via `__builtin_eq` with NaN unboxing), `<`, `>`, `<=`, `>=` (via hardware `FLT`, `FLE`, `FGT`, `FGE`).

* **Logical:** `and`, `or`, `not` (with short-circuit evaluation).

* **String Concatenation:** `..` operator automatically pushes operands and invokes the runtime subroutine `__builtin_strcat`.

* **Length Operator:** `#` operator invokes `__builtin_len` to resolve string or table lengths.

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

## 8. Hardware I/O & Compiler Intrinsics

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

* **`CFI` (Cast Float to Integer):** Emitted automatically when writing numeric values to integer GPU/Input ports.


* **`CFB` (Cast Float to Boolean):** Emitted when writing boolean flags to hardware registers.


* **`CIF` (Cast Integer to Float):** Emitted immediately after executing an `IN` instruction from integer hardware ports, ensuring the value is immediately usable as a Lua number.

---

### Comprehensive Intrinsics Reference Table

#### 1. GPU Control & Drawing (`ioports.gpu.*`)

| Lua Path / Intrinsic | Vircon32 Port / Command | Access | Description & Behavior |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Read / Write | Sets or reads the active texture ID used for drawing operations.

 |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Read / Write | Selects the texture sub-region (sprite frame) to render.

 |
| **`ioports.gpu.x`** | `GPU_DrawingPointX` | Read / Write | X screen coordinate for drawing placement.

 |
| **`ioports.gpu.y`** | `GPU_DrawingPointY` | Read / Write | Y screen coordinate for drawing placement.

 |
| **`ioports.gpu.minX`** | `GPU_RegionMinX` | Read / Write | Defines the left pixel boundary of the active texture region.

 |
| **`ioports.gpu.minY`** | `GPU_RegionMinY` | Read / Write | Defines the top pixel boundary of the active texture region.

 |
| **`ioports.gpu.maxX`** | `GPU_RegionMaxX` | Read / Write | Defines the right pixel boundary of the active texture region.

 |
| **`ioports.gpu.maxY`** | `GPU_RegionMaxY` | Read / Write | Defines the bottom pixel boundary of the active texture region.

 |
| **`ioports.gpu.hotX`** | `GPU_RegionHotSpotX` | Read / Write | Sets the X drawing origin (hotspot) relative to the sprite region.

 |
| **`ioports.gpu.hotY`** | `GPU_RegionHotSpotY` | Read / Write | Sets the Y drawing origin (hotspot) relative to the sprite region.

 |
| **`ioports.gpu.draw([mode])`** | `GPU_Command` | Function Call | Executes a hardware draw command. Accepts an optional string mode: `"zoom"` (`GPUCommand_DrawRegionZoomed`), `"rotate"` (`GPUCommand_DrawRegionRotated`), `"rotozoom"` (`GPUCommand_DrawRegionRotozoomed`), or default (`GPUCommand_DrawRegion`).

 |
| **`ioports.gpu.clear([color])`** | `GPU_ClearColor` + `GPU_Command` | Function Call | Sets the clear color and wipes the screen (`GPUCommand_ClearScreen`). Supports preset color strings: `"black"` (`0x000000FF`), `"white"` (`0xFFFFFFFF`), `"blue"` (`0x0000FFFF`), `"red"` (`0xFF0000FF`), `"green"` (`0x00FF00FF`), or numeric hex values.

 |

#### 2. Gamepad & Input (`ioports.inp.*`)

| Lua Path / Intrinsic | Vircon32 Port / Command | Access | Description & Behavior |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Read / Write | Selects the active controller index (`0` to `3`) for input polling.

 |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Read Only | Returns `1` if the selected gamepad is connected, `0` otherwise.

 |
| **`ioports.inp.left`** | `INP_GamepadLeft` | Read Only | D-Pad Left directional state (`1` pressed, `0` released).

 |
| **`ioports.inp.right`** | `INP_GamepadRight` | Read Only | D-Pad Right directional state (`1` pressed, `0` released).

 |
| **`ioports.inp.up`** | `INP_GamepadUp` | Read Only | D-Pad Up directional state (`1` pressed, `0` released).

 |
| **`ioports.inp.down`** | `INP_GamepadDown` | Read Only | D-Pad Down directional state (`1` pressed, `0` released).

 |
| **`ioports.inp.start`** | `INP_GamepadButtonStart` | Read Only | Start button state (`1` pressed, `0` released).

 |
| **`ioports.inp.A`** | `INP_GamepadButtonA` | Read Only | Action Button A state (`1` pressed, `0` released).

 |
| **`ioports.inp.B`** | `INP_GamepadButtonB` | Read Only | Action Button B state (`1` pressed, `0` released).

 |
| **`ioports.inp.X`** | `INP_GamepadButtonX` | Read Only | Action Button X state (`1` pressed, `0` released).

 |
| **`ioports.inp.Y`** | `INP_GamepadButtonY` | Read Only | Action Button Y state (`1` pressed, `0` released).

 |
| **`ioports.inp.L`** | `INP_GamepadButtonL` | Read Only | Left Shoulder Bumper state (`1` pressed, `0` released).

 |
| **`ioports.inp.R`** | `INP_GamepadButtonR` | Read Only | Right Shoulder Bumper state (`1` pressed, `0` released).

 |
| **`ioports.inp.inputs`** | *Custom Action Subroutine* | Read Only | **Collation Intrinsic:** Executes a rapid multi-port polling sequence across all 11 gamepad buttons/axes, shifting and combining their boolean states into a single 32-bit integer bitmask before casting to float (`CIF`). Highly efficient for button state snapshots!

 |

#### 3. System & Runtime Utilities

| Lua Path / Intrinsic | Vircon32 Instruction | Access | Description & Behavior |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Function Call | Emits the hardware `HLT` instruction, immediately terminating CPU execution or freezing the frame until the next interrupt/frame cycle.

 |
| **`print(...)`** | `__builtin_tostring` + `__builtin_print` | Function Call | Coerces arguments to string representation via runtime conversion subroutines and outputs them to the console debug terminal.

 |

---

## 9. Inline Assembly (`__asm__` & `__rawasm__`)

For performance-critical inner loops or advanced Vircon32 hardware manipulation (such as custom sound chip channel programming or DMA transfers), `v32lua` provides direct inline assembly injection.

### Standard Inline Assembly (`__asm__`)

The `__asm__` directive allows embedding raw Vircon32 assembly strings directly inside Lua functions. Crucially, it supports **variable interpolation**, enabling seamless bridging between Lua scope symbols and assembly registers:

```lua
local speed = 5.0
__asm__( "MOV R0, {speed}\n" ..
         "FADD R0, 1.5\n" ..
         "MOV {speed}, R0" )

```

* **How it works:** Any identifier wrapped in braces (e.g., `{speed}`) is dynamically resolved by `emit_interpolated_asm` at compile time. If `speed` is a local variable at stack offset 1, `{speed}` is automatically replaced with `[BP - 1]`. If it is a global, it resolves to `[var_speed]`.


* Each line of interpolated assembly is passed through the compiler's formatting engine, ensuring consistent indentation and comment alignment in the output `.asm` file.



### Raw Assembly (`__rawasm__`)

The `__rawasm__` directive outputs the literal string directly to the assembly stream without variable interpolation or formatting modification, ideal for defining bulk data blocks, custom labels, or raw binary payloads.

---

## 10. Code Example: Putting It All Together

The following complete example demonstrates cartridge hints, table OOP, GPU drawing intrinsics, and inline assembly working together:

```lua
--#title "Vircon32 Tech Demo"
--#version 1.0
--#texture logo "assets/vircon_logo.png"

-- Define a Player object using Table OOP
Player = {}
function Player:init(x, y)
    self.x = x
    self.y = y
    self.speed = 2.5
end

function Player:render()
    -- Select texture using auto-generated ID from cartridge hint
    ioports.gpu.texture = logo
    ioports.gpu.region = 0
    
    -- Set drawing coordinates directly to hardware registers
    ioports.gpu.x = self.x
    ioports.gpu.y = self.y
    
    -- Draw using hardware rotozoom command
    ioports.gpu.draw("rotozoom")
end

-- Main Game Loop
Player:init(160, 120)

while true do
    -- Clear screen to dark blue
    ioports.gpu.clear("blue")
    
    -- Read collated gamepad bitmask in a single intrinsic operation
    local pad = ioports.inp.inputs
    
    -- Check D-Pad Right
    if ioports.inp.right == 1 then
        Player.x = Player.x + Player.speed
    end
    
    Player:render()
    
    -- Halt execution until the next frame interrupt
    system.halt()
end
```

---

## 11. Compiler quirks and assumptions

While `v32lua` attempts  to be a functional lua compiler,  it by no means
is  a full-to-specifications  implementation  of the  language. For  one,
there's no bytecode virtual machine, nor interpreter.

Further, there are some explicit  deviations to a standard implementation
of the language to better suit the freestandingenvironment of Vircon32:

  * `print()` requires, as its first two parameters, the `x` and `y` position on the screen.
  * standalone `return` statements do not work (will generate a syntax error). Give it something (`nil`, 0, etc.) to make it happy.
  * program execution starts in a required `main()` function. Not having a `main()` will lead to an error. Further, `main()` will automatically issue a `WAIT` before calling itself again, making it your natural game loop location. This is intended to be similar to other fantasy consoles (like the `TIC()` function in TIC-80 which is similarly required).

Clearly,  this effort  is focused  on making  a tool  for development  on
Vircon32, and not to be  some fully-compliant lua implementation. Efforts
will  be made  to come  an  close as  is possible  and feasible,  without
sacrificing significant performance  or veering away from  being the tool
it is intended to be.
