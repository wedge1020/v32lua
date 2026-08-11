--@ Vircon32 Lua Math Trigonometry Unit Test
--@ Tests ONLY trigonometric math functions.
--@ Results stored in global variables for automated memory scraping.

function test_math_trigonometry()
    -- === Test 1: math.sin() ===
    number_result1 = math.sin(0)       -- Expected: 0
    number_result2 = math.sin(math.pi/2)  -- Expected: 1

    -- === Test 2: math.cos() ===
    number_result3 = math.cos(0)       -- Expected: 1
    number_result4 = math.cos(math.pi)   -- Expected: -1

    -- === Test 3: math.tan() ===
    number_result5 = math.tan(0)       -- Expected: 0
    number_result6 = math.tan(math.pi/4) -- Expected: ~1

    -- === Test 4: math.asin() ===
    number_result7 = math.asin(0)     -- Expected: 0
    number_result8 = math.asin(1)     -- Expected: ~1.5708 (pi/2)

    -- === Test 5: math.acos() ===
    number_result9 = math.acos(1)     -- Expected: 0
    number_result10 = math.acos(0)    -- Expected: ~1.5708 (pi/2)

    -- === Test 6: math.atan() ===
    number_result11 = math.atan(0)    -- Expected: 0
    number_result12 = math.atan(1)    -- Expected: ~0.7854 (pi/4)

    -- === Test 7: math.atan2() ===
    number_result13 = math.atan2(1, 1)  -- Expected: ~0.7854 (pi/4)
    number_result14 = math.atan2(0, 1)  -- Expected: 0

    -- === Test 8: math.deg() ===
    number_result15 = math.deg(0)      -- Expected: 0
    number_result16 = math.deg(math.pi) -- Expected: 180

    -- === Test 9: math.rad() ===
    number_result17 = math.rad(0)      -- Expected: 0
    number_result18 = math.rad(180)    -- Expected: ~3.14159 (pi)
end

function main()
    ioports.gpu.clear("black")
    test_math_trigonometry()

    print(100, 00,  "--- Math Trigonometry Test ---")
    print(100, 20,  "sin(0): " .. number_result1)
    print(100, 40,  "sin(pi/2): " .. number_result2)
    print(100, 60,  "cos(0): " .. number_result3)
    print(100, 80,  "cos(pi): " .. number_result4)
    print(100, 100, "tan(0): " .. number_result5)
    print(100, 120, "tan(pi/4): " .. number_result6)
    print(100, 140, "asin(0): " .. number_result7)
    print(100, 160, "asin(1): " .. number_result8)
    print(100, 180, "acos(1): " .. number_result9)
    print(100, 200, "acos(0): " .. number_result10)
    print(100, 220, "atan(0): " .. number_result11)
    print(100, 240, "atan(1): " .. number_result12)
    print(100, 260, "atan2(1,1): " .. number_result13)
    print(100, 280, "atan2(0,1): " .. number_result14)
    print(100, 300, "deg(0): " .. number_result15)
    print(100, 320, "deg(pi): " .. number_result16)
    print(100, 340, "rad(0): " .. number_result17)
    print(100, 360, "rad(180): " .. number_result18)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
number_result1: 0
number_result2: 1
number_result3: 1
number_result4: -1
number_result5: 0
number_result6: ~1.0
number_result7: 0
number_result8: ~1.5708
number_result9: 0
number_result10: ~1.5708
number_result11: 0
number_result12: ~0.7854
number_result13: ~0.7854
number_result14: 0
number_result15: 0
number_result16: 180
number_result17: 0
number_result18: ~3.14159
]]
