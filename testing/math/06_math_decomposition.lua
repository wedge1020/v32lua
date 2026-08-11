--@ Vircon32 Lua Math Decomposition Unit Test
--@ Tests ONLY decomposition math functions (frexp, ldexp, modf).
--@ Results stored in global variables for automated memory scraping.

function test_math_decomposition()
    -- === Test 1: math.modf() ===
    local int1, frac1 = math.modf(3.7)
    number_result1 = int1    -- Expected: 3
    number_result2 = frac1   -- Expected: 0.7

    local int2, frac2 = math.modf(-2.3)
    number_result3 = int2    -- Expected: -2
    number_result4 = frac2   -- Expected: -0.3

    -- === Test 2: math.frexp() ===
    local mant1, exp1 = math.frexp(8)
    number_result5 = mant1   -- Expected: 0.5
    number_result6 = exp1    -- Expected: 4 (2^4 = 16, but 0.5*16=8)

    -- === Test 3: math.ldexp() ===
    number_result7 = math.ldexp(0.5, 4)  -- Expected: 8 (0.5 * 2^4)
    number_result8 = math.ldexp(1.0, 3)  -- Expected: 8 (1.0 * 2^3)
end

function main()
    ioports.gpu.clear("black")
    test_math_decomposition()

    print(100, 00,  "--- Math Decomposition Test ---")
    print(100, 20,  "modf(3.7) int: " .. number_result1)
    print(100, 40,  "modf(3.7) frac: " .. number_result2)
    print(100, 60,  "modf(-2.3) int: " .. number_result3)
    print(100, 80,  "modf(-2.3) frac: " .. number_result4)
    print(100, 100, "frexp(8) mant: " .. number_result5)
    print(100, 120, "frexp(8) exp: " .. number_result6)
    print(100, 140, "ldexp(0.5,4): " .. number_result7)
    print(100, 160, "ldexp(1.0,3): " .. number_result8)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
number_result1: 3
number_result2: 0.7
number_result3: -2
number_result4: -0.3
number_result5: 0.5
number_result6: 4
number_result7: 8
number_result8: 8
]]
