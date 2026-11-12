--#title "v32lua unary minus on literals unit test"
--@ Vircon32 Lua Unary Minus Unit Test
--@ A minus sign before a number literal gives the negated literal at compile
--@ time (no __builtin_unm call); -x, -"2" and -(a + b) are still computed at
--@ run time. Raw words (negative zero) are checked in hex_ globals.
--@ Results are stored in global variables for automated memory scraping.

function test_unary_minus_literals()
    local x, z, y = 5, 0, -2
    local t = {}

    -- === Literals, parentheses, double negation ===
    number_result00 = -1                -- -1
    number_result01 = - -1              -- 1
    number_result02 = -(2)              -- -2
    number_result03 = -(-(3))           -- 3
    number_result04 = -0.5              -- -0.5
    number_result05 = -0xFF             -- -255

    -- === Not literals: still computed at run time ===
    number_result06 = -x                -- -5
    number_result07 = -"2"              -- -2 (numeric string)
    number_result08 = -(x + 1)          -- -6
    number_result09 = - -x              -- 5

    -- === Inside expressions ===
    number_result10 = 5 - -3            -- 8
    number_result11 = 2 * -3.5          -- -7
    number_result12 = -2 ^ 2            -- -4 (the power binds tighter)
    number_result13 = 2 ^ -1            -- 0.5
    number_result14 = -7 % 3            -- 2
    number_result15 = -7 // 2           -- -4
    number_result16 = 1 / -4            -- -0.25
    number_result17 = x ^ -1            -- 0.2
    number_result18 = math.abs(-3)      -- 3
    number_result19 = math.max(-1, -2)  -- -1
    number_result20 = math.floor(-1.5)  -- -2

    -- === Comparisons against a negative literal ===
    boolean_result00 = (y == -2)        -- true
    boolean_result01 = (x == -5)        -- false
    boolean_result02 = (y < -1)         -- true
    boolean_result03 = (-1 < y)         -- false
    boolean_result04 = (-0 == z)        -- true

    -- === Negative keys ===
    t[-1] = 7
    number_result21 = t[-1]             -- 7
    local u = {[-1] = 9, [-2] = 4}
    number_result22 = u[-1] + u[-2]     -- 13

    -- === Text ===
    string_result00 = (-1) .. ""        -- "-1"

    -- === Raw words: the sign bit of zero is kept ===
    hex_result00 = -0                   -- negative zero, as the runtime call made it
    hex_result01 = -(0)
    hex_result02 = -z                   -- run time: also negative zero
    hex_result03 = -1                   -- -1.0
    hex_result04 = - -0                 -- +0.0
end

function main()
    test_unary_minus_literals()
end

--[[
=== EXPECTED OUTPUT ===

number_result00: -1.0000
number_result01: 1.0000
number_result02: -2.0000
number_result03: 3.0000
number_result04: -0.5000
number_result05: -255.0000
number_result06: -5.0000
number_result07: -2.0000
number_result08: -6.0000
number_result09: 5.0000
number_result10: 8.0000
number_result11: -7.0000
number_result12: -4.0000
number_result13: 0.5000
number_result14: 2.0000
number_result15: -4.0000
number_result16: -0.2500
number_result17: 0.2000
number_result18: 3.0000
number_result19: -1.0000
number_result20: -2.0000
boolean_result00: true
boolean_result01: false
boolean_result02: true
boolean_result03: false
boolean_result04: true
number_result21: 7.0000
number_result22: 13.0000
string_result00: "-1"
hex_result00: 0x80000000
hex_result01: 0x80000000
hex_result02: 0x80000000
hex_result03: 0xBF800000
hex_result04: 0x00000000

--]]
