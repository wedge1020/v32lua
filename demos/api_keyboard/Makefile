# --- Configuration ---
DEMO          = apidemo_keyboard
LUA_COMPILER  = ../../bin/v32lua
ASSEMBLER     = assemble
TEXTURE_TOOL  = png2vircon
SOUND_TOOL    = wav2vircon
PACKER        = packrom

# This variable is empty by default, but is set to -g during a debug build
DEBUG_FLAGS   =
ASM_DEBUG_FLAGS =

# --- Phony Targets ---
.PHONY: all asm vbin v32 debug clean

# Default target: Performs all steps in order
all: prep asm vbin v32

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
	$(LUA_COMPILER) $(DEBUG_FLAGS) -o obj/$(DEMO).asm $(DEMO).lua
	mv obj/$(DEMO).xml .

