--@ Vircon32 Lua Recursion Unit Test
--@ Tests direct recursion, mutual recursion between two globals,
--@ accumulator-style recursion, local-function self-recursion, and
--@ deeper recursion depth as a stack-frame sanity check.
--@ Results are stored in global variables for automated memory scraping.

function is_even(n)
    if n == 0 then
        return true
    end
    return is_odd(n - 1)
end

function is_odd(n)
    if n == 0 then
        return false
    end
    return is_even(n - 1)
end

function test_recursion()
    -- === Test 00: Factorial ===
    local function factorial(n)
        if n <= 1 then
            return 1
        end
        return n * factorial(n - 1)
    end
    number_result00 = factorial(5)   -- 120
    __rawasm__("__debug0:")

    -- === Test 01: Fibonacci ===
    local function fib(n)
        if n <= 1 then
            return n
        end
        return fib(n - 1) + fib(n - 2)
    end
    number_result01 = fib(6)   -- 8
    __rawasm__("__debug1:")

    -- === Test 02: Mutual recursion between two top-level globals ===
    boolean_result02a = is_even(10)   -- true
    boolean_result02b = is_odd(10)    -- false
    __rawasm__("__debug2:")

    -- === Test 03: Accumulator-style (tail-recursive shape) recursion ===
    local function sum_to(n, acc)
        acc = acc or 0
        if n == 0 then
            return acc
        end
        return sum_to(n - 1, acc + n)
    end
    number_result03 = sum_to(10)   -- 55
    __rawasm__("__debug3:")

    -- === Test 04: 'local function' can call itself by name ===
    -- === (self-reference visible inside its own body) ===
    local function countdown(n)
        if n <= 0 then
            return 0
        end
        return countdown(n - 1)
    end
    number_result04 = countdown(20)   -- 0
    __rawasm__("__debug4:")

    -- === Test 05: Deeper recursion depth -- stack-frame sanity check ===
    local function deep_sum(n)
        if n == 0 then
            return 0
        end
        return n + deep_sum(n - 1)
    end
    number_result05 = deep_sum(50)   -- 1275
    __rawasm__("__debug5:")
end

function main()
    ioports.gpu.clear("black")
    test_recursion()

    print(000, 00,  "--- Recursion Test ---")
    print(000, 020, "Test 00 - Factorial: " ..    number_result00)
    print(000, 040, "Test 01 - Fibonacci: " ..    number_result01)
    print(000, 060, "Test 02 - is_even(10): " ..  tostring(boolean_result02a))
    print(000, 080, "Test 02 - is_odd(10): " ..   tostring(boolean_result02b))
    print(000, 100, "Test 03 - Accumulator: " ..  number_result03)
    print(000, 120, "Test 04 - Countdown: " ..    number_result04)
    print(000, 140, "Test 05 - Deep sum: " ..     number_result05)
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 120.0000
number_result01: 8.0000
boolean_result02a: true
boolean_result02b: false
number_result03: 55.0000
number_result04: 0.0000
number_result05: 1275.0000
--]]
