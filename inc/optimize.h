#ifndef __OPTIMIZE_H
#define __OPTIMIZE_H

#define MAX_TRACKED_CONSTS 256
#define MAX_TRACKED_STORES 128

typedef struct
{
    char    name[64];
    double  value;
    bool    is_active;
} ConstSymbol;

typedef struct
{
    char var_name[64];
    ASTNode *assign_node; // Pointer to the NODE_MULTIPLE_ASSIGNMENT
    bool is_active;
} DeadStoreCandidate;

ASTNode *fold_constants      (ASTNode *);
void     clear_const_table   ();
void     set_constant_var    (const char *, double);
bool     get_constant_var    (const char *, double *);
void     remove_constant_var (const char *);
ASTNode *propagate_constants (ASTNode *);
bool     is_pure_expression  (ASTNode *);

// OPTIMIZATION: DEAD STORE ELIMINATION
void     mark_variable_read  (const char *);
void     scan_for_reads      (ASTNode *);
void     clear_dse_table     (void);
void     eliminate_dead_stores_in_list (ASTNode *);

// OPTIMIZATION: DEAD BRANCH ELIMINATION
int      is_constant_truthy  (ASTNode *, int *);
ASTNode *append_ast_chains   (ASTNode *, ASTNode *);

void     optimize_block      (ASTNode *);

#endif
