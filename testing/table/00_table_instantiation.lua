--#title "v32lua table instantiation unit test"
--@ Vircon32 Lua Table Instantiation Unit Test
--@ Tests ONLY table creation and initialization syntax.
--@ Results are stored in global variables for automated memory scraping.

function test_table_instantiation()
    -- === Test 1: Empty table creation ===
    local t1 = {}
    t1[1] = "first"
    t1[2] = "second"
    number_result1 = #t1  -- Expected: 2 (array length)
    string_result1 = t1[1]  -- Expected: "first"
    string_result2 = t1[2]  -- Expected: "second"

    -- === Test 2: Table with initial array values ===
    local t2 = {"alpha", "beta", "gamma"}
    number_result2 = #t2  -- Expected: 3
    string_result3 = t2[1]  -- Expected: "alpha"
    string_result4 = t2[3]  -- Expected: "gamma"

    -- === Test 3: Table with string keys (hash part) ===
    local t3 = {name = "test", value = 123}
    string_result5 = t3.name  -- Expected: "test"
    number_result3 = t3.value  -- Expected: 123
    boolean_result1 = (t3.name == "test")  -- Expected: true

    -- === Test 4: Mixed table (array + hash) ===
    local t4 = {"arr1", "arr2", key1 = "hash1"}
    number_result4 = #t4  -- Expected: 2 (array part only)
    string_result6 = t4[1]  -- Expected: "arr1"
    string_result7 = t4.key1  -- Expected: "hash1"

    -- === Test 5: Nested table access ===
    local t5 = {inner = {x = 10, y = 20}}
    number_result5 = t5.inner.x  -- Expected: 10
    number_result6 = t5.inner.y  -- Expected: 20

    -- === Test 6: Zero/negative indices (hash fallback) ===
    local t6 = {}
    t6[0] = "zero"
    t6[-1] = "negative"
    string_result8 = t6[0]  -- Expected: "zero"
    string_result9 = t6[-1]  -- Expected: "negative"
    number_result7 = #t6  -- Expected: 0 (no positive integer keys)
end

function main()
    ioports.gpu.clear("black")
    test_table_instantiation()

    -- On-screen display for manual verification
    print(100, 00,  "--- Table Instantiation Test ---")
    print(100, 20,  "Test 1 - Array length: " ..    number_result1)
    print(100, 40,  "Test 1 - Value[1]: " ..        string_result1)
    print(100, 60,  "Test 1 - Value[2]: " ..        string_result2)
    print(100, 80,  "Test 2 - Array length: " ..    number_result2)
    print(100, 100, "Test 2 - Value[1]: " ..        string_result3)
    print(100, 120, "Test 2 - Value[3]: " ..        string_result4)
    print(100, 140, "Test 3 - Hash name: " ..       string_result5)
    print(100, 160, "Test 3 - Hash value: " ..      number_result3)
    print(100, 180, "Test 3 - Boolean check: " ..   tostring(boolean_result1))
    print(100, 200, "Test 4 - Mixed array len: " .. number_result4)
    print(100, 220, "Test 4 - Array val: " ..       string_result6)
    print(100, 240, "Test 4 - Hash val: " ..        string_result7)
    print(100, 260, "Test 5 - Nested x: " ..        number_result5)
    print(100, 280, "Test 5 - Nested y: " ..        number_result6)
    print(100, 300, "Test 6 - Zero index: " ..      string_result8)
    print(100, 320, "Test 6 - Negative index: " ..  string_result9)
    print(100, 340, "Test 6 - Array length: " ..    number_result7)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:

number_result1: 2
string_result1: "first"
string_result2: "second"
number_result2: 3
string_result3: "alpha"
string_result4: "gamma"
string_result5: "test"
number_result3: 123
boolean_result1: true
number_result4: 2
string_result6: "arr1"
string_result7: "hash1"
number_result5: 10
number_result6: 20
string_result8: "zero"
string_result9: "negative"
number_result7: 0

--]]
