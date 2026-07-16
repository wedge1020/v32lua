# --- Base Project Makefile ---

.PHONY: all clean install tests

# Default target: build the main compiler executable inside src/
all:
	$(MAKE) -C src

# Clean both the build files in src/ and the generated assembly in testing/
clean:
	rm -f err.txt v32lua.[ch]
	$(MAKE) -C src clean
	$(MAKE) -C testing clean
	$(MAKE) -C demo clean

# Pass the install target down to the src directory
install:
	$(MAKE) -C src install

# Run the test compilations. 
# We explicitly depend on the compiler binary ('src/compiler') being built first!
tests: bin/v32lua
	$(MAKE) -C testing

# Checkmassembler outputs
# We explicitly depend on the compiler binary ('src/compiler') being built first!
asmcheck: bin/v32lua
	$(MAKE) -C testing asmcheck

demos: bin/v32lua
	$(MAKE) -C demo

monofiles:
	scripts/monolithic_code.sh
	$(MAKE) -C testing monofiles
