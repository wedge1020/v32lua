# --- Toolchain ---
# You can freely change this to: CC = clang
CC = gcc
LEX = flex
YACC = bison

# --- Flags ---
CFLAGS = -Wall -Wextra -g -I ../inc -DYYDEBUG=1
CLIBS = -lm

# --- Output Executable ---
TARGET = ../bin/v32lua

# --- Object Files ---

# Core sources
CORE_SRCS = parser.tab.o lex.yy.o main.o context.o ffi.o optimize.o generator.o ast.o emit.o internals.o register.o runtime_embed.o

# generate cases - automatically include all .c files in generate/
NODE_DIR = node
NODE_SRCS := $(wildcard $(NODE_DIR)/*.c)
NODE_OBJS := $(NODE_SRCS:$(NODE_DIR)/%.c=$(NODE_DIR)/%.o)

# intrinsics - automatically include all .c files in intrinsics
INTRINSICS_DIR = intrinsics
INTRINSICS_SRCS := $(wildcard $(INTRINSICS_DIR)/*.c)
INTRINSICS_OBJS := $(INTRINSICS_SRCS:$(INTRINSICS_DIR)/%.c=$(INTRINSICS_DIR)/%.o)

# All sources
SRCS = $(CORE_SRCS) $(NODE_SRCS) $(INTRINSICS_SRCS)
OBJS = $(SRCS:.c=.o)

# --- Build Rules ---
all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(CLIBS)

parser.tab.c parser.tab.h: parser.y
	$(YACC) -d parser.y -t

lex.yy.c: lexer.l parser.tab.h
	$(LEX) lexer.l

# Rule for standard C files
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Rule for Assembly files (instructs assembler to disable executable stack requirement)
%.o: %.S
	$(CC) $(CFLAGS) -Wa,--noexecstack -c $< -o $@

context:
	@cp -v runtime.s runtime.s.txt
	@cp -v Makefile  Makefile.txt
	@cp -v lexer.l   lexer.l.txt
	@cp -v parser.y  parser.y.txt

# --- Monolithic Source Generation Rule ---
monofile:
	@rm -f ../monolithic_source.c
	@echo "/* ========================================================================== */" >> ../monolithic_source.c
	@echo "/*                   MONOLITHIC SOURCE                                        */" >> ../monolithic_source.c
	@echo "/* ========================================================================== */" >> ../monolithic_source.c
	@echo "" >> ../monolithic_source.c
	@for file in *.c; do \
		if [ -f "$$file" ]; then \
			echo "/* -------------------------------------------------------------------------- */" >> ../monolithic_source.c; \
			echo "/* SOURCE FILE: $$file */" >> ../monolithic_source.c; \
			echo "/* -------------------------------------------------------------------------- */" >> ../monolithic_source.c; \
			cat "$$file" >> ../monolithic_source.c; \
			echo "" >> ../monolithic_source.c; \
			echo "/* -------------------------------------------------------------------------- */" >> ../monolithic_source.c; \
			echo "" >> ../monolithic_source.c; \
		fi; \
	done
	@echo "Successfully generated consolidated file: ../monolithic_source.c"

clean:
	rm -f $(TARGET) $(OBJS) parser.tab.c parser.tab.h lex.yy.c ../monolithic_source.c *.txt

.PHONY: all clean monorule
