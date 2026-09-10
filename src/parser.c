/* A Bison parser, made by GNU Bison 2.3.  */

/* Skeleton implementation for Bison's Yacc-like parsers in C

   Copyright (C) 1984, 1989, 1990, 2000, 2001, 2002, 2003, 2004, 2005, 2006
   Free Software Foundation, Inc.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301, USA.  */

/* As a special exception, you may create a larger work that contains
   part or all of the Bison parser skeleton and distribute that work
   under terms of your choice, so long as that work isn't itself a
   parser generator using the skeleton or a modified version thereof
   as a parser skeleton.  Alternatively, if you modify or redistribute
   the parser skeleton itself, you may (at your option) remove this
   special exception, which will cause the skeleton and the resulting
   Bison output files to be licensed under the GNU General Public
   License without this special exception.

   This special exception was added by the Free Software Foundation in
   version 2.2 of Bison.  */

/* C LALR(1) parser skeleton written by Richard Stallman, by
   simplifying the original so-called "semantic" parser.  */

/* All symbols defined below should begin with yy or YY, to avoid
   infringing on user name space.  This should be done even for local
   variables, as they might otherwise be expanded by user macros.
   There are some unavoidable exceptions within include files to
   define necessary library symbols; they are noted "INFRINGES ON
   USER NAME SPACE" below.  */

/* Identify Bison output.  */
#define YYBISON 1

/* Bison version.  */
#define YYBISON_VERSION "2.3"

/* Skeleton name.  */
#define YYSKELETON_NAME "yacc.c"

/* Pure parsers.  */
#define YYPURE 0

/* Using locations.  */
#define YYLSP_NEEDED 0



/* Tokens.  */
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
   /* Put the tokens into the symbol table, so that GDB and other debuggers
      know about them.  */
   enum yytokentype {
     TOKEN_NUMBER = 258,
     TOKEN_IDENTIFIER = 259,
     TOKEN_STRING = 260,
     TOKEN_COMMENT_LINE = 261,
     TOKEN_COMMENT_BLOCK = 262,
     TOKEN_TIC80_SECTION_HEADER = 263,
     TOKEN_TIC80_ASSET_DATA = 264,
     TOKEN_TIC80_SECTION_FOOTER = 265,
     TOKEN_CART_HINT = 266,
     TOKEN_WHILE = 267,
     TOKEN_FOR = 268,
     TOKEN_BREAK = 269,
     TOKEN_IF = 270,
     TOKEN_ELSEIF = 271,
     TOKEN_THEN = 272,
     TOKEN_ELSE = 273,
     TOKEN_END = 274,
     TOKEN_FUNCTION = 275,
     TOKEN_ASM = 276,
     TOKEN_RAWASM = 277,
     TOKEN_RETURN = 278,
     TOKEN_AND = 279,
     TOKEN_OR = 280,
     TOKEN_EQ = 281,
     TOKEN_NEQ = 282,
     TOKEN_LE = 283,
     TOKEN_GE = 284,
     TOKEN_LT = 285,
     TOKEN_GT = 286,
     TOKEN_CONCAT = 287,
     TOKEN_LOCAL = 288,
     TOKEN_IN = 289,
     TOKEN_DO = 290,
     TOKEN_NOT = 291,
     TOKEN_LEN = 292,
     UNARY_MINUS = 293,
     TOKEN_TRUE = 294,
     TOKEN_FALSE = 295,
     TOKEN_NIL = 296,
     TOKEN_FLOORDIV = 297,
     TOKEN_DOTS = 298,
     TOKEN_REPEAT = 299,
     TOKEN_UNTIL = 300
   };
#endif
/* Tokens.  */
#define TOKEN_NUMBER 258
#define TOKEN_IDENTIFIER 259
#define TOKEN_STRING 260
#define TOKEN_COMMENT_LINE 261
#define TOKEN_COMMENT_BLOCK 262
#define TOKEN_TIC80_SECTION_HEADER 263
#define TOKEN_TIC80_ASSET_DATA 264
#define TOKEN_TIC80_SECTION_FOOTER 265
#define TOKEN_CART_HINT 266
#define TOKEN_WHILE 267
#define TOKEN_FOR 268
#define TOKEN_BREAK 269
#define TOKEN_IF 270
#define TOKEN_ELSEIF 271
#define TOKEN_THEN 272
#define TOKEN_ELSE 273
#define TOKEN_END 274
#define TOKEN_FUNCTION 275
#define TOKEN_ASM 276
#define TOKEN_RAWASM 277
#define TOKEN_RETURN 278
#define TOKEN_AND 279
#define TOKEN_OR 280
#define TOKEN_EQ 281
#define TOKEN_NEQ 282
#define TOKEN_LE 283
#define TOKEN_GE 284
#define TOKEN_LT 285
#define TOKEN_GT 286
#define TOKEN_CONCAT 287
#define TOKEN_LOCAL 288
#define TOKEN_IN 289
#define TOKEN_DO 290
#define TOKEN_NOT 291
#define TOKEN_LEN 292
#define UNARY_MINUS 293
#define TOKEN_TRUE 294
#define TOKEN_FALSE 295
#define TOKEN_NIL 296
#define TOKEN_FLOORDIV 297
#define TOKEN_DOTS 298
#define TOKEN_REPEAT 299
#define TOKEN_UNTIL 300




/* Copy the first part of user declarations.  */
#line 1 "parser.y"


#include "v32lua.h"

// Define the global AST root variable here
ASTNode* root_node = NULL;

extern int yylineno;
extern FILE* yyin;
extern int yylex (void);
void yyerror (const char *s);

// Add your new helper prototype here:
char *mangle_method_name (const char *table_name, const char *method_name);



/* Enabling traces.  */
#ifndef YYDEBUG
# define YYDEBUG 1
#endif

/* Enabling verbose error messages.  */
#ifdef YYERROR_VERBOSE
# undef YYERROR_VERBOSE
# define YYERROR_VERBOSE 1
#else
# define YYERROR_VERBOSE 0
#endif

/* Enabling the token table.  */
#ifndef YYTOKEN_TABLE
# define YYTOKEN_TABLE 0
#endif

#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
typedef union YYSTYPE
#line 18 "parser.y"
{
    double   number_val;
    char    *string_val;
    ASTNode *ast_node;
}
/* Line 193 of yacc.c.  */
#line 209 "parser.c"
	YYSTYPE;
# define yystype YYSTYPE /* obsolescent; will be withdrawn */
# define YYSTYPE_IS_DECLARED 1
# define YYSTYPE_IS_TRIVIAL 1
#endif



/* Copy the second part of user declarations.  */


/* Line 216 of yacc.c.  */
#line 222 "parser.c"

#ifdef short
# undef short
#endif

#ifdef YYTYPE_UINT8
typedef YYTYPE_UINT8 yytype_uint8;
#else
typedef unsigned char yytype_uint8;
#endif

#ifdef YYTYPE_INT8
typedef YYTYPE_INT8 yytype_int8;
#elif (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
typedef signed char yytype_int8;
#else
typedef short int yytype_int8;
#endif

#ifdef YYTYPE_UINT16
typedef YYTYPE_UINT16 yytype_uint16;
#else
typedef unsigned short int yytype_uint16;
#endif

#ifdef YYTYPE_INT16
typedef YYTYPE_INT16 yytype_int16;
#else
typedef short int yytype_int16;
#endif

#ifndef YYSIZE_T
# ifdef __SIZE_TYPE__
#  define YYSIZE_T __SIZE_TYPE__
# elif defined size_t
#  define YYSIZE_T size_t
# elif ! defined YYSIZE_T && (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
#  include <stddef.h> /* INFRINGES ON USER NAME SPACE */
#  define YYSIZE_T size_t
# else
#  define YYSIZE_T unsigned int
# endif
#endif

#define YYSIZE_MAXIMUM ((YYSIZE_T) -1)

#ifndef YY_
# if defined YYENABLE_NLS && YYENABLE_NLS
#  if ENABLE_NLS
#   include <libintl.h> /* INFRINGES ON USER NAME SPACE */
#   define YY_(msgid) dgettext ("bison-runtime", msgid)
#  endif
# endif
# ifndef YY_
#  define YY_(msgid) msgid
# endif
#endif

/* Suppress unused-variable warnings by "using" E.  */
#if ! defined lint || defined __GNUC__
# define YYUSE(e) ((void) (e))
#else
# define YYUSE(e) /* empty */
#endif

/* Identity function, used to suppress warnings about constant conditions.  */
#ifndef lint
# define YYID(n) (n)
#else
#if (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
static int
YYID (int i)
#else
static int
YYID (i)
    int i;
#endif
{
  return i;
}
#endif

#if ! defined yyoverflow || YYERROR_VERBOSE

/* The parser invokes alloca or malloc; define the necessary symbols.  */

# ifdef YYSTACK_USE_ALLOCA
#  if YYSTACK_USE_ALLOCA
#   ifdef __GNUC__
#    define YYSTACK_ALLOC __builtin_alloca
#   elif defined __BUILTIN_VA_ARG_INCR
#    include <alloca.h> /* INFRINGES ON USER NAME SPACE */
#   elif defined _AIX
#    define YYSTACK_ALLOC __alloca
#   elif defined _MSC_VER
#    include <malloc.h> /* INFRINGES ON USER NAME SPACE */
#    define alloca _alloca
#   else
#    define YYSTACK_ALLOC alloca
#    if ! defined _ALLOCA_H && ! defined _STDLIB_H && (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
#     include <stdlib.h> /* INFRINGES ON USER NAME SPACE */
#     ifndef _STDLIB_H
#      define _STDLIB_H 1
#     endif
#    endif
#   endif
#  endif
# endif

# ifdef YYSTACK_ALLOC
   /* Pacify GCC's `empty if-body' warning.  */
#  define YYSTACK_FREE(Ptr) do { /* empty */; } while (YYID (0))
#  ifndef YYSTACK_ALLOC_MAXIMUM
    /* The OS might guarantee only one guard page at the bottom of the stack,
       and a page size can be as small as 4096 bytes.  So we cannot safely
       invoke alloca (N) if N exceeds 4096.  Use a slightly smaller number
       to allow for a few compiler-allocated temporary stack slots.  */
#   define YYSTACK_ALLOC_MAXIMUM 4032 /* reasonable circa 2006 */
#  endif
# else
#  define YYSTACK_ALLOC YYMALLOC
#  define YYSTACK_FREE YYFREE
#  ifndef YYSTACK_ALLOC_MAXIMUM
#   define YYSTACK_ALLOC_MAXIMUM YYSIZE_MAXIMUM
#  endif
#  if (defined __cplusplus && ! defined _STDLIB_H \
       && ! ((defined YYMALLOC || defined malloc) \
	     && (defined YYFREE || defined free)))
#   include <stdlib.h> /* INFRINGES ON USER NAME SPACE */
#   ifndef _STDLIB_H
#    define _STDLIB_H 1
#   endif
#  endif
#  ifndef YYMALLOC
#   define YYMALLOC malloc
#   if ! defined malloc && ! defined _STDLIB_H && (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
void *malloc (YYSIZE_T); /* INFRINGES ON USER NAME SPACE */
#   endif
#  endif
#  ifndef YYFREE
#   define YYFREE free
#   if ! defined free && ! defined _STDLIB_H && (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
void free (void *); /* INFRINGES ON USER NAME SPACE */
#   endif
#  endif
# endif
#endif /* ! defined yyoverflow || YYERROR_VERBOSE */


#if (! defined yyoverflow \
     && (! defined __cplusplus \
	 || (defined YYSTYPE_IS_TRIVIAL && YYSTYPE_IS_TRIVIAL)))

/* A type that is properly aligned for any stack member.  */
union yyalloc
{
  yytype_int16 yyss;
  YYSTYPE yyvs;
  };

/* The size of the maximum gap between one aligned stack and the next.  */
# define YYSTACK_GAP_MAXIMUM (sizeof (union yyalloc) - 1)

/* The size of an array large to enough to hold all stacks, each with
   N elements.  */
# define YYSTACK_BYTES(N) \
     ((N) * (sizeof (yytype_int16) + sizeof (YYSTYPE)) \
      + YYSTACK_GAP_MAXIMUM)

/* Copy COUNT objects from FROM to TO.  The source and destination do
   not overlap.  */
# ifndef YYCOPY
#  if defined __GNUC__ && 1 < __GNUC__
#   define YYCOPY(To, From, Count) \
      __builtin_memcpy (To, From, (Count) * sizeof (*(From)))
#  else
#   define YYCOPY(To, From, Count)		\
      do					\
	{					\
	  YYSIZE_T yyi;				\
	  for (yyi = 0; yyi < (Count); yyi++)	\
	    (To)[yyi] = (From)[yyi];		\
	}					\
      while (YYID (0))
#  endif
# endif

/* Relocate STACK from its old location to the new one.  The
   local variables YYSIZE and YYSTACKSIZE give the old and new number of
   elements in the stack, and YYPTR gives the new location of the
   stack.  Advance YYPTR to a properly aligned location for the next
   stack.  */
# define YYSTACK_RELOCATE(Stack)					\
    do									\
      {									\
	YYSIZE_T yynewbytes;						\
	YYCOPY (&yyptr->Stack, Stack, yysize);				\
	Stack = &yyptr->Stack;						\
	yynewbytes = yystacksize * sizeof (*Stack) + YYSTACK_GAP_MAXIMUM; \
	yyptr += yynewbytes / sizeof (*yyptr);				\
      }									\
    while (YYID (0))

#endif

/* YYFINAL -- State number of the termination state.  */
#define YYFINAL  61
/* YYLAST -- Last index in YYTABLE.  */
#define YYLAST   898

/* YYNTOKENS -- Number of terminals.  */
#define YYNTOKENS  63
/* YYNNTS -- Number of nonterminals.  */
#define YYNNTS  27
/* YYNRULES -- Number of rules.  */
#define YYNRULES  115
/* YYNRULES -- Number of states.  */
#define YYNSTATES  263

/* YYTRANSLATE(YYLEX) -- Bison symbol number corresponding to YYLEX.  */
#define YYUNDEFTOK  2
#define YYMAXUTOK   300

#define YYTRANSLATE(YYX)						\
  ((unsigned int) (YYX) <= YYMAXUTOK ? yytranslate[YYX] : YYUNDEFTOK)

