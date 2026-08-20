#include "v32lua.h"

// Allocate storage for the global variables exactly once
int  o_optflag  = 0; // by default, no compiler optimizations take place
bool g_debug_mode = false;
const char *g_asm_filename = NULL;
const char *g_lua_filename = NULL;
int g_temp_asm_line        = 0;      // Adjust buffer size to match your project's original size
int g_current_lua_line = 0;
char g_current_label[256];      // Adjust buffer size to match your project's original size
FILE *temp_debug_stream = NULL;

// Private to this module; cannot be accidentally modified by other files
FILE *active_out_stream = NULL;

/* Sets the target stream for compilation output */
void  set_output_stream (FILE* stream)
{
    active_out_stream  = stream;
}

/* Returns the current output stream, safely falling back to stdout if none is set */
FILE *out (void)
{
    if (active_out_stream == NULL)
    {
        // Safe fallback: allows debug runs without -o to still print to the console
        return (stdout);
    }
    return (active_out_stream);
}

/* Closes the stream if open and resets the internal pointer */
void  close_output_stream (void)
{
    if ((active_out_stream != NULL) &&
        (active_out_stream != stdout))
       {
        fclose (active_out_stream);
        active_out_stream   = NULL;
    }
}

// --- Columnar & Peephole Optimizer State ---
char last_emitted_inst[32]   = "";
char last_emitted_dest[128] = "";
char last_emitted_src[128]  = "";

