#include "ast.h"

void  ast_free (ASTNode *node)
{
    int32_t  index          = 0;

    if (node               != NULL)
    {
        switch (node -> type)
        {
            case NODE_IDENTIFIER:
                free (node -> data.identifier.name);
                break;

            case NODE_ASSIGN:
                free (node -> data.assign.name);
                ast_free (node -> data.assign.value);
                break;

            case NODE_BINARY_OP:
                ast_free (node -> data.binary_op.left);
                ast_free (node -> data.binary_op.right);
                break;

            case NODE_WHILE:
                ast_free (node -> data.while_loop.condition);
                ast_free (node -> data.while_loop.body);
                break;

            case NODE_PROGRAM:
                for (index  = 0;
                     index <  node -> data.program.statement_count;
                     index  = index +1)
                {
                    ast_free (node -> data.program.statements[index]);
                }
                free (node -> data.program.statements);
                break;

            case NODE_NUMBER:
                break; // No dynamic memory allocated inside
        }
        free (node);
    }
}
