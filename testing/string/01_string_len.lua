--@ Vircon32 Lua string.len() Unit Test
--@ Tests ONLY string length operations.
--@ Results stored in global variables for automated memory scraping.

function test_string_len()
    -- === Test 1: Empty string ===
    number_result1 = string.len("")  -- Expected: 0

    -- === Test 2: Single character ===
    number_result2 = string.len("X")  -- Expected: 1

    -- === Test 3: Normal string ===
    number_result3 = string.len("Hello")  -- Expected: 5

    -- === Test 4: String with spaces ===
    number_result4 = string.len("Hello World")  -- Expected: 11

    -- === Test 5: Unicode-like (ASCII only in Vircon32) ===
    number_result5 = string.len("ABC123!@#")  -- Expected: 9

    -- === Test 6: Length operator # ===
    number_result6 = #"Test"  -- Expected: 4

    -- === Test 7: Length of concatenated string ===
    local s = "Part1" .. "Part2"
    number_result7 = #s  -- Expected: 10

    -- === Test 8: Length of string.char result ===
    local cs = string.char(65, 66, 67)
    number_result8 = #cs  -- Expected: 3
end

function main()
    ioports.gpu.clear("black")
    test_string_len()

    print(100, 00,  "--- string.len Test ---")
    print(100, 20,  "len(''): " .. number_result1)
    print(100, 40,  "len('X'): " .. number_result2)
    print(100, 60,  "len('Hello'): " .. number_result3)
    print(100, 80,  "len('Hello World'): " .. number_result4)
    print(100, 100, "len('ABC123!@#'): " .. number_result5)
    print(100, 120, "#'Test': " .. number_result6)
    print(100, 140, "#concat: " .. number_result7)
    print(100, 160, "#char: " .. number_result8)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
number_result1: 0
number_result2: 1
number_result3: 5
number_result4: 11
number_result5: 9
number_result6: 4
number_result7: 10
number_result8: 3
]]
