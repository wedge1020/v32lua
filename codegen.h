#ifndef CODEGEN_H
#define CODEGEN_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// AST Node Types
typedef enum {
    NODE_WHILE, NODE_BREAK, NODE_IF, NODE_FUNCTION_DEF, 
    NODE_FUNCTION_CALL, NODE_RETURN, NODE_MULTIPLE_ASSIGNMENT,
    NODE_RELATIONAL, NODE_AND, NODE_OR, NODE_STRING, 
    NODE_CONCAT, NODE_TABLE_CONSTRUCTOR, NODE_TABLE_SET, NODE_TABLE_GET,
    NODE_IDENTIFIER, NODE_NUMBER
} NodeType;

// Operator Types
typedef enum {
    OP_EQ, OP_NEQ, OP_LT, OP_GT, OP_LE, OP_GE
} OpType;

// Forward declaration of AST Node
typedef struct ASTNode ASTNode;

// Variable Symbol Definition
typedef struct Symbol {
    char* name;
    int is_global;
    int stack_offset;
    struct Symbol* next;
} Symbol;

// Dynamic Scope Stack via Linked List
typedef struct Scope {
    Symbol* head;
    struct Scope* parent;
} Scope;

// Global Compiler Context
void generate_asm(ASTNode* node);
void emit_runtime_library(void);

#endif
