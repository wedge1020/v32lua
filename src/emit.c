#include "v32lua.h"

void emit_asm(const char *format, ...) {
    char raw_buf[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(raw_buf, sizeof(raw_buf), format, args);
    va_end(args);

    // =========================================================================
    // DETECT WAIT INSTRUCTION IN MAIN()
    // =========================================================================
    if (strcmp(get_current_function_name(), "main") == 0) {
        // Look for the "WAIT" instruction or opcode in the raw buffer
        if (strstr(raw_buf, "WAIT") != NULL) {
            w_mainwait  = 0;
        }
    }

    // 1. Strip trailing newlines/carriage returns for safe parsing
    size_t len = strlen(raw_buf);
    while (len > 0 && (raw_buf[len - 1] == '\n' || raw_buf[len - 1] == '\r')) {
        raw_buf[--len] = '\0';
    }

    // Handle pure empty lines safely without disturbing debug track counts
    if (len == 0) {
        fprintf(out(), "\n");
        return;
    }

    // 2. PARTITIONING: Isolate the first semicolon to isolate Code from Comments
    char *comment_ptr = strchr(raw_buf, ';');
    char code_buf[1024] = {0};

    if (comment_ptr != NULL) {
        size_t code_len = comment_ptr - raw_buf;
        strncpy(code_buf, raw_buf, code_len);
        code_buf[code_len] = '\0';
    } else {
        strcpy(code_buf, raw_buf);
    }

    // Trim whitespace borders from the code space
    char *code_end = code_buf + strlen(code_buf);
    while (code_end > code_buf && isspace((unsigned char)*(code_end - 1))) {
        *(--code_end) = '\0';
    }
    char *code_start = code_buf;
    while (*code_start && isspace((unsigned char)*code_start)) {
        code_start++;
    }

    // Flag used to signal if this line updates our debug instruction mapping
    bool record_instruction = false;

    // --- CASE A: Pure Comment Line ---
    if (*code_start == '\0' && comment_ptr != NULL) {
        // Print the comment exactly as written, preserving manual layout
        fprintf(out(), "%s\n", raw_buf);
    }
    // --- CASE B: Assembly Label ---
    // Colon immunity achieved: we only scan the isolated code string code_start!
    else if (strchr(code_start, ':') != NULL) {
        record_instruction = true;
        if (comment_ptr != NULL) {
            fprintf(out(), "%-16s %s\n", code_start, comment_ptr);
        } else {
            fprintf(out(), "%s\n", code_start);
        }
    }
    // --- CASE C: Standard Instruction ---
    else {
        record_instruction = true;
        char *opcode = code_start;
        char *operands = NULL;
        char *first_space = strpbrk(opcode, " \t");

        if (first_space != NULL) {
            *first_space = '\0'; // Terminate opcode string token
            operands = first_space + 1;
            while (*operands && isspace((unsigned char)*operands)) {
                operands++; // Advance to the start of the operands
            }
        }

        // --- PEEPHOLE OPTIMIZER (-O1) ---
        char dest_buf[128] = {0};
        char src_buf[128]  = {0};

        if (operands != NULL) {
            char op_copy[256];
            strncpy(op_copy, operands, sizeof(op_copy) - 1);
            char *comma = strchr(op_copy, ',');
            if (comma != NULL) {
                *comma = '\0';
                strcpy(dest_buf, op_copy);
                strcpy(src_buf, comma + 1);
                trim_spaces(dest_buf);
                trim_spaces(src_buf);
            }
        }

        if (o_optflag >= 1 && dest_buf[0] != '\0' && src_buf[0] != '\0') {
            if (strcmp(opcode, "MOV") == 0) {
                // Rule 1: Eliminate self-moves (e.g., MOV R0, R0 or MOV [var_x], [var_x])
                if (strcmp(dest_buf, src_buf) == 0) {
                    return; // Suppress instruction completely!
                }
                // Rule 2: Eliminate redundant memory reloads (MOV A, B followed by MOV B, A)
                if (strcmp(last_emitted_inst, "MOV") == 0 &&
                    strcmp(dest_buf, last_emitted_src) == 0 &&
                    strcmp(src_buf, last_emitted_dest) == 0) {
                    return; // Suppress redundant reload!
                }
            }
        }

        // Apply auto-formatting: 4-space indent, 5-char left-aligned opcode width
        fprintf(out(), "    %-5s", opcode);

        if (operands != NULL && *operands != '\0') {
            fprintf(out(), " %s", operands);
        }

        // Append manual comment while accurately evaluating manual pre-padding
        if (comment_ptr != NULL) {
            size_t raw_comment_offset = comment_ptr - raw_buf;
            size_t code_length = (operands ? (operands - code_buf) + strlen(operands) : strlen(opcode));

            int spaces_to_pad = (int)(raw_comment_offset - code_length);
            if (spaces_to_pad < 1) spaces_to_pad = 1;

            for (int i = 0; i < spaces_to_pad; i++) {
                fputc(' ', out());
            }
            fprintf(out(), "%s", comment_ptr);
        }
        fprintf(out(), "\n");

        // --- UPDATE PEEPHOLE TRACKING STATE ---
        if (strchr(code_start, ':') != NULL ||
            strncmp(opcode, "JMP", 3) == 0 || strncmp(opcode, "JT", 2) == 0 ||
            strncmp(opcode, "JF", 2) == 0 || strncmp(opcode, "CALL", 4) == 0 ||
            strncmp(opcode, "RET", 3) == 0) {
            // Jumps, labels, and calls break straight-line execution flow; invalidate cache!
            last_emitted_inst[0] = '\0';
            last_emitted_dest[0] = '\0';
            last_emitted_src[0] = '\0';
        } else {
            strncpy(last_emitted_inst, opcode, sizeof(last_emitted_inst) - 1);
            strncpy(last_emitted_dest, dest_buf, sizeof(last_emitted_dest) - 1);
            strncpy(last_emitted_src, src_buf, sizeof(last_emitted_src) - 1);
        }
    }

    // =========================================================================
    // SECTION 2: INTEGRATED DEBUG REGISTRATION HOOK
    // =========================================================================
    // Only instructions and labels count towards our active program sequence line calculations.
    if (g_debug_mode && record_instruction && temp_debug_stream != NULL)
    {
        if (g_current_label[0] != '\0')
        {
            // Log entry point step-vector with its functional label context
            fprintf(temp_debug_stream, "%d,%d,%s\n", g_temp_asm_line, g_current_lua_line, g_current_label);
            g_current_label[0] = '\0'; // Reset label cache once committed
        }
        else
        {
            // Log regular operational line steps
            fprintf(temp_debug_stream, "%d,%d\n", g_temp_asm_line, g_current_lua_line);
        }

        g_temp_asm_line++; // Move tracking position down by one assembly entry
    }
}

void  emit_interpolated_asm (const char *raw_code)
{
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

int calculate_lua_heap_start(void) {
    int effective_start = o_config.ffi_ram_reserve_words;

    // If C header metadata indicates static allocations exceed default/configured reserve, bump automatically!
    if (o_config.ffi_max_mem_detected > 0) {
        int auto_calculated = o_config.ffi_max_mem_detected + FFI_SAFETY_PADDING;
        if (auto_calculated > effective_start) {
            effective_start = auto_calculated;
        }
    }

    return effective_start;
}

void emit_runtime_init(FILE *out) {
    int heap_start_addr = calculate_lua_heap_start();

    fprintf(out, "    ; --- v32lua Heap Base Initialization ---\n");
    fprintf(out, "    ; FFI Reserved Offset: %d words (%d KB)\n",
            heap_start_addr, (heap_start_addr * 4) / 1024);
    fprintf(out, "    MOV [heap_pointer], %d\n", heap_start_addr);
}

void  emit_cart_xml (const char *input_filename, int  verbose)
{
    // 1. Allocate enough memory for the filename plus ".xml" and the null terminator
    size_t  len           = strlen (input_filename);
    char   *xml_filename  = (char *) malloc (len + 5); 
    char   *vbin_path     = (char *) malloc (len + 6); 
    char   *resource      = NULL;
    char   *last_dot      = NULL;

    if (xml_filename     == NULL)
    {
        fprintf (stderr, "Compiler Error: Memory allocation failed for XML filename.\n");
        exit (2);
    }

    if (vbin_path        == NULL)
    {
        fprintf (stderr, "Compiler Error: Memory allocation failed for VBIN filename.\n");
        exit (3);
    }

    // 2. Copy the input filename (e.g., "example.lua")
    strcpy (vbin_path,    input_filename);
    last_dot              = strrchr (vbin_path, '.');
    if (last_dot         != NULL)
    {
        // Overwrite from the dot onward: "example.lua" -> "example.xml"
        strcpy (last_dot, ".vbin");
    }
    else
    {
        // If no extension was found (e.g., "example"), just append ".xml"
        strcat (vbin_path, ".vbin");
    }

    // 3. Find the last dot to locate the file extension
    strcpy (xml_filename, input_filename);
    last_dot              = strrchr (xml_filename, '.');
    if (last_dot         != NULL)
    {
        // Overwrite from the dot onward: "example.lua" -> "example.xml"
        strcpy (last_dot, ".xml");
    }
    else
    {
        // If no extension was found (e.g., "example"), just append ".xml"
        strcat (xml_filename, ".xml");
    }

    // 4. Open the newly named XML file for writing
    FILE *xml          = fopen (xml_filename, "w");
    if (xml           == NULL)
    {
        fprintf (stderr, "Compiler Error: Could not create XML cart file '%s'.\n", xml_filename);
        free (xml_filename);
        exit (4);
    }

    if (cart_version[0] == 34) {
        size_t vlen = strlen(cart_version);
        if (vlen >= 2 && cart_version[vlen - 1] == 34) {
            cart_version[vlen - 1] = '\0'; // Remove trailing quote
            memmove(cart_version, cart_version + 1, vlen - 1); // Shift out leading quote
        }
    }

    // 5. Emit the Vircon32 XML configuration
    fprintf (xml, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\" ?>\n");
    fprintf (xml, "<rom-definition version=\"1.0\">\n");
    fprintf (xml, "    <rom type=\"cartridge\" title=\"%s\" version=\"%s\" />\n", cart_title, cart_version);
    fprintf (xml, "<binary path=\"%s\" />\n", vbin_path);
    
    if (textures_head != NULL) {
        fprintf(xml, "<textures>\n");
        CARTresource* curr = textures_head;
        while (curr != NULL) {

            len           = strlen (curr -> filename);
            resource      = (char *) malloc (sizeof (char) * (len + 6));
            last_dot      = NULL;

            strcpy (resource,    curr -> filename);
            last_dot              = strrchr (resource, '.');
            if (last_dot         != NULL)
            {
                // Overwrite from the dot onward: "example.lua" -> "example.xml"
                strcpy (last_dot, ".vtex");
            }
            else
            {
                // If no extension was found (e.g., "example"), just append ".xml"
                strcat (resource, ".vtex");
            }
            fprintf(xml, "    <texture path=\"%s\" /> <!-- %s -->\n", 
                    resource, curr -> var_name);
            curr = curr->next;
            free (resource);
            resource      = NULL;
        }
        fprintf(xml, "</textures>\n");
    }
    else
    {
        fprintf (xml, "<textures />\n");
    }
    
    if (sounds_head        != NULL)
    {
        fprintf (xml, "<sounds>\n");
        CARTresource *curr  = sounds_head;
        while (curr        != NULL)
        {
            len           = strlen (curr -> filename);
            resource      = (char *) malloc (sizeof (char) * (len + 6));
            last_dot      = NULL;

            strcpy (resource,    curr -> filename);
            last_dot              = strrchr (resource, '.');
            if (last_dot         != NULL)
            {
                strcpy (last_dot, ".vsnd");
            }
            else
            {
                strcat (resource, ".vsnd");
            }
            fprintf (xml, "    <sound path=\"%s\" /> <!-- %s -->\n",
                     resource, curr -> var_name);
            curr            = curr -> next;
            free (resource);
            resource      = NULL;
        }
        fprintf (xml, "</sounds>\n");
    }
    else
    {
        fprintf (xml, "<sounds />\n");
    }

    fprintf(xml, "</rom-definition>\n");

    fclose (xml);

    // Remove direct stdout printing; rely on main.c stage reporting
    if (verbose)
    {
        ;
        // Optional debug detail if desired:
        // printf("; Generated Vircon32 cart config: %s\n", xml_filename);
        //printf("; Successfully generated Vircon32 cart config: %s\n", xml_filename);
    }

    free (xml_filename);
    free (vbin_path);
}

// Emits Vircon32 assembly to jump to target_label if reg is TRUTHY!
// (i.e., NOT Nil and NOT False). Uses scratch register.
void emit_truthy_jump(int reg, const char *target_label)
{
    int check_id = get_next_label();
    const char *ctx = get_current_function_name(); // Fetch context
    char eval_right_label[128];
    snprintf(eval_right_label, sizeof(eval_right_label), "__%s_truthy_fail_%d", ctx, check_id); // Prefix added
    int  scratch_reg  = allocate_register ();

    // 1. If it IS Nil, it's not truthy -> jump to evaluate right operand
    emit_asm("MOV R%d, R%d ; Copy to scratch register\n", scratch_reg, reg);
    emit_asm("IEQ R%d, 0xFFC00000 ; Is it Nil?\n", scratch_reg);
    emit_asm("JT R%d, %s ; If Nil, do not short-circuit\n", scratch_reg, eval_right_label);

    // 2. If it IS False, it's not truthy -> jump to evaluate right operand
    emit_asm("MOV R%d, R%d ; Copy to scratch register\n", scratch_reg, reg);
    emit_asm("IEQ R%d, 0xFFC00001 ; Is it False?\n", scratch_reg);
    emit_asm("JT R%d, %s ; If False, do not short-circuit\n", scratch_reg, eval_right_label);

    // 3. If we survived both checks, the value is TRUTHY! Short-circuit!
    emit_asm("JMP %s ; Value is truthy -> short-circuit!\n", target_label);

    emit_asm("%s:\n", eval_right_label);

    unlock_register (scratch_reg);
}

// Emits Vircon32 assembly to jump to target_label if reg holds Nil or False.
// Uses scratch register to prevent destructive comparison bugs!
void  emit_falsy_jump (int  reg, const char *target_label)
{
    int  scratch_reg  = allocate_register ();
    // 1. Test against canonical Nil (0xFFC00000)
    emit_asm("MOV R%d, R%d ; Copy condition to scratch register\n", scratch_reg, reg);
    emit_asm("IEQ R%d, 0xFFC00000 ; Destructive test: Is it Nil?\n", scratch_reg);
    emit_asm("JT R%d, %s ; If Nil (falsy), jump to target\n", scratch_reg, target_label);

    // 2. Test against Boolean False (0xFFC00001)
    emit_asm("MOV R%d, R%d ; Copy condition to scratch register\n", scratch_reg, reg);
    emit_asm("IEQ R%d, 0xFFC00001 ; Destructive test: Is it False?\n", scratch_reg);
    emit_asm("JT R%d, %s ; If False (falsy), jump to target\n", scratch_reg, target_label);

    unlock_register (scratch_reg);
}

int   emit_variable_map (void)
{
    int  lines_printed       = 2;
    fprintf(out(), "%%define heap_pointer 0\n");
    
    SymbolNode *curr = global_scope ? global_scope->symbols : NULL;
    while (curr != NULL)
    {
        if (curr->is_function)
            fprintf(out(), "%%define func_%s %d\n", curr->name, curr->location);
        else
            fprintf(out(), "%%define var_%s %d\n", curr->name, curr->location);
        lines_printed    = lines_printed + 1;
        curr = curr->next;
    }
    fprintf(out(), "\n;; Highest used global RAM address: %d\n", next_ram_address - 1);
    fprintf(out(), ";; Dynamic heap will start at runtime address: %d\n\n", next_ram_address);
    lines_printed    = lines_printed + 2;
    return (lines_printed);
}

void  emit_string_data_section (void)
{
    emit_asm ("\n;; =========================================================");
    emit_asm (";; Read-Only String Data Section");
    emit_asm (";; =========================================================");

    if (strings_head               != NULL)
    {
        fprintf (out(), "\n; --- String Literal Allocations ---\n");
        StringLiteralNode *current  = strings_head;
        while (current             != NULL)
        {
            fprintf (out(), "__string_%d:\n", current -> id);
            fprintf (out(), "    string \"%s\"\n\n", current -> value);
            current                 = current -> next;
        }
    }
}

void  emit_runtime_library (void)
{
    emit_asm("\n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n");
    emit_asm(";;\n");
    emit_asm(";; Lua assembly support Runtime Library Subroutines\n");
    emit_asm(";;\n");
    emit_asm(";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n");
    emit_asm("\n");

    // Point our cursor to the start of the embedded Vircon32 assembly
    const char* cursor = runtime_asm_start;
    char line[1024];

    // Read until we hit the null terminator we appended in .S
    while (*cursor != '\0')
    {
        int i = 0;
        
        // Extract a single line up to the newline character or buffer capacity
        while (*cursor != '\0' && *cursor != '\n' && i < (int)sizeof(line) - 2)
        {
            line[i++] = *cursor++;
        }
        
        // Preserve the newline character if present
        if (*cursor == '\n')
        {
            line[i++] = *cursor++;
        }
        
        line[i] = '\0';
        
        // Pass the line through your special formatting function
        emit_asm("%s", line);
    }

    emit_asm("\n;;\n");
    emit_asm(";; End of Runtime Library\n");
    emit_asm(";;\n");
    emit_asm(";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;");
    emit_asm(";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n");
}

void  emit_get_gamepad_inputs_intrinsic (int  dest_reg)
{
    int  bit_reg  = allocate_register();
    emit_asm ("    ;; --- Intrinsic: Read Gamepad Inputs, collate into one word ---\n");
    emit_asm ("MOV R%d, 0\n", dest_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadLeft");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 10\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadRight");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 9\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadUp");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 8\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadDown");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 7\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonStart");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 6\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonA");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 5\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonB");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 4\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonX");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 3\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonY");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 2\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonL");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("SHL R%d, 1\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("IN R%d, %s\n", bit_reg, "INP_GamepadButtonR");
    emit_asm ("IGT R%d, 0\n", bit_reg);
    emit_asm ("OR R%d, R%d\n", dest_reg, bit_reg);
    emit_asm ("    ;; --- Intrinsic: Cast to Lua Float ---\n");
    emit_asm ("CIF R%d\n", dest_reg);
    unlock_register (bit_reg);
}

