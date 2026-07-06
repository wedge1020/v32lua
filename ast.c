typedef struct ASTNode ASTNode;

struct ASTNode
{
    NodeType type;
    union
    {
        // NODE_PROGRAM / BLOCK
        struct
        {
            ASTNode **statements;
            int32_t   statement_count;
        } program;

        // NODE_ASSIGN
        struct
        {
            int8_t   *name;
            ASTNode  *value;
        } assign;

        // NODE_BINARY_OP
        struct
        {
            int32_t   op; // '+', '-', '*', '/'
            ASTNode  *left;
            ASTNode  *right;
        } binary_op;

        // NODE_IDENTIFIER
        struct
        {
            int8_t   *name;
        } identifier;

        // NODE_NUMBER
        struct
        {
            float     value; // Lua uses floats natively, fitting Vircon32 HW
        } number;

        // NODE_WHILE
        struct
        {
            ASTNode  *condition;
            ASTNode  *body;
        } while_loop;
    } data;
};
