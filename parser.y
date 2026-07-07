%{
#include "codegen.h"
#include <stdio.h>
#include <stdlib.h>

extern int yylineno;
extern int yylex(void);
void yyerror(const char *s);

// Inline helper functions for memory allocation during AST compilation
ASTNode* make_node(NodeType type);
void emit_runtime_library(void);
%}

%union {
    double number_val;
    char* string_val;
    ASTNode* ast_node;
}

%token <number_val> TOKEN_NUMBER
%token <string_val> TOKEN_IDENTIFIER TOKEN_STRING
%token TOKEN_WHILE TOKEN_BREAK TOKEN_IF TOKEN_THEN TOKEN_ELSE TOKEN_END 
%token TOKEN_FUNCTION TOKEN_RETURN TOKEN_AND TOKEN_OR
%token TOKEN_EQ TOKEN_NEQ TOKEN_LE TOKEN_GE TOKEN_LT TOKEN_GT TOKEN_CONCAT

%type <ast_node> statement statement_list expr assignment function_def return_stmt table_constructor

/* Operator Precedence Rules (PEMDAS + Logic Core) */
%left TOKEN_OR
%left TOKEN_AND
%left TOKEN_EQ TOKEN_NEQ TOKEN_LT TOKEN_GT TOKEN_LE TOKEN_GE
%right TOKEN_CONCAT
%left '+' '-'
%left '*' '/'
%left '['

%%
program:
    statement_list { 
        printf("; --- Vircon32 Boot Initialization ---\n");
        printf("  MOV R0, 100000\n");
        printf("  MOV [0], R0 ; Initialize heap pointer at RAM address 0\n\n");
        
        printf("; --- Compiled Code Entry Vector ---\n");
        generate_asm($1); 
        
        // Corrected Vircon32 halt instruction
        printf("  HLT\n"); 
        
        emit_string_data_section();
        // emit_global_variables() has been REMOVED!
        emit_runtime_library();
    }
    ;

statement_list:
    statement                    { $$ = $1; }
    | statement_list statement   { 
        // Simple sequential chaining configuration block
        ASTNode* head = $1;
        while(head->next != NULL) head = head->next;
        head->next = $2;
        $$ = $1;
    }
    ;

statement:
    assignment                   { $$ = $1; }
    | TOKEN_WHILE expr statement_list TOKEN_END {
        $$ = make_node(NODE_WHILE);
        $$->as.while_loop.condition = $2;
        $$->as.while_loop.body = $3;
    }
    | TOKEN_BREAK {
        $$ = make_node(NODE_BREAK);
    }
    | TOKEN_IF expr TOKEN_THEN statement_list TOKEN_END {
        $$ = make_node(NODE_IF);
        $$->as.if_stmt.condition = $2;
        $$->as.if_stmt.if_body = $4;
        $$->as.if_stmt.else_body = NULL;
    }
    | TOKEN_IF expr TOKEN_THEN statement_list TOKEN_ELSE statement_list TOKEN_END {
        $$ = make_node(NODE_IF);
        $$->as.if_stmt.condition = $2;
        $$->as.if_stmt.if_body = $4;
        $$->as.if_stmt.else_body = $6;
    }
    | function_def               { $$ = $1; }
    | return_stmt                { $$ = $1; }
    ;

assignment:
    TOKEN_IDENTIFIER '=' expr {
        $$ = make_node(NODE_MULTIPLE_ASSIGNMENT);
        ASTNode* target = make_node(NODE_IDENTIFIER);
        target->as.id.name = $1;
        $$->as.mult_assign.targets_head = target;
        $$->as.mult_assign.right_side_call = $3;
    }
    | expr '[' expr ']' '=' expr {
        $$ = make_node(NODE_TABLE_SET);
        $$->as.table_set.table_expr = $1;
        $$->as.table_set.key = $3;
        $$->as.table_set.value = $6;
    }
    ;

function_def:
    TOKEN_FUNCTION TOKEN_IDENTIFIER '(' ')' statement_list TOKEN_END {
        $$ = make_node(NODE_FUNCTION_DEF);
        $$->as.function_def.name = $2;
        $$->as.function_def.body = $5;
    }
    ;

return_stmt:
    TOKEN_RETURN expr {
        $$ = make_node(NODE_RETURN);
        $$->as.return_stmt.expressions_head = $2;
        $$->as.return_stmt.parent_func_arg_count = 0; // Configured during type check
    }
    ;

expr:
    TOKEN_NUMBER {
        $$ = make_node(NODE_NUMBER);
        $$->as.number.val = $1;
    }
    | TOKEN_IDENTIFIER {
        $$ = make_node(NODE_IDENTIFIER);
        $$->as.id.name = $1;
    }
    | TOKEN_STRING {
        $$ = make_node(NODE_STRING);
        $$->as.string_val.value = $1;
    }
    | table_constructor { $$ = $1; }
    | expr '[' expr ']' {
        $$ = make_node(NODE_TABLE_GET);
        $$->as.table_get.table_expr = $1;
        $$->as.table_get.key = $3;
    }
    | expr TOKEN_EQ expr      { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_EQ;  $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_NEQ expr     { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_NEQ; $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_LT expr      { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_LT;  $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_GT expr      { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_GT;  $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_LE expr      { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_LE;  $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_GE expr      { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_GE;  $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_AND expr     { $$ = make_node(NODE_AND); $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_OR expr      { $$ = make_node(NODE_OR);  $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_CONCAT expr  { $$ = make_node(NODE_CONCAT); $$->as.binary.left = $1; $$->as.binary.right = $3; }
    ;

table_constructor:
    '{' '}' {
        $$ = make_node(NODE_TABLE_CONSTRUCTOR);
    }
    ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "Compilation Parser Error on line %d: %s\n", yylineno, s);
}

ASTNode* make_node(NodeType type) {
    ASTNode* n = (ASTNode*)calloc(1, sizeof(ASTNode));
    n->type = type;
    n->next = NULL;
    return n;
}
