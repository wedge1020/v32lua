--#title "[v32lua] arithmetic operators unit test"
--@ Vircon32 Lua Arithmetic Operators Unit Test
--@ Tests +, -, *, /, %, ^, // (floordiv), unary minus, and operator
--@ precedence -- including the negative-number edge cases where Lua's
--@ floor-based semantics diverge from naive C-style truncation.
--@ Results are stored in global variables for automated memory scraping.

function test_arithmetic_operators()
    -- === Test 00: Basic exponent (^) ===
    number_result00 = 2 ^ 3          -- Expected: 8

    -- === Test 01: Exponent with fractional result ===
    number_result01 = 9 ^ 0.5        -- Expected: 3 (square root via ^)

    -- === Test 02: Exponent binds TIGHTER than unary minus ===
    -- Classic Lua gotcha: -2^2 is -(2^2) = -4, NOT (-2)^2 = 4
    number_result02 = -2 ^ 2         -- Expected: -4

    -- === Test 03: Exponent right-associativity ===
    -- 2^2^3 = 2^(2^3) = 2^8 = 256, NOT (2^2)^3 = 64
    number_result03 = 2 ^ 2 ^ 3      -- Expected: 256

    -- === Test 04: Floor division, positive operands ===
    number_result04 = 7 // 2         -- Expected: 3

    -- === Test 05: Floor division, negative dividend ===
    -- Lua // always floors (rounds toward -infinity), unlike C truncation.
    -- -7 // 2 = floor(-3.5) = -4, NOT -3.
    number_result05 = -7 // 2        -- Expected: -4

    -- === Test 06: Floor division, negative divisor ===
    number_result06 = 7 // -2        -- Expected: -4 (floor(-3.5))

    -- === Test 07: Floor division, both negative ===
    number_result07 = -7 // -2       -- Expected: 3 (floor(3.5))

    -- === Test 08: Modulo, positive operands ===
    number_result08 = 7 % 3          -- Expected: 1

    -- === Test 09: Modulo, negative dividend (Lua floor-mod, NOT C trunc-mod) ===
    -- In Lua: a % b == a - floor(a/b)*b
    -- -5 % 3 = -5 - floor(-5/3)*3 = -5 - (-2)*3 = -5 + 6 = 1
    -- A truncating (C-style) modulo would instead give -2 here.
    number_result09 = -5 % 3         -- Expected: 1

    -- === Test 10: Modulo, negative divisor ===
    -- 5 % -3 = 5 - floor(5/-3)*(-3) = 5 - (-2)*(-3) = 5 - 6 = -1
    number_result10 = 5 % -3         -- Expected: -1

    -- === Test 11: Modulo, both negative ===
    -- -5 % -3 = -5 - floor(-5/-3)*(-3) = -5 - 1*(-3) = -5 + 3 = -2
    number_result11 = -5 % -3        -- Expected: -2

    -- === Test 12: Unary minus on a variable ===
    local v = 42
    number_result12 = -v             -- Expected: -42

    -- === Test 13: Double unary minus ===
    number_result13 = -(-v)          -- Expected: 42

    -- === Test 14: Unary minus on an expression ===
    number_result14 = -(3 + 4)       -- Expected: -7

    -- === Test 15: Multiplication/division bind tighter than +/- ===
    number_result15 = 2 + 3 * 4      -- Expected: 14 (not 20)

    -- === Test 16: Mixed * and / share precedence, left-to-right ===
    number_result16 = 20 / 5 * 2     -- Expected: 8 (not 2)

    -- === Test 17: Parentheses override precedence ===
    number_result17 = (2 + 3) * 4    -- Expected: 20

    -- === Test 18: % shares precedence with * and / ===
    number_result18 = 10 - 7 % 3     -- Expected: 9  (7%3=1, 10-1=9)

    -- === Test 19: // shares precedence with * and / ===
    number_result19 = 1 + 7 // 2     -- Expected: 4  (7//2=3, 1+3=4)

    -- === Test 20: Float division always produces a float, even for exact division ===
    number_result20 = 10 / 2         -- Expected: 5 (still uses / not //)

    -- === Test 21: Chained addition/subtraction, left-associative ===
    number_result21 = 100 - 10 - 5   -- Expected: 85 (not 95)

    -- === Test 22: Combined unary and binary minus ===
    local a = 5
    local b = 3
    number_result22 = a - -b         -- Expected: 8 (5 - (-3))

    -- === Test 23: Exponent of zero ===
    number_result23 = 5 ^ 0          -- Expected: 1

    -- === Test 24: Negative exponent ===
    number_result24 = 2 ^ -1         -- Expected: 0.5
end

function main()
    ioports.gpu.clear("black")
    test_arithmetic_operators()

    print(000, 000, "--- Arithmetic Operators Test ---")
    print(000, 020, "Test 00 - 2^3: " ..          number_result00)
    print(000, 040, "Test 01 - 9^0.5: " ..        number_result01)
    print(000, 060, "Test 02 - -2^2: " ..         number_result02)
    print(000, 080, "Test 03 - 2^2^3: " ..        number_result03)
    print(000, 100, "Test 04 - 7//2: " ..         number_result04)
    print(000, 120, "Test 05 - -7//2: " ..        number_result05)
    print(000, 140, "Test 06 - 7//-2: " ..        number_result06)
    print(000, 160, "Test 07 - -7//-2: " ..       number_result07)
    print(000, 180, "Test 08 - 7%3: " ..          number_result08)
    print(000, 200, "Test 09 - -5%3: " ..         number_result09)
    print(000, 220, "Test 10 - 5%-3: " ..         number_result10)
    print(000, 240, "Test 11 - -5%-3: " ..        number_result11)
    print(000, 260, "Test 12 - Unary -v: " ..     number_result12)
    print(200, 020, "Test 13 - --v: " ..          number_result13)
    print(200, 040, "Test 14 - -(3+4): " ..       number_result14)
    print(200, 060, "Test 15 - 2+3*4: " ..        number_result15)
    print(200, 080, "Test 16 - 20/5*2: " ..       number_result16)
    print(200, 100, "Test 17 - (2+3)*4: " ..      number_result17)
    print(200, 120, "Test 18 - 10-7%3: " ..       number_result18)
    print(200, 140, "Test 19 - 1+7//2: " ..       number_result19)
    print(200, 160, "Test 20 - 10/2: " ..         number_result20)
    print(200, 180, "Test 21 - 100-10-5: " ..     number_result21)
    print(200, 200, "Test 22 - a - -b: " ..       number_result22)
    print(200, 220, "Test 23 - 5^0: " ..          number_result23)
    print(200, 240, "Test 24 - 2^-1: " ..         number_result24)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 8.0000
number_result01: 3.0000
number_result02: -4.0000
number_result03: 256.0000
number_result04: 3.0000
number_result05: -4.0000
number_result06: -4.0000
number_result07: 3.0000
number_result08: 1.0000
number_result09: 1.0000
number_result10: -1.0000
number_result11: -2.0000
number_result12: -42.0000
number_result13: 42.0000
number_result14: -7.0000
number_result15: 14.0000
number_result16: 8.0000
number_result17: 20.0000
number_result18: 9.0000
number_result19: 4.0000
number_result20: 5.0000
number_result21: 85.0000
number_result22: 8.0000
number_result23: 1.0000
number_result24: 0.5000

--]]
