# --- Testing Directory Makefile ---

# Path to the compiler binary relative to this testing directory
COMPILER = ../../bin/v32lua -w -g

# Automatically find all .lua files in this directory
LUA_SRCS = $(wildcard *.lua)

# Translate the list of .lua source files into target .asm files
ASM_OUTS = $(LUA_SRCS:.lua=.asm)

# Translate the list of .lua source files into target .xml files
XML_OUTS = $(LUA_SRCS:.lua=.xml)

.PHONY: all clean asmcheck asm report debug

# Default target builds all the .asm files
all: $(ASM_OUTS)

# Compile each lua file in turn
asm:
	@for f in $(LUA_SRCS); do \
		echo "Compiling test case: $$f -> $${f%.lua}.asm"; \
		$(COMPILER) -g $$f -o $${f%.lua}.asm; \
	done

tests:
	@echo "==============================================================="
	@echo "v32lua iterating conditionals (loops)"
	@echo "==============================================================="
	@for f in $(LUA_SRCS); do \
		../run_tests.sh $$f; \
	done
	@echo "==============================================================="
	@echo

# Run with VERBOSE=true for each file
report:
	@echo "==============================================================="
	@echo "v32lua iterating conditionals (loops)"
	@echo "==============================================================="
	@for f in $(LUA_SRCS); do \
		VERBOSE="true" ../run_tests.sh $$f; \
	done
	@echo "==============================================================="
	@echo

# Run with DEBUG=true for each file
debug:
	@echo "==============================================================="
	@echo "v32lua iterating conditionals (loops)"
	@echo "==============================================================="
	@for f in $(LUA_SRCS); do \
		DEBUG="true" ../run_tests.sh $$f; \
	done
	@echo "==============================================================="
	@echo

# Pattern rule: How to convert a .lua file into a .asm file
%.asm: %.lua
	@echo "Compiling test case: $< -> $@"
	$(COMPILER) -g $< -o $@

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
	rm -f *.asm *.vbin *.xml *.v32 *.debug *.txt *.cmd *.out *.err *.want* *.have* *.output
