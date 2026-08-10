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

	//////////////////////////////////////////////////////////////////////////
	//
	// string library intrinsics
	//
	//////////////////////////////////////////////////////////////////////////

	// string.byte(s [, i [, j]])
	if (strcmp(func_name, "string.byte") == 0) {
		return emit_string_byte_intrinsic(node, dest_reg);
	}

	// string.char(b1, b2, ..., bn)
	if (strcmp(func_name, "string.char") == 0) {
		return emit_string_char_intrinsic(node, dest_reg);
	}

	//////////////////////////////////////////////////////////////////////////
	//
	// math library intrinsics
	//
	//////////////////////////////////////////////////////////////////////////

    // math.floor(x)
    if (strcmp(func_name, "math.floor") == 0) {
        return emit_math_floor_intrinsic(node, dest_reg);
    }

    // math.sqrt(x)
    if (strcmp(func_name, "math.sqrt") == 0) {
        return emit_math_sqrt_intrinsic(node, dest_reg);
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
