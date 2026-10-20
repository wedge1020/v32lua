--#title "v32lua rounding and fmod unit test"
--@ Vircon32 Lua math unit test -- lib/math.lua half 2 of 4
--@ Exercises the rounding/remainder group under their C names:
--@ fmin, fmax, fabs, floor, ceil and fmod. The int/float distinction
--@ of the C header (min/max/abs vs fmin/fmax/fabs) collapses onto the
--@ same intrinsics in v32lua, so the float-flavored names are checked
--@ with float operands here to confirm they forward correctly. fmod
--@ gets the full sign-matrix treatment: the C remainder takes the
--@ sign of the DIVIDEND (fmod(-7, 3) is -1, fmod(7, -3) is 1), which
--@ is what separates it from Lua's %-as-floored-mod convention.
--@ math.h's round() is deliberately NOT ported (no math.round
--@ intrinsic exists, and floor(x+0.5) diverges from the hardware
--@ ROUND instruction on negatives) -- nothing to test for it here.

--#include "../../lib/math.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: fmin / fmax -- float-flavored aliases ===
    number_fmin_fracs = fmin(2.5, 3.5)    -- 2.5
    number_fmin_negs  = fmin(-1, -2)      -- -2
    number_fmax_negs  = fmax(-1, -2)      -- -1
    number_fmax_fracs = fmax(1.5, 2.75)   -- 2.75

    -- === Test 2: fabs ===
    number_fabs_neg = fabs(-3.25)   -- 3.25
    number_fabs_pos = fabs(3.25)    -- 3.25

    -- === Test 3: floor -- toward negative infinity ===
    number_floor_pos   = floor(2.7)   -- 2
    number_floor_neg   = floor(-2.5)  -- -3 (NOT -2: floors, not truncates)
    number_floor_exact = floor(5)     -- 5 (already integral)

    -- === Test 4: ceil -- toward positive infinity ===
    number_ceil_pos   = ceil(2.1)   -- 3
    number_ceil_neg   = ceil(-2.5)  -- -2
    number_ceil_exact = ceil(5)     -- 5

    -- === Test 5: fmod -- remainder with the dividend's sign ===
    number_fmod_pos    = fmod(7, 3)     -- 1
    number_fmod_neg    = fmod(-7, 3)    -- -1 (sign of the dividend)
    number_fmod_negdiv = fmod(7, -3)    -- 1 (still the dividend's sign)
    number_fmod_frac   = fmod(7.5, 2)   -- 1.5
    number_fmod_exact  = fmod(8, 4)     -- 0

    print(10, 0,   "--- rounding/fmod unit test ---")
    print(10, 20,  "floor(-2.5)/ceil(-2.5): " .. number_floor_neg
                   .. "/" .. number_ceil_neg)
    print(10, 40,  "fmod(7,3)/fmod(-7,3)/fmod(7,-3): " .. number_fmod_pos
                   .. "/" .. number_fmod_neg
                   .. "/" .. number_fmod_negdiv)
    print(10, 60,  "fmin(2.5,3.5)/fmax(1.5,2.75): " .. number_fmin_fracs
                   .. "/" .. number_fmax_fracs)
end

--[[
=== EXPECTED OUTPUT ===

number_fmin_fracs: 2.5000
number_fmin_negs: -2.0000
number_fmax_negs: -1.0000
number_fmax_fracs: 2.7500
number_fabs_neg: 3.2500
number_fabs_pos: 3.2500
number_floor_pos: 2.0000
number_floor_neg: -3.0000
number_floor_exact: 5.0000
number_ceil_pos: 3.0000
number_ceil_neg: -2.0000
number_ceil_exact: 5.0000
number_fmod_pos: 1.0000
number_fmod_neg: -1.0000
number_fmod_negdiv: 1.0000
number_fmod_frac: 1.5000
number_fmod_exact: 0.0000

--]]
