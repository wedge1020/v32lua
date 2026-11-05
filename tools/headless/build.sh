#!/bin/bash
# build.sh /path/to/ComputerSoftware
# Builds the headless runner (v32run) and the official Vircon32 assembler
# from a checkout of https://github.com/vircon32/ComputerSoftware into
# this directory. Needs a C++17 compiler; SDL is NOT needed (a tiny shim
# stands in for the three SDL calls the assembler makes).
set -e
CS=${1:?usage: build.sh /path/to/ComputerSoftware}
HERE=$(cd "$(dirname "$0")" && pwd)
# The CPU, memory, buses, timer, RNG and null controller are the DesktopEmulator's own ConsoleLogic
# (the SimplifiedEmulator of older ComputerSoftware no longer exists); GPU, SPU, gamepad, cartridge and
# memory card are logging stand-ins in v32run.cpp.
CL=$CS/DesktopEmulator/ConsoleLogic
[ -d "$CL" ] || { echo "build.sh: $CL not found (is $CS a ComputerSoftware checkout?)" >&2; exit 1; }
# CFI on NaN / out-of-range floats is undefined in C++ and differs by host:
# x86-64 gives 0x80000000, ARM64 gives 0 for NaN and saturates otherwise.
# The runner's copy makes it selectable (V32_CFI=x86|arm, default x86) and
# can report every such conversion (V32_CFI_LOG=1).
mkdir -p "$HERE/.gen"
python3 - "$CL/V32CPUProcessors.cpp" "$HERE/.gen/V32CPUProcessors.cpp" <<'PY'
import sys
s = open(sys.argv[1]).read()
old = "        Register->AsInteger = (int32_t)Register->AsFloat;\n    }"
assert s.count(old) == 1, "ProcessCFI not found: ConsoleLogic changed"
new = """        Register->AsInteger = ::v32run_cfi(Register->AsFloat, CPU.InstructionPointer.AsInteger);
    }"""
s = s.replace(old, new)
s = "#include <cstdint>\nextern int32_t v32run_cfi(float f, int32_t ip);\n" + s
open(sys.argv[2], "w").write(s)
PY
g++ -std=c++17 -O2 -w -I"$CL" -I"$CS/DesktopEmulator" -I"$CS" -I"$HERE/.gen" \
    "$HERE/v32run.cpp" "$CL/V32CPU.cpp" "$HERE/.gen/V32CPUProcessors.cpp" "$CL/V32Memory.cpp" \
    "$CL/V32Buses.cpp" "$CL/V32Timer.cpp" "$CL/V32RNG.cpp" "$CL/V32NullController.cpp" \
    "$CL/ExternalInterfaces.cpp" \
    -o "$HERE/v32run"
ASM=$CS/DevelopmentTools/Assembler
INF=$CS/DevelopmentTools/DevToolsInfrastructure
g++ -std=c++17 -O2 -w -I"$HERE/sdlshim" -I"$ASM" -I"$INF" \
    "$ASM"/*.cpp "$INF"/*.cpp \
    -o "$HERE/Assembler"
echo "built $HERE/v32run and $HERE/Assembler"
