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

/* Largest parameter count of any function in the program (self included for
   ':' methods, '...' excluded). Calls whose target arity is unknown at
   compile time are NIL-padded up to this -- see node_function_call(). */
int g_max_param_count = 0;
/* nesting depth of `function` bodies while parsing (see func_start) */
static int g_func_depth = 0;
static void note_function_param_count (ASTNode *params)
{
    int n = 0;
    for (ASTNode *p = params; p != NULL; p = p->next) {
        if (p->type == NODE_IDENTIFIER && strcmp (p->as.id.name, "...") == 0) continue;
        n++;
    }
    if (n > g_max_param_count) g_max_param_count = n;
}


/* function t.f(...) / function t:f(...): t.f = function([self,] ...) end */
static int method_fn_counter = 0;
static ASTNode *make_method_function_assignment (ASTNode *func_def, char *table,
                                                 char *method, ASTNode *params,
                                                 ASTNode *body, bool add_self)
{
    char buf[256];
    snprintf (buf, sizeof (buf), "%s_%s__m%d", table, method, method_fn_counter++);
    if (add_self) {
        ASTNode *self_param = make_node_ident ("self");
        self_param->next = params;
        params = self_param;
    }
    func_def->as.function_def.name = strdup (buf);
    func_def->as.function_def.params = params;
    note_function_param_count (params);
    func_def->as.function_def.body = body;
    func_def->as.function_def.is_variadic = 0;
    for (ASTNode *p = params; p != NULL; p = p->next)
        if (p->type == NODE_IDENTIFIER && strcmp (p->as.id.name, "...") == 0)
            func_def->as.function_def.is_variadic = 1;

    ASTNode *func_ptr = make_node (NODE_FUNCTION_POINTER);
    func_ptr->as.func_ptr.mangled_name = strdup (buf);
    func_ptr->as.func_ptr.func_def = func_def;

    ASTNode *table_set = make_node (NODE_TABLE_SET);
    table_set->as.table_set.table_expr = make_node_ident (table);
    table_set->as.table_set.key        = make_node_string (method);
    table_set->as.table_set.value      = func_ptr;
    return table_set;
}


#line 138 "parser.c"

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
  YYSYMBOL_TOKEN_BXOR = 44,                /* TOKEN_BXOR  */
  YYSYMBOL_TOKEN_SHL = 45,                 /* TOKEN_SHL  */
  YYSYMBOL_TOKEN_SHR = 46,                 /* TOKEN_SHR  */
  YYSYMBOL_TOKEN_LSHR = 47,                /* TOKEN_LSHR  */
  YYSYMBOL_TOKEN_ROTL = 48,                /* TOKEN_ROTL  */
  YYSYMBOL_TOKEN_ROTR = 49,                /* TOKEN_ROTR  */
  YYSYMBOL_TOKEN_DOTS = 50,                /* TOKEN_DOTS  */
  YYSYMBOL_TOKEN_REPEAT = 51,              /* TOKEN_REPEAT  */
  YYSYMBOL_TOKEN_UNTIL = 52,               /* TOKEN_UNTIL  */
  YYSYMBOL_TOKEN_GOTO = 53,                /* TOKEN_GOTO  */
  YYSYMBOL_TOKEN_DBCOLON = 54,             /* TOKEN_DBCOLON  */
  YYSYMBOL_TOKEN_PRINT_SHORT = 55,         /* TOKEN_PRINT_SHORT  */
  YYSYMBOL_56_ = 56,                       /* '|'  */
  YYSYMBOL_57_ = 57,                       /* '&'  */
  YYSYMBOL_58_ = 58,                       /* '+'  */
  YYSYMBOL_59_ = 59,                       /* '-'  */
  YYSYMBOL_60_ = 60,                       /* '*'  */
  YYSYMBOL_61_ = 61,                       /* '/'  */
  YYSYMBOL_62_ = 62,                       /* '%'  */
  YYSYMBOL_63_ = 63,                       /* '^'  */
  YYSYMBOL_64_ = 64,                       /* '['  */
  YYSYMBOL_65_ = 65,                       /* '.'  */
  YYSYMBOL_66_ = 66,                       /* ':'  */
  YYSYMBOL_67_ = 67,                       /* ';'  */
  YYSYMBOL_68_ = 68,                       /* ','  */
  YYSYMBOL_69_ = 69,                       /* '='  */
  YYSYMBOL_70_ = 70,                       /* ']'  */
  YYSYMBOL_71_ = 71,                       /* '('  */
  YYSYMBOL_72_ = 72,                       /* ')'  */
  YYSYMBOL_73_ = 73,                       /* '{'  */
  YYSYMBOL_74_ = 74,                       /* '}'  */
  YYSYMBOL_YYACCEPT = 75,                  /* $accept  */
  YYSYMBOL_program = 76,                   /* program  */
  YYSYMBOL_statement_list = 77,            /* statement_list  */
  YYSYMBOL_stat_list = 78,                 /* stat_list  */
  YYSYMBOL_parameter_list = 79,            /* parameter_list  */
  YYSYMBOL_argument_list = 80,             /* argument_list  */
  YYSYMBOL_func_start = 81,                /* func_start  */
  YYSYMBOL_while_start = 82,               /* while_start  */
  YYSYMBOL_repeat_start = 83,              /* repeat_start  */
  YYSYMBOL_for_start = 84,                 /* for_start  */
  YYSYMBOL_if_start = 85,                  /* if_start  */
  YYSYMBOL_statement = 86,                 /* statement  */
  YYSYMBOL_last_statement = 87,            /* last_statement  */
  YYSYMBOL_else_branch = 88,               /* else_branch  */
  YYSYMBOL_var_list = 89,                  /* var_list  */
  YYSYMBOL_expr_list = 90,                 /* expr_list  */
  YYSYMBOL_function_def = 91,              /* function_def  */
  YYSYMBOL_return_stmt = 92,               /* return_stmt  */
  YYSYMBOL_prefix_expr = 93,               /* prefix_expr  */
  YYSYMBOL_expr = 94,                      /* expr  */
  YYSYMBOL_function_call = 95,             /* function_call  */
  YYSYMBOL_field = 96,                     /* field  */
  YYSYMBOL_field_list = 97,                /* field_list  */
  YYSYMBOL_field_sep = 98,                 /* field_sep  */
  YYSYMBOL_table_constructor = 99,         /* table_constructor  */
  YYSYMBOL_tic80_section = 100,            /* tic80_section  */
  YYSYMBOL_101_1 = 101,                    /* $@1  */
  YYSYMBOL_tic80_asset_lines = 102         /* tic80_asset_lines  */
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
#define YYFINAL  70
/* YYLAST -- Last index in YYTABLE.  */
#define YYLAST   1284

/* YYNTOKENS -- Number of terminals.  */
#define YYNTOKENS  75
/* YYNNTS -- Number of nonterminals.  */
#define YYNNTS  28
/* YYNRULES -- Number of rules.  */
#define YYNRULES  137
/* YYNSTATES -- Number of states.  */
#define YYNSTATES  299

/* YYMAXUTOK -- Last valid token kind.  */
#define YYMAXUTOK   310


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
       2,     2,     2,     2,     2,     2,     2,    62,    57,     2,
      71,    72,    60,    58,    68,    59,    65,    61,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,    66,    67,
       2,    69,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,    64,     2,    70,    63,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,    73,    56,    74,     2,     2,     2,     2,
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
      45,    46,    47,    48,    49,    50,    51,    52,    53,    54,
      55
};

#if YYDEBUG
/* YYRLINE[YYN] -- Source line where rule number YYN was defined.  */
static const yytype_int16 yyrline[] =
{
       0,   128,   128,   135,   136,   137,   149,   153,   154,   166,
     167,   182,   185,   188,   192,   199,   209,   212,   215,   228,
     232,   236,   240,   243,   247,   248,   255,   260,   264,   270,
     276,   344,   349,   354,   359,   370,   378,   386,   392,   398,
     426,   468,   481,   489,   495,   496,   500,   589,   633,   665,
     669,   673,   677,   678,   684,   685,   686,   687,   691,   692,
     693,   705,   708,   712,   715,   722,   730,   740,   743,   753,
     786,   797,   804,   809,   826,   829,   832,   835,   840,   849,
     852,   856,   857,   858,   859,   860,   861,   862,   863,   864,
     865,   866,   867,   868,   869,   870,   871,   872,   873,   874,
     875,   876,   877,   878,   879,   880,   881,   882,   883,   884,
     885,   886,   887,   888,   889,   890,   922,   929,   941,   953,
     961,   967,   973,   982,   994,   998,  1007,  1014,  1017,  1028,
    1028,  1032,  1035,  1038,  1051,  1050,  1080,  1081
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
  "TOKEN_FLOORDIV", "TOKEN_BXOR", "TOKEN_SHL", "TOKEN_SHR", "TOKEN_LSHR",
  "TOKEN_ROTL", "TOKEN_ROTR", "TOKEN_DOTS", "TOKEN_REPEAT", "TOKEN_UNTIL",
  "TOKEN_GOTO", "TOKEN_DBCOLON", "TOKEN_PRINT_SHORT", "'|'", "'&'", "'+'",
  "'-'", "'*'", "'/'", "'%'", "'^'", "'['", "'.'", "':'", "';'", "','",
  "'='", "']'", "'('", "')'", "'{'", "'}'", "$accept", "program",
  "statement_list", "stat_list", "parameter_list", "argument_list",
  "func_start", "while_start", "repeat_start", "for_start", "if_start",
  "statement", "last_statement", "else_branch", "var_list", "expr_list",
  "function_def", "return_stmt", "prefix_expr", "expr", "function_call",
  "field", "field_list", "field_sep", "table_constructor", "tic80_section",
  "$@1", "tic80_asset_lines", YY_NULLPTR
};

static const char *
yysymbol_name (yysymbol_kind_t yysymbol)
{
  return yytname[yysymbol];
}
#endif

#define YYPACT_NINF (-138)

#define yypact_value_is_default(Yyn) \
  ((Yyn) == YYPACT_NINF)

#define YYTABLE_NINF (-79)

#define yytable_value_is_error(Yyn) \
  0

/* YYPACT[STATE-NUM] -- Index in YYTABLE of the portion describing
   STATE-NUM.  */
