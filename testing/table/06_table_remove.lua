--@ Vircon32 Lua table.remove() Unit Test
--@ Tests ONLY the table.remove() library function.
--@ Results stored in global variables for automated memory scraping.

function test_table_remove()
    -- === Test 1: Remove from end (default) ===
    local t1 = {"a", "b", "c"}
    local removed = table.remove(t1)
    string_result1 = removed  -- Expected: "c"
    number_result1 = #t1     -- Expected: 2
    string_result2 = t1[2]   -- Expected: "b"

    -- === Test 2: Remove from position 1 ===
    local t2 = {"a", "b", "c"}
    local removed2 = table.remove(t2, 1)
    string_result3 = removed2  -- Expected: "a"
    string_result4 = t2[1]     -- Expected: "b" (shifted)
    number_result2 = #t2      -- Expected: 2

    -- === Test 3: Remove from middle ===
    local t3 = {"a", "b", "c"}
    local removed3 = table.remove(t3, 2)
    string_result5 = removed3  -- Expected: "b"
    string_result6 = t3[2]     -- Expected: "c" (shifted)
    number_result3 = #t3      -- Expected: 2

    -- === Test 4: Remove from single-element table ===
    local t4 = {"only"}
    local removed4 = table.remove(t4)
    string_result7 = removed4  -- Expected: "only"
    number_result4 = #t4      -- Expected: 0

    -- === Test 5: Remove with negative position ===
    local t5 = {"a", "b", "c"}
    local removed5 = table.remove(t5, -1)  -- Remove last
    string_result8 = removed5  -- Expected: "c"
    number_result5 = #t5      -- Expected: 2
end

function main()
    ioports.gpu.clear("black")
    test_table_remove()

    print(100, 00,  "--- table.remove() Test ---")
    print(100, 20,  "Test 1 - Removed: " .. string_result1)
    print(100, 40,  "Test 1 - New length: " .. number_result1)
    print(100, 60,  "Test 1 - Last elem: " .. string_result2)
    print(100, 80,  "Test 2 - Removed: " .. string_result3)
    print(100, 100, "Test 2 - Shifted: " .. string_result4)
    print(100, 120, "Test 2 - Length: " .. number_result2)
    print(100, 140, "Test 3 - Removed: " .. string_result5)
    print(100, 160, "Test 3 - Shifted: " .. string_result6)
    print(100, 180, "Test 3 - Length: " .. number_result3)
    print(100, 200, "Test 4 - Removed: " .. string_result7)
    print(100, 220, "Test 4 - Length: " .. number_result4)
    print(100, 240, "Test 5 - Neg pos: " .. string_result8)
    print(100, 260, "Test 5 - Length: " .. number_result5)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
string_result1: "c"
number_result1: 2
string_result2: "b"
string_result3: "a"
string_result4: "b"
number_result2: 2
string_result5: "b"
string_result6: "c"
number_result3: 2
string_result7: "only"
number_result4: 0
string_result8: "c"
number_result5: 2
]]
