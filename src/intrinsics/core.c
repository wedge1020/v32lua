#include "v32lua.h"

// ============================================================================
// --- Internal IO Port Mapping Table ---
// ============================================================================
const IOPortMap ioports[] = {
    { "ioports.tim.date",      "TIM_CurrentDate",          IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "system.date",           "TIM_CurrentDate",          IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.tim.time",      "TIM_CurrentTime",          IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "system.time",           "TIM_CurrentTime",          IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.tim.frames",    "TIM_FrameCounter",         IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "system.frames",         "TIM_FrameCounter",         IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.tim.cycles",    "TIM_CycleCounter",         IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "system.cycles",         "TIM_CycleCounter",         IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.rng.value",     "RNG_CurrentValue",         IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.rng.seed",      "RNG_CurrentValue",         IOPORT_WRITE,                IOPORT_TYPE_INTEGER },
    { "ioports.gpu.pixels",    "GPU_RemainingPixels",      IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.gpu.bgcolor",   "GPU_ClearColor",           IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.multiply",  "GPU_MultiplyColor",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.blending",  "GPU_ActiveBlending",       IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.texture",   "GPU_SelectedTexture",      IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.region",    "GPU_SelectedRegion",       IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.x",         "GPU_DrawingPointX",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.y",         "GPU_DrawingPointY",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.scaleX",    "GPU_DrawingScaleX",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
    { "ioports.gpu.scaleY",    "GPU_DrawingScaleY",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
    { "ioports.gpu.angle",     "GPU_DrawingAngle",         IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
    { "ioports.gpu.minX",      "GPU_RegionMinX",           IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.minY",      "GPU_RegionMinY",           IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.maxX",      "GPU_RegionMaxX",           IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.maxY",      "GPU_RegionMaxY",           IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.hotX",      "GPU_RegionHotSpotX",       IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.hotY",      "GPU_RegionHotSpotY",       IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.spu.volume",    "SPU_GlobalVolume",         IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
    { "ioports.spu.sound",     "SPU_SelectedSound",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.spu.channel",   "SPU_SelectedChannel",      IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.spu.length",    "SPU_SoundLength",          IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.spu.soundloop", "SPU_SoundPlayWithLoop",    IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_BOOLEAN },
    { "ioports.spu.loopstart", "SPU_SoundLoopStart",       IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.spu.loopend",   "SPU_SoundLoopEnd",         IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.spu.state",     "SPU_ChannelState",         IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.spu.chansound", "SPU_ChannelAssignedSound", IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.spu.chanvolume", "SPU_ChannelVolume",       IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
    { "ioports.spu.chanspeed", "SPU_ChannelSpeed",         IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
    { "ioports.spu.chanloop",  "SPU_ChannelLoopEnabled",   IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_BOOLEAN },
    { "ioports.spu.chanpos",   "SPU_ChannelPosition",      IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
    { "ioports.inp.gamepad",   "INP_SelectedGamepad",      IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.inp.status",    "INP_GamepadConnected",     IOPORT_READ,                 IOPORT_TYPE_BOOLEAN },
    { "ioports.inp.inputs",    "ioports.inp.inputs",       IOPORT_READ | IOPORT_ACTION, IOPORT_TYPE_INTEGER },
    { "ioports.inp.left",      "INP_GamepadLeft",          IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.inp.right",     "INP_GamepadRight",         IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.inp.up",        "INP_GamepadUp",            IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.inp.down",      "INP_GamepadDown",          IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.inp.start",     "INP_GamepadButtonStart",   IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.inp.A",         "INP_GamepadButtonA",       IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.inp.B",         "INP_GamepadButtonB",       IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.inp.X",         "INP_GamepadButtonX",       IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.inp.Y",         "INP_GamepadButtonY",       IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.inp.L",         "INP_GamepadButtonL",       IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.inp.R",         "INP_GamepadButtonR",       IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.car.connect",   "CAR_Connected",            IOPORT_READ,                 IOPORT_TYPE_BOOLEAN },
    { "ioports.car.romsize",   "CAR_ProgramROMSize",       IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.car.numvtex",   "CAR_NumberOfTextures",     IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.car.numvsnd",   "CAR_NumberOfSounds",       IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.mem.connec",    "MEM_Connected",            IOPORT_READ,                 IOPORT_TYPE_BOOLEAN },
    { NULL, NULL, 0, 0 } // Sentinel
};

// ============================================================================
// --- Intrinsic Path Validation ---
// ============================================================================

const char *valid_ioports_categories[] = {
    "tim", "rng", "gpu", "spu", "inp", "car", "mem", NULL
};

bool is_valid_ioports_category (const char *category)
{
    for (int  index = 0; valid_ioports_categories[index] != NULL; index++)
    {
        if (strcmp (category, valid_ioports_categories[index]) == 0)
        {
            return (true);
        }
    }
    return (false);
}

void validate_ioports_path(const char* base_path, const char* key, int line_num) {
    // Extract category from base_path (e.g., "tim" from "ioports.tim")
    if (strncmp(base_path, "ioports.", 8) == 0) {
        char* category = (char*)base_path + 8;

        // Check if category is valid
        if (!is_valid_ioports_category(category)) {
            char available[256] = "";
            for (int i = 0; valid_ioports_categories[i] != NULL; i++) {
                strcat(available, valid_ioports_categories[i]);
                if (valid_ioports_categories[i+1] != NULL) {
                    strcat(available, ", ");
                }
            }
            compiler_error(ERR_SEMANTIC, line_num,
                "Unknown ioports category '%s'. Available categories: %s", category, available);
            return;
        }

        // Build full path and validate property exists in the ioports table
        char full_path[512];
        snprintf(full_path, sizeof(full_path), "%s.%s", base_path, key);

        bool found = false;
        for (int i = 0; ioports[i].lua_path != NULL; i++) {
            if (strcmp(full_path, ioports[i].lua_path) == 0) {
                found = true;
                break;
            }
        }

        if (!found) {
            compiler_error(ERR_SEMANTIC, line_num,
                "Unknown ioports property '%s.%s'", base_path, key);
        }
    }
}

// ============================================================================
// --- Public Interceptor Implementations ---
// ============================================================================

// variables that are backed by functions
int try_emit_action_intrinsic (const char *action, int  dest_reg)
{
    if (strcmp (action, "ioports.inp.inputs") == 0) {
        emit_get_gamepad_inputs_intrinsic (dest_reg);
        return (1);
    }

    return (0);
}

// ============================================================================
// --- Helper: Check if an AST node produces a raw hardware integer ---
// ============================================================================
bool is_raw_integer_expression (ASTNode *node) {
    if (node != NULL)
    {
        // 1. Check if the expression is a direct call to the hex() intrinsic
        if (node -> type    == NODE_FUNCTION_CALL) {
            ASTNode *target  = node -> as.call.target;
            if (target && target -> type == NODE_IDENTIFIER) {
                if (strcmp (target -> as.id.name, "hex") == 0) {
                    return (true);
                }
            }
        }
    }

    // (Future expansion: add checks here for bitwise operators like &, |, <<, etc.)

    return (false);
}


int try_emit_call_intrinsic(ASTNode *node, int dest_reg) {
    char func_name[256] = {0};
    if (!resolve_static_path(node->as.call.target, func_name)) {
        return 0; // Dynamic call, not an intrinsic
    }

    // =========================================================================
    // IOPorts Method Validation (e.g., ioports.gpu.clear())
    // =========================================================================
    if (strncmp(func_name, "ioports.", 8) == 0) {
        // FIX: Find the dot AFTER "ioports." (separates category from method)
        char* dot_pos = strchr(func_name + 8, '.');
        if (dot_pos) {
            // SAFE: Extract category with bounds checking
            char category[64];
            int cat_len = (int)(dot_pos - (func_name + 8));
            if (cat_len >= (int)sizeof(category)) cat_len = sizeof(category) - 1;
            if (cat_len > 0) {
                snprintf(category, sizeof(category), "%.*s", cat_len, func_name + 8);
            } else {
                category[0] = '\0';
            }

            // Validate category
            if (!is_valid_ioports_category(category)) {
                char available[256] = "";
                for (int i = 0; valid_ioports_categories[i] != NULL; i++) {
                    strcat(available, valid_ioports_categories[i]);
                    if (valid_ioports_categories[i+1] != NULL) {
                        strcat(available, ", ");
                    }
                }
                compiler_error(ERR_SEMANTIC, node->line_number,
                    "Unknown ioports category '%s'. Available categories: %s", category, available);
                return 0;
            }

            // SAFE: Extract method with bounds checking
            char method[64];
            snprintf(method, sizeof(method), "%s", dot_pos + 1);

            bool handled = false;

            // Handle known ioports methods
            if (strcmp(func_name, "ioports.gpu.clear") == 0) {
                emit_gpu_clear_intrinsic(node, dest_reg);
                handled = true;
            } else if (strcmp(func_name, "ioports.gpu.draw") == 0) {
                emit_gpu_draw_intrinsic(node, dest_reg);
                handled = true;
            } else if (strcmp(func_name, "ioports.gpu.blending") == 0) {
                emit_gpu_blending_intrinsic(node, dest_reg);
                handled = true;
            } else if (strcmp(func_name, "ioports.spu.command") == 0) {
                emit_spu_cmd_intrinsic(node, dest_reg);
                handled = true;
            }
            else if (strcmp(func_name, "ioports.gpu.sync") == 0) {
                emit_system_wait_intrinsic();
                handled = true;
            }

            if (handled) {
                return 1;
            }

            // Category valid but method not found
            compiler_error(ERR_SEMANTIC, node->line_number,
                "Unknown ioports method '%s'", func_name);
            return 0;
        }
    }

    // =========================================================================
    // Non-ioports Intrinsics
    // =========================================================================

    // print()
    if (strcmp (func_name, "print")  == 0) {
        runtime_req.needs_print       = true;
        runtime_req.needs_strings     = true;

        if (runtime_req.needs_tic80  == true)
        {
            return (emit_tic80_print_intrinsic (node));
        }
        else
        {
            emit_print_intrinsic (node);
            return (1);
        }
    }

    // printf()
    if (strcmp(func_name, "printf") == 0) {
        runtime_req.needs_print      = true;
        runtime_req.needs_strings    = true;
        if (emit_printf_intrinsic(node, dest_reg)) {
            return 1;
        }
    }

    // system.halt
    if (strcmp(func_name, "system.halt") == 0) {
        emit_system_halt_intrinsic();
        return 1;
    }

    // system.wait / ioports.gpu.sync
    if (strcmp(func_name, "system.wait") == 0 ) {
        emit_system_wait_intrinsic();
        return 1;
    }

    // NEW: hard error for any other system.* call. Without this, an
    // unrecognized system.foo() -- like every other dotted call --
    // desugars to a NODE_TABLE_GET target, which skips the generic
    // "Undeclared function" check in node_function_call() and silently
    // miscompiles into a dynamic lookup against a "system" global table
    // that doesn't exist. See AUDIT_string_functionality.md section 2 for
    // the full explanation (written against string.*, but the mechanism
    // is identical for every dotted prefix handled in this function).
    if (strncmp(func_name, "system.", 7) == 0) {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "Unknown system function '%s'", func_name);
        return 0;
    }

    // hex("0x...")
    if (strcmp(func_name, "hex") == 0) {
        return emit_hex_intrinsic(node, dest_reg);
    }

    //////////////////////////////////////////////////////////////////////////
    //
    // PICO-8 API
    //
    //////////////////////////////////////////////////////////////////////////

    // spr()
    if (strcmp(func_name, "spr") == 0) {
        if (runtime_req.needs_pico8 == true)
        {
            return (emit_pico8_spr_intrinsic (node));
        }
        else if (runtime_req.needs_tic80 == true)
        {
            return (emit_tic80_spr_intrinsic (node));
        }
    }

    // btn()
    if (strcmp (func_name, "btn") == 0) {
        if (runtime_req.needs_pico8 == true)
        {
            return (emit_pico8_btn_intrinsic (node, dest_reg));
        }
        else if (runtime_req.needs_tic80 == true)
        {
            return (emit_tic80_btn_intrinsic (node, dest_reg));
        }
    }

    // btnp()
    if (strcmp (func_name, "btnp") == 0) {
        if (runtime_req.needs_pico8 == true)
        {
            return (emit_pico8_btnp_intrinsic (node, dest_reg));
            return (0);
        }
        else if (runtime_req.needs_tic80 == true)
        {
            return (emit_tic80_btnp_intrinsic (node, dest_reg));
        }
    }

    // add()
    if (strcmp (func_name, "add") == 0) {
        if (runtime_req.needs_pico8 == true)
        {
            return (emit_pico8_add_intrinsic (node, dest_reg));
        }
    }

    // TIC-80 cls()
    if (strcmp(func_name, "cls") == 0) {
        if (runtime_req.needs_tic80 == true)
        {
            return emit_tic80_cls_intrinsic(node);
        }
        else if (runtime_req.needs_pico8 == true)
        {
            return (emit_pico8_add_intrinsic (node, dest_reg));
        }
    }

    // TIC-80 mget()
    if (strcmp(func_name, "mget") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_mget_intrinsic(node, dest_reg);
        }
        else if (runtime_req.needs_pico8 == true) {
            return emit_pico8_mget_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 mset()
    if (strcmp(func_name, "mset") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_mset_intrinsic(node, dest_reg);
        }
        else if (runtime_req.needs_pico8 == true) {
            return emit_pico8_mset_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 map()
    if (strcmp(func_name, "map") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_map_intrinsic(node);
        }
        else if (runtime_req.needs_pico8 == true) {
            return emit_pico8_map_intrinsic(node);
        }
    }

    // play()
    if (strcmp(func_name, "play") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_play_intrinsic(node, dest_reg);
        }
    }

    // sfx()
    if (strcmp(func_name, "sfx") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_sfx_intrinsic(node, dest_reg);
        }
    }

    // music()
    if (strcmp(func_name, "music") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_music_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 pmem()
    if (strcmp(func_name, "pmem") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_pmem_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 fget() - sprite flags
    if (strcmp(func_name, "fget") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_fget_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 fset() - sprite flags
    if (strcmp(func_name, "fset") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_fset_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 sync() -- Vircon32 has no cart memory banks, so this is a
    // deliberate no-op. Arguments are still evaluated for side effects
    // (Lua semantics), just never used.
    if (strcmp(func_name, "sync") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_sync_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 pix() -- set/read a single pixel
    if (strcmp(func_name, "pix") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_pix_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 line()
    if (strcmp(func_name, "line") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_line_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 rect() -- filled rectangle
    if (strcmp(func_name, "rect") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_rect_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 rectb() -- rectangle border
    if (strcmp(func_name, "rectb") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_rectb_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 circ() -- filled circle
    if (strcmp(func_name, "circ") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_circ_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 circb() -- circle border only
    if (strcmp(func_name, "circb") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_circb_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 time() -- returns milliseconds since cartridge began execution
    if (strcmp(func_name, "time") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_time_intrinsic(node, dest_reg);
        }
    }

    // TIC-80 exit() -- request the cart stop after the current frame
    if (strcmp(func_name, "exit") == 0) {
        if (runtime_req.needs_tic80 == true) {
            return emit_tic80_exit_intrinsic(node, dest_reg);
        }
    }

    //////////////////////////////////////////////////////////////////////////
    //
    // string library intrinsics
    //
    //////////////////////////////////////////////////////////////////////////

    // check if strings are used (include runtime routines)
    if (strncmp (func_name, "string.", 7) == 0)
    {
        runtime_req.needs_strings          = true;
    }

    // string.byte(s [, i [, j]])
    if (strcmp (func_name, "string.byte") == 0)
    {
        return emit_string_byte_intrinsic(node, dest_reg);
    }

    // string.char(b1, b2, ..., bn)
    if (strcmp (func_name, "string.char") == 0)
    {
        return emit_string_char_intrinsic(node, dest_reg);
    }

    // Core type conversion
    if (strcmp (func_name, "tostring")    == 0)
    {
        runtime_req.needs_strings          = true;
        return emit_tostring_intrinsic(node, dest_reg);
    }

    // string.format(format, ...)
    if (strcmp(func_name, "string.format") == 0)
    {
        runtime_req.needs_strings = true;
        return emit_string_format_intrinsic(node, dest_reg);
    }

    // NEW: string.len(s) -- the runtime routine (__builtin_string_len)
    // already existed and is correct (it's what the # operator calls);
    // it was simply never reachable from string.len(...) call syntax.
    if (strcmp(func_name, "string.len") == 0)
    {
        return emit_string_len_intrinsic(node, dest_reg);
    }

    // NEW: string.sub(s, i [, j])
    if (strcmp(func_name, "string.sub") == 0)
    {
        return emit_string_sub_intrinsic(node, dest_reg);
    }

    // NEW: string.upper(s)
    if (strcmp(func_name, "string.upper") == 0)
    {
        return emit_string_upper_intrinsic(node, dest_reg);
    }

    // NEW: string.lower(s)
    if (strcmp(func_name, "string.lower") == 0)
    {
        return emit_string_lower_intrinsic(node, dest_reg);
    }

    // NEW: string.rep(s, n)
    if (strcmp(func_name, "string.rep") == 0)
    {
        return emit_string_rep_intrinsic(node, dest_reg);
    }

    // NEW: string.reverse(s)
    if (strcmp(func_name, "string.reverse") == 0)
    {
        return emit_string_reverse_intrinsic(node, dest_reg);
    }

    // NEW: string.find(s, pattern) -- PLAIN substring search only, no Lua
    // pattern magic characters, no init/plain-flag arguments. See the
    // header comment on emit_string_find_intrinsic() below.
    if (strcmp(func_name, "string.find") == 0)
    {
        return emit_string_find_intrinsic(node, dest_reg);
    }

    // NEW: string.gsub(s, pattern, repl) -- PLAIN substring replacement
    // only, single return value (no substitution count, no n-limit). See
    // the header comment on emit_string_gsub_intrinsic() below.
    if (strcmp(func_name, "string.gsub") == 0)
    {
        return emit_string_gsub_intrinsic(node, dest_reg);
    }

    // NEW: hard error for any remaining string.* call -- covers typos,
    // and (until they're implemented) string.match/string.gmatch. See
    // AUDIT_string_functionality.md section 2. This must stay AFTER every
    // recognized string.* case above and BEFORE the math.* section below.
    if (strncmp(func_name, "string.", 7) == 0)
    {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "Unknown string method '%s'", func_name);
        return 0;
    }

    //////////////////////////////////////////////////////////////////////////
    //
    // math library intrinsics
    //
    //////////////////////////////////////////////////////////////////////////

    // check if math is used (include runtime routines)
    if (strncmp (func_name, "math.", 5) == 0)
    {
        runtime_req.needs_math           = true;
    }

    // math.sin(x)
    if (strcmp(func_name, "math.sin")   == 0) {
        return emit_math_sin_intrinsic(node, dest_reg);
    }

    // math.abs(x)
    if (strcmp(func_name, "math.abs")   == 0) {
        return emit_math_abs_intrinsic(node, dest_reg);
    }

    // math.ceil(x)
    if (strcmp(func_name, "math.ceil")  == 0) {
        return emit_math_ceil_intrinsic(node, dest_reg);
    }

    // math.acos(x)
    if (strcmp(func_name, "math.acos")  == 0) {
        return emit_math_acos_intrinsic(node, dest_reg);
    }

    // math.log(x)
    if (strcmp(func_name, "math.log")   == 0) {
        return emit_math_log_intrinsic(node, dest_reg);
    }

    // math.pow(x, y)
    if (strcmp(func_name, "math.pow")   == 0) {
        return emit_math_pow_intrinsic(node, dest_reg);
    }

    // math.atan2(y, x)
    if (strcmp(func_name, "math.atan2") == 0) {
        return emit_math_atan2_intrinsic(node, dest_reg);
    }

    // math.floor(x)
    if (strcmp(func_name, "math.floor") == 0) {
        return emit_math_floor_intrinsic(node, dest_reg);
    }

    // math.sqrt(x)
    if (strcmp(func_name, "math.sqrt")   == 0) {
        return emit_math_sqrt_intrinsic(node, dest_reg);
    }

    // math.random([m[, n]])
    if (strcmp(func_name, "math.random") == 0) {
        return emit_math_random_intrinsic(node, dest_reg);
    }

    // math.randomseed(x)
    if (strcmp(func_name, "math.randomseed") == 0) {
        return emit_math_randomseed_intrinsic(node, dest_reg);
    }

    // math.cos(x)
    if (strcmp(func_name, "math.cos") == 0) {
        return emit_math_cos_intrinsic(node, dest_reg);
    }

    // math.atan(x)
    if (strcmp(func_name, "math.atan") == 0) {
        return emit_math_atan_intrinsic(node, dest_reg);
    }

    // math.exp(x)
    if (strcmp(func_name, "math.exp") == 0) {
        return emit_math_exp_intrinsic(node, dest_reg);
    }

    // math.fmod(x, y)
    if (strcmp(func_name, "math.fmod") == 0) {
        return emit_math_fmod_intrinsic(node, dest_reg);
    }

    // math.max(x, y)
    if (strcmp(func_name, "math.max") == 0) {
        return emit_math_max_intrinsic(node, dest_reg);
    }

    // math.min(x, y)
    if (strcmp(func_name, "math.min") == 0) {
        return emit_math_min_intrinsic(node, dest_reg);
    }

    // math.asin(x)
    if (strcmp(func_name, "math.asin") == 0) {
        return emit_math_asin_intrinsic(node, dest_reg);
    }

    // math.tan(x)
    if (strcmp(func_name, "math.tan") == 0) {
        return emit_math_tan_intrinsic(node, dest_reg);
    }

    // math.deg(x)
    if (strcmp(func_name, "math.deg") == 0) {
        return emit_math_deg_intrinsic(node, dest_reg);
    }

    // math.rad(x)
    if (strcmp(func_name, "math.rad") == 0) {
        return emit_math_rad_intrinsic(node, dest_reg);
    }

    // math.log10(x)
    if (strcmp(func_name, "math.log10") == 0) {
        return emit_math_log10_intrinsic(node, dest_reg);
    }

    // math.cosh(x)
    if (strcmp(func_name, "math.cosh") == 0) {
        return emit_math_cosh_intrinsic(node, dest_reg);
    }

    // math.sinh(x)
    if (strcmp(func_name, "math.sinh") == 0) {
        return emit_math_sinh_intrinsic(node, dest_reg);
    }

    // math.tanh(x)
    if (strcmp(func_name, "math.tanh") == 0) {
        return emit_math_tanh_intrinsic(node, dest_reg);
    }

    // math.frexp(x)
    if (strcmp(func_name, "math.frexp") == 0) {
        int ret_count = emit_math_frexp_intrinsic(node, dest_reg);
        if (ret_count > 0) {
            // Store return count in node for multiple assignment handling
            node->as.call.return_count = ret_count;
            return ret_count;
        }
        return 0;
    }

    // math.ldexp(x)
    if (strcmp(func_name, "math.ldexp") == 0) {
        int ret_count = emit_math_ldexp_intrinsic(node, dest_reg);
        if (ret_count > 0) {
            // Store return count in node for multiple assignment handling
            node->as.call.return_count = ret_count;
            return ret_count;
        }
        return 0;
    }

    // math.modf(x)
    if (strcmp(func_name, "math.modf") == 0) {
        int ret_count = emit_math_modf_intrinsic(node, dest_reg);
        if (ret_count > 0) {
            // Store return count in node for multiple assignment handling
            node->as.call.return_count = ret_count;
            return ret_count;
        }
        return 0;
    }

    // NEW: hard error for any remaining math.* call -- same rationale as
    // the string.* guard above. Must stay AFTER every recognized math.*
    // case and BEFORE pairs/ipairs/type/table.* below.
    if (strncmp(func_name, "math.", 5) == 0)
    {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "Unknown math function '%s'", func_name);
        return 0;
    }

    // loop iters
    if (strcmp(func_name, "pairs") == 0) {
        return emit_pairs_intrinsic(node);
    }
    if (strcmp(func_name, "ipairs") == 0) {
        return emit_ipairs_intrinsic(node);
    }

    // type(x)
    if (strcmp(func_name, "type") == 0) {
        return emit_type_intrinsic(node, dest_reg);
    }

    // tables

    if (strcmp(func_name, "table.insert") == 0) {
        return emit_table_insert_intrinsic(node, dest_reg);
    }

    if (strcmp(func_name, "table.remove") == 0) {
        return emit_table_remove_intrinsic(node, dest_reg);
    }

    if (strcmp(func_name, "table.pack") == 0) {
        return emit_table_pack_intrinsic(node, dest_reg);
    }

    // NEW: hard error for any remaining table.* call -- same rationale as
    // the string.* guard above.
    if (strncmp(func_name, "table.", 6) == 0)
    {
        compiler_error(ERR_SEMANTIC, node->line_number,
            "Unknown table function '%s'", func_name);
        return 0;
    }

    return 0; // Not an intrinsic
}

// Returns 1 if hardware intrinsic was emitted, 0 if dynamic table fallback is required.
int try_emit_table_set_intrinsic(ASTNode *table_expr, ASTNode *key_expr, ASTNode *val_node) {
    char base_path[256] = {0};

    // FIX: Add NULL checks for key_expr and val_node
    if (!resolve_static_path(table_expr, base_path) || 
        key_expr == NULL || key_expr->type != NODE_STRING || val_node == NULL) {
        return 0;
    }

    // Validate ioports path structure
    validate_ioports_path(base_path, key_expr->as.string_val.value, yylineno);

    char full_path[512];
    snprintf(full_path, sizeof(full_path), "%s.%s", base_path, key_expr->as.string_val.value);

    for (int i = 0; ioports[i].lua_path != NULL; i++) {
        if (strcmp(full_path, ioports[i].lua_path) == 0) {
            if ((ioports[i].mode & IOPORT_WRITE) != IOPORT_WRITE) {
                compiler_error(ERR_SEMANTIC, yylineno, "%s: port cannot be written to", full_path);
            }

            bool is_raw = is_raw_integer_expression(val_node);

            // Handle immediate operands or allocate register for value
            char imm_str[64];
            if (is_raw && try_get_immediate_operand(val_node, imm_str, sizeof(imm_str))) {
                emit_asm("    ;; --- Intrinsic: Direct Immediate Hardware Write (%s) ---\n", full_path);
                emit_asm("OUT %s, %s\n", ioports[i].asm_port, imm_str);
                return 1;
            }

            // On-demand register evaluation
            int val_reg = allocate_register();
            register_pinned[val_reg] = 1;
            generate_asm(val_node, val_reg);

            int needs_cast = !is_raw && (ioports[i].type & (IOPORT_TYPE_INTEGER | IOPORT_TYPE_BOOLEAN));
            int out_reg = val_reg;

            if (needs_cast) {
                out_reg = allocate_register();
                register_pinned[out_reg] = 1;
                emit_asm("MOV R%d, R%d ; Copy value for hardware type cast\n", out_reg, val_reg);

                if ((ioports[i].type & IOPORT_TYPE_INTEGER) == IOPORT_TYPE_INTEGER) {
                    emit_asm("    ;; --- Intrinsic: Cast Lua Float to Hardware Integer ---\n");
                    emit_asm("CFI R%d\n", out_reg);
                } else if ((ioports[i].type & IOPORT_TYPE_BOOLEAN) == IOPORT_TYPE_BOOLEAN) {
                    emit_asm("    ;; --- Intrinsic: Cast Lua Float to Hardware Boolean ---\n");
                    emit_asm("CFB R%d\n", out_reg);
                }
            }

            if (is_raw) {
                emit_asm("    ;; --- Intrinsic: Direct Raw Hardware Write (%s) ---\n", full_path);
            }
            emit_asm("OUT %s, R%d\n", ioports[i].asm_port, out_reg);

            if (needs_cast) {
                register_pinned[out_reg] = 0;
                unlock_register(out_reg);
            }
            register_pinned[val_reg] = 0;
            unlock_register(val_reg);

            return 1;
        }
    }

    // Category was valid but property not found - emit specific error
    if (strncmp(base_path, "ioports.", 8) == 0) {
        compiler_error(ERR_SEMANTIC, yylineno,
            "Unknown ioports property '%s.%s'", base_path, key_expr->as.string_val.value);
    }

    // Not a hardware port; fall back to dynamic heap table assignment
    return 0;
}

int try_emit_table_get_intrinsic(ASTNode *table_expr, ASTNode *key_expr, int dest_reg) {
    char base_path[256];

    if (!resolve_static_path(table_expr, base_path) ||
        key_expr == NULL || key_expr->type != NODE_STRING) {
        return 0;
    }

    // --- Compile-time math constants: math.pi / math.e / math.huge ---
    // These are plain property reads, not function calls, so they never
    // went through the math.* dispatcher used for math.sin()/math.cos().
    // Without this branch they'd fall through to the generic dynamic
    // table lookup below, which tries to read a "math" table out of the
    // global var_math slot -- a slot nothing in this compiler ever
    // initializes, since there's no real Lua table backing the math
    // library. That read fails __builtin_table_get's type check and
    // traps the whole VM (__runtime_error_not_table -> HLT). Resolve
    // these directly as ROM constant loads instead, the same way
    // math.sin()/math.cos() are resolved as intrinsics rather than real
    // function calls.
    if (strcmp (base_path, "math") == 0) {
        const char *key = key_expr->as.string_val.value;

        if (strcmp (key, "pi") == 0 || strcmp (key, "e") == 0 || strcmp (key, "huge") == 0) {
            runtime_req.needs_math = true;

            if (dest_reg != 0) {
                emit_asm ("    ;; --- Intrinsic: math.%s (constant) ---\n", key);
                emit_asm ("    MOV R%d, [__const_math_%s]\n", dest_reg, key);
            }
            return 1;
        }

        // --- Bare reference to a math function (not a call): box a real
        // callable label instead of falling through to a table lookup
        // against a "math" table that doesn't actually exist at runtime.
        // See __mathfn_sin / __mathfn_log / __mathfn_atan2 in runtime_s.txt.
        // math.cos reuses __builtin_cos directly -- same calling
        // convention already, no wrapper needed.
        const char *label = NULL;
        if      (strcmp (key, "sin")    == 0) label = "__mathfn_sin";
        else if (strcmp (key, "log")    == 0) label = "__mathfn_log";
        else if (strcmp (key, "atan2")  == 0) label = "__mathfn_atan2";
        else if (strcmp (key, "cos")    == 0) label = "__builtin_cos";

        if (label != NULL) {
            runtime_req.needs_math = true;

            if (dest_reg != 0) {
                emit_asm ("    ;; --- math.%s (function value, not called) ---\n", key);
                emit_asm ("    MOV R%d, %s\n", dest_reg, label);
                emit_asm ("    OR  R%d, BOXED_FUNCTION ; Box as Function\n", dest_reg);
            }
            return 1;
        }
    }

    // Build full path first
    char full_path[512];
    snprintf(full_path, sizeof(full_path), "%s.%s", base_path, key_expr->as.string_val.value);

    // Validate ioports path structure (for error messages only)
    validate_ioports_path(base_path, key_expr->as.string_val.value, yylineno);

    // Scan ENTIRE IOPortMap table for a match
    for (int i = 0; ioports[i].lua_path != NULL; i++) {
        if (strcmp(full_path, ioports[i].lua_path) == 0) {
            if ((ioports[i].mode & IOPORT_READ) != IOPORT_READ) {
                compiler_error(ERR_SEMANTIC, yylineno, "%s: port cannot be read from", full_path);
            }

            if ((ioports[i].mode & IOPORT_ACTION) == IOPORT_ACTION) {
                try_emit_action_intrinsic(ioports[i].asm_port, dest_reg);
                return 1;
            }

            if (dest_reg != 0) {
                if ((ioports[i].type & IOPORT_TYPE_INTEGER) == IOPORT_TYPE_INTEGER) {
                    emit_asm("    ;; --- Intrinsic: Read Hardware Integer (%s) ---\n", full_path);
                    emit_asm("    IN R%d, %s\n", dest_reg, ioports[i].asm_port);
                    emit_asm("    CIF R%d ; Cast hardware int to Lua float\n", dest_reg);
                }
                else if ((ioports[i].type & IOPORT_TYPE_BOOLEAN) == IOPORT_TYPE_BOOLEAN) {
                    emit_asm("    ;; --- Intrinsic: Read Hardware Boolean (%s) ---\n", full_path);
                    emit_asm("    IN R%d, %s\n", dest_reg, ioports[i].asm_port);
                    emit_asm("    CIF R%d ; Cast hardware bool to Lua float\n", dest_reg);
                }
                else {
                    emit_asm("    ;; --- Intrinsic: Read Hardware Float (%s) ---\n", full_path);
                    emit_asm("    IN R%d, %s\n", dest_reg, ioports[i].asm_port);
                }
            }
            return 1;
        }
    }

    // ioports-specific error for invalid properties
    if (strncmp(base_path, "ioports.", 8) == 0) {
        compiler_error(ERR_SEMANTIC, yylineno,
            "Unknown ioports property '%s.%s'", base_path, key_expr->as.string_val.value);
        return 0;
    }

    return 0; // Not a hardware port; fallback to dynamic lookup
}

bool emit_type_intrinsic(ASTNode *node, int dest_reg) {
    ASTNode *arg = node->as.call.args_head;

    // === DEBUG: Show what we actually parsed ===
    fprintf(stderr, "[debug] emit_type_intrinsic(): args_head = %p\n", (void*)arg);
    if (arg) {
        fprintf(stderr, "[debug] emit_type_intrinsic(): arg->type = %d, arg->next = %p\n",
                arg->type, (void*)arg->next);
    }

    if (!arg || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "type() expects exactly 1 argument");
        return false;
    }

    emit_asm("    ;; --- Intrinsic: type(value) ---\n");

    int arg_reg = allocate_register();  // Regular register is fine
    generate_asm(arg, arg_reg);

    emit_asm("    PUSH R%d             ; Arg 1: Value to check\n", arg_reg);
    emit_asm("    CALL __builtin_type\n");
    emit_asm("    IADD SP, 1           ; Clean up 1 argument\n");

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, R0         ; Store string result\n", dest_reg);
    }

    unlock_register(arg_reg);
    return true;
}
