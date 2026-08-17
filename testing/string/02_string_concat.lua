--@ Vircon32 Lua String Concatenation Unit Test
--@ Tests ONLY string concatenation via .. operator (uses __builtin_strcat).
--@ Results stored in global variables for automated memory scraping.

function test_string_concat()
    -- === Test 1: Simple concatenation ===
    string_result1 = "Hello" .. "World"  -- Expected: "HelloWorld"

    -- === Test 2: With spaces ===
    string_result2 = "Hello" .. " " .. "World"  -- Expected: "Hello World"

    -- === Test 3: Empty strings ===
    string_result3 = "" .. "Test" .. ""  -- Expected: "Test"

    -- === Test 4: Number to string coercion ===
    string_result4 = "Value: " .. 42  -- Expected: "Value: 42"

    -- === Test 5: Boolean coercion ===
    string_result5 = "True: " .. true  -- Expected: "True: true"
    string_result6 = "False: " .. false  -- Expected: "False: false"

    -- === Test 6: Nil coercion ===
    string_result7 = "Nil: " .. nil  -- Expected: "Nil: nil"

    -- === Test 7: Complex concatenation ===
    local a = "A"
    local b = "B"
    local c = "C"
    string_result8 = a .. b .. c .. "D"  -- Expected: "ABCD"

    -- === Test 8: Length of concatenated result ===
    local s = "Part1" .. "Part2" .. "Part3"
    number_result1 = #s  -- Expected: 15
end

function main()
    ioports.gpu.clear("black")
    test_string_concat()

    print(100, 00,  "--- String Concat Test ---")
    print(100, 20,  "Hello..World: " .. string_result1)
    print(100, 40,  "With spaces: " .. string_result2)
    print(100, 60,  "Empty strings: " .. string_result3)
    print(100, 80,  "Num coercion: " .. string_result4)
    print(100, 100, "Bool true: " .. string_result5)
    print(100, 120, "Bool false: " .. string_result6)
    print(100, 140, "Nil coercion: " .. string_result7)
    print(100, 160, "Complex: " .. string_result8)
    print(100, 180, "Concat length: " .. number_result1)
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "HelloWorld"
string_result2: "Hello World"
string_result3: "Test"
string_result4: "Value: 42"
string_result5: "True: true"
string_result6: "False: false"
string_result7: "Nil: nil"
string_result8: "ABCD"
number_result1: 15.0000
]]