static const yytype_int16 yypact[] =
{
     480,     2,  -138,  -138,  -138,  -138,  -138,  -138,   -56,  -138,
    -138,   -43,   -34,   126,     9,   480,  -138,    41,    44,   126,
     126,    56,  -138,   480,    66,   126,   480,     5,   126,    29,
    -138,    23,  -138,    48,    79,   202,  -138,  -138,   126,    13,
    -138,  -138,  -138,   128,   144,  -138,    35,  -138,   126,   126,
    -138,  -138,  -138,   126,  -138,   126,   -10,    84,   146,  1140,
    -138,  -138,   157,   -49,   166,   153,  -138,   120,    84,   612,
    -138,   119,  -138,    89,  1062,   135,    36,   -29,   565,  -138,
     126,    18,   126,  -138,   126,   194,   203,   126,   -26,  1140,
     126,  -138,   929,  -138,   -36,   149,   136,   155,   150,   150,
     150,   150,     8,   126,   126,   214,   126,   126,   126,   126,
     126,   126,   126,   126,   126,   126,   126,   126,   126,   126,
     126,   126,   126,   126,   126,   126,   126,   126,   126,   126,
     117,   126,   126,   225,  -138,  -138,  -138,  -138,   238,   241,
       8,   480,   126,   126,   126,  -138,   480,  -138,  -138,  1140,
       2,   169,    84,   660,    57,    24,    52,   126,  -138,   706,
     126,  -138,  -138,  -138,    98,  -138,  -138,  -138,  -138,  -138,
    -138,   147,  1140,   752,    39,   338,  1179,   464,   464,   464,
     464,   464,   464,   163,   150,   132,   163,   163,   163,   163,
     163,  1200,  1221,   141,   141,   150,   150,   150,   150,   256,
     257,     8,    84,   798,    47,   193,   201,   148,   255,  1140,
    1018,    54,   104,   126,   273,    31,  -138,   126,   126,  -138,
     126,  -138,  1140,   209,  1140,  -138,  -138,    43,   480,  -138,
     211,   217,   175,   205,     8,     8,   480,  -138,   126,   480,
     126,   480,   265,   844,    47,   126,  1140,   176,   182,   126,
    -138,  -138,   272,     8,     8,   480,   184,   185,   274,   974,
     277,   890,  -138,  -138,   205,  1140,  -138,  -138,  1140,  -138,
     190,   191,   279,   480,   480,  -138,   480,   126,  -138,   480,
     480,   480,  -138,   281,   282,   285,  1101,   104,   286,   288,
    -138,  -138,  -138,   480,  -138,  -138,  -138,   290,  -138
};

/* YYDEFACT[STATE-NUM] -- Default reduction number in state STATE-NUM.
   Performed when YYTABLE does not specify something else to do.  Zero
   means the default is an error.  */
static const yytype_uint8 yydefact[] =
{
       3,    61,    50,    51,   134,    53,    20,    22,    56,    23,
      19,     0,     0,    73,     0,     3,    21,     0,     0,     0,
       0,     0,     2,     4,     0,     0,     3,     0,     0,     9,
       6,     0,    44,    54,     0,    24,    52,   120,    16,     0,
     121,   136,    57,     0,     0,    80,    74,    81,     0,     0,
     100,   101,   102,     0,    79,     0,     0,    72,    83,    67,
      75,    82,     0,    43,     0,     0,    26,     0,    25,     0,
       1,    10,     5,     0,     0,     0,    74,     0,     0,     7,
       0,     0,     0,    55,     0,     0,     0,    16,     0,    17,
       0,   131,   124,   127,     0,     0,     0,     0,   105,   103,
      99,   104,    11,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,     0,    42,    27,    76,     8,     0,     0,
      11,     3,     0,     0,     0,    41,     3,    40,    39,    30,
      64,     0,    28,     0,    78,     0,     0,     0,   116,     0,
       0,   130,   129,   132,     0,   137,   135,    45,    49,    12,
      13,     0,    68,     0,    78,   112,   113,   106,   107,   110,
     111,   108,   109,   114,    87,    93,    94,    95,    96,    97,
      98,    92,    91,    84,    85,    86,    88,    89,    90,     0,
       0,    11,    29,     0,    62,     0,     0,     0,     0,    34,
       0,     0,    58,     0,     0,    77,   122,     0,    16,   123,
      16,   119,    18,     0,   125,   133,   128,     0,     3,    77,
       0,     0,     0,    63,    11,    11,     3,    33,     0,     3,
       0,     3,     0,     0,    65,     0,    32,     0,     0,     0,
      14,    15,     0,    11,    11,     3,     0,     0,     0,     0,
       0,     0,    59,    38,    66,    31,   117,   118,   126,   115,
       0,     0,     0,     3,     3,    69,     3,     0,    37,     3,
       3,     3,    46,     0,     0,     0,     0,    58,     0,     0,
      70,    71,    35,     3,    60,    48,    47,     0,    36
};

/* YYPGOTO[NTERM-NUM].  */
static const yytype_int16 yypgoto[] =
{
    -138,  -138,    68,  -138,  -137,   -86,    10,  -138,  -138,  -138,
    -138,   -18,   289,    26,    -6,   -17,  -138,  -138,     0,   325,
      59,   151,  -138,  -138,     3,  -138,  -138,  -138
};

/* YYDEFGOTO[NTERM-NUM].  */
static const yytype_uint8 yydefgoto[] =
{
       0,    21,    22,    23,   171,    88,    56,    25,    26,    27,
      28,    29,    30,   242,    31,    57,    32,    33,    58,    59,
      60,    93,    94,   164,    61,    36,    41,    95
};

/* YYTABLE[YYPACT[STATE-NUM]] -- What to do in state STATE-NUM.  If
   positive, shift that token.  If negative, reduce the rule whose
   number is the opposite.  If YYTABLE_NINF, syntax error.  */
