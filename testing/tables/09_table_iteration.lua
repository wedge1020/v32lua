--@ Vircon32 Lua Table Iteration Unit Test
--@ Tests ONLY pairs() and ipairs() iteration over tables.
--@ Results stored in global variables for automated memory scraping.

function test_table_iteration()
    -- === Test 1: ipairs over a pure array table (order is guaranteed) ===
    local t1 = {"a", "b", "c"}
    local concat1 = ""
    __rawasm__("__debug0:")
    for i, v in ipairs(t1) do
        concat1 = concat1 .. v
    end
    string_result1 = concat1  -- Expected: "abc"
    __rawasm__("__debug1:")

    -- === Test 2: ipairs stops at the first gap (matches # semantics) ===
    local t2 = {}
    t2[1] = "x"
    t2[2] = "y"
    t2[4] = "z"  -- Gap at index 3
    local count2 = 0
    for i, v in ipairs(t2) do
        count2 = count2 + 1
    end
    number_result1 = count2  -- Expected: 2 (stops before the gap)
    __rawasm__("__debug2:")

    -- === Test 3: pairs visits every key exactly once (array + hash mixed) ===
    local t3 = {"arr1", "arr2", tag = "hashval"}
    local visit_count3 = 0
    local saw_arr1 = false
    local saw_tag = false
    for k, v in pairs(t3) do
        visit_count3 = visit_count3 + 1
        if v == "arr1" then saw_arr1 = true end
        if k == "tag" then saw_tag = true end
    end
    number_result2 = visit_count3    -- Expected: 3
    boolean_result1 = saw_arr1       -- Expected: true
    boolean_result2 = saw_tag        -- Expected: true
    __rawasm__("__debug3:")

    -- === Test 4: pairs over an empty table visits nothing ===
    local t4 = {}
    local visited4 = false
    for k, v in pairs(t4) do
        visited4 = true
    end
    boolean_result3 = visited4  -- Expected: false
    __rawasm__("__debug4:")

    -- === Test 5: break exits a pairs() loop early ===
    local t5 = {10, 20, 30, 40, 50}
    local count5 = 0
    for k, v in pairs(t5) do
        count5 = count5 + 1
        if count5 == 2 then break end
    end
    number_result3 = count5  -- Expected: 2
    __rawasm__("__debug5:")

    -- === Test 6: pairs skips a key that was deleted (set to nil) ===
    local t6 = {x = 1, y = 2, z = 3}
    t6.y = nil
    local visit_count6 = 0
    local saw_y6 = false
    for k, v in pairs(t6) do
        visit_count6 = visit_count6 + 1
        if k == "y" then saw_y6 = true end
    end
    number_result4 = visit_count6  -- Expected: 2
    boolean_result4 = saw_y6       -- Expected: false
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_table_iteration()

    print(100, 00,  "--- Table Iteration Test ---")
    print(100, 20,  "Test 1 - ipairs concat: " .. string_result1)
    print(100, 40,  "Test 2 - ipairs gap stop: " .. number_result1)
    print(100, 60,  "Test 3 - pairs count: " .. number_result2)
    print(100, 80,  "Test 3 - saw arr1: " .. tostring(boolean_result1))
    print(100, 100, "Test 3 - saw tag: " .. tostring(boolean_result2))
    print(100, 120, "Test 4 - empty visited: " .. tostring(boolean_result3))
    print(100, 140, "Test 5 - break count: " .. number_result3)
    print(100, 160, "Test 6 - count after delete: " .. number_result4)
    print(100, 180, "Test 6 - saw deleted key: " .. tostring(boolean_result4))
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "abc"
number_result1: 2.0000
number_result2: 3.0000
boolean_result1: true
boolean_result2: true
boolean_result3: false
number_result3: 2.0000
number_result4: 2.0000
boolean_result4: false
]]
