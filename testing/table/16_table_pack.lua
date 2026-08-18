--@ Vircon32 Lua table.pack() Unit Test
--@ Tests ONLY the table.pack() library function.
--@ Results stored in global variables for automated memory scraping.

function test_table_pack()
    -- === Test 1: Pack multiple values ===
    local t1 = table.pack("a", "b", "c")
    string_result1 = t1[1]  -- Expected: "a"
    string_result2 = t1[2]  -- Expected: "b"
    string_result3 = t1[3]  -- Expected: "c"
    number_result1 = t1.n   -- Expected: 3

    -- === Test 2: Pack single value ===
    local t2 = table.pack(42)
    number_result2 = t2[1]  -- Expected: 42
    number_result3 = t2.n   -- Expected: 1

    -- === Test 3: Pack no values ===
    local t3 = table.pack()
    number_result4 = t3.n   -- Expected: 0

    -- === Test 4: Pack mixed types ===
    local t4 = table.pack(1, "two", true, nil)
    number_result5 = t4[1]      -- Expected: 1
    string_result4 = t4[2]      -- Expected: "two"
    boolean_result1 = t4[3]     -- Expected: true
    boolean_result2 = (t4[4] == nil)  -- Expected: true
    number_result6 = t4.n       -- Expected: 4

    -- === Test 5: Pack with nils in middle ===
    local t5 = table.pack("a", nil, "c")
    string_result5 = t5[1]     -- Expected: "a"
    boolean_result3 = (t5[2] == nil)  -- Expected: true
    string_result6 = t5[3]     -- Expected: "c"
    number_result7 = t5.n     -- Expected: 3
end

function main()
    ioports.gpu.clear("black")
    test_table_pack()

    print(100, 00,  "--- table.pack() Test ---")
    print(100, 20,  "Test 1 - Val[1]: " .. string_result1)
    print(100, 40,  "Test 1 - Val[2]: " .. string_result2)
    print(100, 60,  "Test 1 - Val[3]: " .. string_result3)
    print(100, 80,  "Test 1 - .n field: " .. number_result1)
    print(100, 100, "Test 2 - Single: " .. number_result2)
    print(100, 120, "Test 2 - .n: " .. number_result3)
    print(100, 140, "Test 3 - Empty .n: " .. number_result4)
    print(100, 160, "Test 4 - Num: " .. number_result5)
    print(100, 180, "Test 4 - Str: " .. string_result4)
    print(100, 200, "Test 4 - Bool: " .. tostring(boolean_result1))
    print(100, 220, "Test 4 - Nil check: " .. tostring(boolean_result2))
    print(100, 240, "Test 4 - .n: " .. number_result6)
    print(100, 260, "Test 5 - Val[1]: " .. string_result5)
    print(100, 280, "Test 5 - Nil check: " .. tostring(boolean_result3))
    print(100, 300, "Test 5 - Val[3]: " .. string_result6)
    print(100, 320, "Test 5 - .n: " .. number_result7)
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "a"
string_result2: "b"
string_result3: "c"
number_result1: 3
number_result2: 42
number_result3: 1
number_result4: 0
number_result5: 1
string_result4: "two"
boolean_result1: true
boolean_result2: true
number_result6: 4
string_result5: "a"
boolean_result3: true
string_result6: "c"
number_result7: 3
]]
