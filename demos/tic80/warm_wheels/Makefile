# --- Configuration ---
DEMO          = warm_wheels
COMPILER      = ../../../bin/v32lua --rate 11025
OPTIMIZER     = v32opt -O3 -v
ASSEMBLER     = assemble
TEXTURE_TOOL  = png2vircon
PACKER        = packrom

# Is the optimizer installed? Looks up the first word of OPTIMIZER (v32opt)
# in PATH once, when make starts. Non-empty = found: the *Opt variants
# (Opt.asm, Opt.xml, Opt.vbin, Opt.v32) are built alongside the regular
# ones. Empty = not found: the optimizer is never invoked and only the
# regular build runs. Force it off with `make HAVE_OPTIMIZER=`.
#
# The optimized steps are soft failures (the leading `-`): if v32opt, the
# assembler or the packer fails on the Opt variant, make reports it and
# carries on -- the regular, unoptimized cart is always built.
HAVE_OPTIMIZER := $(shell command -v $(firstword $(OPTIMIZER)) 2>/dev/null)

# This variable is empty by default, but is set to -g during a debug build
DEBUG_FLAGS   =
ASM_DEBUG_FLAGS =

# --- Phony Targets ---
.PHONY: all prep asm vbin v32 debug clean

# Default target: Performs all steps in order
all: prep asm vbin v32

# Debug target: Sets the debug flags and builds all targets
debug: DEBUG_FLAGS = -g
debug: ASM_DEBUG_FLAGS = -g program
debug: all

# --- Build Rules ---
prep:
	@mkdir -p bin obj
ifeq ($(HAVE_OPTIMIZER),)
	@echo "note: $(firstword $(OPTIMIZER)) not found in PATH -- skipping the optimized (Opt) build"
endif

# Compile Lua to Assembly
asm: obj/$(DEMO).asm

obj/$(DEMO).asm: prep $(DEMO).lua
	$(COMPILER)   $(DEBUG_FLAGS) -o obj/$(DEMO).asm    $(DEMO).lua
ifneq ($(HAVE_OPTIMIZER),)
	-$(OPTIMIZER) $(DEBUG_FLAGS) -o obj/$(DEMO)Opt.asm obj/$(DEMO).asm
endif
	mv obj/$(DEMO).xml .
ifneq ($(HAVE_OPTIMIZER),)
	sed 's/\.vbin/Opt.vbin/g' $(DEMO).xml > $(DEMO)Opt.xml
endif

# Assemble Assembly to Binary
vbin: obj/$(DEMO).vbin

obj/$(DEMO).vbin: prep obj/$(DEMO).asm
	$(ASSEMBLER) $(ASM_DEBUG_FLAGS) -o obj/$(DEMO).vbin    obj/$(DEMO).asm
ifneq ($(HAVE_OPTIMIZER),)
	-$(ASSEMBLER) $(ASM_DEBUG_FLAGS) -o obj/$(DEMO)Opt.vbin obj/$(DEMO)Opt.asm
endif

# Process PNG sprite sheet to Vircon texture
vtex: textures/$(DEMO)_sprites.vtex

textures/$(DEMO)_sprites.vtex: textures/$(DEMO)_sprites.png
	$(TEXTURE_TOOL) textures/$(DEMO)_sprites.png -o textures/$(DEMO)_sprites.vtex

# Pack ROM cartridge (Depends on the binary to ensure it is built first)
v32: bin/$(DEMO).v32

bin/$(DEMO).v32: obj/$(DEMO).vbin
	$(PACKER) $(DEMO).xml    -o bin/$(DEMO).v32
ifneq ($(HAVE_OPTIMIZER),)
	-$(PACKER) $(DEMO)Opt.xml -o bin/$(DEMO)Opt.v32
endif

context:
	split -a 1 -b 45K -d obj/$(DEMO).asm obj/$(DEMO)_part
	@for file in obj/$(DEMO)_part?; do \
		mv "$$file" "$$file.asm.txt"; \
	done

# --- Clean Up ---
clean:
	rm -f bin/*.v32 obj/* textures/*.vtex *.xml
