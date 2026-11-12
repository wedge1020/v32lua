--#title "v32lua negative literal step loops unit test"
--@ Vircon32 Lua Numeric For Loops with Negative Literals Unit Test
--@ `-1`, `-(2)` and `- -3` are number literals: a literal step compiles to the
--@ short constant-step loop (exit test "control < limit" for a negative step).
--@ Results are stored in global variables for automated memory scraping.

function test_negative_step_loops()
    -- === Test 00: Countdown, sum ===
    local s = 0
    for i = 10, 1, -1 do s = s + i end
    number_result00 = s                 -- 55

    -- === Test 01: Countdown, last value seen ===
    local last = 0
    for i = 10, 1, -1 do last = i end
    number_result01 = last              -- 1

    -- === Test 02: Step -2 ===
    s = 0
    for i = 5, 1, -2 do s = s + i end
    number_result02 = s                 -- 5 + 3 + 1 = 9

    -- === Test 03: Negative start and limit, step -1 ===
    s = 0
    for i = -1, -5, -1 do s = s + i end
    number_result03 = s                 -- -15

    -- === Test 04: Count across zero ===
    local n = 0
    for i = 3, -3, -1 do n = n + 1 end
    number_result04 = n                 -- 7

    -- === Test 05: Negative start, default step ===
    s, n = 0, 0
    for i = -3, 3 do s = s + i; n = n + 1 end
    number_result05 = n                 -- 7
    number_result06 = s                 -- 0

    -- === Test 07: Negative limit only ===
    s = 0
    for i = 0, -2, -1 do s = s + i end
    number_result07 = s                 -- -3

    -- === Test 08: Fractional negative step ===
    s, n = 0, 0
    for i = 1, 0, -0.25 do s = s + i; n = n + 1 end
    number_result08 = n                 -- 5
    number_result09 = s                 -- 2.5

    -- === Test 10: Step that "%f" would round (six decimals) ===
    n = 0
    for i = 0, -1, -0.1234567 do n = n + 1 end
    number_result10 = n                 -- 9 (0 down to -0.9876536)

    -- === Test 11: Double negation and parentheses in the step ===
    s = 0
    for i = 1, 3, - -1 do s = s + i end
    number_result11 = s                 -- step +1: 6
    s = 0
    for i = 3, 1, -(1) do s = s + i end
    number_result12 = s                 -- step -1: 6
    s = 0
    for i = 3, 1, (-1) do s = s + i end
    number_result13 = s                 -- 6

    -- === Test 14: A countdown that never runs, and one that runs once ===
    n = 0
    for i = 1, 10, -1 do n = n + 1 end
    number_result14 = n                 -- 0
    n = 0
    for i = 5, 5, -1 do n = n + 1 end
    number_result15 = n                 -- 1

    -- === Test 16: Nested countdowns ===
    n = 0
    for i = 3, 1, -1 do
        for j = i, 1, -1 do n = n + 1 end
    end
    number_result16 = n                 -- 3 + 2 + 1 = 6

    -- === Test 17: break in a countdown ===
    last = 0
    for i = 10, 1, -1 do
        last = i
        if i == 7 then break end
    end
    number_result17 = last              -- 7

    -- === Test 18: goto continue in a countdown ===
    s = 0
    for i = 6, 1, -1 do
        if i % 2 == 1 then goto continue end
        s = s + i
        ::continue::
    end
    number_result18 = s                 -- 6 + 4 + 2 = 12

    -- === Test 19: Closures capture each iteration's value ===
    local fs = {}
    for i = 3, 1, -1 do fs[#fs + 1] = function() return i end end
    number_result19 = fs[1]() * 100 + fs[2]() * 10 + fs[3]()   -- 321

    -- === Test 20: Assigning the loop variable does not change the loop ===
    n = 0
    for i = 5, 1, -1 do i = i * 10; n = n + 1 end
    number_result20 = n                 -- 5

    -- === Test 21: A step held in a variable still works ===
    local step = -1
    s = 0
    for i = 4, 1, step do s = s + i end
    number_result21 = s                 -- 10
end

function main()
    test_negative_step_loops()
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 55.0000
number_result01: 1.0000
number_result02: 9.0000
number_result03: -15.0000
number_result04: 7.0000
number_result05: 7.0000
number_result06: 0.0000
number_result07: -3.0000
number_result08: 5.0000
number_result09: 2.5000
number_result10: 9.0000
number_result11: 6.0000
number_result12: 6.0000
number_result13: 6.0000
number_result14: 0.0000
number_result15: 1.0000
number_result16: 6.0000
number_result17: 7.0000
number_result18: 12.0000
number_result19: 321.0000
number_result20: 5.0000
number_result21: 10.0000

--]]
