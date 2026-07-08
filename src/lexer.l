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

[ \t\\r\\n]+              { /* Skip whitespace */ }

    /* 1. Transposed Multiline Comment: --@[[ ... ]] */
"--@\[\[([^*]|\*+[^\]])*\]\]" {
    // Strip the opening "--@[[" and closing "]]" to extract the comment text
    int len = strlen(yytext);
    // Print directly to the generated assembly file stream
    fprintf (stdout, ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n");
    fprintf (stdout, ";; ");
    fprintf (stdout, ";; lua comment: ");
    for (int index = 5; index < len - 2; index++)
    {
        // If a newline is encountered, wrap the line and start a new comment ...
        if (yytext[index] == '\n')
        {
            fprintf (stdout, "\n;; lua comment: ");
        }

        //////////////////////////////////////////////////////////////////////////////////////
        //
        // ... in the case of encountering a carriage return, do nothing ...
        //
        else if (yytext[index] == '\r')
        {
            ;
        }

        //////////////////////////////////////////////////////////////////////////////////////
        //
        // ... in the case of encountering a tab, collapse it to a single space ...
        //
        else if (yytext[index] == '\t')
        {
            fprintf (stdout, " ");
        }

        //////////////////////////////////////////////////////////////////////////////////////
        //
        // ... otherwise, display the encountered character:
        //
        else
        {
            putchar(yytext[index]);
        }
    }
    fprintf (stdout, "\n;; \n");
}

    /* 2. Standard Multiline Comment: --[[ ... ]] (Silently Skipped) */
"--\[\[([^*]|\*+[^\]])*\]\]" { /* Skip standard multiline comments */ }

    /* 3. Transposed Single-Line Comment: --@ ... */
"--@".* {
    // Print the content following the "--@" directly as an assembly comment
    printf(";; lua comment: %s\n", yytext + 3);
}

    /* 4. Standard Single-Line Comment (Your existing rule, updated to match standard only) */
"--[^@].*" { /* Skip standard single-line comments */ }

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
