# --- Configuration ---
DEMO          = digdug
LUA_COMPILER  = ../../bin/v32lua
ASSEMBLER     = assemble
TEXTURE_TOOL  = png2vircon
PACKER        = packrom

# This variable is empty by default, but is set to -g during a debug build
DEBUG_FLAGS   =
ASM_DEBUG_FLAGS =

# --- Phony Targets ---
.PHONY: all asm vbin vtex v32 debug clean

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
	$(LUA_COMPILER) $(DEBUG_FLAGS) -o obj/$(DEMO).asm $(DEMO).lua
	mv obj/$(DEMO).xml .

# Assemble Assembly to Binary
vbin: obj/$(DEMO).vbin

obj/$(DEMO).vbin: obj/$(DEMO).asm
	$(ASSEMBLER) $(ASM_DEBUG_FLAGS) -o obj/$(DEMO).vbin obj/$(DEMO).asm

# Process PNG sprite sheet to Vircon texture
vtex: textures/$(DEMO)_sprites.vtex

textures/$(DEMO)_sprites.vtex: textures/$(DEMO)_sprites.png
	$(TEXTURE_TOOL) textures/$(DEMO)_sprites.png -o textures/$(DEMO)_sprites.vtex

# Pack ROM cartridge (Depends on the binary and texture to ensure they are built first)
v32: bin/$(DEMO).v32

bin/$(DEMO).v32: obj/$(DEMO).vbin textures/$(DEMO)_sprites.vtex
	$(PACKER) $(DEMO).xml -o bin/$(DEMO).v32

# --- Clean Up ---
clean:
	rm -f bin/*.v32 obj/* textures/*.vtex *.xml
