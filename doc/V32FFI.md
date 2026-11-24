# V32FFI Technical Specification & Reference: Foreign Function Interface (FFI) in `v32lua`

---

## 1. Overview: Foreign Function Interface (FFI)

A **Foreign Function Interface (FFI)** is  a mechanism by which a program
written in one programming language can call routines or utilize services
written in another. In managed  or interpreted runtime environments (such
as Lua, Python, or WebAssembly), FFI bridges the high-level language with
low-level compiled languages like C, C++, or Assembly.

```
+------------------------------------+          +------------------------------------+
|         High-Level Language        |          |          Native C Library          |
|             (v32lua)               |          |            (Vircon32 C)            |
|  - Dynamically Typed (NaN-Boxed)   |          |  - Statically Typed (Raw Words)    |
|  - Dynamic Memory & Heap           |          |  - Fixed Stack & Global Memory     |
+------------------------------------+          +------------------------------------+
                   |                                       ^
                   |         Foreign Function Call         |
                   +---------------------------------------+
                              FFI Boundary Layer
                   - Unboxes/Boxes Values
                   - Translates Calling Conventions
                   - Direct Assembly Dispatch
```

### Core Responsibilities of an FFI Layer

1. **Calling Convention Alignment**: Translating the caller's stack frame
setup  into the  exact sequence  (e.g., argument  order, register  usage,
stack cleanup) expected by the target function.

2.  **Type Marshalling  &  Value Unboxing**:  Converting managed  dynamic
types (e.g.,  NaN-boxed floating-point values or  object references) into
raw C data types (e.g., raw 32-bit integers, standard IEEE 754 floats, or
raw pointers) and vice versa.

3. **Symbol  Resolution**: Mapping script-level identifiers  or namespace
paths (e.g.,  `Draw.sprite`) to the  symbol labels emitted by  the native
compiler (e.g., `_Draw_sprite`).

4. **Memory Arena Coexistence**: Ensuring that high-level heap management
does  not collide  with static  or  dynamic memory  regions allocated  by
native code.

---

## 2. The V32FFI Specification

**V32FFI** is the  native FFI specification for  the **Vircon32** virtual
console ecosystem. It establishes a standard protocol for invoking native
C/Assembly  functions directly  from `v32lua`  scripts with  zero dynamic
dispatch overhead.

### Key Specifications

* **Word Size**: 32-bit architecture ($1\text{ word} = 4\text{ bytes}$).
* **Target Assembly Standard**: Vircon32 Assembly (V32ASM).
* **Native C ABI Rules**:
* **Argument Pushing**: Pushed Right-to-Left (last argument first).
* **Caller Cleanup**: The calling function cleans up stack arguments via `IADD SP, <count>`.
* **Return Register**: Return values are passed via hardware register `R0`.
* **Symbol Prefixing**: C functions are exported as assembly labels prefixed with an underscore (e.g., C function `select_texture` becomes V32ASM label `_select_texture`).

* **Name Mangling Standard**:
* Dot (`.`) and Colon (`:`) path separators in script module identifiers are translated to underscores (`_`) during native lookup.
* *Example*: `Graphics.draw_region` resolves to symbol `_Graphics_draw_region`.

* **Omitted Argument Handling**:
* Native C functions do not understand Lua `Nil` (`0xFFC00000`).
* If a script passes fewer arguments than expected by a C function's signature, missing trailing parameters are automatically padded with raw unboxed integer `0` values.

---

## 3. `v32lua` V32FFI Implementation Mechanics

> [!WARNING]
> **Corrected 20261124-dev: the unboxing and boxing below do not match
> v32lua's values.** A Lua number is a plain IEEE-754 float, not a tagged
> word (doc/NaN_boxing.md): `AND R, 0x003FFFFF` destroys it, and
> `OR R0, 0x7FF00000` turns a returned integer into a NaN. Marshalling has to
> go by the C parameter type instead:
>
> | C type | Lua -> C | C -> Lua |
> | --- | --- | --- |
> | `int` | `CFI R` (the float truncated) | `CIF R0` |
> | `float` | as is | as is |
> | `bool` | `true` -> 1, `false`/`nil` -> 0 (a tag test) | 1/0 -> `BOXED_TRUE`/`BOXED_FALSE` |
> | pointer (`int*`, `char*` of a RAM string, a table header) | `AND R, BOXED_PAYLOAD` on a table or RAM-string value: its raw RAM address (strings are one character per word, NUL-ended) | not returned as a Lua value |
>
> A missing trailing argument is padded with 0 as described in section 2.
> The flow diagram and snippets are kept as the original plan; read them
> with this table.

In `v32lua`, FFI integration is  implemented directly within the Abstract
Syntax Tree (AST) code  generator (`NODE_FUNCTION_CALL` in `generate.c`).
When  `v32lua` encounters  a  call  node, it  checks  symbol metadata  to
determine if the target is a native C symbol (`is_c_native == 1`).

