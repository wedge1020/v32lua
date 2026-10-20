--@ Vircon32 Lua Bitwise Operators Unit Test (Lua 5.3/5.4 integer model)
--@ & | ~ << >> and unary ~ on numbers, with and without literal operands
--@ (literal-only expressions are folded at compile time; the others run
--@ through __builtin_bitop). Expected values are Lua 5.4's own results.
--@ Results are stored in global variables for automated memory scraping.

function test_bitwise()
    local a, b, n, m1, big = 0xF0F0, 0x0FF0, 4, -1, 0xFF
    local t = { x = 12 }
    -- === Test 00: a & b ===
    number_result00 = a & b

    -- === Test 01: a | b ===
    number_result01 = a | b

    -- === Test 02: a ~ b ===
    number_result02 = a ~ b

    -- === Test 03: ~0 ===
    number_result03 = ~0

    -- === Test 04: ~a ===
    number_result04 = ~a

    -- === Test 05: m1 & 0xFF ===
    number_result05 = m1 & 0xFF

    -- === Test 06: -256 & 0xFFFF ===
    number_result06 = -256 & 0xFFFF

    -- === Test 07: big << 24 ===
    number_result07 = big << 24

    -- === Test 08: 1 << n ===
    number_result08 = 1 << n

    -- === Test 09: a >> n ===
    number_result09 = a >> n

    -- === Test 10: a >> -n ===
    number_result10 = a >> -n

    -- === Test 11: a << -n ===
    number_result11 = a << -n

    -- === Test 12: m1 >> 0 ===
    number_result12 = m1 >> 0

    -- === Test 13: 1 | 2 & 3 ===
    number_result13 = 1 | 2 & 3

    -- === Test 14: 1 << 2 + 1 ===
    number_result14 = 1 << 2 + 1

    -- === Test 15: 6 ~ 3 | 8 ===
    number_result15 = 6 ~ 3 | 8

    -- === Test 16: 7.0 & 3 ===
    number_result16 = 7.0 & 3

    -- === Test 17: -5 & 7 ===
    number_result17 = -5 & 7

    -- === Test 18: ~m1 ===
    number_result18 = ~m1

    -- === Test 19: -1 ~ 0xFF ===
    number_result19 = -1 ~ 0xFF

    -- === Test 20: 0xFF00 & 0x0FF0 ===
    number_result20 = 0xFF00 & 0x0FF0

    -- === Test 21: ~5 ===
    number_result21 = ~5

    -- === Test 22: 3 << 2 ===
    number_result22 = 3 << 2

    -- === Test 23: 0x1.8 ===
    number_result23 = 0x1.8

    -- === Test 24: (n & 1) + (n | 1) * 2 ===
    number_result24 = (n & 1) + (n | 1) * 2

    -- === Test 25: t.x & 8 | 1 ===
    number_result25 = t.x & 8 | 1

    -- === Test 26: math.floor(9.5) & 3 ===
    number_result26 = math.floor(9.5) & 3

    -- === Test 27: packed fields (24-bit float32 limit) ===
    number_result27 = ((255 << 24) >> 24) + ((16 << 16) | (32 << 8) | 64)

    -- === Test 28: 0xFFFFFFFF >> 28 ===
    number_result28 = 0xFFFFFFFF >> 28

    -- === Test 29: (0x123456 >> 8) & 0xFF ===
    number_result29 = (0x123456 >> 8) & 0xFF
    boolean_result00 = 5 & 3 == 1
    boolean_result01 = (a & 0xF0) == 0xF0
end

function main()
    ioports.gpu.clear("black")
    test_bitwise()
    print(0, 0, "--- Bitwise Operators Test ---")
end


--[[
=== EXPECTED OUTPUT ===

number_result00: 240.0000
number_result01: 65520.0000
number_result02: 65280.0000
number_result03: -1.0000
number_result04: -61681.0000
number_result05: 255.0000
number_result06: 65280.0000
number_result07: 4278190080.0000
number_result08: 16.0000
number_result09: 3855.0000
number_result10: 986880.0000
number_result11: 3855.0000
number_result12: -1.0000
number_result13: 3.0000
number_result14: 8.0000
number_result15: 13.0000
number_result16: 3.0000
number_result17: 3.0000
number_result18: 0.0000
number_result19: -256.0000
number_result20: 3840.0000
number_result21: -6.0000
number_result22: 12.0000
number_result23: 1.5000
number_result24: 10.0000
number_result25: 9.0000
number_result26: 1.0000
number_result27: 1057087.0000
number_result28: 15.0000
number_result29: 52.0000
boolean_result00: true
boolean_result01: true

--]]
