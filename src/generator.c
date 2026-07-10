#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "codegen.h"

// --- Output Routing ---
static FILE* current_out_stream = NULL;

static FILE* out() {
    return current_out_stream ? current_out_stream : stdout;
}

// --- Columnar & Peephole Optimizer State ---
static char last_emitted_inst[32]   = "";
static char last_emitted_dest[128] = "";
static char last_emitted_src[128]  = "";

static void trim_spaces(char *str) {
    int len = strlen(str);
    while (len > 0 && (str[len-1] == ' ' || str[len-1] == '\t' || str[len-1] == '\r' || str[len-1] == '\n')) {
        str[len-1] = '\0';
        len--;
    }
    int start = 0;
    while (str[start] == ' ' || str[start] == '\t') start++;
    if (start > 0) memmove(str, str + start, strlen(str + start) + 1);
}

// Recursively flattens an AST chain like table_get(table_get("ioports", "gpu"), "clear")
// into a flat C string "ioports.gpu.clear". Returns 1 if successful, 0 if dynamic.
static int resolve_static_path(ASTNode* node, char* path_buffer) {
    if (!node) return 0;

    if (node->type == NODE_IDENTIFIER) {
        strcpy(path_buffer, node->as.id.name);
        return (1);
    }

    if (node->type == NODE_TABLE_GET && node->as.table_get.key->type == NODE_STRING) {
        char base_path[256] = {0};
        if (resolve_static_path(node->as.table_get.table_expr, base_path)) {
            sprintf(path_buffer, "%s.%s", base_path, node->as.table_get.key->as.string_val.value);
            return (1);
        }
    }
    
    return 0;
}

static void emit_asm(const char* format, ...) {
    char current_instruction[256];
    va_list args;
    
    va_start(args, format);
    vsprintf(current_instruction, format, args);
    va_end(args);

    char *p = current_instruction;
    while (*p == ' ' || *p == '\t') p++;

    // 1. Find where the first colon and semicolon are located
    char *colon_pos = strchr(p, ':');
    char *semi_pos  = strchr(p, ';');
    
    // 2. It is only a label if a colon exists AND (there is no comment OR the colon is before the comment)
    int is_label = (colon_pos != NULL && (semi_pos == NULL || colon_pos < semi_pos));

    // 3. Use our new is_label check instead of strchr
    if (*p == '\0' || *p == '\r' || *p == '\n' || *p == ';' || is_label) {
        fprintf(out(), "%s", current_instruction);
        if (is_label || *p == '\0' || *p == '\r' || *p == '\n') {
            last_emitted_inst[0] = '\0';
            last_emitted_dest[0] = '\0';
            last_emitted_src[0] = '\0';
        }
        return;
    }
    
    char inst[32] = {0};
    char operands[256] = {0};
    char comment[256] = {0};

    int inst_len = 0;
    while (*p && *p != ' ' && *p != '\t' && *p != '\r' && *p != '\n' && *p != ';') {
        if (inst_len < 31) inst[inst_len++] = *p;
        p++;
    }
    inst[inst_len] = '\0';

    while (*p == ' ' || *p == '\t') p++;

    int op_len = 0;
    while (*p && *p != ';' && *p != '\r' && *p != '\n') {
        if (op_len < 255) operands[op_len++] = *p;
        p++;
    }
    operands[op_len] = '\0';
    trim_spaces(operands);

    if (*p == ';') {
        p++;
        while (*p == ' ' || *p == '\t') p++; 
        int c_len = 0;
        while (*p && *p != '\r' && *p != '\n') {
            if (c_len < 255) comment[c_len++] = *p;
            p++;
        }
        comment[c_len] = '\0';
        trim_spaces(comment);
    }

    if (strcmp(inst, "MOV") == 0) {
        char dest[128] = {0}, src[128] = {0};
        if (sscanf(operands, "%[^,], %[^\n]", dest, src) == 2) {
            trim_spaces(dest);
            trim_spaces(src);

            if (strcmp(dest, src) == 0) {
                fprintf(out(), "    ;; Peephole optimized out: %s %s\n", inst, operands);
                return;
            }

            if (strcmp(last_emitted_inst, "MOV") == 0) {
                if (strcmp(dest, last_emitted_src) == 0 && strcmp(src, last_emitted_dest) == 0) {
                    fprintf(out(), "    ;; Peephole optimized out: %s %s\n", inst, operands);
                    return;
                }
            }
        }
    }

    if (strlen(comment) > 0) {
        if (strlen(operands) > 0) fprintf(out(), "    %-5s %-30s ; %s\n", inst, operands, comment);
        else fprintf(out(), "    %-5s %-30s ; %s\n", inst, "", comment);
    } else {
        if (strlen(operands) > 0) fprintf(out(), "    %-5s %s\n", inst, operands);
        else fprintf(out(), "    %-5s\n", inst);
    }

    strcpy(last_emitted_inst, inst);
    if (strcmp(inst, "MOV") == 0) {
        char dest[128] = {0}, src[128] = {0};
        if (sscanf(operands, "%[^,], %[^\n]", dest, src) == 2) {
            trim_spaces(dest);
            trim_spaces(src);
            strcpy(last_emitted_dest, dest);
            strcpy(last_emitted_src, src);
        } else {
            last_emitted_dest[0] = '\0';
            last_emitted_src[0] = '\0';
        }
    } else {
        last_emitted_dest[0] = '\0';
        last_emitted_src[0] = '\0';
    }
}

