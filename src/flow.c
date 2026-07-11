#include "codegen.h"

void generate_repeat_loop(ASTNode* node) {
    int loop_id = get_next_label_id();
    char start_label[32];
    snprintf(start_label, sizeof(start_label), "__repeat_start_%d", loop_id);

    printf("%s:\n", start_label);

    // 1. Execute Loop Body First
    generate_statement(node->body);

    // 2. Evaluate Until Condition -> Leaves result in R0
    generate_expression(node->condition);

    // 3. If the result IS Nil, loop again!
    printf("    MOV   R6, R0\n");
    printf("    IEQ   R6, 0xFFC00000 ; Is condition Nil?\n");
    printf("    JT    R6, %s         ; If Nil (falsy), keep looping\n", start_label);

    // 4. If the result IS False, loop again!
    printf("    MOV   R6, R0\n");
    printf("    IEQ   R6, 0xFFC00001 ; Is condition False?\n");
    printf("    JT    R6, %s         ; If False (falsy), keep looping\n", start_label);

    // If it wasn't Nil or False, it is truthy -> loop terminates naturally!
}

void generate_while_loop(ASTNode* node) {
    int loop_id = get_next_label_id();
    char start_label[32], end_label[32];
    snprintf(start_label, sizeof(start_label), "__while_start_%d", loop_id);
    snprintf(end_label, sizeof(end_label), "__while_end_%d", loop_id);

    printf("%s:\n", start_label);

    // 1. Evaluate Condition -> Leaves result in R0
    generate_expression(node->condition);

    // 2. If falsy, break out of loop
    emit_falsy_jump(end_label);

    // 3. Loop Body
    generate_statement(node->body);

    // 4. Jump back to condition check
    printf("    JMP   %s\n", start_label);
    printf("%s:\n", end_label);
}

void generate_if_statement(ASTNode* node) {
    int if_id = get_next_label_id();
    char else_label[32], end_label[32];
    snprintf(else_label, sizeof(else_label), "__if_else_%d", if_id);
    snprintf(end_label, sizeof(end_label), "__if_end_%d", if_id);

    // 1. Evaluate Condition -> Leaves result in R0
    generate_expression(node->condition);

    // 2. If falsy, jump to else block (or end label if no else block exists)
    emit_falsy_jump(node->else_body ? else_label : end_label);

    // 3. 'Then' Body
    generate_statement(node->then_body);
    printf("    JMP   %s\n", end_label);

    // 4. 'Else' Body (Optional)
    if (node->else_body) {
        printf("%s:\n", else_label);
        generate_statement(node->else_body);
    }

    printf("%s:\n", end_label);
}
