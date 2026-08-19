--@ Vircon32 Lua Variadic Functions Unit Test
--@ Tests '...' capture via {...}, argument counting, zero-argument
--@ calls, mixing variadics with fixed leading parameters, and forwarding.
--@ Results are stored in global variables for automated memory scraping.
--@
--@ NOTE: bare '...' as a standalone expression is NOT covered here --
--@ NODE_VARIADIC_EXPR is currently an unimplemented stub in generate_asm()
--@ (emits a comment and nothing else). Everything below deliberately uses
--@ the {...} table-capture idiom instead, which does work.

function test_variadics()
    -- === Test 00: Sum via {...} + ipairs ===
    local function sum(...)
        local total = 0
        local args = {...}
        for i, v in ipairs(args) do
            total = total + v
        end
        return total
    end
    number_result00 = sum(1, 2, 3, 4, 5)   -- 15
    __rawasm__("__debug0:")

    -- === Test 01: Count via #{...} ===
    local function count(...)
        local args = {...}
        return #args
    end
    number_result01 = count(1, 2, 3, 4)   -- 4
    __rawasm__("__debug1:")

    -- === Test 02: Max via {...} ===
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
    number_result02 = max(3, 1, 4, 1, 5, 9, 2)   -- 9
    __rawasm__("__debug2:")

    -- === Test 03: Variadic function called with ZERO arguments ===
    local function count_or_zero(...)
        local args = {...}
        return #args
    end
    number_result03 = count_or_zero()   -- 0
    __rawasm__("__debug3:")

    -- === Test 04: Variadic mixed with fixed leading parameters ===
    local function scaled_sum(scale, ...)
        local args = {...}
        local total = 0
        for i, v in ipairs(args) do
            total = total + v
        end
        return total * scale
    end
    number_result04 = scaled_sum(2, 1, 2, 3)   -- 12
    __rawasm__("__debug4:")

    -- === Test 05: Variadic args captured, then forwarded as explicit ===
    -- === positional arguments to another call ===
    local function add3(a, b, c)
        return a + b + c
    end
    local function forward(...)
        local args = {...}
        return add3(args[1], args[2], args[3])
    end
    number_result05 = forward(10, 20, 30)   -- 60
    __rawasm__("__debug5:")
end

function main()
    ioports.gpu.clear("black")
    test_variadics()

    print(000, 00,  "--- Variadics Test ---")
    print(000, 020, "Test 00 - Sum: " ..           number_result00)
    print(000, 040, "Test 01 - Count: " ..         number_result01)
    print(000, 060, "Test 02 - Max: " ..           number_result02)
    print(000, 080, "Test 03 - Zero args: " ..     number_result03)
    print(000, 100, "Test 04 - Scaled sum: " ..    number_result04)
    print(000, 120, "Test 05 - Forwarded: " ..     number_result05)
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 15.0000
number_result01: 4.0000
number_result02: 9.0000
number_result03: 0.0000
number_result04: 12.0000
number_result05: 60.0000
--]]
