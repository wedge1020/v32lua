# NaN-Boxing Architecture

This compiler infrastructure utilizes **32-bit NaN-Boxing** (Not-a-Number Boxing) to represent all dynamically typed Lua values within a single machine word. By exploiting the architectural specification of IEEE 754 floating-point numbers, the runtime compresses primitives, object references, and floating-point numeric values into a unified, highly optimized format tailored specifically for the Vircon32 processor.

---

## Why NaN-Boxing for Vircon32?

In traditional dynamically typed language runtimes, a variable must store both its **type tag** and its **actual data/payload**. On a 32-bit architecture like the Vircon32, a naive implementation requires a "tagged union" structure spanning at least two words (64 bits): one word for the type enum and one word for the value or pointer.

NaN-boxing eliminates this overhead by taking advantage of how IEEE 754 single-precision (32-bit) floating-point numbers represent undefined values (NaNs). In standard IEEE 754, any 32-bit word where all 8 exponent bits are set to `1` and the 23-bit mantissa is non-zero is evaluated by the hardware as a NaN. This leaves millions of unique bit patterns that the hardware considers "Not a Number," providing a vast, unused space where custom type tags and memory addresses can be safely stored.

By repurposing these unused NaN payloads, **every Lua value takes up exactly 1 word (32 bits) of RAM and register space.**

---

## Bit-Level Implementation & Tag Registry

The Vircon32 Lua runtime reserves the upper **10 bits** of the 32-bit word for type tagging and uses the lower **22 bits** (`0x003FFFFF`) to store raw memory pointers or immediate primitive payloads.

When a value is a standard floating-point number, its upper bits will not match any reserved NaN tags, allowing the CPU's native floating-point instructions to operate on it directly without modification or unboxing overhead.

### Runtime Tag Registry

The following table details the canonical bit masks and tags implemented in the assembly runtime (`runtime.s`):

| Lua Data Type | Upper Tag Mask | Canonical Hex Tag | Payload Area (Lower 22 Bits) | Assembly Usage Reference |
| --- | --- | --- | --- | --- |
| **Number (Float)** | *Varied* | *Standard IEEE 754* | Native Float Mantissa | Zero-cost native execution |
| **String** | `0xFFC00000` | `0x7FC00000`<br> | Raw Heap Address

 | `__builtin_strcat`, `__tostring`<br> |
| **Table** | `0xFFC00000` | `0x7F800000`<br> | Raw Heap Address

 | `__builtin_table_new`<br> |
| **Function** | `0xFFC00000` | `0xFF800000`<br> | Code/Closure Address

 | `__tostring_function`<br> |
| **Nil** | `0xFFC00000` | `0xFFC00000`<br> | `0x000000`<br> | Canonical absence of value

 |
| **Boolean (False)** | `0xFFC00000` | `0xFFC00001`<br> | `0x000001`<br> | Immediate boolean false

 |
| **Boolean (True)** | `0xFFC00000` | `0xFFC00002`<br> | `0x000002`<br> | Immediate boolean true

 |

---

## Key Architectural Benefits

* **50% Memory Bandwidth Reduction:** Transferring values between CPU registers, the hardware stack, and heap storage requires only a single memory read/write cycle (`MOV`) instead of two.
* **Zero-Cost Numeric Arithmetic:** Because numbers are stored as standard IEEE 754 floats rather than wrapped inside a heap-allocated struct, math operations incur zero boxing or unboxing penalties. The CPU executes math instructions directly on the registers.
* **O(1) Universal Equality (`==`):** In the runtime's equality evaluation (`__builtin_eq`), identical floats, booleans, nils, and identical object references can be validated in a single clock cycle using a bitwise comparison (`IEQ R3, R2`). If the 32-bit patterns match exactly, the values are equal.


* **Ultra-Fast Type Dispatching:** Determining a variable's type requires only a bitwise `AND` mask of the top bits (`AND R2, 0xFFC00000`) followed by an immediate branch (`IEQ` / `JT`), enabling hyper-fast method dispatching in operations like `__builtin_len` (`#`) and `__builtin_tostring`.


* **Unified Register Passing:** Function arguments and return values seamlessly map 1:1 to Vircon32's general-purpose registers (`R0`–`R15`), avoiding complex multi-register calling conventions or stack-overflow hazards.

---

## Runtime Mechanics & Usage Examples

### 1. Boxing a Heap Allocation (Table Creation)

When allocating a new structure (such as a Table) on the heap, the memory allocator returns a raw 22-bit memory address in `R0`. The runtime boxes this address into a Lua Table by applying the Table tag via a bitwise `OR` instruction:

```assembly
;; R0 holds the raw heap pointer (e.g., address 0x00000410)
OR   R0, 0x7F800000      ; Apply Table NaN-tag -> R0 is now 0x7F800410[cite: 11]

```

