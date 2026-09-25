%{

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
static void note_function_param_count (ASTNode *params)
{
    int n = 0;
    for (ASTNode *p = params; p != NULL; p = p->next) {
        if (p->type == NODE_IDENTIFIER && strcmp (p->as.id.name, "...") == 0) continue;
        n++;
    }
    if (n > g_max_param_count) g_max_param_count = n;
}

%}

%union {
    double   number_val;
    char    *string_val;
    ASTNode *ast_node;
}

//%expect 5

/* --- AST Node Types --- */
%type <ast_node> parameter_list
%type <ast_node> argument_list
%type <ast_node> var_list       /* Added for multiple assignment */
%type <ast_node> expr_list      /* Added for multiple assignment */
%type <ast_node> tic80_section tic80_asset_lines

%token <number_val> TOKEN_NUMBER
%token <string_val> TOKEN_IDENTIFIER TOKEN_STRING
%token <string_val> TOKEN_COMMENT_LINE TOKEN_COMMENT_BLOCK
%token <string_val> TOKEN_TIC80_SECTION_HEADER TOKEN_TIC80_ASSET_DATA
%token <string_val> TOKEN_TIC80_SECTION_FOOTER
%token <string_val> TOKEN_CART_HINT
%token <number_val> TOKEN_COMPOUND_ASSIGN  /* PICO-8-only += -= *= /= %= (see lexer.l) */

%token TOKEN_WHILE TOKEN_FOR TOKEN_BREAK TOKEN_IF TOKEN_ELSEIF TOKEN_THEN TOKEN_ELSE TOKEN_END 
%token TOKEN_FUNCTION TOKEN_ASM TOKEN_RAWASM TOKEN_RETURN TOKEN_AND TOKEN_OR
%token TOKEN_EQ TOKEN_NEQ TOKEN_LE TOKEN_GE TOKEN_LT TOKEN_GT TOKEN_CONCAT
%token TOKEN_LOCAL TOKEN_IN TOKEN_DO TOKEN_NOT TOKEN_LEN UNARY_MINUS
%token TOKEN_TRUE TOKEN_FALSE TOKEN_NIL TOKEN_FLOORDIV
%token TOKEN_DOTS
%token TOKEN_REPEAT TOKEN_UNTIL
%token TOKEN_GOTO TOKEN_DBCOLON

%type <ast_node> statement statement_list stat_list expr function_def return_stmt
%type <ast_node> table_constructor function_call else_branch prefix_expr
%type <ast_node> last_statement func_start while_start repeat_start for_start if_start
%type <ast_node> field
%type <ast_node> field_list

/* Operator Precedence Rules (PEMDAS + Logic Core) */
%left TOKEN_OR
%left TOKEN_AND
%left TOKEN_EQ TOKEN_NEQ TOKEN_LT TOKEN_GT TOKEN_LE TOKEN_GE
%right TOKEN_CONCAT
%left '+' '-'
%left '*' '/' '%' TOKEN_FLOORDIV
%right TOKEN_NOT TOKEN_LEN UNARY_MINUS
%right '^'
%left '['
%left '.'
%left ':'
%right TOKEN_FUNCTION

%%

program:
    statement_list
    {
        root_node = $1; // Captures the entire AST root for main.c to use later
    }
    ;

statement_list:
    /* empty */ { $$ = NULL; }
    | stat_list { $$ = $1; }
    | stat_list last_statement {
        if ($1 == NULL) { 
            $$ = $2; 
        } else {
            ASTNode *current = $1;
            while (current->next != NULL) {
                current = current->next;
            }
            current->next = $2;
            $$ = $1;
        }
    }
    | last_statement { $$ = $1; }
    ;

