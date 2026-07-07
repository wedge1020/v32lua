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
typedef struct astnode ASTNode;
// Place this inside codegen.h, right after the enums
struct astnode {
    NodeType type;
    ASTNode* next;  // For statement lists and sequential chaining
    
    union {
        // Control Flow
        struct {
            ASTNode* condition;
            ASTNode* body;
        } while_loop;

        struct {
            ASTNode* condition;
            ASTNode* if_body;
            ASTNode* else_body;
        } if_stmt;

        // Functions
        struct {
            char* name;
            ASTNode* body;
        } function_def;

        struct {
            ASTNode* expressions_head;
            int parent_func_arg_count;
        } return_stmt;

        // Assignments
        struct {
            ASTNode* targets_head;
            ASTNode* right_side_call;
        } mult_assign;

        // Binary Operations (Math, Logic, Relational, Concat)
        struct {
            int operator; // Holds OpType or character literal like '+'
            ASTNode* left;
            ASTNode* right;
        } binary;

        // Tables
        struct {
            ASTNode* table_expr;
            ASTNode* key;
            ASTNode* value;
        } table_set;

        struct {
            ASTNode* table_expr;
            ASTNode* key;
        } table_get;

        // Terminal Literals / Identifiers
        struct {
            char* value;
        } string_val;

        struct {
            char* name;
        } id;

        struct {
            double val;
        } number;
    } as;
};

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

// Add these to the bottom of codegen.h, right before #endif
void track_global_variable(const char* name);
void emit_global_variables(void);

#endif
