# --- Base Project Makefile ---
TARGET = v32lua
ARCH = $(shell uname -m)

.PHONY: all clean install tests

# Default target: build the main compiler executable inside src/
all:
	$(MAKE) -C src

# Clean both the build files in src/ and the generated assembly in testing/
clean:
	rm -f err.txt put/*
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
		@echo "Skipping: neither ~/bin/bin.$(ARCH) nor ~/bin exist"; \
	fi

sysinstall: bin/$(TARGET)
	@if [ -d /usr/local/bin ]; then \
		echo "Installing $(TARGET) to /usr/local/bin/"; \
		install -m 755 $(TARGET) /usr/local/bin/$(TARGET); \
	else \
		@echo "Skipping: /usr/local/bin does not exist"; \
	fi

# Run the test compilations. 
# We explicitly depend on the compiler binary ('src/compiler') being built first!
tests: bin/$(TARGET)
	$(MAKE) -C testing tests

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
	$(MAKE) -C testing monofiles

context:
	$(MAKE) -C src context

put: context
	@rm -f put/*
	@cp src/parser.output put/parser.output.txt
	@cp inc/*.h src/*.c src/*.txt src/runtime/*.txt README.md doc/*.md put/
	@for file in src/intrinsics/*.c; do \
		cp "$$file" "put/intrinsics_$$(basename "$$file")"; \
	done
	@for file in src/node/*.c; do \
		cp "$$file" "put/node_$$(basename "$$file")"; \
	done
