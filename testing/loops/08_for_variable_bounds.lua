--#title "v32lua numeric for with variable bounds unit test"
--@ Vircon32 Lua Numeric For Loops with Non-literal Bounds Unit Test
--@ A start, limit or step that is not a literal is checked once, before the loop
--@ (it must be a number, or a numeric string as in Lua 5.4); valid loops run as
--@ before. The runtime errors for the other values are in tests/loops/for_errors.sh.
--@ Results are stored in global variables for automated memory scraping.

limit_g = 6
step_g = 2
cfg = { first = 3, last = 7, step = 2 }

local function lim() return 4 end
local function two(a) return a * 2 end

function test_variable_bounds()
    local sum, n

    -- === Test 00: Limit in a local ===
    local lo, hi = 2, 5
    sum = 0
    for i = lo, hi do sum = sum + i end
    number_result00 = sum                 -- 2 + 3 + 4 + 5 = 14

    -- === Test 01: Limit in a global ===
    sum = 0
    for i = 1, limit_g do sum = sum + i end
    number_result01 = sum                 -- 21

    -- === Test 02: Start, limit and step from table fields ===
    sum = 0
    for i = cfg.first, cfg.last, cfg.step do sum = sum + i end
    number_result02 = sum                 -- 3 + 5 + 7 = 15

    -- === Test 03: Bounds from function results ===
    sum = 0
    for i = two(1), lim() + 2 do sum = sum + i end
    number_result03 = sum                 -- 2 + 3 + 4 + 5 + 6 = 20

    -- === Test 04: Float bounds in locals ===
    local fa, fb = 0.5, 2.75
    n = 0
    for i = fa, fb do n = n + 1 end
    number_result04 = n                   -- 0.5, 1.5, 2.5 = 3

    -- === Test 05: Negative step in a local ===
    local neg = -2
    sum = 0
    for i = 10, 1, neg do sum = sum + i end
    number_result05 = sum                 -- 10 + 8 + 6 + 4 + 2 = 30

    -- === Test 06: Negative variable step with a variable start and limit ===
    local from, to = 5, -5
    n = 0
    for i = from, to, -neg * -1 do n = n + 1 end   -- step = -2
    number_result06 = n                   -- 5 3 1 -1 -3 -5 = 6

    -- === Test 07: Float step in a global ===
    fstep = 0.25
    n = 0
    for i = 0, 1, fstep do n = n + 1 end
    number_result07 = n                   -- 5

    -- === Test 08: Bounds from arithmetic ===
    local m = 3
    sum = 0
    for i = m - 1, m * 2, m - 2 do sum = sum + i end
    number_result08 = sum                 -- 2 + 3 + 4 + 5 + 6 = 20

    -- === Test 09: Numeric strings are converted, as in Lua 5.4 ===
    local sl = "4"
    sum = 0
    for i = 1, sl do sum = sum + i end
    number_result09 = sum                 -- 10
    sum = 0
    for i = "2", 6, "2" do sum = sum + i end
    number_result10 = sum                 -- 2 + 4 + 6 = 12

    -- === Test 11: The bounds are evaluated once ===
    local calls = 0
    local function bound() calls = calls + 1; return 3 end
    n = 0
    for i = 1, bound() do n = n + 1 end
    number_result11 = calls * 10 + n      -- 13
    local limit = 3
    n = 0
    for i = 1, limit do limit = 10; n = n + 1 end
    number_result12 = n                   -- 3

    -- === Test 13: Zero iterations and one iteration with variable bounds ===
    local a, b = 5, 1
    n = 0
    for i = a, b do n = n + 1 end
    for i = b, b do n = n + 10 end
    number_result13 = n                   -- 10

    -- === Test 14: Nested loops with variable bounds ===
    n = 0
    for i = 1, hi do for j = i, hi do n = n + 1 end end
    number_result14 = n                   -- 5 + 4 + 3 + 2 + 1 = 15

    -- === Test 15: Variable bounds, break, and the loop variable after assignment ===
    sum = 0
    for i = lo, 100 do
        if i > hi then break end
        sum = sum + i
        i = 1000
    end
    number_result15 = sum                 -- 14
end

function main()
    test_variable_bounds()
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 14.0000
number_result01: 21.0000
number_result02: 15.0000
number_result03: 20.0000
number_result04: 3.0000
number_result05: 30.0000
number_result06: 6.0000
number_result07: 5.0000
number_result08: 20.0000
number_result09: 10.0000
number_result10: 12.0000
number_result11: 13.0000
number_result12: 3.0000
number_result13: 10.0000
number_result14: 15.0000
number_result15: 14.0000

--]]
