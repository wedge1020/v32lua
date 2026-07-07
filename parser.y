%{
#include "codegen.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

/* --- ADD THESE LINES AT THE TOP OF YOUR FILE --- */
%type <ast_node> parameter_list
%type <ast_node> argument_list

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
        printf("; --- Program Initialization ---\n");
        printf("  MOV R0, 20000    ; Load immediate into register\n");
        printf("  MOV [0], R0      ; Initialize heap pointer to dynamic RAM region\n\n");
        
        printf("; --- Global Setup Routine (Table & Method Registration) ---\n");
        generate_global_setup($1); 
        
        printf("\n; --- Main Console Game Loop ---\n");
        printf("__game_loop:\n");
        printf("  CALL _main       ; Execute the user's main function\n");
        printf("  WAIT             ; Pause CPU execution until the next video frame\n");
        printf("  JMP __game_loop  ; Loop forever\n\n"); 
        
        printf("; --- Compiled Function Segments ---\n");
        generate_functions($1);
        
        // If your compiler uses a trailing string data section handler, keep it here:
        // emit_string_data_section();
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

parameter_list:
    /* empty */ { 
        $$ = NULL; 
    }
    | TOKEN_IDENTIFIER { 
        $$ = make_node(NODE_IDENTIFIER); 
    }
    | parameter_list ',' TOKEN_IDENTIFIER {
        ASTNode* new_node = make_node(NODE_IDENTIFIER);
        // Chain the new parameter to the end of the list
        ASTNode* current = $1;
        while (current->next != NULL) {
            current = current->next;
        }
        current->next = new_node;
        $$ = $1;
    }
    ;

argument_list:
    /* empty */ { 
        $$ = NULL; 
    }
    | expr { 
        $$ = $1; 
    }
    | argument_list ',' expr {
        // Chain the new expression to the end of the argument list
        ASTNode* current = $1;
        while (current->next != NULL) {
            current = current->next;
        }
        current->next = $3;
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
    | expr '.' TOKEN_IDENTIFIER '=' expr {
        ASTNode* node = make_node(NODE_TABLE_SET);
        node->as.table_set.table = $1;
        node->as.table_set.key = create_string_node($3);
        node->as.table_set.value = $5;
        $$ = node;
    }
    | TOKEN_FUNCTION TOKEN_IDENTIFIER ':' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END {
        // 1. Inject 'self' as a hidden first argument into the parameter list
        ASTNode* self_param = create_identifier_node("self");
        self_param->next = $6; // Prepended to user-defined parameters
        
        // 2. Desugar into a standard table function definition structure
        ASTNode* func_node = make_node(NODE_FUNCTION_DEF);
        
        // Combine table name and method name for the unique backend label (e.g., "player_bounce")
        func_node->as.function_def.name = mangle_method_name($2, $4);
        func_node->as.function_def.params = self_param;
        func_node->as.function_def.body = $8;
        
        // 3. Chain it to a setup node that binds it to the table at boot time
        ASTNode* bind_node = create_ast_node(NODE_TABLE_SET);
        bind_node->as.table_set.table = create_identifier_node($2);
        bind_node->as.table_set.key = create_string_node($4);
        bind_node->as.table_set.value = func_node; 
        
        // This ensures the function goes to Pass 2 and binding goes to Pass 1!
        func_node->next = bind_node; 
        $$ = func_node;
    }
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
    /* Standard Function: function my_func() ... end */
    TOKEN_FUNCTION TOKEN_IDENTIFIER '(' ')' statement_list TOKEN_END {
        $$ = make_node(NODE_FUNCTION_DEF);
        $$->as.function_def.name = $2;
        $$->as.function_def.body = $5;
    }
    |
    /* Table Function Desugaring: function my_table.my_func() ... end */
    TOKEN_FUNCTION TOKEN_IDENTIFIER '.' TOKEN_IDENTIFIER '(' ')' statement_list TOKEN_END {
        // 1. Create a unique mangled label for assembly execution flow
        char mangled_name[256];
        snprintf(mangled_name, sizeof(mangled_name), "%s_%s", $2, $4);

        // 2. Build the structural function definition body
        ASTNode* func_def = make_node(NODE_FUNCTION_DEF);
        func_def->as.function_def.name = strdup(mangled_name);
        func_def->as.function_def.body = $7;

        // 3. Instantiate a function pointer node evaluating to that address
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        // 4. Generate the lookup components for the string key
        ASTNode* key_node = make_node(NODE_STRING);
        key_node->as.string_val.value = strdup($4);

        // 5. Generate the base identifier lookup for the target table
        ASTNode* table_node = make_node(NODE_IDENTIFIER);
        table_node->as.id.name = $2;

        // 6. Tie it all into a table assignment: table[key] = func_ptr
        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key = key_node;
        table_set->as.table_set.value = func_ptr;

        // 7. Chain them sequentially so the compiler outputs both properties cleanly
        func_def->next = table_set;
        $$ = func_def;
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
    | expr '.' TOKEN_IDENTIFIER {
        ASTNode* node = create_ast_node(NODE_TABLE_GET);
        node->as.table_get.table = $1;
        // Turn the identifier string into a constant string node for the key
        node->as.table_get.key = create_string_node($3); 
        $$ = node;
    }
    | expr ':' TOKEN_IDENTIFIER '(' argument_list ')' {
        ASTNode* node = create_ast_node(NODE_FUNCTION_CALL);
        
        // The table itself is the object context ('self')
        node->as.call.target_table = $1; 
        node->as.call.is_method_call = 1;
        
        // The target to resolve at runtime is the function inside the table: object.method
        ASTNode* dynamic_lookup = create_ast_node(NODE_TABLE_GET);
        dynamic_lookup->as.table_get.table = $1;
        dynamic_lookup->as.table_get.key = create_string_node($3);
        node->as.call.target = dynamic_lookup;
        
        node->as.call.args_head = $5;
        $$ = node;
    }
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