```
Script Invocation: Graphics.draw(10, 20)
       |
       v
+-------------------------------------------------------------+
| AST Node: NODE_FUNCTION_CALL                                |
| Target Symbol Check: target_sym->is_c_native == 1           |
+-------------------------------------------------------------+
       |
       +-------------------------------+
       |                               |
  (Native C Path)             (Standard Lua Path)
       |                               |
       v                               v
1. Unbox Args (AND 0x003FFFFF)   1. Keep Boxed Values
2. Pad missing args with 0       2. Pad missing args with Nil
3. Emit: CALL _symbol            3. Emit: CALL __builtin_exec
4. Stack: IADD SP, N             4. Stack: IADD SP, N
5. Box R0 (OR 0x7FF00000)        5. Keep Boxed Return
```

### High-Level Code Generation Workflow

1. **Symbol Detection & Path Resolution**:
The compiler attempts to resolve the call target symbol. If the target symbol is flagged with `is_c_native`, code generation switches to direct C ABI mode.
2. **Argument Unboxing**:
Lua values in `v32lua` use NaN-boxing. When passing values to C, `v32lua` strips the upper 10-bit tag mask:
```assembly
AND R_arg, 0x003FFFFF ; Strip NaN tag, leaving raw 22-bit/32-bit integer or float payload
PUSH R_arg
```

3. **Direct Emission**:
Instead of routing through `__builtin_exec` (which validates type tags for Lua closures), native calls emit a direct instruction:
```assembly
CALL _target_symbol_name
```

4. **Return Value Boxing**:
When the C function returns, raw primitive values in `R0` are converted back into valid boxed Lua Numbers before being assigned to destination registers:
```assembly
MOV R_dest, R0
OR  R_dest, 0x7FF00000 ; Apply standard Lua Number tag
```

---

## 4. Configurable Memory Architecture

The Vircon32 virtual console features 16 MB of flat, word-addressable RAM
($4,194,304\text{ words}$, addresses `0x00000000`-`0x003FFFFF`). Because standard Vircon32 C programs allocate
global and  static variables  (`.bss` and  `.data` sections)  starting at
address  `0x00000000`,  `v32lua` must  guarantee  that  its dynamic  heap
(`heap_pointer`) never overlaps low-memory C variables.

To  accommodate  C  libraries  of  varying  sizes,  `v32lua`  utilizes  a
flexible, dual-mode memory layout.

### Memory Map Layout

```
RAM Address (32-Bit Word Addressing)
0x00000000 +-------------------------------------------------------+
           | C Global & Static Variables (.bss / .data)            |
           | Allocated upward by Vircon32 C Linker                  |
           | Address Range: 0 to (FFI_MAX_MEM - 1)                 |
           +-------------------------------------------------------+
           | FFI Safety Padding (FFI_SAFETY_PADDING = 256 words)  |
FFI Base   +-------------------------------------------------------+
           | RESERVED FFI MEMORY REGION                             |
           | Default: 64 kW (65,536 words / 256 KB)                 |
           | Configurable via: --#config FFI_RAM_RESERVE <words>   |
Heap Start +-------------------------------------------------------+
           | v32lua Dynamic Heap (__lua_heap_pointer)              |
           | Stores GC Objects, Tables, Strings, Closures           |
           |                                                       |
           |                         |                             |
           |                         v                             |
           |            Allocations grow UPWARD                    |
           |                                                       |
0x003FFFFF +-------------------------------------------------------+  (4M words; the stack grows down from here)
```

### Memory Base Determination Logic

The starting  address for `__lua_heap_pointer` is  calculated dynamically
at compile time based on two inputs:

1. **Explicit Reserve (`FFI_RAM_RESERVE`)**: Configured by the developer via a preprocessor directive or set to the default floor of $65,536\text{ words}$ ($64\text{ kW}$).
2. **Autodetected Memory Usage (`;;FFI_MAX_MEM`)**: Automatically read from headers or C compiler output annotations indicating the highest static memory address used by native code.

The formula used to compute the effective heap start address is:

$$\text{Heap Start Address} = \max\left(\text{FFI\_RAM\_RESERVE},\; \text{FFI\_MAX\_MEM} + \text{FFI\_SAFETY\_PADDING}\right)$$

