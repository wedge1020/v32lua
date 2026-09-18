/* A Bison parser, made by GNU Bison 3.8.2.  */

/* Bison implementation for Yacc-like parsers in C

   Copyright (C) 1984, 1989-1990, 2000-2015, 2018-2021 Free Software Foundation,
   Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.  */

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

/* DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
   especially those whose name start with YY_ or yy_.  They are
   private implementation details that can be changed or removed.  */

/* All symbols defined below should begin with yy or YY, to avoid
   infringing on user name space.  This should be done even for local
   variables, as they might otherwise be expanded by user macros.
   There are some unavoidable exceptions within include files to
   define necessary library symbols; they are noted "INFRINGES ON
   USER NAME SPACE" below.  */

/* Identify Bison output, and Bison version.  */
#define YYBISON 30802

/* Bison version string.  */
#define YYBISON_VERSION "3.8.2"

/* Skeleton name.  */
#define YYSKELETON_NAME "yacc.c"

/* Pure parsers.  */
#define YYPURE 0

/* Push parsers.  */
#define YYPUSH 0

/* Pull parsers.  */
#define YYPULL 1




/* First part of user prologue.  */
#line 1 "src/parser.y"


#include "v32lua.h"

// Define the global AST root variable here
ASTNode* root_node = NULL;

extern int yylineno;
extern FILE* yyin;
extern int yylex (void);
void yyerror (const char *s);

// Add your new helper prototype here:
char *mangle_method_name (const char *table_name, const char *method_name);


#line 88 "src/parser.c"

# ifndef YY_CAST
#  ifdef __cplusplus
#   define YY_CAST(Type, Val) static_cast<Type> (Val)
#   define YY_REINTERPRET_CAST(Type, Val) reinterpret_cast<Type> (Val)
#  else
#   define YY_CAST(Type, Val) ((Type) (Val))
#   define YY_REINTERPRET_CAST(Type, Val) ((Type) (Val))
#  endif
# endif
# ifndef YY_NULLPTR
#  if defined __cplusplus
#   if 201103L <= __cplusplus
#    define YY_NULLPTR nullptr
#   else
#    define YY_NULLPTR 0
#   endif
#  else
#   define YY_NULLPTR ((void*)0)
#  endif
# endif

#include "parser.h"
/* Symbol kind.  */
enum yysymbol_kind_t
{
  YYSYMBOL_YYEMPTY = -2,
  YYSYMBOL_YYEOF = 0,                      /* "end of file"  */
  YYSYMBOL_YYerror = 1,                    /* error  */
  YYSYMBOL_YYUNDEF = 2,                    /* "invalid token"  */
  YYSYMBOL_TOKEN_NUMBER = 3,               /* TOKEN_NUMBER  */
  YYSYMBOL_TOKEN_IDENTIFIER = 4,           /* TOKEN_IDENTIFIER  */
  YYSYMBOL_TOKEN_STRING = 5,               /* TOKEN_STRING  */
  YYSYMBOL_TOKEN_COMMENT_LINE = 6,         /* TOKEN_COMMENT_LINE  */
  YYSYMBOL_TOKEN_COMMENT_BLOCK = 7,        /* TOKEN_COMMENT_BLOCK  */
  YYSYMBOL_TOKEN_TIC80_SECTION_HEADER = 8, /* TOKEN_TIC80_SECTION_HEADER  */
  YYSYMBOL_TOKEN_TIC80_ASSET_DATA = 9,     /* TOKEN_TIC80_ASSET_DATA  */
  YYSYMBOL_TOKEN_TIC80_SECTION_FOOTER = 10, /* TOKEN_TIC80_SECTION_FOOTER  */
  YYSYMBOL_TOKEN_CART_HINT = 11,           /* TOKEN_CART_HINT  */
  YYSYMBOL_TOKEN_COMPOUND_ASSIGN = 12,     /* TOKEN_COMPOUND_ASSIGN  */
  YYSYMBOL_TOKEN_WHILE = 13,               /* TOKEN_WHILE  */
  YYSYMBOL_TOKEN_FOR = 14,                 /* TOKEN_FOR  */
  YYSYMBOL_TOKEN_BREAK = 15,               /* TOKEN_BREAK  */
  YYSYMBOL_TOKEN_IF = 16,                  /* TOKEN_IF  */
  YYSYMBOL_TOKEN_ELSEIF = 17,              /* TOKEN_ELSEIF  */
  YYSYMBOL_TOKEN_THEN = 18,                /* TOKEN_THEN  */
  YYSYMBOL_TOKEN_ELSE = 19,                /* TOKEN_ELSE  */
  YYSYMBOL_TOKEN_END = 20,                 /* TOKEN_END  */
  YYSYMBOL_TOKEN_FUNCTION = 21,            /* TOKEN_FUNCTION  */
  YYSYMBOL_TOKEN_ASM = 22,                 /* TOKEN_ASM  */
  YYSYMBOL_TOKEN_RAWASM = 23,              /* TOKEN_RAWASM  */
  YYSYMBOL_TOKEN_RETURN = 24,              /* TOKEN_RETURN  */
  YYSYMBOL_TOKEN_AND = 25,                 /* TOKEN_AND  */
  YYSYMBOL_TOKEN_OR = 26,                  /* TOKEN_OR  */
  YYSYMBOL_TOKEN_EQ = 27,                  /* TOKEN_EQ  */
  YYSYMBOL_TOKEN_NEQ = 28,                 /* TOKEN_NEQ  */
  YYSYMBOL_TOKEN_LE = 29,                  /* TOKEN_LE  */
  YYSYMBOL_TOKEN_GE = 30,                  /* TOKEN_GE  */
  YYSYMBOL_TOKEN_LT = 31,                  /* TOKEN_LT  */
  YYSYMBOL_TOKEN_GT = 32,                  /* TOKEN_GT  */
  YYSYMBOL_TOKEN_CONCAT = 33,              /* TOKEN_CONCAT  */
  YYSYMBOL_TOKEN_LOCAL = 34,               /* TOKEN_LOCAL  */
  YYSYMBOL_TOKEN_IN = 35,                  /* TOKEN_IN  */
  YYSYMBOL_TOKEN_DO = 36,                  /* TOKEN_DO  */
  YYSYMBOL_TOKEN_NOT = 37,                 /* TOKEN_NOT  */
  YYSYMBOL_TOKEN_LEN = 38,                 /* TOKEN_LEN  */
  YYSYMBOL_UNARY_MINUS = 39,               /* UNARY_MINUS  */
  YYSYMBOL_TOKEN_TRUE = 40,                /* TOKEN_TRUE  */
  YYSYMBOL_TOKEN_FALSE = 41,               /* TOKEN_FALSE  */
  YYSYMBOL_TOKEN_NIL = 42,                 /* TOKEN_NIL  */
  YYSYMBOL_TOKEN_FLOORDIV = 43,            /* TOKEN_FLOORDIV  */
  YYSYMBOL_TOKEN_DOTS = 44,                /* TOKEN_DOTS  */
  YYSYMBOL_TOKEN_REPEAT = 45,              /* TOKEN_REPEAT  */
  YYSYMBOL_TOKEN_UNTIL = 46,               /* TOKEN_UNTIL  */
  YYSYMBOL_47_ = 47,                       /* '+'  */
  YYSYMBOL_48_ = 48,                       /* '-'  */
  YYSYMBOL_49_ = 49,                       /* '*'  */
  YYSYMBOL_50_ = 50,                       /* '/'  */
  YYSYMBOL_51_ = 51,                       /* '%'  */
  YYSYMBOL_52_ = 52,                       /* '^'  */
  YYSYMBOL_53_ = 53,                       /* '['  */
  YYSYMBOL_54_ = 54,                       /* '.'  */
  YYSYMBOL_55_ = 55,                       /* ':'  */
  YYSYMBOL_56_ = 56,                       /* ';'  */
  YYSYMBOL_57_ = 57,                       /* ','  */
  YYSYMBOL_58_ = 58,                       /* '='  */
  YYSYMBOL_59_ = 59,                       /* ']'  */
  YYSYMBOL_60_ = 60,                       /* '('  */
  YYSYMBOL_61_ = 61,                       /* ')'  */
  YYSYMBOL_62_ = 62,                       /* '{'  */
  YYSYMBOL_63_ = 63,                       /* '}'  */
  YYSYMBOL_YYACCEPT = 64,                  /* $accept  */
  YYSYMBOL_program = 65,                   /* program  */
  YYSYMBOL_statement_list = 66,            /* statement_list  */
  YYSYMBOL_stat_list = 67,                 /* stat_list  */
  YYSYMBOL_parameter_list = 68,            /* parameter_list  */
  YYSYMBOL_argument_list = 69,             /* argument_list  */
  YYSYMBOL_func_start = 70,                /* func_start  */
  YYSYMBOL_while_start = 71,               /* while_start  */
  YYSYMBOL_repeat_start = 72,              /* repeat_start  */
  YYSYMBOL_for_start = 73,                 /* for_start  */
  YYSYMBOL_if_start = 74,                  /* if_start  */
  YYSYMBOL_statement = 75,                 /* statement  */
  YYSYMBOL_last_statement = 76,            /* last_statement  */
  YYSYMBOL_else_branch = 77,               /* else_branch  */
  YYSYMBOL_var_list = 78,                  /* var_list  */
  YYSYMBOL_expr_list = 79,                 /* expr_list  */
  YYSYMBOL_function_def = 80,              /* function_def  */
  YYSYMBOL_return_stmt = 81,               /* return_stmt  */
  YYSYMBOL_prefix_expr = 82,               /* prefix_expr  */
  YYSYMBOL_expr = 83,                      /* expr  */
  YYSYMBOL_function_call = 84,             /* function_call  */
  YYSYMBOL_field = 85,                     /* field  */
  YYSYMBOL_field_list = 86,                /* field_list  */
  YYSYMBOL_table_constructor = 87,         /* table_constructor  */
  YYSYMBOL_tic80_section = 88,             /* tic80_section  */
  YYSYMBOL_89_1 = 89,                      /* $@1  */
  YYSYMBOL_tic80_asset_lines = 90          /* tic80_asset_lines  */
};
typedef enum yysymbol_kind_t yysymbol_kind_t;




#ifdef short
# undef short
#endif

/* On compilers that do not define __PTRDIFF_MAX__ etc., make sure
   <limits.h> and (if available) <stdint.h> are included
   so that the code can choose integer types of a good width.  */

#ifndef __PTRDIFF_MAX__
# include <limits.h> /* INFRINGES ON USER NAME SPACE */
# if defined __STDC_VERSION__ && 199901 <= __STDC_VERSION__
#  include <stdint.h> /* INFRINGES ON USER NAME SPACE */
#  define YY_STDINT_H
# endif
#endif

/* Narrow types that promote to a signed type and that can represent a
   signed or unsigned integer of at least N bits.  In tables they can
   save space and decrease cache pressure.  Promoting to a signed type
   helps avoid bugs in integer arithmetic.  */

#ifdef __INT_LEAST8_MAX__
typedef __INT_LEAST8_TYPE__ yytype_int8;
#elif defined YY_STDINT_H
typedef int_least8_t yytype_int8;
#else
typedef signed char yytype_int8;
#endif

#ifdef __INT_LEAST16_MAX__
typedef __INT_LEAST16_TYPE__ yytype_int16;
#elif defined YY_STDINT_H
typedef int_least16_t yytype_int16;
#else
typedef short yytype_int16;
#endif

/* Work around bug in HP-UX 11.23, which defines these macros
   incorrectly for preprocessor constants.  This workaround can likely
   be removed in 2023, as HPE has promised support for HP-UX 11.23
   (aka HP-UX 11i v2) only through the end of 2022; see Table 2 of
   <https://h20195.www2.hpe.com/V2/getpdf.aspx/4AA4-7673ENW.pdf>.  */
#ifdef __hpux
# undef UINT_LEAST8_MAX
# undef UINT_LEAST16_MAX
# define UINT_LEAST8_MAX 255
# define UINT_LEAST16_MAX 65535
#endif

#if defined __UINT_LEAST8_MAX__ && __UINT_LEAST8_MAX__ <= __INT_MAX__
typedef __UINT_LEAST8_TYPE__ yytype_uint8;
#elif (!defined __UINT_LEAST8_MAX__ && defined YY_STDINT_H \
       && UINT_LEAST8_MAX <= INT_MAX)
typedef uint_least8_t yytype_uint8;
#elif !defined __UINT_LEAST8_MAX__ && UCHAR_MAX <= INT_MAX
typedef unsigned char yytype_uint8;
#else
typedef short yytype_uint8;
#endif

#if defined __UINT_LEAST16_MAX__ && __UINT_LEAST16_MAX__ <= __INT_MAX__
typedef __UINT_LEAST16_TYPE__ yytype_uint16;
#elif (!defined __UINT_LEAST16_MAX__ && defined YY_STDINT_H \
       && UINT_LEAST16_MAX <= INT_MAX)
typedef uint_least16_t yytype_uint16;
#elif !defined __UINT_LEAST16_MAX__ && USHRT_MAX <= INT_MAX
typedef unsigned short yytype_uint16;
#else
typedef int yytype_uint16;
#endif

#ifndef YYPTRDIFF_T
# if defined __PTRDIFF_TYPE__ && defined __PTRDIFF_MAX__
#  define YYPTRDIFF_T __PTRDIFF_TYPE__
#  define YYPTRDIFF_MAXIMUM __PTRDIFF_MAX__
# elif defined PTRDIFF_MAX
#  ifndef ptrdiff_t
#   include <stddef.h> /* INFRINGES ON USER NAME SPACE */
#  endif
#  define YYPTRDIFF_T ptrdiff_t
#  define YYPTRDIFF_MAXIMUM PTRDIFF_MAX
# else
#  define YYPTRDIFF_T long
#  define YYPTRDIFF_MAXIMUM LONG_MAX
# endif
#endif

#ifndef YYSIZE_T
# ifdef __SIZE_TYPE__
#  define YYSIZE_T __SIZE_TYPE__
# elif defined size_t
#  define YYSIZE_T size_t
# elif defined __STDC_VERSION__ && 199901 <= __STDC_VERSION__
#  include <stddef.h> /* INFRINGES ON USER NAME SPACE */
#  define YYSIZE_T size_t
# else
#  define YYSIZE_T unsigned
# endif
#endif

#define YYSIZE_MAXIMUM                                  \
  YY_CAST (YYPTRDIFF_T,                                 \
           (YYPTRDIFF_MAXIMUM < YY_CAST (YYSIZE_T, -1)  \
            ? YYPTRDIFF_MAXIMUM                         \
            : YY_CAST (YYSIZE_T, -1)))

#define YYSIZEOF(X) YY_CAST (YYPTRDIFF_T, sizeof (X))


/* Stored state numbers (used for stacks). */
typedef yytype_int16 yy_state_t;

