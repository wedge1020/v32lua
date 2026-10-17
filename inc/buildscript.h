#ifndef __V32LUA_BUILDSCRIPT_H
#define __V32LUA_BUILDSCRIPT_H

// One command-line option to repeat in the generated build scripts' v32lua
// command (the options that change what is produced; not -o, -v or -d).
typedef struct
{
    const char *flag;       // "--rate", "--no-bezel", "-w", ...
    const char *value;      // its argument, or NULL
    int         is_path;    // the argument is a file path (rewritten relative to the script)
} BuildOpt;

// Writes Make.sh and Make.bat, the traditional Vircon32 build scripts, from
// what emit_cart_xml just wrote the XML from. Call it after emit_cart_xml.
// Where they go: beside the source file, or -- when the source is in a
// folder named "src" and the output file is in a sibling of it (src/ and
// obj/ side by side) -- in their parent, the project folder. An existing
// script that v32lua did not write is left alone.
void emit_build_scripts (const char *output_filename, const char *source_filename,
                         int preserve_paths, int debug_map,
                         const BuildOpt *opts, int nopts, int verbose);

#endif
