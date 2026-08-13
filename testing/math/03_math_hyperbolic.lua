--@ Vircon32 Lua Math Hyperbolic Unit Test
--@ Tests ONLY hyperbolic math functions.
--@ Results stored in global variables for automated memory scraping.

function test_math_hyperbolic()
    -- === Test 1: math.sinh() ===
    number_result1 = math.sinh(0)    -- Expected: 0
    number_result2 = math.sinh(1)    -- Expected: ~1.1752

    -- === Test 2: math.cosh() ===
    number_result3 = math.cosh(0)    -- Expected: 1
    number_result4 = math.cosh(1)    -- Expected: ~1.5431

    -- === Test 3: math.tanh() ===
    number_result5 = math.tanh(0)    -- Expected: 0
    number_result6 = math.tanh(1)    -- Expected: ~0.7616
end

function main()
    ioports.gpu.clear("black")
    test_math_hyperbolic()

    print(100, 00,  "--- Math Hyperbolic Test ---")
    print(100, 20,  "sinh(0): " .. number_result1)
    print(100, 40,  "sinh(1): " .. number_result2)
    print(100, 60,  "cosh(0): " .. number_result3)
    print(100, 80,  "cosh(1): " .. number_result4)
    print(100, 100, "tanh(0): " .. number_result5)
    print(100, 120, "tanh(1): " .. number_result6)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 0.0000
number_result2: 1.1752
number_result3: 1.0000
number_result4: 1.5431
number_result5: 0.0000
number_result6: 0.7616
]]
