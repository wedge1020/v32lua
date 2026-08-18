--@ Vircon32 Lua Table Aliasing Unit Test
--@ Tests that tables are reference types: assignment, function
--@ parameters, and function returns all share the same underlying table
--@ rather than copying it.
--@ Results stored in global variables for automated memory scraping.

-- Helper: mutates a table passed by reference
function set_field(t, key, value)
    t[key] = value
end

-- Helper: appends to the array part of a passed-in table
function push_value(t, value)
    t[#t + 1] = value
end

-- Helper: returns the same table it was given (identity passthrough)
function identity(t)
    return t
end

-- Helper: builds and returns a fresh table
function make_counter()
    local t = {count = 0}
    return t
end

function test_table_aliasing()
    -- === Test 1: Plain assignment shares the same table ===
    local t1 = {value = 1}
    local t2 = t1
    t2.value = 99
    number_result1 = t1.value  -- Expected: 99 (t1 sees t2's mutation)
    __rawasm__("__debug1:")

    -- === Test 2: Mutating a table through a function parameter ===
    local t3 = {value = 1}
    set_field(t3, "value", 42)
    number_result2 = t3.value  -- Expected: 42
    __rawasm__("__debug2:")

    -- === Test 3: Appending to a table's array part through a function ===
    local t4 = {"a", "b"}
    push_value(t4, "c")
    number_result3 = #t4    -- Expected: 3
    string_result1 = t4[3]  -- Expected: "c"
    __rawasm__("__debug3:")

    -- === Test 4: A function returning the same table it received ===
    local t5 = {value = 7}
    local t6 = identity(t5)
    t6.value = 8
    number_result4 = t5.value  -- Expected: 8 (t5 and t6 are the same table)
    __rawasm__("__debug4:")

    -- === Test 5: Two locals pointing at a freshly-created table ===
    local t7 = make_counter()
    local t8 = t7
    t8.count = t8.count + 1
    t8.count = t8.count + 1
    number_result5 = t7.count  -- Expected: 2
    __rawasm__("__debug5:")

    -- === Test 6: A table nested inside another table is still shared ===
    local outer = {inner = {value = 1}}
    local inner_ref = outer.inner
    inner_ref.value = 55
    number_result6 = outer.inner.value  -- Expected: 55
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_table_aliasing()

    print(100, 00,  "--- Table Aliasing Test ---")
    print(100, 20,  "Test 1 - Shared assign: " .. number_result1)
    print(100, 40,  "Test 2 - Fn param mutate: " .. number_result2)
    print(100, 60,  "Test 3 - Fn param length: " .. number_result3)
    print(100, 80,  "Test 3 - Fn param val: " .. string_result1)
    print(100, 100, "Test 4 - Return identity: " .. number_result4)
    print(100, 120, "Test 5 - Shared counter: " .. number_result5)
    print(100, 140, "Test 6 - Nested shared: " .. number_result6)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 99.0000
number_result2: 42.0000
number_result3: 3.0000
string_result1: "c"
number_result4: 8.0000
number_result5: 2.0000
number_result6: 55.0000
]]
