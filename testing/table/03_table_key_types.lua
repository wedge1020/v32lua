--@ Vircon32 Lua Table Key Type Distinction Unit Test
--@ Tests that numeric keys and their string-representation keys are
--@ DIFFERENT keys -- t[1] and t["1"] must not collide, matching real
--@ Lua's lack of implicit key coercion.
--@ Results stored in global variables for automated memory scraping.

function test_table_key_types()
    -- === Test 1: t[1] and t["1"] are different keys ===
    local t1 = {}
    t1[1] = "numeric_one"
    t1["1"] = "string_one"
    string_result1 = t1[1]    -- Expected: "numeric_one"
    string_result2 = t1["1"]  -- Expected: "string_one"
    __rawasm__("__debug1:")

    -- === Test 2: Setting the string key first, then the numeric key ===
    local t2 = {}
    t2["2"] = "string_two"
    t2[2] = "numeric_two"
    string_result3 = t2["2"]  -- Expected: "string_two"
    string_result4 = t2[2]    -- Expected: "numeric_two"
    __rawasm__("__debug2:")

    -- === Test 3: A string key that looks numeric doesn't count toward # ===
    local t3 = {}
    t3[1] = "a"
    t3[2] = "b"
    t3["3"] = "c"  -- string key "3", NOT array index 3
    number_result1 = #t3  -- Expected: 2 (the string key "3" doesn't extend the array part)
    __rawasm__("__debug3:")

    -- === Test 4: Zero and its string form are also distinct keys ===
    local t4 = {}
    t4[0] = "numeric_zero"
    t4["0"] = "string_zero"
    string_result5 = t4[0]    -- Expected: "numeric_zero"
    string_result6 = t4["0"]  -- Expected: "string_zero"
    __rawasm__("__debug4:")

    -- === Test 5: A float key with an integral value and its int-looking string form ===
    local t5 = {}
    t5[5] = "int_five"
    t5["5.0"] = "string_five_point_zero"
    string_result7 = t5[5]        -- Expected: "int_five"
    string_result8 = t5["5.0"]    -- Expected: "string_five_point_zero"
    __rawasm__("__debug5:")
end

function main()
    ioports.gpu.clear("black")
    test_table_key_types()

    print(100, 00,  "--- Table Key Type Distinction Test ---")
    print(100, 20,  "Test 1 - t[1]: " .. string_result1)
    print(100, 40,  "Test 1 - t['1']: " .. string_result2)
    print(100, 60,  "Test 2 - t['2']: " .. string_result3)
    print(100, 80,  "Test 2 - t[2]: " .. string_result4)
    print(100, 100, "Test 3 - Length: " .. number_result1)
    print(100, 120, "Test 4 - t[0]: " .. string_result5)
    print(100, 140, "Test 4 - t['0']: " .. string_result6)
    print(100, 160, "Test 5 - t[5]: " .. string_result7)
    print(100, 180, "Test 5 - t['5.0']: " .. string_result8)
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "numeric_one"
string_result2: "string_one"
string_result3: "string_two"
string_result4: "numeric_two"
number_result1: 2.0000
string_result5: "numeric_zero"
string_result6: "string_zero"
string_result7: "int_five"
string_result8: "string_five_point_zero"
]]
