# --- Testing Directory Makefile ---

# Path to the compiler binary relative to this testing directory
# (Adjust "compiler" if your executable file is named differently!)
COMPILER = ../bin/v32lua

# Automatically find all .lua files in this directory
LUA_SRCS = $(wildcard *.lua)

# Translate the list of .lua source files into target .asm files
ASM_OUTS = $(LUA_SRCS:.lua=.asm)

.PHONY: all clean

# Default target builds all the .asm files
all: $(ASM_OUTS)

# Pattern rule: How to convert a .lua file into a .asm file
# $< represents the input (.lua file) and $@ represents the output (.asm file)
%.asm: %.lua $(COMPILER)
	@echo "Compiling test case: $< -> $@"
	$(COMPILER) $< > $@

# Clean target drops all generated assembly test files
clean:
	rm -f *.asm
