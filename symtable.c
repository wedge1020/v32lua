#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include "symtable.h"

// Creates a new inner scope pointing back to the current scope
SymbolTable *scope_enter (SymbolTable *current_scope)
{
    SymbolTable *new_scope   = (SymbolTable *) calloc (1, sizeof (SymbolTable));
    if (new_scope           != NULL)
    {
        new_scope -> parent  = current_scope;
    }
    return (new_scope);
}

// Destroys the current inner scope and returns the parent scope
SymbolTable *scope_exit (SymbolTable *current_scope)
{
    int32_t      index       = 0;
    SymbolTable *parent      = NULL;

    if (current_scope       != NULL)
    {
        SymbolTable *parent  = current_scope -> parent;

        // Free strings allocated in this specific local scope block
        for (index           = 0;
             index          <  current_scope -> symbol_count;
             index           = index + 1)
        {
            free (current_scope -> symbols[index].name);
        }

        free (current_scope);
    }

    return (parent);
}

// Define a local variable in the absolute current block scope
bool scope_define_local (SymbolTable *current_scope, const int8_t *name, int32_t  stack_offset)
{
    int32_t  check    = 0;
    int32_t  index    = 0;

    if (current_scope -> symbol_count >= MAX_SYMBOLS)
    {
        return (false);
    }

    // Check if already declared in *this specific* block level
    for (index        = 0;
         index       <  current_scope -> symbol_count;
         index        = index + 1)
    {
        check         = strcmp (current_scope -> symbols[index].name, name);
        if (check    == 0)
        {
            return (false); // Redefinition in same block context
        }
    }

    index             = current_scope -> symbol_count++;
    current_scope -> symbols[index].name          = strdup (name);
    current_scope -> symbols[index].is_local      = true;
    current_scope -> symbols[index].stack_offset  = stack_offset;

    return (true);
}

// Look up a variable by walking up the scope chain
Symbol *scope_lookup (SymbolTable *current_scope, const int8_t *name)
{
    int32_t  check        = 0;
    int32_t  index        = 0;
    SymbolTable *current  = current_scope;
    while (current       != NULL)
    {
        for (index        = 0;
             index       <  current -> symbol_count;
             index        = index + 1)
           {
            check         = strcmp (current -> symbols[index].name, name);
            if (check    == 0)
            {
                return (&current -> symbols[index]); // Found local or bound global
            }
        }
        current           = current -> parent; // Move outward
    }

    return (NULL); // Not found anywhere (implicitly a runtime global)
}
