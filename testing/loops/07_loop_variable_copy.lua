--#title "v32lua numeric for loop variable unit test"
--@ Vircon32 Lua Numeric For Loop Variable Unit Test
--@ The visible loop variable is a copy of a hidden counter, refreshed at the top of
--@ every iteration (the compiler may say so to v32opt with `;@loop ... var=N`, only
--@ when nothing else writes it). Writes to it, closures, shadowing, break and goto
--@ must behave exactly as in Lua. Results are stored in global variables.

-- No closure here, no assignment to the loop variable: the plain case
function test_plain()
    local n = 0
    for i = 1, 10 do
        if i == 8 then break end
        if i % 3 == 0 then goto skip end
        n = n + i
        ::skip::
    end
    number_result00 = n                 -- 1 + 2 + 4 + 5 + 7 = 19

    n = 0
    for i = 9, 1, -2 do
        if i == 5 then goto c end
        n = n + i
        ::c::
        n = n + i * 100
    end
    number_result01 = n                 -- 20 + 2500 = 2520

    n = 0
    for i = 1, 3 do for j = i, 3 do n = n + i * 10 + j end end
    number_result02 = n                 -- 36 + 45 + 33 = 114
    local function f(x) return x + 1 end
    n = 0
    for i = 1, 5 do n = n + f(i) end
    number_result03 = n                 -- 20

    -- two loops in a row, then a local that reuses a loop's frame word
    n = 0
    for i = 1, 3 do n = n + i end
    for k = 1, 3 do local z = k * 7; n = n + z end
    local after = 5
    number_result04 = n + after         -- 6 + 42 + 5 = 53
end

-- Assignments to the loop variable, shadowing and closures
function test_variable()
    local n = 0
    for i = 1, 5 do i = i * 100; n = n + i end
    number_result05 = n                 -- 1500

    n = 0
    for i = 1, 5 do
        if i % 2 == 0 then do i = 0 end end
        n = n + i
    end
    number_result06 = n                 -- 1 + 0 + 3 + 0 + 5 = 9

    n = 0
    for i = 1, 4 do local i = i * 2; n = n + i end
    number_result07 = n                 -- 20

    n = 0
    for i = 1, 3 do for i = 10, 12 do n = n + i end; n = n + i end
    number_result08 = n                 -- 99 + 6 = 105

    n = 0
    for i = 1, 3 do local a, b = i, i * 2; i, a = a + b, 0; n = n + i end
    number_result09 = n                 -- 3 + 6 + 9 = 18

    local fs = {}
    for i = 1, 4 do fs[i] = function() return i end end
    number_result10 = fs[1]() * 1000 + fs[2]() * 100 + fs[3]() * 10 + fs[4]()   -- 1234

    local g = {}
    for i = 1, 3 do g[i] = function() i = i + 10; return i end end
    number_result11 = g[1]() + g[1]() + g[3]()   -- 11 + 21 + 13 = 45
end

function main()
    test_plain()
    test_variable()
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 19.0000
number_result01: 2520.0000
number_result02: 114.0000
number_result03: 20.0000
number_result04: 53.0000
number_result05: 1500.0000
number_result06: 9.0000
number_result07: 20.0000
number_result08: 105.0000
number_result09: 18.0000
number_result10: 1234.0000
number_result11: 45.0000

--]]
