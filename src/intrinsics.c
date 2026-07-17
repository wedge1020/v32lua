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
    { "ioports.gpu.multcolor", "GPU_MultiplyColor",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.blending",  "GPU_ActiveBlending",       IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.texture",   "GPU_SelectedTexture",      IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.region",    "GPU_SelectedRegion",       IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.x",         "GPU_DrawingPointX",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.y",         "GPU_DrawingPointY",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.gpu.scalex",    "GPU_DrawingScaleX",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
    { "ioports.gpu.scaley",    "GPU_DrawingScaleY",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
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
    { "ioports.spu.chansound", "SPU_ChannelVolume",        IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
    { "ioports.spu.chanspeed", "SPU_ChannelSpeed",         IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
    { "ioports.spu.chanloop",  "SPU_ChannelLoopEnabled",   IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_BOOLEAN },
    { "ioports.spu.chanpos",   "SPU_ChannelPosition",      IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_FLOAT   },
    { "ioports.inp.gamepad",   "INP_SelectedGamepad",      IOPORT_READ | IOPORT_WRITE,  IOPORT_TYPE_INTEGER },
    { "ioports.inp.status",    "INP_GamepadConnected",     IOPORT_READ,                 IOPORT_TYPE_BOOLEAN },
    { "ioports.inp.inputs",    "custom",                   IOPORT_READ | IOPORT_ACTION, IOPORT_TYPE_INTEGER },
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
        emit_asm ("    MOV R%d, 0xFFC00000 ; return nil\n", dest_reg);
    }
}

static void emit_gpu_draw_intrinsic (ASTNode *node, int  dest_reg)
{
    emit_asm ("    ;; --- Intrinsic: ioports.gpu.draw() ---\n");
    ASTNode *arg = node->as.call.args_head;

    if (arg != NULL && arg -> type == NODE_STRING) {
        const char *drawtype = arg->as.string_val.value;
        if (strcmp(drawtype, "zoom") == 0)
            emit_asm ("OUT GPU_Command, GPUCommand_DrawRegionZoomed\n");
        else if (strcmp(drawtype, "rotate") == 0)
            emit_asm ("OUT GPU_Command, GPUCommand_DrawRegionRotated\n");
        else if (strcmp(drawtype, "rotozoom") == 0)
            emit_asm ("OUT GPU_Command, GPUCommand_DrawRegionRotozoomed\n");
        else
        {
            compiler_error (ERR_SEMANTIC, yylineno, "%s: invalid action '%s'", "ioports.gpu.draw()", drawtype);
        }
    }
    else if (arg == NULL)
    {
        emit_asm ("OUT GPU_Command, GPUCommand_DrawRegion\n");
    }
    else
    {
        compiler_error (ERR_SEMANTIC, yylineno, "%s: invalid action", "ioports.gpu.draw()");
    }

    if (dest_reg != 0) {
        emit_asm ("    MOV R%d, 0xFFC00000 ; return nil\n", dest_reg);
    }
}

static void emit_gpu_clear_intrinsic(ASTNode *node, int dest_reg) {
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
        emit_asm ("MOV R%d, 0xFFC00000 ; return nil\n", dest_reg);
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

    return (0); // Not handled here
}

// Returns 1 if hardware intrinsic was emitted, 0 if dynamic table fallback is required.
int  try_emit_table_set_intrinsic (ASTNode *table_expr, ASTNode *key_expr, int  val_reg)
{
    char base_path[256] = {0};

    // 1. Resolve the static namespace path (e.g., "ioports.gpu")
    // Ensure the key is a string node before proceeding
    if (!resolve_static_path(table_expr, base_path) ||
        key_expr->type != NODE_STRING)
    {
        return (0);
    }

    // 2. Build the full path: base_path.key (e.g., "ioports.gpu.bgcolor")
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

            // 4. Determine if hardware casting requires a scratch register
            int out_reg = val_reg;
            int needs_cast = (ioports[i].type & (IOPORT_TYPE_INTEGER | IOPORT_TYPE_BOOLEAN));

            if (needs_cast)
            {
                // Allocate a temporary scratch register to protect the original val_reg from mutation
                out_reg = allocate_register();
                emit_asm("MOV R%d, R%d ; Copy value for hardware type cast\n", out_reg, val_reg);
            }

            // 5. Apply Vircon32 hardware casting instructions
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

            // 6. Emit the OUT instruction using the mapped assembly port name
            emit_asm("OUT %s, R%d\n", ioports[i].asm_port, out_reg);

            // Clean up scratch register if we used one
            if (needs_cast)
            {
                unlock_register(out_reg);
            }

            return (1);
        }
    }

    // Not a hardware port; fall back to dynamic heap table assignment
    return (0);
}

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
