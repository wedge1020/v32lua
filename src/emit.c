#include "v32lua.h"

void  emit_asm (const char *format, ...)
{
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

void  emit_cart_xml (const char *input_filename)
{
    // 1. Allocate enough memory for the filename plus ".xml" and the null terminator
    size_t len = strlen(input_filename);
    char* xml_filename = (char*)malloc(len + 5); 
    if (!xml_filename) {
        fprintf(stderr, "Compiler Error: Memory allocation failed for XML filename.\n");
        return;
    }

    // 2. Copy the input filename (e.g., "example.lua")
    strcpy(xml_filename, input_filename);

    // 3. Find the last dot to locate the file extension
    char* last_dot = strrchr(xml_filename, '.');
    if (last_dot != NULL) {
        // Overwrite from the dot onward: "example.lua" -> "example.xml"
        strcpy(last_dot, ".xml");
    } else {
        // If no extension was found (e.g., "example"), just append ".xml"
        strcat(xml_filename, ".xml");
    }

    // 4. Open the newly named XML file for writing
    FILE* xml = fopen(xml_filename, "w");
    if (!xml) {
        fprintf(stderr, "Compiler Error: Could not create XML cart file '%s'.\n", xml_filename);
        free(xml_filename);
        return;
    }

    // 5. Emit the Vircon32 XML configuration
    fprintf(xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    fprintf(xml, "<cartridge version=\"%s\">\n", cart_version);
    fprintf(xml, "  <title>%s</title>\n", cart_title);
    
    if (textures_head != NULL) {
        fprintf(xml, "  <textures>\n");
        CARTresource* curr = textures_head;
        while (curr != NULL) {
            fprintf(xml, "    <texture id=\"%d\" path=\"%s\" /> <!-- %s -->\n", 
                    curr->id, curr->filename, curr->var_name);
            curr = curr->next;
        }
        fprintf(xml, "  </textures>\n");
    }
    
    fprintf(xml, "</cartridge>\n");
    fclose(xml);

    printf("; Successfully generated Vircon32 cart config: %s\n", xml_filename);
    
    // 6. Clean up allocated memory
    free(xml_filename);
}

// Emits Vircon32 assembly to jump to target_label if reg is TRUTHY!
// (i.e., NOT Nil and NOT False). Uses scratch register R6.
void  emit_truthy_jump (int  reg, const char *target_label)
{
    int check_id = get_next_label();
    char eval_right_label[128];
    snprintf(eval_right_label, sizeof(eval_right_label), "__truthy_fail_%d", check_id);

    // 1. If it IS Nil, it's not truthy -> jump to evaluate right operand
    emit_asm("MOV R6, R%d ; Copy to scratch register R6\n", reg);
    emit_asm("IEQ R6, 0xFFC00000 ; Is it Nil?\n");
    emit_asm("JT R6, %s ; If Nil, do not short-circuit\n", eval_right_label);

    // 2. If it IS False, it's not truthy -> jump to evaluate right operand
    emit_asm("MOV R6, R%d ; Copy to scratch register R6\n", reg);
    emit_asm("IEQ R6, 0xFFC00001 ; Is it False?\n");
    emit_asm("JT R6, %s ; If False, do not short-circuit\n", eval_right_label);

    // 3. If we survived both checks, the value is TRUTHY! Short-circuit!
    emit_asm("JMP %s ; Value is truthy -> short-circuit!\n", target_label);

    emit_asm("%s:\n", eval_right_label);
}

// Emits Vircon32 assembly to jump to target_label if reg holds Nil or False.
// Uses scratch register R6 to prevent destructive comparison bugs!
void  emit_falsy_jump (int  reg, const char *target_label)
{
    // 1. Test against canonical Nil (0xFFC00000)
    emit_asm("MOV R6, R%d ; Copy condition to scratch register R6\n", reg);
    emit_asm("IEQ R6, 0xFFC00000 ; Destructive test: Is it Nil?\n");
    emit_asm("JT R6, %s ; If Nil (falsy), jump to target\n", target_label);

    // 2. Test against Boolean False (0xFFC00001)
    emit_asm("MOV R6, R%d ; Copy condition to scratch register R6\n", reg);
    emit_asm("IEQ R6, 0xFFC00001 ; Destructive test: Is it False?\n");
    emit_asm("JT R6, %s ; If False (falsy), jump to target\n", target_label);
}

void  emit_variable_map (void)
{
    if (global_scope    == NULL) return;
    
    SymbolNode *current  = global_scope -> symbols;
    while (current      != NULL)
    {
        fprintf (stdout, "%%define %s%s %d\n", 
                 current -> is_function ? "func_" : "var_", 
                 current -> name, 
                 current -> location);
        current          = current -> next;
    }
}

void  emit_string_data_section (void)
{
    if (strings_head == NULL) return;
    
    printf("\n; --- String Literal Allocations ---\n");
    StringLiteralNode* current = strings_head;
    while (current != NULL) {
        printf("__string_%d:\n", current->id);
        printf("  integer ");
        for (int i = 0; current->value[i] != '\0'; i++) {
            printf("%d, ", (int)current->value[i]);
        }
        printf("0\n"); 
        current = current->next;
    }
}
