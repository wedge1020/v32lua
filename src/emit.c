#include "v32lua.h"

// In emit.c, replace all 1024-byte buffers with 8192:
#define EMIT_BUFFER_SIZE 8192

// A colon inside a quoted string literal (e.g. the "string \"...: ...\""
// directive) does not make the line an assembly label. Only count a colon
// that appears before the first '"' on the line -- real labels never
// contain a quote at all, so this is exact for both cases without needing
// a full quote-state scanner.
static bool line_is_asm_label (const char *code_start)
{
    const char *first_colon = strchr (code_start, ':');
    if (first_colon == NULL) {
        return false;
    }
    const char *first_quote = strchr (code_start, '"');
    return (first_quote == NULL || first_colon < first_quote);
}

/**
 * Emits a line of Vircon32 assembly code.
 *
 * This function handles:
 * - Formatting and outputting assembly instructions
 * - Partitioning code from comments (at first semicolon)
 * - Tracking debug information for each emitted instruction
 * - Isolating operands (dest and src) for external analysis
 *
 * For standard instructions (Case C), operands are parsed and isolated:
 * - dest: First operand (before comma), or NULL if none exists
 * - src: Second operand (after comma), or NULL if none exists
 * - Both are trimmed of whitespace
 * - Works with registers (R0-R31), immediates, dereferences ([addr]), labels, etc.
 *
 * Optimization code has been removed - external tool will handle optimizations.
 * Operand isolation is preserved for external analysis.
 *
 * @param format Printf-style format string for the assembly line
 * @param ...    Variable arguments for the format string
 */
