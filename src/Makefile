# --- Toolchain ---
# You can freely change this to: CC = clang
CC = gcc
LEX = flex
YACC = bison

# --- Flags ---
CFLAGS = -Wall -Wextra -g -I ../inc -DYYDEBUG=1

# --- Output Executable ---
TARGET = ../bin/v32lua

# --- Object Files ---
# Add runtime_embed.o to your object list
OBJS = parser.tab.o lex.yy.o main.o context.o generator.o ast.o emit.o internals.o register.o runtime_embed.o

# --- Build Rules ---
all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

parser.tab.c parser.tab.h: parser.y
	$(YACC) -d parser.y -t

lex.yy.c: lexer.l parser.tab.h
	$(LEX) lexer.l

# Rule for standard C files
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Rule for Assembly files (handles our .incbin wrapper)
# Rule for Assembly files (instructs assembler to disable executable stack requirement)
%.o: %.S
	$(CC) $(CFLAGS) -Wa,--noexecstack -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJS) parser.tab.c parser.tab.h lex.yy.c

.PHONY: all clean
