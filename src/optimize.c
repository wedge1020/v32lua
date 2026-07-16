#include "v32lua.h"

static ConstSymbol o_const_table[MAX_TRACKED_CONSTS];

static DeadStoreCandidate  o_dse_table[MAX_TRACKED_STORES];

void  eliminate_dead_stores_in_list (ASTNode *head)
{
    for (ASTNode *curr = head; curr != NULL; curr = curr->next) {

        switch (curr->type) {
            // ==========================================
            // 1. EVALUATE ASSIGNMENTS
            // ==========================================
            case NODE_MULTIPLE_ASSIGNMENT: {
                // Step A: In Lua, RHS expressions evaluate BEFORE assignments occur.
                // Any variables used in the RHS values are READ, so scan them first!
                for (ASTNode *val = curr->as.mult_assign.values_head; val != NULL; val = val->next) {
                    scan_for_reads(val);
                }

                // Step B: Check if all RHS expressions are side-effect free (pure)
                bool all_pure = true;
                for (ASTNode *val = curr->as.mult_assign.values_head; val != NULL; val = val->next) {
                    if (!is_pure_expression(val)) {
                        all_pure = false;
                        break;
                    }
                }

                // Step C: Process left-hand side targets
                // For simplicity in -O1, we target 1-to-1 assignments (e.g., x = expr)
                if (curr->as.mult_assign.targets_head != NULL &&
                    curr->as.mult_assign.targets_head->next == NULL &&
                    curr->as.mult_assign.targets_head->type == NODE_IDENTIFIER)
                {
                    char *target_var = curr->as.mult_assign.targets_head->as.id.name;

                    // Check if this variable is ALREADY waiting in our candidate table!
                    for (int i = 0; i < MAX_TRACKED_STORES; i++) {
                        if (o_dse_table[i].is_active && strcmp(o_dse_table[i].var_name, target_var) == 0) {

                            // WE FOUND A DEAD STORE! The previous assignment was never read!
                            ASTNode *dead_node = o_dse_table[i].assign_node;

                            if (g_debug_mode) {
                                printf("[DSE] Eliminating dead store to '%s' at line %d\n",
                                       target_var, dead_node->line_number);
                            }

                            // SAFE TRANSMUTATION: Convert old assignment into an Assembly Comment No-Op
                            dead_node->type = NODE_ASM;
                            dead_node->as.inline_asm.code = ";; OPTIMIZATION (-O1): Dead store eliminated\n";

                            o_dse_table[i].is_active = false;
                            break;
                        }
                    }

                    // If the RHS is pure, register THIS assignment as a new candidate for DSE
                    if (all_pure) {
                        for (int i = 0; i < MAX_TRACKED_STORES; i++) {
                            if (!o_dse_table[i].is_active) {
                                strncpy(o_dse_table[i].var_name, target_var, sizeof(o_dse_table[i].var_name) - 1);
                                o_dse_table[i].assign_node = curr;
                                o_dse_table[i].is_active = true;
                                break;
                            }
                        }
                    }
                }
                break;
            }

            // ==========================================
            // 2. CONTROL FLOW & BRANCHES (Safety Resets)
            // ==========================================
            case NODE_IF:
                scan_for_reads(curr->as.if_stmt.condition);
                clear_dse_table(); // Clear across control flow boundaries!

                // Recursively optimize child statement lists
                eliminate_dead_stores_in_list(curr->as.if_stmt.if_body);
                eliminate_dead_stores_in_list(curr->as.if_stmt.else_body);
                clear_dse_table();
                break;

            case NODE_WHILE:
                clear_dse_table();
                scan_for_reads(curr->as.while_loop.condition);
                eliminate_dead_stores_in_list(curr->as.while_loop.body);
                clear_dse_table();
                break;

            case NODE_FUNCTION_DEF:
                clear_dse_table();
                eliminate_dead_stores_in_list(curr->as.function_def.body);
                clear_dse_table();
                break;

            case NODE_FUNCTION_CALL:
                scan_for_reads(curr->as.call.target);
                for (ASTNode *arg = curr->as.call.args_head; arg != NULL; arg = arg->next) {
                    scan_for_reads(arg);
                }
                // Function calls might read/modify global variables; clear tracking table!
                clear_dse_table();
                break;

            case NODE_RETURN:
                for (ASTNode *expr = curr->as.return_stmt.expressions_head; expr != NULL; expr = expr->next) {
                    scan_for_reads(expr);
                }
                clear_dse_table();
                break;

            default:
                break;
        }
    }
}

