#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "codegen.h"

// --- Label Generator & Function Context Stack ---

// Define the node structure for our linked list stack
typedef struct FunctionContextNode {
    const char* name;
    int label_counter;
    struct FunctionContextNode* next;
} FunctionContextNode;

// Head pointer for the stack
static FunctionContextNode* context_stack_head = NULL;

// Fallback counter for statements outside functions
static int global_label_counter = 0; 

int get_next_label(void) {
    if (context_stack_head == NULL) {
        // We are in the global scope
        return global_label_counter++;
    }
    // Return and increment the counter for the current function scope
    return context_stack_head->label_counter++;
}

void push_function_context(const char* name) {
    FunctionContextNode* new_node = (FunctionContextNode*)malloc(sizeof(FunctionContextNode));
    if (new_node == NULL) {
        fprintf(stderr, "Compiler Error: Out of memory allocating function context\n");
        exit(1);
    }
    
    // Initialize the new context
    new_node->name = name; 
    new_node->label_counter = 0; // Reset counter for this new function
    
    // Push it onto the top of the stack
    new_node->next = context_stack_head;
    context_stack_head = new_node;
}

void pop_function_context(void) {
    if (context_stack_head == NULL) {
        fprintf(stderr, "Compiler Error: Function context stack underflow\n");
        exit(1);
    }
    
    // Pop and free the top node to prevent memory leaks
    FunctionContextNode* old_head = context_stack_head;
    context_stack_head = context_stack_head->next;
    free(old_head);
}

const char* get_current_function_name(void) {
    if (context_stack_head == NULL) {
        return "global";
    }
    return context_stack_head->name;
}

// --- String Literal Tracking ---
typedef struct StringLiteralNode {
    int id;
    char* value;
    struct StringLiteralNode* next;
} StringLiteralNode;

static StringLiteralNode* strings_head = NULL;
static int string_counter = 0;

int add_string_literal(const char* str) {
    // Check if duplicate string already exists
    StringLiteralNode* current = strings_head;
    while (current != NULL) {
        if (strcmp(current->value, str) == 0) {
            return current->id;
        }
        current = current->next;
    }

    StringLiteralNode* new_node = (StringLiteralNode*)malloc(sizeof(StringLiteralNode));
    new_node->id = string_counter++;
    new_node->value = strdup(str);
    new_node->next = strings_head;
    strings_head = new_node;
    return new_node->id;
}

void emit_string_data_section(void) {
    if (strings_head == NULL) return;
    
    printf("\n; --- String Literal Allocations ---\n");
    StringLiteralNode* current = strings_head;
    while (current != NULL) {
        printf("__string_%d:\n", current->id);
        printf("  integer ");
        for (int i = 0; current->value[i] != '\0'; i++) {
            printf("%d, ", (int)current->value[i]);
        }
        printf("0\n"); // Null terminator word
        current = current->next;
    }
}

// --- Loop Stack (for break statements) ---
#define MAX_SUB_DEPTH 128
static int loop_stack[MAX_SUB_DEPTH];
static int loop_stack_top = -1;

void push_loop(int id) {
    if (loop_stack_top >= MAX_SUB_DEPTH - 1) {
        fprintf(stderr, "Compiler Error: Loop stack overflow\n");
        exit(1);
    }
    loop_stack[++loop_stack_top] = id;
}

void pop_loop(void) {
    if (loop_stack_top < 0) {
        fprintf(stderr, "Compiler Error: Loop stack underflow\n");
        exit(1);
    }
    loop_stack_top--;
}

int current_loop(void) {
    if (loop_stack_top < 0) {
        return -1;
    }
    return loop_stack[loop_stack_top];
}

// --- Direct RAM Allocator ---
typedef struct GlobalVarNode {
    char* name;
    int ram_address;
    struct GlobalVarNode* next;
} GlobalVarNode;

static GlobalVarNode* globals_head = NULL;
static int next_ram_address = 1; // Address 0 is reserved for our __heap_pointer

int get_global_variable_address(const char* name) {
    GlobalVarNode* current = globals_head;
    while (current != NULL) {
        if (strcmp(current->name, name) == 0) {
            return current->ram_address;
        }
        current = current->next;
    }

    // Allocate a raw RAM location to avoid Cartridge ROM write conflicts
    GlobalVarNode* new_node = (GlobalVarNode*)malloc(sizeof(GlobalVarNode));
    new_node->name = strdup(name);
    new_node->ram_address = next_ram_address++;
    new_node->next = globals_head;
    globals_head = new_node;
    
    return new_node->ram_address;
}
