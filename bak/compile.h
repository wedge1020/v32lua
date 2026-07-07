#ifndef _COMPILE_H
#define _COMPILE_H

#include "symtable.h"

#define  LUA_VAL_NIL    0
#define  LUA_VAL_FALSE  0
#define  LUA_VAL_TRUE   1

void  compile_node (ASTNode *, SymbolTable *, int32_t *);

#endif
