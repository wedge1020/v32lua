#include "v32lua.h"

// Global state for XML generation
char cart_version[64]        = "1.0";
char cart_title[128]         = "Vircon32 Program";
CARTresource* textures_head  = NULL;
CARTresource* sounds_head    = NULL;
int next_texture_id          = 0;

ASTNode *make_node (NodeType type)
{
    ASTNode* n = (ASTNode*)calloc(1, sizeof(ASTNode));
    n->type = type;
    n->next = NULL;
    return n;
}

ASTNode *make_node_ident (const char* name)
{
    ASTNode* node = make_node(NODE_IDENTIFIER);
    // Use strdup to ensure the AST owns the memory for the string,
    // protecting it from being overwritten by the lexer's buffer.
    node->as.id.name = strdup(name);

    return node;
}

ASTNode *make_node_string (const char* str_value)
{
    ASTNode* node = make_node(NODE_STRING);
    // strdup protects the string from being overwritten by the lexer
    node->as.string_val.value = strdup(str_value);
    return node;
}
ASTNode *make_node_cart_hint (const char *raw_hint)
{
    ASTNode* node = make_node(NODE_CART_HINT);
    
    char action[64] = {0};
    char param1[128] = {0};
    char param2[256] = {0};

    // Parse commands like: texture background "filename.png"
    int tokens = sscanf(raw_hint, "%63s %127s \"%255[^\"]\"", action, param1, param2);
    
    node->as.cart_hint.action = strdup(action);
    node->as.cart_hint.resource_id = -1;

    if (strcmp(action, "version") == 0 && tokens >= 2) {
        // e.g., --#version 1.1
        strncpy(cart_version, param1, sizeof(cart_version) - 1);
        node->as.cart_hint.value = strdup(param1);
    } 
    else if (strcmp(action, "title") == 0) {
        // e.g., --#title "My Awesome Game"
        char title_buf[128] = {0};
        if (sscanf(raw_hint, "%*s \"%127[^\"]\"", title_buf) == 1) {
            strncpy(cart_title, title_buf, sizeof(cart_title) - 1);
            node->as.cart_hint.value = strdup(title_buf);
        }
    }
    else if (strcmp(action, "texture") == 0 && tokens == 3) {
        // e.g., --#texture background "filename.png"
        int assigned_id = next_texture_id++;
        
        node->as.cart_hint.name = strdup(param1);        // Variable name: background
        node->as.cart_hint.value = strdup(param2);       // Filename: filename.png
        node->as.cart_hint.resource_id = assigned_id;    // ID: 0, 1, 2...

        // Register in our XML linked list
        CARTresource* res = (CARTresource*)malloc(sizeof(CARTresource));
        res->id = assigned_id;
        res->var_name = strdup(param1);
        res->filename = strdup(param2);
        res->next = textures_head;
        textures_head = res;
    }

    return node;
}


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
