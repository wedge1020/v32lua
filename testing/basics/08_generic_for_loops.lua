--#title "v32lua generic for loops unit test"
--@ Vircon32 Lua Generic For Loops Unit Test
--@ Tests ipairs and pairs iteration.
--@ Results are stored in global variables for automated memory scraping.

function test_generic_for_loops()
    -- === Test 1: ipairs on array ===
    local t1 = {"a", "b", "c"}
    local count1 = 0
    for i, v in ipairs(t1) do
        count1 = count1 + 1
        if i == 1 then string_result1 = v end
        if i == 3 then string_result2 = v end
    end
    number_result1 = count1  -- Expected: 3

    -- === Test 2: pairs on hash table ===
    local t2 = {x = 10, y = 20, z = 30}
    local sum2 = 0
    for k, v in pairs(t2) do
        sum2 = sum2 + v
        if k == "y" then number_result2 = v end
    end
    number_result3 = sum2  -- Expected: 60

    -- === Test 3: ipairs with mixed table ===
    local t3 = {"first", "second", key = "value"}
    local array_count = 0
    for i, v in ipairs(t3) do
        array_count = array_count + 1
    end
    number_result4 = array_count  -- Expected: 2 (only array part)

    -- === Test 4: pairs counts all keys ===
    local t4 = {"arr", key1 = "val1", key2 = "val2"}
    local total_keys = 0
    for k, v in pairs(t4) do
        total_keys = total_keys + 1
    end
    number_result5 = total_keys  -- Expected: 3 (1 array + 2 hash)
end

function main()
    ioports.gpu.clear("black")
    test_generic_for_loops()

    print(100, 00,  "--- Generic For Loops Test ---")
    print(100, 20,  "Test 1 - ipairs count: " ..    number_result1)
    print(100, 40,  "Test 1 - ipairs[1]: " ..      string_result1)
    print(100, 60,  "Test 1 - ipairs[3]: " ..      string_result2)
    print(100, 80,  "Test 2 - pairs sum: " ..      number_result3)
    print(100, 100, "Test 2 - pairs y val: " ..    number_result2)
    print(100, 120, "Test 3 - ipairs mixed: " ..   number_result4)
    print(100, 140, "Test 4 - pairs all keys: " .. number_result5)
end

--[[
=== EXPECTED OUTPUT ===

number_result1: 3.0000
string_result1: "a"
string_result2: "c"
number_result2: 20.0000
number_result3: 60.0000
number_result4: 2.0000
number_result5: 3.0000

--]]