/* YYTRANSLATE[YYLEX] -- Bison symbol number corresponding to YYLEX.  */
static const yytype_uint8 yytranslate[] =
{
       0,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,    50,     2,     2,
      59,    60,    48,    46,    56,    47,    53,    49,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,    54,    55,
       2,    57,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,    52,     2,    58,    51,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,    61,     2,    62,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     1,     2,     3,     4,
       5,     6,     7,     8,     9,    10,    11,    12,    13,    14,
      15,    16,    17,    18,    19,    20,    21,    22,    23,    24,
      25,    26,    27,    28,    29,    30,    31,    32,    33,    34,
      35,    36,    37,    38,    39,    40,    41,    42,    43,    44,
      45
};

#if YYDEBUG
/* YYPRHS[YYN] -- Index of the first RHS symbol of rule number YYN in
   YYRHS.  */
static const yytype_uint16 yyprhs[] =
{
       0,     0,     3,     5,     6,     8,    11,    13,    16,    20,
      22,    25,    26,    28,    30,    34,    38,    39,    41,    45,
      47,    49,    51,    53,    55,    57,    61,    66,    73,    79,
      85,    90,   100,   112,   120,   127,   131,   134,   136,   141,
     150,   161,   172,   177,   179,   181,   183,   185,   187,   190,
     192,   195,   196,   199,   205,   207,   211,   216,   220,   226,
     233,   235,   239,   247,   257,   267,   270,   272,   274,   276,
     280,   285,   289,   291,   293,   295,   297,   299,   303,   307,
     311,   315,   319,   323,   327,   329,   331,   333,   336,   339,
     342,   346,   350,   354,   358,   362,   366,   370,   374,   378,
     385,   390,   397,   404,   409,   411,   415,   421,   423,   427,
     430,   434,   439,   440,   445,   446
};

/* YYRHS -- A `-1'-separated list of the rules' RHS.  */
static const yytype_int8 yyrhs[] =
{
      64,     0,    -1,    65,    -1,    -1,    66,    -1,    66,    75,
      -1,    75,    -1,    74,    55,    -1,    66,    74,    55,    -1,
      74,    -1,    66,    74,    -1,    -1,     4,    -1,    43,    -1,
      67,    56,     4,    -1,    67,    56,    43,    -1,    -1,    82,
      -1,    68,    56,    82,    -1,    20,    -1,    12,    -1,    44,
      -1,    13,    -1,    15,    -1,    83,    -1,    77,    57,    78,
      -1,    33,    77,    57,    78,    -1,    81,    52,    82,    58,
      57,    82,    -1,    81,    53,     4,    57,    82,    -1,    70,
      82,    35,    65,    19,    -1,    71,    65,    45,    82,    -1,
      72,     4,    57,    82,    56,    82,    35,    65,    19,    -1,
      72,     4,    57,    82,    56,    82,    56,    82,    35,    65,
      19,    -1,    72,    77,    34,    78,    35,    65,    19,    -1,
      73,    82,    17,    65,    76,    19,    -1,    35,    65,    19,
      -1,    33,    77,    -1,    79,    -1,    21,    59,     5,    60,
      -1,    33,    69,     4,    59,    67,    60,    65,    19,    -1,
      33,    69,     4,    54,     4,    59,    67,    60,    65,    19,
      -1,    33,    69,     4,    53,     4,    59,    67,    60,    65,
      19,    -1,    22,    59,     5,    60,    -1,     6,    -1,     7,
      -1,    87,    -1,    11,    -1,    80,    -1,    80,    55,    -1,
      14,    -1,    14,    55,    -1,    -1,    18,    65,    -1,    16,
      82,    17,    65,    76,    -1,     4,    -1,    81,    53,     4,
      -1,    81,    52,    82,    58,    -1,    77,    56,     4,    -1,
      77,    56,    81,    53,     4,    -1,    77,    56,    81,    52,
      82,    58,    -1,    82,    -1,    78,    56,    82,    -1,    69,
       4,    59,    67,    60,    65,    19,    -1,    69,     4,    53,
       4,    59,    67,    60,    65,    19,    -1,    69,     4,    54,
       4,    59,    67,    60,    65,    19,    -1,    23,    78,    -1,
      23,    -1,     4,    -1,    83,    -1,    59,    82,    60,    -1,
      81,    52,    82,    58,    -1,    81,    53,     4,    -1,    43,
      -1,     3,    -1,     5,    -1,    86,    -1,    81,    -1,    82,
      46,    82,    -1,    82,    47,    82,    -1,    82,    48,    82,
      -1,    82,    42,    82,    -1,    82,    49,    82,    -1,    82,
      50,    82,    -1,    82,    51,    82,    -1,    39,    -1,    40,
      -1,    41,    -1,    37,    82,    -1,    47,    82,    -1,    36,
      82,    -1,    82,    26,    82,    -1,    82,    27,    82,    -1,
      82,    30,    82,    -1,    82,    31,    82,    -1,    82,    28,
      82,    -1,    82,    29,    82,    -1,    82,    24,    82,    -1,
      82,    25,    82,    -1,    82,    32,    82,    -1,    69,    59,
      67,    60,    65,    19,    -1,     4,    59,    68,    60,    -1,
      81,    53,     4,    59,    68,    60,    -1,    81,    54,     4,
      59,    68,    60,    -1,    81,    59,    68,    60,    -1,    82,
      -1,    82,    57,    82,    -1,    52,    82,    58,    57,    82,
      -1,    84,    -1,    85,    56,    84,    -1,    61,    62,    -1,
      61,    85,    62,    -1,    61,    85,    56,    62,    -1,    -1,
       8,    88,    89,    10,    -1,    -1,    89,     9,    -1
};

/* YYRLINE[YYN] -- source line where rule number YYN was defined.  */
static const yytype_uint16 yyrline[] =
{
       0,    71,    71,    78,    79,    80,    92,    96,    97,   109,
     110,   125,   128,   131,   135,   142,   152,   155,   158,   171,
     175,   179,   183,   186,   190,   191,   197,   203,   208,   213,
     218,   229,   237,   245,   251,   257,   265,   271,   272,   276,
     334,   377,   408,   412,   416,   420,   421,   427,   428,   429,
     430,   434,   435,   436,   448,   451,   455,   458,   465,   473,
     483,   486,   496,   528,   556,   590,   595,   612,   615,   618,
     621,   626,   635,   638,   642,   643,   644,   645,   646,   647,
     648,   649,   650,   651,   652,   653,   654,   655,   656,   657,
     658,   659,   660,   661,   662,   663,   664,   665,   666,   667,
     698,   705,   717,   729,   739,   743,   752,   759,   762,   772,
     775,   778,   791,   790,   820,   821
};
#endif

#if YYDEBUG || YYERROR_VERBOSE || YYTOKEN_TABLE
/* YYTNAME[SYMBOL-NUM] -- String name of the symbol SYMBOL-NUM.
   First, the terminals, then, starting at YYNTOKENS, nonterminals.  */
static const char *const yytname[] =
{
  "$end", "error", "$undefined", "TOKEN_NUMBER", "TOKEN_IDENTIFIER",
  "TOKEN_STRING", "TOKEN_COMMENT_LINE", "TOKEN_COMMENT_BLOCK",
  "TOKEN_TIC80_SECTION_HEADER", "TOKEN_TIC80_ASSET_DATA",
  "TOKEN_TIC80_SECTION_FOOTER", "TOKEN_CART_HINT", "TOKEN_WHILE",
  "TOKEN_FOR", "TOKEN_BREAK", "TOKEN_IF", "TOKEN_ELSEIF", "TOKEN_THEN",
  "TOKEN_ELSE", "TOKEN_END", "TOKEN_FUNCTION", "TOKEN_ASM", "TOKEN_RAWASM",
  "TOKEN_RETURN", "TOKEN_AND", "TOKEN_OR", "TOKEN_EQ", "TOKEN_NEQ",
  "TOKEN_LE", "TOKEN_GE", "TOKEN_LT", "TOKEN_GT", "TOKEN_CONCAT",
  "TOKEN_LOCAL", "TOKEN_IN", "TOKEN_DO", "TOKEN_NOT", "TOKEN_LEN",
  "UNARY_MINUS", "TOKEN_TRUE", "TOKEN_FALSE", "TOKEN_NIL",
  "TOKEN_FLOORDIV", "TOKEN_DOTS", "TOKEN_REPEAT", "TOKEN_UNTIL", "'+'",
  "'-'", "'*'", "'/'", "'%'", "'^'", "'['", "'.'", "':'", "';'", "','",
  "'='", "']'", "'('", "')'", "'{'", "'}'", "$accept", "program",
  "statement_list", "stat_list", "parameter_list", "argument_list",
  "func_start", "while_start", "repeat_start", "for_start", "if_start",
  "statement", "last_statement", "else_branch", "var_list", "expr_list",
  "function_def", "return_stmt", "prefix_expr", "expr", "function_call",
  "field", "field_list", "table_constructor", "tic80_section", "@1",
  "tic80_asset_lines", 0
};
#endif

# ifdef YYPRINT
/* YYTOKNUM[YYLEX-NUM] -- Internal token number corresponding to
   token YYLEX-NUM.  */
static const yytype_uint16 yytoknum[] =
{
       0,   256,   257,   258,   259,   260,   261,   262,   263,   264,
     265,   266,   267,   268,   269,   270,   271,   272,   273,   274,
     275,   276,   277,   278,   279,   280,   281,   282,   283,   284,
     285,   286,   287,   288,   289,   290,   291,   292,   293,   294,
     295,   296,   297,   298,   299,   300,    43,    45,    42,    47,
      37,    94,    91,    46,    58,    59,    44,    61,    93,    40,
      41,   123,   125
};
# endif

/* YYR1[YYN] -- Symbol number of symbol that rule YYN derives.  */
static const yytype_uint8 yyr1[] =
{
       0,    63,    64,    65,    65,    65,    65,    66,    66,    66,
      66,    67,    67,    67,    67,    67,    68,    68,    68,    69,
      70,    71,    72,    73,    74,    74,    74,    74,    74,    74,
      74,    74,    74,    74,    74,    74,    74,    74,    74,    74,
      74,    74,    74,    74,    74,    74,    74,    75,    75,    75,
      75,    76,    76,    76,    77,    77,    77,    77,    77,    77,
      78,    78,    79,    79,    79,    80,    80,    81,    81,    81,
      81,    81,    82,    82,    82,    82,    82,    82,    82,    82,
      82,    82,    82,    82,    82,    82,    82,    82,    82,    82,
      82,    82,    82,    82,    82,    82,    82,    82,    82,    82,
      83,    83,    83,    83,    84,    84,    84,    85,    85,    86,
      86,    86,    88,    87,    89,    89
};

/* YYR2[YYN] -- Number of symbols composing right hand side of rule YYN.  */
static const yytype_uint8 yyr2[] =
{
       0,     2,     1,     0,     1,     2,     1,     2,     3,     1,
       2,     0,     1,     1,     3,     3,     0,     1,     3,     1,
       1,     1,     1,     1,     1,     3,     4,     6,     5,     5,
       4,     9,    11,     7,     6,     3,     2,     1,     4,     8,
      10,    10,     4,     1,     1,     1,     1,     1,     2,     1,
       2,     0,     2,     5,     1,     3,     4,     3,     5,     6,
       1,     3,     7,     9,     9,     2,     1,     1,     1,     3,
       4,     3,     1,     1,     1,     1,     1,     3,     3,     3,
       3,     3,     3,     3,     1,     1,     1,     2,     2,     2,
       3,     3,     3,     3,     3,     3,     3,     3,     3,     6,
       4,     6,     6,     4,     1,     3,     5,     1,     3,     2,
       3,     4,     0,     4,     0,     2
};

/* YYDEFACT[STATE-NAME] -- Default rule to reduce with in state
   STATE-NUM when YYTABLE doesn't specify something else to do.  Zero
   means the default is an error.  */
static const yytype_uint8 yydefact[] =
{
       3,    54,    43,    44,   112,    46,    20,    22,    49,    23,
      19,     0,     0,    66,     0,     3,    21,     0,     0,     2,
       4,     0,     0,     3,     0,     0,     9,     6,     0,    37,
      47,     0,    24,    45,    16,   114,    50,     0,     0,    73,
      67,    74,     0,     0,    84,    85,    86,    72,     0,     0,
       0,    65,    76,    60,    68,    75,     0,    36,     0,     0,
       0,     1,    10,     5,     0,     0,     0,    67,     0,     0,
       7,     0,     0,    48,     0,     0,     0,    16,     0,    17,
       0,     0,     0,    89,    87,    88,     0,   109,   104,   107,
       0,    11,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,    35,    69,     8,     0,     0,
      11,     3,     0,     0,     0,     3,    57,     0,    25,     0,
      71,     0,     0,     0,   100,   115,   113,    38,    42,     0,
       0,     0,   110,    12,    13,     0,    61,     0,    71,    96,
      97,    90,    91,    94,    95,    92,    93,    98,    80,    77,
      78,    79,    81,    82,    83,     0,     0,    11,    26,     0,
      55,     0,     0,     0,     0,    30,     0,     0,    51,     0,
       0,    70,     0,    16,    16,   103,    18,     0,   105,   111,
     108,     0,     3,    70,     0,     0,     0,    56,    11,    11,
       3,    29,     0,     3,     0,     3,     0,     0,    58,     0,
      28,     0,     0,     0,    14,    15,     0,    11,    11,     3,
       0,     0,     0,     0,     0,     0,    52,    34,    59,    27,
     101,   102,   106,    99,     0,     0,     0,     3,     3,    62,
       3,     0,    33,     3,     3,     3,    39,     0,     0,     0,
       0,    51,     0,     0,    63,    64,    31,     3,    53,    41,
      40,     0,    32
};

/* YYDEFGOTO[NTERM-NUM].  */
static const yytype_int16 yydefgoto[] =
{
      -1,    18,    19,    20,   145,    78,    50,    22,    23,    24,
      25,    26,    27,   206,    28,    51,    29,    30,    52,    53,
      54,    89,    90,    55,    33,    35,    80
};

/* YYPACT[STATE-NUM] -- Index in YYTABLE of the portion describing
   STATE-NUM.  */
