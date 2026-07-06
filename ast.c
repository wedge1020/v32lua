#include "ast.h"

BlockBuilder *mkbuilder ()
{
    BlockBuilder *bb    = malloc (sizeof (BlockBuilder));
    if (bb             != NULL)
    {
        bb -> count     = 0;
        bb -> capacity  = 4;
        bb -> nodes     = malloc (sizeof (ASTNode *) * bb -> capacity);
    }
    return (bb);
}

void  builder_append (BlockBuilder *bb, ASTNode *node)
{
    if (node                       != NULL)
    {
        if (bb -> count            >= bb -> capacity)
        {
            bb -> capacity          = bb -> capacity * 2;
            bb -> nodes             = realloc (bb -> nodes,
                                               sizeof (ASTNode *) * bb -> capacity);
        }
        bb -> nodes[bb -> count++]  = node;
    }
}
