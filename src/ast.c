#include <stdlib.h>
#include <stdio.h>
#include "codegen.h"

ASTNode* make_node_binary (NodeType type, ASTNode* left, ASTNode* right) {
    // 1. Allocate memory for the new node
    ASTNode* node = (ASTNode*)malloc(sizeof(ASTNode));
    if (node == NULL) {
        fprintf(stderr, "Compiler Error: Out of memory during AST node allocation.\n");
        exit(1);
    }

    // 2. Set the node type (e.g., NODE_ADD, NODE_AND, NODE_OR)
    node->type = type;

    // 3. Assign the left and right child expressions
    node->as.binary.left = left;
    node->as.binary.right = right;
    node->as.binary.operator = 0; // Default/unused unless using NODE_RELATIONAL

    // 4. CRITICAL: Always explicitly initialize the sibling pointer to NULL.
    // If left uninitialized, it will contain garbage data and trigger segfaults
    // during code generation traversals!
    node->next = NULL;

    return node;
}