static int check_needs_stack (ASTNode *node)
{
    if (node  == NULL)
    {
        return (0);
    }

    switch (node -> type) {
        case NODE_FUNCTION_CALL:
        case NODE_CONCAT:
        case NODE_TABLE_SET:
        case NODE_TABLE_GET:
        case NODE_ASM:
        case NODE_RAWASM:
            return (1);

        case NODE_IDENTIFIER:
            if (node->as.id.name && strcmp(node->as.id.name, "self") == 0) return (1);
            break;

        case NODE_RETURN: {
            int ret_count = 0;
            ASTNode *expr = node->as.return_stmt.expressions_head;
            while (expr) {
                ret_count++;
                if (check_needs_stack(expr)) return (1);
                expr = expr->next;
            }
            if (ret_count > 3) return (1);
            break;
        }

        case NODE_WHILE:
            if (check_needs_stack(node->as.while_loop.condition)) return (1);
            if (check_needs_stack(node->as.while_loop.body)) return (1);
            break;

        case NODE_IF:
            if (check_needs_stack (node -> as.if_stmt.condition)) return (1);
            if (check_needs_stack (node -> as.if_stmt.if_body))   return (1);
            if (check_needs_stack (node -> as.if_stmt.else_body)) return (1);
            //fprintf (stderr, "[IF] stack check: doesn't need one\n");
            break;

        case NODE_MULTIPLE_ASSIGNMENT: {
            ASTNode* curr_tgt = node->as.mult_assign.targets_head;
            while (curr_tgt) { if (check_needs_stack(curr_tgt)) return (1); curr_tgt = curr_tgt->next; }
            ASTNode* curr_val = node->as.mult_assign.values_head;
            while (curr_val) { if (check_needs_stack(curr_val)) return (1); curr_val = curr_val->next; }
            break;
        }

        case NODE_ADD:
        case NODE_SUB:
        case NODE_MUL:
        case NODE_DIV:
        case NODE_AND:
        case NODE_OR:
        case NODE_RELATIONAL:
            if (check_needs_stack(node->as.binary.left))  return (1);
            if (check_needs_stack(node->as.binary.right)) return (1);
            break;

        default:
            break;
    }

    return check_needs_stack (node -> next);
}

void  generate_block (ASTNode *head)
{
    ASTNode *current   = head;
    while (current    != NULL)
    {
        int  temp_reg  = allocate_register();
        generate_asm (current, temp_reg);
        unlock_register (temp_reg);
        current        = current -> next; // Move to the next sibling statement
    }
}

static void emit_interpolated_asm (const char *raw_code) {
    char buffer[2048] = {0}; // Temporary buffer for the interpolated string
    int buf_idx = 0;
    
    const char *p = raw_code;
    while (*p) {
        if (*p == '{') {
            p++; 
            char var_name[256];
            int i = 0;
            while (*p && *p != '}' && i < 255) var_name[i++] = *p++;
            var_name[i] = '\0'; 
            if (*p == '}') p++; 
            
            // Format the variable and append it to our buffer
            char formatted_var[264];
            sprintf(formatted_var, "[var_%s]", var_name);
            for (int j = 0; formatted_var[j] != '\0' && buf_idx < 2047; j++) {
                buffer[buf_idx++] = formatted_var[j];
            }
        } else {
            if (buf_idx < 2047) buffer[buf_idx++] = *p;
            p++;
        }
    }
    buffer[buf_idx] = '\0';

    // Split the buffer by newlines and feed each line to emit_asm
    // This gives your inline assembly the exact same formatting love as the rest!
    char *line = strtok(buffer, "\n");
    while (line != NULL) {
        emit_asm("%s\n", line); 
        line = strtok(NULL, "\n");
    }
}