/* State numbers in computations.  */
typedef int yy_state_fast_t;

#ifndef YY_
# if defined YYENABLE_NLS && YYENABLE_NLS
#  if ENABLE_NLS
#   include <libintl.h> /* INFRINGES ON USER NAME SPACE */
#   define YY_(Msgid) dgettext ("bison-runtime", Msgid)
#  endif
# endif
# ifndef YY_
#  define YY_(Msgid) Msgid
# endif
#endif


#ifndef YY_ATTRIBUTE_PURE
# if defined __GNUC__ && 2 < __GNUC__ + (96 <= __GNUC_MINOR__)
#  define YY_ATTRIBUTE_PURE __attribute__ ((__pure__))
# else
#  define YY_ATTRIBUTE_PURE
# endif
#endif

#ifndef YY_ATTRIBUTE_UNUSED
# if defined __GNUC__ && 2 < __GNUC__ + (7 <= __GNUC_MINOR__)
#  define YY_ATTRIBUTE_UNUSED __attribute__ ((__unused__))
# else
#  define YY_ATTRIBUTE_UNUSED
# endif
#endif

/* Suppress unused-variable warnings by "using" E.  */
#if ! defined lint || defined __GNUC__
# define YY_USE(E) ((void) (E))
#else
# define YY_USE(E) /* empty */
#endif

/* Suppress an incorrect diagnostic about yylval being uninitialized.  */
#if defined __GNUC__ && ! defined __ICC && 406 <= __GNUC__ * 100 + __GNUC_MINOR__
# if __GNUC__ * 100 + __GNUC_MINOR__ < 407
#  define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN                           \
    _Pragma ("GCC diagnostic push")                                     \
    _Pragma ("GCC diagnostic ignored \"-Wuninitialized\"")
# else
#  define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN                           \
    _Pragma ("GCC diagnostic push")                                     \
    _Pragma ("GCC diagnostic ignored \"-Wuninitialized\"")              \
    _Pragma ("GCC diagnostic ignored \"-Wmaybe-uninitialized\"")
# endif
# define YY_IGNORE_MAYBE_UNINITIALIZED_END      \
    _Pragma ("GCC diagnostic pop")
#else
# define YY_INITIAL_VALUE(Value) Value
#endif
#ifndef YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
# define YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
# define YY_IGNORE_MAYBE_UNINITIALIZED_END
#endif
#ifndef YY_INITIAL_VALUE
# define YY_INITIAL_VALUE(Value) /* Nothing. */
#endif

#if defined __cplusplus && defined __GNUC__ && ! defined __ICC && 6 <= __GNUC__
# define YY_IGNORE_USELESS_CAST_BEGIN                          \
    _Pragma ("GCC diagnostic push")                            \
    _Pragma ("GCC diagnostic ignored \"-Wuseless-cast\"")
# define YY_IGNORE_USELESS_CAST_END            \
    _Pragma ("GCC diagnostic pop")
#endif
#ifndef YY_IGNORE_USELESS_CAST_BEGIN
# define YY_IGNORE_USELESS_CAST_BEGIN
# define YY_IGNORE_USELESS_CAST_END
#endif


#define YY_ASSERT(E) ((void) (0 && (E)))

#if !defined yyoverflow

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
#    if ! defined _ALLOCA_H && ! defined EXIT_SUCCESS
#     include <stdlib.h> /* INFRINGES ON USER NAME SPACE */
      /* Use EXIT_SUCCESS as a witness for stdlib.h.  */
#     ifndef EXIT_SUCCESS
#      define EXIT_SUCCESS 0
#     endif
#    endif
#   endif
#  endif
# endif

# ifdef YYSTACK_ALLOC
   /* Pacify GCC's 'empty if-body' warning.  */
#  define YYSTACK_FREE(Ptr) do { /* empty */; } while (0)
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
#  if (defined __cplusplus && ! defined EXIT_SUCCESS \
       && ! ((defined YYMALLOC || defined malloc) \
             && (defined YYFREE || defined free)))
#   include <stdlib.h> /* INFRINGES ON USER NAME SPACE */
#   ifndef EXIT_SUCCESS
#    define EXIT_SUCCESS 0
#   endif
#  endif
#  ifndef YYMALLOC
#   define YYMALLOC malloc
#   if ! defined malloc && ! defined EXIT_SUCCESS
void *malloc (YYSIZE_T); /* INFRINGES ON USER NAME SPACE */
#   endif
#  endif
#  ifndef YYFREE
#   define YYFREE free
#   if ! defined free && ! defined EXIT_SUCCESS
void free (void *); /* INFRINGES ON USER NAME SPACE */
#   endif
#  endif
# endif
#endif /* !defined yyoverflow */

#if (! defined yyoverflow \
     && (! defined __cplusplus \
         || (defined YYSTYPE_IS_TRIVIAL && YYSTYPE_IS_TRIVIAL)))

/* A type that is properly aligned for any stack member.  */
union yyalloc
{
  yy_state_t yyss_alloc;
  YYSTYPE yyvs_alloc;
};

/* The size of the maximum gap between one aligned stack and the next.  */
# define YYSTACK_GAP_MAXIMUM (YYSIZEOF (union yyalloc) - 1)

/* The size of an array large to enough to hold all stacks, each with
   N elements.  */
# define YYSTACK_BYTES(N) \
     ((N) * (YYSIZEOF (yy_state_t) + YYSIZEOF (YYSTYPE)) \
      + YYSTACK_GAP_MAXIMUM)

# define YYCOPY_NEEDED 1

/* Relocate STACK from its old location to the new one.  The
   local variables YYSIZE and YYSTACKSIZE give the old and new number of
   elements in the stack, and YYPTR gives the new location of the
   stack.  Advance YYPTR to a properly aligned location for the next
   stack.  */
# define YYSTACK_RELOCATE(Stack_alloc, Stack)                           \
    do                                                                  \
      {                                                                 \
        YYPTRDIFF_T yynewbytes;                                         \
        YYCOPY (&yyptr->Stack_alloc, Stack, yysize);                    \
        Stack = &yyptr->Stack_alloc;                                    \
        yynewbytes = yystacksize * YYSIZEOF (*Stack) + YYSTACK_GAP_MAXIMUM; \
        yyptr += yynewbytes / YYSIZEOF (*yyptr);                        \
      }                                                                 \
    while (0)

#endif

#if defined YYCOPY_NEEDED && YYCOPY_NEEDED
/* Copy COUNT objects from SRC to DST.  The source and destination do
   not overlap.  */
# ifndef YYCOPY
#  if defined __GNUC__ && 1 < __GNUC__
#   define YYCOPY(Dst, Src, Count) \
      __builtin_memcpy (Dst, Src, YY_CAST (YYSIZE_T, (Count)) * sizeof (*(Src)))
#  else
#   define YYCOPY(Dst, Src, Count)              \
      do                                        \
        {                                       \
          YYPTRDIFF_T yyi;                      \
          for (yyi = 0; yyi < (Count); yyi++)   \
            (Dst)[yyi] = (Src)[yyi];            \
        }                                       \
      while (0)
#  endif
# endif
#endif /* !YYCOPY_NEEDED */

/* YYFINAL -- State number of the termination state.  */
#define YYFINAL  61
/* YYLAST -- Last index in YYTABLE.  */
#define YYLAST   981

/* YYNTOKENS -- Number of terminals.  */
#define YYNTOKENS  64
/* YYNNTS -- Number of nonterminals.  */
#define YYNNTS  27
/* YYNRULES -- Number of rules.  */
#define YYNRULES  119
/* YYNSTATES -- Number of states.  */
#define YYNSTATES  268

/* YYMAXUTOK -- Last valid token kind.  */
#define YYMAXUTOK   301


/* YYTRANSLATE(TOKEN-NUM) -- Symbol number corresponding to TOKEN-NUM
   as returned by yylex, with out-of-bounds checking.  */
#define YYTRANSLATE(YYX)                                \
  (0 <= (YYX) && (YYX) <= YYMAXUTOK                     \
   ? YY_CAST (yysymbol_kind_t, yytranslate[YYX])        \
   : YYSYMBOL_YYUNDEF)

/* YYTRANSLATE[TOKEN-NUM] -- Symbol number corresponding to TOKEN-NUM
   as returned by yylex.  */
static const yytype_int8 yytranslate[] =
{
       0,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,    51,     2,     2,
      60,    61,    49,    47,    57,    48,    54,    50,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,    55,    56,
       2,    58,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,    53,     2,    59,    52,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,    62,     2,    63,     2,     2,     2,     2,
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
      45,    46
};

#if YYDEBUG
/* YYRLINE[YYN] -- Source line where rule number YYN was defined.  */
static const yytype_int16 yyrline[] =
{
       0,    72,    72,    79,    80,    81,    93,    97,    98,   110,
     111,   126,   129,   132,   136,   143,   153,   156,   159,   172,
     176,   180,   184,   187,   191,   192,   198,   204,   272,   277,
     282,   287,   298,   306,   314,   320,   326,   354,   396,   409,
     417,   423,   424,   428,   486,   529,   560,   564,   568,   572,
     573,   579,   580,   581,   582,   586,   587,   588,   600,   603,
     607,   610,   617,   625,   635,   638,   648,   680,   708,   742,
     747,   764,   767,   770,   773,   778,   787,   790,   794,   795,
     796,   797,   798,   799,   800,   801,   802,   803,   804,   805,
     806,   807,   808,   809,   810,   811,   812,   813,   814,   815,
     816,   817,   818,   819,   850,   857,   869,   881,   891,   895,
     904,   911,   914,   924,   927,   930,   943,   942,   972,   973
};
#endif

/** Accessing symbol of state STATE.  */
#define YY_ACCESSING_SYMBOL(State) YY_CAST (yysymbol_kind_t, yystos[State])

#if YYDEBUG || 0
/* The user-facing name of the symbol whose (internal) number is
   YYSYMBOL.  No bounds checking.  */
static const char *yysymbol_name (yysymbol_kind_t yysymbol) YY_ATTRIBUTE_UNUSED;

/* YYTNAME[SYMBOL-NUM] -- String name of the symbol SYMBOL-NUM.
   First, the terminals, then, starting at YYNTOKENS, nonterminals.  */
static const char *const yytname[] =
{
  "\"end of file\"", "error", "\"invalid token\"", "TOKEN_NUMBER",
  "TOKEN_IDENTIFIER", "TOKEN_STRING", "TOKEN_COMMENT_LINE",
  "TOKEN_COMMENT_BLOCK", "TOKEN_TIC80_SECTION_HEADER",
  "TOKEN_TIC80_ASSET_DATA", "TOKEN_TIC80_SECTION_FOOTER",
  "TOKEN_CART_HINT", "TOKEN_COMPOUND_ASSIGN", "TOKEN_WHILE", "TOKEN_FOR",
  "TOKEN_BREAK", "TOKEN_IF", "TOKEN_ELSEIF", "TOKEN_THEN", "TOKEN_ELSE",
  "TOKEN_END", "TOKEN_FUNCTION", "TOKEN_ASM", "TOKEN_RAWASM",
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
  "field", "field_list", "table_constructor", "tic80_section", "$@1",
  "tic80_asset_lines", YY_NULLPTR
};

static const char *
yysymbol_name (yysymbol_kind_t yysymbol)
{
  return yytname[yysymbol];
}
#endif

#define YYPACT_NINF (-118)

#define yypact_value_is_default(Yyn) \
  ((Yyn) == YYPACT_NINF)

#define YYTABLE_NINF (-76)

#define yytable_value_is_error(Yyn) \
  0

/* YYPACT[STATE-NUM] -- Index in YYTABLE of the portion describing
   STATE-NUM.  */
static const yytype_int16 yypact[] =
{
     458,    97,  -118,  -118,  -118,  -118,  -118,  -118,   -43,  -118,
    -118,   -42,   -30,    23,    -2,   458,  -118,    23,    38,  -118,
     458,    39,    23,   458,    -1,    23,    32,  -118,    -5,  -118,
      45,   101,    79,  -118,    23,  -118,  -118,   105,   108,  -118,
      99,  -118,    23,    23,  -118,  -118,  -118,  -118,    23,    36,
     119,    86,   117,   875,  -118,  -118,   141,    24,   121,   128,
     479,  -118,   112,  -118,    54,   819,   134,   -25,   -23,   395,
    -118,    23,     2,    23,  -118,    23,   182,   191,    23,   -36,
     875,   110,   140,   143,   165,   165,   165,    23,  -118,   719,
    -118,   -52,     4,    23,    23,   202,    23,    23,    23,    23,
      23,    23,    23,    23,    23,    23,    23,    23,    23,    23,
      23,    23,    87,    23,    23,   219,  -118,  -118,  -118,   221,
     222,     4,   458,    23,    23,    23,  -118,   458,  -118,  -118,
     875,    97,   129,    86,   516,    58,   169,    18,    23,  -118,
    -118,  -118,  -118,  -118,   551,    23,   125,  -118,  -118,  -118,
      33,   875,   586,   171,   929,   903,    88,    88,    88,    88,
      88,    88,    88,   165,    74,    74,   165,   165,   165,   165,
     229,   230,     4,    86,   621,   138,   175,   177,   103,   218,
     875,   786,    -7,    85,    23,   236,    35,    23,    23,    23,
    -118,   875,   186,   875,  -118,  -118,     5,   458,  -118,   187,
     192,   133,   167,     4,     4,   458,  -118,    23,   458,    23,
     458,   231,   656,   138,    23,   875,   139,   142,    23,  -118,
    -118,   233,     4,     4,   458,   152,   154,   234,   753,   237,
     691,  -118,  -118,   167,   875,  -118,  -118,   875,  -118,   155,
     157,   238,   458,   458,  -118,   458,    23,  -118,   458,   458,
     458,  -118,   239,   240,   241,   847,    85,   243,   246,  -118,
    -118,  -118,   458,  -118,  -118,  -118,   248,  -118
};

/* YYDEFACT[STATE-NUM] -- Default reduction number in state STATE-NUM.
   Performed when YYTABLE does not specify something else to do.  Zero
   means the default is an error.  */
