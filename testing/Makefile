# --- Testing Directory Makefile ---

# Path to the compiler binary relative to this testing directory
COMPILER = ../bin/v32lua

# Automatically find all .lua files in this directory
LUA_SRCS = $(wildcard *.lua)

# Translate the list of .lua source files into target .asm files
ASM_OUTS = $(LUA_SRCS:.lua=.asm)

.PHONY: all clean asmcheck

# Default target builds all the .asm files
all: $(ASM_OUTS)

# Pattern rule: How to convert a .lua file into a .asm file
%.asm: %.lua $(COMPILER)
	@echo "Compiling test case: $< -> $@"
	$(COMPILER) -g $< -o $@

# Assembly verification: Attempt to assemble all .asm files without halting on errors
asmcheck: $(ASM_OUTS)
	@echo "--- Verifying Vircon32 Assembly ---"
	@for f in $(ASM_OUTS); do \
		out=$${f%.asm}.vbin; \
		if assemble -g program -o $$out $$f > /dev/null 2>&1; then \
			printf "[  OK  ] %-25s -> %s\n" "$$f" "$$out"; \
		else \
			printf "[ FAIL ] %-25s\n" "$$f"; \
		fi; \
	done

# --- Monolithic Source Generation Rule ---
monofiles:
	@rm -f ../monofile_luatests.txt
	@echo "-- ==========================================================================" >> ../monofile_luatests.txt
	@echo "--              MONOLITHIC SOURCE: TESTS & PROBUCED ASSEMBLY                 " >> ../monofile_luatests.txt
	@echo "-- ==========================================================================" >> ../monofile_luatests.txt
	@echo "" >> ../monofile_luatests.txt
	@for file in *.lua; do \
		if [ -f "$$file" ]; then \
			echo "-- --------------------------------------------------------------------------" >> ../monofile_luatests.txt; \
			echo "-- TEST FILE: $$file" >> ../monofile_luatests.txt; \
			echo "-- --------------------------------------------------------------------------" >> ../monofile_luatests.txt; \
			cat "$$file" >> ../monofile_luatests.txt; \
			echo "" >> ../monofile_luatests.txt; \
			echo "-- --------------------------------------------------------------------------" >> ../monofile_luatests.txt; \
			echo "" >> ../monofile_luatests.txt; \
		fi; \
	done
	@echo "Successfully generated consolidated file: ../monofile_luatests.txt"
	@echo "" >> ../monofile_assembly.txt
	@for file in *.asm; do \
		if [ -f "$$file" ]; then \
			echo "-- --------------------------------------------------------------------------" >> ../monofile_assembly.txt; \
			echo "-- PRODUCED ASSEMBLY FILE: $$file" >> ../monofile_assembly.txt; \
			echo "-- --------------------------------------------------------------------------" >> ../monofile_assembly.txt; \
			cat "$$file" >> ../monofile_assembly.txt; \
			echo "" >> ../monofile_assembly.txt; \
			echo "-- --------------------------------------------------------------------------" >> ../monofile_assembly.txt; \
			echo "" >> ../monofile_assembly.txt; \
		fi; \
	done
	@echo "Successfully generated consolidated file: ../monofile_assembly.txt"

# Clean target drops all generated assembly and binary test files
clean:
	rm -f *.asm *.vbin *.xml *.v32 *.debug ../monofile_luatests.txt ../monofile_assembly.txt
