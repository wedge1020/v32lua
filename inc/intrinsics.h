#ifndef __INTRINSICS_H
#define __INTRINSICS_H

#include "ast.h"

#define IOPORT_READ  1
#define IOPORT_WRITE 2
#define IOPORT_ACTION 4

#define IOPORT_TYPE_INTEGER 1
#define IOPORT_TYPE_FLOAT   2
#define IOPORT_TYPE_BOOLEAN 4

extern unsigned int tic80_palette[16];

typedef struct {
    const char *lua_path;
    const char *asm_port;
    int         mode;     // PORT_READ, PORT_WRIT
    int         type;
} IOPortMap;

extern const IOPortMap  ioports[];
extern const char      *valid_ioports_categories[];

extern int              vircon32_sfx_cursor_base;
extern int              vircon32_btn_prev_state_base;
extern int              vircon32_music_channel_mask_base;
extern int              vircon32_sfx_channel_mask_base;

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

bool  emit_type_intrinsic (ASTNode *, int);

//////////////////////////////////////////////////////////////////////////////
//
// pico-8 api intrinsics
//
bool  emit_pico8_spr_intrinsic   (ASTNode *);
bool  emit_pico8_btn_intrinsic   (ASTNode *, int);
bool  emit_pico8_btnp_intrinsic  (ASTNode *, int);
bool  emit_pico8_add_intrinsic   (ASTNode *, int);
bool  emit_pico8_cls_intrinsic   (ASTNode *);
bool  emit_pico8_mget_intrinsic  (ASTNode *, int);
bool  emit_pico8_mset_intrinsic  (ASTNode *, int);
bool  emit_pico8_map_intrinsic   (ASTNode *);

//////////////////////////////////////////////////////////////////////////////
//
// tic80 api intrinsics
//
bool  emit_tic80_spr_intrinsic   (ASTNode *);
bool  emit_tic80_btn_intrinsic   (ASTNode *, int);
bool  emit_tic80_btnp_intrinsic  (ASTNode *, int);
bool  emit_tic80_add_intrinsic   (ASTNode *, int);
bool  emit_tic80_cls_intrinsic   (ASTNode *);
bool  emit_tic80_print_intrinsic (ASTNode *);
// TIC-80 Map Functions
bool  emit_tic80_mget_intrinsic  (ASTNode *, int);
bool  emit_tic80_mset_intrinsic  (ASTNode *, int);
bool  emit_tic80_map_intrinsic   (ASTNode *);
bool  emit_tic80_sync_intrinsic  (ASTNode *, int);
// TIC-80 Sound API
bool  emit_tic80_play_intrinsic  (ASTNode *, int);
bool  emit_tic80_sfx_intrinsic   (ASTNode *, int);
bool  emit_tic80_music_intrinsic (ASTNode *, int);
// TIC-80 pmem
bool  emit_tic80_pmem_intrinsic  (ASTNode *, int);
// TIC-80 Sprite Flag Functions
bool  emit_tic80_fget_intrinsic  (ASTNode *, int);
bool  emit_tic80_fset_intrinsic  (ASTNode *, int);
// TIC-80 drawing functions
bool  emit_tic80_pix_intrinsic   (ASTNode *, int);
bool  emit_tic80_line_intrinsic  (ASTNode *, int);
bool  emit_tic80_rect_intrinsic  (ASTNode *, int);
bool  emit_tic80_rectb_intrinsic (ASTNode *, int);
bool  emit_tic80_circ_intrinsic  (ASTNode *, int);
bool  emit_tic80_circb_intrinsic (ASTNode *, int);

bool  emit_tic80_time_intrinsic  (ASTNode *, int);
bool  emit_tic80_exit_intrinsic  (ASTNode *, int);

void  emit_print_intrinsic       (ASTNode *node);
bool  emit_printf_intrinsic      (ASTNode *node, int);
void  emit_get_gamepad_inputs_intrinsic (int);
void  emit_system_wait_intrinsic ();
void  emit_system_halt_intrinsic ();

//////////////////////////////////////////////////////////////////////////////    
//
// Vircon32 native fantasy console API
//
bool  emit_vircon32_spr_intrinsic           (ASTNode *, int);
bool  emit_vircon32_btn_intrinsic           (ASTNode *, int);
bool  emit_vircon32_btnp_intrinsic          (ASTNode *, int);
bool  emit_vircon32_play_intrinsic          (ASTNode *, int);
bool  emit_vircon32_channel_cmd_intrinsic   (ASTNode *, int, const char *);
bool  emit_vircon32_sfx_play_intrinsic      (ASTNode *, int);
bool  emit_vircon32_sfx_stop_intrinsic      (ASTNode *, int);
bool  emit_vircon32_music_playing_intrinsic (ASTNode *, int);
bool  emit_vircon32_volume_intrinsic        (ASTNode *, int, const char *);
int   try_emit_sound_namespace_intrinsic    (ASTNode *, int, const char *);