void  clear_dse_table (void) {
    for (int i = 0; i < MAX_TRACKED_STORES; i++) {
        o_dse_table[i].is_active = false;
    }
}

// When a variable is READ, it is no longer dead! Remove it from candidate tracking.
void mark_variable_read(const char *name) {
    for (int i = 0; i < MAX_TRACKED_STORES; i++) {
        if (o_dse_table[i].is_active && strcmp(o_dse_table[i].var_name, name) == 0) {
            o_dse_table[i].is_active = false;
        }
    }
}

// Recursively scan an AST node to find ANY variable reads (NODE_IDENTIFIER)
void scan_for_reads(ASTNode *node)
{
    if (node != NULL)
    {
        while (node != NULL)
        {
            switch (node->type)
            {
                case NODE_IDENTIFIER:
                    // Mark the symbol as actively used
                    mark_variable_read(node->as.id.name);
                    break;

                case NODE_WHILE:
                    // Scan the condition for variable reads (e.g., while x < 10)
                    scan_for_reads(node->as.while_loop.condition);
                    // Scan inside the loop body
                    scan_for_reads(node->as.while_loop.body);
                    break;

                case NODE_IF:
                    // Scan the condition for variable reads (e.g., if is_ready then)
                    scan_for_reads(node->as.if_stmt.condition);
                    // Scan both branch bodies for variable usage
                    scan_for_reads(node->as.if_stmt.if_body);
                    scan_for_reads(node->as.if_stmt.else_body);
                    break;

                case NODE_UNARY:
                    scan_for_reads(node->as.unary.operand);
                    break;

                case NODE_ADD:
                case NODE_SUB:
                case NODE_MUL:
                case NODE_DIV:
                case NODE_AND:
                case NODE_OR:
                case NODE_RELATIONAL:
                case NODE_CONCAT:
                    scan_for_reads(node->as.binary.left);
                    scan_for_reads(node->as.binary.right);
                    break;

                case NODE_FUNCTION_CALL:
                    scan_for_reads(node->as.call.target);
                    // Walk the linked list of arguments
                    for (ASTNode *arg = node->as.call.args_head; arg != NULL; arg = arg->next) {
                        scan_for_reads(arg);
                    }
                    break;

                case NODE_TABLE_GET:
                    scan_for_reads(node->as.table_get.table_expr);
                    scan_for_reads(node->as.table_get.key);
                    break;

                case NODE_TABLE_SET:
                    scan_for_reads(node->as.table_set.table_expr);
                    scan_for_reads(node->as.table_set.key);
                    scan_for_reads(node->as.table_set.value);
                    break;

                default:
                    break;
            }
            // Advance to the next sibling statement in the current block
            node = node->next;
        }
    }
}

// Returns true if evaluating this expression has NO side effects (no function calls or I/O)
bool  is_pure_expression (ASTNode *node)
{
    if (node == NULL) return true;

    switch (node->type) {
        // Primitives and variable reads are 100% pure
        case NODE_NUMBER:
        case NODE_STRING:
        case NODE_IDENTIFIER:
            return true;

        // Unary expressions depend on their operand
        case NODE_UNARY:
            return is_pure_expression(node->as.unary.operand);

        // Binary math/relational expressions depend on both operands
        case NODE_ADD:
        case NODE_SUB:
        case NODE_MUL:
        case NODE_DIV:
        case NODE_AND:
        case NODE_OR:
        case NODE_RELATIONAL:
        case NODE_CONCAT:
            return is_pure_expression(node->as.binary.left) &&
                   is_pure_expression(node->as.binary.right);

        // Table constructors/accesses are pure unless they contain impure sub-expressions
        case NODE_TABLE_CONSTRUCTOR:
            return true;
        case NODE_TABLE_GET:
            return is_pure_expression(node->as.table_get.table_expr) &&
                   is_pure_expression(node->as.table_get.key);

        // Function calls, inline ASM, and table writes have side effects!
        case NODE_FUNCTION_CALL:
        case NODE_FUNCTION_POINTER:
        case NODE_TABLE_SET:
        case NODE_ASM:
        case NODE_RAWASM:
        default:
            return false;
    }
}