stat_list:
      statement ';' { $$ = $1; }
    | stat_list statement ';' {
        if ($1 == NULL) {
            $$ = $2;
        } else {
            ASTNode *current = $1;
            while (current->next != NULL) {
                current = current->next;
            }
            current->next = $2;
            $$ = $1;
        }
    }
    | statement { $$ = $1; }
    | stat_list statement {
        if ($1 == NULL) { 
            $$ = $2; 
        } else {
            ASTNode *current = $1;
            while (current->next != NULL) {
                current = current->next;
            }
            current->next = $2;
            $$ = $1;
        }
    }
    ;

parameter_list:
    /* empty */ {
        $$ = NULL;
    }
    | TOKEN_IDENTIFIER {
        $$ = make_node_ident($1);
    }
    | TOKEN_DOTS {
        // Create a marker identifier - will be detected in function_def
        $$ = make_node_ident("...");
    }
    | parameter_list ',' TOKEN_IDENTIFIER {
        ASTNode* new_node = make_node_ident($3);
        ASTNode* current = $1;
        while(current->next) current = current->next;
        current->next = new_node;
        $$ = $1;
    }
    | parameter_list ',' TOKEN_DOTS {
        ASTNode* new_node = make_node_ident("...");
        ASTNode* current = $1;
        while(current->next) current = current->next;
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

/* --- Helper Rules to Capture Opening Line Numbers --- */
func_start:
    TOKEN_FUNCTION { $$ = make_node(NODE_FUNCTION_DEF); }
    ;

while_start:
    TOKEN_WHILE    { $$ = make_node(NODE_WHILE); }
    ;

repeat_start:
    TOKEN_REPEAT   { $$ = make_node(NODE_REPEAT); }
    ;

for_start:
    TOKEN_FOR      { $$ = make_node(NODE_FOR_NUMERIC); }

if_start:
    TOKEN_IF       { $$ = make_node(NODE_IF); }
    ;

statement:
      function_call              { $$ = $1; }
    | TOKEN_GOTO TOKEN_IDENTIFIER {
        /* Lua 5.2+ goto -- see generate_block()'s label scopes */
        $$ = make_node(NODE_GOTO);
        $$->as.id.name = $2;
    }
    | TOKEN_DBCOLON TOKEN_IDENTIFIER TOKEN_DBCOLON {
        $$ = make_node(NODE_LABEL);
        $$->as.id.name = $2;
    }
    | var_list '=' expr_list {
        $$ = make_node(NODE_MULTIPLE_ASSIGNMENT);
        $$->as.mult_assign.targets_head = $1;
        $$->as.mult_assign.values_head = $3;
        $$->as.mult_assign.is_local = 0;
    }
    | TOKEN_LOCAL var_list '=' expr_list {
        $$ = make_node(NODE_MULTIPLE_ASSIGNMENT);
        $$->as.mult_assign.targets_head = $2;
        $$->as.mult_assign.values_head = $4;
        $$->as.mult_assign.is_local = 1;
    }
    | var_list TOKEN_COMPOUND_ASSIGN expr {
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
        if ($1->next != NULL) {
            compiler_error(ERR_SYNTAX, yylineno,
                "compound assignment (+=, -=, *=, /=, %%=) only supports a single target");
        }

        NodeType op = (NodeType)(int) $2;

        if ($1->type == NODE_IDENTIFIER) {
            // lhs = lhs OP rhs, via the exact same plain-assignment path
            // 'var_list = expr_list' above already uses -- $1 becomes
            // the (single) write target, and a second, independent
            // make_node_ident() with the same name is the read reference
            // embedded in the RHS. Safe to duplicate: an identifier read
            // has no side effects, so evaluating the name twice is free.
            ASTNode *read_ref = make_node_ident($1->as.id.name);
            ASTNode *new_val  = make_node_binary(op, read_ref, $3);

            $$ = make_node(NODE_MULTIPLE_ASSIGNMENT);
            $$->as.mult_assign.targets_head = $1;
            $$->as.mult_assign.values_head  = new_val;
            $$->as.mult_assign.is_local     = 0;
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
            ASTNode *table_expr = $1->as.table_get.table_expr;
            ASTNode *key        = $1->as.table_get.key;

            ASTNode *read_ref = make_node_table_get(table_expr, key);
            ASTNode *new_val  = make_node_binary(op, read_ref, $3);

            $$ = make_node_table_set(table_expr, key, new_val);
        }
    }
    | prefix_expr '[' expr ']' '=' expr
    { 
        // $1 = table, $3 = key, $6 = value being assigned
        $$ = make_node_table_set ($1, $3, $6); 
    }
    | prefix_expr '.' TOKEN_IDENTIFIER '=' expr
    {
        ASTNode *string_key  = make_node_string ($3);
        $$                   = make_node_table_set ($1, string_key, $5);
    }
    | while_start expr TOKEN_DO statement_list TOKEN_END {
        $$ = $1;
        $$->as.while_loop.condition = $2;
        $$->as.while_loop.body = $4;
    }
    | repeat_start statement_list TOKEN_UNTIL expr {
        // Note the order: body ($2) is parsed BEFORE the until-condition
        // ($4) -- this matters for scoping. Lua's grammar for repeat/until
        // deliberately puts the condition after the body's closing so
        // that locals declared in the body are still in scope for it.
        // node_repeat() in the compiler mirrors this by NOT popping the
        // body's scope until after the condition has been generated.
        $$ = $1;
        $$->as.repeat_loop.body      = $2;
        $$->as.repeat_loop.condition = $4;
    }
    | for_start TOKEN_IDENTIFIER '=' expr ',' expr TOKEN_DO statement_list TOKEN_END {
        $$ = make_node(NODE_FOR_NUMERIC);
        $$->as.for_numeric.index_name  = $2;
        $$->as.for_numeric.start_expr  = $4;
        $$->as.for_numeric.stop_expr   = $6;
        $$->as.for_numeric.step_expr   = NULL; // Omitted step
        $$->as.for_numeric.body        = $8;
    }
    | for_start TOKEN_IDENTIFIER '=' expr ',' expr ',' expr TOKEN_DO statement_list TOKEN_END {
        $$ = make_node(NODE_FOR_NUMERIC);
        $$->as.for_numeric.index_name  = $2;
        $$->as.for_numeric.start_expr  = $4;
        $$->as.for_numeric.stop_expr   = $6;
        $$->as.for_numeric.step_expr   = $8;  // Explicit step
        $$->as.for_numeric.body        = $10;
    }
    | for_start var_list TOKEN_IN expr_list TOKEN_DO statement_list TOKEN_END {
        $$ = make_node(NODE_FOR_GENERIC);
        $$->as.for_generic.var_list    = $2;
        $$->as.for_generic.iter_expr   = $4;
        $$->as.for_generic.body        = $6;
    }
    | if_start expr TOKEN_THEN statement_list else_branch TOKEN_END { 
        $$                             = $1;
        $$ -> as.if_stmt.condition     = $2;
        $$ -> as.if_stmt.if_body       = $4;
        $$ -> as.if_stmt.else_body     = $5;
    }
    | if_start expr statement {
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
        $$                             = $1;
        $$ -> as.if_stmt.condition     = $2;
        $$ -> as.if_stmt.if_body       = $3;
        $$ -> as.if_stmt.else_body     = NULL;
    }
    | if_start expr TOKEN_RETURN {
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

        $$                             = $1;
        $$ -> as.if_stmt.condition     = $2;
        $$ -> as.if_stmt.if_body       = ret_node;
        $$ -> as.if_stmt.else_body     = NULL;
    }
    | if_start expr TOKEN_BREAK {
        // Bare `if (cond) break`. Same reasoning as the TOKEN_RETURN
        // alternative above -- consumed as a raw terminal, not through
        // 'last_statement', so there's no optional-semicolon collision.
        if (!runtime_req.needs_pico8) {
            compiler_error(ERR_SYNTAX, yylineno,
                "then-less if is a PICO-8 extension; add --#api pico8 to use it");
        }
        $$                             = $1;
        $$ -> as.if_stmt.condition     = $2;
        $$ -> as.if_stmt.if_body       = make_node(NODE_BREAK);
        $$ -> as.if_stmt.else_body     = NULL;
    }
    | TOKEN_DO statement_list TOKEN_END {
        // Bare scoping block: no condition, no loop tracking -- just gives
        // the enclosed statements their own lexical scope. Most useful for
        // deliberately ending a 'local' declaration's shadow before the
        // rest of the enclosing block, without needing an 'if true then'
        // workaround.
        $$ = make_node_do_block ($2);
    }
    | TOKEN_LOCAL var_list {
        $$ = make_node(NODE_MULTIPLE_ASSIGNMENT);
        $$->as.mult_assign.is_local = 1;
        $$->as.mult_assign.targets_head = $2;
        $$->as.mult_assign.values_head = NULL; 
    }
    | function_def               { $$ = $1; }
    | TOKEN_ASM '(' TOKEN_STRING ')' { 
        $$ = make_node(NODE_ASM);
        $$->as.inline_asm.code = $3;
    }
    | TOKEN_LOCAL func_start TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END
    {
        // local function myfunc(...) ... end
        // This is equivalent to: local myfunc = function(...) ... end

                // 1. Get the pre-allocated function_def node from func_start
        ASTNode* func_def = $2;
        func_def->as.function_def.name = strdup($3);
        func_def->as.function_def.params = $5;
        note_function_param_count(func_def->as.function_def.params);
        func_def->as.function_def.body = $7;

        // 2. Initialize and check variadic status
        func_def->as.function_def.is_variadic = 0;
        ASTNode *p = $5;
        while (p != NULL) {
            if (p->type == NODE_IDENTIFIER && strcmp(p->as.id.name, "...") == 0) {
                func_def->as.function_def.is_variadic = 1;
                break;
            }
            p = p->next;
        }

        // ✅ SILENTLY IGNORE 'local': Just return the function_def node directly
        // (No assignment node created, no is_local flag set)
        $$ = func_def;

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
    | TOKEN_LOCAL func_start TOKEN_IDENTIFIER ':' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END
    {
        // local function obj:method(...) ... end
        //
        // Not standard Lua (real Lua's "local function" only accepts a
        // plain Name), but supported here as a project extension so the
        // colon-method sugar works under 'local' too. Semantically this
        // is identical to "function obj:method(...) ... end" -- the
        // 'local' keyword is silently ignored, exactly like the existing
        // "local function NAME(...)" rule above does.

        // 1. Mangle "obj" + "add_multiple" -> "obj_add_multiple"
        char* mangled_name = mangle_method_name($3, $5);

        // 2. Inject "self" as the first parameter (colon-call convention)
        ASTNode* self_param = make_node_ident("self");
        self_param->next = $7; // link to the rest of the declared parameters

        // 3. Build the function definition using the pre-allocated node
        ASTNode* func_def = $2;
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = self_param;
        note_function_param_count(func_def->as.function_def.params);
        func_def->as.function_def.body = $9;
        func_def->as.function_def.is_variadic = 0;

        // 4. Build a function-pointer node targeting the mangled label
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        // 5. Tie it into a table assignment: obj["add_multiple"] = func_ptr
        ASTNode* key_node   = make_node_string($5);
        ASTNode* table_node = make_node_ident($3);

        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key        = key_node;
        table_set->as.table_set.value      = func_ptr;

        // 6. Chain: func_def -> table_set, same pattern as every other
        // method-desugaring rule in this grammar
        func_def->next = table_set;
        $$ = func_def;
    }
    | TOKEN_LOCAL func_start TOKEN_IDENTIFIER '.' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END
    {
        // local function obj.method(...) ... end
        //
        // Dot form: unlike the colon form above, NO implicit 'self' is
        // injected here -- this mirrors the existing non-local dot-rule
        // in function_def: below. If the body needs self, the author
        // writes it as an explicit first parameter, same as real Lua.

        char* mangled_name = mangle_method_name($3, $5);

        ASTNode* func_def = $2;
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = $7;
        note_function_param_count(func_def->as.function_def.params);
        func_def->as.function_def.body = $9;
        func_def->as.function_def.is_variadic = 0;

        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        ASTNode* key_node   = make_node_string($5);
        ASTNode* table_node = make_node_ident($3);

        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key        = key_node;
        table_set->as.table_set.value      = func_ptr;

        func_def->next = table_set;
        $$ = func_def;
    }
    | TOKEN_RAWASM '(' TOKEN_STRING ')' { 
        $$ = make_node(NODE_RAWASM);
        $$->as.inline_asm.code = $3;
    }
    | TOKEN_COMMENT_LINE {
        $$ = make_node(NODE_COMMENT_LINE);
        $$->as.string_val.value = $1;
    }
    | TOKEN_COMMENT_BLOCK {
        $$ = make_node(NODE_COMMENT_BLOCK);
        $$->as.string_val.value = $1;
    }
    | tic80_section             { $$ = $1; }  /* Returns NULL - we process these separately */
    | TOKEN_CART_HINT {
        $$ = make_node_cart_hint($1);
    }
    ;

last_statement:
      return_stmt        { $$ = $1; }
    | return_stmt ';'    { $$ = $1; }
    | TOKEN_BREAK         { $$ = make_node(NODE_BREAK); }
    | TOKEN_BREAK ';'     { $$ = make_node(NODE_BREAK); }
    ;

else_branch:
    /* empty */                  { $$  = NULL; }
    | TOKEN_ELSE statement_list  { $$  = $2; }
    | TOKEN_ELSEIF expr TOKEN_THEN statement_list else_branch
    {
        // Treat elseif exactly like a nested IF statement assigned to the else_body
        $$                             = make_node(NODE_IF);
        $$ -> as.if_stmt.condition     = $2;
        $$ -> as.if_stmt.if_body       = $4;
        $$ -> as.if_stmt.else_body     = $5;
    }
    ;

/* --- LIST RULES FOR MULTIPLE ASSIGNMENT --- */
var_list:
    TOKEN_IDENTIFIER {
        $$ = make_node_ident($1);
    }
    | prefix_expr '.' TOKEN_IDENTIFIER {
        ASTNode *string_key = make_node_string ($3);
        $$ = make_node_table_get ($1, string_key);
    }
    | prefix_expr '[' expr ']' {
        $$ = make_node_table_get ($1, $3);
    }
    | var_list ',' TOKEN_IDENTIFIER {
        ASTNode* new_ident = make_node_ident($3);
        ASTNode* curr = $1;
        while(curr->next) curr = curr->next;
        curr->next = new_ident;
        $$ = $1;
    }
    | var_list ',' prefix_expr '.' TOKEN_IDENTIFIER {
        ASTNode *string_key = make_node_string ($5);
        ASTNode *new_target = make_node_table_get ($3, string_key);
        ASTNode* curr = $1;
        while(curr->next) curr = curr->next;
        curr->next = new_target;
        $$ = $1;
    }
    | var_list ',' prefix_expr '[' expr ']' {
        ASTNode *new_target = make_node_table_get ($3, $5);
        ASTNode* curr = $1;
        while(curr->next) curr = curr->next;
        curr->next = new_target;
        $$ = $1;
    }
    ;

expr_list:
    expr { 
        $$ = $1; 
    }
    | expr_list ',' expr { 
        ASTNode* curr = $1;
        while(curr->next) curr = curr->next;
        curr->next = $3;
        $$ = $1; 
    }
    ;

function_def:
    /* Standard Function: function my_func() ... end */
    func_start TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END {
        // 1. Build the structural function definition using pre-allocated node
        ASTNode* func_def = $1;
        func_def->as.function_def.name = strdup($2);
        func_def->as.function_def.params = $4;
        note_function_param_count(func_def->as.function_def.params);
        func_def->as.function_def.body = $6;

        // NEW: Check if parameter_list contains "..."
        func_def->as.function_def.is_variadic = 0;
        ASTNode *p = $4;
        while (p != NULL) {
            if (p->type == NODE_IDENTIFIER && strcmp(p->as.id.name, "...") == 0) {
                func_def->as.function_def.is_variadic = 1;
                break;
            }
            p = p->next;
        }

        // 2. Instantiate a function pointer node for the address
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup($2);

        // 3. Assign the pointer to the global variable (e.g., func_add)
        ASTNode* assign = make_node(NODE_MULTIPLE_ASSIGNMENT);
        assign->as.mult_assign.targets_head = make_node_ident($2);
        assign->as.mult_assign.values_head = func_ptr;

        // 4. Chain them sequentially for the global init vector
        func_def->next = assign;
        $$ = func_def;
    }
    | /* Table Dot Method Desugaring: function my_table.my_func() ... end */
    func_start TOKEN_IDENTIFIER '.' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END {
        // 1. Create a unique mangled label using the helper function
        char* mangled_name = mangle_method_name($2, $4);

        // 2. Build the structural function definition body using pre-allocated node
        ASTNode* func_def = $1;
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = $6;
        note_function_param_count(func_def->as.function_def.params);
        func_def->as.function_def.body = $8;

        // 3. Instantiate a function pointer node evaluating to that address
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        ASTNode* key_node = make_node_string($4);
        ASTNode* table_node = make_node_ident($2);
        
        // 4. Tie it all into a table assignment: table[key] = func_ptr
        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key = key_node;
        table_set->as.table_set.value = func_ptr;

        // 5. Chain them sequentially so the compiler outputs both properties cleanly
        func_def->next = table_set;
        $$ = func_def;
    }
    | /* Table Colon Method Desugaring: function my_table:my_func() ... end */
    func_start TOKEN_IDENTIFIER ':' TOKEN_IDENTIFIER '(' parameter_list ')' statement_list TOKEN_END {
        // 1. Create a unique mangled label using the helper function
        char* mangled_name = mangle_method_name($2, $4);

        // 2. INJECT "self" as the first parameter!
        ASTNode* self_param = make_node_ident("self");
        self_param->next = $6; // Link it to the rest of the parameters

        // 3. Build the structural function definition body using pre-allocated node
        ASTNode* func_def = $1;
        func_def->as.function_def.name = mangled_name;
        func_def->as.function_def.params = self_param; // Set self as the head of the list
        note_function_param_count(func_def->as.function_def.params);
        func_def->as.function_def.body = $8;

        // 4. Instantiate a function pointer node evaluating to that address
        ASTNode* func_ptr = make_node(NODE_FUNCTION_POINTER);
        func_ptr->as.func_ptr.mangled_name = strdup(mangled_name);

        ASTNode* key_node = make_node_string($4);
        ASTNode* table_node = make_node_ident($2);
        
        // 5. Tie it all into a table assignment: table[key] = func_ptr
        ASTNode* table_set = make_node(NODE_TABLE_SET);
        table_set->as.table_set.table_expr = table_node;
        table_set->as.table_set.key = key_node;
        table_set->as.table_set.value = func_ptr;

        // 6. Chain them sequentially so the compiler outputs both properties cleanly
        func_def->next = table_set;
        $$ = func_def;
    }
    ;

return_stmt:
    TOKEN_RETURN expr_list {
        $$ = make_node(NODE_RETURN);
        $$->as.return_stmt.expressions_head = $2;
        $$->as.return_stmt.parent_func_arg_count = 0;
    }
    | TOKEN_RETURN {
        // Bare 'return' with no expression -- equivalent to returning
        // no values at all. node_return() already handles a NULL
        // expressions_head correctly: its per-expression loop simply
        // doesn't execute (ret_idx stays 0), and the existing
        // stale-register nil-padding logic (see the earlier fix) fills
        // in BOXED_NIL for however many return slots this function's
        // OTHER branches statically require -- exactly the same as an
        // early-exit branch that returns fewer values than a sibling
        // branch elsewhere in the same function.
        $$ = make_node(NODE_RETURN);
        $$->as.return_stmt.expressions_head = NULL;
        $$->as.return_stmt.parent_func_arg_count = 0;
    }
    ;

prefix_expr:
    TOKEN_IDENTIFIER { 
        $$ = make_node_ident($1); 
    }
    | function_call { 
        $$ = $1; 
    }
    | '(' expr ')' { 
        $$ = $2; 
    }
    | prefix_expr '[' expr ']' {
        $$ = make_node(NODE_TABLE_GET);
        $$->as.table_get.table_expr = $1;
        $$->as.table_get.key = $3;
    }
    | prefix_expr '.' TOKEN_IDENTIFIER {
        ASTNode *string_key = make_node_string($3);
        $$ = make_node(NODE_TABLE_GET);
        $$->as.table_get.table_expr = $1;
        $$->as.table_get.key = string_key;
    }
    ;

expr:
    TOKEN_DOTS {
        $$ = make_node(NODE_VARIADIC_EXPR);
    }
    | TOKEN_NUMBER {
        $$ = make_node(NODE_NUMBER);
        $$->as.number.val = $1;
    }
    | TOKEN_STRING      { $$ = make_node_string($1); }
    | table_constructor { $$ = $1; }
    | prefix_expr       { $$ = $1; }  /* <-- REPLACES IDENTS, PARENS, TABLE GETS, & CALLS! */
    | expr '+' expr     { $$ = make_node_binary (NODE_ADD, $1, $3); }
    | expr '-' expr     { $$ = make_node_binary (NODE_SUB, $1, $3); }
    | expr '*' expr     { $$ = make_node_binary (NODE_MUL, $1, $3); }
    | expr TOKEN_FLOORDIV expr { $$ = make_node_binary (NODE_FLOORDIV, $1, $3); }
    | expr '/' expr     { $$ = make_node_binary (NODE_DIV, $1, $3); }
    | expr '%' expr     { $$ = make_node_binary (NODE_MOD, $1, $3); }
    | expr '^' expr     { $$ = make_node_binary (NODE_POW, $1, $3); }
    | TOKEN_TRUE  { $$ = make_node_boolean (true);  }
    | TOKEN_FALSE { $$ = make_node_boolean (false); }
    | TOKEN_NIL   { $$ = make_node_nil ();          }
    | TOKEN_LEN expr    { $$ = make_node_unary  (OP_LEN,   $2);     }
    | '-' expr %prec UNARY_MINUS { $$ = make_node_unary (OP_UNM, $2); }
    | TOKEN_NOT expr             { $$ = make_node_unary (OP_NOT, $2); }
    | expr TOKEN_EQ expr      { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_EQ;  $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_NEQ expr     { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_NEQ; $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_LT expr      { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_LT;  $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_GT expr      { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_GT;  $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_LE expr      { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_LE;  $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_GE expr      { $$ = make_node(NODE_RELATIONAL); $$->as.binary.operator = OP_GE;  $$->as.binary.left = $1; $$->as.binary.right = $3; }
    | expr TOKEN_AND expr     { $$ = make_node(NODE_AND);        $$->as.binary.left = $1;     $$->as.binary.right = $3; }
    | expr TOKEN_OR expr      { $$ = make_node(NODE_OR);         $$->as.binary.left = $1;     $$->as.binary.right = $3; }
    | expr TOKEN_CONCAT expr  { $$ = make_node(NODE_CONCAT);     $$->as.binary.left = $1;     $$->as.binary.right = $3; }
    | func_start '(' parameter_list ')' statement_list TOKEN_END
    {
        static int anon_counter = 0;
        char buf[64];
        snprintf(buf, sizeof(buf), "__anon_%d", anon_counter++);

        ASTNode* func_def = $1;
        func_def->as.function_def.name = strdup(buf);
        func_def->as.function_def.params = $3;
        note_function_param_count(func_def->as.function_def.params);
        func_def->as.function_def.body = $5;

        // Initialize and check variadic status for anonymous functions
        func_def->as.function_def.is_variadic = 0;
        ASTNode *p = $3;
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

        $$ = func_ptr;
    }
    ;

function_call:
    TOKEN_IDENTIFIER '(' argument_list ')' {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.target = make_node_ident($1);
        node->as.call.is_method_call = 0; 
        node->as.call.args_head = $3;
        $$ = node;
    }
    | prefix_expr '.' TOKEN_IDENTIFIER '(' argument_list ')' {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.is_method_call = 0;
        
        // Dynamically look up the function inside the table
        ASTNode* dynamic_lookup = make_node(NODE_TABLE_GET);
        dynamic_lookup->as.table_get.table_expr = $1;
        dynamic_lookup->as.table_get.key = make_node_string($3);
        node->as.call.target = dynamic_lookup;
        node->as.call.args_head = $5;
        $$ = node;
    }
    | prefix_expr ':' TOKEN_IDENTIFIER '(' argument_list ')' {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.target = $1;
        node->as.call.is_method_call = 1;
        
        ASTNode* dynamic_lookup = make_node(NODE_TABLE_GET);
        dynamic_lookup->as.table_get.table_expr = $1;
        dynamic_lookup->as.table_get.key = make_node_string($3);
        node->as.call.target = dynamic_lookup;
        node->as.call.args_head = $5;
        $$ = node;
    }
    | prefix_expr '(' argument_list ')' {
        ASTNode* node = make_node(NODE_FUNCTION_CALL);
        node->as.call.target = $1;
        node->as.call.is_method_call = 0;
        node->as.call.args_head = $3;
        $$ = node;
    }
    ;

field:
    expr {
        // Array-style: {value} -> implicit sequential key
        $$ = $1;
    }
    | expr '=' expr {
    // Record-style: {key = value}
    // Convert identifier key to string literal (Lua semantics: x=8 means key "x", not var x)
    ASTNode *key_node = $1;
    if (key_node->type == NODE_IDENTIFIER) {
        key_node = make_node_string(key_node->as.id.name);
    }
    $$ = make_node_table_set(NULL, key_node, $3);
}
    | '[' expr ']' '=' expr {
        // Explicit key: {[key] = value}
        $$ = make_node_table_set(NULL, $2, $5);
    }
    ;

field_list:
    field {
        $$ = $1;
    }
    | field_list ',' field {
        // Chain fields together via next pointer
        ASTNode* curr = $1;
        while (curr->next) curr = curr->next;
        curr->next = $3;
        $$ = $1;
    }
    ;

table_constructor:
    '{' '}' {
        $$ = make_node_table_constructor(NULL);
    }
    | '{' field_list '}' {
        $$ = make_node_table_constructor($2);
    }
    | '{' field_list ',' '}' {
        // Trailing comma before the closing brace -- e.g.
        //   { [1] = a, [2] = b, }
        // Standard, idiomatic Lua; the parser previously had no
        // production for a comma immediately followed by '}', since
        // field_list only ever grows via 'field_list , field' and a
        // field must start with an expression token, which '}' is not.
        $$ = make_node_table_constructor($2);
    }
    ;

tic80_section:
    TOKEN_TIC80_SECTION_HEADER
    {
        current_tic80_section = strdup($1);
        free($1);
    }
    tic80_asset_lines
    TOKEN_TIC80_SECTION_FOOTER
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

        free($3);
        $$ = NULL;
    }
    ;

tic80_asset_lines:
    /* empty */ { $$ = NULL; }
    | tic80_asset_lines TOKEN_TIC80_ASSET_DATA
    {
        TIC80AssetData *data = parse_tic80_asset_line($2);
        if (data != NULL) {  // <-- ADD THIS CHECK
            data->next = current_tic80_assets;
            current_tic80_assets = data;
        }
        free($2);
        $$ = NULL;
    }
    ;
%%

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
