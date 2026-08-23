--#title "[v32lua] math arithmetic unit test"
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

    -- === Test 7: math.fmod() vs the % operator -- these are DIFFERENT ===
    -- === operations in Lua and must give DIFFERENT answers for operands ===
    -- === with opposite signs. math.fmod() is C-style TRUNCATING modulo ===
    -- === (uses the Vircon32 FMOD instruction directly); % is FLOOR modulo ===
    -- === (a % b == a - floor(a/b)*b). This is a regression guard against ===
    -- === the two accidentally sharing one implementation again -- that ===
    -- === exact bug (% was wrongly implemented via truncating int IMOD) ===
    -- === was found and fixed via 09_arithmetic_operators.lua in basic/. ===

    -- --- Opposite-sign operands: fmod and % MUST disagree ---
    number_result13 = math.fmod(-5, 3)   -- Expected: -2  (truncating)
    number_result14 = -5 % 3             -- Expected: 1   (flooring)
    boolean_result13 = (number_result13 ~= number_result14)  -- Expected: true

    number_result15 = math.fmod(5, -3)   -- Expected: 2   (truncating)
    number_result16 = 5 % -3             -- Expected: -1  (flooring)
    boolean_result14 = (number_result15 ~= number_result16)  -- Expected: true

    -- --- Same-sign operands: fmod and % happen to AGREE here -- this is ---
    -- --- the case that let the bug hide before, so it's included as a ---
    -- --- sanity check that the fix didn't overcorrect and break the ---
    -- --- case where they're SUPPOSED to match. ---
    number_result17 = math.fmod(-5, -3)  -- Expected: -2
    number_result18 = -5 % -3            -- Expected: -2
    boolean_result15 = (number_result17 == number_result18)  -- Expected: true

    number_result19 = math.fmod(5, 3)    -- Expected: 2
    number_result20 = 5 % 3              -- Expected: 2
    boolean_result16 = (number_result19 == number_result20)  -- Expected: true
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
    print(100, 260, "fmod(-5,3): " .. number_result13)
    print(100, 280, "-5 % 3: " .. number_result14)
    print(100, 300, "fmod != mod (opp sign): " .. tostring(boolean_result13))
    print(320, 020, "fmod(5,-3): " .. number_result15)
    print(320, 040, "5 % -3: " .. number_result16)
    print(320, 060, "fmod != mod (opp sign): " .. tostring(boolean_result14))
    print(320, 080, "fmod(-5,-3): " .. number_result17)
    print(320, 100, "-5 % -3: " .. number_result18)
    print(320, 120, "fmod == mod (same sign): " .. tostring(boolean_result15))
    print(320, 140, "fmod(5,3): " .. number_result19)
    print(320, 160, "5 % 3: " .. number_result20)
    print(320, 180, "fmod == mod (same sign): " .. tostring(boolean_result16))
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
number_result13: -2.0000
number_result14: 1.0000
boolean_result13: true
number_result15: 2.0000
number_result16: -1.0000
boolean_result14: true
number_result17: -2.0000
number_result18: -2.0000
boolean_result15: true
number_result19: 2.0000
number_result20: 2.0000
boolean_result16: true
]]
