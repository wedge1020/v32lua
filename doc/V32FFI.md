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
($4,194,304\text{ words}$). Because standard Vircon32 C programs allocate
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
0x00FFFFFF +-------------------------------------------------------+
```

### Memory Base Determination Logic

The starting  address for `__lua_heap_pointer` is  calculated dynamically
at compile time based on two inputs:

1. **Explicit Reserve (`FFI_RAM_RESERVE`)**: Configured by the developer via a preprocessor directive or set to the default floor of $65,536\text{ words}$ ($64\text{ kW}$).
2. **Autodetected Memory Usage (`;;FFI_MAX_MEM`)**: Automatically read from headers or C compiler output annotations indicating the highest static memory address used by native code.

The formula used to compute the effective heap start address is:

$$\text{Heap Start Address} = \max\left(\text{FFI\_RAM\_RESERVE},\; \text{FFI\_MAX\_MEM} + \text{FFI\_SAFETY\_PADDING}\right)$$

### Directive Reference

| Directive / Annotation | Source | Description | Example |
| --- | --- | --- | --- |
| `--#config FFI_RAM_RESERVE <words>` | Script Source | Explicitly overrides the low-memory reservation for C globals. | `--#config FFI_RAM_RESERVE 262144` *(Reserves 256 kW / 1 MB)* |
| `;;FFI_MAX_MEM <address>` | Generated Header | Emitted by toolchains to specify the highest word address used by C static memory. | `;;FFI_MAX_MEM 8192` *(Indicates C globals end at word 8192)* |

---

## 5. Summary of FFI Configuration Defaults

> [!NOTE]
> All memory sizes in the Vircon32 system are measured in **32-bit words** ($1\text{ word} = 4\text{ bytes}$).

* **Default Reserved Region**: $65,536\text{ words}$ ($64\text{ kW} / 256\text{ KB}$).
* **Safety Alignment Buffer**: $256\text{ words}$ ($1\text{ KB}$).
* **Default Heap Start Address (no FFI configuration)**: `0x00010000` ($65,536$).
* **Argument Boxing Tag (Lua Number)**: `0x7FF00000`.
* **Argument Unboxing Mask**: `0x003FFFFF`.
