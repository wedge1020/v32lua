#include "v32lua.h"

void  node_multiple_assignment (ASTNode *node)
{
    ASTNode *curr_tgt             = node -> as.mult_assign.targets_head;
    ASTNode *curr_val             = node -> as.mult_assign.values_head;
    int      val_reg              = -1;

    // --- Intercept Bare Local Declarations (e.g., "local x, y") ---
    if (node -> as.mult_assign.is_local && node -> as.mult_assign.values_head == NULL)
    {
        while (curr_tgt          != NULL)
        {
            if (curr_tgt -> type == NODE_IDENTIFIER)
            {
                // Register local symbol and initialize to canonical Nil (BOXED_NIL)
                SymbolNode *sym   = register_local (curr_tgt -> as.id.name);
                char access_str[128];
                get_variable_access_string(sym->name, access_str);

                emit_asm ("    ;; Bare local '%s' initialized to nil", sym->name);
                emit_asm ("MOV %s, BOXED_NIL", access_str);
            }
            curr_tgt              = curr_tgt -> next;
        }
        return;
    }

    // --- Standard & Multiple Assignment Evaluation ---
    while (curr_tgt != NULL) {
        // =========================================================================
        // 1. ATTEMPT HARDWARE INTRINSIC FIRST (Immediate Folding / Lazy Evaluation)
        // =========================================================================
        // Only check if we are targeting a table property AND have a valid value node
        if (curr_tgt->type == NODE_TABLE_GET && curr_val != NULL) {
            if (try_emit_table_set_intrinsic(curr_tgt->as.table_get.table_expr,
                                             curr_tgt->as.table_get.key,
                                             curr_val))
            {
                // Intrinsic successfully emitted (either folded to immediate or 
                // evaluated on-demand)! Advance pointers and skip standard allocation.
                curr_tgt = curr_tgt->next;
                curr_val = curr_val->next;
                continue;
            }
        }

        // =========================================================================
        // 2. STANDARD EVALUATION (Identifiers, Fallback Dynamic Tables, or Nils)
        // =========================================================================
        val_reg = allocate_pinned_register();

        // ✅ Value register used immediately for assignment
        mark_register_live(val_reg, 1);

        if (curr_val != NULL) {
            // Evaluate the right-hand expression into our temporary register
            generate_asm(curr_val, val_reg);
            curr_val = curr_val->next;
        } else {
            // Lua rule: If values run out, remaining targets are assigned nil
            emit_asm("MOV R%d, BOXED_NIL ; Pad missing value with Nil", val_reg);
        }

        ensure_in_register(val_reg);

        // Assign evaluated value to the target
        if (curr_tgt->type == NODE_IDENTIFIER) {
            if (node->as.mult_assign.is_local) {
                register_local(curr_tgt->as.id.name);
            }
            char access_str[128];
            get_variable_access_string(curr_tgt->as.id.name, access_str);

            // ✅ NEW DEBUG
            if (g_verbose_debug) {
                fprintf(stderr, "[debug] node_multiple_assignment() Assigning: %s -> %s (val_reg=R%d)\n",
						curr_tgt->as.id.name, access_str, val_reg);
			}

            emit_asm("MOV %s, R%d", access_str, val_reg);
        }
        else if (curr_tgt->type == NODE_TABLE_GET)
        {
            // Fallback: Dynamic heap table assignment (table[key] = value)
            int table_reg = allocate_pinned_register();
            int key_reg   = allocate_pinned_register();

            generate_asm(curr_tgt->as.table_get.table_expr, table_reg);
            generate_asm(curr_tgt->as.table_get.key, key_reg);

            emit_asm("PUSH R%d ; Push Table Pointer", table_reg);
            emit_asm("PUSH R%d ; Push Key", key_reg);
            emit_asm("PUSH R%d ; Push Value", val_reg);
            emit_asm("CALL __builtin_table_set");
            emit_asm("IADD SP, 3 ; Clean up stack");

            unlock_pinned_register(table_reg);
            unlock_pinned_register(key_reg);
        }

        unlock_pinned_register(val_reg);
        curr_tgt = curr_tgt->next;
    }
}
