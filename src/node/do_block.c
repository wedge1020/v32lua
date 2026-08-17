#include "v32lua.h"

// ============================================================================
// DO BLOCK: do ... end
//
// The simplest statement in the grammar: no condition, no branch, no loop
// bookkeeping. It exists purely to give its contents their own lexical
// scope -- most commonly so a 'local' declared inside goes out of scope at
// the matching 'end' instead of shadowing for the rest of the enclosing
// block. This is exactly the body-scoping half of node_if() above, with
// the condition/branch machinery removed.
// ============================================================================
void  node_do_block (ASTNode *node)
{
    push_scope ();
    generate_block (node -> as.do_block.body);
    pop_scope ();
}
