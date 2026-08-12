# --- Testing Directory Makefile ---

# Path to the compiler binary relative to this testing directory
COMPILER = ../../bin/v32lua

# Automatically find all .lua files in this directory
LUA_SRCS = $(wildcard *.lua)

# Translate the list of .lua source files into target .asm files
ASM_OUTS = $(LUA_SRCS:.lua=.asm)

# Translate the list of .lua source files into target .xml files
XML_OUTS = $(LUA_SRCS:.lua=.xml)

.PHONY: all clean asmcheck

# Default target builds all the .asm files
all: $(ASM_OUTS)

# Pattern rule: How to convert a .lua file into a .asm file
%.asm: %.lua $(COMPILER)
	@../run_tests.sh $<

#@echo "Compiling test case: $< -> $@"
#$(COMPILER) -g $< -o $@

# Assembly verification: Attempt to assemble all .asm files without halting on errors
vbin: $(ASM_OUTS)
	@echo "--- Verifying Vircon32 Assembly ---"
	@for f in $(ASM_OUTS); do \
		out=$${f%.asm}.vbin; \
		if assemble -g program -o $$out $$f > /dev/null 2>&1; then \
			printf "[  OK  ] %-25s -> %s\n" "$$f" "$$out"; \
		else \
			printf "[ FAIL ] %-25s\n" "$$f"; \
		fi; \
	done

# CART verification: Attempt to pack all .vbin files without halting on errors (testing XML)
v32: $(XML_OUTS)
	@echo "--- Verifying Vircon32 CART packing and XML config validity ---"
	@for f in $(XML_OUTS); do \
		vbin=$${f%.xml}.vbin; \
		out=$${f%.xml}.v32; \
		if packrom $$f > /dev/null 2>&1; then \
			printf "[  OK  ] %-25s -> %s\n" "$$vbin" "$$out"; \
		else \
			printf "[ FAIL ] %-25s\n" "$$f"; \
		fi; \
	done

# Clean target drops all generated assembly and binary test files
clean:
	rm -f *.asm *.vbin *.xml *.v32 *.debug *.txt *.cmd *.out *.want* *.have*
