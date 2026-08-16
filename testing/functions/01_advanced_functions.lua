--#title "v32lua functions advanced unit test"
--@ Vircon32 Lua Functions Advanced Unit Test
--@ Tests advanced function features: variadic, closures, recursion, higher-order.
--@ Results are stored in global variables for automated memory scraping.

function test_functions_advanced()
    -- === Test 00: Recursive function - factorial ===
    local function factorial(n)
        if n <= 1 then
            return 1
        end
        return n * factorial(n - 1)
    end
    number_result00 = factorial(5)

    -- === Test 01: Recursive function - fibonacci ===
    local function fib(n)
        if n <= 1 then
            return n
        end
        return fib(n - 1) + fib(n - 2)
    end
    number_result01 = fib(6)

    -- === Test 02: Closure - simple counter ===
    local function make_counter()
        local count = 0
        return function()
            count = count + 1
            return count
        end
    end
    local counter = make_counter()
    number_result02 = counter()
    number_result03 = counter()
    number_result04 = counter()

    -- === Test 03: Closure - with parameter ===
    local function make_adder(x)
        return function(y)
            return x + y
        end
    end
    local adder = make_adder(10)
    number_result05 = adder(5)
    number_result06 = adder(20)

    -- === Test 04: Variadic function - sum ===
    local function sum(...)
        local total = 0
        local args = {...}
        for i, v in ipairs(args) do
            total = total + v
        end
        return total
    end
    number_result07 = sum(1, 2, 3, 4, 5)

    -- === Test 05: Variadic function - count ===
    local function count(...)
        local args = {...}
        return #args
    end
    number_result08 = count(1, 2, 3, 4)

    -- === Test 06: Variadic function - max ===
    local function max(...)
        local args = {...}
        local m = args[1]
        for i = 2, #args do
            if args[i] > m then
                m = args[i]
            end
        end
        return m
    end
    number_result09 = max(3, 1, 4, 1, 5, 9, 2)

    -- === Test 07: Function as argument - apply ===
    local function apply(f, x)
        return f(x)
    end
    local function double(x)
        return x * 2
    end
    number_result10 = apply(double, 25)

    -- === Test 08: Function as argument - map-like ===
    local function transform(f, a, b, c)
        return f(a), f(b), f(c)
    end
    local function square(x)
        return x * x
    end
    local s1, s2, s3 = transform(square, 2, 3, 4)
    number_result11 = s1
    number_result12 = s2
    number_result13 = s3

    -- === Test 09: Function returning function ===
    local function make_multiplier(factor)
        return function(x)
            return x * factor
        end
    end
    local triple = make_multiplier(3)
    number_result14 = triple(10)

    -- === Test 10: Higher-order function - compose ===
    local function compose(f, g)
        return function(x)
            return f(g(x))
        end
    end
    local function add_one(x)
        return x + 1
    end
    local function double_it(x)
        return x * 2
    end
    local composed = compose(add_one, double_it)
    number_result15 = composed(5)

    -- === Test 11: Anonymous function ===
    local anonymous = function(x, y)
        return x + y
    end
    number_result16 = anonymous(10, 20)

    -- === Test 12: Immediately invoked function expression ===
    local result = (function(x, y)
        return x * y
    end)(5, 6)
    number_result17 = result

    -- === Test 13: Closure with multiple captured variables ===
    local function make_rectangle_area(width, height)
        return function()
            return width * height
        end
    end
    local area = make_rectangle_area(10, 20)
    number_result18 = area()

    -- === Test 14: Closure modifying captured variable ===
    local function make_incrementer(start)
        return function()
            start = start + 1
            return start
        end
    end
    local incrementer = make_incrementer(0)
    number_result19 = incrementer()
    number_result20 = incrementer()
    number_result21 = incrementer()

    -- === Test 15: Multiple closures sharing state ===
    local function make_counters()
        local count = 0
        local function increment()
            count = count + 1
            return count
        end
        local function get()
            return count
        end
        return increment, get
    end
    local inc, get = make_counters()
    inc()
    inc()
    number_result22 = get()

    -- === Test 16: Variadic function with select ===
    local function first(...)
        local args = {...}
        return args[1]
    end
    number_result23 = first(100, 200, 300)

    -- === Test 17: Nested function definition ===
    local function outer(x)
        local function inner(y)
            return x + y
        end
        return inner(10)
    end
    number_result24 = outer(5)

    -- === Test 18: Function with default-like parameters via or ===
    local function with_default(x, y)
        y = y or 10
        return x + y
    end
    number_result25 = with_default(5)

    -- === Test 19: Function with multiple return values to single variable ===
    local function multi_return()
        return 1, 2, 3
    end
    local first_only = multi_return()
    number_result26 = first_only

    -- === Test 20: Recursive closure (via local function) ===
    local function recursive_factorial(n)
        local fact
        fact = function(k)
            if k <= 1 then
                return 1
            end
            return k * fact(k - 1)
        end
        return fact(n)
    end
    number_result27 = recursive_factorial(5)
