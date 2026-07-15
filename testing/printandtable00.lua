--@ Vircon32 Lua Runtime & Table Test Suite
--@ Tests print() coordinates, to_string coercion, and table array/hash routines

-- Global helper function to test storing and calling function pointers from tables
function calculate_bonus(score, multiplier)
    return score * multiplier
end

-- --- TEST 1: Print & Type Coercion ---
function test_print_and_coercion()
    -- 1. Direct string printing at (x=10, y=10)
    print(10, 10, "--- TEST 1: Print & Coercion ---")
    
    -- 2. Automatic to_string coercion via print() for floats, booleans, and nil
    print(10, 30, 42.5)
    print(10, 50, true)
    print(10, 70, false)
    
    -- 3. Testing explicit string concatenation (..) which invokes __builtin_strcat
    local greeting = "Hello, " .. "Vircon32!"
    print(10, 90, greeting)
    
    return 0
end

-- --- TEST 2: Table Routines & Memory Paths ---
function test_table_routines()
    print(200, 10, "--- TEST 2: Table Routines ---")
    
    -- 1. Allocation: Grammar strictly requires empty constructors {}
    local t = {}
    
    -- 2. Array Fast-Path: Integer keys >= 1 (stored in contiguous heap buffer)
    t[1] = "Array Index 1"
    t[2] = 100
    print(200, 30, t[1])
    print(200, 50, t[2])
    
    -- 3. Hash Fallback: String keys and 0 / negative indices (stored in association list)
    t.name = "Hero"
    t["class"] = "Warrior"
    t[0] = "Zero Index (Hash Path)"
    print(200, 70, t.name)
    print(200, 90, t.class)
    print(200, 110, t[0])
    
    -- 4. Overwriting existing values in both storage parts
    t[1] = "Updated Index 1"
    t.name = "Legendary Hero"
    print(200, 130, t[1])
    print(200, 150, t.name)
    
    -- 5. Dynamic method lookup: Storing and executing function pointers inside tables
    t.get_bonus = calculate_bonus
    local bonus = t.get_bonus(t[2], 5)
    print(200, 170, "Bonus: " .. bonus)
    
    -- 6. Coercing a raw table pointer to string via print()
    print(200, 190, t)
    
    return 0
end

-- --- PROGRAM STARTING PLACE ---
-- Required by the compiler's __start assembly vector
function main()
    test_print_and_coercion()
    test_table_routines()
end
