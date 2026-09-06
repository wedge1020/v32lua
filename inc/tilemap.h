#ifndef __TILEMAP_H
#define __TILEMAP_H

typedef struct tilemap_asset TilemapAsset;
struct tilemap_asset
{
    char         *name;
    char         *filename;
    int           width;
    int           height;
    int          *cells;        // width*height ints, row-major
    TilemapAsset *next;
};

extern TilemapAsset *tilemaps_head;
extern TilemapAsset *tilemaps_tail;

void          emit_tilemap_rom_data               (FILE       *);
TilemapAsset *tilemap_resolve_name                (ASTNode *);
bool          emit_vircon32_tilemap_get_intrinsic (ASTNode *, int);
bool          emit_vircon32_tilemap_set_intrinsic (ASTNode *, int);

#endif
