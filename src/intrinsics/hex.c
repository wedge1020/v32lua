#include "v32lua.h"

/**
 * Emits assembly for the hex() intrinsic.
 *
 * Converts a hexadecimal string literal to a 32-bit integer value.
 * Syntax: hex("0x...")
 *
 * @param node   The AST node representing the function call.
 * @param dest_reg The destination register for the result (0 = discard).
 * @return        true if successfully emitted, false on error.
 */
bool emit_hex_intrinsic(ASTNode *node, int dest_reg)
{
    ASTNode *arg = node->as.call.args_head;

    // --- Validate: exactly one string literal argument ---
    if (!arg || arg->type != NODE_STRING || arg->next != NULL) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "hex() intrinsic expects exactly one string literal argument (e.g., hex(\"0xFF800000\"))");
        return false;
    }

    // --- Parse hexadecimal string ---
    const char *hex_str = arg->as.string_val.value;
    char *end_ptr = NULL;
    unsigned long raw_val = strtoul(hex_str, &end_ptr, 16);

    if (*end_ptr != '\0' || end_ptr == hex_str) {
        compiler_error(ERR_SYNTAX, node->line_number,
            "Invalid hexadecimal literal passed to hex(): '%s'", hex_str);
        return false;
    }

    // --- Emit direct 32-bit word load ---
    if (dest_reg != 0) {
        emit_asm("    ;; Intrinsic: hex(\"%s\") -> direct 32-bit word load\n", hex_str);
        emit_asm("MOV R%d, 0x%08lX\n", dest_reg, raw_val);
    }

    return true;
}
