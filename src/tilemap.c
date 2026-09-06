#include "v32lua.h"

TilemapAsset *tilemaps_head = NULL;
TilemapAsset *tilemaps_tail = NULL;

void emit_tilemap_rom_data (FILE *out)
{
    if (tilemaps_head == NULL) return;

    fprintf (out, "\n;; =========================================================\n");
    fprintf (out, ";; Native Vircon32 tilemap ROM data\n");
    fprintf (out, ";; =========================================================\n");

    for (TilemapAsset *t = tilemaps_head; t != NULL; t = t->next) {
        fprintf (out, "__tilemap_%s_rom:\n    integer ", t->name);
        int total = t->width * t->height;
        for (int i = 0; i < total; i++) {
            fprintf (out, "%d", t->cells[i]);
            if (i < total - 1) fprintf (out, ", ");
            if ((i + 1) % 16 == 0 && i < total - 1) fprintf (out, "\n    integer ");
        }
        fprintf (out, "\n\n");
    }
}

// ADD -- near tilemap_head/tail or wherever's convenient
// Resolves a bare identifier naming a --#tilemap hint. No numeric fallback
// unlike sound ids -- a tilemap selector is always a name, never a value.
TilemapAsset *tilemap_resolve_name (ASTNode *node)
{
    if (node == NULL || node->type != NODE_IDENTIFIER || node->as.id.name == NULL) {
        return NULL;
    }
    for (TilemapAsset *t = tilemaps_head; t != NULL; t = t->next) {
        if (strcmp (t->name, node->as.id.name) == 0) {
            return t;
        }
    }
    return NULL;
}

bool emit_vircon32_tilemap_get_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *name_arg = node->as.call.args_head;
    TilemapAsset *t = tilemap_resolve_name (name_arg);
    if (t == NULL) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "tilemap.get() requires a --#tilemap-declared name as its first "
            "argument: tilemap.get(NAME, x, y)");
        return false;
    }

    ASTNode *arg_x = (name_arg != NULL) ? name_arg->next : NULL;
    ASTNode *arg_y = (arg_x    != NULL) ? arg_x->next    : NULL;
    if (arg_x == NULL || arg_y == NULL) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "tilemap.get() requires 3 arguments: tilemap.get(NAME, x, y)");
        return false;
    }

    runtime_req.needs_vircon32 = true;

    char ram_ptr_label[192];
    snprintf (ram_ptr_label, sizeof (ram_ptr_label),
              "var_VIRCON32_TILEMAP_%s_RAM_PTR", t->name);

    emit_asm ("    ;; --- Native tilemap.get('%s') ---\n", t->name);

    int reg = allocate_register();
    generate_asm (arg_y, reg);
    emit_asm ("PUSH R%d ; y\n", reg);
    unlock_register (reg);

    reg = allocate_register();
    generate_asm (arg_x, reg);
    emit_asm ("PUSH R%d ; x\n", reg);
    unlock_register (reg);

    reg = allocate_register();
    emit_asm ("MOV R%d, %d\n", reg, t->height);
    emit_asm ("PUSH R%d ; height\n", reg);
    unlock_register (reg);

    reg = allocate_register();
    emit_asm ("MOV R%d, %d\n", reg, t->width);
    emit_asm ("PUSH R%d ; width\n", reg);
    unlock_register (reg);

    reg = allocate_register();
    emit_asm ("MOV R%d, %s\n", reg, ram_ptr_label);   // address, not value
    emit_asm ("PUSH R%d ; ram_ptr_addr\n", reg);
    unlock_register (reg);

    reg = allocate_register();
    emit_asm ("MOV R%d, __tilemap_%s_rom\n", reg, t->name);
    emit_asm ("PUSH R%d ; rom_ptr\n", reg);
    unlock_register (reg);

    emit_asm ("CALL __builtin_vircon32_tilemap_get\n");
    emit_asm ("IADD SP, 6 ; clean up tilemap.get() arguments\n");

    if (dest_reg != 0) {
        emit_asm ("MOV R%d, R0\n", dest_reg);
    }
    return true;
}

bool  emit_vircon32_tilemap_set_intrinsic (ASTNode *node, int dest_reg)
{
    ASTNode *name_arg = node->as.call.args_head;
    TilemapAsset *t = tilemap_resolve_name (name_arg);
    if (t == NULL) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "tilemap.set() requires a --#tilemap-declared name as its first "
            "argument: tilemap.set(NAME, x, y, v)");
        return false;
    }

    ASTNode *arg_x = (name_arg != NULL) ? name_arg->next : NULL;
    ASTNode *arg_y = (arg_x    != NULL) ? arg_x->next    : NULL;
    ASTNode *arg_v = (arg_y    != NULL) ? arg_y->next    : NULL;
    if (arg_x == NULL || arg_y == NULL || arg_v == NULL) {
        compiler_error (ERR_SEMANTIC, node->line_number,
            "tilemap.set() requires 4 arguments: tilemap.set(NAME, x, y, v)");
        return false;
    }

    runtime_req.needs_vircon32 = true;

    char ram_ptr_label[192];
    snprintf (ram_ptr_label, sizeof (ram_ptr_label),
              "var_VIRCON32_TILEMAP_%s_RAM_PTR", t->name);

    emit_asm ("    ;; --- Native tilemap.set('%s') ---\n", t->name);

    int reg = allocate_register();
    generate_asm (arg_v, reg);
    emit_asm ("PUSH R%d ; v\n", reg);
    unlock_register (reg);

    reg = allocate_register();
    generate_asm (arg_y, reg);
    emit_asm ("PUSH R%d ; y\n", reg);
    unlock_register (reg);

    reg = allocate_register();
    generate_asm (arg_x, reg);
    emit_asm ("PUSH R%d ; x\n", reg);
    unlock_register (reg);

    reg = allocate_register();
    emit_asm ("MOV R%d, %d\n", reg, t->height);
    emit_asm ("PUSH R%d ; height\n", reg);
    unlock_register (reg);

    reg = allocate_register();
    emit_asm ("MOV R%d, %d\n", reg, t->width);
    emit_asm ("PUSH R%d ; width\n", reg);
    unlock_register (reg);

    reg = allocate_register();
    emit_asm ("MOV R%d, %s\n", reg, ram_ptr_label);
    emit_asm ("PUSH R%d ; ram_ptr_addr\n", reg);
    unlock_register (reg);

    reg = allocate_register();
    emit_asm ("MOV R%d, __tilemap_%s_rom\n", reg, t->name);
    emit_asm ("PUSH R%d ; rom_ptr\n", reg);
    unlock_register (reg);

    emit_asm ("CALL __builtin_vircon32_tilemap_set\n");
    emit_asm ("IADD SP, 7 ; clean up tilemap.set() arguments\n");

    if (dest_reg != 0) {
        emit_asm ("MOV R%d, R0\n", dest_reg);
    }
    return true;
}
