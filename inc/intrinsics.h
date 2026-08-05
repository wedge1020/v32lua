#ifndef __INTRINSICS_H
#define __INTRINSICS_H

#include "ast.h"

#define IOPORT_READ  1
#define IOPORT_WRITE 2
#define IOPORT_ACTION 4

#define IOPORT_TYPE_INTEGER 1
#define IOPORT_TYPE_FLOAT   2
#define IOPORT_TYPE_BOOLEAN 4

typedef struct {
    const char *lua_path;
    const char *asm_port;
    int         mode;     // PORT_READ, PORT_WRIT
    int         type;
} IOPortMap;

extern const IOPortMap  ioports[];
extern const char      *valid_ioports_categories[];

// Returns 1 if the node was an intrinsic and assembly was emitted; 0 otherwise.
//
int   try_emit_action_intrinsic    (const char *, int);
int   try_emit_call_intrinsic      (ASTNode    *, int);
int   try_emit_table_set_intrinsic (ASTNode    *, ASTNode *, ASTNode *);
int   try_emit_table_get_intrinsic (ASTNode    *, ASTNode *, int);
bool  is_raw_integer_expression    (ASTNode    *);

bool  is_valid_ioports_category    (const char *);
void  validate_ioports_path        (const char *, const char *, int);
bool  emit_gpu_draw_intrinsic(ASTNode *node, int dest_reg);
void  emit_gpu_blending_intrinsic (ASTNode *node, int  dest_reg);
void  emit_gpu_clear_intrinsic(ASTNode *node, int dest_reg);
bool  emit_spu_cmd_intrinsic       (ASTNode *, int);
bool  emit_hex_intrinsic(ASTNode *node, int dest_reg);
void  emit_get_gamepad_inputs_intrinsic(int dest_reg);

//////////////////////////////////////////////////////////////////////////////
//
// pico-8 api intrinsics
//
bool  emit_pico8_spr_intrinsic (ASTNode *);
bool  emit_pico8_btn_intrinsic (ASTNode *, int);
bool  emit_pico8_add_intrinsic (ASTNode *, int);

//////////////////////////////////////////////////////////////////////////////
//
// tic80 api intrinsics
//
bool  emit_tic80_spr_intrinsic (ASTNode *);
bool  emit_tic80_btn_intrinsic (ASTNode *, int);
bool  emit_tic80_add_intrinsic (ASTNode *, int);

void  emit_print_intrinsic (ASTNode *node);
bool  emit_printf_intrinsic(ASTNode *node, int dest_reg);
void  emit_get_gamepad_inputs_intrinsic(int dest_reg);
void  emit_system_wait_intrinsic ();
void  emit_system_halt_intrinsic ();

//////////////////////////////////////////////////////////////////////////////	
//
// math intrinsics
//
bool  emit_math_floor_intrinsic (ASTNode *, int);
bool  emit_math_sqrt_intrinsic  (ASTNode *, int);

#endif
