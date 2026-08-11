# --- Testing Directory Makefile ---

# Path to the compiler binary relative to this testing directory
COMPILER = ../../bin/v32lua

# Automatically find all .lua files in this directory
LUA_SRCS = $(wildcard *.lua)

# Translate the list of .lua source files into target .asm files
ASM_OUTS = $(LUA_SRCS:.lua=.asm)

# Translate the list of .lua source files into target .xml files
XML_OUTS = $(LUA_SRCS:.lua=.xml)

.PHONY: all debug clean asmcheck vbin v32 monofiles

# Default target: compile, assemble, pack, and run all tests
all:
	@echo "=== Running all tests ==="; \
	success=0; total=0; \
	for lua_file in $(LUA_SRCS); do \
		base=$${lua_file%.lua}; \
		asm_file=$${base}.asm; \
		vbin_file=$${base}.vbin; \
		v32_file=$${base}.v32; \
		xml_file=$${base}.xml; \
		step1=0; step2=0; step3_xml=0; step3=0; step4=0; \
		$(COMPILER) $$lua_file -o $$asm_file > /dev/null 2>&1 && step1=1; \
		[ $$step1 -eq 1 ] && assemble program -o $$vbin_file $$asm_file > /dev/null 2>&1 && step2=1; \
		[ $$step2 -eq 1 ] && printf '<cart><program>%s.vbin</program></cart>\n' "$$base" > $$xml_file && step3_xml=1; \
		[ $$step3_xml -eq 1 ] && packrom $$xml_file > /dev/null 2>&1 && step3=1; \
		[ $$step3 -eq 1 ] && v32sim $$v32_file > /dev/null 2>&1 && step4=1; \
		if [ $$step1 -eq 1 ] && [ $$step2 -eq 1 ] && [ $$step3 -eq 1 ] && [ $$step4 -eq 1 ]; then \
			echo "[  OK  ] $$lua_file"; \
			success=$$((success + 5)); \
		else \
			echo "[ FAIL ] $$lua_file"; \
		fi; \
		total=$$((total + 5)); \
	done; \
	echo ""; \
	echo "Results: $$success / $$total"

# Debug target: same pipeline with debug flags
debug:
	@echo "=== Running all tests (debug mode) ==="; \
	success=0; total=0; \
	for lua_file in $(LUA_SRCS); do \
		base=$${lua_file%.lua}; \
		asm_file=$${base}.asm; \
		vbin_file=$${base}.vbin; \
		v32_file=$${base}.v32; \
		xml_file=$${base}.xml; \
		step1=0; step2=0; step3_xml=0; step3=0; step4=0; \
		$(COMPILER) -g $$lua_file -o $$asm_file > /dev/null 2>&1 && step1=1; \
		[ $$step1 -eq 1 ] && assemble -g program -o $$vbin_file $$asm_file > /dev/null 2>&1 && step2=1; \
		[ $$step2 -eq 1 ] && printf '<cart><program>%s.vbin</program></cart>\n' "$$base" > $$xml_file && step3_xml=1; \
		[ $$step3_xml -eq 1 ] && packrom $$xml_file > /dev/null 2>&1 && step3=1; \
		[ $$step3 -eq 1 ] && v32sim $$v32_file > /dev/null 2>&1 && step4=1; \
		if [ $$step1 -eq 1 ] && [ $$step2 -eq 1 ] && [ $$step3 -eq 1 ] && [ $$step4 -eq 1 ]; then \
			echo "[  OK  ] $$lua_file"; \
			success=$$((success + 5)); \
		else \
			echo "[ FAIL ] $$lua_file"; \
		fi; \
		total=$$((total + 5)); \
	done; \
	echo ""; \
	echo "Results: $$success / $$total"

# Pattern rule: How to convert a .lua file into a .asm file (no debug by default)
%.asm: %.lua $(COMPILER)
	@echo "Compiling test case: $< -> $@"
	$(COMPILER) $< -o $@

# Assembly verification: Attempt to assemble all .asm files without halting on errors
vbin: $(ASM_OUTS)
	@echo "--- Verifying Vircon32 Assembly ---"
	@for f in $(ASM_OUTS); do \
		out=$${f%.asm}.vbin; \
		if assemble program -o $$out $$f > /dev/null 2>&1; then \
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

# --- Monolithic Source Generation Rule ---
monofiles:
	@rm -f ../put/monofile_luatests.txt
	@echo "-- ==========================================================================" >> ../put/monofile_luatests.txt
	@echo "--              MONOLITHIC SOURCE: TESTS & PROBUCED ASSEMBLY                 " >> ../put/monofile_luatests.txt
	@echo "-- ==========================================================================" >> ../put/monofile_luatests.txt
	@echo "" >> ../put/monofile_luatests.txt
	@for file in *.lua; do \
		if [ -f "$$file" ]; then \
			echo "-- --------------------------------------------------------------------------" >> ../put/monofile_luatests.txt; \
			echo "-- TEST FILE: $$file" >> ../put/monofile_luatests.txt; \
			echo "-- --------------------------------------------------------------------------" >> ../put/monofile_luatests.txt; \
			cat "$$file" >> ../put/monofile_luatests.txt; \
			echo "" >> ../put/monofile_luatests.txt; \
			echo "-- --------------------------------------------------------------------------" >> ../put/monofile_luatests.txt; \
			echo "" >> ../put/monofile_luatests.txt; \
		fi; \
	done
	@echo "Successfully generated consolidated file: ../put/monofile_luatests.txt"
	@echo "" >> ../put/monofile_assembly.txt
	@for file in *.asm; do \
		if [ -f "$$file" ]; then \
			echo "-- --------------------------------------------------------------------------" >> ../put/monofile_assembly.txt; \
			echo "-- PRODUCED ASSEMBLY FILE: $$file" >> ../put/monofile_assembly.txt; \
			echo "-- --------------------------------------------------------------------------" >> ../put/monofile_assembly.txt; \
			cat "$$file" >> ../put/monofile_assembly.txt; \
			echo "" >> ../put/monofile_assembly.txt; \
			echo "-- --------------------------------------------------------------------------" >> ../put/monofile_assembly.txt; \
			echo "" >> ../put/monofile_assembly.txt; \
		fi; \
	done
	@echo "Successfully generated consolidated file: ../put/monofile_assembly.txt"

# Clean target drops all generated assembly and binary test files
clean:
	rm -f *.asm *.vbin *.xml *.v32 *.debug *.txt
