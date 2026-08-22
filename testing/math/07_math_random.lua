--@ Vircon32 Lua Math Random Unit Test
--@ Tests ONLY random math functions.
--@ Results stored in global variables for automated memory scraping.

function test_math_random()
    -- === Test 1: math.randomseed() ===
    math.randomseed(42)  -- Seed with fixed value for reproducibility

    -- === Test 2: math.random() no args ===
    number_result1 = math.random()  -- Expected: float in [0, 1)

    -- === Test 3: math.random(n) ===
    number_result2 = math.random(10)  -- Expected: integer in [1, 10]

    -- === Test 4: math.random(m, n) ===
    number_result3 = math.random(5, 10)  -- Expected: integer in [5, 10]

    -- === Test 5: Re-seed and verify different sequence ===
    math.randomseed(123)
    number_result4 = math.random(100)  -- Expected: different from above
end

function main()
    ioports.gpu.clear("black")
    test_math_random()

    print(100, 00,  "--- Math Random Test ---")
    print(100, 20,  "random(): " .. number_result1)
    print(100, 40,  "random(10): " .. number_result2)
    print(100, 60,  "random(5,10): " .. number_result3)
    print(100, 80,  "random(100): " .. number_result4)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 0.0000
number_result2: 4.0000
number_result3: 6.0000
number_result4: 62.0000
]]