static const yytype_int16 yytable[] =
{
      34,   156,    68,   207,    40,    71,   144,    37,    63,    76,
      24,    42,   169,     1,    64,    34,    45,    46,    47,    81,
     131,    77,   150,    34,    62,    24,    34,    64,    43,   219,
      10,   161,   162,    24,    10,    80,    24,    44,   163,    81,
      37,    37,   157,   -63,   216,    66,   158,   250,    67,    40,
      48,    49,   216,    50,    51,    52,    70,    53,   170,    35,
     148,   102,   216,    54,   232,   152,   -74,   -74,   -74,   -62,
      73,   -61,    55,    38,    35,    39,    20,    90,    34,    40,
      20,   151,    35,    65,    20,    35,    39,    91,    24,    20,
     239,    81,    82,   251,    75,   220,    79,   256,   257,   -63,
     245,    45,    46,    47,   -61,   143,    38,    38,    39,    39,
     218,   -78,   -78,   -78,   202,    83,   270,   271,   218,    10,
     157,   240,   103,   241,   221,   -62,   217,   211,   218,    45,
      46,    47,   247,    96,   248,    48,    49,    35,    50,    51,
      52,    34,    53,    84,    85,    86,    34,    10,    54,    97,
      87,    24,   103,    40,   138,   139,    24,    55,   165,   166,
     140,   130,    90,    48,    49,   114,    50,    51,    52,    20,
      53,    39,   225,   134,   135,   115,    54,   117,   118,   119,
     120,   121,   199,   200,   115,    55,   137,   142,   201,   123,
     124,   125,   126,   127,   128,   129,   114,    20,   154,    39,
      35,   126,   127,   128,   129,    35,   115,   155,   167,   208,
     104,   105,    86,   129,   212,   227,   227,    87,   174,   228,
     236,   124,   125,   126,   127,   128,   129,   168,    34,   204,
     132,   133,    86,   213,   214,    86,    34,    87,    24,    34,
      87,    34,   205,   227,   157,   206,    24,   255,   266,    24,
     157,    24,   227,   227,   267,    34,   273,   274,   227,   227,
     230,   231,   280,   281,   234,    24,   -75,   -75,   -75,   -77,
     -77,   -77,   235,    34,    34,   237,    34,   244,   249,    34,
      34,    34,   253,    24,    24,   263,    24,    35,   254,    24,
      24,    24,   269,    34,   275,    35,   252,   278,    35,   282,
      35,   290,   291,    24,   258,   292,   295,   260,   296,   262,
     298,     0,    72,   294,    35,   226,     0,     0,     0,     0,
       0,     0,     0,   272,     0,     0,     0,     0,     0,     0,
       0,     0,    35,    35,     0,    35,     0,     0,    35,    35,
      35,   283,   284,     0,   285,    69,     0,   287,   288,   289,
      74,     0,    35,    78,     0,     0,     0,     0,     0,     0,
       0,   297,     0,    89,    92,   108,   109,   110,   111,   112,
     113,   114,     0,    98,    99,     0,     0,     0,   100,     0,
     101,   115,   116,   117,   118,   119,   120,   121,     0,     0,
       0,     0,     0,     0,   122,   123,   124,   125,   126,   127,
     128,   129,     0,     0,     0,   149,     0,     0,     0,   153,
       0,     0,    89,     0,     0,   159,     0,     0,     0,     0,
       0,     0,     0,     0,     0,     0,     0,     0,   172,   173,
       0,   175,   176,   177,   178,   179,   180,   181,   182,   183,
     184,   185,   186,   187,   188,   189,   190,   191,   192,   193,
     194,   195,   196,   197,   198,     0,     0,   203,     0,     0,
       0,     0,     0,     0,     0,     0,     0,   209,   210,     0,
       0,     0,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,   222,     0,     1,   224,     2,     3,     4,    92,
       0,     5,     0,     6,     7,     8,     9,   114,     0,     0,
       0,    10,    11,    12,    13,     0,     0,   115,   116,   117,
     118,   119,   120,   121,    14,     0,    15,     0,     0,     0,
     122,   123,   124,   125,   126,   127,   128,   129,     0,     0,
       0,    16,     0,    17,    18,    19,     0,     0,   243,     0,
       0,     0,   246,    89,     0,    89,     0,     0,     0,     0,
       0,    20,     0,     0,     0,     0,     0,     0,     0,     0,
       0,     0,     0,   259,     0,   261,     0,     0,     0,     1,
     265,     2,     3,     4,   268,     0,     5,     0,     6,     7,
     145,     9,     0,   146,     0,     0,    10,    11,    12,   147,
     106,   107,   108,   109,   110,   111,   112,   113,   114,    14,
       0,    15,   286,     0,     0,     0,     0,     0,   115,   116,
     117,   118,   119,   120,   121,     0,    16,     0,    17,    18,
      19,   122,   123,   124,   125,   126,   127,   128,   129,     0,
       0,     0,     0,     0,     0,     0,    20,   106,   107,   108,
     109,   110,   111,   112,   113,   114,     0,     0,     0,     0,
       0,     0,     0,     0,     0,   115,   116,   117,   118,   119,
     120,   121,     0,     0,     0,     0,     0,     0,   122,   123,
     124,   125,   126,   127,   128,   129,     0,     0,     0,     0,
       0,     0,     0,     0,   136,   106,   107,   108,   109,   110,
     111,   112,   113,   114,     0,     0,     0,     0,     0,     0,
       0,     0,     0,   115,   116,   117,   118,   119,   120,   121,
       0,     0,     0,     0,     0,     0,   122,   123,   124,   125,
     126,   127,   128,   129,     0,     0,     0,     0,     0,     0,
     215,   106,   107,   108,   109,   110,   111,   112,   113,   114,
       0,     0,     0,     0,     0,     0,     0,     0,     0,   115,
     116,   117,   118,   119,   120,   121,     0,     0,     0,     0,
       0,     0,   122,   123,   124,   125,   126,   127,   128,   129,
       0,     0,     0,     0,     0,     0,   223,   106,   107,   108,
     109,   110,   111,   112,   113,   114,     0,     0,     0,     0,
       0,     0,     0,     0,     0,   115,   116,   117,   118,   119,
     120,   121,     0,     0,     0,     0,     0,     0,   122,   123,
     124,   125,   126,   127,   128,   129,     0,     0,     0,     0,
       0,     0,   229,   106,   107,   108,   109,   110,   111,   112,
     113,   114,     0,     0,     0,     0,     0,     0,     0,     0,
       0,   115,   116,   117,   118,   119,   120,   121,     0,     0,
       0,     0,     0,     0,   122,   123,   124,   125,   126,   127,
     128,   129,     0,     0,     0,     0,     0,     0,   233,   106,
     107,   108,   109,   110,   111,   112,   113,   114,     0,     0,
       0,     0,     0,     0,     0,     0,     0,   115,   116,   117,
     118,   119,   120,   121,     0,     0,     0,     0,     0,     0,
     122,   123,   124,   125,   126,   127,   128,   129,   279,     0,
       0,     0,     0,     0,   264,   106,   107,   108,   109,   110,
     111,   112,   113,   114,     0,     0,     0,     0,     0,     0,
       0,     0,     0,   115,   116,   117,   118,   119,   120,   121,
       0,     0,     0,     0,     0,     0,   122,   123,   124,   125,
     126,   127,   128,   129,   106,   107,   108,   109,   110,   111,
     112,   113,   114,     0,     0,     0,     0,     0,     0,     0,
       0,     0,   115,   116,   117,   118,   119,   120,   121,     0,
       0,     0,     0,     0,     0,   122,   123,   124,   125,   126,
     127,   128,   129,     0,     0,     0,     0,     0,   160,   106,
     107,   108,   109,   110,   111,   112,   113,   114,     0,     0,
     276,     0,     0,     0,     0,     0,     0,   115,   116,   117,
     118,   119,   120,   121,     0,     0,     0,     0,     0,     0,
     122,   123,   124,   125,   126,   127,   128,   129,     0,     0,
       0,     0,   277,   106,   107,   108,   109,   110,   111,   112,
     113,   114,     0,     0,     0,     0,     0,     0,     0,     0,
       0,   115,   116,   117,   118,   119,   120,   121,     0,     0,
       0,     0,     0,     0,   122,   123,   124,   125,   126,   127,
     128,   129,     0,     0,     0,     0,   238,   106,   107,   108,
     109,   110,   111,   112,   113,   114,     0,     0,   141,     0,
       0,     0,     0,     0,     0,   115,   116,   117,   118,   119,
     120,   121,     0,     0,     0,     0,     0,     0,   122,   123,
     124,   125,   126,   127,   128,   129,   106,   107,   108,   109,
     110,   111,   112,   113,   114,     0,     0,   293,     0,     0,
       0,     0,     0,     0,   115,   116,   117,   118,   119,   120,
     121,     0,     0,     0,     0,     0,     0,   122,   123,   124,
     125,   126,   127,   128,   129,   106,   107,   108,   109,   110,
     111,   112,   113,   114,     0,     0,     0,     0,     0,     0,
       0,     0,     0,   115,   116,   117,   118,   119,   120,   121,
       0,     0,     0,     0,     0,     0,   122,   123,   124,   125,
     126,   127,   128,   129,   106,     0,   108,   109,   110,   111,
     112,   113,   114,     0,     0,     0,     0,     0,     0,     0,
       0,     0,   115,   116,   117,   118,   119,   120,   121,     0,
       0,     0,     0,   114,     0,   122,   123,   124,   125,   126,
     127,   128,   129,   115,   116,   117,   118,   119,   120,   121,
       0,     0,     0,     0,   114,     0,     0,   123,   124,   125,
     126,   127,   128,   129,   115,     0,   117,   118,   119,   120,
     121,     0,     0,     0,     0,     0,     0,     0,     0,   124,
     125,   126,   127,   128,   129
};

static const yytype_int16 yycheck[] =
{
       0,    87,    19,   140,     1,    23,    35,     5,    14,     4,
       0,    67,     4,     4,    14,    15,     3,     4,     5,    68,
      69,    27,     4,    23,    14,    15,    26,    27,    71,     5,
      21,    67,    68,    23,    21,    12,    26,    71,    74,    68,
       5,     5,    68,    12,     5,     4,    72,     4,     4,    46,
      37,    38,     5,    40,    41,    42,     0,    44,    50,     0,
      78,    71,     5,    50,   201,    82,    64,    65,    66,    12,
       4,    35,    59,    71,    15,    73,    71,    64,    78,    76,
      71,    81,    23,    15,    71,    26,    73,    74,    78,    71,
      36,    68,    69,    50,    26,    71,    67,   234,   235,    68,
      69,     3,     4,     5,    68,    69,    71,    71,    73,    73,
      71,    64,    65,    66,   131,    67,   253,   254,    71,    21,
      68,    17,    68,    19,    72,    68,    69,   144,    71,     3,
       4,     5,   218,     5,   220,    37,    38,    78,    40,    41,
      42,   141,    44,    64,    65,    66,   146,    21,    50,     5,
      71,   141,    68,   150,    65,    66,   146,    59,     9,    10,
      71,     4,    64,    37,    38,    33,    40,    41,    42,    71,
      44,    73,    74,    20,    54,    43,    50,    45,    46,    47,
      48,    49,    65,    66,    43,    59,    67,    52,    71,    57,
      58,    59,    60,    61,    62,    63,    33,    71,     4,    73,
     141,    60,    61,    62,    63,   146,    43,     4,    72,   141,
      64,    65,    66,    63,   146,    68,    68,    71,     4,    72,
      72,    58,    59,    60,    61,    62,    63,    72,   228,     4,
      64,    65,    66,    64,    65,    66,   236,    71,   228,   239,
      71,   241,     4,    68,    68,     4,   236,    72,    72,   239,
      68,   241,    68,    68,    72,   255,    72,    72,    68,    68,
       4,     4,    72,    72,    71,   255,    64,    65,    66,    64,
      65,    66,    71,   273,   274,    20,   276,     4,    69,   279,
     280,   281,    71,   273,   274,    20,   276,   228,    71,   279,
     280,   281,    20,   293,    20,   236,   228,    20,   239,    20,
     241,    20,    20,   293,   236,    20,    20,   239,    20,   241,
      20,    -1,    23,   287,   255,   164,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,   255,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,   273,   274,    -1,   276,    -1,    -1,   279,   280,
     281,   273,   274,    -1,   276,    20,    -1,   279,   280,   281,
      25,    -1,   293,    28,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,   293,    -1,    38,    39,    27,    28,    29,    30,    31,
      32,    33,    -1,    48,    49,    -1,    -1,    -1,    53,    -1,
      55,    43,    44,    45,    46,    47,    48,    49,    -1,    -1,
      -1,    -1,    -1,    -1,    56,    57,    58,    59,    60,    61,
      62,    63,    -1,    -1,    -1,    80,    -1,    -1,    -1,    84,
      -1,    -1,    87,    -1,    -1,    90,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,   103,   104,
      -1,   106,   107,   108,   109,   110,   111,   112,   113,   114,
     115,   116,   117,   118,   119,   120,   121,   122,   123,   124,
     125,   126,   127,   128,   129,    -1,    -1,   132,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,   142,   143,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,   157,    -1,     4,   160,     6,     7,     8,   164,
      -1,    11,    -1,    13,    14,    15,    16,    33,    -1,    -1,
      -1,    21,    22,    23,    24,    -1,    -1,    43,    44,    45,
      46,    47,    48,    49,    34,    -1,    36,    -1,    -1,    -1,
      56,    57,    58,    59,    60,    61,    62,    63,    -1,    -1,
      -1,    51,    -1,    53,    54,    55,    -1,    -1,   213,    -1,
      -1,    -1,   217,   218,    -1,   220,    -1,    -1,    -1,    -1,
      -1,    71,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,   238,    -1,   240,    -1,    -1,    -1,     4,
     245,     6,     7,     8,   249,    -1,    11,    -1,    13,    14,
      15,    16,    -1,    18,    -1,    -1,    21,    22,    23,    24,
      25,    26,    27,    28,    29,    30,    31,    32,    33,    34,
      -1,    36,   277,    -1,    -1,    -1,    -1,    -1,    43,    44,
      45,    46,    47,    48,    49,    -1,    51,    -1,    53,    54,
      55,    56,    57,    58,    59,    60,    61,    62,    63,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    71,    25,    26,    27,
      28,    29,    30,    31,    32,    33,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    43,    44,    45,    46,    47,
      48,    49,    -1,    -1,    -1,    -1,    -1,    -1,    56,    57,
      58,    59,    60,    61,    62,    63,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    72,    25,    26,    27,    28,    29,
      30,    31,    32,    33,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    43,    44,    45,    46,    47,    48,    49,
      -1,    -1,    -1,    -1,    -1,    -1,    56,    57,    58,    59,
      60,    61,    62,    63,    -1,    -1,    -1,    -1,    -1,    -1,
      70,    25,    26,    27,    28,    29,    30,    31,    32,    33,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    43,
      44,    45,    46,    47,    48,    49,    -1,    -1,    -1,    -1,
      -1,    -1,    56,    57,    58,    59,    60,    61,    62,    63,
      -1,    -1,    -1,    -1,    -1,    -1,    70,    25,    26,    27,
      28,    29,    30,    31,    32,    33,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    43,    44,    45,    46,    47,
      48,    49,    -1,    -1,    -1,    -1,    -1,    -1,    56,    57,
      58,    59,    60,    61,    62,    63,    -1,    -1,    -1,    -1,
      -1,    -1,    70,    25,    26,    27,    28,    29,    30,    31,
      32,    33,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    43,    44,    45,    46,    47,    48,    49,    -1,    -1,
      -1,    -1,    -1,    -1,    56,    57,    58,    59,    60,    61,
      62,    63,    -1,    -1,    -1,    -1,    -1,    -1,    70,    25,
      26,    27,    28,    29,    30,    31,    32,    33,    -1,    -1,
      -1,    -1,    -1,    -1,    -1,    -1,    -1,    43,    44,    45,
      46,    47,    48,    49,    -1,    -1,    -1,    -1,    -1,    -1,
      56,    57,    58,    59,    60,    61,    62,    63,    18,    -1,
      -1,    -1,    -1,    -1,    70,    25,    26,    27,    28,    29,
      30,    31,    32,    33,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    43,    44,    45,    46,    47,    48,    49,
      -1,    -1,    -1,    -1,    -1,    -1,    56,    57,    58,    59,
      60,    61,    62,    63,    25,    26,    27,    28,    29,    30,
      31,    32,    33,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    43,    44,    45,    46,    47,    48,    49,    -1,
      -1,    -1,    -1,    -1,    -1,    56,    57,    58,    59,    60,
      61,    62,    63,    -1,    -1,    -1,    -1,    -1,    69,    25,
      26,    27,    28,    29,    30,    31,    32,    33,    -1,    -1,
      36,    -1,    -1,    -1,    -1,    -1,    -1,    43,    44,    45,
      46,    47,    48,    49,    -1,    -1,    -1,    -1,    -1,    -1,
      56,    57,    58,    59,    60,    61,    62,    63,    -1,    -1,
      -1,    -1,    68,    25,    26,    27,    28,    29,    30,    31,
      32,    33,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    43,    44,    45,    46,    47,    48,    49,    -1,    -1,
      -1,    -1,    -1,    -1,    56,    57,    58,    59,    60,    61,
      62,    63,    -1,    -1,    -1,    -1,    68,    25,    26,    27,
      28,    29,    30,    31,    32,    33,    -1,    -1,    36,    -1,
      -1,    -1,    -1,    -1,    -1,    43,    44,    45,    46,    47,
      48,    49,    -1,    -1,    -1,    -1,    -1,    -1,    56,    57,
      58,    59,    60,    61,    62,    63,    25,    26,    27,    28,
      29,    30,    31,    32,    33,    -1,    -1,    36,    -1,    -1,
      -1,    -1,    -1,    -1,    43,    44,    45,    46,    47,    48,
      49,    -1,    -1,    -1,    -1,    -1,    -1,    56,    57,    58,
      59,    60,    61,    62,    63,    25,    26,    27,    28,    29,
      30,    31,    32,    33,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    -1,    43,    44,    45,    46,    47,    48,    49,
      -1,    -1,    -1,    -1,    -1,    -1,    56,    57,    58,    59,
      60,    61,    62,    63,    25,    -1,    27,    28,    29,    30,
      31,    32,    33,    -1,    -1,    -1,    -1,    -1,    -1,    -1,
      -1,    -1,    43,    44,    45,    46,    47,    48,    49,    -1,
      -1,    -1,    -1,    33,    -1,    56,    57,    58,    59,    60,
      61,    62,    63,    43,    44,    45,    46,    47,    48,    49,
      -1,    -1,    -1,    -1,    33,    -1,    -1,    57,    58,    59,
      60,    61,    62,    63,    43,    -1,    45,    46,    47,    48,
      49,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    -1,    58,
      59,    60,    61,    62,    63
};

