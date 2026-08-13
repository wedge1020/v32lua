--@ Vircon32 Lua Math Log/Exp Unit Test
--@ Tests ONLY logarithmic and exponential math functions.
--@ Results stored in global variables for automated memory scraping.

function test_math_log_exp()
    -- === Test 1: math.exp() ===
    number_result1 = math.exp(0)    -- Expected: 1
    number_result2 = math.exp(1)    -- Expected: ~2.7183 (e)

    -- === Test 2: math.log() ===
    number_result3 = math.log(1)    -- Expected: 0
    number_result4 = math.log(math.e)  -- Expected: 1

    -- === Test 3: math.log10() ===
    number_result5 = math.log10(1)   -- Expected: 0
    number_result6 = math.log10(10)  -- Expected: 1
    number_result7 = math.log10(100) -- Expected: 2
end

function main()
    ioports.gpu.clear("black")
    test_math_log_exp()

    print(100, 00,  "--- Math Log/Exp Test ---")
    print(100, 20,  "exp(0): " .. number_result1)
    print(100, 40,  "exp(1): " .. number_result2)
    print(100, 60,  "log(1): " .. number_result3)
    print(100, 80,  "log(e): " .. number_result4)
    print(100, 100, "log10(1): " .. number_result5)
    print(100, 120, "log10(10): " .. number_result6)
    print(100, 140, "log10(100): " .. number_result7)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 1.0000
number_result2: 2.7183
number_result3: 0.0000
number_result4: 1.0000
number_result5: 0.0000
number_result6: 1.0000
number_result7: 2.0000
]]
