--@ Vircon32 Lua Math Rounding Unit Test
--@ Tests ONLY rounding math functions.
--@ Results stored in global variables for automated memory scraping.

function test_math_rounding()
    -- === Test 1: math.floor() ===
    number_result1 = math.floor(3.7)    -- Expected: 3
    number_result2 = math.floor(-2.3)   -- Expected: -3

    -- === Test 2: math.ceil() ===
    number_result3 = math.ceil(3.2)    -- Expected: 4
    number_result4 = math.ceil(-2.7)   -- Expected: -2
end

function main()
    ioports.gpu.clear("black")
    test_math_rounding()

    print(100, 00,  "--- Math Rounding Test ---")
    print(100, 20,  "floor(3.7): " .. number_result1)
    print(100, 40,  "floor(-2.3): " .. number_result2)
    print(100, 60,  "ceil(3.2): " .. number_result3)
    print(100, 80,  "ceil(-2.7): " .. number_result4)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 3.0000
number_result2: -3.0000
number_result3: 4.0000
number_result4: -2.0000
]]
