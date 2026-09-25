%{
#include "v32lua.h"
#include "parser.h"  // Generated automatically by Bison
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wsign-compare"

static int lex_in_tic80_section = 0;   /* see the TIC-80 asset-data rule */

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

// PICO-8 compound assignment operators (+=, -=, *=, /=, %=). Standard Lua
// has no compound assignment at all -- this is a PICO-8-only extension --
// so all five share this one helper, gated on runtime_req.needs_pico8. By
// the time any of these can be lexed, --#api pico8 (a normal TOKEN_CART_HINT
// reduced earlier in this same single parse pass) has already set that flag,
// PROVIDED the --#api hint appears before the first use in the source --
// the existing convention every cart hint already follows. Outside PICO-8
// mode this fails loudly and immediately rather than falling through to the
// generic "syntax error" the separate '+' '=' tokens would otherwise produce.
//
// The operator itself is carried in yylval.number_val (reusing TOKEN_NUMBER's
// slot in the union) as one of the NodeType enum values (NODE_ADD/NODE_SUB/
// NODE_MUL/NODE_DIV/NODE_MOD) -- parser.y casts it back and feeds it straight
// into the same make_node_binary() every plain '+'/'-'/'*'/'/'/'%' expr
// already uses, so the arithmetic itself needed no new codegen.
static int compound_assign_token (NodeType op)
{
    if (!runtime_req.needs_pico8) {
        compiler_error (ERR_SYNTAX, yylineno,
            "compound assignment operators (+=, -=, *=, /=, %%=) are a "
            "PICO-8 extension; add --#api pico8 to use them");
    }
    yylval.number_val = (double) op;
    return TOKEN_COMPOUND_ASSIGN;
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

    /* Extract section name between < and > */
"-- <"[A-Z]+">"\r?\n {
    char *start = strchr(yytext, '<') + 1;
    char *end = strchr(yytext, '>');
    if (end) *end = '\0';
    yylval.string_val = strdup(start);  // Returns "TILES"
    lex_in_tic80_section = 1;
    return TOKEN_TIC80_SECTION_HEADER;
}

"-- </"[A-Z]+">"\r?\n {
    char *start = strchr(yytext, '<') + 2;  // Skip '<' AND '/'
    char *end = strchr(yytext, '>');
    if (end) *end = '\0';
    yylval.string_val = strdup(start);  // Returns "TILES"
    lex_in_tic80_section = 0;
    return TOKEN_TIC80_SECTION_FOOTER;
}

"-- "[0-9]+[:][0-9a-fA-F]+\r?\n {
    // Only INSIDE a TIC-80 -- <SECTION> ... -- </SECTION> block. Outside
    // one, "-- 5:6" / "-- 3:30 timeout" is just a comment -- it used to be
    // returned as asset data anywhere and fail the parse with a syntax error.
    if (!lex_in_tic80_section) {
        /* ordinary comment: skip (yylineno counts the newline itself) */
    } else {
        yylval.string_val = strdup(yytext + 3);  // Skip "-- "
        return TOKEN_TIC80_ASSET_DATA;
    }
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
"repeat"                { return TOKEN_REPEAT;   }
"until"                 { return TOKEN_UNTIL;    }
"for"                   { return TOKEN_FOR;      }
"in"                    { return TOKEN_IN;       }
"break"                 { return TOKEN_BREAK;    }
"goto"                  { return TOKEN_GOTO;     }
"::"                    { return TOKEN_DBCOLON;  }
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
    /* PICO-8 alias for ~= (C-style "not equal"). Real Lua only ever has
       ~=; this is PICO-8-specific sugar, same category as += and the
       then-less if, so it's gated the same way -- checked here rather
       than in parser.y since it produces the exact same TOKEN_NEQ the
       parser already knows how to handle, so no grammar change at all. */
"!="                    {
                            if (!runtime_req.needs_pico8) {
                                compiler_error (ERR_LEXICAL, yylineno,
                                    "'!=' is a PICO-8 extension (use '~=', or add --#api pico8 to use '!=')");
                            }
                            return TOKEN_NEQ;
                        }
"<="                    { return TOKEN_LE;       }
">="                    { return TOKEN_GE;       }
"<"                     { return TOKEN_LT;       }
">"                     { return TOKEN_GT;       }
"#"                     { return TOKEN_LEN;      }
"not"                   { return TOKEN_NOT;      }
"..."                   { return TOKEN_DOTS;     }
".."                    { return TOKEN_CONCAT;   }
"__asm__"               { return TOKEN_ASM;      }
"__rawasm__"            { return TOKEN_RAWASM;   }
"^"                     { return '^'; }
    /* PICO-8-only compound assignment (see compound_assign_token() above).
       Listed ahead of the plain '+' '-' '*' '/' '%' rules below, same
       convention as "==" etc. being listed ahead of their single-char
       prefixes -- flex's longest-match rule would pick these correctly
       either way, but grouping the multi-char variant next to its base
       operator matches the rest of this file. */
"+="                    { return compound_assign_token(NODE_ADD); }
"-="                    { return compound_assign_token(NODE_SUB); }
"*="                    { return compound_assign_token(NODE_MUL); }
"/="                    { return compound_assign_token(NODE_DIV); }
"%="                    { return compound_assign_token(NODE_MOD); }
"+"                     { return '+'; }
"-"                     { return '-'; }
"*"                     { return '*'; }
"//"                    { return TOKEN_FLOORDIV; }
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
";"                     { return ';'; }

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

[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)? {
                            /* exponent form (1e-17, 2.5E3) added: TIC-80
                               exports and hand-written tables use it --
                               warm_wheels.lua failed to parse without it */
                            yylval.number_val  = atof (yytext); 
                            return (TOKEN_NUMBER); 
                        }

\.[0-9]+([eE][+-]?[0-9]+)? {
                            yylval.number_val  = atof (yytext);
                            return (TOKEN_NUMBER);
                        }

\"(\\.|[^"\\])*\"       { 
                            yylval.string_val  = process_string_literal (yytext, yyleng); 
                            return (TOKEN_STRING);
                        }

\'(\\.|[^'\\\n])*\'      {
                            /* single-quoted strings -- plain Lua, but only
                               "..." used to be accepted */
                            yylval.string_val  = process_string_literal (yytext, yyleng);
                            return (TOKEN_STRING);
                        }

"[["([^\]]|\][^\]])*"]]" {
                            /* long string [[...]]: no escape processing; a
                               newline right after the opening [[ is dropped,
                               as in Lua */
                            int start = 2, len = yyleng - 4;
                            if (len > 0 && yytext[start] == '\r') { start++; len--; }
                            if (len > 0 && yytext[start] == '\n') { start++; len--; }
                            char *str = (char *) malloc (len + 1);
                            memcpy (str, yytext + start, len);
                            str[len] = '\0';
                            yylval.string_val  = str;
                            return (TOKEN_STRING);
                        }

.  { compiler_error(ERR_LEXICAL, yylineno, "Unexpected character '%s'", yytext); }
%%
