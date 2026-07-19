#ifndef _ENUMS_H
#define _ENUMS_H

////////////////////////////////////////////////////////////////////////////////////////
//
// NODE_type enums
//
typedef enum
{
    NODE_WHILE,
    NODE_BREAK,
    NODE_IF,
    NODE_FUNCTION_DEF,
    NODE_FUNCTION_CALL,
    NODE_FUNCTION_POINTER,
    NODE_RETURN,
    NODE_MULTIPLE_ASSIGNMENT,
    NODE_ADD,
    NODE_SUB,
    NODE_MUL,
    NODE_DIV,
	MODE_MOD,
    NODE_AND,
    NODE_OR,
    NODE_RELATIONAL,
    NODE_STRING,
    NODE_CONCAT,
    NODE_TABLE_CONSTRUCTOR,
    NODE_TABLE_SET,
    NODE_TABLE_GET,
    NODE_IDENTIFIER,
    NODE_NUMBER,
    NODE_UNARY,
    NODE_ASM,
    NODE_RAWASM,
    NODE_COMMENT_LINE,
    NODE_COMMENT_BLOCK,
    NODE_CART_HINT
} NodeType;

typedef enum
{
    OP_EQ,
    OP_NEQ,
    OP_LT,
    OP_GT,
    OP_LE,
    OP_GE,
    OP_LEN,
    OP_NOT,
    OP_UNM
} Operator;

typedef enum
{
    ERR_LEXICAL,
    ERR_SYNTAX,
    ERR_SEMANTIC,
    ERR_INTERNAL
} ErrorType;

#endif
