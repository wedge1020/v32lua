--@ Vircon32 Lua table.insert() Unit Test
--@ Tests ONLY the table.insert() library function.
--@ Results stored in global variables for automated memory scraping.

function test_table_insert()
    -- === Test 1: Insert at end (default) ===
    local t1 = {"a", "b"}
    table.insert(t1, "c")
    string_result1 = t1[3]  -- Expected: "c"
    number_result1 = #t1    -- Expected: 3
    __rawasm__("__debug1:")

    -- === Test 2: Insert at position 1 ===
    local t2 = {"b", "c"}
    table.insert(t2, 1, "a")
    string_result2 = t2[1]  -- Expected: "a"
    string_result3 = t2[3]  -- Expected: "c" (shifted)
    number_result2 = #t2    -- Expected: 3
    __rawasm__("__debug2:")

    -- === Test 3: Insert in middle ===
    local t3 = {"a", "c"}
    table.insert(t3, 2, "b")
    string_result4 = t3[2]  -- Expected: "b"
    number_result3 = #t3    -- Expected: 3
    __rawasm__("__debug3:")

    -- === Test 4: Insert into empty table ===
    local t4 = {}
    table.insert(t4, "only")
    string_result5 = t4[1]  -- Expected: "only"
    number_result4 = #t4    -- Expected: 1
    __rawasm__("__debug4:")

    -- === Test 5: Insert with negative position (from end) ===
    local t5 = {"a", "b", "c"}
    table.insert(t5, -1, "x")  -- Before last element
    string_result6 = t5[3]  -- Expected: "x"
    string_result7 = t5[4]  -- Expected: "c"
    number_result5 = #t5    -- Expected: 4
    __rawasm__("__debug5:")
end

function main()
    ioports.gpu.clear("black")
    test_table_insert()

    print(100, 00,  "--- table.insert() Test ---")
    print(100, 20,  "Test 1 - End insert: " .. string_result1)
    print(100, 40,  "Test 1 - New length: " .. number_result1)
    print(100, 60,  "Test 2 - Pos 1: " .. string_result2)
    print(100, 80,  "Test 2 - Shifted: " .. string_result3)
    print(100, 100, "Test 2 - Length: " .. number_result2)
    print(100, 120, "Test 3 - Middle: " .. string_result4)
    print(100, 140, "Test 3 - Length: " .. number_result3)
    print(100, 160, "Test 4 - Empty: " .. string_result5)
    print(100, 180, "Test 4 - Length: " .. number_result4)
    print(100, 200, "Test 5 - Neg pos: " .. string_result6)
    print(100, 220, "Test 5 - Shifted: " .. string_result7)
    print(100, 240, "Test 5 - Length: " .. number_result5)
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "c"
number_result1: 3.0000
string_result2: "a"
string_result3: "c"
number_result2: 3.0000
string_result4: "b"
number_result3: 3.0000
string_result5: "only"
number_result4: 1.0000
string_result6: "x"
string_result7: "c"
number_result5: 4.0000
]]
