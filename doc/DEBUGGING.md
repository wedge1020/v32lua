# v32lua Debugging Reference

> **Assembly-Oriented Troubleshooting Guide for the `v32lua` compiler**

---

## 📚 Table of Contents

1. [NaN-Boxing Scheme](#1-nan-boxing-scheme)
2. [Table Architecture](#2-table-architecture)
3. [AST Node Types & Code Generation](#3-ast-node-types--code-generation)
4. [Register Allocation & Pinning](#4-register-allocation--pinning)
5. [Intrinsics System](#5-intrinsics-system)
6. [Variable Storage: Global vs Local/Stack](#6-variable-storage-global-vs-localstack)
7. [Runtime Routines Reference](#7-runtime-routines-reference)
8. [Common Debugging Scenarios](#8-common-debugging-scenarios)
9. [Memory Layout Quick Reference](#9-memory-layout-quick-reference)

---

## 1. NaN-Boxing Scheme

v32lua uses **NaN-boxing** to represent all Lua values as 32-bit floats, with type information encoded in the upper bits.

### Type Tags & Bitmasks

| Tag | Hex | Category | Type | Storage |
|-----|-----|----------|------|---------|
| `BOXED_TABLE` | `0xFF800000` | RAM (1) | TABLE/FUNC (0) | RAM |
| `BOXED_FUNCTION` | `0x7F800000` | ROM (0) | TABLE/FUNC (0) | ROM |
| `BOXED_ROMSTRING` | `0x7FC00000` | ROM (0) | STRING (1) | ROM |
| `BOXED_RAMSTRING` | `0xFFC00000` | RAM (1) | STRING (1) | RAM |
| `BOXED_NIL` | `0xFFC00000` | RAM (1) | STRING (1) | N/A |
| `BOXED_FALSE` | `0xFFC00001` | RAM (1) | STRING (1) | N/A |
| `BOXED_TRUE` | `0xFFC00002` | RAM (1) | STRING (1) | N/A |

**Bitmask Definitions:**
```c
#define BOXED_CATEGORY  0x80000000  // Sign bit: RAM(1) vs ROM(0)
#define BOXED_TYPE      0x00400000  // Bit 22: TABLE/FUNC(0) vs STRING(1)
#define BOXED_DATA      0xFFC00000  // Common boxed data mask
#define BOXED_PAYLOAD   0x003FFFFF  // Extract address/data
#define TABLE_ARRAYSIZE 0x0000FFFF  // Capacity mask
```

**Unboxing:**
```assembly
; Always validate first!
MOV  R4, R1
AND  R4, BOXED_DATA
IEQ  R4, BOXED_TABLE
JF   R4, __runtime_error_not_table
AND  R1, BOXED_PAYLOAD   ; Now safe to unbox
```

---

## 2. Table Architecture

### Header Layout (16 bytes)

| Offset | Field | Purpose |
|--------|-------|---------|
| `[R0+0]` | **flags** | Bitfield: lower 16 bits = array capacity |
| `[R0+1]` | **length** | Current array length (1-based integer) |
| `[R0+2]` | **array_ptr** | Pointer to contiguous array storage |
| `[R0+3]` | **hash_ptr** | Pointer to first hash bucket |

**Key distinction:**
- **Capacity** (from flags via `TABLE_ARRAYSIZE` mask): Maximum array elements *allocated*
- **Length** (word 1): Current array elements *used*
- **Relationship: `capacity >= length`**

When `length` exceeds `capacity`, the array reallocates (typically doubling).

### Storage Model

**Array:** Contiguous 32-bit words for sequential integer keys (1-indexed). Fast O(1) access when key is unboxed float.

**Hash:** Linked list of buckets (7 pairs max per bucket). Each bucket:
- Word 0: PairCount
- Word 1: NextBucketPtr
- Words 2+: Key/Value pairs

### Construction
`__builtin_table_new` allocates 4 words, zero-initializes header, tags with `BOXED_TABLE`.

---

## 3. AST Node Types & Code Generation

### Node Types (from `enums.h`)
Control flow: `WHILE`, `FOR_NUMERIC`, `BREAK`, `IF`, `FUNCTION_DEF`, `FUNCTION_CALL`, `RETURN`, `MULTIPLE_ASSIGNMENT`
Operators: `ADD`, `SUB`, `MUL`, `DIV`, `MOD`, `AND`, `OR`, `RELATIONAL`, `UNARY`, `CONCAT`
Literals: `STRING`, `BOOLEAN`, `NIL`, `NUMBER`, `IDENTIFIER`
Tables: `TABLE_CONSTRUCTOR`, `TABLE_SET`, `TABLE_GET`
Special: `ASM`, `RAWASM`, `COMMENT_LINE`, `COMMENT_BLOCK`, `CART_HINT`, `FUNCTION_POINTER`

### Code Generation Pattern
`generate_asm(node, dest_reg)` dispatches to type-specific handlers. The `dest_reg` parameter specifies where to place the result (0 = R0).

**Two-Operand Operations:**
```c
int left_reg = allocate_register();
int right_reg = allocate_register();
mark_register_live(left_reg, 2);
mark_register_live(right_reg, 2);
generate_asm(node->as.binary.left, left_reg);
generate_asm(node->as.binary.right, right_reg);
ensure_in_register(left_reg);
ensure_in_register(right_reg);
emit_asm("FADD R%d, R%d, R%d\n", dest_reg, left_reg, right_reg);
unlock_register(left_reg);
unlock_register(right_reg);
```

### Table Operations
**Table Set:** Try intrinsic → allocate pinned registers for table/key/value → `CALL __builtin_table_set` with 3 args on stack → clean up.

**Table Get:** Try intrinsic → allocate registers for table/key → `CALL __builtin_table_get` with 2 args → `MOV R_dest, R0`.

**Table Constructor:** `CALL __builtin_table_new` → process initializers with `__builtin_table_set`.

---

## 4. Register Allocation & Pinning

### Register Inventory
14 GPRs (R0-R13). R14=BP, R15=SP - **never modify**.

### Allocation States
- `register_inventory[]`: 0=free, 1=allocated
- `register_pinned[]`: 0=can spill, 1=must keep in register
- `register_use_distance[]`: Instructions until next use

### Allocation Algorithm (4-phase)
1. Free register
2. Dead register (use_distance == 0)
3. Spill farthest-future-use register
4. Fallback to highest-numbered

### Pinning
```c
int reg = allocate_pinned_register();  // allocates and pins
unlock_pinned_register(reg);          // unpins and unlocks
```
**Pin** registers that must survive across `generate_asm()` calls (table pointers, function pointers).

### Spilling
```c
spill_register(reg);      // Store Rn to [BP - N]
ensure_in_register(reg);  // Load from spill slot if needed
```
Spill slots are negative BP offsets: `base_spill_frame_offset - reg - 1`.

### Liveness Tracking
```c
mark_register_live(reg, 5);  // Used 5 instructions later
update_register_live(reg);   // Decrement counter each instruction
```

---

## 5. Intrinsics System

Compile-time optimizations emitting direct hardware operations.

### Categories
- **I/O Ports:** Hardware register access via `IN`/`OUT`
- **Actions:** Special operations (gamepad, etc.)
- **Calls:** `print()`, `hex()`, `spr()`, `btn()`, `add()`, math functions
- **GPU/SPU:** Direct GPU/SPU operations
- **System:** `WAIT`, `HLT`

### I/O Port Intrinsics
Maps Lua paths (e.g., `ioports.gpu.clearcolor`) to hardware ports (e.g., `GPU_ClearColor`).

**Type Casting:**
| Conversion | Instruction |
|------------|-------------|
| Float → Integer | `CFI Rn` |
| Float → Boolean | `CFB Rn` |
| Integer/Boolean → Float | `CIF Rn` |

### Example: Table Get Intrinsic
```c
int try_emit_table_get_intrinsic(ASTNode *table_expr, ASTNode *key_expr, int dest_reg) {
    // Resolve static path
    if (!resolve_static_path(table_expr, base_path)) return 0;
    if (key_expr->type != NODE_STRING) return 0;

    // Find matching port
    for (int i = 0; ioports[i].lua_path != NULL; i++) {
        if (strcmp(full_path, ioports[i].lua_path) == 0) {
            if (ioports[i].type & IOPORT_TYPE_INTEGER) {
                emit_asm("IN R%d, %s\n", dest_reg, ioports[i].asm_port);
                emit_asm("CIF R%d\n", dest_reg);  // Cast to float
            } else {
                emit_asm("IN R%d, %s\n", dest_reg, ioports[i].asm_port);
            }
            return 1;
        }
    }
    return 0;
}
```

---

## 6. Variable Storage: Global vs Local/Stack

### Symbol Table
Scoped symbol table with `SymbolNode` (name, type, location, is_function, arity) and `ScopeNode` (symbols, local_offset_counter, parent).

### Global Variables
- **Storage:** Sequential RAM addresses from `next_ram_address`
- **Access:** `[var_name]`
- **Auto-registration:** Unknown identifiers auto-registered as globals

### Local Variables
- **Storage:** Stack frame relative to BP
- **Access:** `[BP - N]` for locals (N=1,2,3...), `[BP + N]` for parameters (N=2,3...)
- **Registration:** `register_local()` or `register_parameter()`

**Access string generation:**
```c
void get_variable_access_string(const char *name, char *buf) {
    SymbolNode *sym = resolve_symbol(name);
    if (sym == NULL) sym = register_global(name);  // Auto-register

    if (sym->type == SYM_GLOBAL) {
        sprintf(buf, "[%s_%s]", sym->is_function ? "func" : "var", sym->name);
    } else if (sym->location < 0) {
        // Parameter
        sprintf(buf, "[BP + %d]", -sym->location + 1);
    } else {
        // Local
        sprintf(buf, "[BP - %d]", sym->location);
    }
}
```

---

## 7. Runtime Routines Reference

Assembly subroutines in `runtime.s` implementing Lua semantics. C calling convention: args on stack, return in R0, caller cleans stack.

### Memory Management
| Routine | Params | Returns | Purpose |
|---------|--------|---------|---------|
| `__malloc` | `[BP+2]` = size (words) | R0 = raw pointer | Allocate heap |
| `__oom_handler` | none | never | OOM trap (HLT) |

### Table Operations
| Routine | Stack Params | Returns | Purpose |
|---------|--------------|---------|---------|
| `__builtin_table_new` | none | R0 = tagged table | Create table |
| `__builtin_table_get` | `[BP+3]`=table, `[BP+2]`=key | R0 = value | Read from table |
| `__builtin_table_set` | `[BP+4]`=table, `[BP+3]`=key, `[BP+2]`=value | R0 = value | Write to table |
| `__builtin_table_len` | `[BP+2]`=table | R0 = length | Get array length |
| `__builtin_table_insert` | `[BP+4]`=table, `[BP+3]`=index, `[BP+2]`=value | R0 = value | Insert into array |

### Function Execution
| Routine | Stack Params | Returns | Purpose |
|---------|--------------|---------|---------|
| `__builtin_exec` | `[BP+2]`=function | R0 = result | Execute function |

**`__builtin_exec` implementation:**
```assembly
__builtin_exec:
    MOV R1, R0
    AND R1, BOXED_DATA
    IEQ R1, BOXED_FUNCTION
    JT  R1, __exec_valid
    JMP __runtime_error_not_callable

__exec_valid:
    AND R0, BOXED_PAYLOAD    ; Unbox
    OR  R0, V32_CART_PAGE    ; Restore page bit
    JMP R0                   ; Tail call
```

### Error Handlers
| Routine | Behavior |
|---------|----------|
| `__runtime_error_not_table` | `HLT` |
| `__runtime_error_hash_overflow` | `HLT` |
| `__runtime_error_not_callable` | Clear screen red, `HLT` |
| `__oom_handler` | `HLT` |

### Example Uses
```c
// Table construction
emit_asm("CALL __builtin_table_new\n");
emit_asm("MOV R%d, R0\n", dest_reg);

// Table access
emit_asm("PUSH R%d\n", table_reg);
emit_asm("PUSH R%d\n", key_reg);
emit_asm("CALL __builtin_table_get\n");
emit_asm("IADD SP, 2\n");
emit_asm("MOV R%d, R0\n", dest_reg);

// Function call
emit_asm("PUSH R%d\n", target_reg);
emit_asm("CALL __builtin_exec\n");
emit_asm("IADD SP, %d\n", arg_count + 1);
```

---

## 8. Common Debugging Scenarios

### Register Exhausted
**Fix:** Add `spill_register()` before complex ops, verify `unlock_register()` calls, use `mark_register_live()`.

### Table Access Returns NIL
**Fix:** Validate table tag before unboxing, check key type (NaN-boxed vs unboxed), verify array bounds.

### Hash Overflow
**Fix:** Use array indices, limit non-sequential keys (<=7 per bucket).

### Intrinsic Not Triggering
**Fix:** Check `resolve_static_path()`, verify key is `NODE_STRING`, search `ioports[]`.

### Stack Corruption
**Fix:** Count PUSH/POP, verify `IADD SP, N`, check inline ASM preserves SP/BP.

### Wrong Register Value
**Fix:** Use `mark_register_live()` + `ensure_in_register()`, add type casts.

### Function Arguments Wrong
**Fix:** Push args right-to-left, verify `IADD SP, N`, prevent register reuse.

### NaN-Boxing Confusion
**Fix:** Always `AND Rn, BOXED_PAYLOAD` before dereferencing, validate tags first.

---

## 9. Memory Layout Quick Reference

### NaN-Boxed Format
```
32-bit Float:
  31      22 21       0
  +--------+----------+
  | Cat(1) | Type(1) | Payload(21b) |
  +--------+----------+
```

### Table Layout
```
Header (16B):
+-----------+-----------+-----------+-----------+
| flags     | length    | array_ptr | hash_ptr  |
+-----------+-----------+-----------+-----------+

Array (contiguous):
+-----------+-----------+-----------+-----------+
| value_1   | value_2   | value_3   | ...       |
+-----------+-----------+-----------+-----------+

Hash (linked buckets):
+-----------+-----------+-----------+-----------+
| count     | next_ptr  | key0      | val0      |
+-----------+-----------+-----------+-----------+
```

### Stack Frame
```
High Address:
+-----------+  <- SP
| Arg N     |
| ...       |
| Arg 1     |
+-----------+  <- BP
| Saved R13 |
| Saved R12 |
| ...       |
| Local 1   |  <- BP - N
+-----------+
| Param 1   |  <- BP + 2
| Param 2   |  <- BP + 3
+-----------+
Low Address:
```

### Debug Commands
```assembly
; Unbox and dump table header
AND  R0, BOXED_PAYLOAD
MOV  R1, [R0]    ; flags
MOV  R2, [R0+1]  ; length
MOV  R3, [R0+2]  ; array_ptr
MOV  R4, [R0+3]  ; hash_ptr

; Validate table
AND  R5, R0, BOXED_DATA
IEQ  R5, BOXED_TABLE

; Extract capacity
MOV  R6, R1
AND  R6, TABLE_ARRAYSIZE
```

---

## Appendix: Key Constants

```c
#define V32_CART_PAGE   0x20000000
#define NAN_VALUE       0x7F800000
#define BOXED_CATEGORY  0x80000000
#define BOXED_TYPE      0x00400000
#define BOXED_DATA      0xFFC00000
#define BOXED_FUNCTION  0x7F800000
#define BOXED_ROMSTRING 0x7FC00000
#define BOXED_TABLE     0xFF800000
#define BOXED_RAMSTRING 0xFFC00000
#define BOXED_NIL       0xFFC00000
#define BOXED_FALSE     0xFFC00001
#define BOXED_TRUE      0xFFC00002
#define BOXED_TOMBSTONE 0xFFC00003
#define BOXED_PAYLOAD   0x003FFFFF
#define TABLE_ARRAYSIZE 0x0000FFFF
```

---

*Document version: 1.0 | Last updated: August 4, 2026 | Compiler: 20260804-dev*
