/* A Bison parser, made by GNU Bison 3.8.2.  */

/* Bison interface for Yacc-like parsers in C

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

/* DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
   especially those whose name start with YY_ or yy_.  They are
   private implementation details that can be changed or removed.  */

#ifndef YY_YY_INC_PARSER_H_INCLUDED
# define YY_YY_INC_PARSER_H_INCLUDED
/* Debug traces.  */
#ifndef YYDEBUG
# define YYDEBUG 1
#endif
#if YYDEBUG
extern int yydebug;
#endif

/* Token kinds.  */
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
  enum yytokentype
  {
    YYEMPTY = -2,
    YYEOF = 0,                     /* "end of file"  */
    YYerror = 256,                 /* error  */
    YYUNDEF = 257,                 /* "invalid token"  */
    TOKEN_NUMBER = 258,            /* TOKEN_NUMBER  */
    TOKEN_IDENTIFIER = 259,        /* TOKEN_IDENTIFIER  */
    TOKEN_STRING = 260,            /* TOKEN_STRING  */
    TOKEN_COMMENT_LINE = 261,      /* TOKEN_COMMENT_LINE  */
    TOKEN_COMMENT_BLOCK = 262,     /* TOKEN_COMMENT_BLOCK  */
    TOKEN_TIC80_SECTION_HEADER = 263, /* TOKEN_TIC80_SECTION_HEADER  */
    TOKEN_TIC80_ASSET_DATA = 264,  /* TOKEN_TIC80_ASSET_DATA  */
    TOKEN_TIC80_SECTION_FOOTER = 265, /* TOKEN_TIC80_SECTION_FOOTER  */
    TOKEN_CART_HINT = 266,         /* TOKEN_CART_HINT  */
    TOKEN_COMPOUND_ASSIGN = 267,   /* TOKEN_COMPOUND_ASSIGN  */
    TOKEN_WHILE = 268,             /* TOKEN_WHILE  */
    TOKEN_FOR = 269,               /* TOKEN_FOR  */
    TOKEN_BREAK = 270,             /* TOKEN_BREAK  */
    TOKEN_IF = 271,                /* TOKEN_IF  */
    TOKEN_ELSEIF = 272,            /* TOKEN_ELSEIF  */
    TOKEN_THEN = 273,              /* TOKEN_THEN  */
    TOKEN_ELSE = 274,              /* TOKEN_ELSE  */
    TOKEN_END = 275,               /* TOKEN_END  */
    TOKEN_FUNCTION = 276,          /* TOKEN_FUNCTION  */
    TOKEN_ASM = 277,               /* TOKEN_ASM  */
    TOKEN_RAWASM = 278,            /* TOKEN_RAWASM  */
    TOKEN_RETURN = 279,            /* TOKEN_RETURN  */
    TOKEN_AND = 280,               /* TOKEN_AND  */
    TOKEN_OR = 281,                /* TOKEN_OR  */
    TOKEN_EQ = 282,                /* TOKEN_EQ  */
    TOKEN_NEQ = 283,               /* TOKEN_NEQ  */
    TOKEN_LE = 284,                /* TOKEN_LE  */
    TOKEN_GE = 285,                /* TOKEN_GE  */
    TOKEN_LT = 286,                /* TOKEN_LT  */
    TOKEN_GT = 287,                /* TOKEN_GT  */
    TOKEN_CONCAT = 288,            /* TOKEN_CONCAT  */
    TOKEN_LOCAL = 289,             /* TOKEN_LOCAL  */
    TOKEN_IN = 290,                /* TOKEN_IN  */
    TOKEN_DO = 291,                /* TOKEN_DO  */
    TOKEN_NOT = 292,               /* TOKEN_NOT  */
    TOKEN_LEN = 293,               /* TOKEN_LEN  */
    UNARY_MINUS = 294,             /* UNARY_MINUS  */
    TOKEN_TRUE = 295,              /* TOKEN_TRUE  */
    TOKEN_FALSE = 296,             /* TOKEN_FALSE  */
    TOKEN_NIL = 297,               /* TOKEN_NIL  */
    TOKEN_FLOORDIV = 298,          /* TOKEN_FLOORDIV  */
    TOKEN_DOTS = 299,              /* TOKEN_DOTS  */
    TOKEN_REPEAT = 300,            /* TOKEN_REPEAT  */
    TOKEN_UNTIL = 301,             /* TOKEN_UNTIL  */
    TOKEN_GOTO = 302,              /* TOKEN_GOTO  */
    TOKEN_DBCOLON = 303,           /* TOKEN_DBCOLON  */
    TOKEN_PRINT_SHORT = 304        /* TOKEN_PRINT_SHORT  */
  };
  typedef enum yytokentype yytoken_kind_t;
#endif

/* Value type.  */
#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
union YYSTYPE
{
#line 68 "parser.y"

    double   number_val;
    char    *string_val;
    ASTNode *ast_node;

#line 119 "../inc/parser.h"

};
typedef union YYSTYPE YYSTYPE;
# define YYSTYPE_IS_TRIVIAL 1
# define YYSTYPE_IS_DECLARED 1
#endif


extern YYSTYPE yylval;


int yyparse (void);


#endif /* !YY_YY_INC_PARSER_H_INCLUDED  */
