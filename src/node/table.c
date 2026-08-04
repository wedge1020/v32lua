#include "v32lua.h"

void  node_table_constructor (ASTNode *node, int dest_reg)
{
    // 1. Allocate new table
    emit_asm("CALL __builtin_table_new\n");
    emit_asm("MOV R%d, R0\n", dest_reg);

    // 2. If there are initializers, process them
    if (node->as.table_constructor.initializers_head != NULL) {
        ASTNode *field = node->as.table_constructor.initializers_head;
        int array_index = 1; // Lua arrays are 1-indexed

        while (field != NULL) {
            // Handle array-style initializer (just a value expression)
            if (field->type != NODE_TABLE_SET) {
                // Generate: table[array_index] = value
                int val_reg = allocate_pinned_register();
                int key_reg = allocate_pinned_register();

                mark_register_live(val_reg, 2);
                mark_register_live(key_reg, 2);

                // Generate the value
                generate_asm(field, val_reg);

                // Create integer key node for array index
                ASTNode *key_node = make_node(NODE_NUMBER);
                key_node->as.number.val = array_index;
                generate_asm(key_node, key_reg);
                free(key_node); // Clean up temporary node

                ensure_in_register(val_reg);
                ensure_in_register(key_reg);

                // Call __builtin_table_set
                emit_asm("PUSH R%d ; table pointer", dest_reg);
                emit_asm("PUSH R%d ; key", key_reg);
                emit_asm("PUSH R%d ; value", val_reg);
                emit_asm("CALL __builtin_table_set");
                emit_asm("IADD SP, 3 ; clean up stack");

                unlock_pinned_register(val_reg);
                unlock_pinned_register(key_reg);

                array_index++;
            }
            // Handle record-style initializer (key = value)
            else {
                // field is already a NODE_TABLE_SET with key and value
                // We need to set the table_expr to our new table
                field->as.table_set.table_expr = make_node_ident("__temp_table");

                int table_reg = dest_reg; // Already has the table
                int val_reg = allocate_pinned_register();
                int key_reg = allocate_pinned_register();

                mark_register_live(val_reg, 2);
                mark_register_live(key_reg, 2);

                generate_asm(field->as.table_set.value, val_reg);
                generate_asm(field->as.table_set.key, key_reg);

                ensure_in_register(val_reg);
                ensure_in_register(key_reg);

                emit_asm("PUSH R%d ; table pointer", table_reg);
                emit_asm("PUSH R%d ; key", key_reg);
                emit_asm("PUSH R%d ; value", val_reg);
                emit_asm("CALL __builtin_table_set");
                emit_asm("IADD SP, 3 ; clean up stack");

                unlock_pinned_register(val_reg);
                unlock_pinned_register(key_reg);
            }

            field = field->next;
        }
    }
}

void  node_table_set (ASTNode *node)
{
    // 1. Attempt to emit as a hardware intrinsic FIRST, passing only the AST node!
    if (try_emit_table_set_intrinsic(node->as.table_set.table_expr,
                                     node->as.table_set.key,
                                     node->as.table_set.value))
    {
        // Intrinsic handled the emission (either via immediate or on-demand register)!
        return;
    }

    // 2. Fallback: Dynamic heap assignment (table[key] = value)
    int  val_reg    = allocate_pinned_register ();
    int  table_reg  = allocate_pinned_register ();
    int  key_reg    = allocate_pinned_register ();

    // ✅ All used immediately for table operation
    mark_register_live (val_reg,   2);
    mark_register_live (table_reg, 2);
    mark_register_live (key_reg,   2);

    generate_asm (node -> as.table_set.value,      val_reg);
    generate_asm (node -> as.table_set.table_expr, table_reg);
    generate_asm (node -> as.table_set.key,        key_reg);

    ensure_in_register (val_reg);
    ensure_in_register (table_reg);
    ensure_in_register (key_reg);

    emit_asm ("PUSH R%d ; table pointer", table_reg);
    emit_asm ("PUSH R%d ; key",           key_reg);
    emit_asm ("PUSH R%d ; value",         val_reg);
    emit_asm ("CALL __builtin_table_set ; store key-value pair in table");
    emit_asm ("IADD SP, 3 ; clean up stack arguments");

    unlock_pinned_register (val_reg);
    unlock_pinned_register (table_reg);
    unlock_pinned_register (key_reg);
}

void  node_table_get (ASTNode *node, int  dest_reg)
{
    // 1. Attempt hardware intrinsic read directly into dest_reg
    if (try_emit_table_get_intrinsic(node->as.table_get.table_expr,
                                     node->as.table_get.key,
                                     dest_reg)) {
        return; // Successfully emitted Vircon32 IN instruction!
    }

    // 2. Fallback: Dynamic heap table lookup
    int table_reg = allocate_register();
    int key_reg   = allocate_register();

    // ✅ Short-lived
    mark_register_live(table_reg, 2);
    mark_register_live(key_reg, 2);

    generate_asm(node->as.table_get.table_expr, table_reg);
    generate_asm(node->as.table_get.key, key_reg);

    ensure_in_register(table_reg);
    ensure_in_register(key_reg);

    emit_asm ("PUSH R%d ; Arg1: Table Pointer", table_reg);
    emit_asm ("PUSH R%d ; Arg2: Key", key_reg);

    emit_asm ("CALL __builtin_table_get");
    emit_asm ("IADD SP, 2 ; Clean up stack");
    emit_asm ("MOV R%d, R0 ; Store result in destination register", dest_reg);

    unlock_register (table_reg);
    unlock_register (key_reg);
}