#define YYPACT_NINF -119
static const yytype_int16 yypact[] =
{
     386,    15,  -119,  -119,  -119,  -119,  -119,  -119,   -50,  -119,
    -119,   -43,   -19,   128,    -1,   386,  -119,   128,    55,  -119,
     386,   102,   128,   386,     2,   128,    60,  -119,    16,  -119,
      96,    24,    64,  -119,   128,  -119,  -119,    74,   169,  -119,
     124,  -119,   128,   128,  -119,  -119,  -119,  -119,   128,    23,
     129,   137,    75,   847,  -119,  -119,   191,   159,    87,   182,
     423,  -119,   152,  -119,   167,   791,   179,   -27,   -23,   460,
    -119,     6,   128,  -119,   128,   228,   229,   128,   -39,   847,
     208,   196,   201,   188,   188,   188,   128,  -119,   691,  -119,
     -44,     4,   128,   128,   238,   128,   128,   128,   128,   128,
     128,   128,   128,   128,   128,   128,   128,   128,   128,   128,
     128,   193,   128,   128,   249,  -119,  -119,  -119,   259,   260,
       4,   386,   128,   128,   128,   386,    15,   132,   137,   488,
     -18,   211,    -3,   128,  -119,  -119,  -119,  -119,  -119,   523,
     128,    83,  -119,  -119,  -119,    41,   847,   558,   224,    63,
     131,   162,   162,   162,   162,   162,   162,   162,   188,   148,
     148,   188,   188,   188,   188,   281,   283,     4,   137,   593,
     176,   231,   232,    42,   273,   847,   758,   -22,    34,   128,
     289,   192,   128,   128,   128,  -119,   847,   237,   847,  -119,
    -119,     5,   386,  -119,   236,   240,    93,    84,     4,     4,
     386,  -119,   128,   386,   128,   386,   277,   628,   176,   128,
     847,    94,   110,   128,  -119,  -119,   282,     4,     4,   386,
     116,   195,   286,   725,   287,   663,  -119,  -119,    84,   847,
    -119,  -119,   847,  -119,   198,   222,   288,   386,   386,  -119,
     386,   128,  -119,   386,   386,   386,  -119,   290,   291,   292,
     819,    34,   293,   294,  -119,  -119,  -119,   386,  -119,  -119,
    -119,   295,  -119
};

/* YYPGOTO[NTERM-NUM].  */
static const yytype_int16 yypgoto[] =
{
    -119,  -119,    81,  -119,  -118,   -76,    22,  -119,  -119,  -119,
    -119,   296,   297,    51,    11,   -68,  -119,  -119,     0,   255,
      31,   174,  -119,  -119,  -119,  -119,  -119
};

/* YYTABLE[YYPACT[STATE-NUM]].  What to do in state STATE-NUM.  If
   positive, shift that token.  If negative, reduce the rule which
   number is the opposite.  If zero, do what YYDEFACT says.
   If YYTABLE_NINF, syntax error.  */
#define YYTABLE_NINF -72
static const yytype_int16 yytable[] =
{
      31,   132,   173,     1,   128,    36,    67,   -54,   143,   214,
     126,   124,   141,   203,    58,    31,    37,   133,   142,    10,
      31,   134,    21,    31,    58,    57,    39,    40,    41,   -54,
     123,    32,    34,    71,    92,    68,    56,    21,   -55,   182,
      38,   183,    21,    10,   168,    21,    32,   144,   215,   196,
     204,    32,   205,   133,    32,    61,   177,   185,    17,    42,
      43,    17,    44,    45,    46,    17,    47,   -67,   -67,   -67,
      48,   127,    71,    72,    34,    86,    74,    75,    76,    81,
     220,   221,    17,    77,    49,    87,    39,    40,    41,    97,
      98,    99,   100,   101,   102,   103,    59,   191,   191,   234,
     235,   192,   200,    10,    66,   104,    64,   211,   212,   105,
     106,   107,   108,   109,   110,    70,   -68,   -68,   -68,    42,
      43,    31,    44,    45,    46,    31,    47,    93,    94,    76,
      48,    39,    40,    41,    77,    86,   -70,   -70,   -70,   113,
     114,    76,    17,    21,    49,   189,    77,    21,    10,   191,
     133,    73,    32,   219,   230,    95,    32,    97,    98,    99,
     100,   101,   102,   103,    42,    43,   133,    44,    45,    46,
     231,    47,   191,   104,    82,    48,   237,   105,   106,   107,
     108,   109,   110,    34,   179,   180,    76,    17,    91,    49,
     104,    77,    31,    92,   103,   111,   107,   108,   109,   110,
      31,   115,   174,    31,   104,    31,   178,   117,   105,   106,
     107,   108,   109,   110,    21,    71,   112,   135,   136,    31,
     118,   119,    21,    32,   122,    21,   120,    21,   -71,   -71,
     -71,    32,   130,   131,    32,   183,    32,    31,    31,   110,
      31,    21,   148,    31,    31,    31,   165,   166,   -56,   209,
      32,   191,   167,   170,   191,   238,   137,    31,   244,    21,
      21,   138,    21,   171,   172,    21,    21,    21,    32,    32,
     184,    32,    60,   216,    32,    32,    32,    65,   191,    21,
      69,   222,   245,   183,   224,   194,   226,   195,    32,    79,
     198,   199,   201,   208,   213,   217,   227,    83,    84,   218,
     236,   233,   258,    85,    88,   239,   242,   246,     0,   254,
     255,   256,   259,   260,   262,   190,    62,    63,   247,   248,
       0,   249,     0,     0,   251,   252,   253,     0,     0,   129,
       0,     0,    79,     0,     0,     0,     0,     0,   261,     0,
       0,   139,     0,     0,     0,     0,     0,   146,   147,     0,
     149,   150,   151,   152,   153,   154,   155,   156,   157,   158,
     159,   160,   161,   162,   163,   164,     0,     0,   169,     0,
       0,     0,     0,     0,     0,     0,     0,   175,   176,     0,
       0,     0,     0,     0,     0,     0,     0,     0,   186,     0,
       1,     0,     2,     3,     4,   188,    88,     5,     6,     7,
       8,     9,     0,     0,     0,     0,    10,    11,    12,    13,
       0,     0,     0,     0,     0,     0,     0,     0,     0,    14,
       0,    15,     0,     0,     0,     0,     0,     0,     0,     0,
      16,     0,     0,     0,   207,     0,     0,   210,    79,    79,
       0,     0,     0,     0,     0,    17,     0,    95,    96,    97,
      98,    99,   100,   101,   102,   103,     0,   223,     0,   225,
       0,     0,     0,     0,   229,   104,     0,     0,   232,   105,
     106,   107,   108,   109,   110,     0,     0,   125,     0,     0,
       0,     0,     0,   116,    95,    96,    97,    98,    99,   100,
     101,   102,   103,     0,     0,     0,   250,     0,     0,     0,
       0,     0,   104,     0,     0,     0,   105,   106,   107,   108,
     109,   110,    95,    96,    97,    98,    99,   100,   101,   102,
     103,     0,     0,     0,     0,     0,     0,     0,     0,     0,
     104,     0,     0,     0,   105,   106,   107,   108,   109,   110,
       0,     0,     0,     0,     0,     0,   181,    95,    96,    97,
      98,    99,   100,   101,   102,   103,     0,     0,     0,     0,
       0,     0,     0,     0,     0,   104,     0,     0,     0,   105,
     106,   107,   108,   109,   110,     0,     0,     0,     0,     0,
       0,   187,    95,    96,    97,    98,    99,   100,   101,   102,
     103,     0,     0,     0,     0,     0,     0,     0,     0,     0,
     104,     0,     0,     0,   105,   106,   107,   108,   109,   110,
       0,     0,     0,     0,     0,     0,   193,    95,    96,    97,
      98,    99,   100,   101,   102,   103,     0,     0,     0,     0,
       0,     0,     0,     0,     0,   104,     0,     0,     0,   105,
     106,   107,   108,   109,   110,     0,     0,     0,     0,     0,
       0,   197,    95,    96,    97,    98,    99,   100,   101,   102,
     103,     0,     0,     0,     0,     0,     0,     0,     0,     0,
     104,     0,     0,     0,   105,   106,   107,   108,   109,   110,
     243,     0,     0,     0,     0,     0,   228,    95,    96,    97,
      98,    99,   100,   101,   102,   103,     0,     0,     0,     0,
       0,     0,     0,     0,     0,   104,     0,     0,     0,   105,
     106,   107,   108,   109,   110,    95,    96,    97,    98,    99,
     100,   101,   102,   103,     0,     0,     0,     0,     0,     0,
       0,     0,     0,   104,     0,     0,     0,   105,   106,   107,
     108,   109,   110,     0,     0,     0,     0,     0,   140,    95,
      96,    97,    98,    99,   100,   101,   102,   103,     0,     0,
     240,     0,     0,     0,     0,     0,     0,   104,     0,     0,
       0,   105,   106,   107,   108,   109,   110,     0,     0,     0,
       0,   241,    95,    96,    97,    98,    99,   100,   101,   102,
     103,     0,     0,     0,     0,     0,     0,     0,     0,     0,
     104,     0,     0,     0,   105,   106,   107,   108,   109,   110,
       0,     0,     0,     0,   202,    95,    96,    97,    98,    99,
     100,   101,   102,   103,     0,     0,   121,     0,     0,     0,
       0,     0,     0,   104,     0,     0,     0,   105,   106,   107,
     108,   109,   110,    95,    96,    97,    98,    99,   100,   101,
     102,   103,     0,     0,   257,     0,     0,     0,     0,     0,
       0,   104,     0,     0,     0,   105,   106,   107,   108,   109,
     110,    95,    96,    97,    98,    99,   100,   101,   102,   103,
       0,     0,     0,     0,     0,     0,     0,     0,     0,   104,
       0,     0,     0,   105,   106,   107,   108,   109,   110
};

static const yytype_int16 yycheck[] =
{
       0,    77,   120,     4,    72,    55,     4,    34,     4,     4,
       4,    34,    56,    35,    14,    15,    59,    56,    62,    20,
      20,    60,     0,    23,    24,    14,     3,     4,     5,    56,
      57,     0,    59,    56,    56,    24,    14,    15,    56,    57,
      59,    59,    20,    20,   112,    23,    15,    43,    43,   167,
      16,    20,    18,    56,    23,     0,   124,    60,    59,    36,
      37,    59,    39,    40,    41,    59,    43,    52,    53,    54,
      47,    71,    56,    57,    59,    52,    52,    53,    54,     5,
     198,   199,    59,    59,    61,    62,     3,     4,     5,    26,
      27,    28,    29,    30,    31,    32,    15,    56,    56,   217,
     218,    60,    60,    20,    23,    42,     4,   183,   184,    46,
      47,    48,    49,    50,    51,    55,    52,    53,    54,    36,
      37,   121,    39,    40,    41,   125,    43,    52,    53,    54,
      47,     3,     4,     5,    59,    52,    52,    53,    54,    52,
      53,    54,    59,   121,    61,    62,    59,   125,    20,    56,
      56,    55,   121,    60,    60,    24,   125,    26,    27,    28,
      29,    30,    31,    32,    36,    37,    56,    39,    40,    41,
      60,    43,    56,    42,     5,    47,    60,    46,    47,    48,
      49,    50,    51,    59,    52,    53,    54,    59,    59,    61,
      42,    59,   192,    56,    32,     4,    48,    49,    50,    51,
     200,    19,   121,   203,    42,   205,   125,    55,    46,    47,
      48,    49,    50,    51,   192,    56,    57,     9,    10,   219,
      53,    54,   200,   192,    45,   203,    59,   205,    52,    53,
      54,   200,     4,     4,   203,    59,   205,   237,   238,    51,
     240,   219,     4,   243,   244,   245,    53,    54,    56,    57,
     219,    56,    59,     4,    56,    60,    60,   257,    60,   237,
     238,    60,   240,     4,     4,   243,   244,   245,   237,   238,
      59,   240,    17,   192,   243,   244,   245,    22,    56,   257,
      25,   200,    60,    59,   203,     4,   205,     4,   257,    34,
      59,    59,    19,     4,    57,    59,    19,    42,    43,    59,
     219,    19,   251,    48,    49,    19,    19,    19,    -1,    19,
      19,    19,    19,    19,    19,   141,    20,    20,   237,   238,
      -1,   240,    -1,    -1,   243,   244,   245,    -1,    -1,    74,
      -1,    -1,    77,    -1,    -1,    -1,    -1,    -1,   257,    -1,
      -1,    86,    -1,    -1,    -1,    -1,    -1,    92,    93,    -1,
      95,    96,    97,    98,    99,   100,   101,   102,   103,   104,
     105,   106,   107,   108,   109,   110,    -1,    -1,   113,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,   122,   123,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,   133,    -1,
       4,    -1,     6,     7,     8,   140,   141,    11,    12,    13,
      14,    15,    -1,    -1,    -1,    -1,    20,    21,    22,    23,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    33,
      -1,    35,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      44,    -1,    -1,    -1,   179,    -1,    -1,   182,   183,   184,
      -1,    -1,    -1,    -1,    -1,    59,    -1,    24,    25,    26,
      27,    28,    29,    30,    31,    32,    -1,   202,    -1,   204,
      -1,    -1,    -1,    -1,   209,    42,    -1,    -1,   213,    46,
      47,    48,    49,    50,    51,    -1,    -1,    17,    -1,    -1,
      -1,    -1,    -1,    60,    24,    25,    26,    27,    28,    29,
      30,    31,    32,    -1,    -1,    -1,   241,    -1,    -1,    -1,
      -1,    -1,    42,    -1,    -1,    -1,    46,    47,    48,    49,
      50,    51,    24,    25,    26,    27,    28,    29,    30,    31,
      32,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      42,    -1,    -1,    -1,    46,    47,    48,    49,    50,    51,
      -1,    -1,    -1,    -1,    -1,    -1,    58,    24,    25,    26,
      27,    28,    29,    30,    31,    32,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    42,    -1,    -1,    -1,    46,
      47,    48,    49,    50,    51,    -1,    -1,    -1,    -1,    -1,
      -1,    58,    24,    25,    26,    27,    28,    29,    30,    31,
      32,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      42,    -1,    -1,    -1,    46,    47,    48,    49,    50,    51,
      -1,    -1,    -1,    -1,    -1,    -1,    58,    24,    25,    26,
      27,    28,    29,    30,    31,    32,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    42,    -1,    -1,    -1,    46,
      47,    48,    49,    50,    51,    -1,    -1,    -1,    -1,    -1,
      -1,    58,    24,    25,    26,    27,    28,    29,    30,    31,
      32,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      42,    -1,    -1,    -1,    46,    47,    48,    49,    50,    51,
      17,    -1,    -1,    -1,    -1,    -1,    58,    24,    25,    26,
      27,    28,    29,    30,    31,    32,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    42,    -1,    -1,    -1,    46,
      47,    48,    49,    50,    51,    24,    25,    26,    27,    28,
      29,    30,    31,    32,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    42,    -1,    -1,    -1,    46,    47,    48,
      49,    50,    51,    -1,    -1,    -1,    -1,    -1,    57,    24,
      25,    26,    27,    28,    29,    30,    31,    32,    -1,    -1,
      35,    -1,    -1,    -1,    -1,    -1,    -1,    42,    -1,    -1,
      -1,    46,    47,    48,    49,    50,    51,    -1,    -1,    -1,
      -1,    56,    24,    25,    26,    27,    28,    29,    30,    31,
      32,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      42,    -1,    -1,    -1,    46,    47,    48,    49,    50,    51,
      -1,    -1,    -1,    -1,    56,    24,    25,    26,    27,    28,
      29,    30,    31,    32,    -1,    -1,    35,    -1,    -1,    -1,
      -1,    -1,    -1,    42,    -1,    -1,    -1,    46,    47,    48,
      49,    50,    51,    24,    25,    26,    27,    28,    29,    30,
      31,    32,    -1,    -1,    35,    -1,    -1,    -1,    -1,    -1,
      -1,    42,    -1,    -1,    -1,    46,    47,    48,    49,    50,
      51,    24,    25,    26,    27,    28,    29,    30,    31,    32,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    42,
      -1,    -1,    -1,    46,    47,    48,    49,    50,    51
};

