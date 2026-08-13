--#title "v32lua variables unit test"
--@ Vircon32 Lua Variables Unit Test
--@ Tests non-table variable operations and types.
--@ Results are stored in global variables for automated memory scraping.

function test_variables()
    -- === Test 1: Basic number variables ===
    local a = 42
    local b = 10
    number_result1 = a + b  -- Expected: 52
    number_result2 = a - b  -- Expected: 32
    number_result3 = a * b  -- Expected: 420
    number_result4 = a / b  -- Expected: 4.2

    -- === Test 2: String variables ===
    local s1 = "hello"
    local s2 = "world"
    string_result1 = s1 .. " " .. s2  -- Expected: "hello world"
    number_result5 = #s1  -- Expected: 5 (string length)

    -- === Test 3: Boolean variables ===
    local t = true
    local f = false
    boolean_result1 = (t and f)
    boolean_result2 = (t or f)
    boolean_result3 = not t

    -- === Test 4: Nil and type checking ===
    local n = nil
    string_result2 = type(n)  -- Expected: "nil"
    string_result3 = type(a)  -- Expected: "number"
    string_result4 = type(s1)  -- Expected: "string"
    string_result5 = type(t)  -- Expected: "boolean"

    -- === Test 5: Variable reassignment ===
    local x = 100
    x = x + 50
    x = x * 2
    number_result6 = x  -- Expected: 300

    -- === Test 6: Multiple assignment ===
    local p, q, r = 1, 2, 3
    number_result7 = p + q + r  -- Expected: 6
end

function main()
    ioports.gpu.clear("black")
    test_variables()

    print(100, 00,  "--- Variables Test ---")
    print(100, 20,  "Test 1 - Add: " ..          number_result1)
    print(100, 40,  "Test 1 - Subtract: " ..     number_result2)
    print(100, 60,  "Test 1 - Multiply: " ..     number_result3)
    print(100, 80,  "Test 1 - Divide: " ..      number_result4)
    print(100, 100, "Test 2 - Concat: " ..      string_result1)
    print(100, 120, "Test 2 - Length: " ..      number_result5)
    print(100, 140, "Test 3 - And: " ..         tostring(boolean_result1))
    print(100, 160, "Test 3 - Or: " ..          tostring(boolean_result2))
    print(100, 180, "Test 3 - Not: " ..         tostring(boolean_result3))
    print(100, 200, "Test 4 - Nil type: " ..    string_result2)
    print(100, 220, "Test 4 - Number type: " .. string_result3)
    print(100, 240, "Test 4 - String type: " .. string_result4)
    print(100, 260, "Test 4 - Bool type: " ..   string_result5)
    print(100, 280, "Test 5 - Reassign: " ..    number_result6)
    print(100, 300, "Test 6 - Multi assign: " .. number_result7)
end

--[[
=== EXPECTED OUTPUT ===

number_result1: 52.0000
number_result2: 32.0000
number_result3: 420.0000
number_result4: 4.2000
string_result1: "hello world"
number_result5: 5.0000
boolean_result1: false
boolean_result2: true
boolean_result3: false
string_result2: "nil"
string_result3: "number"
string_result4: "string"
string_result5: "boolean"
number_result6: 300.0000
number_result7: 6.0000

--]]
