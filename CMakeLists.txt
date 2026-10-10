# ----------------------------------------------------------------------------
#   CMake build for v32lua, the Lua compiler for the Vircon32 console
#
#   Laid  out  after  the  Vircon32  DevTools' own CMake setup and those
#   of v32opt and v32c++. This is an ALTERNATIVE to the base Makefile,
#   which  keeps  working exactly as before (`make`, `make tests`, `make
#   sysinstall`, ...); the two never share build products. Build out of
#   tree:
#
#       cmake -S . -B build      (MSYS2/MinGW: add -G "MSYS Makefiles")
#       cmake --build build
#       ctest --test-dir build   (compiles every test program)
#       cmake --install build    (may need sudo / an elevated shell)
#       cmake --build build --target uninstall
#       cpack --config build/CPackConfig.cmake
#                                (.tar.gz / .deb / .rpm, or .zip on Windows)
#
#   Default install locations (the community tools live in v32tools/,
#   next to the DevTools, shared with v32opt and v32c++):
#
#       Linux / macOS: /usr/local/bin/v32lua
#                      /usr/local/share/man/man1/v32lua.1
#                      /usr/local/Vircon32/v32tools/include/v32lua/*.lua
#                      /usr/local/Vircon32/v32tools/docs/v32lua/
#       Windows      : <Program Files>/Vircon32/v32tools/v32lua.exe
#                      <Program Files>/Vircon32/v32tools/include/v32lua/*.lua
#                      <Program Files>/Vircon32/v32tools/docs/v32lua/
#                       (the READMEs, doc/ and the manual page)
#
#   Change the root with -DCMAKE_INSTALL_PREFIX=<dir> when configuring.
#   The  include  directory  (lib/*.lua,  the  standard-library ports) is
#   compiled  into the compiler (config.h's V32LUA_INCLUDE_PATH), so `--
#   #include  "string.lua"`  works  from any directory. The path compiled
#   in  is  the configure-time one: `cmake --install build --prefix <dir>`
#   copies  the  files  elsewhere  but  the  compiler still looks where it
#   was configured to.
#
#   flex  and  bison  (3.x)  are used when found; otherwise the parser and
#   lexer  already  generated  in  the  source  tree  (src/parser.c,
#   inc/parser.h,  src/lexer.c)  are  compiled  as they are, so neither tool
#   is  needed  for  a  plain  build  --  only  for  changing src/parser.y or
#   src/lexer.l.
# ----------------------------------------------------------------------------

cmake_minimum_required(VERSION 3.13...3.31)

# Refuse  an in-source build: CMake's generated Makefile would overwrite
# the project's own hand-written base Makefile.
#
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR)
    message(FATAL_ERROR
        "v32lua: in-source CMake builds are not supported -- they would "
        "overwrite the base Makefile. Build in a separate directory:\n"
        "    cmake -S . -B build\n"
        "First remove the CMakeCache.txt and CMakeFiles/ just created here.")
endif()

# By  default,  project configuration will be Release (must be done before
# the project() statement)
#
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING
        "Choose the type of build (Debug, Release, RelWithDebInfo, MinSizeRel)" FORCE)
endif()

# ----------------------------------------------------------------------------
#   VERSION (single source: inc/v32lua.h)
# ----------------------------------------------------------------------------

# The  full  version  string,  e.g.  "20261010-dev",  read from the same
# #define  that  `v32lua --version` prints and `make version` stamps into
# the man page. Configuration re-runs automatically when it changes.
#
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/inc/v32lua.h" V32LUA_VERSION_LINE
     REGEX "^#define[ \t]+VERSION[ \t]+\"[^\"]*\"")
string(REGEX REPLACE "^#define[ \t]+VERSION[ \t]+\"([^\"]*)\".*" "\\1"
       V32LUA_VERSION "${V32LUA_VERSION_LINE}")
if(NOT V32LUA_VERSION)
    message(FATAL_ERROR "v32lua: could not read VERSION from inc/v32lua.h")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
             "${CMAKE_CURRENT_SOURCE_DIR}/inc/v32lua.h")

# project()  only  takes  a  numeric  version:  derive YYYY.MM.DD from the
# leading date (the "-dev"/"-release" status is kept in V32LUA_VERSION).
#
if(V32LUA_VERSION MATCHES "^([0-9][0-9][0-9][0-9])([0-9][0-9])([0-9][0-9])")
    set(V32LUA_NUMERIC_VERSION "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}")
