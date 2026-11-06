# Headless test harness

Runs a compiled cart on the **official Vircon32 CPU, memory, bus, timer
and RNG cores** (the `ConsoleLogic` of the DesktopEmulator in
[vircon32/ComputerSoftware](https://github.com/vircon32/ComputerSoftware)),
with logging stand-ins for the GPU, SPU, gamepad, cartridge and memory
card. Nothing is drawn or played: GPU and SPU port writes are logged
instead. So program logic, the runtime and the calling convention are
checked on the real CPU, but rendering and audio are not.

## The runner is v32sim's

v32lua has no runner of its own any more. `v32orun` (v32sim, `tools/oracle/orun.cpp`) is the one headless runner on the
official Vircon32 console logic (`ConsoleLogic` of the DesktopEmulator: CPU, memory, bus, timer and RNG cores)
with logging stand-ins for the GPU, SPU, gamepad, cartridge and memory card. Nothing is drawn or played: GPU and SPU
port writes are logged. Build it, with the stock `assemble`, in a v32sim checkout:

    make oracle COMPUTERSOFTWARE=/path/to/ComputerSoftware        # tools/oracle/bin/{v32orun,assemble,...}

`runlua` and `trap` find it through `oracle.sh` (`oracle.py` for Python): `$V32ORUN` / `$V32ASM`, then
`$V32SIM_HOME/tools/oracle/bin`, `~/share/v32sim/...`, a v32sim checkout next to this one, then `$PATH`.
The runner's log format, options and exit lines are the ones this directory's `v32run` had (it is the same code,
now shared); v32orun adds `-b` (per-frame cycles, what `v32bench` printed), console mode (`--bios B --cart C` for the
real BIOS and the real GPU/SPU, with the same `-g -s -t -B -P`), `--cfi=arm`, `--spu-state` and friends. The
documentation of every option is the header of `orun.cpp` and v32sim's `docs/TOOLS.md`.

Checked: the `testing/` unit tests give 1811/1826 (the 15 are the SPU/RNG tests named under `unittest.py`), and the
runs of the old runner and v32orun on the same carts are byte-identical (`-g -s -D -m -P -t -G`, `V32_SPU_STATE`).

## Tools

| Tool | Use |
|---|---|
| `runlua prog.lua [v32orun args]` | Compile with `bin/v32lua` (override with `$V32LUA`), assemble, run. Panic handlers are trapped; on a trap or hardware error it prints the faulting asm line, the recent trail and the call stack. Also takes `.p8`. |
| `v32orun prog.vbin [options]` | `-f N` frames, `-c N` cycle cap, `-g` GPU log (with computed screen rectangles), `-s` SPU log, `-d a,b` / `-D` dump globals (`-D` also prints `RAW name XXXXXXXX` and, for strings, `ESTR name text` with `\xHH` escapes), `-p "frame:Btn=1;..."` pad script, `-t addr,...` trap addresses, `-q` quiet. |
| | `-G` starts the cart the way the BIOS leaves the machine (RAM, registers and stack not clean). `-P prof.txt [frame]` writes a per-address cycle profile (summarize with `profile.py`), `-m addr,n` dumps memory, and a dumped table global (`-d`) shows its contents. The overrun count in `STATUS` is the number of frames that ran out of cycles before a `WAIT`. `gpu_dropped` counts draws the real GPU would have silently skipped: it has a per-frame pixel budget of 9 screens (a draw costs its whole scaled region size, capped at the screen, ×1.15 scaled, +0.25 rotated, **on screen or not**; a clear costs half a screen), and once that's spent every later draw of the frame is dropped. In the `-g` log those draws are tagged `GPU-DROPPED` (and `render.py` skips them). |
| | `-B` BP watch: reports (and traps at) the first `RET` whose `BP` differs from its value at the matching `CALL` — a routine that leaves the caller's frame pointer wrong. `V32_TRAIL=N` makes a trap print the last N (up to 4096) instruction addresses instead of 48. |
| `-b` | | Per-frame cycle counts, `FC <frame> <cycles> <overrun 0/1>` (what `v32bench` printed; `scripts/testing_harness/bench_v32.py` reads it). |
| `padrand.py SEED FRAMES` | Random pad script for long soak runs: `runlua game.lua -f 3000 -q -p "$(padrand.py 1 3000)"`. Celeste's register-allocator bug only showed up this way. |
| `render.py prog.run FRAME out.png tex0.vtex [tex1.vtex ...]` | Rebuild one frame as a PNG from a `-g` log (textures in cartridge order). Approximate: no rotation, BIOS font drawn as boxes. Only frames that drew something have content; the screen otherwise keeps the last image. |
| `spu_render.py prog.run prog.xml out.wav [first last]` | Rebuild the audio from a `-s` log as a 44.1 kHz WAV, mixing like the SPU (nearest sample, speed, loop points, volumes). For listening, and for checking that sounds start and join where they should. Needs numpy. |
| `profile.py prog.vbin.debug prof.txt [N]` | Cycles per routine from a `-P` profile. |
| `trap prog LABEL` | Run until an asm label is reached; print trail and call stack. |
| `where.py prog.vbin.debug prog.asm ADDR...` | Map addresses to asm lines. |
| `circles.py [tic80\|pico8]` | Pixel-checks TIC-80 `circ`/`circb` and PICO-8 `circfill`/`circ` (radius 0-45 and some large ones: the shape-atlas and the octant-run paths) against the consoles' own rasterizers; prints the GPU draws per circle. |
| `V32_SPU_STATE=1` (or `--spu-state`) | Give the SPU stand-in a state per channel: `SPU_ChannelState` and `SPU_ChannelAssignedSound` read back what the *selected* channel was given (`PlaySelectedChannel` → Playing, Pause, Stop, and the `*AllChannels` commands). Sounds never run out, so a played channel stays Playing until stopped. Off by default (the port is then a plain latch). For code that reads the SPU back, e.g. PICO-8 `stat(46..49)` (`tests/audit/pico8/stat_audio.p8`). |
| `V32_NO_MEMCARD=1` | Run with no memory card connected (`MEM_Connected` reads 0; card memory faults, as on the console). |
| `V32_FIXED_TIME=1` | Start the clock at a fixed date and time. Carts seed their RNG from the clock (`math.random`, PICO-8 `rnd`), so this makes runs repeatable: compare two builds' `-g`/`-s` logs for the same pad script. For a cart that overruns its frames, compare with no pad script (input is frame-indexed, so a timing change moves it). |
| `V32_CFI=arm` / `V32_CFI_LOG=1` | The emulator's float→int conversion of NaN or out-of-range values is host-dependent (0x80000000 on x86-64; 0 or saturated on ARM64). Pick the ARM behaviour, or log every such conversion. |
| `difftest.py test.lua` | Compare `R_*` globals against reference Lua 5.4 (`$LUA54`). |
| `unittest.py [-v] testing/*/NN_*.lua` | Run the `testing/` unit tests headless, with `run_tests.sh`'s contract (scrape `number_`/`string_`/`boolean_`/`hex_` globals, compare with the `=== EXPECTED OUTPUT ===` block, v32sim's `%.4f` / `"\xHH"` formats). Compares by name, so one missing value doesn't cascade. Tests that read the SPU or RNG (`v32stdapi/09-11`, `math/07`) can't pass here: the SPU is a logging stand-in, and the RNG is the official core's, which returns the seed on the first read after `srand()` (the expected values came from v32sim). |
| `lua2tic.py game.lua game.tic [--strip-hints]` | Pack a TIC-80 `.lua` project into a binary `.tic` the way TIC-80 saves one (bank 0), to check the compiler's `.tic` reader: both should compile to the same program. |