static const yytype_int8 yydefact[] =
{
       3,    58,    47,    48,   116,    50,    20,    22,    53,    23,
      19,     0,     0,    70,     0,     3,    21,     0,     0,     2,
       4,     0,     0,     3,     0,     0,     9,     6,     0,    41,
      51,     0,    24,    49,    16,   118,    54,     0,     0,    77,
      71,    78,     0,     0,    88,    89,    90,    76,     0,     0,
       0,    69,    80,    64,    72,    79,     0,    40,     0,     0,
       0,     1,    10,     5,     0,     0,     0,    71,     0,     0,
       7,     0,     0,     0,    52,     0,     0,     0,    16,     0,
      17,     0,     0,     0,    93,    91,    92,     0,   113,   108,
     111,     0,    11,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,    39,    73,     8,     0,
       0,    11,     3,     0,     0,     0,    38,     3,    37,    36,
      27,    61,     0,    25,     0,    75,     0,     0,     0,   104,
     119,   117,    42,    46,     0,     0,     0,   114,    12,    13,
       0,    65,     0,    75,   100,   101,    94,    95,    98,    99,
      96,    97,   102,    84,    81,    82,    83,    85,    86,    87,
       0,     0,    11,    26,     0,    59,     0,     0,     0,     0,
      31,     0,     0,    55,     0,     0,    74,     0,    16,    16,
     107,    18,     0,   109,   115,   112,     0,     3,    74,     0,
       0,     0,    60,    11,    11,     3,    30,     0,     3,     0,
       3,     0,     0,    62,     0,    29,     0,     0,     0,    14,
      15,     0,    11,    11,     3,     0,     0,     0,     0,     0,
       0,    56,    35,    63,    28,   105,   106,   110,   103,     0,
       0,     0,     3,     3,    66,     3,     0,    34,     3,     3,
       3,    43,     0,     0,     0,     0,    55,     0,     0,    67,
      68,    32,     3,    57,    45,    44,     0,    33
};

/* YYPGOTO[NTERM-NUM].  */
static const yytype_int16 yypgoto[] =
{
    -118,  -118,    80,  -118,  -117,   -77,    22,  -118,  -118,  -118,
    -118,    -3,   249,    19,    83,   -57,  -118,  -118,     0,   269,
      31,   132,  -118,  -118,  -118,  -118,  -118
};

/* YYDEFGOTO[NTERM-NUM].  */
static const yytype_uint8 yydefgoto[] =
{
       0,    18,    19,    20,   150,    79,    50,    22,    23,    24,
      25,    26,    27,   211,    28,    51,    29,    30,    52,    53,
      54,    90,    91,    55,    33,    35,    81
};

/* YYTABLE[YYPACT[STATE-NUM]] -- What to do in state STATE-NUM.  If
   positive, shift that token.  If negative, reduce the rule whose
   number is the opposite.  If YYTABLE_NINF, syntax error.  */
static const yytype_int16 yytable[] =
{
      31,   137,     1,    67,   178,   146,   131,    71,   148,   219,
     -58,   147,   125,    36,    58,    31,   133,    62,    37,    10,
      31,   138,    21,    31,    58,   139,    39,    40,    41,   208,
      38,    32,   -58,   124,    72,    34,    56,    21,    61,    39,
      40,    41,    21,    64,    10,    21,    32,   -60,   149,   220,
      93,    32,    72,    73,    32,   201,   173,    10,    17,    17,
      42,    43,    17,    44,    45,    46,   129,    47,   182,    31,
     -59,    48,   132,    42,    43,   138,    44,    45,    46,   190,
      47,    72,   113,    17,    48,    49,   225,   226,    70,    87,
     196,    21,   -60,   214,   197,    59,    17,    57,    49,    88,
      32,    74,   209,    66,   210,   239,   240,    68,   119,   120,
      82,   216,   217,    83,   121,   -59,   187,   105,   188,   140,
     141,   104,    31,   108,   109,   110,   111,    31,    39,    40,
      41,   105,   -72,   -72,   -72,   106,   107,   108,   109,   110,
     111,   170,   171,    93,    21,   112,    10,   172,   116,    21,
     -71,   -71,   -71,    32,    75,    76,    77,    34,    32,    34,
     196,    78,    42,    43,   205,    44,    45,    46,   118,    47,
      94,    95,    77,    48,   114,   115,    77,    78,    87,    92,
     123,    78,   184,   185,    77,    17,   135,    49,   194,    78,
     196,   -75,   -75,   -75,   224,   136,   138,    31,   188,   138,
     235,   142,   179,   236,   143,    31,   153,   183,    31,   196,
      31,   196,   196,   242,   196,   243,   249,   111,   250,    21,
     -74,   -74,   -74,   175,    31,   176,   177,    21,    32,   189,
      21,   188,    21,   199,   200,   203,    32,   204,   206,    32,
     213,    32,    31,    31,   218,    31,    21,   222,    31,    31,
      31,   232,   223,   238,   244,    32,     0,   247,   251,   259,
     260,   261,    31,   264,    21,    21,   265,    21,   267,    63,
      21,    21,    21,    32,    32,   263,    32,   221,   195,    32,
      32,    32,     0,     0,    21,   227,    60,     0,   229,     0,
     231,    65,     0,    32,    69,     0,     0,     0,     0,     0,
       0,     0,     0,    80,   241,     0,     0,     0,     0,     0,
       0,    84,    85,     0,     0,     0,     0,    86,    89,     0,
       0,     0,   252,   253,     0,   254,     0,     0,   256,   257,
     258,     0,     0,     0,     0,     0,     0,     0,     0,     0,
     130,     0,   266,     0,   134,     0,     0,    80,     0,     0,
       0,     0,     0,     0,     0,     0,   144,     0,     0,     0,
       0,     0,   151,   152,     0,   154,   155,   156,   157,   158,
     159,   160,   161,   162,   163,   164,   165,   166,   167,   168,
     169,     0,     0,   174,     0,     0,     0,     0,     0,     0,
       0,     0,   180,   181,     0,     0,     0,     0,     0,     1,
       0,     2,     3,     4,     0,     0,     5,   191,     6,     7,
     126,     9,     0,   127,   193,    89,    10,    11,    12,   128,
      96,    97,    98,    99,   100,   101,   102,   103,   104,    14,
       0,    15,     0,     0,     0,     0,     0,     0,   105,     0,
      16,     0,   106,   107,   108,   109,   110,   111,     0,     0,
       0,     0,     0,   212,     0,    17,   215,    80,    80,     0,
       0,     0,     1,     0,     2,     3,     4,     0,     0,     5,
       0,     6,     7,     8,     9,     0,   228,     0,   230,    10,
      11,    12,    13,   234,     0,     0,     0,   237,     0,     0,
       0,     0,    14,     0,    15,     0,     0,     0,     0,     0,
       0,     0,     0,    16,    96,    97,    98,    99,   100,   101,
     102,   103,   104,     0,     0,   255,     0,     0,    17,     0,
       0,     0,   105,     0,     0,     0,   106,   107,   108,   109,
     110,   111,     0,     0,     0,     0,     0,     0,     0,     0,
     117,    96,    97,    98,    99,   100,   101,   102,   103,   104,
       0,     0,     0,     0,     0,     0,     0,     0,     0,   105,
       0,     0,     0,   106,   107,   108,   109,   110,   111,     0,
       0,     0,     0,     0,     0,   186,    96,    97,    98,    99,
     100,   101,   102,   103,   104,     0,     0,     0,     0,     0,
       0,     0,     0,     0,   105,     0,     0,     0,   106,   107,
     108,   109,   110,   111,     0,     0,     0,     0,     0,     0,
     192,    96,    97,    98,    99,   100,   101,   102,   103,   104,
       0,     0,     0,     0,     0,     0,     0,     0,     0,   105,
       0,     0,     0,   106,   107,   108,   109,   110,   111,     0,
       0,     0,     0,     0,     0,   198,    96,    97,    98,    99,
     100,   101,   102,   103,   104,     0,     0,     0,     0,     0,
       0,     0,     0,     0,   105,     0,     0,     0,   106,   107,
     108,   109,   110,   111,     0,     0,     0,     0,     0,     0,
     202,    96,    97,    98,    99,   100,   101,   102,   103,   104,
       0,     0,     0,     0,     0,     0,     0,     0,     0,   105,
       0,     0,     0,   106,   107,   108,   109,   110,   111,   248,
       0,     0,     0,     0,     0,   233,    96,    97,    98,    99,
     100,   101,   102,   103,   104,     0,     0,     0,     0,     0,
       0,     0,     0,     0,   105,     0,     0,     0,   106,   107,
     108,   109,   110,   111,    96,    97,    98,    99,   100,   101,
     102,   103,   104,     0,     0,     0,     0,     0,     0,     0,
       0,     0,   105,     0,     0,     0,   106,   107,   108,   109,
     110,   111,     0,     0,     0,     0,     0,   145,    96,    97,
      98,    99,   100,   101,   102,   103,   104,     0,     0,   245,
       0,     0,     0,     0,     0,     0,   105,     0,     0,     0,
     106,   107,   108,   109,   110,   111,     0,     0,     0,     0,
     246,    96,    97,    98,    99,   100,   101,   102,   103,   104,
       0,     0,     0,     0,     0,     0,     0,     0,     0,   105,
       0,     0,     0,   106,   107,   108,   109,   110,   111,     0,
       0,     0,     0,   207,    96,    97,    98,    99,   100,   101,
     102,   103,   104,     0,     0,   122,     0,     0,     0,     0,
       0,     0,   105,     0,     0,     0,   106,   107,   108,   109,
     110,   111,    96,    97,    98,    99,   100,   101,   102,   103,
     104,     0,     0,   262,     0,     0,     0,     0,     0,     0,
     105,     0,     0,     0,   106,   107,   108,   109,   110,   111,
      96,    97,    98,    99,   100,   101,   102,   103,   104,     0,
       0,     0,     0,     0,     0,     0,     0,     0,   105,     0,
       0,     0,   106,   107,   108,   109,   110,   111,    96,     0,
      98,    99,   100,   101,   102,   103,   104,     0,     0,     0,
       0,     0,     0,     0,     0,     0,   105,     0,     0,     0,
     106,   107,   108,   109,   110,   111,    98,    99,   100,   101,
     102,   103,   104,     0,     0,     0,     0,     0,     0,     0,
       0,     0,   105,     0,     0,     0,   106,   107,   108,   109,
     110,   111
};

static const yytype_int16 yycheck[] =
{
       0,    78,     4,     4,   121,    57,     4,    12,     4,     4,
      35,    63,    35,    56,    14,    15,    73,    20,    60,    21,
      20,    57,     0,    23,    24,    61,     3,     4,     5,    36,
      60,     0,    57,    58,    57,    60,    14,    15,     0,     3,
       4,     5,    20,     4,    21,    23,    15,    12,    44,    44,
      57,    20,    57,    58,    23,   172,   113,    21,    60,    60,
      37,    38,    60,    40,    41,    42,    69,    44,   125,    69,
      12,    48,    72,    37,    38,    57,    40,    41,    42,    61,
      44,    57,    58,    60,    48,    62,   203,   204,    56,    53,
      57,    69,    57,    58,    61,    15,    60,    14,    62,    63,
      69,    56,    17,    23,    19,   222,   223,    24,    54,    55,
       5,   188,   189,     5,    60,    57,    58,    43,    60,     9,
      10,    33,   122,    49,    50,    51,    52,   127,     3,     4,
       5,    43,    53,    54,    55,    47,    48,    49,    50,    51,
      52,    54,    55,    57,   122,     4,    21,    60,    20,   127,
      53,    54,    55,   122,    53,    54,    55,    60,   127,    60,
      57,    60,    37,    38,    61,    40,    41,    42,    56,    44,
      53,    54,    55,    48,    53,    54,    55,    60,    53,    60,
      46,    60,    53,    54,    55,    60,     4,    62,    63,    60,
      57,    53,    54,    55,    61,     4,    57,   197,    60,    57,
      61,    61,   122,    61,    61,   205,     4,   127,   208,    57,
     210,    57,    57,    61,    57,    61,    61,    52,    61,   197,
      53,    54,    55,     4,   224,     4,     4,   205,   197,    60,
     208,    60,   210,     4,     4,    60,   205,    60,    20,   208,
       4,   210,   242,   243,    58,   245,   224,    60,   248,   249,
     250,    20,    60,    20,    20,   224,    -1,    20,    20,    20,
      20,    20,   262,    20,   242,   243,    20,   245,    20,    20,
     248,   249,   250,   242,   243,   256,   245,   197,   146,   248,
     249,   250,    -1,    -1,   262,   205,    17,    -1,   208,    -1,
     210,    22,    -1,   262,    25,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    34,   224,    -1,    -1,    -1,    -1,    -1,
      -1,    42,    43,    -1,    -1,    -1,    -1,    48,    49,    -1,
      -1,    -1,   242,   243,    -1,   245,    -1,    -1,   248,   249,
     250,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      71,    -1,   262,    -1,    75,    -1,    -1,    78,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    87,    -1,    -1,    -1,
      -1,    -1,    93,    94,    -1,    96,    97,    98,    99,   100,
     101,   102,   103,   104,   105,   106,   107,   108,   109,   110,
     111,    -1,    -1,   114,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,   123,   124,    -1,    -1,    -1,    -1,    -1,     4,
      -1,     6,     7,     8,    -1,    -1,    11,   138,    13,    14,
      15,    16,    -1,    18,   145,   146,    21,    22,    23,    24,
      25,    26,    27,    28,    29,    30,    31,    32,    33,    34,
      -1,    36,    -1,    -1,    -1,    -1,    -1,    -1,    43,    -1,
      45,    -1,    47,    48,    49,    50,    51,    52,    -1,    -1,
      -1,    -1,    -1,   184,    -1,    60,   187,   188,   189,    -1,
      -1,    -1,     4,    -1,     6,     7,     8,    -1,    -1,    11,
      -1,    13,    14,    15,    16,    -1,   207,    -1,   209,    21,
      22,    23,    24,   214,    -1,    -1,    -1,   218,    -1,    -1,
      -1,    -1,    34,    -1,    36,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    45,    25,    26,    27,    28,    29,    30,
      31,    32,    33,    -1,    -1,   246,    -1,    -1,    60,    -1,
      -1,    -1,    43,    -1,    -1,    -1,    47,    48,    49,    50,
      51,    52,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      61,    25,    26,    27,    28,    29,    30,    31,    32,    33,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    43,
      -1,    -1,    -1,    47,    48,    49,    50,    51,    52,    -1,
      -1,    -1,    -1,    -1,    -1,    59,    25,    26,    27,    28,
      29,    30,    31,    32,    33,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    43,    -1,    -1,    -1,    47,    48,
      49,    50,    51,    52,    -1,    -1,    -1,    -1,    -1,    -1,
      59,    25,    26,    27,    28,    29,    30,    31,    32,    33,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    43,
      -1,    -1,    -1,    47,    48,    49,    50,    51,    52,    -1,
      -1,    -1,    -1,    -1,    -1,    59,    25,    26,    27,    28,
      29,    30,    31,    32,    33,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    43,    -1,    -1,    -1,    47,    48,
      49,    50,    51,    52,    -1,    -1,    -1,    -1,    -1,    -1,
      59,    25,    26,    27,    28,    29,    30,    31,    32,    33,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    43,
      -1,    -1,    -1,    47,    48,    49,    50,    51,    52,    18,
      -1,    -1,    -1,    -1,    -1,    59,    25,    26,    27,    28,
      29,    30,    31,    32,    33,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    43,    -1,    -1,    -1,    47,    48,
      49,    50,    51,    52,    25,    26,    27,    28,    29,    30,
      31,    32,    33,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    43,    -1,    -1,    -1,    47,    48,    49,    50,
      51,    52,    -1,    -1,    -1,    -1,    -1,    58,    25,    26,
      27,    28,    29,    30,    31,    32,    33,    -1,    -1,    36,
      -1,    -1,    -1,    -1,    -1,    -1,    43,    -1,    -1,    -1,
      47,    48,    49,    50,    51,    52,    -1,    -1,    -1,    -1,
      57,    25,    26,    27,    28,    29,    30,    31,    32,    33,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    43,
      -1,    -1,    -1,    47,    48,    49,    50,    51,    52,    -1,
      -1,    -1,    -1,    57,    25,    26,    27,    28,    29,    30,
      31,    32,    33,    -1,    -1,    36,    -1,    -1,    -1,    -1,
      -1,    -1,    43,    -1,    -1,    -1,    47,    48,    49,    50,
      51,    52,    25,    26,    27,    28,    29,    30,    31,    32,
      33,    -1,    -1,    36,    -1,    -1,    -1,    -1,    -1,    -1,
      43,    -1,    -1,    -1,    47,    48,    49,    50,    51,    52,
      25,    26,    27,    28,    29,    30,    31,    32,    33,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    43,    -1,
      -1,    -1,    47,    48,    49,    50,    51,    52,    25,    -1,
      27,    28,    29,    30,    31,    32,    33,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    43,    -1,    -1,    -1,
      47,    48,    49,    50,    51,    52,    27,    28,    29,    30,
      31,    32,    33,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    43,    -1,    -1,    -1,    47,    48,    49,    50,
      51,    52
};

