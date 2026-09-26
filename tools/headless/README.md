# Headless test harness

Runs a compiled cart on the **official Vircon32 CPU, memory, bus, timer
and RNG cores** (from the SimplifiedEmulator in
[vircon32/ComputerSoftware](https://github.com/vircon32/ComputerSoftware)),
with logging stand-ins for the GPU, SPU, gamepad, cartridge and memory
card. Nothing is drawn or played: GPU and SPU port writes are logged
instead. So program logic, the runtime and the calling convention are
checked on the real CPU, but rendering and audio are not.

## Build

    ./build.sh /path/to/ComputerSoftware

builds `v32run` and the official `Assembler` (SDL isn't needed; `sdlshim/`
stands in for it).

## Tools

| Tool | Use |
|---|---|
| `runlua prog.lua [v32run args]` | Compile with `bin/v32lua` (override with `$V32LUA`), assemble, run. Panic handlers are trapped; on a trap or hardware error it prints the faulting asm line, the recent trail and the call stack. Also takes `.p8`. |
| `v32run prog.vbin [options]` | `-f N` frames, `-c N` cycle cap, `-g` GPU log (with computed screen rectangles), `-s` SPU log, `-d a,b` / `-D` dump globals, `-p "frame:Btn=1;..."` pad script, `-t addr,...` trap addresses, `-q` quiet. |
| | `-G` starts the cart the way the BIOS leaves the machine (RAM, registers and stack not clean). `-P prof.txt [frame]` writes a per-address cycle profile (summarize with `profile.py`), `-m addr,n` dumps memory, and a dumped table global (`-d`) shows its contents. The overrun count in `STATUS` is the number of frames that ran out of cycles before a `WAIT`. |
| `padrand.py SEED FRAMES` | Random pad script for long soak runs: `runlua game.lua -f 3000 -q -p "$(padrand.py 1 3000)"`. Celeste's register-allocator bug only showed up this way. |
| `render.py prog.run FRAME out.png tex0.vtex [tex1.vtex ...]` | Rebuild one frame as a PNG from a `-g` log (textures in cartridge order). Approximate: no rotation, BIOS font drawn as boxes. Only frames that drew something have content; the screen otherwise keeps the last image. |
| `profile.py prog.vbin.debug prof.txt [N]` | Cycles per routine from a `-P` profile. |
| `trap prog LABEL` | Run until an asm label is reached; print trail and call stack. |
| `where.py prog.vbin.debug prog.asm ADDR...` | Map addresses to asm lines. |
| `V32_CFI=arm` / `V32_CFI_LOG=1` | The emulator's float→int conversion of NaN or out-of-range values is host-dependent (0x80000000 on x86-64; 0 or saturated on ARM64). Pick the ARM behaviour, or log every such conversion. |
| `difftest.py test.lua` | Compare `R_*` globals against reference Lua 5.4 (`$LUA54`). |
