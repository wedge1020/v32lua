#ifndef _SYMTABLE_H
#define _SYMTABLE_H

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

#define  MAX_SYMBOLS 128

struct symbol
{
    int8_t  *name;
    int32_t  stack_offset;
    bool     is_local;
};
typedef struct symbol Symbol;

int  stack_offset; // Used for local variables inside Vircon32 functions

typedef struct SymbolTable SymbolTable;
struct SymbolTable
{
    Symbol       symbols[MAX_SYMBOLS];
    int32_t      symbol_count;
    SymbolTable *parent; // Points to the enclosing outer scope
};

// Creates a new inner scope pointing back to the current scope
SymbolTable *scope_enter (SymbolTable *);

// Destroys the current inner scope and returns the parent scope
SymbolTable *scope_exit (SymbolTable *);

// Define a local variable in the absolute current block scope
bool scope_define_local (SymbolTable *, const int8_t *, int32_t);

// Look up a variable by walking up the scope chain
Symbol *scope_lookup (SymbolTable *, const int8_t *);

#endif
