typedef enum
{
	NODE_PROGRAM,     // Root of the script
	NODE_ASSIGN,      // a = expression
	NODE_BINARY_OP,   // arithmetic (+, -, *, /)
	NODE_IDENTIFIER,  // Variable name
	NODE_NUMBER,      // Numeric literal
	NODE_WHILE        // while condition do body end
} NodeType;