/* YYSTOS[STATE-NUM] -- The (internal number of the) accessing
   symbol of state STATE-NUM.  */
static const yytype_uint8 yystos[] =
{
       0,     4,     6,     7,     8,    11,    12,    13,    14,    15,
      20,    21,    22,    23,    33,    35,    44,    59,    64,    65,
      66,    69,    70,    71,    72,    73,    74,    75,    77,    79,
      80,    81,    83,    87,    59,    88,    55,    59,    59,     3,
       4,     5,    36,    37,    39,    40,    41,    43,    47,    61,
      69,    78,    81,    82,    83,    86,    69,    77,    81,    65,
      82,     0,    74,    75,     4,    82,    65,     4,    77,    82,
      55,    56,    57,    55,    52,    53,    54,    59,    68,    82,
      89,     5,     5,    82,    82,    82,    52,    62,    82,    84,
      85,    59,    56,    52,    53,    24,    25,    26,    27,    28,
      29,    30,    31,    32,    42,    46,    47,    48,    49,    50,
      51,     4,    57,    52,    53,    19,    60,    55,    53,    54,
      59,    35,    45,    57,    34,    17,     4,    81,    78,    82,
       4,     4,    68,    56,    60,     9,    10,    60,    60,    82,
      57,    56,    62,     4,    43,    67,    82,    82,     4,    82,
      82,    82,    82,    82,    82,    82,    82,    82,    82,    82,
      82,    82,    82,    82,    82,    53,    54,    59,    78,    82,
       4,     4,     4,    67,    65,    82,    82,    78,    65,    52,
      53,    58,    57,    59,    59,    60,    82,    58,    82,    62,
      84,    56,    60,    58,     4,     4,    67,    58,    59,    59,
      60,    19,    56,    35,    16,    18,    76,    82,     4,    57,
      82,    68,    68,    57,     4,    43,    65,    59,    59,    60,
      67,    67,    65,    82,    65,    82,    65,    19,    58,    82,
      60,    60,    82,    19,    67,    67,    65,    60,    60,    19,
      35,    56,    19,    17,    60,    60,    19,    65,    65,    65,
      82,    65,    65,    65,    19,    19,    19,    35,    76,    19,
      19,    65,    19
};

#define yyerrok		(yyerrstatus = 0)
#define yyclearin	(yychar = YYEMPTY)
#define YYEMPTY		(-2)
#define YYEOF		0

#define YYACCEPT	goto yyacceptlab
#define YYABORT		goto yyabortlab
#define YYERROR		goto yyerrorlab


/* Like YYERROR except do call yyerror.  This remains here temporarily
   to ease the transition to the new meaning of YYERROR, for GCC.
   Once GCC version 2 has supplanted version 1, this can go.  */

#define YYFAIL		goto yyerrlab

#define YYRECOVERING()  (!!yyerrstatus)

#define YYBACKUP(Token, Value)					\
do								\
  if (yychar == YYEMPTY && yylen == 1)				\
    {								\
      yychar = (Token);						\
      yylval = (Value);						\
      yytoken = YYTRANSLATE (yychar);				\
      YYPOPSTACK (1);						\
      goto yybackup;						\
    }								\
  else								\
    {								\
      yyerror (YY_("syntax error: cannot back up")); \
      YYERROR;							\
    }								\
while (YYID (0))


#define YYTERROR	1
#define YYERRCODE	256


/* YYLLOC_DEFAULT -- Set CURRENT to span from RHS[1] to RHS[N].
   If N is 0, then set CURRENT to the empty location which ends
   the previous symbol: RHS[0] (always defined).  */

#define YYRHSLOC(Rhs, K) ((Rhs)[K])
#ifndef YYLLOC_DEFAULT
# define YYLLOC_DEFAULT(Current, Rhs, N)				\
    do									\
      if (YYID (N))                                                    \
	{								\
	  (Current).first_line   = YYRHSLOC (Rhs, 1).first_line;	\
	  (Current).first_column = YYRHSLOC (Rhs, 1).first_column;	\
	  (Current).last_line    = YYRHSLOC (Rhs, N).last_line;		\
	  (Current).last_column  = YYRHSLOC (Rhs, N).last_column;	\
	}								\
      else								\
	{								\
	  (Current).first_line   = (Current).last_line   =		\
	    YYRHSLOC (Rhs, 0).last_line;				\
	  (Current).first_column = (Current).last_column =		\
	    YYRHSLOC (Rhs, 0).last_column;				\
	}								\
    while (YYID (0))
#endif


/* YY_LOCATION_PRINT -- Print the location on the stream.
   This macro was not mandated originally: define only if we know
   we won't break user code: when these are the locations we know.  */

#ifndef YY_LOCATION_PRINT
# if defined YYLTYPE_IS_TRIVIAL && YYLTYPE_IS_TRIVIAL
#  define YY_LOCATION_PRINT(File, Loc)			\
     fprintf (File, "%d.%d-%d.%d",			\
	      (Loc).first_line, (Loc).first_column,	\
	      (Loc).last_line,  (Loc).last_column)
# else
#  define YY_LOCATION_PRINT(File, Loc) ((void) 0)
# endif
#endif


/* YYLEX -- calling `yylex' with the right arguments.  */

#ifdef YYLEX_PARAM
# define YYLEX yylex (YYLEX_PARAM)
#else
# define YYLEX yylex ()
#endif

/* Enable debugging if requested.  */
#if YYDEBUG

# ifndef YYFPRINTF
#  include <stdio.h> /* INFRINGES ON USER NAME SPACE */
#  define YYFPRINTF fprintf
# endif

# define YYDPRINTF(Args)			\
do {						\
  if (yydebug)					\
    YYFPRINTF Args;				\
} while (YYID (0))

# define YY_SYMBOL_PRINT(Title, Type, Value, Location)			  \
do {									  \
  if (yydebug)								  \
    {									  \
      YYFPRINTF (stderr, "%s ", Title);					  \
      yy_symbol_print (stderr,						  \
		  Type, Value); \
      YYFPRINTF (stderr, "\n");						  \
    }									  \
} while (YYID (0))


/*--------------------------------.
| Print this symbol on YYOUTPUT.  |
`--------------------------------*/

/*ARGSUSED*/
#if (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
static void
yy_symbol_value_print (FILE *yyoutput, int yytype, YYSTYPE const * const yyvaluep)
#else
static void
yy_symbol_value_print (yyoutput, yytype, yyvaluep)
    FILE *yyoutput;
    int yytype;
    YYSTYPE const * const yyvaluep;
#endif
{
  if (!yyvaluep)
    return;
# ifdef YYPRINT
  if (yytype < YYNTOKENS)
    YYPRINT (yyoutput, yytoknum[yytype], *yyvaluep);
# else
  YYUSE (yyoutput);
# endif
  switch (yytype)
    {
      default:
	break;
    }
}


/*--------------------------------.
| Print this symbol on YYOUTPUT.  |
`--------------------------------*/

#if (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
static void
yy_symbol_print (FILE *yyoutput, int yytype, YYSTYPE const * const yyvaluep)
#else
static void
yy_symbol_print (yyoutput, yytype, yyvaluep)
    FILE *yyoutput;
    int yytype;
    YYSTYPE const * const yyvaluep;
#endif
{
  if (yytype < YYNTOKENS)
    YYFPRINTF (yyoutput, "token %s (", yytname[yytype]);
  else
    YYFPRINTF (yyoutput, "nterm %s (", yytname[yytype]);

  yy_symbol_value_print (yyoutput, yytype, yyvaluep);
  YYFPRINTF (yyoutput, ")");
}

/*------------------------------------------------------------------.
| yy_stack_print -- Print the state stack from its BOTTOM up to its |
| TOP (included).                                                   |
`------------------------------------------------------------------*/

#if (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
static void
yy_stack_print (yytype_int16 *bottom, yytype_int16 *top)
#else
static void
yy_stack_print (bottom, top)
    yytype_int16 *bottom;
    yytype_int16 *top;
#endif
{
  YYFPRINTF (stderr, "Stack now");
  for (; bottom <= top; ++bottom)
    YYFPRINTF (stderr, " %d", *bottom);
  YYFPRINTF (stderr, "\n");
}

# define YY_STACK_PRINT(Bottom, Top)				\
do {								\
  if (yydebug)							\
    yy_stack_print ((Bottom), (Top));				\
} while (YYID (0))


/*------------------------------------------------.
| Report that the YYRULE is going to be reduced.  |
`------------------------------------------------*/

#if (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
static void
yy_reduce_print (YYSTYPE *yyvsp, int yyrule)
#else
static void
yy_reduce_print (yyvsp, yyrule)
    YYSTYPE *yyvsp;
    int yyrule;
#endif
{
  int yynrhs = yyr2[yyrule];
  int yyi;
  unsigned long int yylno = yyrline[yyrule];
  YYFPRINTF (stderr, "Reducing stack by rule %d (line %lu):\n",
	     yyrule - 1, yylno);
  /* The symbols being reduced.  */
  for (yyi = 0; yyi < yynrhs; yyi++)
    {
      fprintf (stderr, "   $%d = ", yyi + 1);
      yy_symbol_print (stderr, yyrhs[yyprhs[yyrule] + yyi],
		       &(yyvsp[(yyi + 1) - (yynrhs)])
		       		       );
      fprintf (stderr, "\n");
    }
}

# define YY_REDUCE_PRINT(Rule)		\
do {					\
  if (yydebug)				\
    yy_reduce_print (yyvsp, Rule); \
} while (YYID (0))

/* Nonzero means print parse trace.  It is left uninitialized so that
   multiple parsers can coexist.  */
int yydebug;
#else /* !YYDEBUG */
# define YYDPRINTF(Args)
# define YY_SYMBOL_PRINT(Title, Type, Value, Location)
# define YY_STACK_PRINT(Bottom, Top)
# define YY_REDUCE_PRINT(Rule)
#endif /* !YYDEBUG */


/* YYINITDEPTH -- initial size of the parser's stacks.  */
#ifndef	YYINITDEPTH
# define YYINITDEPTH 200
#endif

/* YYMAXDEPTH -- maximum size the stacks can grow to (effective only
   if the built-in stack extension method is used).

   Do not make this value too large; the results are undefined if
   YYSTACK_ALLOC_MAXIMUM < YYSTACK_BYTES (YYMAXDEPTH)
   evaluated with infinite-precision integer arithmetic.  */

#ifndef YYMAXDEPTH
# define YYMAXDEPTH 10000
#endif



#if YYERROR_VERBOSE

# ifndef yystrlen
#  if defined __GLIBC__ && defined _STRING_H
#   define yystrlen strlen
#  else
/* Return the length of YYSTR.  */
#if (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
static YYSIZE_T
yystrlen (const char *yystr)
#else
static YYSIZE_T
yystrlen (yystr)
    const char *yystr;
#endif
{
  YYSIZE_T yylen;
  for (yylen = 0; yystr[yylen]; yylen++)
    continue;
  return yylen;
}
#  endif
# endif

# ifndef yystpcpy
#  if defined __GLIBC__ && defined _STRING_H && defined _GNU_SOURCE
#   define yystpcpy stpcpy
#  else
/* Copy YYSRC to YYDEST, returning the address of the terminating '\0' in
   YYDEST.  */
#if (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
static char *
yystpcpy (char *yydest, const char *yysrc)
#else
static char *
yystpcpy (yydest, yysrc)
    char *yydest;
    const char *yysrc;
#endif
{
  char *yyd = yydest;
  const char *yys = yysrc;

  while ((*yyd++ = *yys++) != '\0')
    continue;

  return yyd - 1;
}
#  endif
# endif

# ifndef yytnamerr
/* Copy to YYRES the contents of YYSTR after stripping away unnecessary
   quotes and backslashes, so that it's suitable for yyerror.  The
   heuristic is that double-quoting is unnecessary unless the string
   contains an apostrophe, a comma, or backslash (other than
   backslash-backslash).  YYSTR is taken from yytname.  If YYRES is
   null, do not copy; instead, return the length of what the result
   would have been.  */
static YYSIZE_T
yytnamerr (char *yyres, const char *yystr)
{
  if (*yystr == '"')
    {
      YYSIZE_T yyn = 0;
      char const *yyp = yystr;

      for (;;)
	switch (*++yyp)
	  {
	  case '\'':
	  case ',':
	    goto do_not_strip_quotes;

	  case '\\':
	    if (*++yyp != '\\')
	      goto do_not_strip_quotes;
	    /* Fall through.  */
	  default:
	    if (yyres)
	      yyres[yyn] = *yyp;
	    yyn++;
	    break;

	  case '"':
	    if (yyres)
	      yyres[yyn] = '\0';
	    return yyn;
	  }
    do_not_strip_quotes: ;
    }

  if (! yyres)
    return yystrlen (yystr);

  return yystpcpy (yyres, yystr) - yyres;
}
# endif