end

function main()
    ioports.gpu.clear("black")
    test_functions_advanced()

    print(000, 00,  "--- Functions Advanced Test ---")
    print(000, 020, "Test 00 - Factorial: " ..        number_result00)
    print(000, 040, "Test 01 - Fibonacci: " ..        number_result01)
    print(000, 060, "Test 02 - Counter 1: " ..         number_result02)
    print(000, 080, "Test 03 - Counter 2: " ..         number_result03)
    print(000, 100, "Test 04 - Counter 3: " ..         number_result04)
    print(000, 120, "Test 05 - Adder 5: " ..          number_result05)
    print(000, 140, "Test 06 - Adder 20: " ..         number_result06)
    print(000, 160, "Test 07 - Variadic sum: " ..     number_result07)
    print(000, 180, "Test 08 - Variadic count: " ..   number_result08)
    print(000, 200, "Test 09 - Variadic max: " ..     number_result09)
    print(000, 220, "Test 10 - Apply: " ..            number_result10)
    print(000, 240, "Test 11 - Transform a: " ..      number_result11)
    print(000, 260, "Test 12 - Transform b: " ..      number_result12)
    print(200, 020, "Test 13 - Transform c: " ..      number_result13)
    print(200, 040, "Test 14 - Make mult: " ..        number_result14)
    print(200, 060, "Test 15 - Compose: " ..          number_result15)
    print(200, 080, "Test 16 - Anonymous: " ..        number_result16)
    print(200, 100, "Test 17 - IIFE: " ..             number_result17)
    print(200, 120, "Test 18 - Rectangle: " ..        number_result18)
    print(200, 140, "Test 19 - Increment 1: " ..      number_result19)
    print(200, 160, "Test 20 - Increment 2: " ..      number_result20)
    print(200, 180, "Test 21 - Increment 3: " ..      number_result21)
    print(200, 200, "Test 22 - Shared state: " ..      number_result22)
    print(200, 220, "Test 23 - First: " ..            number_result23)
    print(200, 240, "Test 24 - Nested: " ..           number_result24)
    print(200, 260, "Test 25 - Default: " ..          number_result25)
    print(200, 280, "Test 26 - Multi ret: " ..        number_result26)
    print(200, 300, "Test 27 - Rec closure: " ..      number_result27)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 120.0000
number_result01: 8.0000
number_result02: 1.0000
number_result03: 2.0000
number_result04: 3.0000
number_result05: 15.0000
number_result06: 30.0000
number_result07: 15.0000
number_result08: 4.0000
number_result09: 9.0000
number_result10: 50.0000
number_result11: 4.0000
number_result12: 9.0000
number_result13: 16.0000
number_result14: 30.0000
number_result15: 11.0000
number_result16: 30.0000
number_result17: 30.0000
number_result18: 200.0000
number_result19: 1.0000
number_result20: 2.0000
number_result21: 3.0000
number_result22: 2.0000
number_result23: 100.0000
number_result24: 15.0000
number_result25: 15.0000
number_result26: 1.0000
number_result27: 120.0000

--]]
