%{
#include "codegen.h"
#include "parser.tab.h"  // Generated automatically by Bison
#include <string.h>
#include <stdlib.h>
%}

%option noyywrap
%option yylineno
/* Add these options to disable the unused functions */
%option nounput noinput

%%

[ \t\r\n]+              { /* Skip whitespace */ }
"--".* { /* Skip single-line comments */ }

"while"                 { return TOKEN_WHILE; }
"break"                 { return TOKEN_BREAK; }
"if"                    { return TOKEN_IF; }
"then"                  { return TOKEN_THEN; }
"else"                  { return TOKEN_ELSE; }
"end"                   { return TOKEN_END; }
"function"              { return TOKEN_FUNCTION; }
"return"                { return TOKEN_RETURN; }
"and"                   { return TOKEN_AND; }
"or"                    { return TOKEN_OR; }

"=="                    { return TOKEN_EQ; }
"~="                    { return TOKEN_NEQ; }
"<="                    { return TOKEN_LE; }
">="                    { return TOKEN_GE; }
"<"                     { return TOKEN_LT; }
">"                     { return TOKEN_GT; }
".."                    { return TOKEN_CONCAT; }
"("         { return '('; }
")"         { return ')'; }
"="                     { return '='; }
","                     { return ','; }
"{"                     { return '{'; }
"}"                     { return '}'; }
"["                     { return '['; }
"]"                     { return ']'; }

[a-zA-Z_][a-zA-Z0-9_]* { 
                            yylval.string_val = strdup(yytext); 
                            return TOKEN_IDENTIFIER; 
                        }

[0-9]+(\.[0-9]+)?       { 
                            yylval.number_val = atof(yytext); 
                            return TOKEN_NUMBER; 
                        }

\"(\\.|[^"\\])*\"       {
                            // Strip quotes before saving string contents
                            int len = strlen(yytext);
                            yylval.string_val = strndup(yytext + 1, len - 2);
                            return TOKEN_STRING;
                        }

.                       { printf("Lexical Error on line %d: Unexpected character %s\n", yylineno, yytext); }

%%
