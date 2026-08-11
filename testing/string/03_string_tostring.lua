--@ Vircon32 Lua tostring() Unit Test
--@ Tests ONLY tostring() function (uses __builtin_tostring).
--@ Results stored in global variables for automated memory scraping.

function test_tostring()
    -- === Test 1: tostring(nil) ===
    string_result1 = tostring(nil)  -- Expected: "nil"

    -- === Test 2: tostring(true/false) ===
    string_result2 = tostring(true)  -- Expected: "true"
    string_result3 = tostring(false)  -- Expected: "false"

    -- === Test 3: tostring(numbers) ===
    string_result4 = tostring(42)  -- Expected: "42"
    string_result5 = tostring(3.14)  -- Expected: "3.14" (or similar float repr)

    -- === Test 4: tostring(string) - passthrough ===
    string_result6 = tostring("already a string")  -- Expected: "already a string"

    -- === Test 5: tostring(table) ===
    local t = {x = 1, y = 2}
    string_result7 = tostring(t)  -- Expected: "table" (address or type name)

    -- === Test 6: tostring(function) ===
    local func = function() end
    string_result8 = tostring(func)  -- Expected: "function" (address or type name)

    -- === Test 7: Concatenation with tostring results ===
    string_result9 = tostring(123) .. tostring(456)  -- Expected: "123456"
end

function main()
    ioports.gpu.clear("black")
    test_tostring()

    print(100, 00,  "--- tostring Test ---")
    print(100, 20,  "tostring(nil): " .. string_result1)
    print(100, 40,  "tostring(true): " .. string_result2)
    print(100, 60,  "tostring(false): " .. string_result3)
    print(100, 80,  "tostring(42): " .. string_result4)
    print(100, 100, "tostring(3.14): " .. string_result5)
    print(100, 120, "tostring(str): " .. string_result6)
    print(100, 140, "tostring(table): " .. string_result7)
    print(100, 160, "tostring(func): " .. string_result8)
    print(100, 180, "concat tostring: " .. string_result9)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
string_result1: "nil"
string_result2: "true"
string_result3: "false"
string_result4: "42"
string_result5: "3.14" (or similar)
string_result6: "already a string"
string_result7: "table" (or address)
string_result8: "function" (or address)
string_result9: "123456"
]]
