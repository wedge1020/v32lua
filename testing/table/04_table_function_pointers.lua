--@ Vircon32 Lua Table Function Pointers Unit Test
--@ Tests ONLY storing and calling functions from tables.
--@ Results stored in global variables for automated memory scraping.

-- Helper functions for testing
function add(a, b) return a + b end
function multiply(a, b) return a * b end
function greet(name) return "Hello, " .. name end

function test_table_function_pointers()
    -- === Test 1: Storing function in table ===
    local t1 = {op = add}
    number_result1 = t1.op(3, 5)  -- Expected: 8

    -- === Test 2: Multiple function pointers ===
    local t2 = {sum = add, product = multiply}
    number_result2 = t2.sum(4, 6)      -- Expected: 10
    number_result3 = t2.product(4, 6) -- Expected: 24

    -- === Test 3: Method-style calls ===
    local t3 = {value = 10, double = function(self) return self.value * 2 end}
    number_result4 = t3.double(t3)  -- Expected: 20

    -- === Test 4: Dynamic function assignment ===
    local t4 = {}
    t4.func = greet
    string_result1 = t4.func("Vircon32")  -- Expected: "Hello, Vircon32"

    -- === Test 5: Overwriting function pointers ===
    local t5 = {op = add}
    t5.op = multiply
    number_result5 = t5.op(3, 4)  -- Expected: 12 (not 7)

    -- === Test 6: Nested function tables ===
    local t6 = {
        math = {add = add, mul = multiply}
    }
    number_result6 = t6.math.add(7, 3)   -- Expected: 10
    number_result7 = t6.math.mul(7, 3)  -- Expected: 21
end

function main()
    ioports.gpu.clear("black")
    test_table_function_pointers()

    print(100, 00,  "--- Table Function Pointers Test ---")
    print(100, 20,  "Test 1 - add(3,5): " .. number_result1)
    print(100, 40,  "Test 2 - sum(4,6): " .. number_result2)
    print(100, 60,  "Test 2 - product(4,6): " .. number_result3)
    print(100, 80,  "Test 3 - double(): " .. number_result4)
    print(100, 100, "Test 4 - greet(): " .. string_result1)
    print(100, 120, "Test 5 - swapped op: " .. number_result5)
    print(100, 140, "Test 6 - nested add: " .. number_result6)
    print(100, 160, "Test 6 - nested mul: " .. number_result7)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
number_result1: 8
number_result2: 10
number_result3: 24
number_result4: 20
string_result1: "Hello, Vircon32"
number_result5: 12
number_result6: 10
number_result7: 21
]]
