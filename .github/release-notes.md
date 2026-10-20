**v32lua** is a Lua compiler for [Vircon32](https://www.vircon32.com): Lua goes in, native Vircon32 assembly and the cartridge XML come out. There is no bytecode interpreter; it is a substitute for the Vircon32 C compiler, so once you have assembly you carry on with the usual toolchain.

## Highlights

- **A practical Lua subset, compiled to native code.** Closures with shared upvalues, tables with metatables (`__index`, `__newindex`, `__call`, `__tostring`, `__len`), varargs and multiple returns, `goto`, bitwise operators, the string library, and inline assembly. Numbers are 32-bit floats (NaN-boxed); there are no coroutines or garbage collection, by design.
- **Native Vircon32 API.** Video, sound, input, tilemaps, the memory card and raw I/O ports, with keyboard and mouse support through v32io (needs a v32io device).
- **Run TIC-80 and PICO-8 carts.** Two compatibility layers compile many existing carts, including `.p8` and `.tic` files, to Vircon32 with little or no source change. They are a work in progress: the known gaps are listed in the README and in `doc/PICO8.md` and `doc/TIC80.md`.
- **Carts without the paperwork.** `--#title`, `--#texture`, `--#sound` and `--#tilemap` hints in your source generate the cartridge XML (and its `v32opt` twin) and ready-to-run `Make.sh` / `Make.bat` build scripts.
- **BIOS builds.** `-b` builds a Vircon32 BIOS instead of a cartridge, under the same rules as the official toolchain.
- **Multi-file projects.** `--#include` pastes in other files, and a small standard library (`lib/*.lua`) ships with the compiler.
- **Debuggable.** `-g` writes a file mapping assembly lines back to Lua lines, for stepping through a cart in v32sim; see `doc/DEBUGGING.md`.
- **Documented.** A manual page, the README, and the API and usage references in English, Spanish and French.

## Downloads

Pick the zip for your system: `v32lua-@VERSION@-<os>-<arch>.zip`.

| System | Architectures |
| --- | --- |
| Windows | x86_64, arm64 |
| macOS | x86_64 (Intel), arm64 (Apple silicon) |
| Linux | x86_64, arm64, armv7 and armv8 (Raspberry Pi) |
| OpenBSD, Haiku | included when their (optional) builds succeeded |

Each zip unpacks straight into your `v32tools` folder (`/usr/local/Vircon32/v32tools`, or `C:\Program Files\Vircon32\v32tools` on Windows) and holds `v32lua`, its `--#include` library, the documents and the manual page. Check a download against `SHA256SUMS.txt`. You also need the Vircon32 DevTools on your `PATH` to assemble and pack cartridges.

## Quick start

```sh
v32lua game.lua      # writes game.asm, game.xml, Make.sh and Make.bat
bash Make.sh         # assemble, convert assets, pack the cartridge
```

See the [README](https://github.com/wedge1020/v32lua#readme) for the full feature list and the roadmap of what is not implemented yet. Bug reports and feature requests are welcome in the issues.
