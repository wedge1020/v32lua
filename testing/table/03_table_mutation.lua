--@ Vircon32 Lua Table Mutation Unit Test
--@ Tests ONLY table value modification and deletion.
--@ Results stored in global variables for automated memory scraping.

function test_table_mutation()
    -- === Test 1: Overwriting array values ===
    local t1 = {"old1", "old2", "old3"}
    t1[1] = "new1"
    t1[2] = "new2"
    string_result1 = t1[1]  -- Expected: "new1"
    string_result2 = t1[2]  -- Expected: "new2"
    string_result3 = t1[3]  -- Expected: "old3" (unchanged)

    -- === Test 2: Overwriting hash values ===
    local t2 = {name = "old_name", value = 0}
    t2.name = "new_name"
    t2.value = 42
    string_result4 = t2.name  -- Expected: "new_name"
    number_result1 = t2.value  -- Expected: 42

    -- === Test 3: Adding new keys ===
    local t3 = {a = 1}
    t3.b = 2
    t3[1] = "array"
    number_result2 = t3.a  -- Expected: 1
    number_result3 = t3.b  -- Expected: 2
    string_result5 = t3[1]  -- Expected: "array"

    -- === Test 4: Deleting keys (setting to nil) ===
    local t4 = {x = 10, y = 20, z = 30}
    t4.y = nil
    number_result4 = t4.x  -- Expected: 10
    boolean_result1 = (t4.y == nil)  -- Expected: true
    number_result5 = t4.z  -- Expected: 30

    -- === Test 5: Clearing and reusing table ===
    local t5 = {1, 2, 3}
    t5[1] = nil
    t5[2] = nil
    t5[3] = nil
    t5.new = "fresh"
    string_result6 = t5.new  -- Expected: "fresh"
    number_result6 = #t5    -- Expected: 0
end

function main()
    ioports.gpu.clear("black")
    test_table_mutation()

    print(100, 00,  "--- Table Mutation Test ---")
    print(100, 20,  "Test 1 - Overwrite[1]: " .. string_result1)
    print(100, 40,  "Test 1 - Overwrite[2]: " .. string_result2)
    print(100, 60,  "Test 1 - Unchanged[3]: " .. string_result3)
    print(100, 80,  "Test 2 - Hash name: " .. string_result4)
    print(100, 100, "Test 2 - Hash value: " .. number_result1)
    print(100, 120, "Test 3 - Key a: " .. number_result2)
    print(100, 140, "Test 3 - Key b: " .. number_result3)
    print(100, 160, "Test 3 - Array[1]: " .. string_result5)
    print(100, 180, "Test 4 - x: " .. number_result4)
    print(100, 200, "Test 4 - y==nil: " .. tostring(boolean_result1))
    print(100, 220, "Test 4 - z: " .. number_result5)
    print(100, 240, "Test 5 - new key: " .. string_result6)
    print(100, 260, "Test 5 - length: " .. number_result6)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
string_result1: "new1"
string_result2: "new2"
string_result3: "old3"
string_result4: "new_name"
number_result1: 42
number_result2: 1
number_result3: 2
string_result5: "array"
number_result4: 10
boolean_result1: true
number_result5: 30
string_result6: "fresh"
number_result6: 0
]]
