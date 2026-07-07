#include <stdio.h>
#include "ast.h"

void  generate_assembly (ASTNode *node)
{
    if (node != NULL)
    {
        switch (node -> type)
        {
            case NODE_NUMBER:
                // For a stack-based machine / evaluation pattern:
                fprintf (stdout, "    MOV R0, %f\n", node -> data.number.value);
                break;

            case NODE_IDENTIFIER:
                fprintf (stdout, "    MOV R0, [%s]\n", node -> data.identifier.name);
                break;

            case NODE_BINARY_OP:
                // Evaluate right side first, push to a temporary place/stack, then left side
                generate_assembly (node -> data.binary_op.right);
                fprintf (stdout, "    PUSH R0\n"); // Push right side value
                generate_assembly (node -> data.binary_op.left);
                fprintf (stdout, "    POP R1\n"); // Pop right side into R1
                switch (node -> data.binary_op.op)
                {
                    case '+':
                        fprintf (stdout, "    IADD  R0, R1\n");
                        break;

                    case '-':
                        fprintf (stdout, "    ISUB  R0, R1\n"); // will need to deal with order
                        break;

                    case '*':
                        fprintf (stdout, "    IMUL  R0, R1\n");
                        break;

                    case '/':
                        fprintf (stdout, "    IDIV  R0, R1\n"); // will need to deal with order
                        break;

                    case '%':
                        fprintf (stdout, "    IMOD  R0, R1\n"); // will need to deal with order
                        break;

                    default:
                        fprintf (stderr, "ERROR: invalid binary operation '%s'\n", node -> data.binary_op.op);
                        break;
                }
                break;

            case NODE_ASSIGN:
                generate_assembly (node -> data.assign.value); // Result is in R0
                fprintf (stdout, "    MOV [%s], R0\n", node -> data.assign.name);
                break;

            default:
                fprintf(stderr, "Unknown AST node type!\n");
                break;
        }
    }
}