void trim_spaces(char *str) {
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
int resolve_static_path(ASTNode* node, char* path_buffer) {
    if (!node)
    {
        fprintf (stderr, "[resolve_static_path] node is NULL\n");
        return 0;
    }

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

int  get_expected_arity (ASTNode *target)
{
    if (!target) return -1;

    // 1. Direct function call: foo(1, 2)
    if (target->type == NODE_IDENTIFIER) {
        SymbolNode *sym = resolve_symbol(target->as.id.name);
        if (sym && sym->is_function) {
            return sym->arity;
        }
    }

    // 2. Method or static table call: player:draw() -> resolves to "player.draw"
    char path_buf[256] = {0};
    if (resolve_static_path(target, path_buf)) {
        // First, try direct lookup
        SymbolNode *sym = resolve_symbol(path_buf);
        if (sym && sym->is_function) {
            return sym->arity;
        }

        // NEW: Try mangled lookup by converting '.' and ':' to '_'
        char mangled_buf[256];
        strncpy(mangled_buf, path_buf, sizeof(mangled_buf) - 1);
        mangled_buf[sizeof(mangled_buf) - 1] = '\0';

        for (int i = 0; mangled_buf[i] != '\0'; i++) {
            if (mangled_buf[i] == '.' || mangled_buf[i] == ':') {
                mangled_buf[i] = '_';
            }
        }

        sym = resolve_symbol(mangled_buf);
        if (sym && sym->is_function) {
            return sym->arity;
        }
    }

    return -1;
}

int  count_function_locals(ASTNode* node)
{
    int count = 0;

    // Traverse sibling statements in the current block
    while (node != NULL) {
        switch (node->type) {
            case NODE_MULTIPLE_ASSIGNMENT:
                // Check if this assignment is a local declaration
                if (node->as.mult_assign.is_local) {
                    // Count how many variables are in the target list
                    ASTNode* target = node->as.mult_assign.targets_head;
                    while (target != NULL) {
                        count++;
                        target = target->next;
                    }
                }
                break;

            case NODE_IF: {
                // Recurse into both branches of an IF statement
                int  max       = 0;
                int  tmpcount  = 0;
                max            = count_function_locals (node -> as.if_stmt.if_body);
                tmpcount       = count_function_locals (node -> as.if_stmt.else_body);
                if (tmpcount  >  max)
                {
                    max        = tmpcount;
                }
                count          = count + max;
                break;
            }

            case NODE_DO_BLOCK:
                count += count_function_locals(node->as.do_block.body);
                break;

            case NODE_WHILE:
                // Recurse into WHILE loop bodies
                count += count_function_locals(node->as.while_loop.body);
                break;

            case NODE_FOR_NUMERIC:
                // Adds 3 to the stack requirement frame frame (+1 index, +1 limit, +1 step)
                count += 3 + count_function_locals(node->as.for_numeric.body);
                break;

            case NODE_FOR_GENERIC:
                // Adds 3 to the stack requirement frame frame (+1 index, +1 limit, +1 step)
                count += 3 + count_function_locals(node->as.for_numeric.body);
                break;

            case NODE_FUNCTION_DEF:
                // CRITICAL BOUNDARY: Do NOT recurse into nested function definitions!
                // Any locals inside a closure/nested function belong to THAT function's 
                // stack frame, not our current enclosing function.
                break;

            default:
                break;
        }

        node = node->next; // Move to the next statement in the block
    }

    return count;
}

int check_needs_stack (ASTNode *node)
{
    if (node  == NULL)
    {
        return (0);
    }

    switch (node -> type) {
        case NODE_FOR_NUMERIC:
        case NODE_FOR_GENERIC:
        case NODE_CONCAT:
        case NODE_TABLE_SET:
        case NODE_TABLE_GET:
        case NODE_ASM:
        case NODE_RAWASM:
            return (1);

        case NODE_FUNCTION_CALL: {
            // If it's a compile-time intrinsic like hex(), it doesn't need stack space!
            if (node -> as.call.target -> type == NODE_IDENTIFIER) {
                const char *name = node -> as.call.target -> as.id.name;
                if (strcmp (name, "hex") == 0) {
                    return 0; // Leaf intrinsic: no stack required
                }
            }
            return (1); // Standard function call: stack required
        }

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

        case NODE_DO_BLOCK:
            if (check_needs_stack(node->as.do_block.body)) return (1);
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
        case NODE_MOD:
        case NODE_FLOORDIV:
        case NODE_POW:
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

void generate_block(ASTNode *head) {
    ASTNode *current = head;
    while (current != NULL) {
        // -------------------------------------------------------------
        // FIX: previously this allocated a temp_reg for every statement
        // except NODE_BREAK/NODE_RETURN, on the assumption every
        // statement needs somewhere to put a result. But node_if(),
        // node_while(), node_for_numeric(), node_for_generic(), and
        // node_do_block() all take ONLY an ASTNode* -- no dest_reg
        // parameter -- and never write to one. Handing them a temp_reg
        // anyway just leaves it locked, uselessly, for as long as that
        // statement takes to fully generate -- which for a NODE_IF
        // nested inside an elseif chain (your grammar desugars elseif
        // into a NODE_IF sitting alone in the previous branch's
        // else_body) means the WHOLE REST OF THE CHAIN, since
        // generate_block(else_body) allocates one more temp_reg per
        // nesting level and doesn't release it until everything below
        // that level has finished generating. Each elseif branch
        // permanently stacked one more locked-but-useless register on
        // top of the last, which is why register numbers climbed
        // higher (R6, R7, R8, R9...) the deeper into the chain you
        // went, and why corruption only appeared several branches in --
        // eventually there weren't enough real registers left for what
        // each branch's own condition check and function call actually
        // needed.
        //
        // These node types are statement-only control structures: they
        // never produce a value a caller could consume, so there's
        // nothing to protect a register FOR in the first place. Route
        // them through the same 0-dest_reg path as break/return.
        // -------------------------------------------------------------
        bool produces_no_value =
            (current->type == NODE_BREAK)          ||
            (current->type == NODE_RETURN)         ||
            (current->type == NODE_IF)             ||
            (current->type == NODE_WHILE)          ||
            (current->type == NODE_FOR_NUMERIC)     ||
            (current->type == NODE_FOR_GENERIC)     ||
            (current->type == NODE_DO_BLOCK)        ||
            (current->type == NODE_FUNCTION_DEF)    ||
            (current->type == NODE_MULTIPLE_ASSIGNMENT);

        if (!produces_no_value) {
            // Only actual value-producing expression-statements (bare
            // function calls used as statements, etc.) still get a
            // temp_reg -- and even for those, this register is released
            // immediately after that ONE statement's own codegen
            // returns, not held across any further nested block.
            int temp_reg = allocate_register();

            // Mark as live for this statement
            mark_register_live (temp_reg, 1);

            generate_asm(current, temp_reg);
            unlock_register(temp_reg);
        } else {
            // Statements that don't produce values, or whose handler
            // takes no dest_reg parameter at all: no register needed.
            generate_asm(current, 0);
        }
        current = current->next;
    }
}

void  generate_asm (ASTNode *node, int  dest_reg)
{
    if (node                    != NULL)
    {
        // Automatically synchronize the tracker with the current AST element's source line
        if (g_debug_mode) {
            g_current_lua_line = node->line_number; // Assumes your parser sets node->line_number
        }

        if (g_verbose_debug && node != NULL) {
            fprintf(stderr, "\n[debug] generate_asm(): Processing node type %d at line %d\n",
                    node->type, node->line_number);
        }

        switch (node -> type)
        {
            case NODE_WHILE:
                node_while (node);
                break;

            case NODE_FOR_NUMERIC:
                node_for_numeric (node);
                break;

            case NODE_FOR_GENERIC:
                node_for_generic (node);
                runtime_req.needs_tables = true;  // pairs/ipairs need tables
                break;

            case NODE_BREAK:
                node_break ();
                break;

            case NODE_IF:
                node_if (node);
                break;

            case NODE_DO_BLOCK:
                node_do_block (node);
                break;

            case NODE_FUNCTION_DEF:
                node_function_def (node);
                break;

            case NODE_UNARY:
                node_unary (node, dest_reg);
                break;
                             
            case NODE_MULTIPLE_ASSIGNMENT:
                node_multiple_assignment (node);
                break;

            case NODE_IDENTIFIER:
                node_identifier (node, dest_reg);
                break;

            case NODE_FUNCTION_CALL:
                node_function_call (node, dest_reg);
                runtime_req.needs_exec          = true;
                break;

            case NODE_FUNCTION_POINTER:
                node_function_pointer (node, dest_reg);
                break;

            case NODE_RETURN:
                node_return (node);
                break;

            case NODE_ADD:
                node_add (node, dest_reg);
                break;

            case NODE_MUL:
                node_mul (node, dest_reg);
                break;

            case NODE_SUB:
                node_sub (node, dest_reg);
                break;
        
            case NODE_DIV:
                node_div (node, dest_reg);
                break;

            case NODE_MOD:
                node_mod (node, dest_reg);
                break;

            case NODE_POW:
                node_pow (node, dest_reg);
                break;

            case NODE_FLOORDIV:
                node_floordiv (node, dest_reg);
                break;

            case NODE_BOOLEAN:
                node_boolean (node, dest_reg);
                break;

            case NODE_NIL:
                node_nil (dest_reg);
                break;

            case NODE_AND:
                node_and (node, dest_reg);
                break;

            case NODE_OR:
                node_or (node, dest_reg);
                break;

            case NODE_RELATIONAL:
                node_relational (node, dest_reg);
                break;

            case NODE_VARIADIC_EXPR:
                // Don't register as variable!
                // Instead, generate code to access variadic arguments
                emit_asm("    ; Variadic expression - access from stack\n");
                // You'll need to implement proper variadic arg access here
                break;

            case NODE_STRING:
                node_string (node, dest_reg);
                runtime_req.needs_strings       = true;
                break;

            case NODE_CONCAT:
                node_concat (node, dest_reg);
                runtime_req.needs_strings       = true;
                break;

            case NODE_TABLE_CONSTRUCTOR:
                node_table_constructor(node, dest_reg);
                runtime_req.needs_tables        = true;
                runtime_req.needs_memory_alloc  = true;
                break;

            case NODE_TABLE_SET:
                node_table_set (node);
                runtime_req.needs_tables        = true;
                break;

            case NODE_TABLE_GET:
                node_table_get (node, dest_reg);
                runtime_req.needs_tables        = true;
                break;

            case NODE_NUMBER:
                node_number (node, dest_reg);
                break;

            case NODE_ASM:
                node_asm (node);
                break;

            case NODE_RAWASM:
                node_rawasm (node);
                break;

            case NODE_COMMENT_LINE:
                node_comment_line (node);
                break;

            case NODE_COMMENT_BLOCK:
                node_comment_block (node);
                break;

            case NODE_CART_HINT:
                node_cart_hint (node, dest_reg);
                break;

            default:
                break;
        }
    }
}

void generate_global_setup (ASTNode *node)
{
    // 1. Emit the section header and entry label
    emit_asm ("\n; --- Global Variable & Runtime Initialization ---\n");
    emit_asm ("__global_scope_initialization:\n");
    emit_asm ("PUSH BP\n");
    emit_asm ("MOV BP, SP\n");
    if (next_ram_address >= 4)
        emit_asm ("MOV R0, %d ; heap start", next_ram_address);
    else
        emit_asm ("MOV R0, 4  ; heap start (minimum bound, for nil/false/true)");
    emit_asm ("MOV [HEAP_POINTER], R0");

    if (node != NULL)
    {
        ASTNode *current = node;

        while (current != NULL)
        {
            // 2. Filter out function definitions!
            // We only want top-level statements, assignments, and hints here.
            if (current -> type != NODE_FUNCTION_DEF)
            {
                // Allocate a temporary register from your inventory
                int temp_reg = allocate_register ();

                // Compile the top-level instruction (e.g., binding function pointers,
                // initializing variables, setting up cart hint resource IDs)
                generate_asm (current, temp_reg);

                // Return the register to the pool
                unlock_register (temp_reg);
            }

            // Move to the next statement in the AST chain
            current = current -> next;
        }
    }

    // 4. Emit RET to prevent falling through into __malloc or the runtime library
    emit_asm ("MOV SP, BP\n");
    emit_asm ("POP BP\n");
    emit_asm ("RET\n");
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

void  show_global_symbol_list (const char *label)
{
    SymbolNode *tmp  = global_scope ? global_scope -> symbols : NULL;
    fprintf (stderr, "[debug] show_global_symbol_list(\"%s\")\n", label);
    while (tmp      != NULL)
    {
        fprintf (stderr, "[debug] %%define %s%s %d\n", (tmp -> is_function == 1) ? "func" : "var", tmp -> name, tmp -> location);
        tmp          = tmp -> next;
    }
}

void generate_program (ASTNode *head)
{
    ASTNode *current             = NULL;
    char     buffer[1024];
    char    *check               = NULL;
    int      final_line_offset   = 0;

    // Must run before ANY codegen below touches NODE_FUNCTION_DEF bodies --
    // register_local()/register_parameter() consult the boxed_locals list
    // this populates the first time they see a captured name.
    analyze_closures (head);

    // =========================================================================
    // 1. CONDITIONAL ENTRY POINT CHECKS
    // =========================================================================
    SymbolNode *init_sym     = NULL;
    SymbolNode *main_sym     = NULL;
    SymbolNode *update_sym   = NULL;

    if (runtime_req.needs_tic80)
    {
        init_sym             = resolve_symbol ("BOOT");
        update_sym           = resolve_symbol ("TIC");
    }
    else if (runtime_req.needs_pico8)
    {
        init_sym             = resolve_symbol ("_init");
        main_sym             = resolve_symbol ("_draw");
        update_sym           = resolve_symbol ("_update");
    }
    else
    {
        init_sym             = resolve_symbol ("init");
        main_sym             = resolve_symbol ("main");
        update_sym           = resolve_symbol ("game_loop");
    }

    bool  has_init           = (init_sym   != NULL && init_sym -> is_function   == 1);
    bool  has_main           = (main_sym   != NULL && main_sym -> is_function   == 1);
    bool  has_update         = (update_sym != NULL && update_sym -> is_function == 1);

    // If neither main() nor game_loop() exists, halt compilation immediately
    if (runtime_req.needs_tic80 && !has_update)
    {
        compiler_error(ERR_SEMANTIC, -1, 
            "Compilation failed: Your program must declare a 'TIC()' function.");
    }
    else if (runtime_req.needs_pico8 && !has_update)
    {
        compiler_error(ERR_SEMANTIC, -1, 
            "Compilation failed: Your program must declare a '_update()' function.");
    }
    else if (!has_update && !has_main)
    {
        compiler_error(ERR_SEMANTIC, -1, 
            "Compilation failed: Your program must declare either a 'main()' or a 'game_loop()' function.");
    }

    // =========================================================================
    // 2. CODE GENERATION SETUP
    // =========================================================================
    FILE *temp_asm_stream = tmpfile();
    if (g_debug_mode) {
        temp_debug_stream = tmpfile();
        g_temp_asm_line = 1;
        g_current_label[0] = '\0';
    }

    FILE *final_out_stream = out();
    set_output_stream(temp_asm_stream);
    
    // =========================================================================
    // 3. EMIT COMPILED CODE ENTRY VECTOR
    // =========================================================================
    emit_asm (";; --- Compiled Code Entry Vector ---\n");
    emit_asm ("CALL __global_scope_initialization  ; Run top-level setups first\n");
    
    // --- API Initialization: Call the appropriate region setup routine ---
    // Only call one based on which API is enabled (mutually exclusive)
    if (runtime_req.needs_pico8) {
        emit_asm ("CALL __builtin_pico8_init  ; Initialize PICO-8 assets\n");
    } else if (runtime_req.needs_tic80) {
        emit_asm ("CALL __builtin_tic80_init  ; Initialize TIC-80 assets\n");
    }

    // If init() exists, execute it immediately after global variable setup
    if (has_init)
    {
        if (runtime_req.needs_pico8)
            emit_asm ("CALL __function__init  ; Run user-defined _init function\n");
        else if (runtime_req.needs_tic80)
            emit_asm ("CALL __function_BOOT   ; Run user-defined BOOT function\n");
        else
            emit_asm ("CALL __function_init   ; Run user-defined init function\n");
    }

    // Route to main() if available; fall back to game_loop() otherwise
    if (has_main && !runtime_req.needs_pico8)
    {
        w_mainwait  = 1; // look for WAIT, issue warning if not found
        emit_asm ("CALL __function_main ; Execute main execution cycle\n");
    }
    else if (has_update)
    {
        if (runtime_req.needs_tic80)
        {
            emit_asm ("MOV R0, var_TIC80_PAUSE_FLAG\n");
            emit_asm ("MOV R1, 0\n");
            emit_asm ("MOV [R0], R1 ; initialize pause flag to 0\n");
            emit_asm ("MOV R0, var_TIC80_EXIT_FLAG\n");
            emit_asm ("MOV [R0], R1 ; initialize exit flag to 0 (R1 already 0)\n");
        }

        emit_asm ("__start:\n");
        if (runtime_req.needs_pico8)
        {
            if (has_main)
            {
                emit_asm ("CALL __function__draw   ; Execute _draw()\n");
            }
            emit_asm ("CALL __function__update ; Execute _update()\n");
        }
        else if (runtime_req.needs_tic80)
        {
            // Check START button rising edge
            emit_asm ("IN R0, INP_GamepadButtonStart\n");
            emit_asm ("IEQ R0, 1\n");
            emit_asm ("JF R0, __check_flag ; No edge: check if we need TIC\n");

            // Rising edge detected: toggle pause
            emit_asm ("MOV R1, var_TIC80_PAUSE_FLAG\n");
            emit_asm ("MOV R1, [R1]\n");
            emit_asm ("IEQ R1, 0\n");
            emit_asm ("JT R1, __do_pause\n");
            emit_asm ("JMP __do_unpause\n");

            // Normal frame: call TIC if not paused
            emit_asm ("__check_flag:\n");
            emit_asm ("MOV R1, var_TIC80_PAUSE_FLAG\n");
            emit_asm ("MOV R1, [R1]\n");
            emit_asm ("IEQ R1, 0\n");
            emit_asm ("JF R1, __just_wait ; If paused, skip TIC\n");
            emit_asm ("CALL __function_TIC\n");
            emit_asm ("__just_wait:");
            emit_asm ("WAIT\n");

            // exit() defers termination to the end of the current frame --
            // TIC() has already run and WAIT has already presented whatever
            // it drew, so it's safe to stop here instead of looping back
            // into another frame.
            emit_asm ("MOV R1, var_TIC80_EXIT_FLAG\n");
            emit_asm ("MOV R1, [R1]\n");
            emit_asm ("IEQ R1, 0\n");
            emit_asm ("JF R1, __exit_requested ; exit() was called this frame\n");
            emit_asm ("JMP __start\n");
            emit_asm ("__exit_requested:\n");
            emit_asm ("HLT ; exit() requested -- Vircon32 has no console to return to, so halt cleanly\n");
            emit_asm ("JMP __exit_requested\n");

            // PAUSE: dim, render one frame, print, set flag
            emit_asm ("__do_pause:\n");
            emit_asm ("MOV R1, var_TIC80_COLOR_MULTIPLY\n");
            emit_asm ("IN R2, GPU_MultiplyColor\n");
            emit_asm ("MOV [R1], R2 ; Save current multiply\n");
            emit_asm ("MOV R2, 0xFF404040 ; 50% gray\n");
            emit_asm ("OUT GPU_MultiplyColor, R2\n");
            emit_asm ("CALL __function_TIC ; Render ONE dimmed frame\n");
            emit_asm ("MOV R1, 0xFFFFFFFF ; Restore for text\n");
            emit_asm ("OUT GPU_MultiplyColor, R1\n");
            emit_asm ("MOV R1, 275\n");
            emit_asm ("PUSH R1\n");
            emit_asm ("MOV R1, 170\n");
            emit_asm ("PUSH R1\n");
            emit_asm ("MOV R1, __const_str_pause\n");
            emit_asm ("OR R1, BOXED_ROMSTRING\n");
            emit_asm ("PUSH R1\n");
            emit_asm ("CALL __builtin_print\n");
            emit_asm ("IADD SP, 3\n");
            emit_asm ("MOV R1, var_TIC80_PAUSE_FLAG\n");
            emit_asm ("MOV R2, 1\n");
            emit_asm ("MOV [R1], R2 ; Set flag = 1\n");
            emit_asm ("WAIT\n");
            emit_asm ("JMP __start\n");

            // UNPAUSE: restore color, clear flag
            emit_asm ("__do_unpause:\n");
            emit_asm ("MOV R1, var_TIC80_COLOR_MULTIPLY\n");
            emit_asm ("MOV R2, [R1]\n");
            emit_asm ("OUT GPU_MultiplyColor, R2 ; Restore\n");
            emit_asm ("MOV R1, var_TIC80_PAUSE_FLAG\n");
            emit_asm ("MOV R2, 0\n");
            emit_asm ("MOV [R1], R2 ; Clear flag = 0\n");
        }
        else
        {
            emit_asm ("CALL __function_game_loop ; Execute game loop tick\n");
        }
        emit_asm ("WAIT\n");
        emit_asm ("JMP __start\n");
    }

    emit_asm ("HLT ; Safe-guard halt\n");

    // =========================================================================
    // 4. FUNCTION DEFINITIONS & GLOBAL INITIALIZERS
    // =========================================================================
    emit_asm ("\n;; --- Function Definitions ---\n");
    current = head;
    while (current != NULL)
    {
        if (current -> type == NODE_FUNCTION_DEF) {
            generate_asm (current, 0);
        }
        current = current->next;
    }

    generate_global_setup (head);

    // Restore output back to the final compilation output file
    set_output_stream (final_out_stream);

    fprintf (out(), ";; --- Global Variable RAM Map ---\n");
    final_line_offset           = final_line_offset + 2;
    
    final_line_offset += emit_variable_map();
    fprintf (out(), "\n");
    final_line_offset           = final_line_offset + 1;

    // Flush buffered compiler assembly to our output target
    rewind (temp_asm_stream);
    while ((check = fgets (buffer, sizeof (buffer), temp_asm_stream)) != NULL) {
        fputs (buffer, out());
    }
    fclose (temp_asm_stream);

    emit_runtime_library ();
    emit_string_data_section ();

    // --- GENERATE DEBUG FILE ---
    if (g_debug_mode && temp_debug_stream != NULL)
    {
        char debug_filename[1024];
        snprintf(debug_filename, sizeof(debug_filename), "%s.debug", g_asm_filename);
        
        FILE *debug_file = fopen(debug_filename, "w");
        if (debug_file != NULL)
        {
            rewind(temp_debug_stream);
            char dbg_buffer[512];
            int last_seen_lua_line = -1; 
            
            while (fgets(dbg_buffer, sizeof(dbg_buffer), temp_debug_stream) != NULL)
            {
                int rel_line = 0;
                int lua_line = 0;
                char label[256] = "";
                
                int items = sscanf(dbg_buffer, "%d,%d,%255s", &rel_line, &lua_line, label);
                if (items >= 2)
                {
                    if (lua_line != last_seen_lua_line)
                    {
                        last_seen_lua_line = lua_line;
                        int actual_asm_line = final_line_offset + rel_line;
                        
                        if (items == 3) {
                            label[strcspn(label, "\r\n")] = 0;
                            fprintf(debug_file, "%s,%d,%s,%d,%s\n", g_asm_filename, actual_asm_line, g_lua_filename, lua_line, label);
                        } else {
                            fprintf(debug_file, "%s,%d,%s,%d\n", g_asm_filename, actual_asm_line, g_lua_filename, lua_line);
                        }
                    }
                }
            }
            fclose(debug_file);
        }
        fclose(temp_debug_stream);
        temp_debug_stream = NULL; 
    }
}