### 2. Unboxing a Reference (String Access)

When a built-in function needs to read or manipulate the underlying characters of a string, it strips the upper 10-bit tag using a bitwise `AND` mask (`0x003FFFFF`) to isolate the safe physical memory address:

```assembly
MOV  R1, [BP+2]          ; Load tagged string pointer from stack[cite: 11]
AND  R1, 0x003FFFFF      ; UNBOX: Clear upper 10 bits -> R1 is now a raw memory address[cite: 11]
MOV  R2, [R1]            ; Safely read string header or character data from the heap[cite: 11]

```

### 3. Fast-Path Type Validation

In routines like table indexing (`t[k]`), the runtime performs non-destructive type verification to separate numeric array indices from hash-map keys:

```assembly
MOV  R3, R2              ; Copy key to scratch register[cite: 11]
AND  R3, 0xFFC00000      ; Isolate top 10 bits[cite: 11]
INE  R3, 0               ; If top bits != 0, it is a tagged pointer/primitive, NOT a float![cite: 11]
JT   R3, __table_get_fallback ; Route tagged keys to hash table lookup[cite: 11]

```

---

## Technical Bounds & Considerations

* **Address Space Ceiling:** Because the lower 22 bits are dedicated to pointer storage (`0x003FFFFF`), the maximum addressable heap space for boxed objects is $2^{22}$ words (4,194,304 words / 16 MB). This aligns comfortably with the Vircon32 hardware architecture, which naturally operates within a 4 MW physical RAM space.


* **Strict Masking Discipline:** Assembly developers modifying compiler intrinsics or writing bare-metal runtime subroutines must adhere strictly to the unboxing protocol. Attempting to dereference a boxed pointer without first masking off the upper tag via `AND Rx, 0x003FFFFF` will result in an immediate out-of-bounds memory fault.

Here is a general-purpose, professional writeup formatted in GitHub-flavored Markdown. You can copy and paste this directly into your project's `FEATURES.md` file.

---

## Standalone Compiler Executable & Resource Embedding

This compiler is distributed as a **true standalone, zero-dependency executable**. Unlike traditional compiler toolchains that require external libraries, header files, or environment variable configurations (like `PATH` or `COMPILER_HOME`) to function, this compiler bundles all necessary runtime assets directly into its binary.

---

### The `.incbin` Embedding Mechanism

To achieve complete self-containment without bloating the codebase or requiring complex build steps, the compiler leverages the GNU Assembler (`gas`) **`.incbin` directive** (or equivalent linker-level resource embedding).

During the compilation of the compiler itself, external assets—such as the standard runtime library, startup assembly wrappers (`crt0`), and default system headers—are embedded directly into the compiler's read-only data section (`.rodata`).

```c
// Example of how embedded runtime resources are exposed to the code generator
extern const char _binary_runtime_asm_start[];
extern const char _binary_runtime_asm_end[];

size_t runtime_size = _binary_runtime_asm_end - _binary_runtime_asm_start;

```

When generating output, the code generator writes these embedded payloads directly into the target assembly or binary file from memory. This ensures the runtime architecture is always perfectly synchronized with the compiler version.

---

### Key Capabilities Enabled

* **Embedded Runtime Library:** Standard built-in functions, memory management routines, and system call wrappers are statically compiled into the compiler binary and injected into target builds on demand.
* **Zero Environment Setup:** Users can download the single binary and immediately compile code without installing external SDKs, setting up library paths, or configuring directory hierarchies.
* **Hermetic & Reproducible Builds:** Because all core dependencies are frozen inside the executable, builds are inherently deterministic. The compiler will not fail due to a missing or modified file on the host system's disk.
* **Simplified Distribution & Sandboxing:** Ideal for CI/CD pipelines, containerized environments, and automated grading systems where installing a multi-gigabyte toolchain is impractical.

---

### Traditional Toolchain vs. Standalone Architecture

| Feature | Traditional Compilers (e.g., GCC/Clang) | Standalone Compiler (`incbin`-enabled) |
| --- | --- | --- |
| **Installation** | Requires package manager or multi-file installer | Single binary download |
| **External Dependencies** | Relies on external `/usr/include`, `/lib`, or SDKs | **None** (all core assets are embedded) |
| **Path Configuration** | Needs explicit environment variables (`PATH`, etc.) | Works out-of-the-box from any directory |
| **Portability** | Low; tied to host OS library layouts | **High**; easily moved or executed anywhere |
| **Maintenance** | Risk of version mismatch with external libraries | **Zero risk**; runtime is version-locked |

> **Note for Contributors:** If you are modifying the internal runtime library or built-in assembly macros, you do not need to rewrite C strings manually. Simply edit the source files in the `runtime/` directory; the build system will automatically rebuild and re-embed the raw binary data using `.incbin` during the next compilation cycle.