(Superseded by section 5.2, which also counts the C heap and moves all of
v32lua's RAM words, not only its heap, above the reserve.)

### Directive Reference

| Directive / Annotation | Source | Description | Example |
| --- | --- | --- | --- |
| `--#config FFI_RAM_RESERVE <words>` | Script Source | Explicitly overrides the low-memory reservation for C globals. | `--#config FFI_RAM_RESERVE 262144` *(Reserves 256 kW / 1 MB)* |
| `;;FFI_MAX_MEM <address>` | Generated Header | Emitted by toolchains to specify the highest word address used by C static memory. | `;;FFI_MAX_MEM 8192` *(Indicates C globals end at word 8192)* |

---

## 5. Memory and arena rules (settled 20261124-dev, with v32cc)

The FFI is still unimplemented. These are the rules its implementation
follows, agreed with v32cc (its `docs/ARENA.md`, "v32lua FFI").

### 5.1 C owns the bottom of RAM, Lua starts at the reserve's end

Today v32lua's own fixed words start at RAM word 0: `HEAP_POINTER` (0),
`FTOA_SCRATCH_PTR_A`/`_B` (1, 2), then its runtime state, the globals, the
arena and free-list words, and `HEAP_START` after them (`src/emit.c`
`emit_variable_map()`). v32cc places C globals from word 0 too, so the two
collide at words 0-2 before anything else.

**v32lua moves; C keeps its defaults.** With the FFI enabled, every
v32lua RAM word -- the three low words included -- is laid out from
**Lua base** upwards instead of from 0:

```
0x00000000  C globals (.data / .bss), from 0 as v32cc places them
            C heap (if any), inside the reserve (5.3)
            FFI_SAFETY_PADDING
Lua base    HEAP_POINTER, FTOA_SCRATCH_PTR_A/B, runtime words, globals,
            arena / free-list words
HEAP_START  the v32lua heap, growing up
            ...
0x003FFFFF  the stack, growing down
```

Nothing changes without the FFI: Lua base is 0. In the compiler this is the
starting value of `next_ram_address` and the three fixed `%define`s
(`HEAP_POINTER`, `FTOA_SCRATCH_PTR_A/B`); the runtime reaches them only by
those names.

### 5.2 Where Lua base comes from

$$\text{Lua base} = \max\left(\text{FFI\_RAM\_RESERVE},\; \text{FFI\_MAX\_MEM} + \text{C heap words} + \text{FFI\_SAFETY\_PADDING}\right)$$

v32lua lays out its RAM at compile time, as numbers, so it needs the C
side's size as a number when it compiles: **v32cc writes it**. v32cc's link
already defines `__v32_data_end` (the first RAM word after all C globals);
a v32cc option will write it, with the C heap size, as the annotation
v32lua already reads (`src/ast.c`):

```
;;FFI_MAX_MEM <__v32_data_end>
;;FFI_C_HEAP <words>        (0 or absent: no C heap)
```

So the C side is built first and the Lua side reads its annotation file
(`--#include`d, or given on the command line). `--#config FFI_RAM_RESERVE`
stays the floor for a hand-made layout.

### 5.3 The C heap lives in the reserve

v32cc's `--hosted` heap defaults to words 1M-3.75M, which is inside
v32lua's heap. With the FFI, the C heap is part of the reserve (it is
counted in 5.2): v32lua's FFI start-up calls `v32_set_heap(start, end)` on
the reserve's heap part before any Lua code runs -- before stdio's first
allocation -- so a C library needs nothing of its own. C code may use
`<v32arena.h>` over the same region instead.

### 5.4 Lua values held by C (and arenas)

* A Lua table, RAM string or closure passed to C is **borrowed for the
  call**: C may read it (and write a table's array words in place) while
  the call runs.
* C may **keep** a Lua heap value after the call returns only if the
  value was made **outside every open arena**. With `--gc none` nothing is
  freed; with `--gc arena`, `arena.release(m)` frees everything made since
  `m`, and a value C kept from that span dangles. (Block reuse never frees a
  live object: only blocks the runtime has replaced.)
* A C function that keeps a Lua value is declared as such in its binding
  (a `retains` mark). With `--gc-check`, the call stub checks each heap
  value it passes to a `retains` function as the escape check does
  (`__arena_check_store`, `src/runtime/arena.s`) and panics if it was made
  inside the innermost open arena.
* C never frees, resizes or allocates in the Lua heap: Lua memory is v32lua's
  (`__malloc`), C memory is v32cc's.
* The other direction -- C memory that Lua holds -- is v32cc's side
  (`v32_arena_owns`, the debug-mode poison).

### 5.5 Out of memory, arena marks

* C running out of memory shows v32lua's red out-of-memory screen: the FFI
  start-up installs v32lua's `__oom_handler` as the C arena's out-of-memory
  hook (`v32_arena_set_oom`).
* Arena marks do not cross the boundary: a Lua mark is a plain number (a
  heap word address) that only `arena.release` reads, and C has its own
  arenas. If that ever changes, a plain `int` mark would match v32lua's.

---

## 6. Summary of FFI Configuration Defaults

> [!NOTE]
> All memory sizes in the Vircon32 system are measured in **32-bit words** ($1\text{ word} = 4\text{ bytes}$).

* **Default Reserved Region**: $65,536\text{ words}$ ($64\text{ kW} / 256\text{ KB}$).
* **Safety Alignment Buffer**: $256\text{ words}$ ($1\text{ KB}$).
* **Without the FFI** v32lua's RAM starts at word 0 and its heap right after its globals (`HEAP_START`); there is no reserve. The reserve -- and Lua base above it (5.1) -- exists only with the FFI enabled. (`calculate_lua_heap_start()` in `src/emit.c`, which would apply it, has no callers yet.)
* **Argument Boxing Tag (Lua Number)**: `0x7FF00000`.
* **Argument Unboxing Mask**: `0x003FFFFF`.
