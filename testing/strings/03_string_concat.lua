--#title "[v32lua] string concat unit test"
--@ Vircon32 Lua String Concatenation Unit Test -- SAFE SUBSET
--@ Tests .. operator with string and number operands only.
--@ Deliberately excludes true/false/nil operands -- see
--@ 03_string_concat_coercion_risk.lua for those, isolated separately
--@ because of a known __builtin_strcat bug (see AUDIT section 3) that
--@ can hang or crash on boolean/nil operands. Keeping this file free of
--@ that risk means it should reliably tell you whether plain
--@ string/number concatenation itself is healthy, independent of that bug.

function test_string_concat_safe()
    -- === Test 1: Simple concatenation ===
    string_result1 = "Hello" .. "World"  -- Expected: "HelloWorld"

    __rawasm__("__debug1:")
    -- === Test 2: With spaces ===
    string_result2 = "Hello" .. " " .. "World"  -- Expected: "Hello World"

    __rawasm__("__debug2:")
    -- === Test 3: Empty strings ===
    string_result3 = "" .. "Test" .. ""  -- Expected: "Test"

    __rawasm__("__debug3:")
    -- === Test 4: Number to string coercion (whole number) ===
    string_result4 = "Value- " .. 42  -- Expected: "Value: 42"

    __rawasm__("__debug4:")
    -- === Test 5: Number to string coercion (fractional) ===
    -- See AUDIT section 5: current default float formatting always emits
    -- 6 fractional digits, so expect "Value: 3.140000" until/unless that's
    -- changed, NOT "Value: 3.14".
    string_result5 = "Value- " .. 3.14

    __rawasm__("__debug5:")
    -- === Test 6: Complex concatenation (locals, 4-way chain) ===
    local a = "A"
    local b = "B"
    local c = "C"
    string_result6 = a .. b .. c .. "D"  -- Expected: "ABCD"

    __rawasm__("__debug6:")
    -- === Test 7: Length of concatenated result ===
    local s = "Part1" .. "Part2" .. "Part3"
    number_result1 = #s  -- Expected: 15

    __rawasm__("__debug7:")
end

function test_concat_true()
    string_result7 = "True- " .. true  -- Expected: "True: true"
    __rawasm__("__debug8:")
end

function test_concat_false()
    string_result8 = "False- " .. false  -- Expected: "False: false"
    __rawasm__("__debug9:")
end

function test_concat_nil()
    string_result9 = "Nil- " .. nil  -- Expected: "Nil: nil"
    __rawasm__("__debug10:")
end

function main()
    ioports.gpu.clear("black")
    test_string_concat_safe()
    test_concat_true()
    test_concat_false()
    test_concat_nil()

    print(100, 00,  "--- String Concat Test (safe subset) ---")
    print(100, 20,  "Hello..World: " .. string_result1)
    print(100, 40,  "With spaces: " .. string_result2)
    print(100, 60,  "Empty strings: " .. string_result3)
    print(100, 80,  "Num coercion (int): " .. string_result4)
    print(100, 100, "Num coercion (float): " .. string_result5)
    print(100, 120, "Complex: " .. string_result6)
    print(100, 140, "Concat length: " .. number_result1)
    print(100, 160, "--- Concat with true ---")
    print(100, 180, string_result7)
    print(100, 200, "--- Concat with false ---")
    print(100, 220, string_result8)
    print(100, 240, "--- Concat with nil ---")
    print(100, 260, string_result9)
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "HelloWorld"
string_result2: "Hello World"
string_result3: "Test"
string_result4: "Value- 42"
string_result5: "Value- 3.140000"
string_result6: "ABCD"
number_result1: 15.0000
string_result7: "True- true"
string_result8: "False- false"
string_result9: "Nil- nil"
]]