ASTNode *fold_constants (ASTNode *node)
{
    if (node                              != NULL)
    {
        switch (node -> type)
        {
            // ==========================================
            // 1. BINARY ARITHMETIC & COMPARISONS
            // ==========================================
            case NODE_ADD:
            case NODE_SUB:
            case NODE_MUL:
            case NODE_DIV: {
                // Post-order: Fold children first!
                node -> as.binary.left     = fold_constants (node -> as.binary.left);
                node -> as.binary.right    = fold_constants (node -> as.binary.right);

                ASTNode *left              = node -> as.binary.left;
                ASTNode *right             = node -> as.binary.right;

                // Check if both children are now numeric constants
                if ((left  -> type        == NODE_NUMBER) &&
                    (right -> type        == NODE_NUMBER))
                   {
                    double  l_val          = left  -> as.number.val;
                    double  r_val          = right -> as.number.val;
                    double  result         = 0.0;

                    switch (node -> type)
                    {
                        case NODE_ADD:
                            result         = l_val + r_val;
                            break;

                        case NODE_SUB:
                            result         = l_val - r_val;
                            break;

                        case NODE_MUL:
                            result         = l_val * r_val;
                            break;

                        case NODE_DIV:

                            // Safety Guard: Do not fold division by zero at compile-time!
                            // Leave it for runtime so it generates proper VM exceptions/errors.
                            if (r_val     == 0.0)
                            {
                                if (g_debug_mode)
                                {
                                    fprintf (stderr, "Warning: Compile-time division by zero avoided.\n");
                                }
                                return (node); 
                            }
                            result         = l_val / r_val;
                            break;

                        default:
                            break;
                    }

                    // In-Place Mutation: Transform this Binary Node into a Number Node
                    node -> type           = NODE_NUMBER;
                    node -> as.number.val  = result;
                    
                    // Optional: Free left and right child nodes here to avoid memory leaks
                    //free_ast (left);
                //    free_ast (right);
                }
                break;
            }

            // ==========================================
            // 2. UNARY OPERATIONS (e.g., -5 or !(1))
            // ==========================================
			/*
			case NODE_UNARY_MINUS:
				// Length (#) and Unary Minus (-) push arguments and call built-ins!
				if (node->as.unary.operator == OP_LEN || node->as.unary.operator == OP_UNM) {
					return 1;
				}
				// Check if the operand itself requires stack space
				return check_needs_stack(node->as.unary.operand);
				*/
            /*
            case NODE_UNARY_MINUS: {
                node -> as.unary.operand              = fold_constants (node -> as.unary.operand);
                if (node -> as.unary.operand -> type == NODE_NUMBER)
                {
                    double  val = node->as.unary.operand->as.number.val;
                    node -> type = NODE_NUMBER;
                    node -> as.number.val = -val;
                }
                break;
            }*/

            // ==========================================
            // 3. STATEMENTS & CONTROL FLOW
            // ==========================================
            case NODE_IDENTIFIER:
            case NODE_MULTIPLE_ASSIGNMENT:
                // Fold the right-hand side expression being assigned/declared
                //node -> as.mult_assign.expr  = fold_constants (node -> as.mult_assign.expr);
                break;

			case NODE_IF: {
				// 1. Recursively fold the condition first
				node->as.if_stmt.condition = fold_constants(node->as.if_stmt.condition);

				int is_const = 0;
				int truthy = is_constant_truthy(node->as.if_stmt.condition, &is_const);

				if (is_const)
				{
					// We are stripping the IF node, but we MUST preserve the rest of the program
					ASTNode *next_program_chain = fold_constants(node->next);

					if (truthy)
					{
						// Condition is always TRUE: Keep only the IF body, discard the ELSE body
						ASTNode *optimized_body = fold_constants(node->as.if_stmt.if_body);

						// NOTE: If you aren't using an arena allocator, free the unused
						// node, node->as.if_stmt.condition, and node->as.if_stmt.else_body here.

						return append_ast_chains(optimized_body, next_program_chain);
					}
					else
					{
						// Condition is always FALSE: Keep only the ELSE body, discard the IF body
						ASTNode *optimized_else = fold_constants(node->as.if_stmt.else_body);

						return append_ast_chains(optimized_else, next_program_chain);
					}
				}

				// If the condition isn't constant, keep the IF structure but optimize both branches
				node->as.if_stmt.if_body = fold_constants(node->as.if_stmt.if_body);
				node->as.if_stmt.else_body = fold_constants(node->as.if_stmt.else_body);
				break;
			}

			case NODE_WHILE: {
				// 1. Fold the loop condition
				node->as.while_loop.condition = fold_constants(node->as.while_loop.condition);

				int is_const = 0;
				int truthy = is_constant_truthy(node->as.while_loop.condition, &is_const);

				if (is_const && !truthy)
				{
					// Condition is always FALSE: The loop body will never run.
					// Bypass this node completely and jump straight to the next program statement.
					return fold_constants(node->next);
				}

				// NOTE: If the condition is always TRUE (infinite loop), we DO NOT prune the loop.
				// We keep the loop, but still optimize the statements inside its body.
				node->as.while_loop.body = fold_constants(node->as.while_loop.body);
				break;
			}

                /*
            case NODE_BLOCK: {
                // Traverse all statements in the linked list / array of the block
                ASTNode *curr = node->as.block.stmts;
                while (curr != NULL) {
                    curr = fold_constants(curr);
                    curr = curr->next; // Assuming linked-list AST structure
                }
                break;
            }
            */

            case NODE_FUNCTION_DEF:
                node->as.function_def.body = fold_constants(node->as.function_def.body);
                break;

            default:
                break;
        }

    }
    // Process the next statement in the chain normally if no pruning occurred
   // node->next = fold_constants(node->next); // disabled due to infinite recursion detected
    return (node);
}

