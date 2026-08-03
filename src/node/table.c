#include "v32lua.h"

void  node_table_constructor (int  dest_reg)
//void  node_table_constructor (ASTNode *node, int  dest_reg)
{
    // Call the built-in to allocate a new table
    emit_asm ("CALL __builtin_table_new\n");
    // Move the returned tagged pointer into the destination register
    emit_asm ("MOV R%d, R0\n", dest_reg);
    
    // (If you want to support {1, 2, 3} later, you would loop through 
    // the node's children here and call __builtin_table_set for each one)
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
    int  val_reg    = allocate_register ();
    int  table_reg  = allocate_register ();
    int  key_reg    = allocate_register ();

	// ✅ NEW: Pin registers to prevent reuse by function calls
    register_pinned[val_reg] = 1;
    register_pinned[table_reg] = 1;
    register_pinned[key_reg] = 1;

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

	// ✅ NEW: Unpin registers
    register_pinned[val_reg] = 0;
    register_pinned[table_reg] = 0;
    register_pinned[key_reg] = 0;

    unlock_register (val_reg);
    unlock_register (table_reg);
    unlock_register (key_reg);
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