/* Copy into YYRESULT an error message about the unexpected token
   YYCHAR while in state YYSTATE.  Return the number of bytes copied,
   including the terminating null byte.  If YYRESULT is null, do not
   copy anything; just return the number of bytes that would be
   copied.  As a special case, return 0 if an ordinary "syntax error"
   message will do.  Return YYSIZE_MAXIMUM if overflow occurs during
   size calculation.  */
static YYSIZE_T
yysyntax_error (char *yyresult, int yystate, int yychar)
{
  int yyn = yypact[yystate];

  if (! (YYPACT_NINF < yyn && yyn <= YYLAST))
    return 0;
  else
    {
      int yytype = YYTRANSLATE (yychar);
      YYSIZE_T yysize0 = yytnamerr (0, yytname[yytype]);
      YYSIZE_T yysize = yysize0;
      YYSIZE_T yysize1;
      int yysize_overflow = 0;
      enum { YYERROR_VERBOSE_ARGS_MAXIMUM = 5 };
      char const *yyarg[YYERROR_VERBOSE_ARGS_MAXIMUM];
      int yyx;

# if 0
      /* This is so xgettext sees the translatable formats that are
	 constructed on the fly.  */
      YY_("syntax error, unexpected %s");
      YY_("syntax error, unexpected %s, expecting %s");
      YY_("syntax error, unexpected %s, expecting %s or %s");
      YY_("syntax error, unexpected %s, expecting %s or %s or %s");
      YY_("syntax error, unexpected %s, expecting %s or %s or %s or %s");
# endif
      char *yyfmt;
      char const *yyf;
      static char const yyunexpected[] = "syntax error, unexpected %s";
      static char const yyexpecting[] = ", expecting %s";
      static char const yyor[] = " or %s";
      char yyformat[sizeof yyunexpected
		    + sizeof yyexpecting - 1
		    + ((YYERROR_VERBOSE_ARGS_MAXIMUM - 2)
		       * (sizeof yyor - 1))];
      char const *yyprefix = yyexpecting;

      /* Start YYX at -YYN if negative to avoid negative indexes in
	 YYCHECK.  */
      int yyxbegin = yyn < 0 ? -yyn : 0;

      /* Stay within bounds of both yycheck and yytname.  */
      int yychecklim = YYLAST - yyn + 1;
      int yyxend = yychecklim < YYNTOKENS ? yychecklim : YYNTOKENS;
      int yycount = 1;

      yyarg[0] = yytname[yytype];
      yyfmt = yystpcpy (yyformat, yyunexpected);

      for (yyx = yyxbegin; yyx < yyxend; ++yyx)
	if (yycheck[yyx + yyn] == yyx && yyx != YYTERROR)
	  {
	    if (yycount == YYERROR_VERBOSE_ARGS_MAXIMUM)
	      {
		yycount = 1;
		yysize = yysize0;
		yyformat[sizeof yyunexpected - 1] = '\0';
		break;
	      }
	    yyarg[yycount++] = yytname[yyx];
	    yysize1 = yysize + yytnamerr (0, yytname[yyx]);
	    yysize_overflow |= (yysize1 < yysize);
	    yysize = yysize1;
	    yyfmt = yystpcpy (yyfmt, yyprefix);
	    yyprefix = yyor;
	  }

      yyf = YY_(yyformat);
      yysize1 = yysize + yystrlen (yyf);
      yysize_overflow |= (yysize1 < yysize);
      yysize = yysize1;

      if (yysize_overflow)
	return YYSIZE_MAXIMUM;

      if (yyresult)
	{
	  /* Avoid sprintf, as that infringes on the user's name space.
	     Don't have undefined behavior even if the translation
	     produced a string with the wrong number of "%s"s.  */
	  char *yyp = yyresult;
	  int yyi = 0;
	  while ((*yyp = *yyf) != '\0')
	    {
	      if (*yyp == '%' && yyf[1] == 's' && yyi < yycount)
		{
		  yyp += yytnamerr (yyp, yyarg[yyi++]);
		  yyf += 2;
		}
	      else
		{
		  yyp++;
		  yyf++;
		}
	    }
	}
      return yysize;
    }
}
#endif /* YYERROR_VERBOSE */


/*-----------------------------------------------.
| Release the memory associated to this symbol.  |
`-----------------------------------------------*/

/*ARGSUSED*/
#if (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
static void
yydestruct (const char *yymsg, int yytype, YYSTYPE *yyvaluep)
#else
static void
yydestruct (yymsg, yytype, yyvaluep)
    const char *yymsg;
    int yytype;
    YYSTYPE *yyvaluep;
#endif
{
  YYUSE (yyvaluep);

  if (!yymsg)
    yymsg = "Deleting";
  YY_SYMBOL_PRINT (yymsg, yytype, yyvaluep, yylocationp);

  switch (yytype)
    {

      default:
	break;
    }
}


/* Prevent warnings from -Wmissing-prototypes.  */

#ifdef YYPARSE_PARAM
#if defined __STDC__ || defined __cplusplus
int yyparse (void *YYPARSE_PARAM);
#else
int yyparse ();
#endif
#else /* ! YYPARSE_PARAM */
#if defined __STDC__ || defined __cplusplus
int yyparse (void);
#else
int yyparse ();
#endif
#endif /* ! YYPARSE_PARAM */



/* The look-ahead symbol.  */
int yychar;

/* The semantic value of the look-ahead symbol.  */
YYSTYPE yylval;

/* Number of syntax errors so far.  */
int yynerrs;



/*----------.
| yyparse.  |
`----------*/

#ifdef YYPARSE_PARAM
#if (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
int
yyparse (void *YYPARSE_PARAM)
#else
int
yyparse (YYPARSE_PARAM)
    void *YYPARSE_PARAM;
#endif
#else /* ! YYPARSE_PARAM */
#if (defined __STDC__ || defined __C99__FUNC__ \
     || defined __cplusplus || defined _MSC_VER)
int
yyparse (void)
#else
int
yyparse ()

#endif
#endif
{
  
  int yystate;
  int yyn;
  int yyresult;
  /* Number of tokens to shift before error messages enabled.  */
  int yyerrstatus;
  /* Look-ahead token as an internal (translated) token number.  */
  int yytoken = 0;
#if YYERROR_VERBOSE
  /* Buffer for error messages, and its allocated size.  */
  char yymsgbuf[128];
  char *yymsg = yymsgbuf;
  YYSIZE_T yymsg_alloc = sizeof yymsgbuf;
#endif

  /* Three stacks and their tools:
     `yyss': related to states,
     `yyvs': related to semantic values,
     `yyls': related to locations.

     Refer to the stacks thru separate pointers, to allow yyoverflow
     to reallocate them elsewhere.  */

  /* The state stack.  */
  yytype_int16 yyssa[YYINITDEPTH];
  yytype_int16 *yyss = yyssa;
  yytype_int16 *yyssp;

  /* The semantic value stack.  */
  YYSTYPE yyvsa[YYINITDEPTH];
  YYSTYPE *yyvs = yyvsa;
  YYSTYPE *yyvsp;



#define YYPOPSTACK(N)   (yyvsp -= (N), yyssp -= (N))

  YYSIZE_T yystacksize = YYINITDEPTH;

  /* The variables used to return semantic value and location from the
     action routines.  */
  YYSTYPE yyval;


  /* The number of symbols on the RHS of the reduced rule.
     Keep to zero when no symbol should be popped.  */
  int yylen = 0;

  YYDPRINTF ((stderr, "Starting parse\n"));

  yystate = 0;
  yyerrstatus = 0;
  yynerrs = 0;
  yychar = YYEMPTY;		/* Cause a token to be read.  */

  /* Initialize stack pointers.
     Waste one element of value and location stack
     so that they stay on the same level as the state stack.
     The wasted elements are never initialized.  */

  yyssp = yyss;
  yyvsp = yyvs;

  goto yysetstate;

/*------------------------------------------------------------.
| yynewstate -- Push a new state, which is found in yystate.  |
`------------------------------------------------------------*/
 yynewstate:
  /* In all cases, when you get here, the value and location stacks
     have just been pushed.  So pushing a state here evens the stacks.  */
  yyssp++;

 yysetstate:
  *yyssp = yystate;

  if (yyss + yystacksize - 1 <= yyssp)
    {
      /* Get the current used size of the three stacks, in elements.  */
      YYSIZE_T yysize = yyssp - yyss + 1;

#ifdef yyoverflow
      {
	/* Give user a chance to reallocate the stack.  Use copies of
	   these so that the &'s don't force the real ones into
	   memory.  */
	YYSTYPE *yyvs1 = yyvs;
	yytype_int16 *yyss1 = yyss;


	/* Each stack pointer address is followed by the size of the
	   data in use in that stack, in bytes.  This used to be a
	   conditional around just the two extra args, but that might
	   be undefined if yyoverflow is a macro.  */
	yyoverflow (YY_("memory exhausted"),
		    &yyss1, yysize * sizeof (*yyssp),
		    &yyvs1, yysize * sizeof (*yyvsp),

		    &yystacksize);

	yyss = yyss1;
	yyvs = yyvs1;
      }
#else /* no yyoverflow */
# ifndef YYSTACK_RELOCATE
      goto yyexhaustedlab;
# else
      /* Extend the stack our own way.  */
      if (YYMAXDEPTH <= yystacksize)
	goto yyexhaustedlab;
      yystacksize *= 2;
      if (YYMAXDEPTH < yystacksize)
	yystacksize = YYMAXDEPTH;

      {
	yytype_int16 *yyss1 = yyss;
	union yyalloc *yyptr =
	  (union yyalloc *) YYSTACK_ALLOC (YYSTACK_BYTES (yystacksize));
	if (! yyptr)
	  goto yyexhaustedlab;
	YYSTACK_RELOCATE (yyss);
	YYSTACK_RELOCATE (yyvs);

#  undef YYSTACK_RELOCATE
	if (yyss1 != yyssa)
	  YYSTACK_FREE (yyss1);
      }
# endif
#endif /* no yyoverflow */

      yyssp = yyss + yysize - 1;
      yyvsp = yyvs + yysize - 1;


      YYDPRINTF ((stderr, "Stack size increased to %lu\n",
		  (unsigned long int) yystacksize));

      if (yyss + yystacksize - 1 <= yyssp)
	YYABORT;
    }

  YYDPRINTF ((stderr, "Entering state %d\n", yystate));

  goto yybackup;

/*-----------.
| yybackup.  |
`-----------*/
yybackup:

  /* Do appropriate processing given the current state.  Read a
     look-ahead token if we need one and don't already have one.  */

  /* First try to decide what to do without reference to look-ahead token.  */
  yyn = yypact[yystate];
  if (yyn == YYPACT_NINF)
    goto yydefault;

  /* Not known => get a look-ahead token if don't already have one.  */

  /* YYCHAR is either YYEMPTY or YYEOF or a valid look-ahead symbol.  */
  if (yychar == YYEMPTY)
    {
      YYDPRINTF ((stderr, "Reading a token: "));
      yychar = YYLEX;
    }

  if (yychar <= YYEOF)
    {
      yychar = yytoken = YYEOF;
      YYDPRINTF ((stderr, "Now at end of input.\n"));
    }
  else
    {
      yytoken = YYTRANSLATE (yychar);
      YY_SYMBOL_PRINT ("Next token is", yytoken, &yylval, &yylloc);
    }

  /* If the proper action on seeing token YYTOKEN is to reduce or to
     detect an error, take that action.  */
  yyn += yytoken;
  if (yyn < 0 || YYLAST < yyn || yycheck[yyn] != yytoken)
    goto yydefault;
  yyn = yytable[yyn];
  if (yyn <= 0)
    {
      if (yyn == 0 || yyn == YYTABLE_NINF)
	goto yyerrlab;
      yyn = -yyn;
      goto yyreduce;
    }

  if (yyn == YYFINAL)
    YYACCEPT;

  /* Count tokens shifted since error; after three, turn off error
     status.  */
  if (yyerrstatus)
    yyerrstatus--;

  /* Shift the look-ahead token.  */
  YY_SYMBOL_PRINT ("Shifting", yytoken, &yylval, &yylloc);

  /* Discard the shifted token unless it is eof.  */
  if (yychar != YYEOF)
    yychar = YYEMPTY;

  yystate = yyn;
  *++yyvsp = yylval;

  goto yynewstate;


/*-----------------------------------------------------------.
| yydefault -- do the default action for the current state.  |
`-----------------------------------------------------------*/
yydefault:
  yyn = yydefact[yystate];
  if (yyn == 0)
    goto yyerrlab;
  goto yyreduce;


/*-----------------------------.
| yyreduce -- Do a reduction.  |
`-----------------------------*/
yyreduce:
  /* yyn is the number of a rule to reduce with.  */
  yylen = yyr2[yyn];

  /* If YYLEN is nonzero, implement the default value of the action:
     `$$ = $1'.

     Otherwise, the following line sets YYVAL to garbage.
     This behavior is undocumented and Bison
     users should not rely upon it.  Assigning to YYVAL
     unconditionally makes the parser a bit smaller, and it avoids a
     GCC warning that YYVAL may be used uninitialized.  */
  yyval = yyvsp[1-yylen];


  YY_REDUCE_PRINT (yyn);
  switch (yyn)
    {
        case 2:
#line 72 "parser.y"
    {
        root_node = (yyvsp[(1) - (1)].ast_node); // Captures the entire AST root for main.c to use later
    ;}
    break;

  case 3:
#line 78 "parser.y"
    { (yyval.ast_node) = NULL; ;}
    break;

  case 4:
#line 79 "parser.y"
    { (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node); ;}
    break;

  case 5:
#line 80 "parser.y"
    {
        if ((yyvsp[(1) - (2)].ast_node) == NULL) { 
            (yyval.ast_node) = (yyvsp[(2) - (2)].ast_node); 
        } else {
            ASTNode *current = (yyvsp[(1) - (2)].ast_node);
            while (current->next != NULL) {
                current = current->next;
            }
            current->next = (yyvsp[(2) - (2)].ast_node);
            (yyval.ast_node) = (yyvsp[(1) - (2)].ast_node);
        }
    ;}
    break;

  case 6:
#line 92 "parser.y"
    { (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node); ;}
    break;

  case 7:
#line 96 "parser.y"
    { (yyval.ast_node) = (yyvsp[(1) - (2)].ast_node); ;}
    break;

  case 8:
#line 97 "parser.y"
    {
        if ((yyvsp[(1) - (3)].ast_node) == NULL) {
            (yyval.ast_node) = (yyvsp[(2) - (3)].ast_node);
        } else {
            ASTNode *current = (yyvsp[(1) - (3)].ast_node);
            while (current->next != NULL) {
                current = current->next;
            }
            current->next = (yyvsp[(2) - (3)].ast_node);
            (yyval.ast_node) = (yyvsp[(1) - (3)].ast_node);
        }
    ;}
    break;

  case 9:
#line 109 "parser.y"
    { (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node); ;}
    break;

  case 10:
#line 110 "parser.y"
    {
        if ((yyvsp[(1) - (2)].ast_node) == NULL) { 
            (yyval.ast_node) = (yyvsp[(2) - (2)].ast_node); 
        } else {
            ASTNode *current = (yyvsp[(1) - (2)].ast_node);
            while (current->next != NULL) {
                current = current->next;
            }
            current->next = (yyvsp[(2) - (2)].ast_node);
            (yyval.ast_node) = (yyvsp[(1) - (2)].ast_node);
        }
    ;}
    break;

  case 11:
#line 125 "parser.y"
    {
        (yyval.ast_node) = NULL;
    ;}
    break;

  case 12:
#line 128 "parser.y"
    {
        (yyval.ast_node) = make_node_ident((yyvsp[(1) - (1)].string_val));
    ;}
    break;

  case 13:
#line 131 "parser.y"
    {
        // Create a marker identifier - will be detected in function_def
        (yyval.ast_node) = make_node_ident("...");
    ;}
    break;

  case 14:
#line 135 "parser.y"
    {
        ASTNode* new_node = make_node_ident((yyvsp[(3) - (3)].string_val));
        ASTNode* current = (yyvsp[(1) - (3)].ast_node);
        while(current->next) current = current->next;
        current->next = new_node;
        (yyval.ast_node) = (yyvsp[(1) - (3)].ast_node);
    ;}
    break;

  case 15:
#line 142 "parser.y"
    {
        ASTNode* new_node = make_node_ident("...");
        ASTNode* current = (yyvsp[(1) - (3)].ast_node);
        while(current->next) current = current->next;
        current->next = new_node;
        (yyval.ast_node) = (yyvsp[(1) - (3)].ast_node);
    ;}
    break;

  case 16:
#line 152 "parser.y"
    { 
        (yyval.ast_node) = NULL;
    ;}
    break;

  case 17:
#line 155 "parser.y"
    { 
        (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node);
    ;}
    break;

  case 18:
#line 158 "parser.y"
    {
        // Chain the new expression to the end of the argument list
        ASTNode* current = (yyvsp[(1) - (3)].ast_node);
        while (current->next != NULL) {
            current = current->next;
        }
        current->next = (yyvsp[(3) - (3)].ast_node);
        (yyval.ast_node) = (yyvsp[(1) - (3)].ast_node);
    ;}
    break;

  case 19:
#line 171 "parser.y"
    { (yyval.ast_node) = make_node(NODE_FUNCTION_DEF); ;}
    break;

  case 20:
#line 175 "parser.y"
    { (yyval.ast_node) = make_node(NODE_WHILE); ;}
    break;

  case 21:
#line 179 "parser.y"
    { (yyval.ast_node) = make_node(NODE_REPEAT); ;}
    break;

  case 22:
#line 183 "parser.y"
    { (yyval.ast_node) = make_node(NODE_FOR_NUMERIC); ;}
    break;

  case 23:
#line 186 "parser.y"
    { (yyval.ast_node) = make_node(NODE_IF); ;}
    break;

  case 24:
#line 190 "parser.y"
    { (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node); ;}
    break;

  case 25:
#line 191 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_MULTIPLE_ASSIGNMENT);
        (yyval.ast_node)->as.mult_assign.targets_head = (yyvsp[(1) - (3)].ast_node);
        (yyval.ast_node)->as.mult_assign.values_head = (yyvsp[(3) - (3)].ast_node);
        (yyval.ast_node)->as.mult_assign.is_local = 0;
    ;}
    break;

  case 26:
#line 197 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_MULTIPLE_ASSIGNMENT);
        (yyval.ast_node)->as.mult_assign.targets_head = (yyvsp[(2) - (4)].ast_node);
        (yyval.ast_node)->as.mult_assign.values_head = (yyvsp[(4) - (4)].ast_node);
        (yyval.ast_node)->as.mult_assign.is_local = 1;
    ;}
    break;

  case 27:
#line 204 "parser.y"
    { 
        // $1 = table, $3 = key, $6 = value being assigned
        (yyval.ast_node) = make_node_table_set ((yyvsp[(1) - (6)].ast_node), (yyvsp[(3) - (6)].ast_node), (yyvsp[(6) - (6)].ast_node)); 
    ;}
    break;

  case 28:
#line 209 "parser.y"
    {
        ASTNode *string_key  = make_node_string ((yyvsp[(3) - (5)].string_val));
        (yyval.ast_node)                   = make_node_table_set ((yyvsp[(1) - (5)].ast_node), string_key, (yyvsp[(5) - (5)].ast_node));
    ;}
    break;

  case 29:
#line 213 "parser.y"
    {
        (yyval.ast_node) = (yyvsp[(1) - (5)].ast_node);
        (yyval.ast_node)->as.while_loop.condition = (yyvsp[(2) - (5)].ast_node);
        (yyval.ast_node)->as.while_loop.body = (yyvsp[(4) - (5)].ast_node);
    ;}
    break;

  case 30:
#line 218 "parser.y"
    {
        // Note the order: body ($2) is parsed BEFORE the until-condition
        // ($4) -- this matters for scoping. Lua's grammar for repeat/until
        // deliberately puts the condition after the body's closing so
        // that locals declared in the body are still in scope for it.
        // node_repeat() in the compiler mirrors this by NOT popping the
        // body's scope until after the condition has been generated.
        (yyval.ast_node) = (yyvsp[(1) - (4)].ast_node);
        (yyval.ast_node)->as.repeat_loop.body      = (yyvsp[(2) - (4)].ast_node);
        (yyval.ast_node)->as.repeat_loop.condition = (yyvsp[(4) - (4)].ast_node);
    ;}
    break;

  case 31:
#line 229 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_FOR_NUMERIC);
        (yyval.ast_node)->as.for_numeric.index_name  = (yyvsp[(2) - (9)].string_val);
        (yyval.ast_node)->as.for_numeric.start_expr  = (yyvsp[(4) - (9)].ast_node);
        (yyval.ast_node)->as.for_numeric.stop_expr   = (yyvsp[(6) - (9)].ast_node);
        (yyval.ast_node)->as.for_numeric.step_expr   = NULL; // Omitted step
        (yyval.ast_node)->as.for_numeric.body        = (yyvsp[(8) - (9)].ast_node);
    ;}
    break;

  case 32:
#line 237 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_FOR_NUMERIC);
        (yyval.ast_node)->as.for_numeric.index_name  = (yyvsp[(2) - (11)].string_val);
        (yyval.ast_node)->as.for_numeric.start_expr  = (yyvsp[(4) - (11)].ast_node);
        (yyval.ast_node)->as.for_numeric.stop_expr   = (yyvsp[(6) - (11)].ast_node);
        (yyval.ast_node)->as.for_numeric.step_expr   = (yyvsp[(8) - (11)].ast_node);  // Explicit step
        (yyval.ast_node)->as.for_numeric.body        = (yyvsp[(10) - (11)].ast_node);
    ;}
    break;

  case 33:
#line 245 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_FOR_GENERIC);
        (yyval.ast_node)->as.for_generic.var_list    = (yyvsp[(2) - (7)].ast_node);
        (yyval.ast_node)->as.for_generic.iter_expr   = (yyvsp[(4) - (7)].ast_node);
        (yyval.ast_node)->as.for_generic.body        = (yyvsp[(6) - (7)].ast_node);
    ;}
    break;

  case 34:
#line 251 "parser.y"
    { 
        (yyval.ast_node)                             = (yyvsp[(1) - (6)].ast_node);
        (yyval.ast_node) -> as.if_stmt.condition     = (yyvsp[(2) - (6)].ast_node);
        (yyval.ast_node) -> as.if_stmt.if_body       = (yyvsp[(4) - (6)].ast_node);
        (yyval.ast_node) -> as.if_stmt.else_body     = (yyvsp[(5) - (6)].ast_node);
    ;}
    break;

  case 35:
#line 257 "parser.y"
    {
        // Bare scoping block: no condition, no loop tracking -- just gives
        // the enclosed statements their own lexical scope. Most useful for
        // deliberately ending a 'local' declaration's shadow before the
        // rest of the enclosing block, without needing an 'if true then'
        // workaround.
        (yyval.ast_node) = make_node_do_block ((yyvsp[(2) - (3)].ast_node));
    ;}
    break;

  case 36:
#line 265 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_MULTIPLE_ASSIGNMENT);
        (yyval.ast_node)->as.mult_assign.is_local = 1;
        (yyval.ast_node)->as.mult_assign.targets_head = (yyvsp[(2) - (2)].ast_node);
        (yyval.ast_node)->as.mult_assign.values_head = NULL; 
    ;}
    break;

  case 37:
#line 271 "parser.y"
    { (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node); ;}
    break;

  case 38:
#line 272 "parser.y"
    { 
        (yyval.ast_node) = make_node(NODE_ASM);
        (yyval.ast_node)->as.inline_asm.code = (yyvsp[(3) - (4)].string_val);
    ;}
    break;

  case 39:
#line 277 "parser.y"
    {
        // local function myfunc(...) ... end
        // This is equivalent to: local myfunc = function(...) ... end

                // 1. Get the pre-allocated function_def node from func_start
        ASTNode* func_def = (yyvsp[(2) - (8)].ast_node);
        func_def->as.function_def.name = strdup((yyvsp[(3) - (8)].string_val));
        func_def->as.function_def.params = (yyvsp[(5) - (8)].ast_node);
        func_def->as.function_def.body = (yyvsp[(7) - (8)].ast_node);

        // 2. Initialize and check variadic status
        func_def->as.function_def.is_variadic = 0;
        ASTNode *p = (yyvsp[(5) - (8)].ast_node);
        while (p != NULL) {
            if (p->type == NODE_IDENTIFIER && strcmp(p->as.id.name, "...") == 0) {
                func_def->as.function_def.is_variadic = 1;
                break;
            }
            p = p->next;
        }

        // ✅ SILENTLY IGNORE 'local': Just return the function_def node directly
        // (No assignment node created, no is_local flag set)
        (yyval.ast_node) = func_def;

        /* until we pursue actual local functions, comment this out
        // 1. Get the pre-allocated function_def node from func_start
        ASTNode* func_def = $2;
        func_def->as.function_def.name = strdup($3);
        func_def->as.function_def.params = $5;
        func_def->as.function_def.body = $7;

        // 2. Initialize and check variadic status for local functions
        func_def->as.function_def.is_variadic = 0;
        ASTNode *p = $5;
        while (p != NULL) {
            if (p->type == NODE_IDENTIFIER && strcmp(p->as.id.name, "...") == 0) {
                func_def->as.function_def.is_variadic = 1;
                break;
            }
            p = p->next;
        }

        // 3. Create function pointer node
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup($3);

        // 4. Create local assignment: local myfunc = func_ptr
        ASTNode* assign = make_node(NODE_MULTIPLE_ASSIGNMENT);
        assign->as.mult_assign.targets_head = make_node_ident($3);
        assign->as.mult_assign.values_head = func_ptr;
        assign->as.mult_assign.is_local = 1;  // THIS IS THE KEY DIFFERENCE

        // 5. Chain them: func_def -> assign
        func_def->next = assign;
        $$ = func_def;*/
    ;}
    break;

  case 40:
#line 335 "parser.y"
    {
        // local function obj:method(...) ... end
        //
        // Not standard Lua (real Lua's "local function" only accepts a
        // plain Name), but supported here as a project extension so the
        // colon-method sugar works under 'local' too. Semantically this
        // is identical to "function obj:method(...) ... end" -- the
        // 'local' keyword is silently ignored, exactly like the existing
        // "local function NAME(...)" rule above does.

        // 1. Mangle "obj" + "add_multiple" -> "obj_add_multiple"
        char* mangled_name = mangle_method_name((yyvsp[(3) - (10)].string_val), (yyvsp[(5) - (10)].string_val));

        // 2. Inject "self" as the first parameter (colon-call convention)
        ASTNode* self_param = make_node_ident("self");
        self_param->next = (yyvsp[(7) - (10)].ast_node); // link to the rest of the declared parameters

        // 3. Build the function definition using the pre-allocated node
        ASTNode* func_def = (yyvsp[(2) - (10)].ast_node);
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = self_param;
        func_def->as.function_def.body = (yyvsp[(9) - (10)].ast_node);
        func_def->as.function_def.is_variadic = 0;

        // 4. Build a function-pointer node targeting the mangled label
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        // 5. Tie it into a table assignment: obj["add_multiple"] = func_ptr
        ASTNode* key_node   = make_node_string((yyvsp[(5) - (10)].string_val));
        ASTNode* table_node = make_node_ident((yyvsp[(3) - (10)].string_val));

        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key        = key_node;
        table_set->as.table_set.value      = func_ptr;

        // 6. Chain: func_def -> table_set, same pattern as every other
        // method-desugaring rule in this grammar
        func_def->next = table_set;
        (yyval.ast_node) = func_def;
    ;}
    break;

  case 41:
#line 378 "parser.y"
    {
        // local function obj.method(...) ... end
        //
        // Dot form: unlike the colon form above, NO implicit 'self' is
        // injected here -- this mirrors the existing non-local dot-rule
        // in function_def: below. If the body needs self, the author
        // writes it as an explicit first parameter, same as real Lua.

        char* mangled_name = mangle_method_name((yyvsp[(3) - (10)].string_val), (yyvsp[(5) - (10)].string_val));

        ASTNode* func_def = (yyvsp[(2) - (10)].ast_node);
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = (yyvsp[(7) - (10)].ast_node);
        func_def->as.function_def.body = (yyvsp[(9) - (10)].ast_node);
        func_def->as.function_def.is_variadic = 0;

        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        ASTNode* key_node   = make_node_string((yyvsp[(5) - (10)].string_val));
        ASTNode* table_node = make_node_ident((yyvsp[(3) - (10)].string_val));

        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key        = key_node;
        table_set->as.table_set.value      = func_ptr;

        func_def->next = table_set;
        (yyval.ast_node) = func_def;
    ;}
    break;

  case 42:
