--#title "v32lua functions unit test"
--@ Vircon32 Lua Functions Unit Test
--@ Tests function definition, calls, returns, and closures.
--@ Results are stored in global variables for automated memory scraping.

function test_functions()
    -- === Test 1: Basic function call ===
    local function add(a, b)
        return a + b
    end
    number_result1 = add(2, 3)  -- Expected: 5

    -- === Test 2: Function with multiple returns ===
    local function swap(a, b)
        return b, a
    end
    local x, y = swap(10, 20)
    number_result2 = x  -- Expected: 20
    number_result3 = y  -- Expected: 10

    -- === Test 3: Recursive function ===
    local function factorial(n)
        if n <= 1 then return 1 end
        return n * factorial(n - 1)
    end
    number_result4 = factorial(5)  -- Expected: 120

    -- === Test 4: Closure ===
    local function make_counter()
        local count = 0
        return function()
            count = count + 1
            return count
        end
    end
    local counter = make_counter()
    number_result5 = counter()  -- Expected: 1
    number_result6 = counter()  -- Expected: 2

    -- === Test 5: Variadic function ===
    local function sum(...)
        local total = 0
        local args = {...}
        for i, v in ipairs(args) do
            total = total + v
        end
        return total
    end
    number_result7 = sum(1, 2, 3, 4)  -- Expected: 10

    -- === Test 6: Function as argument ===
    local function apply(f, x)
        return f(x)
    end
    local function double(x)
        return x * 2
    end
    number_result8 = apply(double, 25)  -- Expected: 50
end

function main()
    ioports.gpu.clear("black")
    test_functions()

    print(100, 00,  "--- Functions Test ---")
    print(100, 20,  "Test 1 - Add: " ..          number_result1)
    print(100, 40,  "Test 2 - Swap x: " ..      number_result2)
    print(100, 60,  "Test 2 - Swap y: " ..      number_result3)
    print(100, 80,  "Test 3 - Factorial: " ..   number_result4)
    print(100, 100, "Test 4 - Counter 1: " ..   number_result5)
    print(100, 120, "Test 4 - Counter 2: " ..   number_result6)
    print(100, 140, "Test 5 - Variadic: " ..    number_result7)
    print(100, 160, "Test 6 - Apply: " ..       number_result8)
end

--[[
=== EXPECTED OUTPUT ===

number_result1: 5.0000
number_result2: 20.0000
number_result3: 10.0000
number_result4: 120.0000
number_result5: 1.0000
number_result6: 2.0000
number_result7: 10.0000
number_result8: 50.0000

--]]
