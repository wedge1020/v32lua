/* A Bison parser, made by GNU Bison 2.3.  */

/* Skeleton interface for Bison's Yacc-like parsers in C

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




#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
typedef union YYSTYPE
#line 18 "parser.y"
{
    double   number_val;
    char    *string_val;
    ASTNode *ast_node;
}
/* Line 1529 of yacc.c.  */
#line 145 "parser.tab.h"
	YYSTYPE;
# define yystype YYSTYPE /* obsolescent; will be withdrawn */
# define YYSTYPE_IS_DECLARED 1
# define YYSTYPE_IS_TRIVIAL 1
#endif

extern YYSTYPE yylval;

