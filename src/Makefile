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
CORE_SRCS = parser.tab.o lex.yy.o main.o context.o ffi.o optimize.o generator.o ast.o emit.o internals.o register.o tic80_assets.o vtex_generator.o vsnd_generator.o runtime_embed.o

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
	$(YACC) -v -d parser.y -t

lex.yy.c: lexer.l parser.tab.h
	$(LEX) lexer.l

# Rule for standard C files
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Rule for Assembly files (instructs assembler to disable executable stack requirement)
%.o: %.S
	$(CC) $(CFLAGS) -Wa,--noexecstack -c $< -o $@

context:
	@cp -v runtime/memory.s   runtime/memory.s.txt
	@cp -v runtime/exec.s     runtime/exec.s.txt
	@cp -v runtime/table.s    runtime/table.s.txt
	@cp -v runtime/math.s     runtime/math.s.txt
	@cp -v runtime/string.s   runtime/string.s.txt
	@cp -v runtime/print.s    runtime/print.s.txt
	@cp -v runtime/iters.s    runtime/iters.s.txt
	@cp -v runtime/pico8.s    runtime/pico8.s.txt
	@cp -v runtime/tic80.s    runtime/tic80.s.txt
	@cp -v runtime/constant.s runtime/constant.s.txt
	@cp -v Makefile           Makefile.txt
	@cp -v lexer.l            lexer.l.txt
	@cp -v parser.y           parser.y.txt
	@cp -v runtime_embed.S    runtime_embed.S.txt

clean:
	rm -f $(TARGET) $(OBJS) parser.tab.c parser.tab.h lex.yy.c ../monolithic_source.c *.txt runtime/*.txt intrinsics/*.txt node/*.txt *.output

.PHONY: all clean monorule
