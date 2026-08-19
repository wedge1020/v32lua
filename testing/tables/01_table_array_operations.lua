--#title "v32lua table array operations unit test"
--@ Vircon32 Lua Table Array Operations Unit Test
--@ Tests ONLY array part operations (integer keys >= 1).
--@ Results stored in global variables for automated memory scraping.

function test_table_array_operations()
    -- === Test 1: Sequential integer indexing ===
    local t1 = {}
    t1[1] = 100
    t1[2] = 200
    t1[3] = 300
    number_result1 = t1[1]  -- Expected: 100
    number_result2 = t1[2]  -- Expected: 200
    number_result3 = t1[3]  -- Expected: 300
    number_result4 = #t1    -- Expected: 3
    __rawasm__("__debug1:")

    -- === Test 2: Length operator with gaps ===
    local t2 = {}
    t2[1] = "a"
    t2[2] = "b"
    t2[4] = "d"  -- Gap at index 3
    number_result5 = #t2    -- Expected: 2 (stops at first nil)
    __rawasm__("__debug2:")

    -- === Test 3: Appending via length+1 ===
    local t3 = {"x", "y"}
    t3[#t3 + 1] = "z"
    string_result1 = t3[3]  -- Expected: "z"
    number_result6 = #t3    -- Expected: 3
    __rawasm__("__debug3:")

    -- === Test 4: Array bounds checking ===
    local t4 = {"only"}
    string_result2 = t4[1]  -- Expected: "only"
    string_result3 = t4[2] or "nil"  -- Expected: "nil"
    __rawasm__("__debug4:")

    -- === Test 5: Large array ===
    local t5 = {}
    for i = 1, 10 do t5[i] = i * 10 end
    number_result7 = t5[5]  -- Expected: 50
    number_result8 = #t5    -- Expected: 10
    __rawasm__("__debug5:")
end

function main()
    ioports.gpu.clear("black")
    test_table_array_operations()

    print(100, 00,  "--- Table Array Operations Test ---")
    print(100, 20,  "Test 1 - Index[1]: " .. number_result1)
    print(100, 40,  "Test 1 - Index[2]: " .. number_result2)
    print(100, 60,  "Test 1 - Index[3]: " .. number_result3)
    print(100, 80,  "Test 1 - Length: " .. number_result4)
    print(100, 100, "Test 2 - Length (gap): " .. number_result5)
    print(100, 120, "Test 3 - Appended val: " .. string_result1)
    print(100, 140, "Test 3 - New length: " .. number_result6)
    print(100, 160, "Test 4 - First val: " .. string_result2)
    print(100, 180, "Test 4 - OOB val: " .. string_result3)
    print(100, 200, "Test 5 - Mid val: " .. number_result7)
    print(100, 220, "Test 5 - Length: " .. number_result8)
end

--[[

=== EXPECTED OUTPUT ===
number_result1: 100.0000
number_result2: 200.0000
number_result3: 300.0000
number_result4: 3.0000
number_result5: 2.0000
string_result1: "z"
number_result6: 3.0000
string_result2: "only"
string_result3: "nil"
number_result7: 50.0000
number_result8: 10.0000

--]]