/* YYSTOS[STATE-NUM] -- The symbol kind of the accessing symbol of
   state STATE-NUM.  */
static const yytype_int8 yystos[] =
{
       0,     4,     6,     7,     8,    11,    13,    14,    15,    16,
      21,    22,    23,    24,    34,    36,    45,    60,    65,    66,
      67,    70,    71,    72,    73,    74,    75,    76,    78,    80,
      81,    82,    84,    88,    60,    89,    56,    60,    60,     3,
       4,     5,    37,    38,    40,    41,    42,    44,    48,    62,
      70,    79,    82,    83,    84,    87,    70,    78,    82,    66,
      83,     0,    75,    76,     4,    83,    66,     4,    78,    83,
      56,    12,    57,    58,    56,    53,    54,    55,    60,    69,
      83,    90,     5,     5,    83,    83,    83,    53,    63,    83,
      85,    86,    60,    57,    53,    54,    25,    26,    27,    28,
      29,    30,    31,    32,    33,    43,    47,    48,    49,    50,
      51,    52,     4,    58,    53,    54,    20,    61,    56,    54,
      55,    60,    36,    46,    58,    35,    15,    18,    24,    75,
      83,     4,    82,    79,    83,     4,     4,    69,    57,    61,
       9,    10,    61,    61,    83,    58,    57,    63,     4,    44,
      68,    83,    83,     4,    83,    83,    83,    83,    83,    83,
      83,    83,    83,    83,    83,    83,    83,    83,    83,    83,
      54,    55,    60,    79,    83,     4,     4,     4,    68,    66,
      83,    83,    79,    66,    53,    54,    59,    58,    60,    60,
      61,    83,    59,    83,    63,    85,    57,    61,    59,     4,
       4,    68,    59,    60,    60,    61,    20,    57,    36,    17,
      19,    77,    83,     4,    58,    83,    69,    69,    58,     4,
      44,    66,    60,    60,    61,    68,    68,    66,    83,    66,
      83,    66,    20,    59,    83,    61,    61,    83,    20,    68,
      68,    66,    61,    61,    20,    36,    57,    20,    18,    61,
      61,    20,    66,    66,    66,    83,    66,    66,    66,    20,
      20,    20,    36,    77,    20,    20,    66,    20
};

/* YYR1[RULE-NUM] -- Symbol kind of the left-hand side of rule RULE-NUM.  */
static const yytype_int8 yyr1[] =
{
       0,    64,    65,    66,    66,    66,    66,    67,    67,    67,
      67,    68,    68,    68,    68,    68,    69,    69,    69,    70,
      71,    72,    73,    74,    75,    75,    75,    75,    75,    75,
      75,    75,    75,    75,    75,    75,    75,    75,    75,    75,
      75,    75,    75,    75,    75,    75,    75,    75,    75,    75,
      75,    76,    76,    76,    76,    77,    77,    77,    78,    78,
      78,    78,    78,    78,    79,    79,    80,    80,    80,    81,
      81,    82,    82,    82,    82,    82,    83,    83,    83,    83,
      83,    83,    83,    83,    83,    83,    83,    83,    83,    83,
      83,    83,    83,    83,    83,    83,    83,    83,    83,    83,
      83,    83,    83,    83,    84,    84,    84,    84,    85,    85,
      85,    86,    86,    87,    87,    87,    89,    88,    90,    90
};

/* YYR2[RULE-NUM] -- Number of symbols on the right-hand side of rule RULE-NUM.  */
static const yytype_int8 yyr2[] =
{
       0,     2,     1,     0,     1,     2,     1,     2,     3,     1,
       2,     0,     1,     1,     3,     3,     0,     1,     3,     1,
       1,     1,     1,     1,     1,     3,     4,     3,     6,     5,
       5,     4,     9,    11,     7,     6,     3,     3,     3,     3,
       2,     1,     4,     8,    10,    10,     4,     1,     1,     1,
       1,     1,     2,     1,     2,     0,     2,     5,     1,     3,
       4,     3,     5,     6,     1,     3,     7,     9,     9,     2,
       1,     1,     1,     3,     4,     3,     1,     1,     1,     1,
       1,     3,     3,     3,     3,     3,     3,     3,     1,     1,
       1,     2,     2,     2,     3,     3,     3,     3,     3,     3,
       3,     3,     3,     6,     4,     6,     6,     4,     1,     3,
       5,     1,     3,     2,     3,     4,     0,     4,     0,     2
};


enum { YYENOMEM = -2 };

#define yyerrok         (yyerrstatus = 0)
#define yyclearin       (yychar = YYEMPTY)

#define YYACCEPT        goto yyacceptlab
#define YYABORT         goto yyabortlab
#define YYERROR         goto yyerrorlab
#define YYNOMEM         goto yyexhaustedlab


#define YYRECOVERING()  (!!yyerrstatus)

#define YYBACKUP(Token, Value)                                    \
  do                                                              \
    if (yychar == YYEMPTY)                                        \
      {                                                           \
        yychar = (Token);                                         \
        yylval = (Value);                                         \
        YYPOPSTACK (yylen);                                       \
        yystate = *yyssp;                                         \
        goto yybackup;                                            \
      }                                                           \
    else                                                          \
      {                                                           \
        yyerror (YY_("syntax error: cannot back up")); \
        YYERROR;                                                  \
      }                                                           \
  while (0)

/* Backward compatibility with an undocumented macro.
   Use YYerror or YYUNDEF. */
#define YYERRCODE YYUNDEF


/* Enable debugging if requested.  */
#if YYDEBUG

# ifndef YYFPRINTF
#  include <stdio.h> /* INFRINGES ON USER NAME SPACE */
#  define YYFPRINTF fprintf
# endif

# define YYDPRINTF(Args)                        \
do {                                            \
  if (yydebug)                                  \
    YYFPRINTF Args;                             \
} while (0)




# define YY_SYMBOL_PRINT(Title, Kind, Value, Location)                    \
do {                                                                      \
  if (yydebug)                                                            \
    {                                                                     \
      YYFPRINTF (stderr, "%s ", Title);                                   \
      yy_symbol_print (stderr,                                            \
                  Kind, Value); \
      YYFPRINTF (stderr, "\n");                                           \
    }                                                                     \
} while (0)


/*-----------------------------------.
| Print this symbol's value on YYO.  |
`-----------------------------------*/

static void
yy_symbol_value_print (FILE *yyo,
                       yysymbol_kind_t yykind, YYSTYPE const * const yyvaluep)
{
  FILE *yyoutput = yyo;
  YY_USE (yyoutput);
  if (!yyvaluep)
    return;
  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  YY_USE (yykind);
  YY_IGNORE_MAYBE_UNINITIALIZED_END
}


/*---------------------------.
| Print this symbol on YYO.  |
`---------------------------*/

static void
yy_symbol_print (FILE *yyo,
                 yysymbol_kind_t yykind, YYSTYPE const * const yyvaluep)
{
  YYFPRINTF (yyo, "%s %s (",
             yykind < YYNTOKENS ? "token" : "nterm", yysymbol_name (yykind));

  yy_symbol_value_print (yyo, yykind, yyvaluep);
  YYFPRINTF (yyo, ")");
}

/*------------------------------------------------------------------.
| yy_stack_print -- Print the state stack from its BOTTOM up to its |
| TOP (included).                                                   |
`------------------------------------------------------------------*/

static void
yy_stack_print (yy_state_t *yybottom, yy_state_t *yytop)
{
  YYFPRINTF (stderr, "Stack now");
  for (; yybottom <= yytop; yybottom++)
    {
      int yybot = *yybottom;
      YYFPRINTF (stderr, " %d", yybot);
    }
  YYFPRINTF (stderr, "\n");
}

# define YY_STACK_PRINT(Bottom, Top)                            \
do {                                                            \
  if (yydebug)                                                  \
    yy_stack_print ((Bottom), (Top));                           \
} while (0)


/*------------------------------------------------.
| Report that the YYRULE is going to be reduced.  |
`------------------------------------------------*/

static void
yy_reduce_print (yy_state_t *yyssp, YYSTYPE *yyvsp,
                 int yyrule)
{
  int yylno = yyrline[yyrule];
  int yynrhs = yyr2[yyrule];
  int yyi;
  YYFPRINTF (stderr, "Reducing stack by rule %d (line %d):\n",
             yyrule - 1, yylno);
  /* The symbols being reduced.  */
  for (yyi = 0; yyi < yynrhs; yyi++)
    {
      YYFPRINTF (stderr, "   $%d = ", yyi + 1);
      yy_symbol_print (stderr,
                       YY_ACCESSING_SYMBOL (+yyssp[yyi + 1 - yynrhs]),
                       &yyvsp[(yyi + 1) - (yynrhs)]);
      YYFPRINTF (stderr, "\n");
    }
}

# define YY_REDUCE_PRINT(Rule)          \
do {                                    \
  if (yydebug)                          \
    yy_reduce_print (yyssp, yyvsp, Rule); \
} while (0)

/* Nonzero means print parse trace.  It is left uninitialized so that
   multiple parsers can coexist.  */
int yydebug;
#else /* !YYDEBUG */
# define YYDPRINTF(Args) ((void) 0)
# define YY_SYMBOL_PRINT(Title, Kind, Value, Location)
# define YY_STACK_PRINT(Bottom, Top)
# define YY_REDUCE_PRINT(Rule)
#endif /* !YYDEBUG */


/* YYINITDEPTH -- initial size of the parser's stacks.  */
#ifndef YYINITDEPTH
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






/*-----------------------------------------------.
| Release the memory associated to this symbol.  |
`-----------------------------------------------*/

static void
yydestruct (const char *yymsg,
            yysymbol_kind_t yykind, YYSTYPE *yyvaluep)
{
  YY_USE (yyvaluep);
  if (!yymsg)
    yymsg = "Deleting";
  YY_SYMBOL_PRINT (yymsg, yykind, yyvaluep, yylocationp);

  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  YY_USE (yykind);
  YY_IGNORE_MAYBE_UNINITIALIZED_END
}


/* Lookahead token kind.  */
int yychar;

/* The semantic value of the lookahead symbol.  */
YYSTYPE yylval;
/* Number of syntax errors so far.  */
int yynerrs;




/*----------.
| yyparse.  |
`----------*/