void  emit_asm (const char *format, ...) {
    char raw_buf[EMIT_BUFFER_SIZE];
    va_list args;
    va_start(args, format);
    vsnprintf(raw_buf, sizeof(raw_buf), format, args);
    va_end(args);

    // =========================================================================
    // SPECIAL HANDLING: Detect WAIT instruction in main()
    // This is preserved as it's not optimization but runtime behavior detection
    // =========================================================================
    if (strcmp(get_current_function_name(), "main") == 0) {
        // Look for the "WAIT" instruction or opcode in the raw buffer
        if (strstr(raw_buf, "WAIT") != NULL) {
            w_mainwait = 0;
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
    char code_buf[EMIT_BUFFER_SIZE] = {0};

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

    // =========================================================================
    // CASE A: Pure Comment Line
    // =========================================================================
    if (*code_start == '\0' && comment_ptr != NULL) {
        // Print the comment exactly as written, preserving manual layout
        fprintf(out(), "%s\n", raw_buf);
    }
    // =========================================================================
    // CASE B: Assembly Label (contains colon)
    // Colon immunity: we only scan the isolated code string code_start!
    // =========================================================================
    else if (line_is_asm_label (code_start)) {
        record_instruction = true;
        if (comment_ptr != NULL) {
            fprintf(out(), "%-16s %s\n", code_start, comment_ptr);
        } else {
            fprintf(out(), "%s\n", code_start);
        }
    }
    // =========================================================================
    // CASE C: Standard Instruction
    // This is where we parse and isolate operands for external use
    // =========================================================================
    else {
        record_instruction = true;
        char *opcode = code_start;
        char *operands = NULL;
        char *first_space = strpbrk(opcode, " \t");

        // --- Parse opcode and operands ---
        if (first_space != NULL) {
            *first_space = '\0'; // Terminate opcode string token
            operands = first_space + 1;
            while (*operands && isspace((unsigned char)*operands)) {
                operands++; // Advance to the start of the operands
            }
        }

        // =====================================================================
        // OPERAND ISOLATION: Extract dest and src for external analysis
        // These variables can be used by external tools for validation, analysis,
        // or optimization. They are set to NULL when the operand doesn't exist.
        // =====================================================================
        char *dest = NULL;  // First operand (destination), or NULL
        char *src = NULL;   // Second operand (source), or NULL
        char op_copy[EMIT_BUFFER_SIZE];  // dest/src point into this: keep it in scope

        if (operands != NULL && *operands != '\0') {
            strncpy(op_copy, operands, sizeof(op_copy) - 1);
            op_copy[sizeof(op_copy) - 1] = '\0'; // Ensure null-termination

            char *comma = strchr(op_copy, ',');

            if (comma != NULL) {
                // Two operands: dest, src
                *comma = '\0';

                // Extract and trim destination operand
                char *dest_start = op_copy;
                char *dest_end = comma;
                while (dest_end > dest_start && isspace((unsigned char)*(dest_end - 1))) {
                    *(--dest_end) = '\0';
                }
                while (*dest_start && isspace((unsigned char)*dest_start)) {
                    dest_start++;
                }
                if (*dest_start != '\0') {
                    dest = dest_start;
                }

                // Extract and trim source operand
                char *src_start = comma + 1;
                while (*src_start && isspace((unsigned char)*src_start)) {
                    src_start++;
                }
                char *src_end = src_start + strlen(src_start);
                while (src_end > src_start && isspace((unsigned char)*(src_end - 1))) {
                    *(--src_end) = '\0';
                }
                if (*src_start != '\0') {
                    src = src_start;
                }
            } else {
                // Single operand: could be dest-only (e.g., "PUSH R0") or src-only
                // We treat it as dest for consistency, src remains NULL
                char *single_start = op_copy;
                char *single_end = op_copy + strlen(op_copy);
                while (single_end > single_start && isspace((unsigned char)*(single_end - 1))) {
                    *(--single_end) = '\0';
                }
                while (*single_start && isspace((unsigned char)*single_start)) {
                    single_start++;
                }
                if (*single_start != '\0') {
                    dest = single_start;
                    // src remains NULL
                }
            }
        }
        // If no operands at all (e.g., "HLT", "WAIT", "RET"), both remain NULL

        // =====================================================================
        // OUTPUT: Emit the instruction with proper formatting
        // =====================================================================

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

        // =====================================================================
        // UPDATE TRACKING STATE: Keep for external tools if needed
        // These global variables track the last emitted instruction for reference
        // =====================================================================
        if (strchr(code_start, ':') != NULL ||
            strncmp(opcode, "JMP", 3) == 0 || strncmp(opcode, "JT", 2) == 0 ||
            strncmp(opcode, "JF", 2) == 0 || strncmp(opcode, "CALL", 4) == 0 ||
            strncmp(opcode, "RET", 3) == 0) {
            // Jumps, labels, and calls break straight-line execution flow
            last_emitted_inst[0] = '\0';
            last_emitted_dest[0] = '\0';
            last_emitted_src[0] = '\0';
        } else {
            snprintf (last_emitted_inst, sizeof (last_emitted_inst), "%.*s", (int) sizeof (last_emitted_inst) - 1, opcode);
            snprintf (last_emitted_dest, sizeof (last_emitted_dest), "%.*s", (int) sizeof (last_emitted_dest) - 1, dest ? dest : "");
            snprintf (last_emitted_src,  sizeof (last_emitted_src),  "%.*s", (int) sizeof (last_emitted_src) - 1,  src  ? src  : "");
        }

        // Immediate stderr output in verbose debug mode
        if (g_verbose_debug) {
            fprintf(stderr, "[debug] emit_asm(): %s\n", raw_buf);
        }

        // =========================================================================
        // UPDATE REGISTER LIVE TRACKING (only for registers actually touched)
        // =========================================================================
        update_if_register (dest);
        update_if_register (src);
    }

    // =========================================================================
    // SECTION 2: INTEGRATED DEBUG REGISTRATION HOOK
    // =========================================================================
    // Only instructions and labels count towards our active program sequence line calculations.
    if (g_debug_mode && record_instruction && temp_debug_stream != NULL) {
        if (g_current_label[0] != '\0') {
            // Log entry point step-vector with its functional label context
            fprintf(temp_debug_stream, "%d,%d,%s\n", g_temp_asm_line, g_current_lua_line, g_current_label);
            g_current_label[0] = '\0'; // Reset label cache once committed
        } else {
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
            char var_name[EMIT_BUFFER_SIZE];
            int i = 0;
            while (*p && *p != '}' && i < 255) var_name[i++] = *p++;
            var_name[i] = '\0'; 
            if (*p == '}') p++; 
            
            // Format the variable and append it to our buffer
            // {name} is the variable's memory operand: [BP - n] for a
            // local or parameter in scope, [var_name] for a global (it
            // used to be [var_name] always, so a local silently read and
            // wrote a global of the same name instead).
            char formatted_var[EMIT_BUFFER_SIZE+8];
            get_variable_access_string(var_name, formatted_var);
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
    fprintf(out, "    MOV [HEAP_POINTER], %d\n", heap_start_addr);
}

// ----------------------------------------------------------------------------
// Cartridge XML
//
// packrom resolves every path in the XML relative to the XML file itself. So,
// by default (preserve_paths == 0):
//
//   * the XML is written beside the output file (-o obj/game.asm gives
//     obj/game.xml) and holds BARE file names: <binary path="game.vbin" />,
//     <texture path="spaceship.vtex" /> for --#texture S "textures/spaceship.png".
//     The produced .vbin/.vtex/.vsnd files are expected beside the XML.
//   * two assets that collapse to the same file name keep as much of their
//     directories as it takes to tell them apart: textures/ship.png followed
//     by textures/extra/ship.png gives ship.vtex and extra/ship.vtex (the
//     latter expected in <xml dir>/extra/). The first one to claim a name
//     keeps the short form; only two assets whose whole paths collapse to the
//     same name still draw a warning.
//
// With preserve_paths (--xml-preserve-paths):
//
//   * each --#texture/--#sound path is kept as written in the hint (only the
//     extension changes), the XML goes in the PROJECT folder under the
//     output's base name -- the source file's directory (the hints' own point
//     of reference), or its parent when the source is in src/ and the output
//     in a sibling such as obj/ -- and <binary> is the .vbin path relative to
//     it. Hint paths are re-based onto that folder when it is the parent
//     (textures/ship.png becomes src/textures/ship.vtex).
//   * assets the compiler itself generates (PICO-8/TIC-80 sprite sheets and
//     sounds) live beside the output file, so they are written relative to
//     the XML's directory too.
//
// A twin for the optimized build (v32opt) is written next to every XML:
// game.xml -> game.vbin, gameOpt.xml -> gameOpt.vbin, identical otherwise.
// ----------------------------------------------------------------------------

static int   g_xml_warn_collisions = 1;     // once per run, not once per XML
static char *g_xml_src_dir         = NULL;  // the source file's directory (for --xml-preserve-paths)

// Components of `buf` ('/' or '\' separated) with empty, "." and ".." parts
// dropped; `parts` points into `buf`. Returns the count.
static int xml_split_components (char *buf, const char **parts, int max_parts)
{
    int n = 0;

    for (char *tok = buf; *tok != '\0'; )
    {
        char *end = tok;
        while (*end != '\0' && *end != '/' && *end != '\\') end++;
        char saved = *end;
        *end = '\0';
        if (tok[0] != '\0' && strcmp (tok, ".") != 0 && strcmp (tok, "..") != 0 && n < max_parts)
        {
            parts[n++] = tok;
        }
        if (saved == '\0') break;
        tok = end + 1;
    }
    return n;
}

// The file `r` names once converted: the hint's extension swapped for `ext`
// (".vtex"/".vsnd"). A compiler-generated resource is registered without its
// extension (or already with it), so `ext` is appended only when missing --
// swapping would eat the tail of a name such as "obj/my.game_pico8".
static char *xml_full_name (const CARTresource *r, const char *ext)
{
    if (r->generated)
    {
        size_t len = strlen (r->filename), elen = strlen (ext);
        char  *out = malloc (len + elen + 1);

        if (out == NULL) { fprintf (stderr, "Compiler Error: Memory allocation failed for XML path.\n"); exit (2); }
        strcpy (out, r->filename);
        if (len < elen || strcmp (out + len - elen, ext) != 0) strcat (out, ext);
        return out;
    }
    return replace_extension (r->filename, ext);
}

// `full` reduced to its last `depth` components, joined with '/'.
// *total receives how many components `full` has.
static char *xml_name_with_depth (const char *full, int depth, int *total)
{
    char        *buf   = strdup (full);
    const char  *parts[64];
    int          n     = xml_split_components (buf, parts, 64);
    char        *joined;

    if (n == 0) { parts[0] = path_basename (full); n = 1; }
    if (depth > n) depth = n;

    joined = malloc (strlen (full) + 2);
    if (buf == NULL || joined == NULL) { fprintf (stderr, "Compiler Error: Memory allocation failed for XML path.\n"); exit (2); }
    joined[0] = '\0';
    for (int k = n - depth; k < n; k++)
    {
        if (k > n - depth) strcat (joined, "/");
        strcat (joined, parts[k]);
    }
    *total = n;
    free (buf);
    return joined;
}

// The XML path of every resource in the list, in order (malloc'd array of
// malloc'd strings, `count` long; the caller frees). See the notes above.
char **cart_xml_resolve_names (CARTresource *head, int count, const char *tag,
                                 const char *ext, int preserve_paths, const char *xml_dir)
{
    char          **names = calloc ((size_t) count + 1, sizeof (char *));
    char          **full  = calloc ((size_t) count + 1, sizeof (char *));
    CARTresource  **res   = calloc ((size_t) count + 1, sizeof (CARTresource *));
    int             i     = 0;

    if (names == NULL || full == NULL || res == NULL)
    {
        fprintf (stderr, "Compiler Error: Memory allocation failed for XML paths.\n");
        exit (2);
    }
    for (CARTresource *r = head; r != NULL && i < count; r = r->next, i++)
    {
        res[i]  = r;
        full[i] = xml_full_name (r, ext);
    }

    for (i = 0; i < count; i++)
    {
        if (preserve_paths)
        {
            // Hints as written; compiler-made files (beside the output) from the XML's directory.
            if (res[i]->generated || g_xml_src_dir == NULL)
            {
                names[i] = res[i]->generated ? path_relative_to (xml_dir, full[i]) : strdup (full[i]);
            }
            else
            {
                // A hint path is relative to the source file; the XML may sit one level up.
                char *from_src = malloc (strlen (g_xml_src_dir) + strlen (full[i]) + 2);
                if (from_src == NULL) { fprintf (stderr, "Compiler Error: Memory allocation failed for XML paths.\n"); exit (2); }
                sprintf (from_src, "%s/%s", g_xml_src_dir, full[i]);
                names[i] = path_relative_to (xml_dir, from_src);
                free (from_src);
            }
            continue;
        }

        int depth = 1, total = 1, clash;
        for (;;)
        {
            free (names[i]);
            names[i] = xml_name_with_depth (full[i], depth, &total);
            clash    = 0;
            for (int j = 0; j < i; j++)
            {
                if (strcmp (names[j], names[i]) != 0) continue;
                if (strcmp (res[j]->filename, res[i]->filename) == 0) continue;   // the very same file listed twice
                clash = 1;
                if (depth >= total && g_xml_warn_collisions)
                {
                    fprintf (stderr, "---- warning: %s '%s' and '%s' both become '%s' in the XML ----\n",
                             tag, res[j]->var_name ? res[j]->var_name : "<unnamed>",
                             res[i]->var_name ? res[i]->var_name : "<unnamed>", names[i]);
                }
                break;
            }
            if (!clash || depth >= total) break;
            depth++;
        }
    }

    for (i = 0; i < count; i++) free (full[i]);
    free (full);
    free (res);
    return names;
}

// One <textures>...</textures> or <sounds>...</sounds> block.
static void xml_emit_resources (FILE *xml, CARTresource *head, const char *tag,
                                const char *ext, int preserve_paths, const char *xml_dir)
{
    int count = 0;

    for (CARTresource *r = head; r != NULL; r = r->next) count++;
    if (count == 0)
    {
        fprintf (xml, "<%ss />\n", tag);
        return;
    }

    char **names = cart_xml_resolve_names (head, count, tag, ext, preserve_paths, xml_dir);
    int    index = 0;

    fprintf (xml, "<%ss>\n", tag);
    for (CARTresource *curr = head; curr != NULL; curr = curr->next, index++)
    {
        // Vircon32 numbers resources by their position here. If that ever
        // stops matching the id the compiler baked into the generated
        // code, every reference silently targets the wrong resource --
        // so say so loudly instead.
        if (curr->id != index && g_xml_warn_collisions)
        {
            compiler_warning (ERR_INTERNAL, -1,
                "cart XML: %s '%s' has resource id %d but is emitted at "
                "position %d; generated code will reference the wrong %s",
                tag, (curr->var_name != NULL) ? curr->var_name : "<unnamed>",
                curr->id, index, tag);
        }
        fprintf (xml, "    <%s path=\"%s\" /> <!-- %s -->\n", tag, names[index], curr->var_name);
        free (names[index]);
    }
    free (names);
    fprintf (xml, "</%ss>\n", tag);
}

// Where the XML for `output_filename` goes (malloc'd): beside the output, or
// (preserve_paths) under the same name in the project folder -- the source
// file's directory, or its parent when the source is in src/ and the output
// in a sibling such as obj/ (path_project_dir).
char *cart_xml_filename (const char *output_filename, const char *source_filename,
                         int preserve_paths)
{
    char *xml_name = replace_extension (output_filename, ".xml");

    if (!preserve_paths) return xml_name;

    char   *dir    = path_project_dir (source_filename, output_filename);
    size_t  cap    = strlen (dir) + strlen (xml_name) + 2;
    char   *result = malloc (cap);

    if (result == NULL) { fprintf (stderr, "Compiler Error: Memory allocation failed for XML filename.\n"); exit (2); }
    snprintf (result, cap, "%s/%s", dir, path_basename (xml_name));
    free (dir);
    free (xml_name);
    return result;
}

// The cart title the XML of `variant` shows ("" = the regular build, "Opt"
// = the optimized one). The optimized cart uses --titleopt / --#titleopt
// when given, else the title with " [optimized]" added -- unless
// --no-diff-opt-title / --#no-diff-opt-title keeps it the same.
static void cart_title_for_variant (const char *variant, char *out, size_t size)
{
    static const char suffix[] = " [optimized]";
    size_t            slen     = sizeof (suffix) - 1;
    size_t            tlen     = strlen (cart_title);

    if (variant[0] == '\0' || (!cart_title_opt_set && g_no_diff_opt_title))
    {
        snprintf (out, size, "%s", cart_title);
    }
    else if (cart_title_opt_set)
    {
        snprintf (out, size, "%s", cart_title_opt);
    }
    else if (tlen >= slen && strcmp (cart_title + tlen - slen, suffix) == 0)
    {
        snprintf (out, size, "%s", cart_title);      // already says so
    }
    else
    {
        // A long title is cut so the whole fits (cart_title's size).
        int room = (int) (sizeof (cart_title) - 1 - slen);
        snprintf (out, size, "%.*s%s", room, cart_title, suffix);
    }
}

// Writes one XML. `variant` is "" for the plain build and "Opt" for the
// optimized one: it goes before the extension of both the XML's name and
// the <binary> it references.
static void write_cart_xml (const char *output_filename, const char *source_filename,
                            int preserve_paths, const char *variant, int verbose)
{
    char *plain_xml    = cart_xml_filename (output_filename, source_filename, preserve_paths);
    char *variant_ext  = malloc (strlen (variant) + 8);
    char *xml_filename;
    char *xml_dir;
    char *vbin_full;
    char *vbin_path;

    if (variant_ext == NULL) { fprintf (stderr, "Compiler Error: Memory allocation failed for XML filename.\n"); exit (2); }
    sprintf (variant_ext, "%s.xml", variant);
    xml_filename = replace_extension (plain_xml, variant_ext);
    free (plain_xml);

    sprintf (variant_ext, "%s.vbin", variant);
    xml_dir   = path_dirname (xml_filename);
    vbin_full = replace_extension (output_filename, variant_ext);
    vbin_path = preserve_paths ? path_relative_to (xml_dir, vbin_full)
                               : strdup (path_basename (vbin_full));
    free (variant_ext);
    free (vbin_full);

    FILE *xml = fopen (xml_filename, "w");
    if (xml  == NULL)
    {
        fprintf (stderr, "Compiler Error: Could not create XML cart file '%s'.\n", xml_filename);
        exit (4);
    }

    if (cart_version[0] == 34) {
        size_t vlen = strlen(cart_version);
        if (vlen >= 2 && cart_version[vlen - 1] == 34) {
            cart_version[vlen - 1] = '\0'; // Remove trailing quote
            memmove(cart_version, cart_version + 1, vlen - 1); // Shift out leading quote
        }
    }

    fprintf (xml, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\" ?>\n");
    fprintf (xml, "<rom-definition version=\"1.0\">\n");
    // XML-escape the title: it can come from a file name or a cart's own
    // metadata ("Tom & Jerry", "\"quoted\""), not only from --#title.
    char xml_title[sizeof (cart_title) * 6];
    {
        char shown[sizeof (cart_title)];
        cart_title_for_variant (variant, shown, sizeof (shown));
        char *w = xml_title;
        for (const char *r = shown; *r; r++) {
            const char *e = (*r == '&') ? "&amp;" : (*r == '<') ? "&lt;" : (*r == '>') ? "&gt;"
                          : (*r == '"') ? "&quot;" : NULL;
            if (e) { strcpy (w, e); w += strlen (e); } else { *w++ = *r; }
        }
        *w = '\0';
    }
    fprintf (xml, "    <rom type=\"%s\" title=\"%s\" version=\"%s\" />\n",
             g_bios_mode ? "bios" : "cartridge", xml_title, cart_version);
    fprintf (xml, "<binary path=\"%s\" />\n", vbin_path);
    xml_emit_resources (xml, textures_head, "texture", ".vtex", preserve_paths, xml_dir);
    xml_emit_resources (xml, sounds_head,   "sound",   ".vsnd", preserve_paths, xml_dir);
    fprintf (xml, "</rom-definition>\n");
    fclose (xml);

    if (verbose)
    {
        fprintf (stdout, "saving cart config file %s\n", xml_filename);
    }

    free (xml_filename);
    free (xml_dir);
    free (vbin_path);
}

// Collision warnings (and the resource-id check) are printed once per run;
// the build-script generator turns them off while it asks for the names again.
void  cart_xml_set_quiet (int quiet)
{
    g_xml_warn_collisions = !quiet;
}

void  emit_cart_xml (const char *output_filename, const char *source_filename,
                     int preserve_paths, int verbose)
{
    free (g_xml_src_dir);
    g_xml_src_dir = path_dirname (source_filename);
    g_xml_warn_collisions = 1;
    write_cart_xml (output_filename, source_filename, preserve_paths, "", verbose);
    g_xml_warn_collisions = 0;          // the Opt twin would only repeat the warnings
    write_cart_xml (output_filename, source_filename, preserve_paths, "Opt", verbose);
    g_xml_warn_collisions = 1;
}

// Jump to target_label if reg is truthy (not nil, not false) / falsy.
// nil = 0xFFC00000 and false = 0xFFC00001, so falsy <=> (v & ~1) == nil:
// one test instead of two. (The scratch is a real allocated register:
// callers such as the for-in loop still need R0 after this.)
static void emit_truthiness_jump (int reg, bool when_true, const char *target_label)
{
    int scratch = allocate_register ();
    emit_asm("MOV  R%d, R%d\n", scratch, reg);
    emit_asm("AND  R%d, 0xFFFFFFFE\n", scratch);
    emit_asm("IEQ  R%d, BOXED_NIL ; 1 if nil or false\n", scratch);
    emit_asm("%s   R%d, %s\n", when_true ? "JF" : "JT", scratch, target_label);
    unlock_register (scratch);
}

void emit_truthy_jump (int reg, const char *target_label)
{
    emit_truthiness_jump (reg, true, target_label);
}

void  emit_falsy_jump (int  reg, const char *target_label)
{
    emit_truthiness_jump (reg, false, target_label);
}

int   emit_variable_map (void)
{
    int  lines_printed       = 2;
    // Program ROM page: a cartridge's code and data sit at 0x20000000, a
    // BIOS's (-b) at 0x10000000.
    fprintf (out(), "%%define  V32_CART_PAGE            %s\n", g_bios_mode ? "0x10000000" : "0x20000000");
    fprintf (out(), "%%define  NAN_VALUE                0x7F800000\n");
    fprintf (out(), "%%define  BOXED_CATEGORY           0x80000000 ; RAM(1), ROM(0)\n");
    fprintf (out(), "%%define  BOXED_TYPE               0x00400000 ; TABLE/FUNCTION (0), STRING (1)\n");
    fprintf (out(), "%%define  BOXED_DATA               0xFFC00000 ; common bitmask to indicate boxed data\n");
    fprintf (out(), "%%define  BOXED_FUNCTION           0x7F800000 ; bitmask for boxed lua function (ROM)\n");
    fprintf (out(), "%%define  BOXED_ROMSTRING          0x7FC00000 ; bitmank for boxed lua string literal (ROM)\n");
    fprintf (out(), "%%define  BOXED_TABLE              0xFF800000 ; bitmask for boxed lua table (RAM)\n");
    fprintf (out(), "%%define  BOXED_RAMSTRING          0xFFC00000 ; starting at offset 4\n");
    fprintf (out(), "%%define  BOXED_NIL                0xFFC00000\n");
    fprintf (out(), "%%define  BOXED_FALSE              0xFFC00001\n");
    fprintf (out(), "%%define  BOXED_BOOLEAN            0xFFC00001\n");
    fprintf (out(), "%%define  BOXED_TRUE               0xFFC00002\n");
    fprintf (out(), "%%define  BOXED_TOMBSTONE          0xFFC00003 ; future feature\n");
    fprintf (out(), "%%define  BOXED_PAYLOAD            0x003FFFFF\n");
    fprintf (out(), "%%define  TABLE_ARRAYSIZE          0x0000FFFF\n");
    fprintf (out(), "%%define  BOXED_CLOSURE_FLAG       0x00200000\n");
    fprintf (out(), "%%define  CLOSURE_ADDR_MASK        0x001FFFFF\n");
    fprintf (out(), "%%define  HEAP_POINTER             0x00000000\n");
    fprintf (out(), "%%define  FTOA_SCRATCH_PTR_A       0x00000001\n");
    fprintf (out(), "%%define  FTOA_SCRATCH_PTR_B       0x00000002\n");

    if (runtime_req.needs_tic80)
    {
        fprintf (out(), "%%define  TIC80_SPRITE_COUNT       0x00000200\n");
        fprintf (out(), "%%define  TIC80_FLAGS_PER_SPRITE   0x00000008\n");
        fprintf (out(), "%%define  TIC80_FLAG_BUFFER_WORDS  0x00000080\n");
        // synthesized sound (tic80_audio.c): rate, base SPU speed, and the
        // remaining duration (frames, -1 = none) of each sfx() channel 0-3
        fprintf (out(), "%%define  TIC80_AUDIO_RATE         %d\n", tic80_audio_rate ());
        fprintf (out(), "%%define  TIC80_AUDIO_SPEED        %.6f\n", tic80_audio_rate () / 44100.0);
        fprintf (out(), "%%define  TIC80_SFX_DURATION       0x%.8X\n", next_ram_address);
        next_ram_address = next_ram_address + 4;
        lines_printed += 3;
    }

    if (runtime_req.needs_pico8)
    {
        // Fixed RAM (not heap): must exist before any top-level cart code,
        // which runs inside __global_scope_initialization. See pico8.s.
        fprintf (out(), "%%define  PICO8_CAMERA_X           0x%.8X\n", next_ram_address);
        fprintf (out(), "%%define  PICO8_CAMERA_Y           0x%.8X\n", (next_ram_address + 1));
        fprintf (out(), "%%define  PICO8_PEN                0x%.8X\n", (next_ram_address + 2));
        fprintf (out(), "%%define  PICO8_TICK_FRAME         0x%.8X\n", (next_ram_address + 3));
        fprintf (out(), "%%define  PICO8_DRAW_FRAME         0x%.8X\n", (next_ram_address + 4));
        fprintf (out(), "%%define  PICO8_DRAW_CYCLE         0x%.8X\n", (next_ram_address + 5));
        fprintf (out(), "%%define  PICO8_DRAW_COST          0x%.8X\n", (next_ram_address + 6));
        fprintf (out(), "%%define  PICO8_MUSIC_PATTERN      0x%.8X\n", (next_ram_address + 7));
        fprintf (out(), "%%define  PICO8_MUSIC_END          0x%.8X\n", (next_ram_address + 8));
        fprintf (out(), "%%define  PICO8_SFX_NEXT           0x%.8X\n", (next_ram_address + 9));
        fprintf (out(), "%%define  PICO8_START_PREV         0x%.8X\n", (next_ram_address + 10));
        fprintf (out(), "%%define  PICO8_TICKS              0x%.8X\n", (next_ram_address + 11));
        fprintf (out(), "%%define  PICO8_RAM_PTR            0x%.8X\n", (next_ram_address + 12));
        fprintf (out(), "%%define  PICO8_CARTDATA           0x%.8X\n", (next_ram_address + 13));
        fprintf (out(), "%%define  PICO8_MENU_HOOK          0x%.8X\n", (next_ram_address + 14));
        // line(): end point of the last line (boxed numbers, as passed) and
        // the "line() was called: the next line(x, y) only sets it" flag
        fprintf (out(), "%%define  PICO8_LINE_X             0x%.8X\n", (next_ram_address + 15));
        fprintf (out(), "%%define  PICO8_LINE_Y             0x%.8X\n", (next_ram_address + 16));
        fprintf (out(), "%%define  PICO8_LINE_BREAK         0x%.8X\n", (next_ram_address + 17));
        // text cursor (cursor(), print() without coordinates): PICO-8 pixels, ints
        fprintf (out(), "%%define  PICO8_CURSOR_X           0x%.8X\n", (next_ram_address + 18));
        fprintf (out(), "%%define  PICO8_CURSOR_Y           0x%.8X\n", (next_ram_address + 19));
        // SFX sound ids start here (-1: the cart plays no synthesized sound)
        fprintf (out(), "%%define  PICO8_SFX_BASE           %d\n", pico8_sfx_base_id);
        fprintf (out(), "%%define  PICO8_AUDIO_RATE         %d\n", synth_audio_rate);
        fprintf (out(), "%%define  PICO8_AUDIO_SPEED        %.4f\n", synth_audio_rate / 44100.0);
        // camera x, y (floats), pen (int), tick frame, draw start frame /
        // cycle, last draw's cost in cycles, music sequencer state (current
        // pattern, frame it ends on), next auto sfx channel, Start held at
        // the last pause check, PICO-8 frames since start (time()), the
        // emulated 64 KB RAM (0 until first used), cartdata() state, the
        // pause menu (menuitem(): a boxed Lua function, 0 = none), line()'s
        // end point x, y and break flag, the text cursor x, y
        next_ram_address    = next_ram_address + 20;
        fprintf (out(), "%%define  PICO8_FLAGS_RAM          0x%.8X\n", next_ram_address);
        next_ram_address    = next_ram_address + 256;
        fprintf (out(), "%%define  PICO8_MAP_RAM            0x%.8X\n", next_ram_address);
        next_ram_address    = next_ram_address + (PICO8_MAP_WIDTH * PICO8_MAP_HEIGHT) / 4;
        fprintf (out(), "%%define  PICO8_FRAME_STEP         %d\n", pico8_frame_step);
        fprintf (out(), "%%define  PICO8_BEZEL              %d\n",
                 !pico8_bezel_enabled ? 0 : pico8_bezel_texture_id >= 0 ? 2 : 1);
        // custom art (pico8_bezel.c): its texture, panel size, scale to 144x360
        fprintf (out(), "%%define  PICO8_BEZEL_TEXTURE      %d\n", pico8_bezel_texture_id >= 0 ? pico8_bezel_texture_id : 0);
        fprintf (out(), "%%define  PICO8_BEZEL_PW           %d\n", pico8_bezel_panel_w);
        fprintf (out(), "%%define  PICO8_BEZEL_PH           %d\n", pico8_bezel_panel_h);
        fprintf (out(), "%%define  PICO8_BEZEL_SCALE        %.7f\n", 360.0 / pico8_bezel_panel_h);
        fprintf (out(), "%%define  PICO8_BEZEL_ALPHA        %d\n", pico8_bezel_has_alpha ? 1 : 0);
        lines_printed      += 6;
    }

    // Circle shape atlas (shapes.c): texture index, -1 when there is none
    if (runtime_req.needs_pico8 || runtime_req.needs_tic80)
    {
        fprintf (out(), "%%define  SHAPES_TEXTURE           %d\n", shapes_texture_id);
        fprintf (out(), "%%define  SHAPES_MAX_R             %d\n", SHAPES_MAX_R);
        fprintf (out(), "%%define  SHAPES_FAST              %d\n", shapes_fast ? 1 : 0);
    }

    // v32kbd keyboard state (v32kbd.c): fixed RAM, only when the program
    // uses the keyboard
    lines_printed += v32kbd_emit_defines (out());
    lines_printed += v32mouse_emit_defines (out());

    // Unconditional -- see the allocation comment in main.c.
    {
        fprintf (out(), "%%define  VIRCON32_BTN_PREV_STATE  0x%.8X\n", vircon32_btn_prev_state_base);
        fprintf (out(), "%%define  VIRCON32_SFX_CURSOR      0x%.8X\n", vircon32_sfx_cursor_base);
        fprintf (out(), "%%define  V32IO_GAMEPAD            0x%.8X\n", v32io_gamepad_base);
        fprintf (out(), "%%define  VIRCON32_MUSIC_CHANNEL_MASK 0x%.8X\n", vircon32_music_channel_mask_base);
        fprintf (out(), "%%define  VIRCON32_SFX_CHANNEL_MASK   0x%.8X\n", vircon32_sfx_channel_mask_base);
        fprintf (out(), "%%define  RET_COUNT                0x%.8X\n", ret_count_base);
        fprintf (out(), "%%define  MV_BUF                   0x%.8X\n", mv_buf_base);
        fprintf (out(), "%%define  MV_MAX                   %d\n", MV_MAX);
        fprintf (out(), "%%define  META_CALL_DEPTH          0x%.8X\n", meta_call_base);
        fprintf (out(), "%%define  META_CALL_STACK          0x%.8X\n", meta_call_base + 1);
        fprintf (out(), "%%define  META_CALL_STACK_SIZE     %d\n", META_CALL_STACK_SIZE);

        // Fixed hardware address range for the memory card -- word-addressed
        // like the rest of this VM's memory, entirely outside the compiler-
        // managed RAM pool (next_ram_address never touches it), same
        // category as V32_CART_PAGE. See memcard.load()/save()/title() and
        // the header comment on VIRCON32_MEMCARD_BASE in v32lua.h.
        fprintf (out(), "%%define  VIRCON32_MEMCARD_BASE       0x%.8X\n", VIRCON32_MEMCARD_BASE);
        fprintf (out(), "%%define  VIRCON32_MEMCARD_DATA_BASE  0x%.8X\n", VIRCON32_MEMCARD_DATA_BASE);
        fprintf (out(), "%%define  VIRCON32_MEMCARD_CURSOR_ADDR 0x%.8X\n", VIRCON32_MEMCARD_CURSOR_ADDR);
        fprintf (out(), "%%define  VIRCON32_MEMCARD_END        0x%.8X\n", VIRCON32_MEMCARD_END);
    }

    SymbolNode *curr = global_scope ? global_scope->symbols : NULL;
    while (curr != NULL) {
        // ONLY true globals get a RAM address here. A SYM_LOCAL that ended up
        // on this list carries a STACK OFFSET in ->location, not an address;
        // printing it as "%define var_X 0x<offset>" produced symbols pointing
        // at reserved low memory (0 = HEAP_POINTER, 1/2 = FTOA_SCRATCH_PTR_A/B).
        // register_local() no longer creates those at global scope, but if one
        // ever reappears we want a loud diagnostic and an undefined symbol at
        // assembly time -- not a silent write into the scratch pointers.
        if (curr->type != SYM_GLOBAL) {
            compiler_warning (ERR_INTERNAL, -1,
                "Non-global symbol '%s' (stack offset %d) leaked into the global "
                "symbol list; omitted from the RAM map", curr->name, curr->location);
            curr = curr->next;
            continue;
        }

        if (curr->is_function) {
            if (curr->location != -2) {  // Skip functions (they use labels, not RAM)
                fprintf(out(), "%%define  func_%-19s 0x%.8X\n", curr->name, curr->location);
            }
        } else {
            fprintf(out(), "%%define  var_%-20s 0x%.8X\n", curr->name, curr->location);
        }
        lines_printed    = lines_printed + 1;
        curr = curr->next;
    }

    // Heap base as a SYMBOL, not a baked-in literal. generate_global_setup()
    // used to emit "MOV R0, <next_ram_address>" at the top of the init
    // routine -- but codegen for the top-level statements that follows can
    // still register new globals, bumping next_ram_address past the value
    // already emitted and putting the heap on top of them. This map is
    // written after ALL codegen, so the number here is always the final one.
    {
        int heap_start = (next_ram_address >= 4) ? next_ram_address : 4;
        fprintf(out(), "%%define  HEAP_START               0x%.8X\n", heap_start);
        lines_printed    = lines_printed + 1;
    }

    fprintf(out(), "\n;; Highest used global RAM address: 0x%.8X\n", next_ram_address - 1);
    fprintf(out(), ";; Dynamic heap will start at runtime address: 0x%.8X\n\n", next_ram_address);
    lines_printed    = lines_printed + 2;
    return (lines_printed);
}

// ----------------------------------------------------------------------
// Re-escape a raw, already-decoded string literal for safe embedding in
// the assembler's `string "..."` directive. process_string_literal() (in
// the lexer) decodes Lua source escapes like \n, \t, \\ into their raw
// byte values at lex time -- which is correct, the runtime string must
// contain real control characters. But that means by the time we get
// here, current->value may contain a literal 0x0A/0x09/0x0D/'\\'/'"'
// byte. Writing those bytes straight into the .s TEXT FILE via "%s" is
// what caused the corruption: a raw newline byte splits the `string`
// directive across two physical assembly lines, and a raw '"' would
// prematurely close the assembler's string literal. This re-encodes
// those bytes back into backslash escapes so the assembly source stays
// on one line and round-trips correctly.
static void emit_escaped_asm_string (FILE *f, const char *raw)
{
    for (const unsigned char *p = (const unsigned char *) raw; *p; p++) {
        switch (*p) {
            case '\n': fputs ("\\n",  f); break;
            case '\t': fputs ("\\t",  f); break;
            case '\r': fputs ("\\r",  f); break;
            case '\\': fputs ("\\\\", f); break;
            case '"':  fputs ("\\\"", f); break;
            default:   fputc (*p, f);     break;
        }
    }
}

void  emit_string_data_section (void)
{
    emit_asm ("\n;; =========================================================");
    emit_asm (";; Read-Only String Data Section");
    emit_asm (";; =========================================================");

    // Cart title -- emitted first within this section (dedicated,
    // well-known label, not part of the auto-numbered __string_N table
    // below it, so external tooling can find it by name regardless of
    // how many other string literals the program contains) -- but
    // grouped here with the rest of the read-only string constants
    // rather than living at a separate location in the file.
    emit_cart_title_label (g_lua_filename);

    // Every literal is preceded by its FNV-1a content hash, and the whole
    // pool is bracketed by __string_pool_start/_end: table lookups with a
    // literal key read the hash instead of hashing the characters (see
    // __table_hash in table.s). The runtime computes the identical hash
    // for strings built at run time.
    fprintf (out(), "\n__string_pool_start:\n");
    if (strings_head               != NULL)
    {
        fprintf (out(), "\n; --- String Literal Allocations ---\n");
        StringLiteralNode *current  = strings_head;
        while (current             != NULL)
        {
            uint32_t h = 0x811C9DC5u;
            for (const unsigned char *c = (const unsigned char *) current -> value; *c; c++) {
                h ^= (uint32_t)(*c & 0xFF);
                h *= 16777619u;
            }
            fprintf (out(), "    integer 0x%08X\n", h);
            fprintf (out(), "__string_%d:\n", current -> id);
            fprintf (out(), "    string \"");
            emit_escaped_asm_string (out(), current -> value);
            fprintf (out(), "\"\n\n");
            current                 = current -> next;
        }
    }
    fprintf (out(), "__string_pool_end:\n    integer 0\n");
}

////////////////////////////////////////////////////////////////////////////////////////
//
// Helper: emit contents of a binary blob through emit_asm() for consistent formatting
//
static void emit_embedded_asm (const char *start)
{
    const char *cursor = start;
    char line[EMIT_BUFFER_SIZE];

    while (*cursor != '\0') {
        int i = 0;
        while (*cursor != '\0' && *cursor != '\n' && i < (int)sizeof(line) - 2) {
            line[i++] = *cursor++;
        }
        if (*cursor == '\n') {
            line[i++] = *cursor++;
        }
        line[i] = '\0';
        emit_asm ("%s", line);  // Preserves formatting, comments
    }
}

void  emit_runtime_library (void)
{
    emit_asm ("\n;; ===========================================================================");
    emit_asm (";; v32lua Runtime Library Routines\n");
    emit_asm (";; ===========================================================================\n");

    ////////////////////////////////////////////////////////////////////////////////////
    //
    // Always needed - core routines
    //
    emit_embedded_asm (runtime_memory_start);
    emit_embedded_asm (runtime_datetime_start);
    emit_embedded_asm (runtime_exec_start);

    ////////////////////////////////////////////////////////////////////////////////////
    //
    // Conditional modules
    //
    if (runtime_req.needs_tables)
        emit_embedded_asm (runtime_table_start);
    if (runtime_req.needs_math)
        emit_embedded_asm (runtime_math_start);
    if (runtime_req.needs_strings)
        emit_embedded_asm (runtime_string_start);
    if (runtime_req.needs_print)
        emit_embedded_asm (runtime_print_start);
    if (runtime_req.needs_iters)
        emit_embedded_asm (runtime_iters_start);

    ////////////////////////////////////////////////////////////////////////////////////
    //
    // API bundles (all-or-nothing)
    //
    if (runtime_req.needs_pico8)
    {
        emit_embedded_asm (runtime_pico8_start);
        emit_pico8_cart_data (out());
        emit_shapes_runtime (out());
    }
    if (g_uses_env)
    {
        emit_env_table (out());
    }
    if (runtime_req.needs_tic80)
    {
        emit_embedded_asm (runtime_tic80_start);

        // OVERWRITE default palette with custom if present
        emit_asm ("\n;; =========================================================");
        emit_asm (";; TIC-80 Custom Palette (from cartridge, overrides defaults)");
        emit_asm (";; =========================================================\n");
        emit_asm ("__tic80_palette:\n");

        // Emit all 16 colors on one line (matches default format)
        fprintf (out(), "    integer ");
        for (int  index = 0; index < 16; index++)
        {
            fprintf (out(), "0x%.8X", tic80_get_palette_color (index));
            if (index <  15)
            {
                fprintf (out(), ", ");
            }
        }
        fprintf (out(), "\n");

        // Sprite flags from the cart's -- <FLAGS> section (zeros if none),
        // packed 4 sprites per word (sprite n at bits 8*(n%4)) -- the layout
        // __builtin_tic80_fget/fset use. Copied to RAM by init_flags.
        fprintf (out(), "\n__tic80_flags_rom:\n");
        for (int w = 0; w < 128; w++) {
            uint32_t word = (uint32_t) tic80_sprite_flags[w * 4]
                          | ((uint32_t) tic80_sprite_flags[w * 4 + 1] << 8)
                          | ((uint32_t) tic80_sprite_flags[w * 4 + 2] << 16)
                          | ((uint32_t) tic80_sprite_flags[w * 4 + 3] << 24);
            fprintf (out(), "%s0x%08X%s", (w % 8 == 0) ? "    integer " : "",
                     word, (w % 8 == 7) ? "\n" : ", ");
        }

        // Is tile 0 fully transparent in colorkey texture k (0-15; 16 is
        // opaque)? map() skips drawing such cells -- usually most of a map.
        fprintf (out(), "\n__tic80_tile0_empty:\n    integer ");
        for (int k = 0; k <= 16; k++) {
            int empty = (k < 16);
            for (int y = 0; y < 8 && empty; y++)
                for (int x = 0; x < 8 && empty; x++)
                    if ((get_tic80_tile_pixel (x, y) & 15) != k) empty = 0;
            fprintf (out(), "%d%s", empty, k < 16 ? ", " : "\n");
        }
        emit_tic80_ram_rom (out());
        emit_shapes_runtime (out());

        emit_tic80_map_data (out());
        emit_tic80_audio_tables (out());
    }

    if (runtime_req.needs_vircon32)
    {
        emit_embedded_asm (runtime_vircon32_start);
    }

    // v32io: gamepad selection (always -- every API's btn() selects
    // through it) and the group read the v32kbd decoder uses
    emit_embedded_asm (runtime_v32io_start);
    if (v32kbd_wanted)
    {
        emit_embedded_asm (runtime_v32kbd_start);
    }
    if (v32mouse_wanted)
    {
        emit_embedded_asm (runtime_v32mouse_start);
    }

    emit_tilemap_rom_data (out());

    ////////////////////////////////////////////////////////////////////////////////////
    //
    // Always needed - epilogue
    //
    emit_embedded_asm (runtime_constant_start);
    emit_asm (";; ===========================================================================\n");
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
    emit_asm("OR   R%d, BOXED_ROMSTRING ; Box key as ROM String", scratch);
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
    emit_asm("OR   R%d, BOXED_ROMSTRING ; Box key as ROM String", scratch);
    emit_asm("PUSH R%d             ; Arg 2: Property Key", scratch);
    unlock_register(scratch);

    // 4. Call Routine and Clean Stack
    emit_asm("CALL __builtin_table_get");
    emit_asm("IADD SP, 2           ; Clean up stack arguments");

    // 5. Capture Return Value
    emit_asm("MOV  R%d, R0         ; Store returned value", table_reg);
}

// ============================================================================
// Map Data Emission
// ============================================================================

/// Emit the parsed TIC-80 map as ROM data using 'integer' directive
/// Call this from emit.c after processing TIC-80 sections
void emit_tic80_map_data(FILE *out) {
    if (!tic80_has_map) {
        tic80_map_width   = 0;
        tic80_map_height  = 0;
    }

    int total_bytes = tic80_map_width * tic80_map_height;

    fprintf(out, "\n;; =========================================================\n");
    fprintf(out, ";; TIC-80 Map Data (from cartridge)\n");
    fprintf(out, ";; =========================================================\n");

    // Emit dimensions as integers
    fprintf(out, "__tic80_map_static_width:\n    integer %d\n\n", tic80_map_width);
    fprintf(out, "__tic80_map_static_height:\n    integer %d\n\n", tic80_map_height);

    // Emit map data as comma-separated integers (one per byte)
    fprintf(out, "__tic80_map_static_data:\n    integer ");
    for (int i = 0; i < total_bytes; i++) {
        fprintf(out, "%d", tic80_map_data[i]);
        if (i < total_bytes - 1) {
            fprintf(out, ", ");
        }
        // Line break every 16 values for readability
        if ((i + 1) % 16 == 0 && i < total_bytes - 1) {
            fprintf(out, "\n    integer ");
        }
    }
    if (!tic80_has_map) {
        fprintf (out, "0");
    }
    fprintf(out, "\n\n");
}

// ============================================================================
// emit_load_variable: load the VALUE of a Lua variable into dest_reg.
// Fast path (globals, uncaptured locals/params): identical to before, one
// MOV. Slow path (a boxed local, or any upvalue -- upvalues are ALWAYS
// boxed): the slot holds a pointer, so load the pointer then dereference it.
// ============================================================================
void emit_load_variable (const char *name, int dest_reg)
{
    SymbolNode *sym = resolve_symbol(name);
    if (sym == NULL) sym = register_global(name);

    char access_str[256];
    get_variable_access_string(name, access_str);

    if (!sym->is_boxed) {
        emit_asm("MOV R%d, %s ; load '%s'", dest_reg, access_str, name);
        return;
    }

    emit_asm("    ; --- '%s' is captured -- boxed access ---", name);
    emit_asm("MOV R%d, %s ; load box pointer", dest_reg, access_str);
    emit_asm("MOV R%d, [R%d] ; dereference box", dest_reg, dest_reg);
}

// ============================================================================
// emit_store_variable: store src_reg's value into a Lua variable's slot.
// Mirrors emit_load_variable()'s indirection on the write side.
// ============================================================================
void emit_store_variable (const char *name, int src_reg)
{
    SymbolNode *sym = resolve_symbol(name);
    if (sym == NULL) sym = register_global(name);

    char access_str[256];
    get_variable_access_string(name, access_str);

    if (!sym->is_boxed) {
        emit_asm("MOV %s, R%d ; store '%s'", access_str, src_reg, name);
        return;
    }

    int ptr_reg = allocate_pinned_register();
    emit_asm("    ; --- '%s' is captured -- boxed access ---", name);
    emit_asm("MOV R%d, %s ; load box pointer", ptr_reg, access_str);
    emit_asm("MOV [R%d], R%d ; write through box", ptr_reg, src_reg);
    unlock_pinned_register(ptr_reg);
}

// ============================================================================
// emit_initialize_local: store a local's INITIAL value at its declaration
// site. If the analysis pass marked it boxed, allocate the box first and
// leave the pointer in the slot instead of the raw value.
// ============================================================================
void  emit_initialize_local (SymbolNode *sym, int  value_reg)
{
    char  access_str[256];
    get_variable_access_string (sym -> name, access_str);

    if (!sym -> is_boxed)
    {
        emit_asm ("MOV %s, R%d ; init local '%s'", access_str,
                                                   value_reg,
                                                   sym -> name);
        return;
    }

    emit_asm ("    ; --- '%s' is captured by a nested closure: box it ---", sym -> name);

    //////////////////////////////////////////////////////////////////////////
    //
    // __malloc clobbers R0-R3 and R6 internally (see runtime.s). We cannot
    // rely on spill_register()/ensure_in_register() to protect value_reg
    // across that call: spill_register() explicitly refuses to touch a
    // PINNED register (that's what pinning means), and value_reg IS pinned
    // on some call paths -- e.g. node_multiple_assignment's standard
    // assignment branch always passes a pinned val_reg here. When that
    // happens spill_register() silently becomes a no-op and, if value_reg
    // lands on R1/R2/R3/R6, __malloc clobbers it before we read it back --
    // the box ends up initialized with __malloc's internal state instead
    // of the value we meant to store, intermittently, depending on which
    // register the allocator happened to hand out.
    //
    // A raw PUSH/POP sidesteps register_pinned[] entirely -- it's the same
    // idiom __builtin_table_new already uses in runtime.s to protect its
    // own registers across this same call, and it's correct regardless of
    // whether value_reg is pinned, spilled, or anything else.
    //
    emit_asm ("PUSH R%d ; preserve value across __malloc", value_reg);

    emit_asm ("MOV R0, 1");
    emit_asm ("PUSH R0 ; box size = 1 word");
    emit_asm ("CALL __malloc");
    emit_asm ("IADD SP, 1 ; clean up malloc argument");

    emit_asm ("POP R%d ; restore value saved before __malloc", value_reg);
    emit_asm ("MOV [R0], R%d ; store initial value into the box", value_reg);
    emit_asm ("MOV %s, R0 ; slot now holds the box pointer",      access_str);
}

// ============================================================================
// emit_load_function_value: load a boxed function VALUE into dest_reg.
//
// No-upvalue case (the overwhelming majority of functions): identical to
// before -- a bare boxed code address, no heap allocation.
//
// Closure case: allocate [code_addr, count, up_0, up_1, ...] on the heap and
// box its address instead, with BOXED_CLOSURE_FLAG set so __builtin_exec
// knows to route through it.
// ============================================================================
void emit_load_function_value (ASTNode *func_def_node, const char *mangled_name, int dest_reg)
{
    int upvalue_count = (func_def_node != NULL)
        ? name_list_length(func_def_node->as.function_def.upvalues)
        : 0;

    if (upvalue_count == 0) {
        emit_asm("    ;; Load and box address of the mangled function");
        emit_asm("MOV R%d, __function_%s", dest_reg, mangled_name);
        emit_asm("OR R%d, BOXED_FUNCTION ; Box as Function", dest_reg);
        return;
    }

    emit_asm("    ;; Build closure record for '%s' (%d upvalue%s)",
             mangled_name, upvalue_count, upvalue_count == 1 ? "" : "s");

    // -------------------------------------------------------------------
    // FIX: this function ALWAYS uses raw R0 as scratch for the malloc
    // size argument, malloc's own return value, and the code-address
    // load below -- by hardcoded register number, not through the
    // compiler's own register allocator. allocate_register() never
    // hands out R0 (its scan starts at index 1), so dest_reg here is
    // never literally R0 -- but that offers no protection when the
    // CALLER already has something meaningful sitting in the PHYSICAL
    // R0 register that this function doesn't own.
    //
    // node_return()'s multi-return protocol is exactly such a caller:
    // for `return a, b` where both a and b are closures, the first
    // return value is deliberately placed in R0 before the SECOND
    // return expression is ever evaluated. Building the second
    // closure's record here then unconditionally overwrote that R0
    // with its own malloc scratch, destroying the first closure before
    // the function ever returned -- e.g. `return increment, get` always
    // clobbered `increment`'s already-built closure pointer while
    // constructing `get`'s.
    //
    // Saving/restoring R0 around just the portion that actually uses it
    // as scratch is universally safe regardless of caller context: if
    // R0 didn't hold anything meaningful, this is a harmless no-op;
    // if it did, the caller's value survives unchanged. Same
    // save-across-an-internal-CALL idiom already used elsewhere in this
    // runtime (see __builtin_table_new's callee-save comment for R1
    // across its own internal CALL __malloc).
    // -------------------------------------------------------------------
    emit_asm("PUSH R0 ; preserve caller's R0 across this closure's own malloc scratch");

    // One spare word: the record starts at an even address, so the box
    // can hold address / 2 -- the payload has 21 bits next to the closure
    // flag, and a record above 2M words (a cart that has used half of RAM,
    // nanoman after its level decoding) used to lose its top bit.
    emit_asm("MOV R0, %d", 3 + upvalue_count);
    emit_asm("PUSH R0");
    emit_asm("CALL __malloc");
    emit_asm("IADD SP, 1 ; clean up malloc argument");

    int rec_reg = allocate_pinned_register();
    emit_asm("MOV R%d, R0 ; closure record base", rec_reg);
    emit_asm("IADD R%d, 1", rec_reg);
    emit_asm("AND R%d, 0xFFFFFFFE ; even address", rec_reg);

    emit_asm("MOV R0, __function_%s", mangled_name);
    emit_asm("MOV [R%d], R0 ; word 0: code address", rec_reg);
    emit_asm("MOV R0, %d", upvalue_count);
    emit_asm("MOV [R%d+1], R0 ; word 1: upvalue count", rec_reg);

    // Done needing raw R0 as scratch -- restore the caller's value now,
    // before anything else (the upvalue-copy loop below only ever uses
    // allocate_pinned_register()-issued temporaries, never R0).
    emit_asm("POP R0 ; restore caller's R0");

    int index = 0;
    for (NameList *up = func_def_node->as.function_def.upvalues; up != NULL; up = up->next) {
        int tmp_reg = allocate_pinned_register();
        char access_str[256];
        get_variable_access_string(up->name, access_str);
        emit_asm("MOV R%d, %s ; box pointer for captured '%s'", tmp_reg, access_str, up->name);
        emit_asm("MOV [R%d+%d], R%d", rec_reg, 2 + index, tmp_reg);
        unlock_pinned_register(tmp_reg);
        index++;
    }

    emit_asm("MOV R%d, R%d ; box the closure record", dest_reg, rec_reg);
    emit_asm("SHL R%d, -1 ; address / 2 (see above)", dest_reg);
    emit_asm("OR R%d, BOXED_FUNCTION", dest_reg);
    emit_asm("OR R%d, BOXED_CLOSURE_FLAG ; mark payload as a closure record, not raw code", dest_reg);
    unlock_pinned_register(rec_reg);
}

// Emits a fixed, well-known __cart_title label as the VERY FIRST thing
// in the assembled output -- before the entry vector, before the global
// variable RAM map, before anything else -- so external tooling (e.g.
// memory card formatting) can find it at a predictable, stable location
// regardless of program size. Deliberately a dedicated label rather than
// just another entry in the normal ROM string table (__string_N), since
// those are auto-numbered and their position shifts depending on how
// many other string literals the program happens to contain.
//
// Title source: --#title "..." if the program gave one, otherwise the
// input filename with its directory path and ".lua" extension stripped.
// Hard-truncated to 20 characters either way -- this is a fixed field
// width for Vircon32 memory card formatting, not a stylistic choice, so
// no attempt is made to truncate at a word boundary.
void emit_cart_title_label(const char *input_filename)
{
    const char *title_source;

    if (cart_title_was_set) {
        title_source = cart_title;
    } else {
        title_source = derive_cart_title_from_filename(input_filename);
    }

    char truncated[21];
    snprintf(truncated, sizeof(truncated), "%.20s", title_source);

    fprintf(out(), ";; --- Cart Title (Vircon32 memory card formatting, max 20 chars) ---\n");
    fprintf(out(), "__cart_title:\n");
    fprintf(out(), "    string \"");
    emit_escaped_asm_string(out(), truncated);
    fprintf(out(), "\"\n\n");
}

// ----------------------------------------------------------------------
// _ENV support: a (name, address) table of every global, plus the two
// lookup routines node_table_get()/node_table_set() call for _ENV[k].
// ----------------------------------------------------------------------
void emit_env_table (FILE *f)
{
    int count = 0;
    for (SymbolNode *c = global_scope ? global_scope->symbols : NULL; c; c = c->next)
        if (c->type == SYM_GLOBAL && c->location > 0) count++;

    fprintf (f, "\n;; --- _ENV: global name table (%d globals) ---\n", count);
    fprintf (f, "__env_table:\n    integer %d\n", count);
    int i = 0;
    for (SymbolNode *c = global_scope ? global_scope->symbols : NULL; c; c = c->next) {
        if (c->type != SYM_GLOBAL || c->location <= 0) continue;
        fprintf (f, "    pointer __env_name_%d\n    integer 0x%08X\n", i++, c->location);
    }
    i = 0;
    for (SymbolNode *c = global_scope ? global_scope->symbols : NULL; c; c = c->next) {
        if (c->type != SYM_GLOBAL || c->location <= 0) continue;
        // PICO-8 builtin wrappers (pico8_prelude.c) answer to the builtin's
        // own name -- unless the program has a global of that name itself
        const char *name = c->name;
        if (strncmp (name, "__p8env_", 8) == 0) {
            bool shadowed = false;
            for (SymbolNode *d = global_scope->symbols; d; d = d->next)
                if (d->type == SYM_GLOBAL && d->location > 0 && strcmp (d->name, name + 8) == 0)
                    shadowed = true;
            if (!shadowed) name += 8;
        }
        fprintf (f, "__env_name_%d:\n    string \"%s\"\n", i++, name);
    }
    fputs (
";; __env_find: R1 = boxed key -> R2 = global's RAM address, or -1\n"
"__env_find:\n"
"    PUSH  R3\n"
"    PUSH  R4\n"
"    PUSH  R5\n"
"    MOV   R3, __env_table\n"
"    MOV   R4, [R3]\n"
"    IADD  R3, 1\n"
"__env_find_loop:\n"
"    MOV   R5, R4\n"
"    ILE   R5, 0\n"
"    JT    R5, __env_find_none\n"
"    MOV   R5, [R3]\n"
"    OR    R5, BOXED_ROMSTRING\n"
"    PUSH  R3\n"
"    PUSH  R4\n"
"    PUSH  R1\n"
"    PUSH  R1\n"
"    PUSH  R5\n"
"    CALL  __builtin_eq\n"
"    IADD  SP, 2\n"
"    POP   R1\n"
"    POP   R4\n"
"    POP   R3\n"
"    IEQ   R0, BOXED_TRUE\n"
"    JT    R0, __env_find_hit\n"
"    IADD  R3, 2\n"
"    ISUB  R4, 1\n"
"    JMP   __env_find_loop\n"
"__env_find_hit:\n"
"    MOV   R2, [R3+1]\n"
"    JMP   __env_find_done\n"
"__env_find_none:\n"
"    MOV   R2, -1\n"
"__env_find_done:\n"
"    POP   R5\n"
"    POP   R4\n"
"    POP   R3\n"
"    RET\n"
";; __builtin_env_get(key) -> R0 = value of the global named key, or nil\n"
"__builtin_env_get:\n"
"    PUSH  BP\n"
"    MOV   BP, SP\n"
"    PUSH  R1\n"
"    PUSH  R2\n"
"    MOV   R1, [BP+2]\n"
"    CALL  __env_find\n"
"    MOV   R0, BOXED_NIL\n"
"    MOV   R1, R2\n"
"    ILT   R1, 0\n"
"    JT    R1, __env_get_done\n"
"    MOV   R0, [R2]\n"
"__env_get_done:\n"
"    POP   R2\n"
"    POP   R1\n"
"    MOV   SP, BP\n"
"    POP   BP\n"
"    RET\n"
";; __builtin_env_set(key, value): assigns an existing global by name\n"
";; (a name the program never uses as a global has no slot: ignored)\n"
"__builtin_env_set:\n"
"    PUSH  BP\n"
"    MOV   BP, SP\n"
"    PUSH  R1\n"
"    PUSH  R2\n"
"    MOV   R1, [BP+2]\n"
"    CALL  __env_find\n"
"    MOV   R1, R2\n"
"    ILT   R1, 0\n"
"    JT    R1, __env_set_done\n"
"    MOV   R1, [BP+3]\n"
"    MOV   [R2], R1\n"
"__env_set_done:\n"
"    MOV   R0, BOXED_NIL\n"
"    POP   R2\n"
"    POP   R1\n"
"    MOV   SP, BP\n"
"    POP   BP\n"
"    RET\n", f);
}


// __globals_to_nil: stores nil into every global variable's RAM word
// (called from __global_scope_initialization before any top-level code).
// Emitted after all code generation, so it covers every global.
void  emit_globals_to_nil (void)
{
    fprintf (out(), "\n;; --- every global starts as nil ---\n");
    fprintf (out(), "__globals_to_nil:\n");
    fprintf (out(), "    MOV  R0, BOXED_NIL\n");
    SymbolNode *curr = global_scope ? global_scope->symbols : NULL;
    for (; curr != NULL; curr = curr->next)
    {
        if (curr->type != SYM_GLOBAL || curr->is_function) continue;
        fprintf (out(), "    MOV  [var_%s], R0\n", curr->name);
    }
    fprintf (out(), "    RET\n");
}
