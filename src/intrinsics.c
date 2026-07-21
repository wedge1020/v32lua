#include "v32lua.h"

// ============================================================================
// --- Internal IO Port Mapping Table ---
// ============================================================================
const IOPortMap ioports[] = {
    { "ioports.tim.date",      "TIM_CurrentDate",          IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "system.date",           "TIM_CurrentDate",          IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.tim.time",      "TIM_CurrentTime",          IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "system.time",           "TIM_CurrentTime",          IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.time.frames",   "TIM_FrameCounter",         IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "system.frames",         "TIM_FrameCounter",         IOPORT_READ,                 IOPORT_TYPE_INTEGER },
    { "ioports.time.cycles",   "TIM_CycleCounter",         IOPORT_READ,                 IOPORT_TYPE_INTEGER },
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

static void  emit_spu_cmd_intrinsic (ASTNode *node, int  dest_reg)
{
    if (node != NULL)
        dest_reg  = dest_reg;
}

static void  emit_system_wait_intrinsic ()
{
    emit_asm ("WAIT\n");
}

static void  emit_system_halt_intrinsic ()
{
    emit_asm ("HLT\n");
}

// ============================================================================
// --- Static Helper Functions for Complex Calls ---
// ============================================================================

static void  emit_print_intrinsic (ASTNode *node)
{
    // 1. Extract the 3 positional arguments from the argument linked list
    ASTNode *arg_x   = node->as.call.args_head;
    ASTNode *arg_y   = (arg_x != NULL) ? arg_x->next : NULL;
    ASTNode *arg_val = (arg_y != NULL) ? arg_y->next : NULL;

    // Basic semantic validation to protect against malformed user scripts
    if (arg_x == NULL || arg_y == NULL || arg_val == NULL) {
        compiler_error(ERR_SEMANTIC, node->line_number, 
                       "print() intrinsic requires 3 arguments: print(x, y, value)");
    }

    // 2. Allocate registers and evaluate each argument expression
    int reg_x = allocate_register();
    generate_asm(arg_x, reg_x);

    int reg_y = allocate_register();
    generate_asm(arg_y, reg_y);

    int reg_val = allocate_register();
    generate_asm(arg_val, reg_val);

    emit_asm ("    ;; --- Intrinsic: print(x, y, value) ---\n");

    // 3. Convert text coordinates from Lua Floats to Hardware Integers
    // Because all numbers in your compiler are floats, we must cast 
    // screen spaces using the Vircon32 'CFI' (Cast Float to Integer) instruction.
    emit_asm ("CFI R%d ; Convert X to hardware integer\n", reg_x);
    emit_asm ("CFI R%d ; Convert Y to hardware integer\n", reg_y);

    // 4. Push arguments to the stack (Left-to-Right layout)
    emit_asm ("PUSH R%d ; Push X coordinate\n", reg_x);
    emit_asm ("PUSH R%d ; Push Y coordinate\n", reg_y);
    emit_asm ("PUSH R%d ; Push raw value to convert\n", reg_val);

    // 5. Coerce the value to a string pointer
    // Because value was pushed last, it is safely resting on top of the stack [SP].
    // __builtin_tostring will process it and return the string address in R0.
    emit_asm ("CALL __builtin_tostring\n"); 
    emit_asm ("MOV  [SP], R0 ; Overwrite raw value with the string pointer\n");

    // 6. Fire the printing routine and tear down the stack frame
    emit_asm ("CALL __builtin_print\n");    
    emit_asm ("ISUB SP, 3 ; Clean up x, y, and string from the stack\n");

    // 7. Unlock registers back to the compiler pool
    unlock_register (reg_val);
    unlock_register (reg_y);
    unlock_register (reg_x);
}

static void emit_gpu_blending_intrinsic (ASTNode *node, int  dest_reg)
{
    emit_asm ("    ;; --- Intrinsic: ioports.gpu.blending() ---\n");
    ASTNode *arg = node -> as.call.args_head;

    if (arg != NULL && arg -> type == NODE_STRING)
    {
        const char *blendmode = arg -> as.string_val.value;
        if (strcmp (blendmode, "alpha") == 0)
            emit_asm ("OUT GPU_ActiveBlending, GPUBlendingMode_Alpha\n");
        else if (strcmp (blendmode, "add") == 0)
            emit_asm ("OUT GPU_ActiveBlending, GPUBlendingMode_Add\n");
        else if (strcmp (blendmode, "subtract") == 0)
            emit_asm ("OUT GPU_ActiveBlending, GPUBlendingMode_Subtract\n");
        else
            compiler_error (ERR_SEMANTIC, yylineno, "%s: invalid blending mode '%s'", "ioports.gpu.blending()", blendmode);
    }
    else
    {
        compiler_error (ERR_SEMANTIC, yylineno, "%s: invalid blending mode", "ioports.gpu.blending()");
    }

    if (dest_reg != 0) {
        emit_asm ("    MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
    }
}

bool emit_gpu_draw_intrinsic(ASTNode *node, int dest_reg) {
    char path_buf[256] = {0};

    if (!resolve_static_path(node->as.call.target, path_buf)) {
        return false;
    }

    if (strcmp(path_buf, "ioports.gpu.draw") != 0) {
        return false;
    }

    ASTNode *arg = node -> as.call.args_head;

    // =========================================================================
    // FAST PATH 1: Omitted argument -> ioports.gpu.draw()
    // =========================================================================
    if (arg == NULL) {
        emit_asm("    ;; Intrinsic: ioports.gpu.draw() [Fast-path default]\n");
        emit_asm("OUT GPU_Command, GPUCommand_DrawRegion\n");
        if (dest_reg >= 0) {
            emit_asm("MOV R%d, 0x%08X ; Return true\n", dest_reg, BOXED_TRUE);
        }
        return true;
    }

    // =========================================================================
    // FAST PATH 2: Static String Literal -> ioports.gpu.draw("zoom")
    // =========================================================================
    if (arg->type == NODE_STRING) {
        const char *val = arg->as.string_val.value;
        bool valid = true;

        emit_asm("    ;; Intrinsic: ioports.gpu.draw(\"%s\") [Static fast-path]\n", val);
        if (strcmp(val, "draw") == 0) {
            emit_asm("OUT GPU_Command, GPUCommand_DrawRegion\n");
        } else if (strcmp(val, "zoom") == 0) {
            emit_asm("OUT GPU_Command, GPUCommand_DrawRegionZoomed\n");
        } else if (strcmp(val, "rotate") == 0) {
            emit_asm("OUT GPU_Command, GPUCommand_DrawRegionRotated\n");
        } else if (strcmp(val, "rotozoom") == 0) {
            emit_asm("OUT GPU_Command, GPUCommand_DrawRegionRotozoomed\n");
        } else {
            compiler_error (ERR_SEMANTIC, yylineno, "%s: invalid draw mode '%s'", "ioports.gpu.draw()", val);
        }

        if (dest_reg >= 0)
        {
            emit_asm("MOV R%d, 0x%08X ; Return %s\n", dest_reg, valid ? BOXED_TRUE : BOXED_FALSE, valid ? "true" : "false");
        }
        return true;
    }

    // =========================================================================
    // RUNTIME PATH: Dynamic argument via NaN-Boxed Pointer Equality
    // =========================================================================
    int mode_reg = allocate_register();
    generate_asm(arg, mode_reg);

    int label_id = get_next_label();
    const char *ctx = get_current_function_name();
    
    char lbl_zoom[128], lbl_rot[128], lbl_rotozoom[128], lbl_default[128], lbl_end[128];
    snprintf(lbl_default, sizeof(lbl_default), "__%s_draw_default_%d", ctx, label_id);
    snprintf(lbl_zoom, sizeof(lbl_zoom), "__%s_draw_zoom_%d", ctx, label_id);
    snprintf(lbl_rot, sizeof(lbl_rot), "__%s_draw_rot_%d", ctx, label_id);
    snprintf(lbl_rotozoom, sizeof(lbl_rotozoom), "__%s_draw_rotozoom_%d", ctx, label_id);
    snprintf(lbl_end, sizeof(lbl_end), "__%s_draw_end_%d", ctx, label_id);

    emit_asm("    ;; Intrinsic: ioports.gpu.draw(dynamic_arg) [NaN-boxed dispatch]\n");
    
    // 1. Check for Nil -> default draw
    emit_asm("IEQ R%d, 0x%08X ; Is mode nil?\n", mode_reg, BOXED_NIL);
    emit_asm("JT R%d, %s\n", mode_reg, lbl_default);

    int  sid  = add_string_literal ("draw");

    int  treg  = allocate_register ();
    // 2. Direct NaN-boxed pointer/ID comparisons!
    // (Assuming your compiler can emit symbols or known constants for ROM string literals)
    emit_asm ("MOV R%d, __string_%d ; load string into tmp register\n", treg, sid);
    emit_asm("IEQ R%d, R%d ; Compare against boxed \"draw\" pointer\n", mode_reg, treg);
    emit_asm("JT R%d, %s\n", mode_reg, lbl_default);

    sid  = add_string_literal ("zoom");
    emit_asm ("MOV R%d, __string_%d ; load string into tmp register\n", treg, sid);
    emit_asm("IEQ R%d, R%d ; Compare against boxed \"zoom\" pointer\n", mode_reg, treg);
    emit_asm("JT R%d, %s\n", mode_reg, lbl_zoom);

    sid  = add_string_literal ("rotate");
    emit_asm ("MOV R%d, __string_%d ; load string into tmp register\n", treg, sid);
    emit_asm("IEQ R%d, R%d ; Compare against boxed \"rotate\" pointer\n", mode_reg, treg);
    emit_asm("JT R%d, %s\n", mode_reg, lbl_rot);

    sid  = add_string_literal ("rotozoom");
    emit_asm ("MOV R%d, __string_%d ; load string into tmp register\n", treg, sid);
    emit_asm("IEQ R%d, R%d ; Compare against boxed \"rotozoom\" pointer\n", mode_reg, treg);
    emit_asm("JT R%d, %s\n", mode_reg, lbl_rotozoom);

    // 3. Invalid Mode Fallthrough -> Return false
    emit_asm("    ;; Unrecognized dynamic mode -> do not draw, return false\n");
    if (dest_reg >= 0) {
        emit_asm("MOV R%d, 0x%08X ; Return false\n", dest_reg, BOXED_FALSE);
    }
    emit_asm("JMP %s\n", lbl_end);

    // =========================================================================
    // HARDWARE COMMAND EMISSION BLOCKS (All return true)
    // =========================================================================
    emit_asm("%s:\n", lbl_default);
    emit_asm("OUT GPU_Command, GPUCommand_DrawRegion\n");
    if (dest_reg >= 0) emit_asm("MOV R%d, 0x%08X ; Return true\n", dest_reg, BOXED_TRUE);
    emit_asm("JMP %s\n", lbl_end);

    emit_asm("%s:\n", lbl_zoom);
    emit_asm("OUT GPU_Command, GPUCommand_DrawRegionZoomed\n");
    if (dest_reg >= 0) emit_asm("MOV R%d, 0x%08X ; Return true\n", dest_reg, BOXED_TRUE);
    emit_asm("JMP %s\n", lbl_end);

    emit_asm("%s:\n", lbl_rot);
    emit_asm("OUT GPU_Command, GPUCommand_DrawRegionRotated\n");
    if (dest_reg >= 0) emit_asm("MOV R%d, 0x%08X ; Return true\n", dest_reg, BOXED_TRUE);
    emit_asm("JMP %s\n", lbl_end);

    emit_asm("%s:\n", lbl_rotozoom);
    emit_asm("OUT GPU_Command, GPUCommand_DrawRegionRotozoomed\n");
    if (dest_reg >= 0) emit_asm("MOV R%d, 0x%08X ; Return true\n", dest_reg, BOXED_TRUE);

    emit_asm("%s:\n", lbl_end);

    unlock_register(mode_reg);
    return true;
}

void emit_gpu_clear_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm ("    ;; --- Intrinsic: ioports.gpu.clear() ---\n");
    ASTNode *arg = node->as.call.args_head;

    if (arg != NULL) {
        int color_reg = allocate_register();
        if (arg->type == NODE_STRING) {
            const char *color_name = arg->as.string_val.value;
            unsigned int color_hex = 0x000000FF; // Default Opaque Black
            int is_preset = 1;

            if      (strcmp(color_name, "black") == 0) color_hex = 0xFF000000; 
            else if (strcmp(color_name, "white") == 0) color_hex = 0xFFFFFFFF;
            else if (strcmp(color_name, "blue") == 0)  color_hex = 0xFFFF0000;
            else if (strcmp(color_name, "red") == 0)   color_hex = 0xFF0000FF;
            else if (strcmp(color_name, "green") == 0) color_hex = 0xFF00FF00;
            else is_preset = 0; 
            
            if (is_preset) {
                emit_asm ("MOV R%d, 0x%.8X ; Preset color '%s'\n", color_reg, color_hex, color_name);
            } else {
                generate_asm(arg, color_reg);
            }
        } else {
            generate_asm(arg, color_reg);
        }
        emit_asm ("OUT GPU_ClearColor, R%d\n", color_reg);
        unlock_register(color_reg);
    }

    emit_asm ("OUT GPU_Command, GPUCommand_ClearScreen\n");
    if (dest_reg != 0) {
        emit_asm ("MOV R%d, BOXED_NIL ; return nil\n", dest_reg);
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

int   try_emit_call_intrinsic (ASTNode *node, int  dest_reg)
{
    char  func_name[256] = {0};
    if (!resolve_static_path (node -> as.call.target, func_name))
    {
        return (0); // Dynamic call, not an intrinsic
    }

    if (strcmp (func_name, "print")             == 0)
    {
        emit_print_intrinsic (node);
        return (1);
    }
    if (strcmp (func_name, "ioports.gpu.draw")  == 0)
    {
        emit_gpu_draw_intrinsic (node, dest_reg);
        return (1);
    }
    if (strcmp (func_name, "ioports.gpu.blending")  == 0)
    {
        emit_gpu_blending_intrinsic (node, dest_reg);
        return (1);
    }
    if (strcmp (func_name, "ioports.gpu.clear") == 0)
    {
        emit_gpu_clear_intrinsic (node, dest_reg);
        return (1);
    }
    if (strcmp (func_name, "ioports.spu.command")  == 0)
    {
        emit_spu_cmd_intrinsic (node, dest_reg);
        return (1);
    }

    // =========================================================================
    // INTRINSIC: hex("0x...") -> Direct 32-bit Word Load
    // =========================================================================
    if (strcmp (func_name, "hex")                  == 0)
    {
        ASTNode *arg  = node -> as.call.args_head;

        // 1. Strict Compile-Time Argument Validation
        if (!arg || arg->type != NODE_STRING || arg->next != NULL) {
            compiler_error (ERR_SYNTAX, node->line_number,
                           "hex() intrinsic expects exactly one string literal argument (e.g., hex(\"0xFF800000\"))");
        }

        const char *hex_str = arg -> as.string_val.value;

        // 2. Parse Hexadecimal String to Raw 32-Bit Integer
        char *end_ptr = NULL;
        unsigned long raw_val = strtoul (hex_str, &end_ptr, 16);

        // Ensure the entire string was consumed and contains valid hex characters
        if (*end_ptr != '\0' || end_ptr == hex_str) {
            compiler_error(ERR_SYNTAX, node->line_number,
                           "Invalid hexadecimal literal passed to hex(): '%s'", hex_str);
        }

        // 3. Emit Direct Vircon32 Assembly
        // If dest_reg is 0 (value ignored by caller), we emit nothing!
        if (dest_reg != 0) {
            emit_asm("    ;; Intrinsic: hex(\"%s\") -> direct 32-bit word load\n", hex_str);
            emit_asm("MOV R%d, 0x%08lX\n", dest_reg, raw_val);
        }

        return (1); // Signal to codegen that the call was fully resolved
    }

    if (strcmp (func_name, "system.halt")       == 0)
    {
        emit_system_halt_intrinsic ();
        return (1);
    }
    if ((strcmp (func_name, "system.wait")      == 0) ||
        (strcmp (func_name, "ioports.gpu.sync") == 0))
    {
        emit_system_wait_intrinsic ();
        return (1);
    }
    if (strcmp (func_name, "math.abs")          == 0)
    {
        ;
        // load variable value into register, run `FABS` on it, return result
    }
    if (strcmp (func_name, "math.floor")        == 0)
    {
        ;
        // load variable value into register, run `FLR` on it, return result
    }
    if (strcmp (func_name, "math.ceil")         == 0)
    {
        ;
        // load variable value into register, run `CEIL` on it, return result
    }
    if (strcmp (func_name, "math.sqrt")         == 0)
    {
        ;
        // load variable value into register, calculate sqrt, return result
    }

    return (0); // Not handled here
}

// Notice: 'int val_reg' has been removed from the function signature!
int try_emit_table_set_intrinsic(ASTNode *table_expr, ASTNode *key_expr, ASTNode *val_node)
{
    char base_path[256] = {0};

    if (!resolve_static_path(table_expr, base_path) || key_expr->type != NODE_STRING)
    {
        return 0;
    }

    char full_path[512];
    snprintf(full_path, sizeof(full_path), "%s.%s", base_path, key_expr->as.string_val.value);

    for (int i = 0; ioports[i].lua_path != NULL; i++)
    {
        if (strcmp(full_path, ioports[i].lua_path) == 0)
        {
            if ((ioports[i].mode & IOPORT_WRITE) != IOPORT_WRITE)
            {
                compiler_error(ERR_SEMANTIC, yylineno, "%s: port cannot be written to", full_path);
            }

            bool is_raw = is_raw_integer_expression(val_node);

            // ==========================================================
            // PATH A: IMMEDIATE OPERAND FOLDING (Zero Registers Used!)
            // ==========================================================
            char imm_str[64];
            if (is_raw && try_get_immediate_operand(val_node, imm_str, sizeof(imm_str)))
            {
                emit_asm("    ;; --- Intrinsic: Direct Immediate Hardware Write (%s) ---\n", full_path);
                emit_asm("OUT %s, %s\n", ioports[i].asm_port, imm_str);
                return 1;
            }

            // ==========================================================
            // PATH B: ON-DEMAND REGISTER EVALUATION (Variables / Floats)
            // ==========================================================
            int val_reg = allocate_register();
            generate_asm(val_node, val_reg);

            int needs_cast = !is_raw && (ioports[i].type & (IOPORT_TYPE_INTEGER | IOPORT_TYPE_BOOLEAN));
            int out_reg = val_reg;

            if (needs_cast)
            {
                out_reg = allocate_register();
                emit_asm("MOV R%d, R%d ; Copy value for hardware type cast\n", out_reg, val_reg);

                if ((ioports[i].type & IOPORT_TYPE_INTEGER) == IOPORT_TYPE_INTEGER)
                {
                    emit_asm("    ;; --- Intrinsic: Cast Lua Float to Hardware Integer ---\n");
                    emit_asm("CFI R%d\n", out_reg);
                }
                else if ((ioports[i].type & IOPORT_TYPE_BOOLEAN) == IOPORT_TYPE_BOOLEAN)
                {
                    emit_asm("    ;; --- Intrinsic: Cast Lua Float to Hardware Boolean ---\n");
                    emit_asm("CFB R%d\n", out_reg);
                }
            }

            if (is_raw) {
                emit_asm("    ;; --- Intrinsic: Direct Raw Hardware Write (%s) ---\n", full_path);
            }
            emit_asm("OUT %s, R%d\n", ioports[i].asm_port, out_reg);

            if (needs_cast)
            {
                unlock_register(out_reg);
            }
            unlock_register(val_reg);

            return 1;
        }
    }

    return 0;
}

/*
// Returns 1 if hardware intrinsic was emitted, 0 if dynamic table fallback is required.
int try_emit_table_set_intrinsic(ASTNode *table_expr, ASTNode *key_expr, ASTNode *val_node, int val_reg)
{
    char base_path[256] = {0};

    // 1. Resolve the static namespace path (e.g., "ioports.gpu")
    // Ensure the key is a string node before proceeding
    if (!resolve_static_path(table_expr, base_path) ||
        key_expr->type != NODE_STRING)
    {
        return 0;
    }

    // 2. Build the full path: base_path.key (e.g., "ioports.gpu.multiply")
    char full_path[512];
    snprintf(full_path, sizeof(full_path), "%s.%s", base_path, key_expr->as.string_val.value);

    // 3. Scan the internal IOPortMap table for a match
    for (int i = 0; ioports[i].lua_path != NULL; i++)
    {
        if (strcmp(full_path, ioports[i].lua_path) == 0)
        {
            // Verify hardware port write permissions
            if ((ioports[i].mode & IOPORT_WRITE) != IOPORT_WRITE)
            {
                compiler_error(ERR_SEMANTIC, yylineno, "%s: port cannot be written to", full_path);
            }

            // 4. Determine if hardware casting is needed
            // If the expression is already a raw integer (like hex()), suppress casting!
            bool is_raw = is_raw_integer_expression(val_node);
            int needs_cast = !is_raw && (ioports[i].type & (IOPORT_TYPE_INTEGER | IOPORT_TYPE_BOOLEAN));

            int out_reg = val_reg;
            if (needs_cast)
            {
                // Allocate a temporary scratch register to protect the original val_reg from mutation
                out_reg = allocate_register();
                emit_asm("MOV R%d, R%d ; Copy value for hardware type cast\n", out_reg, val_reg);
            }

            // 5. Apply Vircon32 hardware casting instructions ONLY if casting is needed
            if (needs_cast)
            {
                if ((ioports[i].type & IOPORT_TYPE_INTEGER) == IOPORT_TYPE_INTEGER)
                {
                    emit_asm("    ;; --- Intrinsic: Cast Lua Float to Hardware Integer ---\n");
                    emit_asm("CFI R%d\n", out_reg);
                }
                else if ((ioports[i].type & IOPORT_TYPE_BOOLEAN) == IOPORT_TYPE_BOOLEAN)
                {
                    emit_asm("    ;; --- Intrinsic: Cast Lua Float to Hardware Boolean ---\n");
                    emit_asm("CFB R%d\n", out_reg);
                }
            }

            // 6. Emit the OUT instruction using the mapped assembly port name
            if (is_raw) {
                emit_asm("    ;; --- Intrinsic: Direct Raw Hardware Write (%s) ---\n", full_path);
            }
            emit_asm("OUT %s, R%d\n", ioports[i].asm_port, out_reg);

            // Clean up scratch register if we used one
            if (needs_cast)
            {
                unlock_register(out_reg);
            }

            return 1;
        }
    }

    // Not a hardware port; fall back to dynamic heap table assignment
    return 0;
}*/

// Returns 1 if hardware intrinsic was emitted, 0 if dynamic table fallback is required.
int try_emit_table_get_intrinsic(ASTNode *table_expr, ASTNode *key_expr, int dest_reg)
{
    char base_path[256] = {0};

    // 1. Resolve the static namespace path (e.g., "ioports.gpu")
    // Ensure the key is a string node before proceeding
    if (!resolve_static_path(table_expr, base_path) ||
        key_expr->type != NODE_STRING)
    {
        return (0);
    }

    // 2. Build the full path: base_path.key (e.g., "ioports.gpu.x")
    char full_path[512];
    snprintf(full_path, sizeof(full_path), "%s.%s", base_path, key_expr->as.string_val.value);

    // 3. Scan the internal IOPortMap table for a match
    for (int i = 0; ioports[i].lua_path != NULL; i++)
    {
        if (strcmp(full_path, ioports[i].lua_path) == 0)
        {
            // Verify hardware port read permissions
            if ((ioports[i].mode & IOPORT_READ) != IOPORT_READ)
            {
                compiler_error(ERR_SEMANTIC, yylineno, "%s: port cannot be read from", full_path);
            }

            // 4. Handle custom action delegation (e.g., ioports.inp.inputs -> emit_get_gamepad_inputs_intrinsic)
            if ((ioports[i].mode & IOPORT_ACTION) == IOPORT_ACTION)
            {
                try_emit_action_intrinsic(ioports[i].asm_port, dest_reg);
                return (1);
            }

            // 5. Emit direct Vircon32 hardware IN instruction if a destination register is provided
            if (dest_reg != 0)
            {
                if ((ioports[i].type & IOPORT_TYPE_INTEGER) == IOPORT_TYPE_INTEGER)
                {
                    emit_asm("    ;; --- Intrinsic: Read Hardware Integer (%s) ---\n", full_path);
                    emit_asm("    IN R%d, %s\n", dest_reg, ioports[i].asm_port);
                    emit_asm("    CIF R%d ; Cast hardware int to Lua float\n", dest_reg);
                }
                else if ((ioports[i].type & IOPORT_TYPE_BOOLEAN) == IOPORT_TYPE_BOOLEAN)
                {
                    emit_asm("    ;; --- Intrinsic: Read Hardware Boolean (%s) ---\n", full_path);
                    emit_asm("    IN R%d, %s\n", dest_reg, ioports[i].asm_port);
                    emit_asm("    CIF R%d ; Cast hardware bool to Lua float\n", dest_reg);

                    // NOTE: If your NaN-boxing overhaul requires explicit boolean type tags
                    // instead of raw 0.0/1.0 floats, apply your bitwise tag mask here!
                    // e.g., emit_asm("    OR R%d, 0xFFFA0000 ; Apply boolean NaN tag\n", dest_reg);
                }
                else
                {
                    // Default: IOPORT_TYPE_FLOAT (No casting required!)
                    emit_asm("    ;; --- Intrinsic: Read Hardware Float (%s) ---\n", full_path);
                    emit_asm("    IN R%d, %s\n", dest_reg, ioports[i].asm_port);
                }
            }

            return (1);
        }
    }

    // Not a hardware port; fall back to dynamic heap table lookup
    return (0);
}
