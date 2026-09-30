# --- Base Project Makefile ---
TARGET = v32lua
ARCH = $(shell uname -m)

# The compiler version: inc/v32lua.h's VERSION is the single source.
# `make version` shows it and stamps it into the other files that print it
# (the man page header and doc/DEBUGGING.md's footer); `v32lua --version`
# reads it from the header directly.
# Portable between GNU and BSD/macOS tools: no `sed -i` (BSD sed takes
# the script as the backup suffix), no \t in brackets, no `date +%-d`.
VERSION := $(shell sed -n 's/^\#define[[:space:]]*VERSION[[:space:]]*"\(.*\)".*/\1/p' inc/v32lua.h)
MONTH   := $(shell LC_ALL=C date +"%B %Y")
TODAY   := $(shell LC_ALL=C date +"%B %d, %Y" | sed 's/ 0\([0-9]\),/ \1,/')

.PHONY: all clean install tests version

# Default target: build the main compiler executable inside src/
all:
	$(MAKE) -C src

# Clean both the build files in src/ and the generated assembly in testing/
clean:
	rm -f err.txt put/* *.zip
	$(MAKE) -C src clean
	$(MAKE) -C testing clean
	$(MAKE) -C demos clean

install: bin/$(TARGET)
	@if [ -d ~/bin/bin.$(ARCH) ]; then \
		echo "Installing $(TARGET) to ~/bin/bin.$(ARCH)/"; \
		install -m 755 bin/$(TARGET) ~/bin/bin.$(ARCH)/$(TARGET); \
	elif [ -d ~/bin ]; then \
		echo "Installing $(TARGET) to ~/bin/"; \
		install -m 755 bin/$(TARGET) ~/bin/$(TARGET); \
	else \
		echo "Skipping: neither ~/bin/bin.$(ARCH) nor ~/bin exist"; \
	fi

sysinstall: bin/$(TARGET)
	@if [ -d /usr/local/bin ]; then \
		echo "Installing $(TARGET) to /usr/local/bin/"; \
		install -m 755 bin/$(TARGET) /usr/local/bin/$(TARGET); \
	else \
		echo "Skipping: /usr/local/bin does not exist"; \
	fi

# Show the version (from inc/v32lua.h) and stamp it into the man page and
# doc/DEBUGGING.md. Run after changing VERSION, before a release.
version:
	@echo "v32lua $(VERSION)"
	@sed 's/^\.TH V32LUA 1 "[^"]*" "v32lua [^"]*"/.TH V32LUA 1 "$(MONTH)" "v32lua $(VERSION)"/' man/v32lua.1 > man/v32lua.1.tmp && mv man/v32lua.1.tmp man/v32lua.1
	@sed 's/Last updated: [^|]*| Compiler: [^*]*\*/Last updated: $(TODAY) | Compiler: $(VERSION)*/' doc/DEBUGGING.md > doc/DEBUGGING.md.tmp && mv doc/DEBUGGING.md.tmp doc/DEBUGGING.md
	@grep -H "^\.TH" man/v32lua.1
	@grep -H "Compiler: " doc/DEBUGGING.md

# Run the test compilations. 
# We explicitly depend on the compiler binary ('src/compiler') being built first!
tests: bin/$(TARGET)
	@$(MAKE) -C testing tests

# Checkmassembler outputs
# We explicitly depend on the compiler binary ('src/compiler') being built first!
asmcheck: bin/$(TARGET)
	$(MAKE) -C testing vbin

v32check: bin/$(TARGET)
	$(MAKE) -C testing v32

demos: bin/$(TARGET)
	$(MAKE) -C demos

monofiles:
	@rm -f put/*
	scripts/monolithic_code.sh
	@cp src/lexer.l put/lexer.l.txt
	@cp src/parser.y put/parser.y.txt
	#$(MAKE) -C testing monofiles

context:
	$(MAKE) -C src context

put: context
	@rm -f put/*
	#@cp src/parser.output put/parser.output.txt
	@cp inc/*.h src/*.c src/*.txt src/runtime/*.txt README.md doc/*.md put/
	@for file in src/intrinsics/*.c; do \
		cp "$$file" "put/intrinsics_$$(basename "$$file")"; \
	done
	@for file in src/node/*.c; do \
		cp "$$file" "put/node_$$(basename "$$file")"; \
	done

archive: clean
	zip -r v32lua-project.zip demos doc inc lib Makefile man README.* scripts src tests v32 testing tools
