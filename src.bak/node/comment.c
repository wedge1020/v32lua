#include "v32lua.h"

void  node_comment_line (ASTNode *node)
{
    emit_asm ("%s", node -> as.string_val.value);
}

void  node_comment_block (ASTNode *node)
{
    // Split block comments by newline and prepend ';' to every individual line
    char *buffer     = strdup(node->as.string_val.value);
    if (buffer      != NULL)
    {
        char *line   = strtok (buffer, "\n");
        emit_asm (";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n");
        emit_asm (";; \n");
        while (line != NULL) {
            emit_asm (";;@ %s", line);
            line     = strtok(NULL, "\n");
        }
        free (buffer);
        emit_asm (";; \n");
    }
}

void  node_cart_hint (ASTNode *node, int  dest_reg)
{
    // Only indexed resources (textures/audio) generate runtime Lua variables
    if ((node -> as.cart_hint.resource_id != -1) &&
        (node -> as.cart_hint.name        != NULL))
    {
        char  var_access[256];

        ////////////////////////////////////////////////////////////////////
        //
        // Automatically register provided name as a global variable
        //
        get_variable_access_string (node -> as.cart_hint.name, var_access);
        
        emit_asm ("    ;; Texture: Initialize '%s' to resource ID %d\n", 
                 node -> as.cart_hint.name,
                 node -> as.cart_hint.resource_id);
                 
        // FIX: Stage the immediate resource ID into our scratch register first,
        // then move the register's contents into the memory address!
        emit_asm ("MOV R%d, %f\n", dest_reg, 
                  (float) node -> as.cart_hint.resource_id);
        emit_asm ("MOV %s, R%d\n", var_access, dest_reg);
    }
}
