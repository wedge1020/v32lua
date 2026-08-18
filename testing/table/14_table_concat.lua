--@ Vircon32 Lua table.concat() Unit Test
--@ Tests ONLY the table.concat() library function.
--@ Results stored in global variables for automated memory scraping.

function test_table_concat()
    -- === Test 1: Basic concatenation ===
    local t1 = {"a", "b", "c"}
    string_result1 = table.concat(t1)  -- Expected: "abc"

    -- === Test 2: With separator ===
    local t2 = {"a", "b", "c"}
    string_result2 = table.concat(t2, "-")  -- Expected: "a-b-c"

    -- === Test 3: With start index ===
    local t3 = {"a", "b", "c", "d"}
    string_result3 = table.concat(t3, "", 2)  -- Expected: "bcd"

    -- === Test 4: With end index ===
    local t4 = {"a", "b", "c", "d"}
    string_result4 = table.concat(t4, "", 1, 2)  -- Expected: "ab"

    -- === Test 5: Empty table ===
    local t5 = {}
    string_result5 = table.concat(t5)  -- Expected: ""

    -- === Test 6: Single element ===
    local t6 = {"only"}
    string_result6 = table.concat(t6)  -- Expected: "only"

    -- === Test 7: Mixed types (numbers coerced to strings) ===
    local t7 = {"a", 1, "b", 2}
    string_result7 = table.concat(t7)  -- Expected: "a1b2"
end

function main()
    ioports.gpu.clear("black")
    test_table_concat()

    print(100, 00,  "--- table.concat() Test ---")
    print(100, 20,  "Test 1 - Basic: " .. string_result1)
    print(100, 40,  "Test 2 - Separator: " .. string_result2)
    print(100, 60,  "Test 3 - Start idx: " .. string_result3)
    print(100, 80,  "Test 4 - End idx: " .. string_result4)
    print(100, 100, "Test 5 - Empty: '" .. string_result5 .. "'")
    print(100, 120, "Test 6 - Single: " .. string_result6)
    print(100, 140, "Test 7 - Mixed: " .. string_result7)
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "abc"
string_result2: "a-b-c"
string_result3: "bcd"
string_result4: "ab"
string_result5: ""
string_result6: "only"
string_result7: "a1b2"
]]
