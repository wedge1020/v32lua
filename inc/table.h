#ifndef __TABLE_H
#define __TABLE_H

bool  is_table_unpack_call             (ASTNode *);
void  emit_table_unpack_resolve_bounds (ASTNode *, char *, char *, char *, int);
void  emit_table_unpack_fetch_element  (const char *, const char *, const char *, int, int);

#endif
