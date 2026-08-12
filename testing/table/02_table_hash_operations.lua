--#title "v32lua table hash operations unit test"
--@ Vircon32 Lua Table Hash Operations Unit Test
--@ Tests ONLY hash part operations (non-integer keys).
--@ Results stored in global variables for automated memory scraping.

function test_table_hash_operations()
    -- === Test 1: String keys ===
    local t1 = {name = "hero", class = "mage", level = 99}
    string_result1 = t1.name   -- Expected: "hero"
    string_result2 = t1.class  -- Expected: "mage"
    number_result1 = t1.level  -- Expected: 99

    -- === Test 2: Zero and negative indices ===
    local t2 = {}
    t2[0] = "zero"
    t2[-1] = "minus_one"
    t2[-100] = "minus_hundred"
    string_result3 = t2[0]     -- Expected: "zero"
    string_result4 = t2[-1]    -- Expected: "minus_one"
    string_result5 = t2[-100]  -- Expected: "minus_hundred"

    -- === Test 3: Mixed key types ===
    local t3 = {}
    t3["string"] = "text"
    t3[0] = "zero_key"
    t3[1] = "array_start"
    string_result6 = t3.string    -- Expected: "text"
    string_result7 = t3[0]        -- Expected: "zero_key"
    string_result8 = t3[1]        -- Expected: "array_start"
    number_result2 = #t3         -- Expected: 1 (only positive int keys count)

    -- === Test 4: Dynamic key access ===
    local t4 = {}
    local key = "dynamic"
    t4[key] = "value"
    string_result9 = t4[key]     -- Expected: "value"
    string_result10 = t4["dynamic"]  -- Expected: "value"

    -- === Test 5: Nil value vs missing key ===
    local t5 = {exists = "yes", missing = nil}
    string_result11 = t5.exists  -- Expected: "yes"
    boolean_result1 = (t5.missing == nil)  -- Expected: true
    boolean_result2 = (t5.absent == nil)   -- Expected: true (absent key returns nil)
end

function main()
    ioports.gpu.clear("black")
    test_table_hash_operations()

    print(100, 00,  "--- Table Hash Operations Test ---")
    print(100, 20,  "Test 1 - name: " .. string_result1)
    print(100, 40,  "Test 1 - class: " .. string_result2)
    print(100, 60,  "Test 1 - level: " .. number_result1)
    print(100, 80,  "Test 2 - Index[0]: " .. string_result3)
    print(100, 100, "Test 2 - Index[-1]: " .. string_result4)
    print(100, 120, "Test 2 - Index[-100]: " .. string_result5)
    print(100, 140, "Test 3 - string key: " .. string_result6)
    print(100, 160, "Test 3 - zero key: " .. string_result7)
    print(100, 180, "Test 3 - array key: " .. string_result8)
    print(100, 200, "Test 3 - length: " .. number_result2)
    print(100, 220, "Test 4 - dynamic: " .. string_result9)
    print(100, 240, "Test 4 - literal: " .. string_result10)
    print(100, 260, "Test 5 - exists: " .. string_result11)
    print(100, 280, "Test 5 - missing==nil: " .. tostring(boolean_result1))
    print(100, 300, "Test 5 - absent==nil: " .. tostring(boolean_result2))
end

--[[

=== EXPECTED OUTPUT ===
string_result1: "hero"
string_result2: "mage"
number_result1: 99.0000
string_result3: "zero"
string_result4: "minus_one"
string_result5: "minus_hundred"
string_result6: "text"
string_result7: "zero_key"
string_result8: "array_start"
number_result2: 1.0000
string_result9: "value"
string_result10: "value"
string_result11: "yes"
boolean_result1: true
boolean_result2: true

--]]
