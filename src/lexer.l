%{
#include "v32lua.h"
#include "parser.tab.h"  // Generated automatically by Bison

char *process_string_literal (const char *text, int  len)
{
    // Allocate space. The processed string will never be longer 
    // than the raw string minus the two quotes.
    char *processed  = (char *) malloc (len - 1); 
    if (processed   == NULL) {
        compiler_error (ERR_INTERNAL, -1, "Memory allocation failed while processing string literal\n");
    }
    int   i          = 1; // Start at 1 to skip the opening quote
    int   j          = 0;
    
    while (i < len - 1) { // Stop before the closing quote
        if (text[i] == '\\' && i + 1 < len - 1) {
            i++; // Skip the backslash
            switch (text[i]) {
                case 'n': processed[j++] = '\n'; break;
                case 't': processed[j++] = '\t'; break;
                case 'r': processed[j++] = '\r'; break;
                case '\\': processed[j++] = '\\'; break;
                case '"':  processed[j++] = '"'; break;
                // Add more cases here if you want to support \a, \b, or \0
                default: 
                    // Unrecognized escape sequence, just keep the character
                    processed[j++] = text[i]; 
                    break;
            }
        } else {
            // Normal character
            processed[j++] = text[i];
        }
        i++;
    }
    processed[j] = '\0'; // Ensure it is null-terminated for the C-side
    return (processed);
}
%}

%option noyywrap
%option yylineno
/* Add these options to disable the unused functions */
%option nounput noinput

%%

[ \t\r\n]+              { /* Skip whitespace - Fixed single backslashes */ }

    /* 1. Transposed Multiline Comment: --@[[ ... ]] */
"--@[["([^\]]|\][^\]])*"]]" {
    int len = strlen(yytext);
    // Strip the opening "--@[[" (5 chars) and closing "]]" (2 chars)
    yylval.string_val = strndup(yytext + 5, len - 7);
    return TOKEN_COMMENT_BLOCK;
}

    /* 2. Standard Multiline Comment: --[[ ... ]] (Silently Skipped) */
"--[["([^\]]|\][^\]])*"]]" { /* Skip standard multiline comments safely */ }

	/* 3. Transposed Single-Line Comment: --@ ... */
"--@".* {
    // Allocate space and replace "--@" with ";  " to preserve length and add assembly prefix
    char *comment = strdup(yytext);
	int   index   = 0;

	while (comment[index] != '\0')
	{
		if (comment[index] == '-')
		{
			comment[index]  = ';';
		}
		else if (comment[index] == '@')
		{
			break;
		}
		index               = index + 1;
	}
    yylval.string_val = comment;
    return TOKEN_COMMENT_LINE;
}

"--#".* { 
    char *hint = strdup (yytext + 3);
    int len = strlen(hint);
    // Strip trailing \r, \n, or spaces
    while (len > 0 && (hint[len - 1] == '\r' || hint[len - 1] == '\n' || hint[len - 1] == ' ')) {
        hint[--len] = '\0';
    }
    yylval.string_val = hint;
    return (TOKEN_CART_HINT);
}

    /* 4. Standard Single-Line Comment: Matches '--' with text, or a bare '--' */
"--".* { /* Skip standard single-line comments safely */ }

"while"                 { return TOKEN_WHILE;    }
"for"                   { return TOKEN_FOR;    }
"break"                 { return TOKEN_BREAK;    }
"do"                    { return TOKEN_DO;       }
"if"                    { return TOKEN_IF;       }
"elseif"                { return TOKEN_ELSEIF;   }
"then"                  { return TOKEN_THEN;     }
"else"                  { return TOKEN_ELSE;     }
"end"                   { return TOKEN_END;      }
"local"                 { return TOKEN_LOCAL;    }
"function"              { return TOKEN_FUNCTION; }
"return"                { return TOKEN_RETURN;   }
"and"                   { return TOKEN_AND;      }
"or"                    { return TOKEN_OR;       }
"true"                  { return TOKEN_TRUE;     }
"false"                 { return TOKEN_FALSE;    }
"nil"                   { return TOKEN_NIL;      }

"=="                    { return TOKEN_EQ;       }
"~="                    { return TOKEN_NEQ;      }
"<="                    { return TOKEN_LE;       }
">="                    { return TOKEN_GE;       }
"<"                     { return TOKEN_LT;       }
">"                     { return TOKEN_GT;       }
"#"                     { return TOKEN_LEN;      }
"not"                   { return TOKEN_NOT;      }
".."                    { return TOKEN_CONCAT;   }
"__asm__"               { return TOKEN_ASM;      }
"__rawasm__"            { return TOKEN_RAWASM;   }
"+"                     { return '+'; }
"-"                     { return '-'; }
"*"                     { return '*'; }
"/"                     { return '/'; }
"%"                     { return '%'; }
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

[a-zA-Z_][a-zA-Z0-9_]*  { 
                            yylval.string_val  = strdup (yytext); 
                            return (TOKEN_IDENTIFIER); 
                        }

0x[0-9a-fA-F]+          {
                            // Parse hex string as 32-bit unsigned integer
                            unsigned long val = strtoul(yytext, NULL, 16);
                            // Store in your existing double AST payload
                            yylval.number_val = (double) val;
                            return (TOKEN_NUMBER);
                        }

[0-9]+(\.[0-9]+)?       { 
                            yylval.number_val  = atof (yytext); 
                            return (TOKEN_NUMBER); 
                        }

\"(\\.|[^"\\])*\"       { 
                            yylval.string_val  = process_string_literal (yytext, yyleng); 
                            return (TOKEN_STRING);
                        }

.  { compiler_error(ERR_LEXICAL, yylineno, "Unexpected character '%s'", yytext); }
%%