// Clear the table when entering/exiting complex control flow
void clear_const_table() {
    for (int i = 0; i < MAX_TRACKED_CONSTS; i++) {
        o_const_table[i].is_active = false;
    }
}

// Record or update a constant variable
void set_constant_var(const char *name, double val) {
    // Check if it already exists to update it
    for (int i = 0; i < MAX_TRACKED_CONSTS; i++) {
        if (o_const_table[i].is_active && strcmp(o_const_table[i].name, name) == 0) {
            o_const_table[i].value = val;
            return;
        }
    }
    // Otherwise, find an empty slot
    for (int i = 0; i < MAX_TRACKED_CONSTS; i++) {
        if (!o_const_table[i].is_active) {
            strncpy(o_const_table[i].name, name, sizeof(o_const_table[i].name) - 1);
            o_const_table[i].value = val;
            o_const_table[i].is_active = true;
            return;
        }
    }
}

// Try to fetch a constant variable's value
bool get_constant_var(const char *name, double *out_val) {
    for (int i = 0; i < MAX_TRACKED_CONSTS; i++) {
        if (o_const_table[i].is_active && strcmp(o_const_table[i].name, name) == 0) {
            *out_val = o_const_table[i].value;
            return true;
        }
    }
    return false;
}

// Invalidate a variable if it gets assigned a non-constant runtime expression
void remove_constant_var(const char *name) {
    for (int i = 0; i < MAX_TRACKED_CONSTS; i++) {
        if (o_const_table[i].is_active && strcmp(o_const_table[i].name, name) == 0) {
            o_const_table[i].is_active = false;
            return;
        }
    }
}

