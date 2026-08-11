--@ Vircon32 Lua table.sort() Unit Test
--@ Tests ONLY the table.sort() library function.
--@ Results stored in global variables for automated memory scraping.

function test_table_sort()
    -- === Test 1: Basic numeric sort ===
    local t1 = {3, 1, 4, 2, 5}
    table.sort(t1)
    number_result1 = t1[1]  -- Expected: 1
    number_result2 = t1[3]  -- Expected: 3
    number_result3 = t1[5]  -- Expected: 5

    -- === Test 2: String sort ===
    local t2 = {"z", "a", "m", "b"}
    table.sort(t2)
    string_result1 = t2[1]  -- Expected: "a"
    string_result2 = t2[2]  -- Expected: "b"
    string_result3 = t2[4]  -- Expected: "z"

    -- === Test 3: Single element ===
    local t3 = {42}
    table.sort(t3)
    number_result4 = t3[1]  -- Expected: 42

    -- === Test 4: Empty table ===
    local t4 = {}
    table.sort(t4)
    number_result5 = #t4  -- Expected: 0

    -- === Test 5: Already sorted ===
    local t5 = {1, 2, 3, 4}
    table.sort(t5)
    number_result6 = t5[1]  -- Expected: 1
    number_result7 = t5[4]  -- Expected: 4

    -- === Test 6: Reverse sorted ===
    local t6 = {5, 4, 3, 2, 1}
    table.sort(t6)
    number_result8 = t6[1]  -- Expected: 1
    number_result9 = t6[5]  -- Expected: 5
end

function main()
    ioports.gpu.clear("black")
    test_table_sort()

    print(100, 00,  "--- table.sort() Test ---")
    print(100, 20,  "Test 1 - First: " .. number_result1)
    print(100, 40,  "Test 1 - Middle: " .. number_result2)
    print(100, 60,  "Test 1 - Last: " .. number_result3)
    print(100, 80,  "Test 2 - First str: " .. string_result1)
    print(100, 100, "Test 2 - Second str: " .. string_result2)
    print(100, 120, "Test 2 - Last str: " .. string_result3)
    print(100, 140, "Test 3 - Single: " .. number_result4)
    print(100, 160, "Test 4 - Empty len: " .. number_result5)
    print(100, 180, "Test 5 - Sorted[1]: " .. number_result6)
    print(100, 200, "Test 5 - Sorted[4]: " .. number_result7)
    print(100, 220, "Test 6 - Rev[1]: " .. number_result8)
    print(100, 240, "Test 6 - Rev[5]: " .. number_result9)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
number_result1: 1
number_result2: 3
number_result3: 5
string_result1: "a"
string_result2: "b"
string_result3: "z"
number_result4: 42
number_result5: 0
number_result6: 1
number_result7: 4
number_result8: 1
number_result9: 5
]]
