#ifndef __INTRINSICS_H
#define __INTRINSICS_H

#include "ast.h"

#define IOPORT_READ  1
#define IOPORT_WRITE 2

#define IOPORT_TYPE_INTEGER 1
#define IOPORT_TYPE_FLOAT   2
#define IOPORT_TYPE_BOOLEAN 4


// Returns 1 if the node was an intrinsic and assembly was emitted; 0 otherwise.
int try_emit_call_intrinsic      (ASTNode *node, int dest_reg);
int try_emit_table_set_intrinsic (ASTNode *node);
int try_emit_table_get_intrinsic (ASTNode *node, int dest_reg);

#endif