ASTNode* propagate_constants(ASTNode *node) {
    if (node == NULL) return NULL;

    switch (node->type) {
        // ==========================================
        // 1. THE CORE WIN: IDENTIFIER SUBSTITUTION
        // ==========================================
        case NODE_IDENTIFIER: {
            double const_val = 0.0;
            // If this identifier is currently known to hold a constant...
            if (get_constant_var(node->as.id.name, &const_val)) {
                if (g_debug_mode) {
                    printf("[Propagate] Replacing variable '%s' with constant %f\n",
                           node->as.id.name, const_val);
                }
                // In-Place Mutation: Transform IDENTIFIER into NUMBER!
                node->type = NODE_NUMBER;
                node->as.number.val = const_val;
            }
            break;
        }

        // ==========================================
        // 2. TRACKING ASSIGNMENTS & DECLARATIONS
        // ==========================================
        case NODE_MULTIPLE_ASSIGNMENT:
            if (node->as.mult_assign.is_local) {
                // This is a local variable declaration (e.g., "local x = 5" or bare "local x")
                ASTNode *target = node->as.mult_assign.targets_head;
                while (target != NULL) {
                    register_local(target->as.id.name); // Register symbol in current scope
                    target = target->next;
                }
            } // else a standard assignment
            break;

        // ==========================================
        // 3. CONTROL FLOW SAFETY (INVALIDATION)
        // ==========================================
        case NODE_IF:
            // 1. Evaluate the if condition
            node->as.if_stmt.condition = propagate_constants(node->as.if_stmt.condition);

            // 2. Traverse the main IF body
            node->as.if_stmt.if_body = propagate_constants(node->as.if_stmt.if_body);

            // 3. Safely traverse the ELSE body if it exists
            if (node->as.if_stmt.else_body != NULL)
            {
                node->as.if_stmt.else_body = propagate_constants(node->as.if_stmt.else_body);
            }
            clear_const_table(); // Safety reset!
            break;

        case NODE_WHILE:
            clear_const_table();
            // 1. Fold and propagate inside the loop condition
            node->as.while_loop.condition = propagate_constants(node->as.while_loop.condition);

            // 2. Traverse the statement block inside the loop body
            node->as.while_loop.body = propagate_constants(node->as.while_loop.body);
            clear_const_table();
            break;

        case NODE_FUNCTION_DEF:
            clear_const_table();
            node->as.function_def.body = propagate_constants(node->as.function_def.body);
            clear_const_table();
            break;

        // ==========================================
        // 4. STANDARD RECURSIVE TRAVERSAL
        // ==========================================
        case NODE_ADD:
        case NODE_SUB:
        case NODE_MUL:
        case NODE_DIV:
            node->as.binary.left  = propagate_constants(node->as.binary.left);
            node->as.binary.right = propagate_constants(node->as.binary.right);
            break;

            /*
        case NODE_BLOCK: {
            ASTNode *curr = node->as.block.stmts;
            while (curr != NULL) {
                curr = propagate_constants(curr);
                curr = curr->next;
            }
            break;
        }
        */

        default:
            break;
    }

    return node;
}

// Helper: Checks if a node has folded into a static number constant.
// (Adjust "NODE_NUMBER" and "as.number.value" to match your actual AST structure)
int is_constant_truthy(ASTNode *node, int *is_const)
{
    if (node == NULL)
    {
        *is_const = 0;
        return 0;
    }

    if (node->type == NODE_NUMBER)
    {
        *is_const = 1;
        return (node->as.number.val != 0.0);
    }

    *is_const = 0;
    return 0;
}

// Helper: Attaches the rest of the program (second) to the end of a block (first).
ASTNode *append_ast_chains(ASTNode *first, ASTNode *second)
{
    if (first == NULL) return second;

    ASTNode *curr = first;
    while (curr->next != NULL)
    {
        curr = curr->next;
    }
    curr->next = second;
    return first;
}

void  optimize_block (ASTNode *head) {
    ASTNode *current = head;
    while (current != NULL) {
        // 1. Optimize the current statement/expression tree
        //optimize_ast(current);

        // 2. Move to the next sibling statement in the block
        current = current->next;
    }
}
