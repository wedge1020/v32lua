#include "v32lua.h"

void  load_ffi_library (const char *filename)
{
    FILE *ffi                     = fopen (filename, "r");
    if (ffi                      == NULL)
	{
        compiler_error (ERR_INTERNAL, -1, "Could not open library file '%s'", filename);
    }
	else
	{
		char line[256];
		while (fgets(line, sizeof(line), ffi)) {
			// Look for the special ";;FFI" token
			char *tag = strstr(line, ";;FFI");
			if (tag) {
				char func_name[128] = {0};
				int arity = 0;

				// Parse formatted: ";;FFI func_name, arity"
				if (sscanf (tag, ";;FFI %127[^,], %d", func_name, &arity) == 2) {
					// Trim trailing spaces from func_name
					trim_spaces (func_name);

					// Register in v32lua's global symbol table!
					SymbolNode *sym     = register_global (func_name);
					sym -> is_function  = 1;
					sym -> arity        = arity;
					sym -> is_c_native  = 1; // Flag for C ABI calling convention
				}
			}
		}
		fclose (ffi);
	}
}
