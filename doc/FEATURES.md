# Compiler internals: value representation and the embedded runtime

Two design choices shape everything `v32lua` generates: every Lua value
is one 32-bit word (NaN boxing), and the runtime library is built into
the compiler binary. This page gives an overview of both;
[NaN_boxing.md](NaN_boxing.md) has the full bit-level reasoning.

---

## One word per value: NaN boxing

A Lua variable can hold any type, so a value must carry its type with it.
The obvious layout, a type word plus a data word, doubles the memory and
the moves for every value. `v32lua` fits both into one word instead, using
the fact that an IEEE 754 float32 whose 8 exponent bits are all 1 is a
NaN (or an infinity): those bit patterns are never ordinary numbers, so
they can carry a type and a 22-bit payload (an address, or a small
constant) instead.

* A **number** is a plain float32, so arithmetic is the CPU's own `FADD`,
  `FMUL`, … with no unboxing.
* Everything else has all exponent bits set; bit 31 selects RAM (1) or
  ROM (0), bit 22 selects string (1) or table/function (0), and the low 22
  bits are the payload.

| Type | Tag (`value & 0xFFC00000`) | Payload |
|---|---|---|
| number | not one of the tags below | the float itself |
| string literal (ROM) | `0x7FC00000` | ROM offset of the string |
| function | `0x7F800000` | ROM offset of the code; with bit 21 (`0x00200000`) set, the RAM address / 2 of a closure record |
| table | `0xFF800000` | RAM address of the table |
| string built at run time (RAM) | `0xFFC00000` | RAM address (≥ 4) |
| `nil` | `0xFFC00000` | 0 |
| `false` / `true` | `0xFFC00000` | 1 / 2 |

What this buys:

* **Every value is one word** in a register, a stack slot, a table entry
  or a global, and moves with one `MOV`.
* **Equality is mostly one compare.** Identical bit patterns are equal
  values; `__builtin_eq` only does more work for strings, which compare by
  content.
* **Type tests are a mask and a compare** (`AND R, 0xFFC00000` then
  `IEQ`), which is how `type()`, `#`, `tostring()` and table indexing
  dispatch.

Limits that follow from it:

* **22-bit payloads.** RAM is exactly 4M words, so every RAM address fits.
  ROM strings and functions must lie in the first 4M words (16 MB) of the
  cartridge's program ROM; textures and sounds don't count toward this.
* **Numbers are float32**: 24 significant bits. Integers above 2^24 are
  not exact, and there is no separate integer type.
* **A raw 32-bit word can look like a tagged value.** Packed colors from
  `rgba()`, `color()` or `hex()` are raw words, and one whose top bits
  happen to be `0xFFC00000` *is* `nil` to the rest of the program (see
  [API.md](API.md#colors-rgba)).
* **Division by zero, `log(0)` and friends** give finite answers, because
  an infinity or NaN would read back as a tagged value (the table is at
  the end of [NaN_boxing.md](NaN_boxing.md#arithmetic-with-no-boxable-answer)).

## Calling convention

Arguments are pushed on the stack (the callee sees them at `[BP + 2]`,
`[BP + 3]`, …; a variadic function also receives the argument count). The
first three return values come back in `R0`, `R2` and `R3`; further ones
go through a reserved RAM buffer (`MV_BUF`, 32 values), with the count in
`RET_COUNT` when it isn't known at compile time. Captured variables
(upvalues) are pushed as hidden trailing arguments by the closure call
(`__builtin_exec`), so a closure's body reads them like parameters.

## The embedded runtime

The runtime library — tables, strings, number formatting, math, the
sound, input and memory-card helpers, the PICO-8 and TIC-80 layers — is
Vircon32 assembly in `src/runtime/*.s`. `src/runtime_embed.S` includes
each file into the compiler binary with the assembler's `.incbin`
directive, so `bin/v32lua` needs no files beside it: copy it anywhere and
it works.

When compiling a program, the compiler records which parts of the
runtime the program uses (`runtime_req` in the source) and appends only
those units to the generated `.asm`. The output is self-contained
assembly for the Vircon32 assembler, and the runtime always matches the
compiler that produced it.

To change the runtime, edit the files in `src/runtime/` and rebuild; the
Makefile tracks them as dependencies of the embed object.
