#include "v32lua.h"

// ============================================================================
// --- Internal GPU Port Mapping Table ---
// ============================================================================

typedef struct {
    const char *lua_path;
    const char *asm_port;
} GPUPortMap;

static const GPUPortMap gpu_ports[] = {
    { "ioports.gpu.texture", "GPU_SelectedTexture" },
    { "ioports.gpu.region",  "GPU_SelectedRegion"  },
    { "ioports.gpu.x",       "GPU_DrawingPointX"   },
    { "ioports.gpu.y",       "GPU_DrawingPointY"   },
    { "ioports.gpu.minX",    "GPU_RegionMinX"      },
    { "ioports.gpu.minY",    "GPU_RegionMinY"      },
    { "ioports.gpu.maxX",    "GPU_RegionMaxX"      },
    { "ioports.gpu.maxY",    "GPU_RegionMaxY"      },
    { "ioports.gpu.hotX",    "GPU_RegionHotSpotX"  },
    { "ioports.gpu.hotY",    "GPU_RegionHotSpotY"  },
    { NULL, NULL } // Sentinel
};

// ============================================================================
// --- Static Helper Functions for Complex Calls ---
// ============================================================================

static void emit_print_intrinsic(ASTNode *node) {
    int arg_reg = allocate_register();
    generate_asm(node->as.call.args_head, arg_reg);
    
    emit_asm("    PUSH R%d\n", arg_reg);
    emit_asm("    CALL __builtin_tostring\n"); // Coerce to string
    emit_asm("    MOV  [SP], R0\n");           // Replace arg with coerced string
    emit_asm("    CALL __builtin_print\n");    // Print it
    emit_asm("    ISUB SP, 1\n");              // Clean up stack
    
    unlock_register(arg_reg);
}

static void emit_gpu_draw_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- Intrinsic: ioports.gpu.draw() ---\n");
    ASTNode *arg = node->as.call.args_head;

    if (arg != NULL && arg->type == NODE_STRING) {
        const char *drawtype = arg->as.string_val.value;
        if (strcmp(drawtype, "zoom") == 0)
            emit_asm("    OUT GPU_Command, GPUCommand_DrawRegionZoomed\n");
        else if (strcmp(drawtype, "rotate") == 0)
            emit_asm("    OUT GPU_Command, GPUCommand_DrawRegionRotated\n");
        else if (strcmp(drawtype, "rotozoom") == 0)
            emit_asm("    OUT GPU_Command, GPUCommand_DrawRegionRotozoomed\n");
        else
            emit_asm("    OUT GPU_Command, GPUCommand_DrawRegion\n");
    } else {
        emit_asm("    OUT GPU_Command, GPUCommand_DrawRegion\n");
    }

    if (dest_reg != 0) {
        emit_asm("    MOV R%d, 0 ; return nil\n", dest_reg);
    }
}

static void emit_gpu_clear_intrinsic(ASTNode *node, int dest_reg) {
    emit_asm("    ;; --- Intrinsic: ioports.gpu.clear() ---\n");
    ASTNode *arg = node->as.call.args_head;

    if (arg != NULL) {
        int color_reg = allocate_register();
        if (arg->type == NODE_STRING) {
            const char *color_name = arg->as.string_val.value;
            unsigned int color_hex = 0x000000FF; // Default Opaque Black
            int is_preset = 1;

            if      (strcmp(color_name, "black") == 0) color_hex = 0x000000FF; 
            else if (strcmp(color_name, "white") == 0) color_hex = 0xFFFFFFFF;
            else if (strcmp(color_name, "blue") == 0)  color_hex = 0x0000FFFF;
            else if (strcmp(color_name, "red") == 0)   color_hex = 0xFF0000FF;
            else if (strcmp(color_name, "green") == 0) color_hex = 0x00FF00FF;
            else is_preset = 0; 
            
            if (is_preset) {
                emit_asm("    MOV R%d, %u ; Preset color '%s'\n", color_reg, color_hex, color_name);
            } else {
                generate_asm(arg, color_reg);
            }
        } else {
            generate_asm(arg, color_reg);
        }
        emit_asm("    OUT GPU_ClearColor, R%d\n", color_reg);
        unlock_register(color_reg);
    }

    emit_asm("    OUT GPU_Command, GPUCommand_ClearScreen\n");
    if (dest_reg != 0) {
        emit_asm("    MOV R%d, 0 ; return nil\n", dest_reg);
    }
}

// ============================================================================
// --- Public Interceptor Implementations ---
// ============================================================================

int try_emit_call_intrinsic(ASTNode *node, int dest_reg) {
    char func_name[256] = {0};
    if (!resolve_static_path(node->as.call.target, func_name)) {
        return 0; // Dynamic call, not an intrinsic
    }

    if (strcmp(func_name, "print") == 0) {
        emit_print_intrinsic(node);
        return 1;
    }
    if (strcmp(func_name, "ioports.gpu.draw") == 0) {
        emit_gpu_draw_intrinsic(node, dest_reg);
        return 1;
    }
    if (strcmp(func_name, "ioports.gpu.clear") == 0) {
        emit_gpu_clear_intrinsic(node, dest_reg);
        return 1;
    }

    return 0; // Not handled here
}

int try_emit_table_set_intrinsic(ASTNode *node) {
    char base_path[256] = {0};
    if (!resolve_static_path(node->as.table_set.table_expr, base_path) || 
        node->as.table_set.key->type != NODE_STRING) {
        return 0;
    }

    char full_path[512];
    snprintf(full_path, sizeof(full_path), "%s.%s", base_path, node->as.table_set.key->as.string_val.value);

    // Clean table lookup replaces all your repetitive strcmp blocks!
    for (int i = 0; gpu_ports[i].lua_path != NULL; i++) {
        if (strcmp(full_path, gpu_ports[i].lua_path) == 0) {
            int val_reg = allocate_register();
            generate_asm(node->as.table_set.value, val_reg);

            emit_asm("    ;; --- Intrinsic: Cast Lua Float to Hardware Integer ---\n");
            emit_asm("    CFI R%d\n", val_reg);
            emit_asm("    OUT %s, R%d\n", gpu_ports[i].asm_port, val_reg);

            unlock_register(val_reg);
            return 1;
        }
    }

    return 0;
}

int try_emit_table_get_intrinsic(ASTNode *node, int dest_reg) {
    char base_path[256] = {0};
    if (!resolve_static_path(node->as.table_get.table_expr, base_path) || 
        node->as.table_get.key->type != NODE_STRING) {
        return 0;
    }

    char full_path[512];
    snprintf(full_path, sizeof(full_path), "%s.%s", base_path, node->as.table_get.key->as.string_val.value);

    for (int i = 0; gpu_ports[i].lua_path != NULL; i++) {
        if (strcmp(full_path, gpu_ports[i].lua_path) == 0) {
            if (dest_reg != 0) {
                emit_asm("    ;; --- Intrinsic: Read Hardware Integer ---\n");
                emit_asm("    IN R%d, %s\n", dest_reg, gpu_ports[i].asm_port);
                emit_asm("    ;; --- Intrinsic: Cast to Lua Float ---\n");
                emit_asm("    CIF R%d\n", dest_reg);
            }
            return 1;
        }
    }

    return 0;
}
