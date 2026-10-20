# --- Configuration ---
DEMO          = apidemo_tilemap
LUA_COMPILER  = ../../bin/v32lua
ASSEMBLER     = assemble
TEXTURE_TOOL  = png2vircon
PACKER        = packrom

# This variable is empty by default, but is set to -g during a debug build
DEBUG_FLAGS   =
ASM_DEBUG_FLAGS =

# --- Phony Targets ---
.PHONY: all asm vbin v32 debug clean

# Default target: Performs all steps in order
all: prep asm vbin vtex v32

# Debug target: Sets the debug flags and builds all targets
debug: DEBUG_FLAGS = -g
debug: ASM_DEBUG_FLAGS = -g program
debug: all

# --- Build Rules ---
prep:
	@mkdir -p bin obj

# Compile Lua to Assembly
asm: obj/$(DEMO).asm

obj/$(DEMO).asm: $(DEMO).lua
	@mkdir -p bin obj
	$(LUA_COMPILER) --no-build-scripts $(DEBUG_FLAGS) -o obj/$(DEMO).asm $(DEMO).lua

# Assemble Assembly to Binary
vbin: obj/$(DEMO).vbin

obj/$(DEMO).vbin: obj/$(DEMO).asm
	$(ASSEMBLER) $(ASM_DEBUG_FLAGS) -o obj/$(DEMO).vbin obj/$(DEMO).asm

# Process PNG sprite sheet to Vircon texture
# (the --#texture hint says assets/$(DEMO).png; the XML names $(DEMO).vtex, expected beside it in obj/)
vtex: obj/$(DEMO).vtex

obj/$(DEMO).vtex: assets/$(DEMO).png | prep
	$(TEXTURE_TOOL) assets/$(DEMO).png -o obj/$(DEMO).vtex

# Pack ROM cartridge (Depends on the binary and texture to ensure they are built first)
v32: bin/$(DEMO).v32

bin/$(DEMO).v32: obj/$(DEMO).vbin obj/$(DEMO).vtex
	$(PACKER) obj/$(DEMO).xml -o bin/$(DEMO).v32

# --- Clean Up ---
clean:
	rm -f bin/*.v32 obj/*
