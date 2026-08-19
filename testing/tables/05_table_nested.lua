--@ Vircon32 Lua Nested Table Unit Test
--@ Tests nested table READ and WRITE access through chained dot/bracket
--@ indexing, including creating and mutating tables several levels deep.
--@ Results stored in global variables for automated memory scraping.

function test_table_nested()
    -- === Test 1: Nested write through an existing structure ===
    local t1 = {inner = {value = 1}}
    t1.inner.value = 42
    number_result1 = t1.inner.value  -- Expected: 42
    __rawasm__("__debug1:")

    -- === Test 2: Three levels deep, read and write ===
    local t2 = {a = {b = {c = 1}}}
    t2.a.b.c = 99
    number_result2 = t2.a.b.c  -- Expected: 99
    __rawasm__("__debug2:")

    -- === Test 3: Adding a brand new nested table at runtime ===
    local t3 = {}
    t3.child = {}
    t3.child.value = 7
    number_result3 = t3.child.value  -- Expected: 7
    __rawasm__("__debug3:")

    -- === Test 4: Mixed bracket and dot syntax on the same path ===
    local t4 = {list = {10, 20, 30}}
    t4["list"][2] = 200
    number_result4 = t4.list[2]  -- Expected: 200
    __rawasm__("__debug4:")

    -- === Test 5: Nested array of tables ===
    local t5 = {{x = 1}, {x = 2}, {x = 3}}
    t5[2].x = 222
    number_result5 = t5[1].x  -- Expected: 1 (unaffected)
    number_result6 = t5[2].x  -- Expected: 222
    number_result7 = t5[3].x  -- Expected: 3 (unaffected)
    __rawasm__("__debug5:")

    -- === Test 6: Writing to a freshly nested table doesn't disturb siblings ===
    local t6 = {a = {value = 1}, b = {value = 2}}
    t6.a.value = 100
    number_result8 = t6.a.value  -- Expected: 100
    number_result9 = t6.b.value  -- Expected: 2 (unaffected)
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_table_nested()

    print(100, 00,  "--- Nested Table Test ---")
    print(100, 20,  "Test 1 - Write+read: " .. number_result1)
    print(100, 40,  "Test 2 - Three deep: " .. number_result2)
    print(100, 60,  "Test 3 - New nested: " .. number_result3)
    print(100, 80,  "Test 4 - Mixed syntax: " .. number_result4)
    print(100, 100, "Test 5 - t5[1].x: " .. number_result5)
    print(100, 120, "Test 5 - t5[2].x: " .. number_result6)
    print(100, 140, "Test 5 - t5[3].x: " .. number_result7)
    print(100, 160, "Test 6 - t6.a.value: " .. number_result8)
    print(100, 180, "Test 6 - t6.b.value: " .. number_result9)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 42.0000
number_result2: 99.0000
number_result3: 7.0000
number_result4: 200.0000
number_result5: 1.0000
number_result6: 222.0000
number_result7: 3.0000
number_result8: 100.0000
number_result9: 2.0000
]]
