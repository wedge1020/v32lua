#ifndef _FACTORY_H
#define _FACTORY_H

#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "ast.h"

//////////////////////////////////////////////////////////////////////////////
//
// Helper to clear and allocate base node memory
//
static ASTNode *mknode (NodeType);
ASTNode *mknode_num    (float);
ASTNode *mknode_ident  (const int8_t *);
ASTNode *mknode_binop  (int32_t, ASTNode *, ASTNode *);
ASTNode *mknode_assign (const int8_t *, ASTNode *);

#endif
