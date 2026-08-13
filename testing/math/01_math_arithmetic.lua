--@ Vircon32 Lua Math Arithmetic Unit Test
--@ Tests ONLY basic math arithmetic functions.
--@ Results stored in global variables for automated memory scraping.

function test_math_arithmetic()
    -- === Test 1: math.abs() ===
    number_result1 = math.abs(-5)    -- Expected: 5
    number_result2 = math.abs(3.14)  -- Expected: 3.14

    -- === Test 2: math.fmod() ===
    number_result3 = math.fmod(10, 3)   -- Expected: 1.0
    number_result4 = math.fmod(7.5, 2)  -- Expected: 1.5

    -- === Test 3: math.max() ===
    number_result5 = math.max(5, 10)     -- Expected: 10
    number_result6 = math.max(-1, -5)    -- Expected: -1

    -- === Test 4: math.min() ===
    number_result7 = math.min(5, 10)     -- Expected: 5
    number_result8 = math.min(-1, -5)    -- Expected: -5

    -- === Test 5: math.pow() ===
    number_result9 = math.pow(2, 3)      -- Expected: 8
    number_result10 = math.pow(4, 0.5)   -- Expected: 2

    -- === Test 6: math.sqrt() ===
    number_result11 = math.sqrt(16)     -- Expected: 4
    number_result12 = math.sqrt(2)      -- Expected: ~1.414213562
end

function main()
    ioports.gpu.clear("black")
    test_math_arithmetic()

    print(100, 00,  "--- Math Arithmetic Test ---")
    print(100, 20,  "abs(-5): " .. number_result1)
    print(100, 40,  "abs(3.14): " .. number_result2)
    print(100, 60,  "fmod(10,3): " .. number_result3)
    print(100, 80,  "fmod(7.5,2): " .. number_result4)
    print(100, 100, "max(5,10): " .. number_result5)
    print(100, 120, "max(-1,-5): " .. number_result6)
    print(100, 140, "min(5,10): " .. number_result7)
    print(100, 160, "min(-1,-5): " .. number_result8)
    print(100, 180, "pow(2,3): " .. number_result9)
    print(100, 200, "pow(4,0.5): " .. number_result10)
    print(100, 220, "sqrt(16): " .. number_result11)
    print(100, 240, "sqrt(2): " .. number_result12)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 5.0000
number_result2: 3.1400
number_result3: 1.0000
number_result4: 1.5000
number_result5: 10.0000
number_result6: -1.0000
number_result7: 5.0000
number_result8: -5.0000
number_result9: 8.0000
number_result10: 2.0000
number_result11: 4.0000
number_result12: 1.4142
]]
