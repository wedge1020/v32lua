#ifndef __INTERNALS_H
#define __INTERNALS_H

// In compiler headers (e.g., compiler.h)
typedef struct {
    const char *name;
    int return_count;  // Number of return values
} BuiltinFunctionInfo;

// In compiler source (e.g., builtins.c)
static const BuiltinFunctionInfo builtin_return_counts[] = {
    {"math.modf",  2},
    {"math.frexp", 2},
    {"math.ldexp", 1},
    // Add other multi-return functions here
    {NULL, 1}  // Default: single return value
};

extern int  w_mainwait;

void  compiler_error   (ErrorType, int, const char *, ...);
void  compiler_warning (ErrorType, int, const char *, ...);
int   get_builtin_return_count (const char *);

#endif
