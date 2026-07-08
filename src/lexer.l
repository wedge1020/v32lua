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

[ \t\r\n]+              { /* Skip whitespace - Fixed single backslashes */ }

    /* 1. Transposed Multiline Comment: --@[[ ... ]] */
"--@[["([^\]]|\][^\]])*"]]" {
    // Strip the opening "--@[[" and closing "]]" to extract the comment text
    int len = strlen(yytext);

    fprintf(stdout, ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n");
    fprintf(stdout, ";; \n");
    fprintf(stdout, ";; lua comment: ");

    for (int index = 5; index < len - 2; index++)
    {
        // If a newline is encountered, wrap the line and start a new comment block line
        if (yytext[index] == '\n')
        {
            fprintf(stdout, "\n;; lua comment: ");
        }
        // Collapse tabs to a single space for cleaner assembly output
        else if (yytext[index] == '\t')
        {
            fprintf(stdout, " ");
        }
        // Completely skip carriage returns to avoid double spacing issues
        else if (yytext[index] == '\r')
        {
            ;
        }
        else
        {
            putchar(yytext[index]);
        }
    }
    fprintf(stdout, "\n;; \n");
}

    /* 2. Standard Multiline Comment: --[[ ... ]] (Silently Skipped) */
"--[["([^\]]|\][^\]])*"]]" { /* Skip standard multiline comments safely */ }

    /* 3. Transposed Single-Line Comment: --@ ... */
"--@".* { fprintf (stdout, ";; lua comment: %s\n", yytext + 3); }

    /* 4. Standard Single-Line Comment: Matches '--' with text, or a bare '--' */
"--".* { /* Skip standard single-line comments safely */ }

"while"                 { return TOKEN_WHILE;    }
"break"                 { return TOKEN_BREAK;    }
"if"                    { return TOKEN_IF;       }
"elseif"                { return TOKEN_ELSEIF;   }
"then"                  { return TOKEN_THEN;     }
"else"                  { return TOKEN_ELSE;     }
"end"                   { return TOKEN_END;      }
"function"              { return TOKEN_FUNCTION; }
"return"                { return TOKEN_RETURN;   }
"and"                   { return TOKEN_AND;      }
"or"                    { return TOKEN_OR;       }

"=="                    { return TOKEN_EQ;       }
"~="                    { return TOKEN_NEQ;      }
"<="                    { return TOKEN_LE;       }
">="                    { return TOKEN_GE;       }
"<"                     { return TOKEN_LT;       }
">"                     { return TOKEN_GT;       }
".."                    { return TOKEN_CONCAT;   }
"__asm__"               { return TOKEN_ASM;      }
"__rawasm__"            { return TOKEN_RAWASM;   }
"+"                     { return '+'; }
"-"                     { return '-'; }
"*"                     { return '*'; }
"/"                     { return '/'; }
"("                     { return '('; }
")"                     { return ')'; }
"="                     { return '='; }
","                     { return ','; }
"{"                     { return '{'; }
"}"                     { return '}'; }
"["                     { return '['; }
"]"                     { return ']'; }
"."                     { return '.'; }
":"                     { return ':'; }

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

.  { compiler_error(ERR_LEXICAL, yylineno, "Unexpected character '%s'", yytext); }
%%