/* YYSTOS[STATE-NUM] -- The symbol kind of the accessing symbol of
   state STATE-NUM.  */
static const yytype_int8 yystos[] =
{
       0,     4,     6,     7,     8,    11,    13,    14,    15,    16,
      21,    22,    23,    24,    34,    36,    51,    53,    54,    55,
      71,    76,    77,    78,    81,    82,    83,    84,    85,    86,
      87,    89,    91,    92,    93,    95,   100,     5,    71,    73,
      99,   101,    67,    71,    71,     3,     4,     5,    37,    38,
      40,    41,    42,    44,    50,    59,    81,    90,    93,    94,
      95,    99,    81,    89,    93,    77,     4,     4,    90,    94,
       0,    86,    87,     4,    94,    77,     4,    89,    94,    67,
      12,    68,    69,    67,    64,    65,    66,    71,    80,    94,
      64,    74,    94,    96,    97,   102,     5,     5,    94,    94,
      94,    94,    71,    68,    64,    65,    25,    26,    27,    28,
      29,    30,    31,    32,    33,    43,    44,    45,    46,    47,
      48,    49,    56,    57,    58,    59,    60,    61,    62,    63,
       4,    69,    64,    65,    20,    54,    72,    67,    65,    66,
      71,    36,    52,    69,    35,    15,    18,    24,    86,    94,
       4,    93,    90,    94,     4,     4,    80,    68,    72,    94,
      69,    67,    68,    74,    98,     9,    10,    72,    72,     4,
      50,    79,    94,    94,     4,    94,    94,    94,    94,    94,
      94,    94,    94,    94,    94,    94,    94,    94,    94,    94,
      94,    94,    94,    94,    94,    94,    94,    94,    94,    65,
      66,    71,    90,    94,     4,     4,     4,    79,    77,    94,
      94,    90,    77,    64,    65,    70,     5,    69,    71,     5,
      71,    72,    94,    70,    94,    74,    96,    68,    72,    70,
       4,     4,    79,    70,    71,    71,    72,    20,    68,    36,
      17,    19,    88,    94,     4,    69,    94,    80,    80,    69,
       4,    50,    77,    71,    71,    72,    79,    79,    77,    94,
      77,    94,    77,    20,    70,    94,    72,    72,    94,    20,
      79,    79,    77,    72,    72,    20,    36,    68,    20,    18,
      72,    72,    20,    77,    77,    77,    94,    77,    77,    77,
      20,    20,    20,    36,    88,    20,    20,    77,    20
};

/* YYR1[RULE-NUM] -- Symbol kind of the left-hand side of rule RULE-NUM.  */
static const yytype_int8 yyr1[] =
{
       0,    75,    76,    77,    77,    77,    77,    78,    78,    78,
      78,    79,    79,    79,    79,    79,    80,    80,    80,    81,
      82,    83,    84,    85,    86,    86,    86,    86,    86,    86,
      86,    86,    86,    86,    86,    86,    86,    86,    86,    86,
      86,    86,    86,    86,    86,    86,    86,    86,    86,    86,
      86,    86,    86,    86,    87,    87,    87,    87,    88,    88,
      88,    89,    89,    89,    89,    89,    89,    90,    90,    91,
      91,    91,    92,    92,    93,    93,    93,    93,    93,    94,
      94,    94,    94,    94,    94,    94,    94,    94,    94,    94,
      94,    94,    94,    94,    94,    94,    94,    94,    94,    94,
      94,    94,    94,    94,    94,    94,    94,    94,    94,    94,
      94,    94,    94,    94,    94,    94,    95,    95,    95,    95,
      95,    95,    95,    95,    96,    96,    96,    97,    97,    98,
      98,    99,    99,    99,   101,   100,   102,   102
};

