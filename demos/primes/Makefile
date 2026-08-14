# --- Configuration ---
TEST             = primes
COMPILER         = v32lua
OPTIMIZER        = ../../v32opt
ASSEMBLER        = assemble
TEXTURE_TOOL     = png2vircon
PACKER           = packrom

COMPILER_FLAGS   = 
OPT_FLAGS        = -O3 -t -v -fpeephole-forwarding -fpeephole-dead-stores -fpeephole-loads

# This variable is empty by default, but is set to -g during a debug build
DEBUG_FLAGS      =
ASM_DEBUG_FLAGS  =

# --- Phony Targets ---
.PHONY: all asm vbin v32 debug clean

# Default target: Performs all steps in order
all: asm opt vbin v32 report

# Debug target: Sets the debug flags and builds all targets
debug: DEBUG_FLAGS = -g
debug: ASM_DEBUG_FLAGS = -g program
debug: OPT_DEBUG_FLAGS = -d
debug: all

# --- Build Rules ---
# Compile to Assembly
asm: $(TEST).asm

$(TEST).asm: $(TEST).lua
	@echo -n "Compiling  $(TEST).lua    -> $(TEST).asm     ... "
	@$(COMPILER) $(COMPILER_FLAGS) $(DEBUG_FLAGS) -o $(TEST).asm $(TEST).lua && echo "OK" || echo "FAIL"

opt: $(TEST)Opt.asm

$(TEST)Opt.asm: $(TEST).asm
	@echo -n "Optimizing $(TEST).asm    -> $(TEST)Opt.asm  ... "
	@$(OPTIMIZER) $(TEST).asm -o $(TEST)Opt.asm $(OPT_FLAGS) $(OPT_DEBUG_FLAGS) && echo "OK" || echo "FAIL"

# Assemble Assembly to Binary
vbin: $(TEST).vbin

$(TEST).vbin: $(TEST).asm
	@echo -n "Assembling $(TEST).asm    -> $(TEST).vbin    ... "
	@$(ASSEMBLER) $(ASM_DEBUG_FLAGS) -o $(TEST).vbin    $(TEST).asm && echo "OK" || echo "FAIL"
	@echo -n "Assembling $(TEST)Opt.asm -> $(TEST)Opt.vbin ... "
	@$(ASSEMBLER) $(ASM_DEBUG_FLAGS) -o $(TEST)Opt.vbin $(TEST)Opt.asm && echo "OK" || echo "FAIL"

# Process PNG sprite sheet to Vircon texture
#vtex: textures/$(TEST)_sprites.vtex

#textures/$(TEST)_sprites.vtex: textures/$(TEST)_sprites.png
#	$(TEXTURE_TOOL) textures/$(TEST)_sprites.png -o textures/$(TEST)_sprites.vtex

# Pack ROM cartridge (Depends on the binary and texture to ensure they are built first)
v32: $(TEST).v32 $(TEST)Opt.v32

$(TEST).v32: $(TEST).vbin
	@echo -n "Packing $(TEST).vbin      -> $(TEST).v32     ... "
	@$(PACKER) $(TEST).xml -o $(TEST).v32 && echo "OK" || echo "FAIL"

$(TEST)Opt.v32: $(TEST)Opt.vbin
	@echo -n "Packing $(TEST)Opt.vbin   -> $(TEST)Opt.v32  ... "
	@$(PACKER) $(TEST)Opt.xml -o $(TEST)Opt.v32 && echo "OK" || echo "FAIL"

report: $(TEST).v32 $(TEST)Opt.v32
	@../run_test.sh $(TEST)

# --- Clean Up ---
clean:
	@rm -f *.asm *.v32 textures/*.vtex *.vbin *Opt.asm *.debug *.txt
