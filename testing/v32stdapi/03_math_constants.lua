--#title "v32lua math constants and min/max/abs unit test"
--@ Vircon32 Lua math unit test -- lib/math.lua half 1 of 4
--@ Exercises the C-style bare-name aliases of v32lua's math.* intrinsics
--@ for the constant and selection group: pi, INT_MIN, INT_MAX, min, max,
--@ abs. Every alias is a pure passthrough, so the values here also
--@ double as a check that the alias names resolve and forward their
--@ arguments in the C positions (max(a, b), not Lua's table spelling).
--@ NOTE on the two int constants, both scraped values come out as
--@ 2147483648.0000 and that is NOT a copy/paste error: v32lua numbers
--@ are 32-bit floats with a 24-bit mantissa, so INT_MIN's literal
--@ 0x80000000 is the exactly-representable +2^31, and INT_MAX's
--@ 2147483647 rounds UP to that same 2^31 -- one ulp of the float32
--@ number model, kept visible here on purpose. (math.h's own parsers
--@ have the mirror-image quirk: they refuse a bare "-2147483648"
--@ literal, which is why INT_MIN is spelled 0x80000000 there too.)

--#include "../../lib/math.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: constants ===
    number_pi_val      = pi          -- 3.1415926, prints at 4 decimals
    number_int_min_val = INT_MIN     -- 0x80000000 -> exactly 2^31 as a float32
    number_int_max_val = INT_MAX     -- 2147483647 -> rounds to 2^31 in float32

    -- === Test 2: min -- smaller of two, ints, negatives, fractions ===
    number_min_ints   = min(3, 7)      -- 3
    number_min_negs   = min(-3, -7)    -- -7
    number_min_fracs  = min(2.5, 2.4)  -- 2.4
    number_min_mixed  = min(-2, 2.5)   -- -2

    -- === Test 3: max -- larger of two ===
    number_max_ints   = max(3, 7)      -- 7
    number_max_negs   = max(-3, -7)    -- -3
    number_max_fracs  = max(2.5, 2.4)  -- 2.5
    number_max_mixed  = max(-2, 2.5)   -- 2.5

    -- === Test 4: abs ===
    number_abs_neg   = abs(-5)    -- 5
    number_abs_pos   = abs(5)     -- 5
    number_abs_frac  = abs(-2.5)  -- 2.5
    number_abs_zero  = abs(0)     -- 0

    print(10, 0,   "--- math constants/min/max/abs unit test ---")
    print(10, 20,  "pi: " .. number_pi_val)
    print(10, 40,  "INT_MIN/INT_MAX (both 2^31 in float32): " .. number_int_min_val
                   .. "/" .. number_int_max_val)
    print(10, 60,  "min(-3,-7)/max(-3,-7): " .. number_min_negs
                   .. "/" .. number_max_negs)
    print(10, 80,  "abs(-2.5): " .. number_abs_frac)
end

--[[
=== EXPECTED OUTPUT ===

number_pi_val: 3.1416
number_int_min_val: 2147483648.0000
number_int_max_val: 2147483648.0000
number_min_ints: 3.0000
number_min_negs: -7.0000
number_min_fracs: 2.4000
number_min_mixed: -2.0000
number_max_ints: 7.0000
number_max_negs: -3.0000
number_max_fracs: 2.5000
number_max_mixed: 2.5000
number_abs_neg: 5.0000
number_abs_pos: 5.0000
number_abs_frac: 2.5000
number_abs_zero: 0.0000

--]]