/* YYR2[RULE-NUM] -- Number of symbols on the right-hand side of rule RULE-NUM.  */
static const yytype_int8 yyr2[] =
{
       0,     2,     1,     0,     1,     2,     1,     2,     3,     1,
       2,     0,     1,     1,     3,     3,     0,     1,     3,     1,
       1,     1,     1,     1,     1,     2,     2,     3,     3,     4,
       3,     6,     5,     5,     4,     9,    11,     7,     6,     3,
       3,     3,     3,     2,     1,     4,     8,    10,    10,     4,
       1,     1,     1,     1,     1,     2,     1,     2,     0,     2,
       5,     1,     3,     4,     3,     5,     6,     1,     3,     7,
       9,     9,     2,     1,     1,     1,     3,     4,     3,     1,
       1,     1,     1,     1,     3,     3,     3,     3,     3,     3,
       3,     3,     3,     3,     3,     3,     3,     3,     3,     2,
       1,     1,     1,     2,     2,     2,     3,     3,     3,     3,
       3,     3,     3,     3,     3,     6,     4,     6,     6,     4,
       2,     2,     4,     4,     1,     3,     5,     1,     3,     1,
       1,     2,     3,     4,     0,     4,     0,     2
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
#line 129 "parser.y"
    {
        root_node = (yyvsp[0].ast_node); // Captures the entire AST root for main.c to use later
    }
#line 1627 "parser.c"
    break;

  case 3: /* statement_list: %empty  */
#line 135 "parser.y"
                { (yyval.ast_node) = NULL; }
#line 1633 "parser.c"
    break;

  case 4: /* statement_list: stat_list  */
#line 136 "parser.y"
                { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 1639 "parser.c"
    break;

  case 5: /* statement_list: stat_list last_statement  */
#line 137 "parser.y"
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
#line 1656 "parser.c"
    break;

  case 6: /* statement_list: last_statement  */
#line 149 "parser.y"
                     { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 1662 "parser.c"
    break;

  case 7: /* stat_list: statement ';'  */
#line 153 "parser.y"
                    { (yyval.ast_node) = (yyvsp[-1].ast_node); }
#line 1668 "parser.c"
    break;

  case 8: /* stat_list: stat_list statement ';'  */
#line 154 "parser.y"
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
#line 1685 "parser.c"
    break;

  case 9: /* stat_list: statement  */
#line 166 "parser.y"
                { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 1691 "parser.c"
    break;

  case 10: /* stat_list: stat_list statement  */
#line 167 "parser.y"
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
#line 1708 "parser.c"
    break;

  case 11: /* parameter_list: %empty  */
#line 182 "parser.y"
                {
        (yyval.ast_node) = NULL;
    }
#line 1716 "parser.c"
    break;

  case 12: /* parameter_list: TOKEN_IDENTIFIER  */
#line 185 "parser.y"
                       {
        (yyval.ast_node) = make_node_ident((yyvsp[0].string_val));
    }
#line 1724 "parser.c"
    break;

  case 13: /* parameter_list: TOKEN_DOTS  */
#line 188 "parser.y"
                 {
        // Create a marker identifier - will be detected in function_def
        (yyval.ast_node) = make_node_ident("...");
    }
#line 1733 "parser.c"
    break;

  case 14: /* parameter_list: parameter_list ',' TOKEN_IDENTIFIER  */
#line 192 "parser.y"
                                          {
        ASTNode* new_node = make_node_ident((yyvsp[0].string_val));
        ASTNode* current = (yyvsp[-2].ast_node);
        while(current->next) current = current->next;
        current->next = new_node;
        (yyval.ast_node) = (yyvsp[-2].ast_node);
    }
#line 1745 "parser.c"
    break;

  case 15: /* parameter_list: parameter_list ',' TOKEN_DOTS  */
#line 199 "parser.y"
                                    {
        ASTNode* new_node = make_node_ident("...");
        ASTNode* current = (yyvsp[-2].ast_node);
        while(current->next) current = current->next;
        current->next = new_node;
        (yyval.ast_node) = (yyvsp[-2].ast_node);
    }
#line 1757 "parser.c"
    break;

  case 16: /* argument_list: %empty  */
#line 209 "parser.y"
                { 
        (yyval.ast_node) = NULL;
    }
#line 1765 "parser.c"
    break;

  case 17: /* argument_list: expr  */
#line 212 "parser.y"
           { 
        (yyval.ast_node) = (yyvsp[0].ast_node);
    }
#line 1773 "parser.c"
    break;

  case 18: /* argument_list: argument_list ',' expr  */
#line 215 "parser.y"
                             {
        // Chain the new expression to the end of the argument list
        ASTNode* current = (yyvsp[-2].ast_node);
        while (current->next != NULL) {
            current = current->next;
        }
        current->next = (yyvsp[0].ast_node);
        (yyval.ast_node) = (yyvsp[-2].ast_node);
    }
#line 1787 "parser.c"
    break;

  case 19: /* func_start: TOKEN_FUNCTION  */
#line 228 "parser.y"
                   { (yyval.ast_node) = make_node(NODE_FUNCTION_DEF); g_func_depth++; }
#line 1793 "parser.c"
    break;

  case 20: /* while_start: TOKEN_WHILE  */
#line 232 "parser.y"
                   { (yyval.ast_node) = make_node(NODE_WHILE); }
#line 1799 "parser.c"
    break;

  case 21: /* repeat_start: TOKEN_REPEAT  */
#line 236 "parser.y"
                   { (yyval.ast_node) = make_node(NODE_REPEAT); }
#line 1805 "parser.c"
    break;

  case 22: /* for_start: TOKEN_FOR  */
#line 240 "parser.y"
                   { (yyval.ast_node) = make_node(NODE_FOR_NUMERIC); }
#line 1811 "parser.c"
    break;

  case 23: /* if_start: TOKEN_IF  */
#line 243 "parser.y"
                   { (yyval.ast_node) = make_node(NODE_IF); }
#line 1817 "parser.c"
    break;

  case 24: /* statement: function_call  */
#line 247 "parser.y"
                                 { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 1823 "parser.c"
    break;

  case 25: /* statement: TOKEN_PRINT_SHORT expr_list  */
#line 248 "parser.y"
                                  {
        /* PICO-8 `?a, b, c` == print(a, b, c) */
        (yyval.ast_node) = make_node(NODE_FUNCTION_CALL);
        (yyval.ast_node)->as.call.target = make_node_ident("print");
        (yyval.ast_node)->as.call.is_method_call = 0;
        (yyval.ast_node)->as.call.args_head = (yyvsp[0].ast_node);
    }
#line 1835 "parser.c"
    break;

  case 26: /* statement: TOKEN_GOTO TOKEN_IDENTIFIER  */
#line 255 "parser.y"
                                  {
        /* Lua 5.2+ goto -- see generate_block()'s label scopes */
        (yyval.ast_node) = make_node(NODE_GOTO);
        (yyval.ast_node)->as.id.name = (yyvsp[0].string_val);
    }
#line 1845 "parser.c"
    break;

  case 27: /* statement: TOKEN_DBCOLON TOKEN_IDENTIFIER TOKEN_DBCOLON  */
#line 260 "parser.y"
                                                   {
        (yyval.ast_node) = make_node(NODE_LABEL);
        (yyval.ast_node)->as.id.name = (yyvsp[-1].string_val);
    }
#line 1854 "parser.c"
    break;

  case 28: /* statement: var_list '=' expr_list  */
#line 264 "parser.y"
                             {
        (yyval.ast_node) = make_node(NODE_MULTIPLE_ASSIGNMENT);
        (yyval.ast_node)->as.mult_assign.targets_head = (yyvsp[-2].ast_node);
        (yyval.ast_node)->as.mult_assign.values_head = (yyvsp[0].ast_node);
        (yyval.ast_node)->as.mult_assign.is_local = 0;
    }
#line 1865 "parser.c"
    break;

  case 29: /* statement: TOKEN_LOCAL var_list '=' expr_list  */
#line 270 "parser.y"
                                         {
        (yyval.ast_node) = make_node(NODE_MULTIPLE_ASSIGNMENT);
        (yyval.ast_node)->as.mult_assign.targets_head = (yyvsp[-2].ast_node);
        (yyval.ast_node)->as.mult_assign.values_head = (yyvsp[0].ast_node);
        (yyval.ast_node)->as.mult_assign.is_local = 1;
    }
#line 1876 "parser.c"
    break;

  case 30: /* statement: var_list TOKEN_COMPOUND_ASSIGN expr  */
#line 276 "parser.y"
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
#line 1949 "parser.c"
    break;

  case 31: /* statement: prefix_expr '[' expr ']' '=' expr  */
#line 345 "parser.y"
    { 
        // $1 = table, $3 = key, $6 = value being assigned
        (yyval.ast_node) = make_node_table_set ((yyvsp[-5].ast_node), (yyvsp[-3].ast_node), (yyvsp[0].ast_node)); 
    }
#line 1958 "parser.c"
    break;

  case 32: /* statement: prefix_expr '.' TOKEN_IDENTIFIER '=' expr  */
#line 350 "parser.y"
    {
        ASTNode *string_key  = make_node_string ((yyvsp[-2].string_val));
        (yyval.ast_node)                   = make_node_table_set ((yyvsp[-4].ast_node), string_key, (yyvsp[0].ast_node));
    }
#line 1967 "parser.c"
    break;

  case 33: /* statement: while_start expr TOKEN_DO statement_list TOKEN_END  */
#line 354 "parser.y"
                                                         {
        (yyval.ast_node) = (yyvsp[-4].ast_node);
        (yyval.ast_node)->as.while_loop.condition = (yyvsp[-3].ast_node);
        (yyval.ast_node)->as.while_loop.body = (yyvsp[-1].ast_node);
    }
#line 1977 "parser.c"
    break;

  case 34: /* statement: repeat_start statement_list TOKEN_UNTIL expr  */
#line 359 "parser.y"
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
#line 1993 "parser.c"
    break;

  case 35: /* statement: for_start TOKEN_IDENTIFIER '=' expr ',' expr TOKEN_DO statement_list TOKEN_END  */
#line 370 "parser.y"
                                                                                     {
        (yyval.ast_node) = make_node(NODE_FOR_NUMERIC);
        (yyval.ast_node)->as.for_numeric.index_name  = (yyvsp[-7].string_val);
        (yyval.ast_node)->as.for_numeric.start_expr  = (yyvsp[-5].ast_node);
        (yyval.ast_node)->as.for_numeric.stop_expr   = (yyvsp[-3].ast_node);
        (yyval.ast_node)->as.for_numeric.step_expr   = NULL; // Omitted step
        (yyval.ast_node)->as.for_numeric.body        = (yyvsp[-1].ast_node);
    }
#line 2006 "parser.c"
    break;

  case 36: /* statement: for_start TOKEN_IDENTIFIER '=' expr ',' expr ',' expr TOKEN_DO statement_list TOKEN_END  */
#line 378 "parser.y"
                                                                                              {
        (yyval.ast_node) = make_node(NODE_FOR_NUMERIC);
        (yyval.ast_node)->as.for_numeric.index_name  = (yyvsp[-9].string_val);
        (yyval.ast_node)->as.for_numeric.start_expr  = (yyvsp[-7].ast_node);
        (yyval.ast_node)->as.for_numeric.stop_expr   = (yyvsp[-5].ast_node);
        (yyval.ast_node)->as.for_numeric.step_expr   = (yyvsp[-3].ast_node);  // Explicit step
        (yyval.ast_node)->as.for_numeric.body        = (yyvsp[-1].ast_node);
    }
#line 2019 "parser.c"
    break;

  case 37: /* statement: for_start var_list TOKEN_IN expr_list TOKEN_DO statement_list TOKEN_END  */
#line 386 "parser.y"
                                                                              {
        (yyval.ast_node) = make_node(NODE_FOR_GENERIC);
        (yyval.ast_node)->as.for_generic.var_list    = (yyvsp[-5].ast_node);
        (yyval.ast_node)->as.for_generic.iter_expr   = (yyvsp[-3].ast_node);
        (yyval.ast_node)->as.for_generic.body        = (yyvsp[-1].ast_node);
    }
#line 2030 "parser.c"
    break;

  case 38: /* statement: if_start expr TOKEN_THEN statement_list else_branch TOKEN_END  */
#line 392 "parser.y"
                                                                    { 
        (yyval.ast_node)                             = (yyvsp[-5].ast_node);
        (yyval.ast_node) -> as.if_stmt.condition     = (yyvsp[-4].ast_node);
        (yyval.ast_node) -> as.if_stmt.if_body       = (yyvsp[-2].ast_node);
        (yyval.ast_node) -> as.if_stmt.else_body     = (yyvsp[-1].ast_node);
    }
#line 2041 "parser.c"
    break;

  case 39: /* statement: if_start expr statement  */
#line 398 "parser.y"
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
#line 2074 "parser.c"
    break;

  case 40: /* statement: if_start expr TOKEN_RETURN  */
#line 426 "parser.y"
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
#line 2121 "parser.c"
    break;

  case 41: /* statement: if_start expr TOKEN_BREAK  */
#line 468 "parser.y"
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
#line 2139 "parser.c"
    break;

  case 42: /* statement: TOKEN_DO statement_list TOKEN_END  */
#line 481 "parser.y"
                                        {
        // Bare scoping block: no condition, no loop tracking -- just gives
        // the enclosed statements their own lexical scope. Most useful for
        // deliberately ending a 'local' declaration's shadow before the
        // rest of the enclosing block, without needing an 'if true then'
        // workaround.
        (yyval.ast_node) = make_node_do_block ((yyvsp[-1].ast_node));
    }
#line 2152 "parser.c"
    break;

  case 43: /* statement: TOKEN_LOCAL var_list  */
#line 489 "parser.y"
                           {
        (yyval.ast_node) = make_node(NODE_MULTIPLE_ASSIGNMENT);
        (yyval.ast_node)->as.mult_assign.is_local = 1;
        (yyval.ast_node)->as.mult_assign.targets_head = (yyvsp[0].ast_node);
        (yyval.ast_node)->as.mult_assign.values_head = NULL; 
    }
#line 2163 "parser.c"
    break;

  case 44: /* statement: function_def  */
#line 495 "parser.y"
                                 { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 2169 "parser.c"
    break;

  case 45: /* statement: TOKEN_ASM '(' TOKEN_STRING ')'  */
#line 496 "parser.y"
                                     { 
        (yyval.ast_node) = make_node(NODE_ASM);
        (yyval.ast_node)->as.inline_asm.code = (yyvsp[-1].string_val);
    }
#line 2178 "parser.c"
    break;

  case 46: /* statement: TOKEN_LOCAL func_start TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 501 "parser.y"
    { g_func_depth--; 
        // local function myfunc(...) ... end
        // This is equivalent to: local myfunc = function(...) ... end

                // 1. Get the pre-allocated function_def node from func_start
        ASTNode* func_def = (yyvsp[-6].ast_node);
        func_def->as.function_def.name = strdup((yyvsp[-5].string_val));
        func_def->as.function_def.params = (yyvsp[-3].ast_node);
        note_function_param_count(func_def->as.function_def.params);
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

        if (g_func_depth > 0) {
            // Inside another function: a real local closure, exactly
            // `local NAME; NAME = function(...) ... end` -- so the body can
            // capture the enclosing function's locals (and itself, for
            // recursion). It used to become a global, capture-less named
            // function, which read garbage for captured variables.
            static int local_fn_counter = 0;
            char buf[256];
            snprintf (buf, sizeof (buf), "%s__l%d", (yyvsp[-5].string_val), local_fn_counter++);
            func_def->as.function_def.name = strdup (buf);

            ASTNode *decl = make_node (NODE_MULTIPLE_ASSIGNMENT);
            decl->as.mult_assign.is_local = 1;
            decl->as.mult_assign.targets_head = make_node_ident ((yyvsp[-5].string_val));
            decl->as.mult_assign.values_head = NULL;

            ASTNode *func_ptr = make_node (NODE_FUNCTION_POINTER);
            func_ptr->as.func_ptr.mangled_name = strdup (buf);
            func_ptr->as.func_ptr.func_def = func_def;

            ASTNode *assign = make_node (NODE_MULTIPLE_ASSIGNMENT);
            assign->as.mult_assign.is_local = 0;
            assign->as.mult_assign.targets_head = make_node_ident ((yyvsp[-5].string_val));
            assign->as.mult_assign.values_head = func_ptr;

            decl->next = assign;
            (yyval.ast_node) = decl;
        } else {
            // Top level: stays a named function (direct calls, no closure
            // needed -- there are no enclosing locals to capture).
            (yyval.ast_node) = func_def;
        }

        /* until we pursue actual local functions, comment this out
        // 1. Get the pre-allocated function_def node from func_start
        ASTNode* func_def = $2;
        func_def->as.function_def.name = strdup($3);
        func_def->as.function_def.params = $5;
        note_function_param_count(func_def->as.function_def.params);
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
#line 2271 "parser.c"
    break;

  case 47: /* statement: TOKEN_LOCAL func_start TOKEN_IDENTIFIER ':' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 590 "parser.y"
    { g_func_depth--; 
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
        note_function_param_count(func_def->as.function_def.params);
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
#line 2319 "parser.c"
    break;

  case 48: /* statement: TOKEN_LOCAL func_start TOKEN_IDENTIFIER '.' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 634 "parser.y"
    { g_func_depth--; 
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
        note_function_param_count(func_def->as.function_def.params);
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
#line 2355 "parser.c"
    break;

  case 49: /* statement: TOKEN_RAWASM '(' TOKEN_STRING ')'  */
#line 665 "parser.y"
                                        { 
        (yyval.ast_node) = make_node(NODE_RAWASM);
        (yyval.ast_node)->as.inline_asm.code = (yyvsp[-1].string_val);
    }
#line 2364 "parser.c"
    break;

  case 50: /* statement: TOKEN_COMMENT_LINE  */
#line 669 "parser.y"
                         {
        (yyval.ast_node) = make_node(NODE_COMMENT_LINE);
        (yyval.ast_node)->as.string_val.value = (yyvsp[0].string_val);
    }
#line 2373 "parser.c"
    break;

  case 51: /* statement: TOKEN_COMMENT_BLOCK  */
#line 673 "parser.y"
                          {
        (yyval.ast_node) = make_node(NODE_COMMENT_BLOCK);
        (yyval.ast_node)->as.string_val.value = (yyvsp[0].string_val);
    }
#line 2382 "parser.c"
    break;

  case 52: /* statement: tic80_section  */
#line 677 "parser.y"
                                { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 2388 "parser.c"
    break;

  case 53: /* statement: TOKEN_CART_HINT  */
#line 678 "parser.y"
                      {
        (yyval.ast_node) = make_node_cart_hint((yyvsp[0].string_val));
    }
#line 2396 "parser.c"
    break;

  case 54: /* last_statement: return_stmt  */
#line 684 "parser.y"
                         { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 2402 "parser.c"
    break;

  case 55: /* last_statement: return_stmt ';'  */
#line 685 "parser.y"
                         { (yyval.ast_node) = (yyvsp[-1].ast_node); }
#line 2408 "parser.c"
    break;

  case 56: /* last_statement: TOKEN_BREAK  */
#line 686 "parser.y"
                          { (yyval.ast_node) = make_node(NODE_BREAK); }
#line 2414 "parser.c"
    break;

  case 57: /* last_statement: TOKEN_BREAK ';'  */
#line 687 "parser.y"
                          { (yyval.ast_node) = make_node(NODE_BREAK); }
#line 2420 "parser.c"
    break;

  case 58: /* else_branch: %empty  */
#line 691 "parser.y"
                                 { (yyval.ast_node)  = NULL; }
#line 2426 "parser.c"
    break;

  case 59: /* else_branch: TOKEN_ELSE statement_list  */
#line 692 "parser.y"
                                 { (yyval.ast_node)  = (yyvsp[0].ast_node); }
#line 2432 "parser.c"
    break;

  case 60: /* else_branch: TOKEN_ELSEIF expr TOKEN_THEN statement_list else_branch  */
#line 694 "parser.y"
    {
        // Treat elseif exactly like a nested IF statement assigned to the else_body
        (yyval.ast_node)                             = make_node(NODE_IF);
        (yyval.ast_node) -> as.if_stmt.condition     = (yyvsp[-3].ast_node);
        (yyval.ast_node) -> as.if_stmt.if_body       = (yyvsp[-1].ast_node);
        (yyval.ast_node) -> as.if_stmt.else_body     = (yyvsp[0].ast_node);
    }
#line 2444 "parser.c"
    break;

  case 61: /* var_list: TOKEN_IDENTIFIER  */
#line 705 "parser.y"
                     {
        (yyval.ast_node) = make_node_ident((yyvsp[0].string_val));
    }
#line 2452 "parser.c"
    break;

  case 62: /* var_list: prefix_expr '.' TOKEN_IDENTIFIER  */
#line 708 "parser.y"
                                       {
        ASTNode *string_key = make_node_string ((yyvsp[0].string_val));
        (yyval.ast_node) = make_node_table_get ((yyvsp[-2].ast_node), string_key);
    }
#line 2461 "parser.c"
    break;

  case 63: /* var_list: prefix_expr '[' expr ']'  */
#line 712 "parser.y"
                               {
        (yyval.ast_node) = make_node_table_get ((yyvsp[-3].ast_node), (yyvsp[-1].ast_node));
    }
#line 2469 "parser.c"
    break;

  case 64: /* var_list: var_list ',' TOKEN_IDENTIFIER  */
#line 715 "parser.y"
                                    {
        ASTNode* new_ident = make_node_ident((yyvsp[0].string_val));
        ASTNode* curr = (yyvsp[-2].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = new_ident;
        (yyval.ast_node) = (yyvsp[-2].ast_node);
    }
#line 2481 "parser.c"
    break;

  case 65: /* var_list: var_list ',' prefix_expr '.' TOKEN_IDENTIFIER  */
#line 722 "parser.y"
                                                    {
        ASTNode *string_key = make_node_string ((yyvsp[0].string_val));
        ASTNode *new_target = make_node_table_get ((yyvsp[-2].ast_node), string_key);
        ASTNode* curr = (yyvsp[-4].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = new_target;
        (yyval.ast_node) = (yyvsp[-4].ast_node);
    }
#line 2494 "parser.c"
    break;

  case 66: /* var_list: var_list ',' prefix_expr '[' expr ']'  */
#line 730 "parser.y"
                                            {
        ASTNode *new_target = make_node_table_get ((yyvsp[-3].ast_node), (yyvsp[-1].ast_node));
        ASTNode* curr = (yyvsp[-5].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = new_target;
        (yyval.ast_node) = (yyvsp[-5].ast_node);
    }
#line 2506 "parser.c"
    break;

  case 67: /* expr_list: expr  */
#line 740 "parser.y"
         { 
        (yyval.ast_node) = (yyvsp[0].ast_node); 
    }
#line 2514 "parser.c"
    break;

  case 68: /* expr_list: expr_list ',' expr  */
#line 743 "parser.y"
                         { 
        ASTNode* curr = (yyvsp[-2].ast_node);
        while(curr->next) curr = curr->next;
        curr->next = (yyvsp[0].ast_node);
        (yyval.ast_node) = (yyvsp[-2].ast_node); 
    }
#line 2525 "parser.c"
    break;

  case 69: /* function_def: func_start TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 753 "parser.y"
                                                                                { g_func_depth--; 
        // 1. Build the structural function definition using pre-allocated node
        ASTNode* func_def = (yyvsp[-6].ast_node);
        func_def->as.function_def.name = strdup((yyvsp[-5].string_val));
        func_def->as.function_def.params = (yyvsp[-3].ast_node);
        note_function_param_count(func_def->as.function_def.params);
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
#line 2562 "parser.c"
    break;

  case 70: /* function_def: func_start TOKEN_IDENTIFIER '.' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 786 "parser.y"
                                                                                                     { g_func_depth--; 
        // Lua semantics: exactly `my_table.my_func = function(...) ... end`.
        // Built as a function EXPRESSION (func_def carried by the pointer,
        // uniquely named) so that a definition inside another function
        // captures that function's locals as a closure -- evercore's
        // `function obj.left() return obj.x ... end` inside init_object().
        // (It used to become a hoisted, capture-less function named
        // my_table_my_func, which read garbage for `obj`.)
        (yyval.ast_node) = make_method_function_assignment((yyvsp[-8].ast_node), (yyvsp[-7].string_val), (yyvsp[-5].string_val), (yyvsp[-3].ast_node), (yyvsp[-1].ast_node), false);
    }
#line 2577 "parser.c"
    break;

  case 71: /* function_def: func_start TOKEN_IDENTIFIER ':' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END  */
#line 797 "parser.y"
                                                                                                     { g_func_depth--; 
        // `my_table.my_func = function(self, ...) ... end` -- see the dot form.
        (yyval.ast_node) = make_method_function_assignment((yyvsp[-8].ast_node), (yyvsp[-7].string_val), (yyvsp[-5].string_val), (yyvsp[-3].ast_node), (yyvsp[-1].ast_node), true);
    }
#line 2586 "parser.c"
    break;

  case 72: /* return_stmt: TOKEN_RETURN expr_list  */
#line 804 "parser.y"
                           {
        (yyval.ast_node) = make_node(NODE_RETURN);
        (yyval.ast_node)->as.return_stmt.expressions_head = (yyvsp[0].ast_node);
        (yyval.ast_node)->as.return_stmt.parent_func_arg_count = 0;
    }
#line 2596 "parser.c"
    break;

  case 73: /* return_stmt: TOKEN_RETURN  */
#line 809 "parser.y"
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
#line 2615 "parser.c"
    break;

  case 74: /* prefix_expr: TOKEN_IDENTIFIER  */
#line 826 "parser.y"
                     { 
        (yyval.ast_node) = make_node_ident((yyvsp[0].string_val)); 
    }
#line 2623 "parser.c"
    break;

  case 75: /* prefix_expr: function_call  */
#line 829 "parser.y"
                    { 
        (yyval.ast_node) = (yyvsp[0].ast_node); 
    }
#line 2631 "parser.c"
    break;

  case 76: /* prefix_expr: '(' expr ')'  */
#line 832 "parser.y"
                   { 
        (yyval.ast_node) = (yyvsp[-1].ast_node); 
    }
#line 2639 "parser.c"
    break;

  case 77: /* prefix_expr: prefix_expr '[' expr ']'  */
#line 835 "parser.y"
                               {
        (yyval.ast_node) = make_node(NODE_TABLE_GET);
        (yyval.ast_node)->as.table_get.table_expr = (yyvsp[-3].ast_node);
        (yyval.ast_node)->as.table_get.key = (yyvsp[-1].ast_node);
    }
#line 2649 "parser.c"
    break;

  case 78: /* prefix_expr: prefix_expr '.' TOKEN_IDENTIFIER  */
#line 840 "parser.y"
                                       {
        ASTNode *string_key = make_node_string((yyvsp[0].string_val));
        (yyval.ast_node) = make_node(NODE_TABLE_GET);
        (yyval.ast_node)->as.table_get.table_expr = (yyvsp[-2].ast_node);
        (yyval.ast_node)->as.table_get.key = string_key;
    }
#line 2660 "parser.c"
    break;

  case 79: /* expr: TOKEN_DOTS  */
#line 849 "parser.y"
               {
        (yyval.ast_node) = make_node(NODE_VARIADIC_EXPR);
    }
#line 2668 "parser.c"
    break;

  case 80: /* expr: TOKEN_NUMBER  */
#line 852 "parser.y"
                   {
        (yyval.ast_node) = make_node(NODE_NUMBER);
        (yyval.ast_node)->as.number.val = (yyvsp[0].number_val);
    }
#line 2677 "parser.c"
    break;

  case 81: /* expr: TOKEN_STRING  */
#line 856 "parser.y"
                        { (yyval.ast_node) = make_node_string((yyvsp[0].string_val)); }
#line 2683 "parser.c"
    break;

  case 82: /* expr: table_constructor  */
#line 857 "parser.y"
                        { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 2689 "parser.c"
    break;

  case 83: /* expr: prefix_expr  */
#line 858 "parser.y"
                        { (yyval.ast_node) = (yyvsp[0].ast_node); }
#line 2695 "parser.c"
    break;

  case 84: /* expr: expr '+' expr  */
#line 859 "parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_ADD, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2701 "parser.c"
    break;

  case 85: /* expr: expr '-' expr  */
#line 860 "parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_SUB, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2707 "parser.c"
    break;

  case 86: /* expr: expr '*' expr  */
#line 861 "parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_MUL, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2713 "parser.c"
    break;

  case 87: /* expr: expr TOKEN_FLOORDIV expr  */
#line 862 "parser.y"
                               { (yyval.ast_node) = make_node_binary (NODE_FLOORDIV, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2719 "parser.c"
    break;

  case 88: /* expr: expr '/' expr  */
#line 863 "parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_DIV, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2725 "parser.c"
    break;

  case 89: /* expr: expr '%' expr  */
#line 864 "parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_MOD, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2731 "parser.c"
    break;

  case 90: /* expr: expr '^' expr  */
#line 865 "parser.y"
                        { (yyval.ast_node) = make_node_binary (NODE_POW, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2737 "parser.c"
    break;

  case 91: /* expr: expr '&' expr  */
#line 866 "parser.y"
                            { (yyval.ast_node) = make_node_binary (NODE_BAND, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2743 "parser.c"
    break;

  case 92: /* expr: expr '|' expr  */
#line 867 "parser.y"
                            { (yyval.ast_node) = make_node_binary (NODE_BOR,  (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2749 "parser.c"
    break;

  case 93: /* expr: expr TOKEN_BXOR expr  */
#line 868 "parser.y"
                            { (yyval.ast_node) = make_node_binary (NODE_BXOR, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2755 "parser.c"
    break;

  case 94: /* expr: expr TOKEN_SHL expr  */
#line 869 "parser.y"
                            { (yyval.ast_node) = make_node_binary (NODE_SHL,  (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2761 "parser.c"
    break;

  case 95: /* expr: expr TOKEN_SHR expr  */
#line 870 "parser.y"
                            { (yyval.ast_node) = make_node_binary (NODE_SHR,  (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2767 "parser.c"
    break;

  case 96: /* expr: expr TOKEN_LSHR expr  */
#line 871 "parser.y"
                            { (yyval.ast_node) = make_node_binary (NODE_LSHR, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2773 "parser.c"
    break;

  case 97: /* expr: expr TOKEN_ROTL expr  */
#line 872 "parser.y"
                            { (yyval.ast_node) = make_node_binary (NODE_ROTL, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2779 "parser.c"
    break;

  case 98: /* expr: expr TOKEN_ROTR expr  */
#line 873 "parser.y"
                            { (yyval.ast_node) = make_node_binary (NODE_ROTR, (yyvsp[-2].ast_node), (yyvsp[0].ast_node)); }
#line 2785 "parser.c"
    break;

  case 99: /* expr: TOKEN_BXOR expr  */
#line 874 "parser.y"
                                        { (yyval.ast_node) = make_node_unary (OP_BNOT, (yyvsp[0].ast_node)); }
#line 2791 "parser.c"
    break;

  case 100: /* expr: TOKEN_TRUE  */
#line 875 "parser.y"
                  { (yyval.ast_node) = make_node_boolean (true);  }
#line 2797 "parser.c"
    break;

  case 101: /* expr: TOKEN_FALSE  */
#line 876 "parser.y"
                  { (yyval.ast_node) = make_node_boolean (false); }
#line 2803 "parser.c"
    break;

  case 102: /* expr: TOKEN_NIL  */
#line 877 "parser.y"
                  { (yyval.ast_node) = make_node_nil ();          }
#line 2809 "parser.c"
    break;

  case 103: /* expr: TOKEN_LEN expr  */
#line 878 "parser.y"
                        { (yyval.ast_node) = make_node_unary  (OP_LEN,   (yyvsp[0].ast_node));     }
#line 2815 "parser.c"
    break;

  case 104: /* expr: '-' expr  */
#line 879 "parser.y"
                                 { (yyval.ast_node) = make_node_unary (OP_UNM, (yyvsp[0].ast_node)); }
#line 2821 "parser.c"
    break;

  case 105: /* expr: TOKEN_NOT expr  */
#line 880 "parser.y"
                                 { (yyval.ast_node) = make_node_unary (OP_NOT, (yyvsp[0].ast_node)); }
#line 2827 "parser.c"
    break;

  case 106: /* expr: expr TOKEN_EQ expr  */
#line 881 "parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_EQ;  (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2833 "parser.c"
    break;

  case 107: /* expr: expr TOKEN_NEQ expr  */
#line 882 "parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_NEQ; (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2839 "parser.c"
    break;

  case 108: /* expr: expr TOKEN_LT expr  */
#line 883 "parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_LT;  (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2845 "parser.c"
    break;

  case 109: /* expr: expr TOKEN_GT expr  */
#line 884 "parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_GT;  (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2851 "parser.c"
    break;

  case 110: /* expr: expr TOKEN_LE expr  */
#line 885 "parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_LE;  (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2857 "parser.c"
    break;

  case 111: /* expr: expr TOKEN_GE expr  */
#line 886 "parser.y"
                              { (yyval.ast_node) = make_node(NODE_RELATIONAL); (yyval.ast_node)->as.binary.operator = OP_GE;  (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node); (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2863 "parser.c"
    break;

  case 112: /* expr: expr TOKEN_AND expr  */
#line 887 "parser.y"
                              { (yyval.ast_node) = make_node(NODE_AND);        (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node);     (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2869 "parser.c"
    break;

  case 113: /* expr: expr TOKEN_OR expr  */
#line 888 "parser.y"
                              { (yyval.ast_node) = make_node(NODE_OR);         (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node);     (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2875 "parser.c"
    break;

  case 114: /* expr: expr TOKEN_CONCAT expr  */
#line 889 "parser.y"
                              { (yyval.ast_node) = make_node(NODE_CONCAT);     (yyval.ast_node)->as.binary.left = (yyvsp[-2].ast_node);     (yyval.ast_node)->as.binary.right = (yyvsp[0].ast_node); }
#line 2881 "parser.c"
    break;

  case 115: /* expr: func_start '(' parameter_list ')' statement_list TOKEN_END  */
#line 891 "parser.y"
    { g_func_depth--; 
        static int anon_counter = 0;
        char buf[64];
        snprintf(buf, sizeof(buf), "__anon_%d", anon_counter++);

        ASTNode* func_def = (yyvsp[-5].ast_node);
        func_def->as.function_def.name = strdup(buf);
        func_def->as.function_def.params = (yyvsp[-3].ast_node);
        note_function_param_count(func_def->as.function_def.params);
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
#line 2914 "parser.c"
    break;

  case 116: /* function_call: TOKEN_IDENTIFIER '(' argument_list ')'  */
#line 922 "parser.y"
                                           {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.target = make_node_ident((yyvsp[-3].string_val));
        node->as.call.is_method_call = 0; 
        node->as.call.args_head = (yyvsp[-1].ast_node);
        (yyval.ast_node) = node;
    }
#line 2926 "parser.c"
    break;

  case 117: /* function_call: prefix_expr '.' TOKEN_IDENTIFIER '(' argument_list ')'  */
#line 929 "parser.y"
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
#line 2943 "parser.c"
    break;

  case 118: /* function_call: prefix_expr ':' TOKEN_IDENTIFIER '(' argument_list ')'  */
#line 941 "parser.y"
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
#line 2960 "parser.c"
    break;

  case 119: /* function_call: prefix_expr '(' argument_list ')'  */
#line 953 "parser.y"
                                        {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.target = (yyvsp[-3].ast_node);
        node->as.call.is_method_call = 0;
        node->as.call.args_head = (yyvsp[-1].ast_node);
        (yyval.ast_node) = node;
    }
#line 2972 "parser.c"
    break;

  case 120: /* function_call: TOKEN_IDENTIFIER TOKEN_STRING  */
#line 961 "parser.y"
                                    {
        (yyval.ast_node) = make_node(NODE_FUNCTION_CALL);
        (yyval.ast_node)->as.call.target = make_node_ident((yyvsp[-1].string_val));
        (yyval.ast_node)->as.call.is_method_call = 0;
        (yyval.ast_node)->as.call.args_head = make_node_string((yyvsp[0].string_val));
    }
#line 2983 "parser.c"
    break;

  case 121: /* function_call: TOKEN_IDENTIFIER table_constructor  */
#line 967 "parser.y"
                                         {
        (yyval.ast_node) = make_node(NODE_FUNCTION_CALL);
        (yyval.ast_node)->as.call.target = make_node_ident((yyvsp[-1].string_val));
        (yyval.ast_node)->as.call.is_method_call = 0;
        (yyval.ast_node)->as.call.args_head = (yyvsp[0].ast_node);
    }
#line 2994 "parser.c"
    break;

  case 122: /* function_call: prefix_expr '.' TOKEN_IDENTIFIER TOKEN_STRING  */
#line 973 "parser.y"
                                                    {
        ASTNode* dynamic_lookup = make_node(NODE_TABLE_GET);
        dynamic_lookup->as.table_get.table_expr = (yyvsp[-3].ast_node);
        dynamic_lookup->as.table_get.key = make_node_string((yyvsp[-1].string_val));
        (yyval.ast_node) = make_node(NODE_FUNCTION_CALL);
        (yyval.ast_node)->as.call.target = dynamic_lookup;
        (yyval.ast_node)->as.call.is_method_call = 0;
        (yyval.ast_node)->as.call.args_head = make_node_string((yyvsp[0].string_val));
    }
#line 3008 "parser.c"
    break;

  case 123: /* function_call: prefix_expr ':' TOKEN_IDENTIFIER TOKEN_STRING  */
#line 982 "parser.y"
                                                    {
        ASTNode* dynamic_lookup = make_node(NODE_TABLE_GET);
        dynamic_lookup->as.table_get.table_expr = (yyvsp[-3].ast_node);
        dynamic_lookup->as.table_get.key = make_node_string((yyvsp[-1].string_val));
        (yyval.ast_node) = make_node(NODE_FUNCTION_CALL);
        (yyval.ast_node)->as.call.target = dynamic_lookup;
        (yyval.ast_node)->as.call.is_method_call = 1;
        (yyval.ast_node)->as.call.args_head = make_node_string((yyvsp[0].string_val));
    }
#line 3022 "parser.c"
    break;

  case 124: /* field: expr  */
#line 994 "parser.y"
         {
        // Array-style: {value} -> implicit sequential key
        (yyval.ast_node) = (yyvsp[0].ast_node);
    }
#line 3031 "parser.c"
    break;

  case 125: /* field: expr '=' expr  */
#line 998 "parser.y"
                    {
    // Record-style: {key = value}
    // Convert identifier key to string literal (Lua semantics: x=8 means key "x", not var x)
    ASTNode *key_node = (yyvsp[-2].ast_node);
    if (key_node->type == NODE_IDENTIFIER) {
        key_node = make_node_string(key_node->as.id.name);
    }
    (yyval.ast_node) = make_node_table_set(NULL, key_node, (yyvsp[0].ast_node));
}
#line 3045 "parser.c"
    break;

  case 126: /* field: '[' expr ']' '=' expr  */
#line 1007 "parser.y"
                            {
        // Explicit key: {[key] = value}
        (yyval.ast_node) = make_node_table_set(NULL, (yyvsp[-3].ast_node), (yyvsp[0].ast_node));
    }
#line 3054 "parser.c"
    break;

  case 127: /* field_list: field  */
#line 1014 "parser.y"
          {
        (yyval.ast_node) = (yyvsp[0].ast_node);
    }
#line 3062 "parser.c"
    break;

  case 128: /* field_list: field_list field_sep field  */
#line 1017 "parser.y"
                                 {
        // Chain fields together via next pointer
        ASTNode* curr = (yyvsp[-2].ast_node);
        while (curr->next) curr = curr->next;
        curr->next = (yyvsp[0].ast_node);
        (yyval.ast_node) = (yyvsp[-2].ast_node);
    }
#line 3074 "parser.c"
    break;

  case 131: /* table_constructor: '{' '}'  */
#line 1032 "parser.y"
            {
        (yyval.ast_node) = make_node_table_constructor(NULL);
    }
#line 3082 "parser.c"
    break;

  case 132: /* table_constructor: '{' field_list '}'  */
#line 1035 "parser.y"
                         {
        (yyval.ast_node) = make_node_table_constructor((yyvsp[-1].ast_node));
    }
#line 3090 "parser.c"
    break;

  case 133: /* table_constructor: '{' field_list field_sep '}'  */
#line 1038 "parser.y"
                                   {
        // Trailing comma before the closing brace -- e.g.
        //   { [1] = a, [2] = b, }
        // Standard, idiomatic Lua; the parser previously had no
        // production for a comma immediately followed by '}', since
        // field_list only ever grows via 'field_list , field' and a
        // field must start with an expression token, which '}' is not.
        (yyval.ast_node) = make_node_table_constructor((yyvsp[-2].ast_node));
    }
#line 3104 "parser.c"
    break;

  case 134: /* $@1: %empty  */
#line 1051 "parser.y"
    {
        current_tic80_section = strdup((yyvsp[0].string_val));
        free((yyvsp[0].string_val));
    }
#line 3113 "parser.c"
    break;

  case 135: /* tic80_section: TOKEN_TIC80_SECTION_HEADER $@1 tic80_asset_lines TOKEN_TIC80_SECTION_FOOTER  */
#line 1057 "parser.y"
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
#line 3138 "parser.c"
    break;

  case 136: /* tic80_asset_lines: %empty  */
#line 1080 "parser.y"
                { (yyval.ast_node) = NULL; }
#line 3144 "parser.c"
    break;

  case 137: /* tic80_asset_lines: tic80_asset_lines TOKEN_TIC80_ASSET_DATA  */
#line 1082 "parser.y"
    {
        TIC80AssetData *data = parse_tic80_asset_line((yyvsp[0].string_val));
        if (data != NULL) {  // <-- ADD THIS CHECK
            data->next = current_tic80_assets;
            current_tic80_assets = data;
        }
        free((yyvsp[0].string_val));
        (yyval.ast_node) = NULL;
    }
#line 3158 "parser.c"
    break;


#line 3162 "parser.c"

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

#line 1092 "parser.y"


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
