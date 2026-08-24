#include "v32lua.h"

int  w_mainwait  = -1;

void compiler_error (ErrorType type, int line_num, const char* format, ...)
{
    // 1. Print the Error Type Prefix
    fprintf (stderr, "\n");
    switch (type)
    {
        case ERR_LEXICAL:
            fprintf (stderr, "[Lexical Error]");
            break;

        case ERR_SYNTAX:
            fprintf (stderr, "[Syntax Error]");
            break;

        case ERR_SEMANTIC:
            fprintf (stderr, "[Semantic Error]");
            break;

        case ERR_INTERNAL:
            fprintf (stderr, "[Internal Compiler Error]");
            break;

        default:
            fprintf (stderr, "[Unknown Error]");
            break;
    }
    
    if (line_num >  0)
    {
        fprintf (stderr, " on line %d: ", line_num);
    }
    else
    {
        fprintf (stderr, ": ");
    }

    // 2. Format and print the custom message
    va_list args;
    va_start (args, format);
    vfprintf (stderr, format, args);
    va_end (args);
    fprintf (stderr, "\n");

    // 3. Highlight the line of code (if we have a valid line number and file)
    if (line_num > 0 && yyin != NULL)
    {
        rewind (yyin);
        char  line_buffer[1024];
        int   current_line    = 1;
        while (fgets(line_buffer, sizeof(line_buffer), yyin))
        {
            if (current_line == line_num)
            {
                fprintf (stderr, "      |\n");
                fprintf (stderr, " %4d | %s", line_num, line_buffer);
                if (strchr(line_buffer, '\n') == NULL)
                {
                    fprintf (stderr, "\n");
                }
                fprintf (stderr, "      |\n\n");
                break;
            }
            current_line++;
        }
    }

    // 4. Halt compilation
    exit (1);
}

void compiler_warning (ErrorType type, int line_num, const char* format, ...)
{
    // 1. Print the Error Type Prefix
    fprintf (stderr, "\n");
    switch (type)
    {
        case ERR_LEXICAL:
            fprintf (stderr, "[Lexical Warning]");
            break;

        case ERR_SYNTAX:
            fprintf (stderr, "[Syntax Warning]");
            break;

        case ERR_SEMANTIC:
            fprintf (stderr, "[Semantic Warning]");
            break;

        case ERR_INTERNAL:
            fprintf (stderr, "[Internal Compiler Warning]");
            break;

        default:
            fprintf (stderr, "[Unknown Warning]");
            break;
    }
    
    if (line_num >  0)
    {
        fprintf (stderr, " on line %d: ", line_num);
    }
    else
    {
        fprintf (stderr, ": ");
    }

    // 2. Format and print the custom message
    va_list args;
    va_start (args, format);
    vfprintf (stderr, format, args);
    va_end (args);
    fprintf (stderr, "\n");

    // 3. Highlight the line of code (if we have a valid line number and file)
    if (line_num > 0 && yyin != NULL)
    {
        rewind (yyin);
        char  line_buffer[1024];
        int   current_line    = 1;
        while (fgets(line_buffer, sizeof(line_buffer), yyin))
        {
            if (current_line == line_num)
            {
                fprintf (stderr, "      |\n");
                fprintf (stderr, " %4d | %s", line_num, line_buffer);
                if (strchr(line_buffer, '\n') == NULL)
                {
                    fprintf (stderr, "\n");
                }
                fprintf (stderr, "      |\n\n");
                break;
            }
            current_line++;
        }
    }
}

// Helper function to look up return count
int get_builtin_return_count(const char *func_name) {
    for (int i = 0; builtin_return_counts[i].name != NULL; i++) {
        if (strcmp(func_name, builtin_return_counts[i].name) == 0) {
            return builtin_return_counts[i].return_count;
        }
    }
    return 1;  // Default to single return value
}

// Derives a fallback cart title from the input filename: strips any
// directory path (handles both '/' and '\' separators defensively,
// since command-line invocation could come from either) and strips a
// trailing ".lua" extension if present. Returns a pointer into a static
// buffer -- caller should copy out before calling this again.
char *derive_cart_title_from_filename(const char *path)
{
    const char *base = strrchr(path, '/');
    const char *base_bs = strrchr(path, '\\');
    if (base_bs != NULL && (base == NULL || base_bs > base)) {
        base = base_bs;
    }
    base = (base != NULL) ? base + 1 : path;

    static char title_buf[256];
    strncpy(title_buf, base, sizeof(title_buf) - 1);
    title_buf[sizeof(title_buf) - 1] = '\0';

    char *dot = strrchr(title_buf, '.');
    if (dot != NULL && strcmp(dot, ".lua") == 0) {
        *dot = '\0';
    }
    return title_buf;
}
