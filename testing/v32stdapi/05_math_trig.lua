--#title "v32lua trigonometry unit test"
--@ Vircon32 Lua math unit test -- lib/math.lua half 3 of 4
--@ Exercises the trigonometric group under its C names: sin, cos, tan,
--@ asin, acos, atan2. All angles are in radians, same as the C header
--@ and v32lua's math.* (there is no degrees mode anywhere in the chain).
--@ The identity angles use the lib's own pi constant (a float32
--@ 3.1415926), which is exactly what ported C code would hand them;
--@ the quarter/half identities still land on their exact values at
--@ the harness's 4-decimal scrape precision. atan2 keeps the C
--@ argument order atan2(y, x) -- the port would silently produce
--@ wrong quadrants if it ever swapped them, so the third-quadrant
--@ case (both arguments negative) is included as the swap detector.

--#include "../../lib/math.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: sin ===
    number_sin_zero    = sin(0)        -- 0
    number_sin_halfpi  = sin(pi / 2)   -- 1
    number_sin_half    = sin(0.5)      -- 0.4794

    -- === Test 2: cos ===
    number_cos_zero  = cos(0)      -- 1
    number_cos_pi    = cos(pi)     -- -1
    number_cos_half  = cos(0.5)    -- 0.8776

    -- === Test 3: tan ===
    number_tan_zero   = tan(0)        -- 0
    number_tan_quart  = tan(pi / 4)   -- 1
    number_tan_half   = tan(0.5)      -- 0.5463

    -- === Test 4: inverse trig ===
    number_asin_one   = asin(1)     -- pi/2: 1.5708
    number_asin_half  = asin(0.5)   -- 0.5236
    number_acos_one   = acos(1)     -- 0
    number_acos_half  = acos(0.5)   -- 1.0472

    -- === Test 5: atan2 -- C order is atan2(y, x) ===
    number_atan2_north = atan2(1, 0)     -- pi/2: 1.5708
    number_atan2_diag  = atan2(1, 1)     -- pi/4: 0.7854
    number_atan2_sw    = atan2(-1, -1)   -- -3*pi/4: -2.3562 (third quadrant, swap detector)

    print(10, 0,   "--- trigonometry unit test ---")
    print(10, 20,  "sin(pi/2)/cos(pi): " .. number_sin_halfpi
                   .. "/" .. number_cos_pi)
    print(10, 40,  "tan(pi/4): " .. number_tan_quart)
    print(10, 60,  "asin(0.5)/acos(0.5): " .. number_asin_half
                   .. "/" .. number_acos_half)
    print(10, 80,  "atan2(1,1)/atan2(-1,-1): " .. number_atan2_diag
                   .. "/" .. number_atan2_sw)
end

--[[
=== EXPECTED OUTPUT ===

number_sin_zero: 0.0000
number_sin_halfpi: 1.0000
number_sin_half: 0.4794
number_cos_zero: 1.0000
number_cos_pi: -1.0000
number_cos_half: 0.8776
number_tan_zero: 0.0000
number_tan_quart: 1.0000
number_tan_half: 0.5463
number_asin_one: 1.5708
number_asin_half: 0.5236
number_acos_one: 0.0000
number_acos_half: 1.0472
number_atan2_north: 1.5708
number_atan2_diag: 0.7854
number_atan2_sw: -2.3562

--]]
