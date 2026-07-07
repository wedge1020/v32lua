#include "codegen.h"

// --- String Pool Linked List ---
typedef struct StringNode {
    int id;
    char* value;
    struct StringNode* next;
} StringNode;

static StringNode* string_pool_head = NULL;
static StringNode* string_pool_tail = NULL;
static int string_count = 0;

int add_string_literal(const char* str) {
    StringNode* new_node = (StringNode*)malloc(sizeof(StringNode));
    new_node->id = string_count++;
    new_node->value = strdup(str);
    new_node->next = NULL;

    if (string_pool_tail == NULL) {
        string_pool_head = new_node;
        string_pool_tail = new_node;
    } else {
        string_pool_tail->next = new_node;
        string_pool_tail = new_node;
    }
    return new_node->id;
}

void emit_string_data_section() {
    if (string_pool_head == NULL) return;
    printf("\n; --- Static String Data ---\n");
    StringNode* current = string_pool_head;
    while (current != NULL) {
        printf("__string_%d:\n", current->id);
        printf("  string \"%s\"\n", current->value);
        current = current->next;
    }
}

// --- Function Context Stack ---
typedef struct FuncContextNode {
    char* name;
    struct FuncContextNode* next;
} FuncContextNode;

static FuncContextNode* func_stack_head = NULL;

void push_function_context(const char* func_name) {
    FuncContextNode* new_node = (FuncContextNode*)malloc(sizeof(FuncContextNode));
    new_node->name = strdup(func_name);
    new_node->next = func_stack_head;
    func_stack_head = new_node;
}

void pop_function_context() {
    if (func_stack_head != NULL) {
        FuncContextNode* temp = func_stack_head;
        func_stack_head = func_stack_head->next;
        free(temp->name);
        free(temp);
    }
}

const char* get_current_function_name() {
    return (func_stack_head == NULL) ? "main" : func_stack_head->name;
}

// --- Loop Label tracking ---
typedef struct LoopNode {
    int id;
    struct LoopNode* next;
} LoopNode;

static LoopNode* loop_stack_head = NULL;

void push_loop(int id) {
    LoopNode* node = (LoopNode*)malloc(sizeof(LoopNode));
    node->id = id;
    node->next = loop_stack_head;
    loop_stack_head = node;
}

void pop_loop() {
    if (loop_stack_head != NULL) {
        LoopNode* temp = loop_stack_head;
        loop_stack_head = loop_stack_head->next;
        free(temp);
    }
}

int current_loop() {
    return (loop_stack_head == NULL) ? -1 : loop_stack_head->id;
}

static int label_counter = 0;
int get_next_label() { return ++label_counter; }
