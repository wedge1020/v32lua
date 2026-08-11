--@ Vircon32 Lua table.unpack() Unit Test
--@ Tests ONLY the table.unpack() library function.
--@ Results stored in global variables for automated memory scraping.

function test_table_unpack()
    -- === Test 1: Unpack full table ===
    local t1 = {"a", "b", "c"}
    local a, b, c = table.unpack(t1)
    string_result1 = a  -- Expected: "a"
    string_result2 = b  -- Expected: "b"
    string_result3 = c  -- Expected: "c"

    -- === Test 2: Unpack with start index ===
    local t2 = {"x", "y", "z"}
    local y, z = table.unpack(t2, 2)
    string_result4 = y  -- Expected: "y"
    string_result5 = z  -- Expected: "z"

    -- === Test 3: Unpack with start and end ===
    local t3 = {"a", "b", "c", "d", "e"}
    local b, c = table.unpack(t3, 2, 3)
    string_result6 = b  -- Expected: "b"
    string_result7 = c  -- Expected: "c"

    -- === Test 4: Unpack empty table ===
    local t4 = {}
    local nothing = table.unpack(t4)
    boolean_result1 = (nothing == nil)  -- Expected: true

    -- === Test 5: Unpack single element ===
    local t5 = {"only"}
    local only = table.unpack(t5)
    string_result8 = only  -- Expected: "only"

    -- === Test 6: Unpack with end < start (invalid) ===
    local t6 = {"a", "b", "c"}
    local result = table.unpack(t6, 3, 1)
    boolean_result2 = (result == nil)  -- Expected: true
end

function main()
    ioports.gpu.clear("black")
    test_table_unpack()

    print(100, 00,  "--- table.unpack() Test ---")
    print(100, 20,  "Test 1 - First: " .. string_result1)
    print(100, 40,  "Test 1 - Second: " .. string_result2)
    print(100, 60,  "Test 1 - Third: " .. string_result3)
    print(100, 80,  "Test 2 - Start[2]: " .. string_result4)
    print(100, 100, "Test 2 - Start[3]: " .. string_result5)
    print(100, 120, "Test 3 - Range[2]: " .. string_result6)
    print(100, 140, "Test 3 - Range[3]: " .. string_result7)
    print(100, 160, "Test 4 - Empty nil: " .. tostring(boolean_result1))
    print(100, 180, "Test 5 - Single: " .. string_result8)
    print(100, 200, "Test 6 - Invalid: " .. tostring(boolean_result2))
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
string_result1: "a"
string_result2: "b"
string_result3: "c"
string_result4: "y"
string_result5: "z"
string_result6: "b"
string_result7: "c"
boolean_result1: true
string_result8: "only"
boolean_result2: true
]]
