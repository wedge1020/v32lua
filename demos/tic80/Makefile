# Find all subdirectories containing a Makefile
# This dynamically filters out folders that do not need to be compiled
SUBDIRS := $(dir $(wildcard */Makefile))

.PHONY: all debug clean

# --- Default Target ---
# Runs a standard 'make' in each subdirectory
all:
	@for dir in $(SUBDIRS); do \
		echo "========================================"; \
		echo "Entering directory: $$dir"; \
		echo "========================================"; \
		$(MAKE) -C $$dir; \
	done

# --- Debug Target ---
# Runs 'make debug' in each subdirectory
debug:
	@for dir in $(SUBDIRS); do \
		echo "========================================"; \
		echo "Entering directory (DEBUG): $$dir"; \
		echo "========================================"; \
		$(MAKE) -C $$dir debug; \
	done

# --- Clean Target ---
# Runs 'make clean' in each subdirectory
clean:
	@for dir in $(SUBDIRS); do \
		echo "========================================"; \
		echo "Cleaning directory: $$dir"; \
		echo "========================================"; \
		$(MAKE) -C $$dir clean; \
	done
