#ifndef __V32LUA_PATHUTIL_H
#define __V32LUA_PATHUTIL_H

// Small file-name helpers used to work out the paths written into the
// cartridge XML (see emit_cart_xml in emit.c). '/' and '\' both separate
// path components.

// Malloc'd copy of `path` with its extension (everything after the last '.',
// provided that dot comes after the last separator) replaced by `new_ext`,
// or `new_ext` appended when there is none. `new_ext` includes its leading
// dot (".xml", ".vbin", ...). "obj/game.asm" + ".xml" -> "obj/game.xml".
// Caller frees.
char       *replace_extension (const char *path, const char *new_ext);

// Pointer to the final component of `path` (not a copy).
const char *path_basename     (const char *path);

// Malloc'd directory part of `path`, without a trailing separator; "." when
// there is none. Caller frees.
char       *path_dirname      (const char *path);

// Malloc'd path of `target` relative to the directory `from_dir` (both are
// resolved against the current directory first, "." and ".." are folded
// lexically; symlinks are not consulted), written with '/' separators.
// "obj" + "obj/game.vbin" -> "game.vbin"; "src" + "obj/game.vbin" ->
// "../obj/game.vbin". Caller frees.
char       *path_relative_to  (const char *from_dir, const char *target);

// Malloc'd absolute, normalized form of `path` (resolved against the current
// directory, "." and ".." folded, '/' separators). Caller frees.
char       *path_absolute     (const char *path);

#endif