//////////////////////////////////////////////////////////////////////////////    
//
// memcard.load()/save()/title(), and the memcard[position] bracket sugar.
// emit_vircon32_memcard_write/_read/_clamp_addr are NOT static -- shared
// by both the dotted-call emitters below AND the bracket-index hookup in
// try_emit_table_get/set_intrinsic, which live in a different source file.
//
void  emit_vircon32_memcard_clamp_addr      (int addr_reg);
bool  emit_vircon32_memcard_write           (ASTNode *val_node, ASTNode *pos_node, int dest_reg, int line_number);
bool  emit_vircon32_memcard_read            (ASTNode *pos_node, int dest_reg, int line_number);
bool  emit_vircon32_memcard_save_intrinsic  (ASTNode *, int);
bool  emit_vircon32_memcard_load_intrinsic  (ASTNode *, int);
bool  emit_vircon32_memcard_title_intrinsic (ASTNode *, int);
int   try_emit_memcard_namespace_intrinsic  (ASTNode *, int, const char *);

const char *resolve_intrinsic_alias         (const char *);
bool        is_intrinsic_alias              (const char *);
bool        is_intrinsic_alias_assignment   (ASTNode *);
void        register_intrinsic_aliases_prepass (ASTNode *);

//////////////////////////////////////////////////////////////////////////////    
//
// string intrinsics
//
bool  emit_string_byte_intrinsic    (ASTNode *, int);
bool  emit_string_char_intrinsic    (ASTNode *, int);
bool  emit_tostring_intrinsic       (ASTNode *, int);
bool  emit_tonumber_intrinsic       (ASTNode *, int);
bool  emit_string_format_intrinsic  (ASTNode *, int);
bool  emit_string_len_intrinsic     (ASTNode *, int);
bool  emit_string_sub_intrinsic     (ASTNode *, int);
bool  emit_string_upper_intrinsic   (ASTNode *, int);
bool  emit_string_lower_intrinsic   (ASTNode *, int);
bool  emit_string_rep_intrinsic     (ASTNode *, int);
bool  emit_string_reverse_intrinsic (ASTNode *, int);
bool  emit_string_find_intrinsic    (ASTNode *, int);
bool  emit_string_gsub_intrinsic    (ASTNode *, int);

//////////////////////////////////////////////////////////////////////////////    
//
// math intrinsics
//
bool  emit_math_floor_intrinsic      (ASTNode *, int);
bool  emit_math_sqrt_intrinsic       (ASTNode *, int);
bool  emit_math_sin_intrinsic        (ASTNode *, int);
bool  emit_math_abs_intrinsic        (ASTNode *, int);
bool  emit_math_ceil_intrinsic       (ASTNode *, int);
bool  emit_math_acos_intrinsic       (ASTNode *, int);
bool  emit_math_log_intrinsic        (ASTNode *, int);
bool  emit_math_pow_intrinsic        (ASTNode *, int);
bool  emit_math_atan2_intrinsic      (ASTNode *, int);
bool  emit_math_random_intrinsic     (ASTNode *, int);
bool  emit_math_randomseed_intrinsic (ASTNode *, int);
bool  emit_math_cos_intrinsic        (ASTNode *, int);
bool  emit_math_atan_intrinsic       (ASTNode *, int);
bool  emit_math_exp_intrinsic        (ASTNode *, int);
bool  emit_math_fmod_intrinsic       (ASTNode *, int);
bool  emit_math_max_intrinsic        (ASTNode *, int);
bool  emit_math_min_intrinsic        (ASTNode *, int);
bool  emit_math_asin_intrinsic       (ASTNode *, int);
bool  emit_math_tan_intrinsic        (ASTNode *, int);
bool  emit_math_deg_intrinsic        (ASTNode *, int);
bool  emit_math_rad_intrinsic        (ASTNode *, int);
bool  emit_math_log10_intrinsic      (ASTNode *, int);
bool  emit_math_cosh_intrinsic       (ASTNode *, int);
bool  emit_math_sinh_intrinsic       (ASTNode *, int);
bool  emit_math_tanh_intrinsic       (ASTNode *, int);
int   emit_math_modf_intrinsic       (ASTNode *, int);
int   emit_math_frexp_intrinsic      (ASTNode *, int);
int   emit_math_ldexp_intrinsic      (ASTNode *, int);

//////////////////////////////////////////////////////////////////////////////    
//
// iter intrinsics (for generic for loops)
//
bool  emit_pairs_intrinsic      (ASTNode *);
bool  emit_ipairs_intrinsic     (ASTNode *);

//////////////////////////////////////////////////////////////////////////////    
//
// table library
//
int   emit_table_insert_intrinsic    (ASTNode *, int);
int   emit_table_remove_intrinsic    (ASTNode *, int);
int   emit_table_move_intrinsic      (ASTNode *, int);
int   emit_table_concat_intrinsic    (ASTNode *, int);
int   emit_table_sort_intrinsic      (ASTNode *, int);
int   emit_table_pack_intrinsic      (ASTNode *, int);
int   emit_table_unpack_intrinsic    (ASTNode *, int);

#endif