#line 408 "parser.y"
    { 
        (yyval.ast_node) = make_node(NODE_RAWASM);
        (yyval.ast_node)->as.inline_asm.code = (yyvsp[(3) - (4)].string_val);
    ;}
    break;

  case 43:
#line 412 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_COMMENT_LINE);
        (yyval.ast_node)->as.string_val.value = (yyvsp[(1) - (1)].string_val);
    ;}
    break;

  case 44:
#line 416 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_COMMENT_BLOCK);
        (yyval.ast_node)->as.string_val.value = (yyvsp[(1) - (1)].string_val);
    ;}
    break;

  case 45:
#line 420 "parser.y"
    { (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node); ;}
    break;

  case 46:
#line 421 "parser.y"
    {
        (yyval.ast_node) = make_node_cart_hint((yyvsp[(1) - (1)].string_val));
    ;}
    break;

  case 47:
#line 427 "parser.y"
    { (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node); ;}
    break;

  case 48:
#line 428 "parser.y"
    { (yyval.ast_node) = (yyvsp[(1) - (2)].ast_node); ;}
    break;

  case 49:
#line 429 "parser.y"
    { (yyval.ast_node) = make_node(NODE_BREAK); ;}
    break;

  case 50:
#line 430 "parser.y"
    { (yyval.ast_node) = make_node(NODE_BREAK); ;}
    break;

  case 51:
#line 434 "parser.y"
    { (yyval.ast_node)  = NULL; ;}
    break;

  case 52:
#line 435 "parser.y"
    { (yyval.ast_node)  = (yyvsp[(2) - (2)].ast_node); ;}
    break;

  case 53:
#line 437 "parser.y"
    {
        // Treat elseif exactly like a nested IF statement assigned to the else_body
        (yyval.ast_node)                             = make_node(NODE_IF);
        (yyval.ast_node) -> as.if_stmt.condition     = (yyvsp[(2) - (5)].ast_node);
        (yyval.ast_node) -> as.if_stmt.if_body       = (yyvsp[(4) - (5)].ast_node);
        (yyval.ast_node) -> as.if_stmt.else_body     = (yyvsp[(5) - (5)].ast_node);
    ;}
    break;

  case 54:
#line 448 "parser.y"
    {
        (yyval.ast_node) = make_node_ident((yyvsp[(1) - (1)].string_val));
    ;}
    break;

  case 55:
#line 451 "parser.y"
    {
        ASTNode *string_key = make_node_string ((yyvsp[(3) - (3)].string_val));
        (yyval.ast_node) = make_node_table_get ((yyvsp[(1) - (3)].ast_node), string_key);
    ;}
    break;

  case 56:
#line 455 "parser.y"
    {
        (yyval.ast_node) = make_node_table_get ((yyvsp[(1) - (4)].ast_node), (yyvsp[(3) - (4)].ast_node));
    ;}
    break;

  case 57:
#line 458 "parser.y"
    {
        ASTNode* new_ident = make_node_ident((yyvsp[(3) - (3)].string_val));
        ASTNode* curr = (yyvsp[(1) - (3)].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = new_ident;
        (yyval.ast_node) = (yyvsp[(1) - (3)].ast_node);
    ;}
    break;

  case 58:
#line 465 "parser.y"
    {
        ASTNode *string_key = make_node_string ((yyvsp[(5) - (5)].string_val));
        ASTNode *new_target = make_node_table_get ((yyvsp[(3) - (5)].ast_node), string_key);
        ASTNode* curr = (yyvsp[(1) - (5)].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = new_target;
        (yyval.ast_node) = (yyvsp[(1) - (5)].ast_node);
    ;}
    break;

  case 59:
#line 473 "parser.y"
    {
        ASTNode *new_target = make_node_table_get ((yyvsp[(3) - (6)].ast_node), (yyvsp[(5) - (6)].ast_node));
        ASTNode* curr = (yyvsp[(1) - (6)].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = new_target;
        (yyval.ast_node) = (yyvsp[(1) - (6)].ast_node);
    ;}
    break;

  case 60:
#line 483 "parser.y"
    { 
        (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node); 
    ;}
    break;

  case 61:
#line 486 "parser.y"
    { 
        ASTNode* curr = (yyvsp[(1) - (3)].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = (yyvsp[(3) - (3)].ast_node);
        (yyval.ast_node) = (yyvsp[(1) - (3)].ast_node); 
    ;}
    break;

  case 62:
#line 496 "parser.y"
    {
        // 1. Build the structural function definition using pre-allocated node
        ASTNode* func_def = (yyvsp[(1) - (7)].ast_node);
        func_def->as.function_def.name = strdup((yyvsp[(2) - (7)].string_val));
        func_def->as.function_def.params = (yyvsp[(4) - (7)].ast_node);
        func_def->as.function_def.body = (yyvsp[(6) - (7)].ast_node);

        // NEW: Check if parameter_list contains "..."
        func_def->as.function_def.is_variadic = 0;
        ASTNode *p = (yyvsp[(4) - (7)].ast_node);
        while (p != NULL) {
            if (p->type == NODE_IDENTIFIER && strcmp(p->as.id.name, "...") == 0) {
                func_def->as.function_def.is_variadic = 1;
                break;
            }
            p = p->next;
        }

        // 2. Instantiate a function pointer node for the address
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup((yyvsp[(2) - (7)].string_val));

        // 3. Assign the pointer to the global variable (e.g., func_add)
        ASTNode* assign = make_node(NODE_MULTIPLE_ASSIGNMENT);
        assign->as.mult_assign.targets_head = make_node_ident((yyvsp[(2) - (7)].string_val));
        assign->as.mult_assign.values_head = func_ptr;

        // 4. Chain them sequentially for the global init vector
        func_def->next = assign;
        (yyval.ast_node) = func_def;
    ;}
    break;

  case 63:
#line 528 "parser.y"
    {
        // 1. Create a unique mangled label using the helper function
        char* mangled_name = mangle_method_name((yyvsp[(2) - (9)].string_val), (yyvsp[(4) - (9)].string_val));

        // 2. Build the structural function definition body using pre-allocated node
        ASTNode* func_def = (yyvsp[(1) - (9)].ast_node);
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = (yyvsp[(6) - (9)].ast_node);
        func_def->as.function_def.body = (yyvsp[(8) - (9)].ast_node);

        // 3. Instantiate a function pointer node evaluating to that address
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        ASTNode* key_node = make_node_string((yyvsp[(4) - (9)].string_val));
        ASTNode* table_node = make_node_ident((yyvsp[(2) - (9)].string_val));
        
        // 4. Tie it all into a table assignment: table[key] = func_ptr
        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key = key_node;
        table_set->as.table_set.value = func_ptr;

        // 5. Chain them sequentially so the compiler outputs both properties cleanly
        func_def->next = table_set;
        (yyval.ast_node) = func_def;
    ;}
    break;

  case 64:
#line 556 "parser.y"
    {
        // 1. Create a unique mangled label using the helper function
        char* mangled_name = mangle_method_name((yyvsp[(2) - (9)].string_val), (yyvsp[(4) - (9)].string_val));

        // 2. INJECT "self" as the first parameter!
        ASTNode* self_param = make_node_ident("self");
        self_param->next = (yyvsp[(6) - (9)].ast_node); // Link it to the rest of the parameters

        // 3. Build the structural function definition body using pre-allocated node
        ASTNode* func_def = (yyvsp[(1) - (9)].ast_node);
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = self_param; // Set self as the head of the list
        func_def->as.function_def.body = (yyvsp[(8) - (9)].ast_node);

        // 4. Instantiate a function pointer node evaluating to that address
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        ASTNode* key_node = make_node_string((yyvsp[(4) - (9)].string_val));
        ASTNode* table_node = make_node_ident((yyvsp[(2) - (9)].string_val));
        
        // 5. Tie it all into a table assignment: table[key] = func_ptr
        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key = key_node;
        table_set->as.table_set.value = func_ptr;

        // 6. Chain them sequentially so the compiler outputs both properties cleanly
        func_def->next = table_set;
        (yyval.ast_node) = func_def;
    ;}
    break;

  case 65:
#line 590 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_RETURN);
        (yyval.ast_node)->as.return_stmt.expressions_head = (yyvsp[(2) - (2)].ast_node);
        (yyval.ast_node)->as.return_stmt.parent_func_arg_count = 0;
    ;}
    break;

  case 66:
#line 595 "parser.y"
    {
        // Bare 'return' with no expression -- equivalent to returning
        // no values at all. node_return() already handles a NULL
        // expressions_head correctly: its per-expression loop simply
        // doesn't execute (ret_idx stays 0), and the existing
        // stale-register nil-padding logic (see the earlier fix) fills
        // in BOXED_NIL for however many return slots this function's
        // OTHER branches statically require -- exactly the same as an
        // early-exit branch that returns fewer values than a sibling
        // branch elsewhere in the same function.
        (yyval.ast_node) = make_node(NODE_RETURN);
        (yyval.ast_node)->as.return_stmt.expressions_head = NULL;
        (yyval.ast_node)->as.return_stmt.parent_func_arg_count = 0;
    ;}
    break;

  case 67:
#line 612 "parser.y"
    { 
        (yyval.ast_node) = make_node_ident((yyvsp[(1) - (1)].string_val)); 
    ;}
    break;

  case 68:
#line 615 "parser.y"
    { 
        (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node); 
    ;}
    break;

  case 69:
#line 618 "parser.y"
    { 
        (yyval.ast_node) = (yyvsp[(2) - (3)].ast_node); 
    ;}
    break;

  case 70:
#line 621 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_TABLE_GET);
        (yyval.ast_node)->as.table_get.table_expr = (yyvsp[(1) - (4)].ast_node);
        (yyval.ast_node)->as.table_get.key = (yyvsp[(3) - (4)].ast_node);
    ;}
    break;

  case 71:
#line 626 "parser.y"
    {
        ASTNode *string_key = make_node_string((yyvsp[(3) - (3)].string_val));
        (yyval.ast_node) = make_node(NODE_TABLE_GET);
        (yyval.ast_node)->as.table_get.table_expr = (yyvsp[(1) - (3)].ast_node);
        (yyval.ast_node)->as.table_get.key = string_key;
    ;}
    break;

  case 72:
#line 635 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_VARIADIC_EXPR);
    ;}
    break;

  case 73:
#line 638 "parser.y"
    {
        (yyval.ast_node) = make_node(NODE_NUMBER);
        (yyval.ast_node)->as.number.val = (yyvsp[(1) - (1)].number_val);
    ;}
    break;

  case 74:
#line 642 "parser.y"
    { (yyval.ast_node) = make_node_string((yyvsp[(1) - (1)].string_val)); ;}
    break;

  case 75:
#line 643 "parser.y"
    { (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node); ;}
    break;

  case 76:
#line 644 "parser.y"
    { (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node); ;}
    break;

  case 77:
#line 645 "parser.y"
    { (yyval.ast_node) = make_node_binary (NODE_ADD, (yyvsp[(1) - (3)].ast_node), (yyvsp[(3) - (3)].ast_node)); ;}
    break;

  case 78:
#line 646 "parser.y"
    { (yyval.ast_node) = make_node_binary (NODE_SUB, (yyvsp[(1) - (3)].ast_node), (yyvsp[(3) - (3)].ast_node)); ;}
    break;

  case 79:
#line 647 "parser.y"
    { (yyval.ast_node) = make_node_binary (NODE_MUL, (yyvsp[(1) - (3)].ast_node), (yyvsp[(3) - (3)].ast_node)); ;}
    break;

  case 80:
#line 648 "parser.y"
    { (yyval.ast_node) = make_node_binary (NODE_FLOORDIV, (yyvsp[(1) - (3)].ast_node), (yyvsp[(3) - (3)].ast_node)); ;}
    break;

  case 81:
#line 649 "parser.y"
    { (yyval.ast_node) = make_node_binary (NODE_DIV, (yyvsp[(1) - (3)].ast_node), (yyvsp[(3) - (3)].ast_node)); ;}
    break;

  case 82:
#line 650 "parser.y"
    { (yyval.ast_node) = make_node_binary (NODE_MOD, (yyvsp[(1) - (3)].ast_node), (yyvsp[(3) - (3)].ast_node)); ;}
    break;

  case 83:
#line 651 "parser.y"
    { (yyval.ast_node) = make_node_binary (NODE_POW, (yyvsp[(1) - (3)].ast_node), (yyvsp[(3) - (3)].ast_node)); ;}
    break;

  case 84:
#line 652 "parser.y"
    { (yyval.ast_node) = make_node_boolean (true);  ;}
    break;

  case 85:
#line 653 "parser.y"
    { (yyval.ast_node) = make_node_boolean (false); ;}
    break;

  case 86:
#line 654 "parser.y"
    { (yyval.ast_node) = make_node_nil ();          ;}
    break;

  case 87:
#line 655 "parser.y"
    { (yyval.ast_node) = make_node_unary  (OP_LEN,   (yyvsp[(2) - (2)].ast_node));     ;}
    break;

  case 88:
#line 656 "parser.y"
    { (yyval.ast_node) = make_node_unary (OP_UNM, (yyvsp[(2) - (2)].ast_node)); ;}
    break;

  case 89:
#line 657 "parser.y"
    { (yyval.ast_node) = make_node_unary (OP_NOT, (yyvsp[(2) - (2)].ast_node)); ;}
    break;

  case 90:
#line 658 "parser.y"
    { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_EQ;  (yyval.ast_node)->as.binary.left = (yyvsp[(1) - (3)].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[(3) - (3)].ast_node); ;}
    break;

  case 91:
#line 659 "parser.y"
    { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_NEQ; (yyval.ast_node)->as.binary.left = (yyvsp[(1) - (3)].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[(3) - (3)].ast_node); ;}
    break;

  case 92:
#line 660 "parser.y"
    { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_LT;  (yyval.ast_node)->as.binary.left = (yyvsp[(1) - (3)].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[(3) - (3)].ast_node); ;}
    break;

  case 93:
#line 661 "parser.y"
    { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_GT;  (yyval.ast_node)->as.binary.left = (yyvsp[(1) - (3)].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[(3) - (3)].ast_node); ;}
    break;

  case 94:
#line 662 "parser.y"
    { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_LE;  (yyval.ast_node)->as.binary.left = (yyvsp[(1) - (3)].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[(3) - (3)].ast_node); ;}
    break;

  case 95:
#line 663 "parser.y"
    { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_GE;  (yyval.ast_node)->as.binary.left = (yyvsp[(1) - (3)].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[(3) - (3)].ast_node); ;}
    break;

  case 96:
#line 664 "parser.y"
    { (yyval.ast_node) = make_node(NODE_AND);        (yyval.ast_node)->as.binary.left = (yyvsp[(1) - (3)].ast_node);     (yyval.ast_node)->as.binary.right = (yyvsp[(3) - (3)].ast_node); ;}
    break;

  case 97:
#line 665 "parser.y"
    { (yyval.ast_node) = make_node(NODE_OR);         (yyval.ast_node)->as.binary.left = (yyvsp[(1) - (3)].ast_node);     (yyval.ast_node)->as.binary.right = (yyvsp[(3) - (3)].ast_node); ;}
    break;

  case 98:
#line 666 "parser.y"
    { (yyval.ast_node) = make_node(NODE_CONCAT);     (yyval.ast_node)->as.binary.left = (yyvsp[(1) - (3)].ast_node);     (yyval.ast_node)->as.binary.right = (yyvsp[(3) - (3)].ast_node); ;}
    break;

  case 99:
#line 668 "parser.y"
    {
        static int anon_counter = 0;
        char buf[64];
        snprintf(buf, sizeof(buf), "__anon_%d", anon_counter++);

        ASTNode* func_def = (yyvsp[(1) - (6)].ast_node);
        func_def->as.function_def.name = strdup(buf);
        func_def->as.function_def.params = (yyvsp[(3) - (6)].ast_node);
        func_def->as.function_def.body = (yyvsp[(5) - (6)].ast_node);

        // Initialize and check variadic status for anonymous functions
        func_def->as.function_def.is_variadic = 0;
        ASTNode *p = (yyvsp[(3) - (6)].ast_node);
        while (p != NULL) {
            if (p->type == NODE_IDENTIFIER && strcmp(p->as.id.name, "...") == 0) {
                func_def->as.function_def.is_variadic = 1;
                break;
            }
            p = p->next;
        }

        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(buf);
        func_ptr->as.func_ptr.func_def = func_def;  // Store here, NOT in next

        (yyval.ast_node) = func_ptr;
    ;}
    break;

  case 100:
#line 698 "parser.y"
    {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.target = make_node_ident((yyvsp[(1) - (4)].string_val));
        node->as.call.is_method_call = 0; 
        node->as.call.args_head = (yyvsp[(3) - (4)].ast_node);
        (yyval.ast_node) = node;
    ;}
    break;

  case 101:
#line 705 "parser.y"
    {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.is_method_call = 0;
        
        // Dynamically look up the function inside the table
        ASTNode* dynamic_lookup = make_node(NODE_TABLE_GET);
        dynamic_lookup->as.table_get.table_expr = (yyvsp[(1) - (6)].ast_node);
        dynamic_lookup->as.table_get.key = make_node_string((yyvsp[(3) - (6)].string_val));
        node->as.call.target = dynamic_lookup;
        node->as.call.args_head = (yyvsp[(5) - (6)].ast_node);
        (yyval.ast_node) = node;
    ;}
    break;

  case 102:
#line 717 "parser.y"
    {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.target = (yyvsp[(1) - (6)].ast_node);
        node->as.call.is_method_call = 1;
        
        ASTNode* dynamic_lookup = make_node(NODE_TABLE_GET);
        dynamic_lookup->as.table_get.table_expr = (yyvsp[(1) - (6)].ast_node);
        dynamic_lookup->as.table_get.key = make_node_string((yyvsp[(3) - (6)].string_val));
        node->as.call.target = dynamic_lookup;
        node->as.call.args_head = (yyvsp[(5) - (6)].ast_node);
        (yyval.ast_node) = node;
    ;}
    break;

  case 103:
#line 729 "parser.y"
    {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.target = (yyvsp[(1) - (4)].ast_node);
        node->as.call.is_method_call = 0;
        node->as.call.args_head = (yyvsp[(3) - (4)].ast_node);
        (yyval.ast_node) = node;
    ;}
    break;

  case 104:
#line 739 "parser.y"
    {
        // Array-style: {value} -> implicit sequential key
        (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node);
    ;}
    break;

  case 105:
#line 743 "parser.y"
    {
    // Record-style: {key = value}
    // Convert identifier key to string literal (Lua semantics: x=8 means key "x", not var x)
    ASTNode *key_node = (yyvsp[(1) - (3)].ast_node);
    if (key_node->type == NODE_IDENTIFIER) {
        key_node = make_node_string(key_node->as.id.name);
    }
    (yyval.ast_node) = make_node_table_set(NULL, key_node, (yyvsp[(3) - (3)].ast_node));
;}
    break;

  case 106:
#line 752 "parser.y"
    {
        // Explicit key: {[key] = value}
        (yyval.ast_node) = make_node_table_set(NULL, (yyvsp[(2) - (5)].ast_node), (yyvsp[(5) - (5)].ast_node));
    ;}
    break;

  case 107:
#line 759 "parser.y"
    {
        (yyval.ast_node) = (yyvsp[(1) - (1)].ast_node);
    ;}
    break;

  case 108:
#line 762 "parser.y"
    {
        // Chain fields together via next pointer
        ASTNode* curr = (yyvsp[(1) - (3)].ast_node);
        while (curr->next) curr = curr->next;
        curr->next = (yyvsp[(3) - (3)].ast_node);
        (yyval.ast_node) = (yyvsp[(1) - (3)].ast_node);
    ;}
    break;

  case 109:
#line 772 "parser.y"
    {
        (yyval.ast_node) = make_node_table_constructor(NULL);
    ;}
    break;

  case 110:
#line 775 "parser.y"
    {
        (yyval.ast_node) = make_node_table_constructor((yyvsp[(2) - (3)].ast_node));
    ;}
    break;

  case 111:
#line 778 "parser.y"
    {
        // Trailing comma before the closing brace -- e.g.
        //   { [1] = a, [2] = b, }
        // Standard, idiomatic Lua; the parser previously had no
        // production for a comma immediately followed by '}', since
        // field_list only ever grows via 'field_list , field' and a
        // field must start with an expression token, which '}' is not.
        (yyval.ast_node) = make_node_table_constructor((yyvsp[(2) - (4)].ast_node));
    ;}
    break;

  case 112:
#line 791 "parser.y"
    {
        current_tic80_section = strdup((yyvsp[(1) - (1)].string_val));
        free((yyvsp[(1) - (1)].string_val));
    ;}
    break;

  case 113:
#line 797 "parser.y"
    {
        // === PROCESS SECTION IMMEDIATELY ===
        process_tic80_section(current_tic80_section, current_tic80_assets);

        // Clean up this section's data
        free(current_tic80_section);
        current_tic80_section = NULL;

        TIC80AssetData *item = current_tic80_assets;
        current_tic80_assets = NULL;
        while (item != NULL) {
            TIC80AssetData *next = item->next;
            if (item->hex_data != NULL) free(item->hex_data);
            free(item);
            item = next;
        }

        free((yyvsp[(3) - (4)].ast_node));
        (yyval.ast_node) = NULL;
    ;}
    break;

  case 114:
#line 820 "parser.y"
    { (yyval.ast_node) = NULL; ;}
    break;

  case 115:
#line 822 "parser.y"
    {
        TIC80AssetData *data = parse_tic80_asset_line((yyvsp[(2) - (2)].string_val));
        if (data != NULL) {  // <-- ADD THIS CHECK
            data->next = current_tic80_assets;
            current_tic80_assets = data;
        }
        free((yyvsp[(2) - (2)].string_val));
        (yyval.ast_node) = NULL;
    ;}
    break;


/* Line 1267 of yacc.c.  */
#line 2905 "parser.c"
      default: break;
    }
  YY_SYMBOL_PRINT ("-> $$ =", yyr1[yyn], &yyval, &yyloc);

  YYPOPSTACK (yylen);
  yylen = 0;
  YY_STACK_PRINT (yyss, yyssp);

  *++yyvsp = yyval;


  /* Now `shift' the result of the reduction.  Determine what state
     that goes to, based on the state we popped back to and the rule
     number reduced by.  */

  yyn = yyr1[yyn];

  yystate = yypgoto[yyn - YYNTOKENS] + *yyssp;
  if (0 <= yystate && yystate <= YYLAST && yycheck[yystate] == *yyssp)
    yystate = yytable[yystate];
  else
    yystate = yydefgoto[yyn - YYNTOKENS];

  goto yynewstate;


