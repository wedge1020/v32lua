#ifndef __INTRINSICS_H
#define __INTRINSICS_H

#include "ast.h"

#define IOPORT_READ  1
#define IOPORT_WRITE 2
#define IOPORT_ACTION 4

#define IOPORT_TYPE_INTEGER 1
#define IOPORT_TYPE_FLOAT   2
#define IOPORT_TYPE_BOOLEAN 4


// Returns 1 if the node was an intrinsic and assembly was emitted; 0 otherwise.
//
int  try_emit_action_intrinsic    (const char *, int);
int  try_emit_call_intrinsic      (ASTNode    *, int);
int  try_emit_table_set_intrinsic (ASTNode    *, ASTNode *, int);
int  try_emit_table_get_intrinsic (ASTNode    *, ASTNode *, int);

#endif
