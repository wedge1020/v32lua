#include <stdlib.h>
#include <stdio.h>
#include "codegen.h"

ASTNode *make_node_unary (Operator  op, ASTNode *operand)
{
    ASTNode* node = malloc(sizeof(ASTNode));
    node->type = NODE_UNARY;
    node->next = NULL;
    node->as.unary.operator = op;
    node->as.unary.operand = operand;
    return node;
}

void generate_binary_op (ASTNode* node)
{
	if (node->type == NODE_CONCAT) {
        // --- Step 1: Evaluate Left Operand ---
        // Generates assembly for left child and leaves result in R0 (register index 0)
        generate_asm(node->as.binary.left, 0);

        // Push left operand to stack (Sits at SP+1 relative to call)
        emit_asm ("PUSH  R0             ; Save left string operand");

        // --- Step 2: Evaluate Right Operand ---
        // Generates assembly for right child and leaves result in R0 (register index 0)
        generate_asm(node->as.binary.right, 0);

        // Push right operand to stack (Sits at SP+0 relative to call)
        emit_asm ("PUSH  R0             ; Save right string operand");

        // --- Step 3: Invoke Built-in ---
        emit_asm ("CALL  __builtin_strcat ; Execute NaN-boxed string concatenation");

        // --- Step 4: Stack Cleanup ---
        emit_asm ("ISUB  SP, 2          ; Pop concatenation arguments");
        return;
    }

    // ... handle other binary operators (+, -, *, /) using node->as.binary.operator ...
}

ASTNode *make_node_binary (NodeType  type, ASTNode *left, ASTNode *right)
{
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

ASTNode *make_node_table_constructor (void)
{
    ASTNode* node = malloc(sizeof(ASTNode));
    node->type = NODE_TABLE_CONSTRUCTOR;
    node->next = NULL;
    // No union data needed for an empty table!
    return node;
}

ASTNode *make_node_table_get (ASTNode *table_expr, ASTNode *key_expr)
{
    ASTNode* node = malloc(sizeof(ASTNode));
    node->type = NODE_TABLE_GET;
    node->next = NULL;
    node->as.table_get.table_expr = table_expr;
    node->as.table_get.key = key_expr;
    return node;
}

ASTNode *make_node_table_set (ASTNode *table_expr, ASTNode *key_expr, ASTNode *value_expr)
{
    ASTNode* node = malloc(sizeof(ASTNode));
    node->type = NODE_TABLE_SET;
    node->next = NULL;
    node->as.table_set.table_expr = table_expr;
    node->as.table_set.key = key_expr;
    node->as.table_set.value = value_expr;
    return node;
}
