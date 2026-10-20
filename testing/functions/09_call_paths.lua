--@ Vircon32 Lua Call-Path Unit Test
--@ Variadic and multi-return functions reached through every kind of call
--@ path: global name, local function, local holding a function value,
--@ table field, method, function passed as a parameter, upvalue, and a
--@ runtime callback (table.sort comparator). Regression test for local
--@ functions losing their arity/return-count metadata (multi-return values
--@ came back nil) and for the variadic argument count only being passed
--@ when the call site could prove the target variadic (calls through any
--@ value read a fixed parameter as the count, or walked off the stack).
--@ Results are stored in global variables for automated memory scraping.

function g_sum(...)
    local t = {...}
    local s = 0
    for i, v in ipairs(t) do s = s + v end
    return s, #t
end

function test_call_paths()
    -- === Test 00: global variadic, called directly ===
    local s0, n0 = g_sum(1, 2, 3)
    number_result00a = s0      -- 6
    number_result00b = n0      -- 3
    __rawasm__("__debug0:")

    -- === Test 01: global variadic, called through a local value ===
    local f = g_sum
    number_result01 = f(4, 5, 6, 7)      -- 22
    __rawasm__("__debug1:")

    -- === Test 02: local function, fixed + variadic, multiple returns ===
    local function head_rest(first, ...)
        local rest = {...}
        return first, #rest
    end
    local h, r = head_rest(10, 20, 30)
    number_result02a = h       -- 10
    number_result02b = r       -- 2
    __rawasm__("__debug2:")

    -- === Test 03: variadic stored in a table field ===
    local lib = {}
    lib.count = function(...) return #{...} end
    number_result03 = lib.count(1, 1, 1, 1, 1)   -- 5
    __rawasm__("__debug3:")

    -- === Test 04: variadic method (self is counted, not a vararg) ===
    local obj = { base = 100 }
    function obj:add(...)
        local s = self.base
        for i, v in ipairs({...}) do s = s + v end
        return s
    end
    number_result04 = obj:add(1, 2)       -- 103
    __rawasm__("__debug4:")

    -- === Test 05: variadic passed as a parameter and called there ===
    local function apply(fn, a, b, c) return fn(a, b, c) end
    number_result05 = apply(g_sum, 7, 8, 9)   -- 24
    __rawasm__("__debug5:")

    -- === Test 06: local variadic called from a nested closure (upvalue) ===
    local function count(...) return #{...} end
    local function outer() return count(9, 9, 9) end
    number_result06 = outer()             -- 3
    __rawasm__("__debug6:")

    -- === Test 07: multi-return local function called through an upvalue ===
    local function pair() return 11, 22 end
    local function via_upvalue()
        local a, b = pair()
        return a + b
    end
    number_result07 = via_upvalue()       -- 33
    __rawasm__("__debug7:")

    -- === Test 08: omitted fixed parameter of a variadic function is nil ===
    local function first_or(x, ...)
        if x == nil then return -1 end
        return x
    end
    number_result08 = first_or()          -- -1
    __rawasm__("__debug8:")

    -- === Test 09: variadic comparator called back by table.sort ===
    local arr = { 3, 1, 2 }
    table.sort(arr, function(...)
        local p = {...}
        return p[1] > p[2]
    end)
    number_result09 = arr[1] * 100 + arr[2] * 10 + arr[3]   -- 321
    __rawasm__("__debug9:")

    -- === Test 10: '...' as a single value (first vararg) ===
    local function first(...)
        local v = ...
        return v
    end
    number_result10 = first(42, 43)       -- 42
    __rawasm__("__debug10:")
end

function main()
    ioports.gpu.clear("black")
    test_call_paths()

    print(000, 000, "--- Call Paths Test ---")
    print(000, 020, "Test 00 - global: " ..        number_result00a .. " " .. number_result00b)
    print(000, 040, "Test 01 - via local: " ..     number_result01)
    print(000, 060, "Test 02 - local fn: " ..      number_result02a .. " " .. number_result02b)
    print(000, 080, "Test 03 - field: " ..         number_result03)
    print(000, 100, "Test 04 - method: " ..        number_result04)
    print(000, 120, "Test 05 - param: " ..         number_result05)
    print(000, 140, "Test 06 - upvalue: " ..       number_result06)
    print(000, 160, "Test 07 - multiret up: " ..   number_result07)
    print(000, 180, "Test 08 - omitted: " ..       number_result08)
    print(000, 200, "Test 09 - sort cb: " ..       number_result09)
    print(000, 220, "Test 10 - '...': " ..         number_result10)
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 6.0000
number_result00b: 3.0000
number_result01: 22.0000
number_result02a: 10.0000
number_result02b: 2.0000
number_result03: 5.0000
number_result04: 103.0000
number_result05: 24.0000
number_result06: 3.0000
number_result07: 33.0000
number_result08: -1.0000
number_result09: 321.0000
number_result10: 42.0000

--]]
