#!/bin/bash
# build.sh /path/to/ComputerSoftware
# Builds the headless runner (v32run) and the official Vircon32 assembler
# from a checkout of https://github.com/vircon32/ComputerSoftware into
# this directory. Needs a C++17 compiler; SDL is NOT needed (a tiny shim
# stands in for the three SDL calls the assembler makes).
set -e
CS=${1:?usage: build.sh /path/to/ComputerSoftware}
HERE=$(cd "$(dirname "$0")" && pwd)
EMU=$CS/SimplifiedEmulator/Emulator
# CFI on NaN / out-of-range floats is undefined in C++ and differs by host:
# x86-64 gives 0x80000000, ARM64 gives 0 for NaN and saturates otherwise.
# The runner's copy makes it selectable (V32_CFI=x86|arm, default x86) and
# can report every such conversion (V32_CFI_LOG=1).
mkdir -p "$HERE/.gen"
python3 - "$EMU/VirconCPUProcessors.cpp" "$HERE/.gen/VirconCPUProcessors.cpp" <<'PY'
import sys
s = open(sys.argv[1]).read()
old = "    Register->AsInteger = (int32_t)Register->AsFloat;\n}"
assert s.count(old) == 1
new = """    extern int32_t v32run_cfi(float f, int32_t ip);
    Register->AsInteger = v32run_cfi(Register->AsFloat, CPU.InstructionPointer.AsInteger);
}"""
s = s.replace(old, new)
s = s.replace('#include "VirconCPU.hpp"', '#include "VirconCPU.hpp"', 1)
open(sys.argv[2], "w").write(s)
PY
g++ -std=c++17 -O2 -w -I"$EMU" -I"$CS/SimplifiedEmulator" -I"$CS" \
    "$HERE/v32run.cpp" "$EMU/VirconCPU.cpp" "$HERE/.gen/VirconCPUProcessors.cpp" "$EMU/VirconMemory.cpp" \
    "$EMU/VirconBuses.cpp" "$EMU/VirconTimer.cpp" "$EMU/VirconRNG.cpp" \
    "$EMU/VirconNullController.cpp" \
    -o "$HERE/v32run"
ASM=$CS/DevelopmentTools/Assembler
INF=$CS/DevelopmentTools/DevToolsInfrastructure
g++ -std=c++17 -O2 -w -I"$HERE/sdlshim" -I"$ASM" -I"$INF" \
    "$ASM"/*.cpp "$INF"/*.cpp \
    -o "$HERE/Assembler"
echo "built $HERE/v32run and $HERE/Assembler"