/*------------------------------------.
| yyerrlab -- here on detecting error |
`------------------------------------*/
yyerrlab:
  /* If not already recovering from an error, report this error.  */
  if (!yyerrstatus)
    {
      ++yynerrs;
#if ! YYERROR_VERBOSE
      yyerror (YY_("syntax error"));
#else
      {
	YYSIZE_T yysize = yysyntax_error (0, yystate, yychar);
	if (yymsg_alloc < yysize && yymsg_alloc < YYSTACK_ALLOC_MAXIMUM)
	  {
	    YYSIZE_T yyalloc = 2 * yysize;
	    if (! (yysize <= yyalloc && yyalloc <= YYSTACK_ALLOC_MAXIMUM))
	      yyalloc = YYSTACK_ALLOC_MAXIMUM;
	    if (yymsg != yymsgbuf)
	      YYSTACK_FREE (yymsg);
	    yymsg = (char *) YYSTACK_ALLOC (yyalloc);
	    if (yymsg)
	      yymsg_alloc = yyalloc;
	    else
	      {
		yymsg = yymsgbuf;
		yymsg_alloc = sizeof yymsgbuf;
	      }
	  }

	if (0 < yysize && yysize <= yymsg_alloc)
	  {
	    (void) yysyntax_error (yymsg, yystate, yychar);
	    yyerror (yymsg);
	  }
	else
	  {
	    yyerror (YY_("syntax error"));
	    if (yysize != 0)
	      goto yyexhaustedlab;
	  }
      }
#endif
    }



  if (yyerrstatus == 3)
    {
      /* If just tried and failed to reuse look-ahead token after an
	 error, discard it.  */

      if (yychar <= YYEOF)
	{
	  /* Return failure if at end of input.  */
	  if (yychar == YYEOF)
	    YYABORT;
	}
      else
	{
	  yydestruct ("Error: discarding",
		      yytoken, &yylval);
	  yychar = YYEMPTY;
	}
    }

  /* Else will try to reuse look-ahead token after shifting the error
     token.  */
  goto yyerrlab1;


/*---------------------------------------------------.
| yyerrorlab -- error raised explicitly by YYERROR.  |
`---------------------------------------------------*/
yyerrorlab:

  /* Pacify compilers like GCC when the user code never invokes
     YYERROR and the label yyerrorlab therefore never appears in user
     code.  */
  if (/*CONSTCOND*/ 0)
     goto yyerrorlab;

  /* Do not reclaim the symbols of the rule which action triggered
     this YYERROR.  */
  YYPOPSTACK (yylen);
  yylen = 0;
  YY_STACK_PRINT (yyss, yyssp);
  yystate = *yyssp;
  goto yyerrlab1;


/*-------------------------------------------------------------.
| yyerrlab1 -- common code for both syntax error and YYERROR.  |
`-------------------------------------------------------------*/
yyerrlab1:
  yyerrstatus = 3;	/* Each real token shifted decrements this.  */

  for (;;)
    {
      yyn = yypact[yystate];
      if (yyn != YYPACT_NINF)
	{
	  yyn += YYTERROR;
	  if (0 <= yyn && yyn <= YYLAST && yycheck[yyn] == YYTERROR)
	    {
	      yyn = yytable[yyn];
	      if (0 < yyn)
		break;
	    }
	}

      /* Pop the current state because it cannot handle the error token.  */
      if (yyssp == yyss)
	YYABORT;


      yydestruct ("Error: popping",
		  yystos[yystate], yyvsp);
      YYPOPSTACK (1);
      yystate = *yyssp;
      YY_STACK_PRINT (yyss, yyssp);
    }

  if (yyn == YYFINAL)
    YYACCEPT;

  *++yyvsp = yylval;


  /* Shift the error token.  */
  YY_SYMBOL_PRINT ("Shifting", yystos[yyn], yyvsp, yylsp);

  yystate = yyn;
  goto yynewstate;


/*-------------------------------------.
| yyacceptlab -- YYACCEPT comes here.  |
`-------------------------------------*/
yyacceptlab:
  yyresult = 0;
  goto yyreturn;

/*-----------------------------------.
| yyabortlab -- YYABORT comes here.  |
`-----------------------------------*/
yyabortlab:
  yyresult = 1;
  goto yyreturn;

#ifndef yyoverflow
/*-------------------------------------------------.
| yyexhaustedlab -- memory exhaustion comes here.  |
`-------------------------------------------------*/
yyexhaustedlab:
  yyerror (YY_("memory exhausted"));
  yyresult = 2;
  /* Fall through.  */
#endif

yyreturn:
  if (yychar != YYEOF && yychar != YYEMPTY)
     yydestruct ("Cleanup: discarding lookahead",
		 yytoken, &yylval);
  /* Do not reclaim the symbols of the rule which action triggered
     this YYABORT or YYACCEPT.  */
  YYPOPSTACK (yylen);
  YY_STACK_PRINT (yyss, yyssp);
  while (yyssp != yyss)
    {
      yydestruct ("Cleanup: popping",
		  yystos[*yyssp], yyvsp);
      YYPOPSTACK (1);
    }
#ifndef yyoverflow
  if (yyss != yyssa)
    YYSTACK_FREE (yyss);
#endif
#if YYERROR_VERBOSE
  if (yymsg != yymsgbuf)
    YYSTACK_FREE (yymsg);
#endif
  /* Make sure YYID is used.  */
  return YYID (yyresult);
}


#line 832 "parser.y"


void yyerror(const char *s) {
    compiler_error(ERR_SYNTAX, yylineno, "%s", s);
}

char* mangle_method_name(const char* table_name, const char* method_name) {
    if (table_name == NULL || method_name == NULL) {
        return NULL;
    }

    // Calculate required string length:
    // Length of table_name + 1 (for the underscore) + Length of method_name + 1 (for the null terminator)
    size_t len = strlen(table_name) + 1 + strlen(method_name) + 1;
    // Allocate memory for the new mangled string
    char *mangled = (char*) malloc (len);
    if (mangled == NULL)
    {
        compiler_error (ERR_INTERNAL, -1, "Memory allocation failed in name mangler\n");
    }

    // Safely format the new string
    snprintf (mangled, len, "%s_%s", table_name, method_name);
    return (mangled);
}

