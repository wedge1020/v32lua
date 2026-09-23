# V32 Breakout - milestone 3
#
# By default this expects v32lua and the Vircon32 tools on PATH.
# Override commands from the command line when needed, for example:
#   make V32LUA=../v32lua/bin/v32lua

GAME         := breakout
V32LUA       ?= v32lua
ASSEMBLER    ?= assemble
PACKER       ?= packrom
TEXTURE_TOOL ?= png2vircon

DEBUG_FLAGS :=
ASM_DEBUG_FLAGS :=

SOURCES := $(GAME).lua \
           src/constants.lua \
           src/state.lua \
           src/graphics.lua \
           src/blocks.lua \
           src/gameplay.lua \
           src/screens.lua \
           levels/level1.csv

TEXTURES := assets/sprites.vtex

.PHONY: all asm vbin vtex v32 debug clean

all: v32

debug: DEBUG_FLAGS := -g
debug: ASM_DEBUG_FLAGS := -g program
debug: clean v32

asm: obj/$(GAME).asm

obj/$(GAME).asm: $(SOURCES) assets/sprites.png
	@mkdir -p obj bin
	$(V32LUA) $(DEBUG_FLAGS) -o obj/$(GAME).asm $(GAME).lua
	@# v32lua emits the cartridge XML next to the ASM output.
	@# Move it to the project root, matching the official demos.
	mv obj/$(GAME).xml .

vbin: obj/$(GAME).vbin

obj/$(GAME).vbin: obj/$(GAME).asm
	$(ASSEMBLER) $(ASM_DEBUG_FLAGS) -o obj/$(GAME).vbin obj/$(GAME).asm

vtex: $(TEXTURES)

assets/sprites.vtex: assets/sprites.png
	$(TEXTURE_TOOL) assets/sprites.png -o assets/sprites.vtex

v32: bin/$(GAME).v32

bin/$(GAME).v32: obj/$(GAME).vbin $(TEXTURES)
	$(PACKER) $(GAME).xml -o bin/$(GAME).v32

clean:
	rm -f bin/*.v32 obj/* assets/*.vtex *.xml
