--#title "v32lua print function unit test"
--@ Vircon32 Lua Print Function Unit Test
--@ Tests print() output to GPU framebuffer.
--@ Results are stored in global variables for automated memory scraping.

function test_print_function()
    -- === Test 1: Basic print with numbers ===
    local x, y = 100, 50
    print(x, y, "Test1")
    number_result1 = x
    number_result2 = y

    -- === Test 2: Print with strings ===
    print(100, 70, "Hello")
    string_result1 = "Hello"

    -- === Test 3: Print with expressions ===
    local a, b = 10, 20
    print(100, 90, "Sum: " .. tostring(a + b))
    number_result3 = a + b

    -- === Test 4: Print with nil ===
    print(100, 110, tostring(nil))
    string_result2 = "nil"

    -- === Test 5: Print with booleans ===
    print(100, 130, tostring(true))
    print(100, 150, tostring(false))
    boolean_result1 = true
    boolean_result2 = false

    -- === Test 6: Print with formatted numbers ===
    local pi = 3.14159
    print(100, 170, string.format("%.2f", pi))
    string_result3 = string.format("%.2f", pi)
end

function main()
    ioports.gpu.clear("black")
    test_print_function()

    print(100, 00,  "--- Print Function Test ---")
    print(100, 20,  "Test 1 - X coord: " ..    number_result1)
    print(100, 40,  "Test 1 - Y coord: " ..    number_result2)
    print(100, 60,  "Test 2 - String: " ..     string_result1)
    print(100, 80,  "Test 3 - Sum: " ..       number_result3)
    print(100, 100, "Test 4 - Nil: " ..       string_result2)
    print(100, 120, "Test 5 - True: " ..      tostring(boolean_result1))
    print(100, 140, "Test 5 - False: " ..     tostring(boolean_result2))
    print(100, 160, "Test 6 - Formatted: " .. string_result3)
end

--[[
=== EXPECTED OUTPUT ===

number_result1: 100.0000
number_result2: 50.0000
string_result1: "Hello"
number_result3: 30.0000
string_result2: "nil"
boolean_result1: true
boolean_result2: false
string_result3: "3.14"

--]]