else()
    set(V32LUA_NUMERIC_VERSION "0.0.0")
endif()

# ----------------------------------------------------------------------------
#   DEFINE THE PROJECT
# ----------------------------------------------------------------------------

# ASM: src/runtime_embed.S, which .incbin's the Vircon32 runtime (src/
# runtime/*.s) into the executable. It is assembled through the C compiler
# (preprocessed, as a .S file).
#
project(v32lua
        VERSION ${V32LUA_NUMERIC_VERSION}
        DESCRIPTION "Lua compiler for the Vircon32 fantasy console"
        HOMEPAGE_URL "https://github.com/wedge1020/v32lua"
        LANGUAGES C ASM)

# ----------------------------------------------------------------------------
#   IDENTIFY HOST ENVIRONMENT
# ----------------------------------------------------------------------------

if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(TARGET_BITS "64")
elseif(CMAKE_SIZEOF_VOID_P EQUAL 4)
    set(TARGET_BITS "32")
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(TARGET_OS "windows")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(TARGET_OS "mac")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(TARGET_OS "linux")
else()
    set(TARGET_OS "${CMAKE_SYSTEM_NAME}")
endif()

# v32lua  is  POSIX-style  C  (<unistd.h> in the flex lexer, strtok_r,
# strcasecmp)  and  embeds  its  runtime  with  GNU assembler directives,
# which  MinGW,  glibc,  musl, macOS and the BSDs all handle but Visual C++
# does not. The Vircon32 DevTools are likewise built with MSYS2 + MinGW
# on Windows.
#
include(CheckIncludeFile)
check_include_file(unistd.h  V32LUA_HAVE_UNISTD_H)
check_include_file(strings.h V32LUA_HAVE_STRINGS_H)
if(MSVC OR NOT V32LUA_HAVE_UNISTD_H OR NOT V32LUA_HAVE_STRINGS_H)
    message(FATAL_ERROR
        "v32lua: needs a GCC- or Clang-style toolchain with a POSIX-style C "
        "library (<unistd.h>, <strings.h>, GNU assembler syntax). On "
        "Windows, build with MSYS2 + MinGW-w64, e.g. from a MINGW64 shell:\n"
        "    cmake -S . -B build -G \"MSYS Makefiles\"")
endif()

# The embedded-runtime symbols carry no leading underscore except on macOS
# (handled in runtime_embed.S); 32-bit Windows would also want one.
#
if(TARGET_OS STREQUAL "windows" AND TARGET_BITS STREQUAL "32")
    message(FATAL_ERROR
        "v32lua: 32-bit Windows builds are not supported; use a 64-bit "
        "MinGW-w64 toolchain (MSYS2's MINGW64 or UCRT64 shell).")
endif()

# ----------------------------------------------------------------------------
#   INSTALL LOCATIONS
# ----------------------------------------------------------------------------

