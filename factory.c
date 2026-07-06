#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "ast.h"

//////////////////////////////////////////////////////////////////////////////
//
// Helper to clear and allocate base node memory
//
static ASTNode *mknode (NodeType  type)
{
    ASTNode *node     = (ASTNode *) malloc (sizeof (ASTNode));
    if (node         != NULL)
    {
        node -> type  = type;
    }
    return (node);
}

ASTNode *mknode_num (float  value)
{
    ASTNode *node              = mknode (NODE_NUMBER);
    node -> data.number.value  = value;
    return (node);
}

ASTNode *mknode_ident (const int8_t *name)
{
    ASTNode *node                 = mknode (NODE_IDENTIFIER);
    node -> data.identifier.name  = strdup (name); // Duplicate string memory
    return (node);
}

ASTNode *mknode_binop (int32_t  op, ASTNode *left, ASTNode *right)
{
    ASTNode *node                 = mknode (NODE_BINARY_OP);
    node -> data.binary_op.op     = op;
    node -> data.binary_op.left   = left;
    node -> data.binary_op.right  = right;
    return (node);
}

ASTNode *mknode_assign (const int8_t *name, ASTNode *value)
{
    ASTNode *node              = mknode (NODE_ASSIGN);
    node -> data.assign.name   = strdup (name);
    node -> data.assign.value  = value;
    return (node);
}
