#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "ast.h"
#include "compile.h"
#include "symtable.h"

// Declared internally by the generated leg code
extern int32_t yyparse();
extern ASTNode* yyval; // Holds the final parsed root element ($$ of Program)
                       //
int32_t  main (int  argc, char **argv)
{
    // leg reads code stream natively from standard input (stdin)
    if (yyparse ())
    {
        ASTNode *root              = yyval;
        fprintf (stdout, "; --- Parsing Successful! Beginning Compilation ---\n");

        // Initialize symbol scope tracking definitions
        SymbolTable *global_scope  = calloc (1, sizeof (SymbolTable));
        int32_t      stack_offset  = 0;

        // Run our code generation pass down the AST tree
        compile_node (root, global_scope, &stack_offset);
        // Free structures cleanly
        ast_free (root);
        free (global_scope);
    }
    else
    {
        fprintf (stderr, "Syntax Error: Failed to parse Lua input script.\n");
        return (1);
    }

    return (0);
}
