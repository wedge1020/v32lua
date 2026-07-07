# --- Toolchain ---
CC = gcc
LEX = flex
YACC = bison

# --- Flags ---
# -Wall -Wextra: Enable helpful compiler warnings
# -g: Include debug symbols (helpful if it crashes)
CFLAGS = -Wall -Wextra -g

# --- Output Executable ---
TARGET = v32lua

# --- Object Files ---
# These are the compiled binary chunks that get linked together at the end.
OBJS = parser.tab.o lex.yy.o main.o context.o generator.o

# --- Build Rules ---

# Default rule executed when you just type 'make'
all: $(TARGET)

# Final linking step: Combine all object files into the executable
$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

# Bison step: Generate the parser C file and the token header file
# We use -d to ensure parser.tab.h is created for the lexer to include
parser.tab.c parser.tab.h: parser.y
	$(YACC) -d parser.y

# Flex step: Generate the lexer C file
# This explicitly depends on parser.tab.h so Bison runs first
lex.yy.c: lexer.l parser.tab.h
	$(LEX) lexer.l

# Generic compilation step: Compile any .c file into a .o file
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# --- Cleanup ---
# Run 'make clean' to wipe out all generated files and start fresh
clean:
	rm -f $(TARGET) $(OBJS) parser.tab.c parser.tab.h lex.yy.c

# Tell Make that 'all' and 'clean' are commands, not actual files
.PHONY: all clean
