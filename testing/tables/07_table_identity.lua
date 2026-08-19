--@ Vircon32 Lua Table Identity/Equality Unit Test
--@ Tests that table equality (==) is reference identity, not
--@ structural/content equality -- two tables with identical contents are
--@ NOT equal unless they are the same underlying table.
--@ Results stored in global variables for automated memory scraping.

function identity(t)
    return t
end

function test_table_identity()
    -- === Test 1: Two separately-created tables with identical content are NOT equal ===
    local t1 = {value = 1}
    local t2 = {value = 1}
    boolean_result1 = (t1 == t2)  -- Expected: false
    __rawasm__("__debug1:")

    -- === Test 2: A table is equal to itself via a second reference ===
    local t3 = {value = 1}
    local t4 = t3
    boolean_result2 = (t3 == t4)  -- Expected: true
    __rawasm__("__debug2:")

    -- === Test 3: Two empty tables are NOT equal ===
    local t5 = {}
    local t6 = {}
    boolean_result3 = (t5 == t6)  -- Expected: false
    __rawasm__("__debug3:")

    -- === Test 4: A table is never equal to nil, a number, or a string ===
    local t7 = {value = 1}
    boolean_result4 = (t7 == nil)     -- Expected: false
    boolean_result5 = (t7 == 1)       -- Expected: false
    boolean_result6 = (t7 == "t7")    -- Expected: false
    __rawasm__("__debug4:")

    -- === Test 5: Identity survives a round trip through a function ===
    local t8 = {value = 1}
    local t9 = identity(t8)
    boolean_result7 = (t8 == t9)  -- Expected: true
    __rawasm__("__debug5:")

    -- === Test 6: Mutating one alias doesn't change identity comparisons ===
    local t10 = {value = 1}
    local t11 = t10
    t11.value = 999
    boolean_result8 = (t10 == t11)  -- Expected: true (still the same table)
    __rawasm__("__debug6:")

    -- === Test 7: ~= is the correct inverse of == for tables ===
    local t12 = {value = 1}
    local t13 = {value = 1}
    boolean_result9 = (t12 ~= t13)  -- Expected: true (different tables)
    __rawasm__("__debug7:")
end

function main()
    ioports.gpu.clear("black")
    test_table_identity()

    print(100, 00,  "--- Table Identity Test ---")
    print(100, 20,  "Test 1 - Same content, diff table: " .. tostring(boolean_result1))
    print(100, 40,  "Test 2 - Same table, two refs: " .. tostring(boolean_result2))
    print(100, 60,  "Test 3 - Two empty tables: " .. tostring(boolean_result3))
    print(100, 80,  "Test 4a - Table vs nil: " .. tostring(boolean_result4))
    print(100, 100, "Test 4b - Table vs number: " .. tostring(boolean_result5))
    print(100, 120, "Test 4c - Table vs string: " .. tostring(boolean_result6))
    print(100, 140, "Test 5 - Identity thru fn: " .. tostring(boolean_result7))
    print(100, 160, "Test 6 - Alias after mutate: " .. tostring(boolean_result8))
    print(100, 180, "Test 7 - Not-equal op: " .. tostring(boolean_result9))
end

--[[
=== EXPECTED OUTPUT ===
boolean_result1: false
boolean_result2: true
boolean_result3: false
boolean_result4: false
boolean_result5: false
boolean_result6: false
boolean_result7: true
boolean_result8: true
boolean_result9: true
]]