int
yyparse (void)
{
    yy_state_fast_t yystate = 0;
    /* Number of tokens to shift before error messages enabled.  */
    int yyerrstatus = 0;

    /* Refer to the stacks through separate pointers, to allow yyoverflow
       to reallocate them elsewhere.  */

    /* Their size.  */
    YYPTRDIFF_T yystacksize = YYINITDEPTH;

    /* The state stack: array, bottom, top.  */
    yy_state_t yyssa[YYINITDEPTH];
    yy_state_t *yyss = yyssa;
    yy_state_t *yyssp = yyss;

    /* The semantic value stack: array, bottom, top.  */
    YYSTYPE yyvsa[YYINITDEPTH];
    YYSTYPE *yyvs = yyvsa;
    YYSTYPE *yyvsp = yyvs;

  int yyn;
  /* The return value of yyparse.  */
  int yyresult;
  /* Lookahead symbol kind.  */
  yysymbol_kind_t yytoken = YYSYMBOL_YYEMPTY;
  /* The variables used to return semantic value and location from the
     action routines.  */
  YYSTYPE yyval;



#define YYPOPSTACK(N)   (yyvsp -= (N), yyssp -= (N))

  /* The number of symbols on the RHS of the reduced rule.
     Keep to zero when no symbol should be popped.  */
  int yylen = 0;

  YYDPRINTF ((stderr, "Starting parse\n"));

  yychar = YYEMPTY; /* Cause a token to be read.  */

  goto yysetstate;


/*------------------------------------------------------------.
| yynewstate -- push a new state, which is found in yystate.  |
`------------------------------------------------------------*/
yynewstate:
  /* In all cases, when you get here, the value and location stacks
     have just been pushed.  So pushing a state here evens the stacks.  */
  yyssp++;


/*--------------------------------------------------------------------.
| yysetstate -- set current state (the top of the stack) to yystate.  |
`--------------------------------------------------------------------*/
yysetstate:
  YYDPRINTF ((stderr, "Entering state %d\n", yystate));
  YY_ASSERT (0 <= yystate && yystate < YYNSTATES);
  YY_IGNORE_USELESS_CAST_BEGIN
  *yyssp = YY_CAST (yy_state_t, yystate);
  YY_IGNORE_USELESS_CAST_END
  YY_STACK_PRINT (yyss, yyssp);

  if (yyss + yystacksize - 1 <= yyssp)
#if !defined yyoverflow && !defined YYSTACK_RELOCATE
    YYNOMEM;
#else
    {
      /* Get the current used size of the three stacks, in elements.  */
      YYPTRDIFF_T yysize = yyssp - yyss + 1;

# if defined yyoverflow
      {
        /* Give user a chance to reallocate the stack.  Use copies of
           these so that the &'s don't force the real ones into
           memory.  */
        yy_state_t *yyss1 = yyss;
        YYSTYPE *yyvs1 = yyvs;

        /* Each stack pointer address is followed by the size of the
           data in use in that stack, in bytes.  This used to be a
           conditional around just the two extra args, but that might
           be undefined if yyoverflow is a macro.  */
        yyoverflow (YY_("memory exhausted"),
                    &yyss1, yysize * YYSIZEOF (*yyssp),
                    &yyvs1, yysize * YYSIZEOF (*yyvsp),
                    &yystacksize);
        yyss = yyss1;
        yyvs = yyvs1;
      }
# else /* defined YYSTACK_RELOCATE */
      /* Extend the stack our own way.  */
      if (YYMAXDEPTH <= yystacksize)
        YYNOMEM;
      yystacksize *= 2;
      if (YYMAXDEPTH < yystacksize)
        yystacksize = YYMAXDEPTH;

      {
        yy_state_t *yyss1 = yyss;
        union yyalloc *yyptr =
          YY_CAST (union yyalloc *,
                   YYSTACK_ALLOC (YY_CAST (YYSIZE_T, YYSTACK_BYTES (yystacksize))));
        if (! yyptr)
          YYNOMEM;
        YYSTACK_RELOCATE (yyss_alloc, yyss);
        YYSTACK_RELOCATE (yyvs_alloc, yyvs);
#  undef YYSTACK_RELOCATE
        if (yyss1 != yyssa)
          YYSTACK_FREE (yyss1);
      }
# endif

      yyssp = yyss + yysize - 1;
      yyvsp = yyvs + yysize - 1;

      YY_IGNORE_USELESS_CAST_BEGIN
      YYDPRINTF ((stderr, "Stack size increased to %ld\n",
                  YY_CAST (long, yystacksize)));
      YY_IGNORE_USELESS_CAST_END

      if (yyss + yystacksize - 1 <= yyssp)
        YYABORT;
    }
#endif /* !defined yyoverflow && !defined YYSTACK_RELOCATE */


  if (yystate == YYFINAL)
    YYACCEPT;

  goto yybackup;


/*-----------.
| yybackup.  |
`-----------*/
yybackup:
  /* Do appropriate processing given the current state.  Read a
     lookahead token if we need one and don't already have one.  */

  /* First try to decide what to do without reference to lookahead token.  */
  yyn = yypact[yystate];
  if (yypact_value_is_default (yyn))
    goto yydefault;

  /* Not known => get a lookahead token if don't already have one.  */

  /* YYCHAR is either empty, or end-of-input, or a valid lookahead.  */
  if (yychar == YYEMPTY)
    {
      YYDPRINTF ((stderr, "Reading a token\n"));
      yychar = yylex ();
    }

  if (yychar <= YYEOF)
    {
      yychar = YYEOF;
      yytoken = YYSYMBOL_YYEOF;
      YYDPRINTF ((stderr, "Now at end of input.\n"));
    }
  else if (yychar == YYerror)
    {
      /* The scanner already issued an error message, process directly
         to error recovery.  But do not keep the error token as
         lookahead, it is too special and may lead us to an endless
         loop in error recovery. */
      yychar = YYUNDEF;
      yytoken = YYSYMBOL_YYerror;
      goto yyerrlab1;
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
      if (yytable_value_is_error (yyn))
        goto yyerrlab;
      yyn = -yyn;
      goto yyreduce;
    }

  /* Count tokens shifted since error; after three, turn off error
     status.  */
  if (yyerrstatus)
    yyerrstatus--;

  /* Shift the lookahead token.  */
  YY_SYMBOL_PRINT ("Shifting", yytoken, &yylval, &yylloc);
  yystate = yyn;
  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  *++yyvsp = yylval;
  YY_IGNORE_MAYBE_UNINITIALIZED_END

  /* Discard the shifted token.  */
  yychar = YYEMPTY;
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
| yyreduce -- do a reduction.  |
`-----------------------------*/
yyreduce:
  /* yyn is the number of a rule to reduce with.  */
  yylen = yyr2[yyn];

  /* If YYLEN is nonzero, implement the default value of the action:
     '$$ = $1'.

     Otherwise, the following line sets YYVAL to garbage.
     This behavior is undocumented and Bison
     users should not rely upon it.  Assigning to YYVAL
     unconditionally makes the parser a bit smaller, and it avoids a
     GCC warning that YYVAL may be used uninitialized.  */
  yyval = yyvsp[1-yylen];


  YY_REDUCE_PRINT (yyn);
  switch (yyn)
    {
  case 2: /* program: statement_list  */
#line 73 "src/parser.y"
    {
        root_node = (yyvsp[0].ast_node); // Captures the entire AST root for main.c to use later
    }
#line 1487 "src/parser.c"
    break;

  case 3: /* statement_list: %empty  */
#line 79 "src/parser.y"
                { (yyval.ast_node) = NULL; }
#line 1493 "src/parser.c"
    break;

  case 4: /* statement_list: stat_list  */
#line 80 "src/parser.y"
                { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 1499 "src/parser.c"
    break;

  case 5: /* statement_list: stat_list last_statement  */
#line 81 "src/parser.y"
                               {
        if ((yyvsp[-1].ast_node) == NULL) { 
            (yyval.ast_node) = (yyvsp[0].ast_node); 
        } else {
            ASTNode *current = (yyvsp[-1].ast_node);
            while (current->next != NULL) {
                current = current->next;
            }
            current->next = (yyvsp[0].ast_node);
            (yyval.ast_node) = (yyvsp[-1].ast_node);
        }
    }
#line 1516 "src/parser.c"
    break;

  case 6: /* statement_list: last_statement  */
#line 93 "src/parser.y"
                     { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 1522 "src/parser.c"
    break;

  case 7: /* stat_list: statement ';'  */
#line 97 "src/parser.y"
                    { (yyval.ast_node) = (yyvsp[-1].ast_node); }
#line 1528 "src/parser.c"
    break;

  case 8: /* stat_list: stat_list statement ';'  */
#line 98 "src/parser.y"
                              {
        if ((yyvsp[-2].ast_node) == NULL) {
            (yyval.ast_node) = (yyvsp[-1].ast_node);
        } else {
            ASTNode *current = (yyvsp[-2].ast_node);
            while (current->next != NULL) {
                current = current->next;
            }
            current->next = (yyvsp[-1].ast_node);
            (yyval.ast_node) = (yyvsp[-2].ast_node);
        }
    }
#line 1545 "src/parser.c"
    break;

  case 9: /* stat_list: statement  */
#line 110 "src/parser.y"
                { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 1551 "src/parser.c"
    break;

  case 10: /* stat_list: stat_list statement  */
#line 111 "src/parser.y"
                          {
        if ((yyvsp[-1].ast_node) == NULL) { 
            (yyval.ast_node) = (yyvsp[0].ast_node); 
        } else {
            ASTNode *current = (yyvsp[-1].ast_node);
            while (current->next != NULL) {
                current = current->next;
            }
            current->next = (yyvsp[0].ast_node);
            (yyval.ast_node) = (yyvsp[-1].ast_node);
        }
    }
#line 1568 "src/parser.c"
    break;

  case 11: /* parameter_list: %empty  */
#line 126 "src/parser.y"
                {
        (yyval.ast_node) = NULL;
    }
#line 1576 "src/parser.c"
    break;

  case 12: /* parameter_list: TOKEN_IDENTIFIER  */
#line 129 "src/parser.y"
                       {
        (yyval.ast_node) = make_node_ident((yyvsp[0].string_val));
    }
#line 1584 "src/parser.c"
    break;

  case 13: /* parameter_list: TOKEN_DOTS  */
#line 132 "src/parser.y"
                 {
        // Create a marker identifier - will be detected in function_def
        (yyval.ast_node) = make_node_ident("...");
    }
#line 1593 "src/parser.c"
    break;

  case 14: /* parameter_list: parameter_list ',' TOKEN_IDENTIFIER  */
#line 136 "src/parser.y"
                                          {
        ASTNode* new_node = make_node_ident((yyvsp[0].string_val));
        ASTNode* current = (yyvsp[-2].ast_node);
        while(current->next) current = current->next;
        current->next = new_node;
        (yyval.ast_node) = (yyvsp[-2].ast_node);
    }
#line 1605 "src/parser.c"
    break;

  case 15: /* parameter_list: parameter_list ',' TOKEN_DOTS  */
#line 143 "src/parser.y"
                                    {
        ASTNode* new_node = make_node_ident("...");
        ASTNode* current = (yyvsp[-2].ast_node);
        while(current->next) current = current->next;
        current->next = new_node;
        (yyval.ast_node) = (yyvsp[-2].ast_node);
    }
#line 1617 "src/parser.c"
    break;

  case 16: /* argument_list: %empty  */
#line 153 "src/parser.y"
                { 
        (yyval.ast_node) = NULL;
    }
#line 1625 "src/parser.c"
    break;

  case 17: /* argument_list: expr  */
#line 156 "src/parser.y"
           { 
        (yyval.ast_node) = (yyvsp[0].ast_node);
    }
#line 1633 "src/parser.c"
    break;

  case 18: /* argument_list: argument_list ',' expr  */
#line 159 "src/parser.y"
                             {
        // Chain the new expression to the end of the argument list
        ASTNode* current = (yyvsp[-2].ast_node);
        while (current->next != NULL) {
            current = current->next;
        }
        current->next = (yyvsp[0].ast_node);
        (yyval.ast_node) = (yyvsp[-2].ast_node);
    }
#line 1647 "src/parser.c"
    break;

  case 19: /* func_start: TOKEN_FUNCTION  */
#line 172 "src/parser.y"
                   { (yyval.ast_node) = make_node(NODE_FUNCTION_DEF); }
#line 1653 "src/parser.c"
    break;

  case 20: /* while_start: TOKEN_WHILE  */
#line 176 "src/parser.y"
                   { (yyval.ast_node) = make_node(NODE_WHILE); }
#line 1659 "src/parser.c"
    break;

  case 21: /* repeat_start: TOKEN_REPEAT  */
#line 180 "src/parser.y"
                   { (yyval.ast_node) = make_node(NODE_REPEAT); }
#line 1665 "src/parser.c"
    break;

  case 22: /* for_start: TOKEN_FOR  */
#line 184 "src/parser.y"
                   { (yyval.ast_node) = make_node(NODE_FOR_NUMERIC); }
#line 1671 "src/parser.c"
    break;

  case 23: /* if_start: TOKEN_IF  */
#line 187 "src/parser.y"
                   { (yyval.ast_node) = make_node(NODE_IF); }
#line 1677 "src/parser.c"
    break;

  case 24: /* statement: function_call  */
#line 191 "src/parser.y"
                                 { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 1683 "src/parser.c"
    break;

  case 25: /* statement: var_list '=' expr_list  */
#line 192 "src/parser.y"
                             {
        (yyval.ast_node) = make_node(NODE_MULTIPLE_ASSIGNMENT);
        (yyval.ast_node)->as.mult_assign.targets_head = (yyvsp[-2].ast_node);
        (yyval.ast_node)->as.mult_assign.values_head = (yyvsp[0].ast_node);
        (yyval.ast_node)->as.mult_assign.is_local = 0;
    }
#line 1694 "src/parser.c"
    break;

  case 26: /* statement: TOKEN_LOCAL var_list '=' expr_list  */
#line 198 "src/parser.y"
                                         {
        (yyval.ast_node) = make_node(NODE_MULTIPLE_ASSIGNMENT);
        (yyval.ast_node)->as.mult_assign.targets_head = (yyvsp[-2].ast_node);
        (yyval.ast_node)->as.mult_assign.values_head = (yyvsp[0].ast_node);
        (yyval.ast_node)->as.mult_assign.is_local = 1;
    }
#line 1705 "src/parser.c"
    break;

  case 27: /* statement: var_list TOKEN_COMPOUND_ASSIGN expr  */
#line 204 "src/parser.y"
                                          {
        // PICO-8-only += -= *= /= %=. Gating already happened in the
        // lexer (compound_assign_token() in lexer.l) the moment the
        // operator token itself was recognized, so nothing to check here.
        //
        // var_list is reused rather than introducing a separate
        // single-target nonterminal: var_list's first three productions
        // (bare identifier, '.field', '[index]') are exactly the three
        // PICO-8 compound-assignment target shapes, and a parallel
        // nonterminal with the identical production shapes would create a
        // reduce-reduce conflict (after shifting TOKEN_IDENTIFIER, the
        // parser would have two different single-token rules it could
        // reduce into, with no lookahead able to distinguish them). Reusing
        // var_list means there's only one reduction, and the choice of
        // which statement rule continues from it (this one, the plain '='
        // rule, or the ',' multi-target continuation) is an ordinary
        // lookahead-driven shift decision, not a reduce-reduce choice.
        // The tradeoff is that var_list also accepts a comma-separated
        // multi-target list, which real PICO-8 compound assignment does
        // not support -- rejected below instead, with a clear message
        // rather than a parse failure.
        if ((yyvsp[-2].ast_node)->next != NULL) {
            compiler_error(ERR_SYNTAX, yylineno,
                "compound assignment (+=, -=, *=, /=, %%=) only supports a single target");
        }

        NodeType op = (NodeType)(int) (yyvsp[-1].number_val);

        if ((yyvsp[-2].ast_node)->type == NODE_IDENTIFIER) {
            // lhs = lhs OP rhs, via the exact same plain-assignment path
            // 'var_list = expr_list' above already uses -- $1 becomes
            // the (single) write target, and a second, independent
            // make_node_ident() with the same name is the read reference
            // embedded in the RHS. Safe to duplicate: an identifier read
            // has no side effects, so evaluating the name twice is free.
            ASTNode *read_ref = make_node_ident((yyvsp[-2].ast_node)->as.id.name);
            ASTNode *new_val  = make_node_binary(op, read_ref, (yyvsp[0].ast_node));

            (yyval.ast_node) = make_node(NODE_MULTIPLE_ASSIGNMENT);
            (yyval.ast_node)->as.mult_assign.targets_head = (yyvsp[-2].ast_node);
            (yyval.ast_node)->as.mult_assign.values_head  = new_val;
            (yyval.ast_node)->as.mult_assign.is_local     = 0;
        } else {
            // NODE_TABLE_GET shape, from var_list's '.'/'[' productions:
            // t.field OP= rhs  desugars to  t.field = t.field OP rhs,
            // via the same make_node_table_set() the plain
            // 'prefix_expr . TOKEN_IDENTIFIER = expr' statement
            // rule uses.
            //
            // KNOWN LIMITATION: table_expr (and, for the '[' form, the key
            // expression) is evaluated once by the read side and once by
            // the write side below -- fine for the common case (a plain
            // variable or a chain of plain field accesses, which is every
            // occurrence in celeste.lua), but if table_expr itself has a
            // side effect (e.g. get_obj().x += 1), that side effect runs
            // TWICE. Deliberately out of scope for now: fixing it for the
            // general case needs a dedicated AST node + codegen that
            // evaluates the table pointer once and reuses it for both the
            // read and the write, rather than this parse-time desugar.
            ASTNode *table_expr = (yyvsp[-2].ast_node)->as.table_get.table_expr;
            ASTNode *key        = (yyvsp[-2].ast_node)->as.table_get.key;

            ASTNode *read_ref = make_node_table_get(table_expr, key);
            ASTNode *new_val  = make_node_binary(op, read_ref, (yyvsp[0].ast_node));

            (yyval.ast_node) = make_node_table_set(table_expr, key, new_val);
        }
    }
#line 1778 "src/parser.c"
    break;

  case 28: /* statement: prefix_expr '[' expr ']' '=' expr  */
#line 273 "src/parser.y"
    { 
        // $1 = table, $3 = key, $6 = value being assigned
        (yyval.ast_node) = make_node_table_set ((yyvsp[-5].ast_node), (yyvsp[-3].ast_node), (yyvsp[0].ast_node)); 
    }
#line 1787 "src/parser.c"
    break;

  case 29: /* statement: prefix_expr '.' TOKEN_IDENTIFIER '=' expr  */
#line 278 "src/parser.y"
    {
        ASTNode *string_key  = make_node_string ((yyvsp[-2].string_val));
        (yyval.ast_node)                   = make_node_table_set ((yyvsp[-4].ast_node), string_key, (yyvsp[0].ast_node));
    }
#line 1796 "src/parser.c"
    break;

  case 30: /* statement: while_start expr TOKEN_DO statement_list TOKEN_END  */
#line 282 "src/parser.y"
                                                         {
        (yyval.ast_node) = (yyvsp[-4].ast_node);
        (yyval.ast_node)->as.while_loop.condition = (yyvsp[-3].ast_node);
        (yyval.ast_node)->as.while_loop.body = (yyvsp[-1].ast_node);
    }
#line 1806 "src/parser.c"
    break;

  case 31: /* statement: repeat_start statement_list TOKEN_UNTIL expr  */
#line 287 "src/parser.y"
                                                   {
        // Note the order: body ($2) is parsed BEFORE the until-condition
        // ($4) -- this matters for scoping. Lua's grammar for repeat/until
        // deliberately puts the condition after the body's closing so
        // that locals declared in the body are still in scope for it.
        // node_repeat() in the compiler mirrors this by NOT popping the
        // body's scope until after the condition has been generated.
        (yyval.ast_node) = (yyvsp[-3].ast_node);
        (yyval.ast_node)->as.repeat_loop.body      = (yyvsp[-2].ast_node);
        (yyval.ast_node)->as.repeat_loop.condition = (yyvsp[0].ast_node);
    }
#line 1822 "src/parser.c"
    break;

  case 32: /* statement: for_start TOKEN_IDENTIFIER '=' expr ',' expr TOKEN_DO statement_list TOKEN_END  */
#line 298 "src/parser.y"
                                                                                     {
        (yyval.ast_node) = make_node(NODE_FOR_NUMERIC);
        (yyval.ast_node)->as.for_numeric.index_name  = (yyvsp[-7].string_val);
        (yyval.ast_node)->as.for_numeric.start_expr  = (yyvsp[-5].ast_node);
        (yyval.ast_node)->as.for_numeric.stop_expr   = (yyvsp[-3].ast_node);
        (yyval.ast_node)->as.for_numeric.step_expr   = NULL; // Omitted step
        (yyval.ast_node)->as.for_numeric.body        = (yyvsp[-1].ast_node);
    }
#line 1835 "src/parser.c"
    break;

  case 33: /* statement: for_start TOKEN_IDENTIFIER '=' expr ',' expr ',' expr TOKEN_DO statement_list TOKEN_END  */
#line 306 "src/parser.y"
                                                                                              {
        (yyval.ast_node) = make_node(NODE_FOR_NUMERIC);
        (yyval.ast_node)->as.for_numeric.index_name  = (yyvsp[-9].string_val);
        (yyval.ast_node)->as.for_numeric.start_expr  = (yyvsp[-7].ast_node);
        (yyval.ast_node)->as.for_numeric.stop_expr   = (yyvsp[-5].ast_node);
        (yyval.ast_node)->as.for_numeric.step_expr   = (yyvsp[-3].ast_node);  // Explicit step
        (yyval.ast_node)->as.for_numeric.body        = (yyvsp[-1].ast_node);
    }
#line 1848 "src/parser.c"
    break;

  case 34: /* statement: for_start var_list TOKEN_IN expr_list TOKEN_DO statement_list TOKEN_END  */
#line 314 "src/parser.y"
                                                                              {
        (yyval.ast_node) = make_node(NODE_FOR_GENERIC);
        (yyval.ast_node)->as.for_generic.var_list    = (yyvsp[-5].ast_node);
        (yyval.ast_node)->as.for_generic.iter_expr   = (yyvsp[-3].ast_node);
        (yyval.ast_node)->as.for_generic.body        = (yyvsp[-1].ast_node);
    }
#line 1859 "src/parser.c"
    break;

  case 35: /* statement: if_start expr TOKEN_THEN statement_list else_branch TOKEN_END  */
#line 320 "src/parser.y"
                                                                    { 
        (yyval.ast_node)                             = (yyvsp[-5].ast_node);
        (yyval.ast_node) -> as.if_stmt.condition     = (yyvsp[-4].ast_node);
        (yyval.ast_node) -> as.if_stmt.if_body       = (yyvsp[-2].ast_node);
        (yyval.ast_node) -> as.if_stmt.else_body     = (yyvsp[-1].ast_node);
    }
#line 1870 "src/parser.c"
    break;

  case 36: /* statement: if_start expr statement  */
#line 326 "src/parser.y"
                              {
        // PICO-8's then-less, end-less single-statement if: `if (cond) stmt`.
        // Not standard Lua. Gated on runtime_req.needs_pico8, which is
        // already set by the time this reduces IF --#api pico8 appears
        // before this line in the source (the same single-pass ordering
        // constraint the compound-assignment tokens rely on in lexer.l).
        //
        // No ambiguity with the TOKEN_THEN rule above: after 'if_start
        // expr', the parser needs exactly one token of lookahead to
        // choose between shifting TOKEN_THEN (the rule above) and
        // reducing into 'statement' here -- TOKEN_THEN can never itself
        // start a statement, so the two never compete for the same
        // lookahead token.
        //
        // Scope: a single statement, ending wherever that statement's own
        // grammar naturally ends (Lua statements are self-delimiting; no
        // newline-tracking is needed or done). No 'elseif'/'else' in this
        // form, matching real PICO-8. Chaining multiple statements on one
        // line (if PICO-8 even allows that) is NOT supported here.
        if (!runtime_req.needs_pico8) {
            compiler_error(ERR_SYNTAX, yylineno,
                "then-less if is a PICO-8 extension; add --#api pico8 to use it");
        }
        (yyval.ast_node)                             = (yyvsp[-2].ast_node);
        (yyval.ast_node) -> as.if_stmt.condition     = (yyvsp[-1].ast_node);
        (yyval.ast_node) -> as.if_stmt.if_body       = (yyvsp[0].ast_node);
        (yyval.ast_node) -> as.if_stmt.else_body     = NULL;
    }
#line 1903 "src/parser.c"
    break;

  case 37: /* statement: if_start expr TOKEN_RETURN  */
#line 354 "src/parser.y"
                                 {
        // Bare `if (cond) return`, e.g. celeste.lua's actual line 118.
        //
        // Deliberately NOT routed through 'last_statement'/'return_stmt'
        // (an earlier version of this rule was 'if_start expr
        // last_statement', covering both bare and value-returning forms).
        // bison -Wcounterexamples caught two real ambiguities that
        // introduced: (1) return_stmt's OPTIONAL expr_list means
        // `if (x) return foo()` can't tell whether `foo()` is the
        // returned value or an unrelated statement immediately
        // following a bare return -- 'return' is only unambiguous in
        // its normal position because it's always immediately followed
        // by end/else/elseif/until/EOF, none of which can start an
        // expr_list, and this shorthand breaks that by allowing
        // arbitrary code to follow; (2) last_statement's OWN optional
        // trailing ';' (TOKEN_BREAK ';' / return_stmt ';') collided with
        // the outer stat_list: statement ';' rule over which of the two
        // gets to consume a trailing semicolon. Consuming the bare
        // TOKEN_RETURN terminal directly here, with no expr_list and no
        // semicolon-swallowing of its own, sidesteps both: nothing else
        // in the grammar has 'if_start expr TOKEN_RETURN' as a prefix,
        // so there's exactly one handle to reduce, and any trailing ';'
        // is left entirely to the ordinary stat_list: statement ';'
        // handling every other statement already goes through.
        //
        // Scope note: `if (x) return <value>` (a shorthand return WITH a
        // value) is consequently NOT supported -- write it with
        // then/end. Not a loss for celeste.lua: every then-less if in it
        // is a bare `return` with nothing after it.
        if (!runtime_req.needs_pico8) {
            compiler_error(ERR_SYNTAX, yylineno,
                "then-less if is a PICO-8 extension; add --#api pico8 to use it");
        }
        ASTNode *ret_node = make_node(NODE_RETURN);
        ret_node->as.return_stmt.expressions_head = NULL;
        ret_node->as.return_stmt.parent_func_arg_count = 0;

        (yyval.ast_node)                             = (yyvsp[-2].ast_node);
        (yyval.ast_node) -> as.if_stmt.condition     = (yyvsp[-1].ast_node);
        (yyval.ast_node) -> as.if_stmt.if_body       = ret_node;
        (yyval.ast_node) -> as.if_stmt.else_body     = NULL;
    }
#line 1950 "src/parser.c"
    break;

  case 38: /* statement: if_start expr TOKEN_BREAK  */
#line 396 "src/parser.y"
                                {
        // Bare `if (cond) break`. Same reasoning as the TOKEN_RETURN
        // alternative above -- consumed as a raw terminal, not through
        // 'last_statement', so there's no optional-semicolon collision.
        if (!runtime_req.needs_pico8) {
            compiler_error(ERR_SYNTAX, yylineno,
                "then-less if is a PICO-8 extension; add --#api pico8 to use it");
        }
        (yyval.ast_node)                             = (yyvsp[-2].ast_node);
        (yyval.ast_node) -> as.if_stmt.condition     = (yyvsp[-1].ast_node);
        (yyval.ast_node) -> as.if_stmt.if_body       = make_node(NODE_BREAK);
        (yyval.ast_node) -> as.if_stmt.else_body     = NULL;
    }
#line 1968 "src/parser.c"
    break;

  case 39: /* statement: TOKEN_DO statement_list TOKEN_END  */
#line 409 "src/parser.y"
                                        {
        // Bare scoping block: no condition, no loop tracking -- just gives
        // the enclosed statements their own lexical scope. Most useful for
        // deliberately ending a 'local' declaration's shadow before the
        // rest of the enclosing block, without needing an 'if true then'
        // workaround.
        (yyval.ast_node) = make_node_do_block ((yyvsp[-1].ast_node));
    }
#line 1981 "src/parser.c"
    break;

  case 40: /* statement: TOKEN_LOCAL var_list  */
#line 417 "src/parser.y"
                           {
        (yyval.ast_node) = make_node(NODE_MULTIPLE_ASSIGNMENT);
        (yyval.ast_node)->as.mult_assign.is_local = 1;
        (yyval.ast_node)->as.mult_assign.targets_head = (yyvsp[0].ast_node);
        (yyval.ast_node)->as.mult_assign.values_head = NULL; 
    }
#line 1992 "src/parser.c"
    break;

  case 41: /* statement: function_def  */
#line 423 "src/parser.y"
                                 { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 1998 "src/parser.c"
    break;

  case 42: /* statement: TOKEN_ASM '(' TOKEN_STRING ')'  */
#line 424 "src/parser.y"
                                     { 
        (yyval.ast_node) = make_node(NODE_ASM);
        (yyval.ast_node)->as.inline_asm.code = (yyvsp[-1].string_val);
    }
#line 2007 "src/parser.c"
    break;

  case 43: /* statement: TOKEN_LOCAL func_start TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 429 "src/parser.y"
    {
        // local function myfunc(...) ... end
        // This is equivalent to: local myfunc = function(...) ... end

                // 1. Get the pre-allocated function_def node from func_start
        ASTNode* func_def = (yyvsp[-6].ast_node);
        func_def->as.function_def.name = strdup((yyvsp[-5].string_val));
        func_def->as.function_def.params = (yyvsp[-3].ast_node);
        func_def->as.function_def.body = (yyvsp[-1].ast_node);

        // 2. Initialize and check variadic status
        func_def->as.function_def.is_variadic = 0;
        ASTNode *p = (yyvsp[-3].ast_node);
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
    }
#line 2069 "src/parser.c"
    break;

  case 44: /* statement: TOKEN_LOCAL func_start TOKEN_IDENTIFIER ':' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 487 "src/parser.y"
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
        char* mangled_name = mangle_method_name((yyvsp[-7].string_val), (yyvsp[-5].string_val));

        // 2. Inject "self" as the first parameter (colon-call convention)
        ASTNode* self_param = make_node_ident("self");
        self_param->next = (yyvsp[-3].ast_node); // link to the rest of the declared parameters

        // 3. Build the function definition using the pre-allocated node
        ASTNode* func_def = (yyvsp[-8].ast_node);
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = self_param;
        func_def->as.function_def.body = (yyvsp[-1].ast_node);
        func_def->as.function_def.is_variadic = 0;

        // 4. Build a function-pointer node targeting the mangled label
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        // 5. Tie it into a table assignment: obj["add_multiple"] = func_ptr
        ASTNode* key_node   = make_node_string((yyvsp[-5].string_val));
        ASTNode* table_node = make_node_ident((yyvsp[-7].string_val));

        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key        = key_node;
        table_set->as.table_set.value      = func_ptr;

        // 6. Chain: func_def -> table_set, same pattern as every other
        // method-desugaring rule in this grammar
        func_def->next = table_set;
        (yyval.ast_node) = func_def;
    }
#line 2116 "src/parser.c"
    break;

  case 45: /* statement: TOKEN_LOCAL func_start TOKEN_IDENTIFIER '.' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 530 "src/parser.y"
    {
        // local function obj.method(...) ... end
        //
        // Dot form: unlike the colon form above, NO implicit 'self' is
        // injected here -- this mirrors the existing non-local dot-rule
        // in function_def: below. If the body needs self, the author
        // writes it as an explicit first parameter, same as real Lua.

        char* mangled_name = mangle_method_name((yyvsp[-7].string_val), (yyvsp[-5].string_val));

        ASTNode* func_def = (yyvsp[-8].ast_node);
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = (yyvsp[-3].ast_node);
        func_def->as.function_def.body = (yyvsp[-1].ast_node);
        func_def->as.function_def.is_variadic = 0;

        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        ASTNode* key_node   = make_node_string((yyvsp[-5].string_val));
        ASTNode* table_node = make_node_ident((yyvsp[-7].string_val));

        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key        = key_node;
        table_set->as.table_set.value      = func_ptr;

        func_def->next = table_set;
        (yyval.ast_node) = func_def;
    }
#line 2151 "src/parser.c"
    break;

  case 46: /* statement: TOKEN_RAWASM '(' TOKEN_STRING ')'  */
#line 560 "src/parser.y"
                                        { 
        (yyval.ast_node) = make_node(NODE_RAWASM);
        (yyval.ast_node)->as.inline_asm.code = (yyvsp[-1].string_val);
    }
#line 2160 "src/parser.c"
    break;

  case 47: /* statement: TOKEN_COMMENT_LINE  */
#line 564 "src/parser.y"
                         {
        (yyval.ast_node) = make_node(NODE_COMMENT_LINE);
        (yyval.ast_node)->as.string_val.value = (yyvsp[0].string_val);
    }
#line 2169 "src/parser.c"
    break;

  case 48: /* statement: TOKEN_COMMENT_BLOCK  */
#line 568 "src/parser.y"
                          {
        (yyval.ast_node) = make_node(NODE_COMMENT_BLOCK);
        (yyval.ast_node)->as.string_val.value = (yyvsp[0].string_val);
    }
#line 2178 "src/parser.c"
    break;

  case 49: /* statement: tic80_section  */
#line 572 "src/parser.y"
                                { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 2184 "src/parser.c"
    break;

  case 50: /* statement: TOKEN_CART_HINT  */
#line 573 "src/parser.y"
                      {
        (yyval.ast_node) = make_node_cart_hint((yyvsp[0].string_val));
    }
#line 2192 "src/parser.c"
    break;

  case 51: /* last_statement: return_stmt  */
#line 579 "src/parser.y"
                         { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 2198 "src/parser.c"
    break;

  case 52: /* last_statement: return_stmt ';'  */
#line 580 "src/parser.y"
                         { (yyval.ast_node) = (yyvsp[-1].ast_node); }
#line 2204 "src/parser.c"
    break;

  case 53: /* last_statement: TOKEN_BREAK  */
#line 581 "src/parser.y"
                          { (yyval.ast_node) = make_node(NODE_BREAK); }
#line 2210 "src/parser.c"
    break;

  case 54: /* last_statement: TOKEN_BREAK ';'  */
#line 582 "src/parser.y"
                          { (yyval.ast_node) = make_node(NODE_BREAK); }
#line 2216 "src/parser.c"
    break;

  case 55: /* else_branch: %empty  */
#line 586 "src/parser.y"
                                 { (yyval.ast_node)  = NULL; }
#line 2222 "src/parser.c"
    break;

  case 56: /* else_branch: TOKEN_ELSE statement_list  */
#line 587 "src/parser.y"
                                 { (yyval.ast_node)  = (yyvsp[0].ast_node); }
#line 2228 "src/parser.c"
    break;

  case 57: /* else_branch: TOKEN_ELSEIF expr TOKEN_THEN statement_list else_branch  */
#line 589 "src/parser.y"
    {
        // Treat elseif exactly like a nested IF statement assigned to the else_body
        (yyval.ast_node)                             = make_node(NODE_IF);
        (yyval.ast_node) -> as.if_stmt.condition     = (yyvsp[-3].ast_node);
        (yyval.ast_node) -> as.if_stmt.if_body       = (yyvsp[-1].ast_node);
        (yyval.ast_node) -> as.if_stmt.else_body     = (yyvsp[0].ast_node);
    }
#line 2240 "src/parser.c"
    break;

  case 58: /* var_list: TOKEN_IDENTIFIER  */
#line 600 "src/parser.y"
                     {
        (yyval.ast_node) = make_node_ident((yyvsp[0].string_val));
    }
#line 2248 "src/parser.c"
    break;

  case 59: /* var_list: prefix_expr '.' TOKEN_IDENTIFIER  */
#line 603 "src/parser.y"
                                       {
        ASTNode *string_key = make_node_string ((yyvsp[0].string_val));
        (yyval.ast_node) = make_node_table_get ((yyvsp[-2].ast_node), string_key);
    }
#line 2257 "src/parser.c"
    break;

  case 60: /* var_list: prefix_expr '[' expr ']'  */
#line 607 "src/parser.y"
                               {
        (yyval.ast_node) = make_node_table_get ((yyvsp[-3].ast_node), (yyvsp[-1].ast_node));
    }
#line 2265 "src/parser.c"
    break;

  case 61: /* var_list: var_list ',' TOKEN_IDENTIFIER  */
#line 610 "src/parser.y"
                                    {
        ASTNode* new_ident = make_node_ident((yyvsp[0].string_val));
        ASTNode* curr = (yyvsp[-2].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = new_ident;
        (yyval.ast_node) = (yyvsp[-2].ast_node);
    }
#line 2277 "src/parser.c"
    break;

  case 62: /* var_list: var_list ',' prefix_expr '.' TOKEN_IDENTIFIER  */
#line 617 "src/parser.y"
                                                    {
        ASTNode *string_key = make_node_string ((yyvsp[0].string_val));
        ASTNode *new_target = make_node_table_get ((yyvsp[-2].ast_node), string_key);
        ASTNode* curr = (yyvsp[-4].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = new_target;
        (yyval.ast_node) = (yyvsp[-4].ast_node);
    }
#line 2290 "src/parser.c"
    break;

  case 63: /* var_list: var_list ',' prefix_expr '[' expr ']'  */
#line 625 "src/parser.y"
                                            {
        ASTNode *new_target = make_node_table_get ((yyvsp[-3].ast_node), (yyvsp[-1].ast_node));
        ASTNode* curr = (yyvsp[-5].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = new_target;
        (yyval.ast_node) = (yyvsp[-5].ast_node);
    }
#line 2302 "src/parser.c"
    break;

  case 64: /* expr_list: expr  */
#line 635 "src/parser.y"
         { 
        (yyval.ast_node) = (yyvsp[0].ast_node); 
    }
#line 2310 "src/parser.c"
    break;

  case 65: /* expr_list: expr_list ',' expr  */
#line 638 "src/parser.y"
                         { 
        ASTNode* curr = (yyvsp[-2].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = (yyvsp[0].ast_node);
        (yyval.ast_node) = (yyvsp[-2].ast_node); 
    }
#line 2321 "src/parser.c"
    break;

  case 66: /* function_def: func_start TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 648 "src/parser.y"
                                                                                {
        // 1. Build the structural function definition using pre-allocated node
        ASTNode* func_def = (yyvsp[-6].ast_node);
        func_def->as.function_def.name = strdup((yyvsp[-5].string_val));
        func_def->as.function_def.params = (yyvsp[-3].ast_node);
        func_def->as.function_def.body = (yyvsp[-1].ast_node);

        // NEW: Check if parameter_list contains "..."
        func_def->as.function_def.is_variadic = 0;
        ASTNode *p = (yyvsp[-3].ast_node);
        while (p != NULL) {
            if (p->type == NODE_IDENTIFIER && strcmp(p->as.id.name, "...") == 0) {
                func_def->as.function_def.is_variadic = 1;
                break;
            }
            p = p->next;
        }

        // 2. Instantiate a function pointer node for the address
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup((yyvsp[-5].string_val));

        // 3. Assign the pointer to the global variable (e.g., func_add)
        ASTNode* assign = make_node(NODE_MULTIPLE_ASSIGNMENT);
        assign->as.mult_assign.targets_head = make_node_ident((yyvsp[-5].string_val));
        assign->as.mult_assign.values_head = func_ptr;

        // 4. Chain them sequentially for the global init vector
        func_def->next = assign;
        (yyval.ast_node) = func_def;
    }
#line 2357 "src/parser.c"
    break;

  case 67: /* function_def: func_start TOKEN_IDENTIFIER '.' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 680 "src/parser.y"
                                                                                                     {
        // 1. Create a unique mangled label using the helper function
        char* mangled_name = mangle_method_name((yyvsp[-7].string_val), (yyvsp[-5].string_val));

        // 2. Build the structural function definition body using pre-allocated node
        ASTNode* func_def = (yyvsp[-8].ast_node);
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = (yyvsp[-3].ast_node);
        func_def->as.function_def.body = (yyvsp[-1].ast_node);

        // 3. Instantiate a function pointer node evaluating to that address
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        ASTNode* key_node = make_node_string((yyvsp[-5].string_val));
        ASTNode* table_node = make_node_ident((yyvsp[-7].string_val));
        
        // 4. Tie it all into a table assignment: table[key] = func_ptr
        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key = key_node;
        table_set->as.table_set.value = func_ptr;

        // 5. Chain them sequentially so the compiler outputs both properties cleanly
        func_def->next = table_set;
        (yyval.ast_node) = func_def;
    }
#line 2389 "src/parser.c"
    break;

  case 68: /* function_def: func_start TOKEN_IDENTIFIER ':' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 708 "src/parser.y"
                                                                                                     {
        // 1. Create a unique mangled label using the helper function
        char* mangled_name = mangle_method_name((yyvsp[-7].string_val), (yyvsp[-5].string_val));

        // 2. INJECT "self" as the first parameter!
        ASTNode* self_param = make_node_ident("self");
        self_param->next = (yyvsp[-3].ast_node); // Link it to the rest of the parameters

        // 3. Build the structural function definition body using pre-allocated node
        ASTNode* func_def = (yyvsp[-8].ast_node);
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = self_param; // Set self as the head of the list
        func_def->as.function_def.body = (yyvsp[-1].ast_node);

        // 4. Instantiate a function pointer node evaluating to that address
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        ASTNode* key_node = make_node_string((yyvsp[-5].string_val));
        ASTNode* table_node = make_node_ident((yyvsp[-7].string_val));
        
        // 5. Tie it all into a table assignment: table[key] = func_ptr
        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key = key_node;
        table_set->as.table_set.value = func_ptr;

        // 6. Chain them sequentially so the compiler outputs both properties cleanly
        func_def->next = table_set;
        (yyval.ast_node) = func_def;
    }
#line 2425 "src/parser.c"
    break;

  case 69: /* return_stmt: TOKEN_RETURN expr_list  */
#line 742 "src/parser.y"
                           {
        (yyval.ast_node) = make_node(NODE_RETURN);
        (yyval.ast_node)->as.return_stmt.expressions_head = (yyvsp[0].ast_node);
        (yyval.ast_node)->as.return_stmt.parent_func_arg_count = 0;
    }
#line 2435 "src/parser.c"
    break;

  case 70: /* return_stmt: TOKEN_RETURN  */
#line 747 "src/parser.y"
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
    }
#line 2454 "src/parser.c"
    break;

  case 71: /* prefix_expr: TOKEN_IDENTIFIER  */
#line 764 "src/parser.y"
                     { 
        (yyval.ast_node) = make_node_ident((yyvsp[0].string_val)); 
    }
#line 2462 "src/parser.c"
    break;

  case 72: /* prefix_expr: function_call  */
#line 767 "src/parser.y"
                    { 
        (yyval.ast_node) = (yyvsp[0].ast_node); 
    }
#line 2470 "src/parser.c"
    break;

  case 73: /* prefix_expr: '(' expr ')'  */
#line 770 "src/parser.y"
                   { 
        (yyval.ast_node) = (yyvsp[-1].ast_node); 
    }
#line 2478 "src/parser.c"
    break;

  case 74: /* prefix_expr: prefix_expr '[' expr ']'  */
#line 773 "src/parser.y"
                               {
        (yyval.ast_node) = make_node(NODE_TABLE_GET);
        (yyval.ast_node)->as.table_get.table_expr = (yyvsp[-3].ast_node);
        (yyval.ast_node)->as.table_get.key = (yyvsp[-1].ast_node);
    }
#line 2488 "src/parser.c"
    break;

  case 75: /* prefix_expr: prefix_expr '.' TOKEN_IDENTIFIER  */
#line 778 "src/parser.y"
                                       {
        ASTNode *string_key = make_node_string((yyvsp[0].string_val));
        (yyval.ast_node) = make_node(NODE_TABLE_GET);
        (yyval.ast_node)->as.table_get.table_expr = (yyvsp[-2].ast_node);
        (yyval.ast_node)->as.table_get.key = string_key;
    }
#line 2499 "src/parser.c"
    break;

  case 76: /* expr: TOKEN_DOTS  */
#line 787 "src/parser.y"
               {
        (yyval.ast_node) = make_node(NODE_VARIADIC_EXPR);
    }
#line 2507 "src/parser.c"
    break;

  case 77: /* expr: TOKEN_NUMBER  */
#line 790 "src/parser.y"
                   {
        (yyval.ast_node) = make_node(NODE_NUMBER);
        (yyval.ast_node)->as.number.val = (yyvsp[0].number_val);
    }
#line 2516 "src/parser.c"
    break;

  case 78: /* expr: TOKEN_STRING  */
#line 794 "src/parser.y"
                        { (yyval.ast_node) = make_node_string((yyvsp[0].string_val)); }
#line 2522 "src/parser.c"
    break;

  case 79: /* expr: table_constructor  */
#line 795 "src/parser.y"
                        { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 2528 "src/parser.c"
    break;

  case 80: /* expr: prefix_expr  */
#line 796 "src/parser.y"
                        { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 2534 "src/parser.c"
    break;

  case 81: /* expr: expr '+' expr  */
#line 797 "src/parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_ADD, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2540 "src/parser.c"
    break;

  case 82: /* expr: expr '-' expr  */
#line 798 "src/parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_SUB, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2546 "src/parser.c"
    break;

  case 83: /* expr: expr '*' expr  */
#line 799 "src/parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_MUL, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2552 "src/parser.c"
    break;

  case 84: /* expr: expr TOKEN_FLOORDIV expr  */
#line 800 "src/parser.y"
                               { (yyval.ast_node) = make_node_binary (NODE_FLOORDIV, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2558 "src/parser.c"
    break;

  case 85: /* expr: expr '/' expr  */
#line 801 "src/parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_DIV, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2564 "src/parser.c"
    break;

  case 86: /* expr: expr '%' expr  */
#line 802 "src/parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_MOD, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2570 "src/parser.c"
    break;

  case 87: /* expr: expr '^' expr  */
#line 803 "src/parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_POW, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2576 "src/parser.c"
    break;

  case 88: /* expr: TOKEN_TRUE  */
#line 804 "src/parser.y"
                  { (yyval.ast_node) = make_node_boolean (true);  }
#line 2582 "src/parser.c"
    break;

  case 89: /* expr: TOKEN_FALSE  */
#line 805 "src/parser.y"
                  { (yyval.ast_node) = make_node_boolean (false); }
#line 2588 "src/parser.c"
    break;

  case 90: /* expr: TOKEN_NIL  */
#line 806 "src/parser.y"
                  { (yyval.ast_node) = make_node_nil ();          }
#line 2594 "src/parser.c"
    break;

  case 91: /* expr: TOKEN_LEN expr  */
#line 807 "src/parser.y"
                        { (yyval.ast_node) = make_node_unary  (OP_LEN,   (yyvsp[0].ast_node));     }
#line 2600 "src/parser.c"
    break;

  case 92: /* expr: '-' expr  */
#line 808 "src/parser.y"
                                 { (yyval.ast_node) = make_node_unary (OP_UNM, (yyvsp[0].ast_node)); }
#line 2606 "src/parser.c"
    break;

  case 93: /* expr: TOKEN_NOT expr  */
#line 809 "src/parser.y"
                                 { (yyval.ast_node) = make_node_unary (OP_NOT, (yyvsp[0].ast_node)); }
#line 2612 "src/parser.c"
    break;

  case 94: /* expr: expr TOKEN_EQ expr  */
#line 810 "src/parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_EQ;  (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2618 "src/parser.c"
    break;

  case 95: /* expr: expr TOKEN_NEQ expr  */
#line 811 "src/parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_NEQ; (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2624 "src/parser.c"
    break;

  case 96: /* expr: expr TOKEN_LT expr  */
#line 812 "src/parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_LT;  (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2630 "src/parser.c"
    break;

  case 97: /* expr: expr TOKEN_GT expr  */
#line 813 "src/parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_GT;  (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2636 "src/parser.c"
    break;

  case 98: /* expr: expr TOKEN_LE expr  */
#line 814 "src/parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_LE;  (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2642 "src/parser.c"
    break;

  case 99: /* expr: expr TOKEN_GE expr  */
#line 815 "src/parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_GE;  (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2648 "src/parser.c"
    break;

  case 100: /* expr: expr TOKEN_AND expr  */
#line 816 "src/parser.y"
                              { (yyval.ast_node) = make_node(NODE_AND);        (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node);     (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2654 "src/parser.c"
    break;

  case 101: /* expr: expr TOKEN_OR expr  */
#line 817 "src/parser.y"
                              { (yyval.ast_node) = make_node(NODE_OR);         (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node);     (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2660 "src/parser.c"
    break;

  case 102: /* expr: expr TOKEN_CONCAT expr  */
#line 818 "src/parser.y"
                              { (yyval.ast_node) = make_node(NODE_CONCAT);     (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node);     (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2666 "src/parser.c"
    break;

  case 103: /* expr: func_start '(' parameter_list ')' statement_list TOKEN_END  */
#line 820 "src/parser.y"
    {
        static int anon_counter = 0;
        char buf[64];
        snprintf(buf, sizeof(buf), "__anon_%d", anon_counter++);

        ASTNode* func_def = (yyvsp[-5].ast_node);
        func_def->as.function_def.name = strdup(buf);
        func_def->as.function_def.params = (yyvsp[-3].ast_node);
        func_def->as.function_def.body = (yyvsp[-1].ast_node);

        // Initialize and check variadic status for anonymous functions
        func_def->as.function_def.is_variadic = 0;
        ASTNode *p = (yyvsp[-3].ast_node);
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
    }
#line 2698 "src/parser.c"
    break;

  case 104: /* function_call: TOKEN_IDENTIFIER '(' argument_list ')'  */
#line 850 "src/parser.y"
                                           {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.target = make_node_ident((yyvsp[-3].string_val));
        node->as.call.is_method_call = 0; 
        node->as.call.args_head = (yyvsp[-1].ast_node);
        (yyval.ast_node) = node;
    }
#line 2710 "src/parser.c"
    break;

  case 105: /* function_call: prefix_expr '.' TOKEN_IDENTIFIER '(' argument_list ')'  */
#line 857 "src/parser.y"
                                                             {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.is_method_call = 0;
        
        // Dynamically look up the function inside the table
        ASTNode* dynamic_lookup = make_node(NODE_TABLE_GET);
        dynamic_lookup->as.table_get.table_expr = (yyvsp[-5].ast_node);
        dynamic_lookup->as.table_get.key = make_node_string((yyvsp[-3].string_val));
        node->as.call.target = dynamic_lookup;
        node->as.call.args_head = (yyvsp[-1].ast_node);
        (yyval.ast_node) = node;
    }
#line 2727 "src/parser.c"
    break;

  case 106: /* function_call: prefix_expr ':' TOKEN_IDENTIFIER '(' argument_list ')'  */
#line 869 "src/parser.y"
                                                             {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.target = (yyvsp[-5].ast_node);
        node->as.call.is_method_call = 1;
        
        ASTNode* dynamic_lookup = make_node(NODE_TABLE_GET);
        dynamic_lookup->as.table_get.table_expr = (yyvsp[-5].ast_node);
        dynamic_lookup->as.table_get.key = make_node_string((yyvsp[-3].string_val));
        node->as.call.target = dynamic_lookup;
        node->as.call.args_head = (yyvsp[-1].ast_node);
        (yyval.ast_node) = node;
    }
#line 2744 "src/parser.c"
    break;

  case 107: /* function_call: prefix_expr '(' argument_list ')'  */
#line 881 "src/parser.y"
                                        {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.target = (yyvsp[-3].ast_node);
        node->as.call.is_method_call = 0;
        node->as.call.args_head = (yyvsp[-1].ast_node);
        (yyval.ast_node) = node;
    }
#line 2756 "src/parser.c"
    break;

  case 108: /* field: expr  */
#line 891 "src/parser.y"
         {
        // Array-style: {value} -> implicit sequential key
        (yyval.ast_node) = (yyvsp[0].ast_node);
    }
#line 2765 "src/parser.c"
    break;

  case 109: /* field: expr '=' expr  */
#line 895 "src/parser.y"
                    {
    // Record-style: {key = value}
    // Convert identifier key to string literal (Lua semantics: x=8 means key "x", not var x)
    ASTNode *key_node = (yyvsp[-2].ast_node);
    if (key_node->type == NODE_IDENTIFIER) {
        key_node = make_node_string(key_node->as.id.name);
    }
    (yyval.ast_node) = make_node_table_set(NULL, key_node, (yyvsp[0].ast_node));
}
#line 2779 "src/parser.c"
    break;

  case 110: /* field: '[' expr ']' '=' expr  */
#line 904 "src/parser.y"
                            {
        // Explicit key: {[key] = value}
        (yyval.ast_node) = make_node_table_set(NULL, (yyvsp[-3].ast_node), (yyvsp[0].ast_node));
    }
#line 2788 "src/parser.c"
    break;

  case 111: /* field_list: field  */
#line 911 "src/parser.y"
          {
        (yyval.ast_node) = (yyvsp[0].ast_node);
    }
#line 2796 "src/parser.c"
    break;

  case 112: /* field_list: field_list ',' field  */
#line 914 "src/parser.y"
                           {
        // Chain fields together via next pointer
        ASTNode* curr = (yyvsp[-2].ast_node);
        while (curr->next) curr = curr->next;
        curr->next = (yyvsp[0].ast_node);
        (yyval.ast_node) = (yyvsp[-2].ast_node);
    }
#line 2808 "src/parser.c"
    break;

  case 113: /* table_constructor: '{' '}'  */
#line 924 "src/parser.y"
            {
        (yyval.ast_node) = make_node_table_constructor(NULL);
    }
#line 2816 "src/parser.c"
    break;

  case 114: /* table_constructor: '{' field_list '}'  */
#line 927 "src/parser.y"
                         {
        (yyval.ast_node) = make_node_table_constructor((yyvsp[-1].ast_node));
    }
#line 2824 "src/parser.c"
    break;

  case 115: /* table_constructor: '{' field_list ',' '}'  */
#line 930 "src/parser.y"
                             {
        // Trailing comma before the closing brace -- e.g.
        //   { [1] = a, [2] = b, }
        // Standard, idiomatic Lua; the parser previously had no
        // production for a comma immediately followed by '}', since
        // field_list only ever grows via 'field_list , field' and a
        // field must start with an expression token, which '}' is not.
        (yyval.ast_node) = make_node_table_constructor((yyvsp[-2].ast_node));
    }
#line 2838 "src/parser.c"
    break;

  case 116: /* $@1: %empty  */
#line 943 "src/parser.y"
    {
        current_tic80_section = strdup((yyvsp[0].string_val));
        free((yyvsp[0].string_val));
    }
#line 2847 "src/parser.c"
    break;

  case 117: /* tic80_section: TOKEN_TIC80_SECTION_HEADER $@1 tic80_asset_lines TOKEN_TIC80_SECTION_FOOTER  */
#line 949 "src/parser.y"
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

        free((yyvsp[-1].ast_node));
        (yyval.ast_node) = NULL;
    }
#line 2872 "src/parser.c"
    break;

  case 118: /* tic80_asset_lines: %empty  */
#line 972 "src/parser.y"
                { (yyval.ast_node) = NULL; }
#line 2878 "src/parser.c"
    break;

  case 119: /* tic80_asset_lines: tic80_asset_lines TOKEN_TIC80_ASSET_DATA  */
#line 974 "src/parser.y"
    {
        TIC80AssetData *data = parse_tic80_asset_line((yyvsp[0].string_val));
        if (data != NULL) {  // <-- ADD THIS CHECK
            data->next = current_tic80_assets;
            current_tic80_assets = data;
        }
        free((yyvsp[0].string_val));
        (yyval.ast_node) = NULL;
    }
#line 2892 "src/parser.c"
    break;


#line 2896 "src/parser.c"

      default: break;
    }
  /* User semantic actions sometimes alter yychar, and that requires
     that yytoken be updated with the new translation.  We take the
     approach of translating immediately before every use of yytoken.
     One alternative is translating here after every semantic action,
     but that translation would be missed if the semantic action invokes
     YYABORT, YYACCEPT, or YYERROR immediately after altering yychar or
     if it invokes YYBACKUP.  In the case of YYABORT or YYACCEPT, an
     incorrect destructor might then be invoked immediately.  In the
     case of YYERROR or YYBACKUP, subsequent parser actions might lead
     to an incorrect destructor call or verbose syntax error message
     before the lookahead is translated.  */
  YY_SYMBOL_PRINT ("-> $$ =", YY_CAST (yysymbol_kind_t, yyr1[yyn]), &yyval, &yyloc);

  YYPOPSTACK (yylen);
  yylen = 0;

  *++yyvsp = yyval;

  /* Now 'shift' the result of the reduction.  Determine what state
     that goes to, based on the state we popped back to and the rule
     number reduced by.  */
  {
    const int yylhs = yyr1[yyn] - YYNTOKENS;
    const int yyi = yypgoto[yylhs] + *yyssp;
    yystate = (0 <= yyi && yyi <= YYLAST && yycheck[yyi] == *yyssp
               ? yytable[yyi]
               : yydefgoto[yylhs]);
  }

  goto yynewstate;


/*--------------------------------------.
| yyerrlab -- here on detecting error.  |
`--------------------------------------*/
yyerrlab:
  /* Make sure we have latest lookahead translation.  See comments at
     user semantic actions for why this is necessary.  */
  yytoken = yychar == YYEMPTY ? YYSYMBOL_YYEMPTY : YYTRANSLATE (yychar);
  /* If not already recovering from an error, report this error.  */
  if (!yyerrstatus)
    {
      ++yynerrs;
      yyerror (YY_("syntax error"));
    }

  if (yyerrstatus == 3)
    {
      /* If just tried and failed to reuse lookahead token after an
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

  /* Else will try to reuse lookahead token after shifting the error
     token.  */
  goto yyerrlab1;


/*---------------------------------------------------.
| yyerrorlab -- error raised explicitly by YYERROR.  |
`---------------------------------------------------*/
yyerrorlab:
  /* Pacify compilers when the user code never invokes YYERROR and the
     label yyerrorlab therefore never appears in user code.  */
  if (0)
    YYERROR;
  ++yynerrs;

  /* Do not reclaim the symbols of the rule whose action triggered
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
  yyerrstatus = 3;      /* Each real token shifted decrements this.  */

  /* Pop stack until we find a state that shifts the error token.  */
  for (;;)
    {
      yyn = yypact[yystate];
      if (!yypact_value_is_default (yyn))
        {
          yyn += YYSYMBOL_YYerror;
          if (0 <= yyn && yyn <= YYLAST && yycheck[yyn] == YYSYMBOL_YYerror)
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
                  YY_ACCESSING_SYMBOL (yystate), yyvsp);
      YYPOPSTACK (1);
      yystate = *yyssp;
      YY_STACK_PRINT (yyss, yyssp);
    }

  YY_IGNORE_MAYBE_UNINITIALIZED_BEGIN
  *++yyvsp = yylval;
  YY_IGNORE_MAYBE_UNINITIALIZED_END


  /* Shift the error token.  */
  YY_SYMBOL_PRINT ("Shifting", YY_ACCESSING_SYMBOL (yyn), yyvsp, yylsp);

  yystate = yyn;
  goto yynewstate;


/*-------------------------------------.
| yyacceptlab -- YYACCEPT comes here.  |
`-------------------------------------*/
yyacceptlab:
  yyresult = 0;
  goto yyreturnlab;


/*-----------------------------------.
| yyabortlab -- YYABORT comes here.  |
`-----------------------------------*/
yyabortlab:
  yyresult = 1;
  goto yyreturnlab;


/*-----------------------------------------------------------.
| yyexhaustedlab -- YYNOMEM (memory exhaustion) comes here.  |
`-----------------------------------------------------------*/
yyexhaustedlab:
  yyerror (YY_("memory exhausted"));
  yyresult = 2;
  goto yyreturnlab;


/*----------------------------------------------------------.
| yyreturnlab -- parsing is finished, clean up and return.  |
`----------------------------------------------------------*/
yyreturnlab:
  if (yychar != YYEMPTY)
    {
      /* Make sure we have latest lookahead translation.  See comments at
         user semantic actions for why this is necessary.  */
      yytoken = YYTRANSLATE (yychar);
      yydestruct ("Cleanup: discarding lookahead",
                  yytoken, &yylval);
    }
  /* Do not reclaim the symbols of the rule whose action triggered
     this YYABORT or YYACCEPT.  */
  YYPOPSTACK (yylen);
  YY_STACK_PRINT (yyss, yyssp);
  while (yyssp != yyss)
    {
      yydestruct ("Cleanup: popping",
                  YY_ACCESSING_SYMBOL (+*yyssp), yyvsp);
      YYPOPSTACK (1);
    }
#ifndef yyoverflow
  if (yyss != yyssa)
    YYSTACK_FREE (yyss);
#endif

  return yyresult;
}

#line 984 "src/parser.y"


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
