#include "v32lua.h"

void  node_boolean (ASTNode *node, int  dest_reg)
{
    if (node -> as.boolean.val)
    {
        emit_asm ("MOV R%d, BOXED_TRUE ; literal true\n",   dest_reg);
    }
    else
    {
        emit_asm ("MOV R%d, BOXED_FALSE ; literal false\n", dest_reg);
    }
}

void  node_nil (int  dest_reg)
{
    emit_asm ("MOV R%d, BOXED_NIL; the lua nil\n", dest_reg);
}