# On  Windows, CMake's default prefix would be "<Program Files>/v32lua".
# Install  under "<Program Files>/Vircon32" instead -- the DevTools' own
# root  --  with v32lua.exe in v32tools/, beside v32opt.exe and v32c++.exe,
# so  one PATH entry covers the community tools. An explicit
# -DCMAKE_INSTALL_PREFIX always wins. (Only when the default has the usual
# "<Program  Files>/v32lua"  shape  --  the  parent is then whichever of
# "Program Files" or "Program Files (x86)" CMake picked for this
# toolchain, exactly as for the DevTools.)
#
if(TARGET_OS STREQUAL "windows" AND CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    get_filename_component(V32LUA_PREFIX_NAME   "${CMAKE_INSTALL_PREFIX}" NAME)
    get_filename_component(V32LUA_PROGRAM_FILES "${CMAKE_INSTALL_PREFIX}" DIRECTORY)
    if(V32LUA_PREFIX_NAME STREQUAL PROJECT_NAME)
        set(CMAKE_INSTALL_PREFIX "${V32LUA_PROGRAM_FILES}/Vircon32" CACHE PATH
            "Install path prefix, prepended onto install directories." FORCE)
    endif()
endif()

include(GNUInstallDirs)   # bin, share/man (CMAKE_INSTALL_PREFIX defaults to /usr/local on Unix)

if(TARGET_OS STREQUAL "windows")
    set(V32LUA_TOOLS_ROOT          "v32tools")
    set(V32LUA_DEFAULT_BINDIR      "v32tools")
    set(V32LUA_DEFAULT_MANDIR      "v32tools/docs/v32lua")
else()
    set(V32LUA_TOOLS_ROOT          "Vircon32/v32tools")
    set(V32LUA_DEFAULT_BINDIR      "${CMAKE_INSTALL_BINDIR}")
    set(V32LUA_DEFAULT_MANDIR      "${CMAKE_INSTALL_MANDIR}/man1")
endif()
set(V32LUA_DEFAULT_INCLUDEDIR      "${V32LUA_TOOLS_ROOT}/include/v32lua")
set(V32LUA_DEFAULT_DOCDIR          "${V32LUA_TOOLS_ROOT}/docs/v32lua")

set(V32LUA_INSTALL_BINDIR "${V32LUA_DEFAULT_BINDIR}" CACHE STRING
    "Where the v32lua executable is installed (relative to CMAKE_INSTALL_PREFIX)")
set(V32LUA_INSTALL_MANDIR "${V32LUA_DEFAULT_MANDIR}" CACHE STRING
    "Where the v32lua.1 manual page is installed (relative to CMAKE_INSTALL_PREFIX)")
set(V32LUA_INSTALL_INCLUDEDIR "${V32LUA_DEFAULT_INCLUDEDIR}" CACHE STRING
    "Where lib/*.lua (the --#include library) goes, relative to CMAKE_INSTALL_PREFIX or absolute; compiled into v32lua")
set(V32LUA_INSTALL_DOCDIR "${V32LUA_DEFAULT_DOCDIR}" CACHE STRING
    "Where the READMEs and doc/ are installed (relative to CMAKE_INSTALL_PREFIX; empty = not installed)")

# The absolute --#include directory the compiler is built to search.
#
if(IS_ABSOLUTE "${V32LUA_INSTALL_INCLUDEDIR}")
    set(V32LUA_LIBRARY_PATH "${V32LUA_INSTALL_INCLUDEDIR}")
else()
    set(V32LUA_LIBRARY_PATH "${CMAKE_INSTALL_PREFIX}/${V32LUA_INSTALL_INCLUDEDIR}")
endif()

# ----------------------------------------------------------------------------
#   PARSER AND LEXER
# ----------------------------------------------------------------------------

option(V32LUA_REGENERATE_PARSER
       "Regenerate the parser and lexer with bison and flex (when both are found)" ON)

set(V32LUA_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${V32LUA_GENERATED_DIR}")
set(V32LUA_USE_SHIPPED_PARSER TRUE)
if(V32LUA_REGENERATE_PARSER)
    find_package(BISON 3.0)
    find_package(FLEX)
    if(BISON_FOUND AND FLEX_FOUND)
        BISON_TARGET(v32lua_parser "${CMAKE_CURRENT_SOURCE_DIR}/src/parser.y"
                     "${V32LUA_GENERATED_DIR}/parser.c"
                     DEFINES_FILE "${V32LUA_GENERATED_DIR}/parser.h"
                     COMPILE_FLAGS "-t")
        FLEX_TARGET(v32lua_lexer "${CMAKE_CURRENT_SOURCE_DIR}/src/lexer.l"
                    "${V32LUA_GENERATED_DIR}/lexer.c")
        ADD_FLEX_BISON_DEPENDENCY(v32lua_lexer v32lua_parser)
        set(V32LUA_PARSER_SRC ${BISON_v32lua_parser_OUTPUTS} ${FLEX_v32lua_lexer_OUTPUTS})
        set(V32LUA_USE_SHIPPED_PARSER FALSE)
    endif()
endif()
if(V32LUA_USE_SHIPPED_PARSER)
    set(V32LUA_PARSER_SRC
        "${CMAKE_CURRENT_SOURCE_DIR}/src/parser.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/lexer.c")
endif()

# ----------------------------------------------------------------------------
#   EMBEDDED RUNTIME
# ----------------------------------------------------------------------------

# runtime_embed.S names each runtime unit relative to src/ (`.incbin
# "runtime/memory.s"`), which the base Makefile satisfies by assembling
# from inside src/. Assemblers differ in whether -I reaches .incbin, so
# the build uses a copy with absolute paths instead -- the same on every
# toolchain. Regenerated whenever runtime_embed.S changes; any change to a
# runtime/*.s file re-assembles it.
#
set(V32LUA_EMBED_SRC "${CMAKE_CURRENT_SOURCE_DIR}/src/runtime_embed.S")
file(READ "${V32LUA_EMBED_SRC}" V32LUA_EMBED_TEXT)
string(REPLACE ".incbin \"runtime/"
               ".incbin \"${CMAKE_CURRENT_SOURCE_DIR}/src/runtime/"
               V32LUA_EMBED_TEXT "${V32LUA_EMBED_TEXT}")
file(WRITE "${V32LUA_GENERATED_DIR}/runtime_embed.S.new" "${V32LUA_EMBED_TEXT}")
configure_file("${V32LUA_GENERATED_DIR}/runtime_embed.S.new"
               "${V32LUA_GENERATED_DIR}/runtime_embed.S" COPYONLY)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${V32LUA_EMBED_SRC}")

file(GLOB V32LUA_RUNTIME_UNITS CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/src/runtime/*.s")
set_source_files_properties("${V32LUA_GENERATED_DIR}/runtime_embed.S" PROPERTIES
    LANGUAGE ASM
    OBJECT_DEPENDS "${V32LUA_RUNTIME_UNITS}")

# ----------------------------------------------------------------------------
#   SOURCE FILES
# ----------------------------------------------------------------------------

# Same set the base Makefile (src/Makefile) links into bin/v32lua: its
# CORE_SRCS, plus every src/node/*.c and src/intrinsics/*.c.
#
set(V32LUA_CORE_SRC
    src/main.c
    src/context.c
    src/ffi.c
    src/closures.c
    src/generator.c
    src/ast.c
    src/emit.c
    src/internals.c
    src/register.c
    src/table.c
    src/tilemap.c
    src/pico8_assets.c
    src/pico8_shorthand.c
    src/pico8_audio.c
    src/pico8_prelude.c
    src/pico8_bezel.c
    src/png.c
    src/tic80_assets.c
    src/tic80_cart.c
    src/tic80_audio.c
    src/vtex_generator.c
    src/shapes.c
    src/v32kbd.c
    src/v32mouse.c)

file(GLOB V32LUA_NODE_SRC       CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/node/*.c")
file(GLOB V32LUA_INTRINSICS_SRC CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/intrinsics/*.c")
file(GLOB V32LUA_HEADERS        "${CMAKE_CURRENT_SOURCE_DIR}/inc/*.h")
list(REMOVE_ITEM V32LUA_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/inc/parser.h")

# ----------------------------------------------------------------------------
#   EXECUTABLE
# ----------------------------------------------------------------------------

add_executable(v32lua
    ${V32LUA_CORE_SRC}
    ${V32LUA_NODE_SRC}
    ${V32LUA_INTRINSICS_SRC}
    ${V32LUA_PARSER_SRC}
    "${V32LUA_GENERATED_DIR}/runtime_embed.S"
    ${V32LUA_HEADERS})

# C11  with the platform's extensions (gnu11, close to the base Makefile's
# compiler default): strdup, strtok_r and strcasecmp are declared by the
# system headers in that mode.
#
set_target_properties(v32lua PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS ON)

# A regenerated parser.h (build tree) must win over the one shipped in
# inc/.
#
if(NOT V32LUA_USE_SHIPPED_PARSER)
    target_include_directories(v32lua BEFORE PRIVATE "${V32LUA_GENERATED_DIR}")
endif()
target_include_directories(v32lua PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/inc")

# YYDEBUG=1 as in the base Makefile (the parser's trace support).
#
target_compile_definitions(v32lua PRIVATE
    "YYDEBUG=1"
    "V32LUA_INCLUDE_PATH=\"${V32LUA_LIBRARY_PATH}\"")

# Warning flags, matching the base Makefile where the compiler supports
# them (flex/bison output trips -Wextra: that is theirs, not ours)
#
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(v32lua PRIVATE $<$<COMPILE_LANGUAGE:C>:-Wall -Wextra>)
    set_source_files_properties(${V32LUA_PARSER_SRC} PROPERTIES
        COMPILE_OPTIONS "-Wno-unused-function;-Wno-sign-compare;-Wno-unused-parameter")
endif()

# The math library, where it is a separate one.
#
if(UNIX)
    target_link_libraries(v32lua PRIVATE m)
endif()

# MinGW: link the C runtime support statically, so the installed
# v32lua.exe needs no MinGW DLLs next to it.
#
option(V32LUA_STATIC_MINGW "Statically link MinGW runtime libraries" ON)
if(MINGW AND V32LUA_STATIC_MINGW)
    target_link_options(v32lua PRIVATE -static)
endif()

# ----------------------------------------------------------------------------
#   SHOW BUILD INFORMATION IN PRETTY FORMAT
# ----------------------------------------------------------------------------

message(STATUS "******** v32lua ********")
message(STATUS "Version: ${V32LUA_VERSION}")
if(NOT TARGET_OS STREQUAL "mac")
    message(STATUS "Target OS: ${TARGET_OS} ${TARGET_BITS}bit")
else()
    message(STATUS "Target OS: ${TARGET_OS} ${TARGET_BITS}bit (SDK: ${CMAKE_OSX_SYSROOT})")
endif()
message(STATUS "Compiler: ${CMAKE_C_COMPILER}")
if(CMAKE_CONFIGURATION_TYPES)
    message(STATUS "Build type: (chosen at build time)")
else()
    message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
endif()
if(V32LUA_USE_SHIPPED_PARSER)
    message(STATUS "Parser: the generated src/parser.c and src/lexer.c (no bison/flex regeneration)")
else()
    message(STATUS "Parser: regenerated with bison ${BISON_VERSION} and flex ${FLEX_VERSION}")
endif()
message(STATUS "Install prefix: ${CMAKE_INSTALL_PREFIX}")
message(STATUS " * executable  -> ${V32LUA_INSTALL_BINDIR}")
message(STATUS " * manual page -> ${V32LUA_INSTALL_MANDIR}")
message(STATUS " * Lua library -> ${V32LUA_INSTALL_INCLUDEDIR} (compiled in: ${V32LUA_LIBRARY_PATH})")
if(V32LUA_INSTALL_DOCDIR)
    message(STATUS " * documents   -> ${V32LUA_INSTALL_DOCDIR}")
endif()

# ----------------------------------------------------------------------------
#   DEFINE THE INSTALL PROCESS
# ----------------------------------------------------------------------------

install(TARGETS v32lua
        RUNTIME DESTINATION "${V32LUA_INSTALL_BINDIR}"
        COMPONENT binaries)

install(FILES man/v32lua.1
        DESTINATION "${V32LUA_INSTALL_MANDIR}"
        COMPONENT documentation)

# The standard-library ports --#include finds through V32LUA_INCLUDE_PATH.
#
file(GLOB V32LUA_LIBRARY_FILES "${CMAKE_CURRENT_SOURCE_DIR}/lib/*.lua")
install(FILES ${V32LUA_LIBRARY_FILES}
        DESTINATION "${V32LUA_INSTALL_INCLUDEDIR}"
        COMPONENT library)

# The READMEs at the top, the rest in doc/ beside them, so the links
# between them keep working.
#
if(V32LUA_INSTALL_DOCDIR)
    install(FILES README.md README.es.md README.fr.md
            DESTINATION "${V32LUA_INSTALL_DOCDIR}"
            COMPONENT documentation)
    install(DIRECTORY doc/
            DESTINATION "${V32LUA_INSTALL_DOCDIR}/doc"
            COMPONENT documentation
            FILES_MATCHING PATTERN "*.md")
endif()

if(TARGET_OS STREQUAL "windows")
    install(CODE "message(STATUS \"v32lua: add ${CMAKE_INSTALL_PREFIX}/${V32LUA_INSTALL_BINDIR} to your PATH\")")
endif()

# `cmake --build build --target uninstall` removes whatever the last
# install put down (CMake has no built-in uninstall; this replays
# install_manifest.txt), then the directories that leaves empty.
#
if(TARGET_OS STREQUAL "windows")
    set(V32LUA_UNIX_VIRCON32_DIR "")                              # that is the prefix
else()
    set(V32LUA_UNIX_VIRCON32_DIR "${CMAKE_INSTALL_PREFIX}/Vircon32")
endif()
if(NOT TARGET uninstall)
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/cmake_uninstall.cmake.in"
        "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
        @ONLY)
    add_custom_target(uninstall
        COMMAND "${CMAKE_COMMAND}" -P "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
        COMMENT "Uninstalling v32lua")
endif()

# ----------------------------------------------------------------------------
#   TESTS (ctest)
# ----------------------------------------------------------------------------

# The binary reports the expected version, every test program `make
# tests` covers compiles, and every program in testing/fail/ is refused.
# The categories are read from testing/Makefile's `tests` recipe (one
# source of truth): each `$(MAKE) -C <dir> tests` line adds the
# testing/<dir>/*.lua programs, compiled with the flags the category
# Makefiles use (-w -g), run in their own directory (some read data files
# next to them) and writing into the build tree. Running the results on
# v32sim and checking their values is still `make tests`.
#
option(BUILD_TESTING "Define the ctest tests" ON)
if(BUILD_TESTING)
    enable_testing()
    add_test(NAME version COMMAND v32lua --version)
    set_tests_properties(version PROPERTIES PASS_REGULAR_EXPRESSION "${V32LUA_VERSION}")

    file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/testing/Makefile" V32LUA_TEST_LINES
         REGEX "^\t@?\\$\\(MAKE\\) -C [A-Za-z0-9_]+ tests")
    set(V32LUA_TEST_OUT "${CMAKE_CURRENT_BINARY_DIR}/testing")
    foreach(line IN LISTS V32LUA_TEST_LINES)
        string(REGEX REPLACE "^.*-C ([A-Za-z0-9_]+) tests.*$" "\\1" category "${line}")
        file(GLOB programs "${CMAKE_CURRENT_SOURCE_DIR}/testing/${category}/*.lua")
        file(MAKE_DIRECTORY "${V32LUA_TEST_OUT}/${category}")
        foreach(program IN LISTS programs)
            get_filename_component(name "${program}" NAME_WE)
            add_test(NAME "${category}/${name}"
                     COMMAND v32lua -w -g -o "${V32LUA_TEST_OUT}/${category}/${name}.asm" "${program}"
                     WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/testing/${category}")
        endforeach()
    endforeach()

    file(GLOB programs "${CMAKE_CURRENT_SOURCE_DIR}/testing/fail/*.lua")
    file(MAKE_DIRECTORY "${V32LUA_TEST_OUT}/fail")
    foreach(program IN LISTS programs)
        get_filename_component(name "${program}" NAME_WE)
        add_test(NAME "fail/${name}"
                 COMMAND v32lua -w -o "${V32LUA_TEST_OUT}/fail/${name}.asm" "${program}"
                 WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/testing/fail")
        set_tests_properties("fail/${name}" PROPERTIES WILL_FAIL TRUE)
    endforeach()
endif()

# ----------------------------------------------------------------------------
#   DEFINE THE PACKAGE CREATION WITH CPACK
# ----------------------------------------------------------------------------

# `cpack` (from the build directory) makes binary packages, as the
# Vircon32 DevTools do: .deb/.rpm/.tar.gz on Linux, .tar.gz on macOS,
# .zip on Windows. Packages carry the full version string in their file
# name; the package-manager version is the numeric YYYY.MM.DD date.
#
set(CPACK_PACKAGE_NAME "v32lua")
set(CPACK_PACKAGE_VENDOR "Matthew Haas")
set(CPACK_PACKAGE_CONTACT "Matthew Haas")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Lua compiler for the Vircon32 fantasy console")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/wedge1020/v32lua")
set(CPACK_PACKAGE_FILE_NAME "v32lua-${V32LUA_VERSION}-${TARGET_OS}${TARGET_BITS}")
set(CPACK_RESOURCE_FILE_README "${CMAKE_CURRENT_SOURCE_DIR}/README.md")
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
    set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
endif()

if(TARGET_OS STREQUAL "linux")
    set(CPACK_PACKAGING_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")
    set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Matthew Haas")
    set(CPACK_DEBIAN_PACKAGE_SECTION "devel")
    set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS OFF)
    set(CPACK_RPM_PACKAGE_GROUP "Development/Tools")
    set(CPACK_RPM_PACKAGE_AUTOREQ ON)
    set(CPACK_GENERATOR "TGZ")
    find_program(V32LUA_DPKG_DEB dpkg-deb)
    if(V32LUA_DPKG_DEB)
        list(APPEND CPACK_GENERATOR "DEB")
    endif()
    find_program(V32LUA_RPMBUILD rpmbuild)
    if(V32LUA_RPMBUILD)
        list(APPEND CPACK_GENERATOR "RPM")
    endif()
elseif(TARGET_OS STREQUAL "windows")
    set(CPACK_GENERATOR "ZIP")
else()
    set(CPACK_GENERATOR "TGZ")
endif()

include(CPack)