void emit_table_set_literal(int table_reg, const char *property_name, int value_reg)
{
    // 1. Intern the property name into the compiler's string pool and get its ID
    int string_id = add_string_literal(property_name);

    emit_asm("    ;; Set table property: .%s = value", property_name);

    // 2. Push Table Pointer (Arg 1 -> [BP+4])
    emit_asm("PUSH R%d             ; Arg 1: Table pointer", table_reg);

    // 3. Load and Box Key as ROM String, then Push (Arg 2 -> [BP+3])
    int scratch = allocate_register();
    emit_asm("MOV  R%d, __string_%d", scratch, string_id);
    emit_asm("OR   R%d, 0x7FC00000 ; Box key as ROM String", scratch);
    emit_asm("PUSH R%d             ; Arg 2: Property Key", scratch);
    unlock_register(scratch);

    // 4. Push Value (Arg 3 -> [BP+2])
    emit_asm("PUSH R%d             ; Arg 3: Value to store", value_reg);

    // 5. Call Routine and Clean Stack (3 arguments = 3 words)
    emit_asm("CALL __builtin_table_set");
    emit_asm("IADD SP, 3           ; Clean up stack arguments");
}

void emit_table_get_literal(int table_reg, const char *property_name)
{
    // 1. Intern the property name into the compiler's string pool and get its ID
    int string_id = add_string_literal(property_name);

    emit_asm("    ;; Lookup table property: .%s", property_name);

    // 2. Push Table Pointer (Arg 1)
    emit_asm("PUSH R%d             ; Arg 1: Table pointer", table_reg);

    // 3. Load and Box Key as ROM String, then Push (Arg 2)
    int scratch = allocate_register();
    emit_asm("MOV  R%d, __string_%d", scratch, string_id);
    emit_asm("OR   R%d, 0x7FC00000 ; Box key as ROM String", scratch);
    emit_asm("PUSH R%d             ; Arg 2: Property Key", scratch);
    unlock_register(scratch);

    // 4. Call Routine and Clean Stack
    emit_asm("CALL __builtin_table_get");
    emit_asm("IADD SP, 2           ; Clean up stack arguments");

    // 5. Capture Return Value
    emit_asm("MOV  R%d, R0         ; Store returned value", table_reg);
}