void  generate_asm (ASTNode *node, int  dest_reg)
{
    if (node                    != NULL)
    {
        switch (node -> type)
        {
            case NODE_WHILE: {
                int  cond_reg    = allocate_register ();
                int  label_id    = get_next_label ();
                const char *ctx  = get_current_function_name ();

                push_loop (label_id);
                emit_asm ("__%s_while_start_%d:\n", ctx, label_id);
                
                generate_asm (node -> as.while_loop.condition, cond_reg);
                
                emit_asm ("JF R%d, __%s_while_end_%d\n", cond_reg, ctx, label_id);
                unlock_register (cond_reg);
                
                ////////////////////////////////////////////////////////////////////////
                //
                // Push a local scope for the while loop block!
                //
                push_scope (); 
                generate_block (node -> as.while_loop.body);
                pop_scope ();
                
                emit_asm ("JMP __%s_while_start_%d\n", ctx, label_id);
                emit_asm ("__%s_while_end_%d:\n", ctx, label_id);
                pop_loop ();
                break;
            }

            case NODE_BREAK: {
                int  current_id  = current_loop ();
                if (current_id  == -1)
                {
                    fprintf (stderr, "Compiler Runtime Error: 'break' declaration found outside loop.\n");
                    exit (1);
                }

                emit_asm("JMP __%s_while_end_%d\n", get_current_function_name (), current_id);
                break;
            }

            case NODE_IF: {
                int         cond_reg  = allocate_register ();
                int         label_id  = get_next_label ();
                const char *ctx       = get_current_function_name ();
                
                generate_asm (node -> as.if_stmt.condition, cond_reg);
                
                emit_asm("JF R%d, __%s_else_%d\n", cond_reg, ctx, label_id);
                unlock_register (cond_reg);
                
                ////////////////////////////////////////////////////////////////////////
                //
                // Push local scope for IF body
                //
                push_scope ();
                generate_block (node -> as.if_stmt.if_body);
                pop_scope ();
                
                emit_asm ("JMP __%s_end_if_%d\n", ctx, label_id);
                emit_asm ("__%s_else_%d:\n", ctx, label_id);
            
                if (node -> as.if_stmt.else_body)
                {
                    ////////////////////////////////////////////////////////////////////
                    //
                    // Push local scope for ELSE body
                    //
                    push_scope ();
                    generate_block (node -> as.if_stmt.else_body);
                    pop_scope ();
                }
                emit_asm ("__%s_end_if_%d:\n", ctx, label_id);
                break;
            }

            case NODE_FUNCTION_DEF: {
                const char *func_name  = node -> as.function_def.name;
                push_function_context (func_name);

                ////////////////////////////////////////////////////////////////////////
                //
                // Emit function prologue
                //
                emit_asm("__function_%s:\n", func_name);
                int  needs_stack  = check_needs_stack (node -> as.function_def.body);
                if (needs_stack)
                {
                    emit_asm ("PUSH BP\n");
                    emit_asm ("MOV BP, SP\n");
                }
                else
                {
                    emit_asm ("    ;; OPTIMIZATION: frame pointer omitted (Leaf Function)\n");
                }

                ////////////////////////////////////////////////////////////////////////
                //
                // Push a new scope for the function body!
                //
                push_scope ();

                ////////////////////////////////////////////////////////////////////////
                //
                // Register function parameters into the local scope as
                // [BP + 2], [BP + 3]
                //
                int      param_offset  = 2; 
                ASTNode *p             = node -> as.function_def.params;
                while (p              != NULL)
                {
                    if (p -> type     == NODE_IDENTIFIER)
                    {
                        register_parameter (p -> as.id.name, param_offset++);
                    }
                    p                  = p -> next;
                }

                generate_block (node -> as.function_def.body);
                pop_scope (); // Exit function scope

                ////////////////////////////////////////////////////////////////////////
                //
                // Emit function epilogue
                //
                emit_asm ("__%s_return:\n", func_name);
                if (needs_stack)
                {
                    emit_asm ("MOV SP, BP\n");
                    emit_asm ("POP BP\n");
                }
                emit_asm ("RET\n");

                pop_function_context ();
                break;
            }

            case NODE_MULTIPLE_ASSIGNMENT: {
                ASTNode *curr_tgt         = node -> as.mult_assign.targets_head;
                ASTNode *curr_val         = node -> as.mult_assign.values_head;
                int      val_reg          = -1;

                while ((curr_tgt         != NULL) &&
                       (curr_val         != NULL))
                {
                    val_reg               = allocate_register();
                    generate_asm (curr_val, val_reg);

                    if (curr_tgt -> type == NODE_IDENTIFIER)
                    {
                        ////////////////////////////////////////////////////////////////
                        //
                        // If this is a `local` assignment, register it in the
                        // current scope!
                        //
                        if (node -> as.mult_assign.is_local)
                        {
                            register_local (curr_tgt -> as.id.name);
                        }
                        
                        ////////////////////////////////////////////////////////////////
                        //
                        // Retrieve the correct assembly access string
                        // ([var_x] vs [BP - 1])
                        //
                        char  var_access[256];
                        get_variable_access_string (curr_tgt -> as.id.name, var_access);
                        emit_asm ("MOV %s, R%d\n", var_access, val_reg);
                    }
                    
                    unlock_register (val_reg);
                    curr_tgt              = curr_tgt -> next;
                    curr_val              = curr_val -> next;
                }
                break;
            }

            case NODE_IDENTIFIER: {
                ////////////////////////////////////////////////////////////////////////
                //
                // NEW: Dynamically lookup identifier location
                //
                char  var_access[256];
                get_variable_access_string (node -> as.id.name, var_access);
                emit_asm ("MOV R%d, %s\n", dest_reg, var_access);
                break;
            }

            case NODE_FUNCTION_CALL: {
                // 1. HARDWARE INTRINSIC INTERCEPT
                char target_path[256] = {0};
                if (resolve_static_path(node->as.call.target, target_path)) {
                    if (strcmp(target_path, "ioports.gpu.clear") == 0) {
                        emit_asm("    ;; --- Intrinsic: ioports.gpu.clear() ---\n");
                        ASTNode *arg = node->as.call.args_head;
                    
                        if (arg != NULL) {
                            int color_reg = allocate_register();
                            if (arg->type == NODE_STRING) {
                                const char *color_name = arg->as.string_val.value;
                                unsigned int color_hex = 0x000000FF; // Default (Opaque Black)
                                int is_preset = 1;
                            
                                if (strcmp(color_name, "black") == 0)
                                      color_hex = 0x000000FF; 
                                else if (strcmp(color_name, "white") == 0)
                                       color_hex = 0xFFFFFFFF;
                                else if (strcmp(color_name, "blue") == 0)
                                      color_hex = 0x0000FFFF;
                                else if (strcmp(color_name, "red") == 0)
                                     color_hex = 0xFF0000FF;
                                else if (strcmp(color_name, "green") == 0)
                                       color_hex = 0x00FF00FF;
                                else {
                                    is_preset = 0; 
                                }
                                
                                if (is_preset) {
                                    emit_asm("MOV R%d, %u ; Preset color '%s'\n", color_reg, color_hex, color_name);
                                } else {
                                    generate_asm (arg, color_reg);
                                }
                            } else {
                                generate_asm (arg, color_reg);
                            }
                            emit_asm("OUT GPU_ClearColor, R%d\n", color_reg);
                            unlock_register (color_reg);
                        }
                    
                        int cmd_reg = allocate_register ();
                        emit_asm("MOV R%d, 1 ; GPU Command Code for Clear Screen\n", cmd_reg);
                        emit_asm("OUT GPU_Command, R%d\n", cmd_reg);
                        unlock_register (cmd_reg);
                        
                        if (dest_reg != 0) {
                            emit_asm ("MOV R%d, 0 ; return nil\n", dest_reg);
                        }
                        return; // Terminate early
                    }
                }

                // 2. STANDARD LUA FUNCTION CALL (Fallback)
                int arg_count = 0;

                if (node -> as.call.is_method_call) {
                    emit_asm ("  ; --- Injecting implicit 'self' ---\n");
                    int self_reg = allocate_register();
                    generate_asm (node -> as.call.target -> as.table_get.table_expr, self_reg);
                    emit_asm ("    PUSH  R%d\n", self_reg);
                    unlock_register(self_reg);
                    arg_count++;
                }

                ASTNode *current_arg = node -> as.call.args_head;
                while (current_arg != NULL) {
                    int arg_reg = allocate_register();
                    generate_asm (current_arg, arg_reg);
                    emit_asm ("    PUSH  R%d\n", arg_reg);
                    unlock_register(arg_reg);
                    arg_count++;
                    current_arg = current_arg -> next;
                }

                int target_reg = allocate_register();
                generate_asm (node -> as.call.target, target_reg);
                emit_asm ("CALL R%d\n", target_reg);
                unlock_register(target_reg);

                if (arg_count > 0) emit_asm ("ISUB SP, %d\n", arg_count);
                if (dest_reg != 0) emit_asm ("MOV R%d, R0\n", dest_reg);
                break;
            }

            case NODE_FUNCTION_POINTER: {
                emit_asm ("    ;; Load address of the mangled function\n");
                emit_asm ("MOV R%d, __function_%s\n", dest_reg, node -> as.func_ptr.mangled_name);
                break;
            }

            case NODE_RETURN: {
                ASTNode *expr = node -> as.return_stmt.expressions_head;
                int ret_idx = 0;
                int arg_count = node -> as.return_stmt.parent_func_arg_count;
                
                while (expr != NULL) {
                    int val_reg = allocate_register();
                    generate_asm (expr, val_reg); 
                    
                    if (ret_idx == 0)      { emit_asm ("MOV R0, R%d\n", val_reg); }
                    else if (ret_idx == 1) { emit_asm ("MOV R2, R%d\n", val_reg); }
                    else if (ret_idx == 2) { emit_asm ("MOV R3, R%d\n", val_reg); }
                    else {
                        int offset = 2 + arg_count + (ret_idx - 3);
                        emit_asm ("MOV [BP + %d], R%d\n", offset, val_reg);
                    }
                    unlock_register(val_reg);
                    
                    ret_idx++;
                    expr = expr -> next;
                }
                emit_asm ("JMP __%s_return\n", get_current_function_name ());
                break;
            }

            case NODE_ADD: {
                generate_asm (node -> as.binary.left, dest_reg);
                int right_reg = allocate_register ();
                generate_asm (node -> as.binary.right, right_reg);
                emit_asm ("FADD R%d, R%d\n", dest_reg, right_reg);
                unlock_register (right_reg);
                break;
            }

            case NODE_SUB: {
                generate_asm (node -> as.binary.left, dest_reg);
                int right_reg = allocate_register ();
                generate_asm (node -> as.binary.right, right_reg);
                emit_asm ("FSUB R%d, R%d\n", dest_reg, right_reg);
                unlock_register (right_reg);
                break;
            }
        
            case NODE_MUL: {
                generate_asm (node -> as.binary.left, dest_reg);
                int right_reg = allocate_register ();
                generate_asm (node -> as.binary.right, right_reg);
                emit_asm ("FMUL R%d, R%d\n", dest_reg, right_reg);
                unlock_register (right_reg);
                break;
            }
        
            case NODE_DIV: {
                generate_asm (node -> as.binary.left, dest_reg);
                int right_reg = allocate_register ();
                generate_asm (node -> as.binary.right, right_reg);
                emit_asm ("FDIV R%d, R%d\n", dest_reg, right_reg);
                unlock_register (right_reg);
                break;
            }

            case NODE_AND: {
                int label_id = get_next_label ();
                generate_asm (node -> as.binary.left, dest_reg);
                emit_asm ("JF R%d, __short_and_%d\n", dest_reg, label_id);
                generate_asm (node -> as.binary.right, dest_reg);
                emit_asm ("__short_and_%d:\n", label_id);
                break;
            }

            case NODE_OR: {
                int label_id = get_next_label ();
                generate_asm (node -> as.binary.left, dest_reg);
                emit_asm ("JT R%d, __short_or_%d\n", dest_reg, label_id);
                generate_asm (node -> as.binary.right, dest_reg);
                emit_asm ("__short_or_%d:\n", label_id);
                break;
            }

            case NODE_RELATIONAL: {
                generate_asm (node -> as.binary.left, dest_reg);
                int right_reg = allocate_register ();
                generate_asm (node -> as.binary.right, right_reg);
                switch (node -> as.binary.operator) {
                    case OP_EQ:  emit_asm ("FEQ R%d, R%d\n", dest_reg, right_reg); break;
                    case OP_NEQ: emit_asm ("FNE R%d, R%d\n", dest_reg, right_reg); break;
                    case OP_LT:  emit_asm ("FLT R%d, R%d\n", dest_reg, right_reg); break;
                    case OP_LE:  emit_asm ("FLE R%d, R%d\n", dest_reg, right_reg); break;
                    case OP_GT:  emit_asm ("FGT R%d, R%d\n", dest_reg, right_reg); break;
                    case OP_GE:  emit_asm ("FGE R%d, R%d\n", dest_reg, right_reg); break;
                }
                unlock_register (right_reg);
                break;
            }

            case NODE_STRING: {
                int str_id = add_string_literal (node -> as.string_val.value);
                emit_asm ("MOV R%d, __string_%d\n", dest_reg, str_id);
                break;
            }

            case NODE_CONCAT: {
                int left_reg = allocate_register();
                generate_asm (node -> as.binary.left, left_reg);
                emit_asm ("PUSH R%d\n", left_reg);
                unlock_register(left_reg);
                
                int right_reg = allocate_register();
                generate_asm (node -> as.binary.right, right_reg);
                emit_asm ("PUSH R%d\n", right_reg);
                unlock_register(right_reg);
                
                emit_asm ("CALL __builtin_strcat\n");
                emit_asm ("ISUB SP, 2\n");
                if (dest_reg != 0)
                    emit_asm ("MOV R%d, R0\n", dest_reg);
                break;
            }

            case NODE_TABLE_CONSTRUCTOR: {
                emit_asm ("MOV R%d, [heap_pointer] ; Read heap_pointer\n", dest_reg);
                int zero_reg = allocate_register ();
                emit_asm ("MOV R%d, 0\n", zero_reg);
                emit_asm ("MOV [R%d], R%d ; Initialize to nil/0\n", dest_reg, zero_reg);
                unlock_register (zero_reg);
                
                int temp_reg = allocate_register();
                emit_asm ("MOV R%d, [heap_pointer]\n", temp_reg);
                emit_asm ("IADD R%d, 1\n", temp_reg); 
                emit_asm ("MOV [heap_pointer], R%d ; Advance heap pointer\n", temp_reg);
                unlock_register(temp_reg);
                break;
            }

            case NODE_TABLE_SET: {
                char base_path[256] = {0};
                
                // 1. HARDWARE INTRINSIC CHECK
                if (resolve_static_path(node->as.table_set.table_expr, base_path) && 
                    node->as.table_set.key->type == NODE_STRING) {
                    
                    char full_path[512];
                    sprintf(full_path, "%s.%s", base_path, node->as.table_set.key->as.string_val.value);

                    if (strcmp(full_path, "ioports.gpu.texture") == 0) {
                        int val_reg = allocate_register();
                        generate_asm(node->as.table_set.value, val_reg);

                        // Convert float to int
                        emit_asm ("    ;; --- Intrinsic: Cast Lua Float to Hardware Integer ---\n");
                        emit_asm ("CFI R%d\n", val_reg);
                        emit_asm ("OUT GPU_SelectedTexture, R%d\n", val_reg);

                        unlock_register(val_reg);
                        return; // Skip standard dynamic table assignment
                    }
                }

                // 2. STANDARD TABLE SET (Fallback)
                int val_reg = allocate_register();
                generate_asm (node -> as.table_set.value, val_reg);
                emit_asm ("PUSH R%d\n", val_reg);
                unlock_register(val_reg);
            
                int key_reg = allocate_register();
                generate_asm (node -> as.table_set.key, key_reg);
                emit_asm ("PUSH R%d\n", key_reg);
                unlock_register(key_reg);
            
                int tbl_reg = allocate_register();
                generate_asm (node -> as.table_set.table_expr, tbl_reg);
                emit_asm ("PUSH R%d\n", tbl_reg);
                unlock_register(tbl_reg);
            
                emit_asm ("CALL __builtin_table_set\n");
                emit_asm ("ISUB SP, 3\n");
                break;
            }

            case NODE_TABLE_GET: {
                char base_path[256] = {0};
                
                // 1. HARDWARE INTRINSIC CHECK
                if (resolve_static_path(node->as.table_get.table_expr, base_path) && 
                    node->as.table_get.key->type == NODE_STRING) {
                    
                    char full_path[512];
                    sprintf(full_path, "%s.%s", base_path, node->as.table_get.key->as.string_val.value);
                
                    if (strcmp(full_path, "ioports.gpu.texture") == 0) {
                        if (dest_reg != 0) {
                            emit_asm ("    ;; --- Intrinsic: Read Hardware Integer ---\n");
                            emit_asm ("IN R%d, GPU_SelectedTexture\n", dest_reg);

                            // Convert integer to float
                            emit_asm ("    ;; --- Intrinsic: Cast to Lua Float ---\n");
                            emit_asm ("CIF R%d\n", dest_reg);
                        }
                        return; // Skip standard dynamic table lookup
                    }
                }

                // 2. STANDARD TABLE GET (Fallback)
                int key_reg = allocate_register ();
                generate_asm (node -> as.table_get.key, key_reg);

                int tbl_reg = allocate_register();
                generate_asm (node -> as.table_get.table_expr, tbl_reg);
            
                emit_asm ("MOV R1, R%d\n", tbl_reg);
                emit_asm ("MOV R2, R%d\n", key_reg);
                emit_asm ("CALL __builtin_table_get\n");
                
                unlock_register (key_reg);
                unlock_register (tbl_reg);
            
                if (dest_reg != 0) emit_asm ("MOV R%d, R0\n", dest_reg);
                break;
            }

            case NODE_NUMBER:
                emit_asm ("MOV R%d, %f\n", dest_reg, node -> as.number.val);
                break;

case NODE_ASM: {
                emit_asm ("    ;; --- Begin Inline ASM Bubble (existing register states preserved) ---\n");
                
                // Get the formatted string for SP and BP snapshots
                char sp_access[256];
                char bp_access[256];
                get_variable_access_string("asm_snap_sp", sp_access);
                get_variable_access_string("asm_snap_bp", bp_access);
                
                emit_asm ("MOV %s, SP\n", sp_access);
                emit_asm ("MOV %s, BP\n", bp_access);

                for (int i = 0; i < NUM_GPRS; i++) {
                    if (is_register_locked (i)) {
                        char snap_name[32];
                        sprintf (snap_name, "asm_snap_r%d", i);
                        
                        char reg_access[256];
                        get_variable_access_string(snap_name, reg_access);
                        emit_asm ("MOV %s, R%d\n", reg_access, i);
                    }
                }
                
                emit_interpolated_asm (node->as.inline_asm.code);

                for (int i = 0; i < NUM_GPRS; i++) {
                    if (is_register_locked (i)) {
                        char snap_name[32];
                        sprintf (snap_name, "asm_snap_r%d", i);
                        
                        char reg_access[256];
                        get_variable_access_string(snap_name, reg_access);
                        emit_asm ("MOV R%d, %s\n", i, reg_access);
                    }
                }

                emit_asm ("MOV BP, %s\n", bp_access);
                emit_asm ("MOV SP, %s\n", sp_access);
                emit_asm ("    ;; --- End Inline ASM Bubble ---\n");
                break;
            }

            case NODE_RAWASM: {
                emit_asm ("    ;; --- Begin Raw ASM (Unprotected) ---\n");
                emit_interpolated_asm (node -> as.inline_asm.code);
                emit_asm ("    ;; --- End Raw ASM ---\n");
                break;
            }

            case NODE_COMMENT_LINE: {
                fprintf (out (), ";;@ %s\n", node->as.string_val.value);
                break;
            }

            case NODE_COMMENT_BLOCK: {
                fprintf(out(), ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n");
                fprintf(out(), ";; \n");
                fprintf(out(), ";;@ ");
                
                char *text = node->as.string_val.value;
                for (int i = 0; text[i] != '\0'; i++) {
                    if (text[i] == '\n') {
                        fprintf(out(), "\n;;@ ");
                    } else if (text[i] == '\t') {
                        fprintf(out(), " ");
                    } else if (text[i] == '\r') {
                        ; // Skip carriage returns
                    } else {
                        putchar(text[i]);
                    }
                }
                fprintf(out(), "\n;; \n");
                break;
            }
        }
    }
}

void  generate_global_setup (ASTNode *node)
{
    if (node              != NULL)
    {
        ////////////////////////////////////////////////////////////////////////////
        //
        // Declare and initialize variables
        //
        //ASTNode    *current      = node;
        //const char *func_name    = NULL;

        ////////////////////////////////////////////////////////////////////////////
        //
        // Pre-Pass: Register all functions globally ---
        //
		/*
        while (current          != NULL)
        {
            if (current -> type == NODE_FUNCTION_DEF)
            {
                ////////////////////////////////////////////////////////////////////
                //
                // Extract the function name:
                //
                func_name        = current -> as.function_def.name;

                ////////////////////////////////////////////////////////////////////
                //
                // Register it or update the existing symbol immediately
                //
                mark_global_as_function (func_name);
            }
            current              = current->next;
        }*/

		/*
        if (node -> type  == NODE_FUNCTION_DEF)
        {
            char  var_access[256];
            int  temp_reg  = allocate_register();

            ////////////////////////////////////////////////////////////////////////////
            //
            // Register the function name in the global scope explicitly
            //
            mark_global_as_function (node -> as.function_def.name);

            emit_asm ("    ;; Load address of the mangled function\n");
            emit_asm ("MOV R%d, __function_%s\n", temp_reg,
                                                  node -> as.function_def.name);
            
            ////////////////////////////////////////////////////////////////////////////
            //
            // Dynamically get its global access string
            //
            get_variable_access_string (node -> as.function_def.name, var_access);
            emit_asm ("MOV %s, R%d\n", var_access, temp_reg);

            unlock_register (temp_reg);
        }*/
        
        generate_global_setup (node -> next);
    }
}

void  generate_functions (ASTNode *node)
{
    while (node                   != NULL)
    {
        if (node -> type          == NODE_FUNCTION_DEF)
        {
            ASTNode *next_sibling  = node -> next;
            node -> next           = NULL;
            generate_asm (node, 0); 
            node -> next           = next_sibling;
        }
        node                       = node -> next;
    }
}

void  generate_program (ASTNode *head)
{
    ////////////////////////////////////////////////////////////////////////////////////
    //
    // Declare and initialize variables
    //
    ASTNode *current                = NULL;
    int      globals_need_stack     = 0;
    int      temp_reg               = -1;  
    char     buffer[1024];
    char    *check                  = NULL;

    ////////////////////////////////////////////////////////////////////////////////////
    //
    // Function Pre-Pass: Register all functions globally before generating ANY code
    //
    current                         = head;
    while (current                 != NULL)
    {
        if (current -> type        == NODE_FUNCTION_DEF)
        {
            mark_global_as_function (current -> as.function_def.name);
        }
        current                     = current -> next;
    }

    ////////////////////////////////////////////////////////////////////////////////////
    //
    // Initialize the global scope before compiling!
    //
    init_global_scope (); 

    ////////////////////////////////////////////////////////////////////////////////////
    //
    // buffered output routing
    //
    current_out_stream              = tmpfile();
    if (current_out_stream         == NULL)
    {
        fprintf (stderr, "Compiler Error: Failed to create temporary file for code generation.\n");
        exit (1);
    }
    
    emit_asm (";; --- Compiled Code Entry Vector ---\n");
    emit_asm ("CALL __init_globals  ; Run top-level setups first\n");
    emit_asm ("CALL __function_main ; Then hand control to the user\n");
    emit_asm ("HLT                  ; Halt CPU when main finishes\n");

    emit_asm ("\n;; --- Function Definitions ---\n");
    current                         = head;
    while (current                 != NULL)
    {
        if (current -> type        == NODE_FUNCTION_DEF)
        {
            generate_asm (current, 0);
        }
        else
        {
            if (check_needs_stack (current))
            {
                globals_need_stack  = 1;
            }
        }
        current                     = current -> next;
    }

    emit_asm ("\n;; --- Global Initialization Vector ---\n");
    emit_asm ("__init_globals:\n");
    
    if (globals_need_stack         == 1)
    {
        emit_asm ("PUSH BP\n");
        emit_asm ("MOV BP, SP\n");
    }
    else
    {
        emit_asm ("    ;; OPTIMIZATION: frame pointer omitted (Leaf Function)\n");
    }

    generate_global_setup (head);

    current                         = head;
    while (current                 != NULL)
    {
        if (current -> type        != NODE_FUNCTION_DEF)
        {
            temp_reg                = allocate_register ();
            generate_asm (current, temp_reg);
            unlock_register (temp_reg);
        }
        current                     = current -> next;
    }

    if (globals_need_stack)
    {
        emit_asm ("MOV SP, BP\n");
        emit_asm ("POP BP\n");
    }
    emit_asm ("RET\n\n");

    fprintf (stdout, ";; --- System Constants ---\n");
    fprintf (stdout, "%%define heap_pointer 0\n");

    fprintf (stdout, "\n;; --- Global Variable RAM Map ---\n");
    emit_variable_map ();
    fprintf (stdout, "\n");

    rewind (current_out_stream);
    check                           = fgets (buffer,
                                             sizeof (buffer),
                                             current_out_stream);
    while (check                   != NULL)
    {
        fputs (buffer, stdout);
        check                       = fgets (buffer,
                                             sizeof (buffer),
                                             current_out_stream);
    }
    fclose (current_out_stream);
    current_out_stream              = NULL;

    emit_runtime_library ();
    emit_string_data_section ();
}
