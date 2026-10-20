--#title "v32lua powers, roots and exponentials unit test"
--@ Vircon32 Lua math unit test -- lib/math.lua half 4 of 4
--@ Exercises the power/exp/log group under its C names: sqrt, pow, exp,
--@ log. pow is probed in its integer-exponent, fractional-exponent and
--@ negative-exponent forms (the last being a division in float32 -- an
--@ easy place for a port to lose the sign or the fraction). log is the
--@ natural logarithm, exactly as in math.h -- there is no log10 alias
--@ in the C header, so none is tested; log(e) closing the loop back to
--@ 1.0000 exercises the float32 constant e = 2.7182818 end to end.

--#include "../../lib/math.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: sqrt ===
    number_sqrt_zero    = sqrt(0)     -- 0
    number_sqrt_two     = sqrt(2)     -- 1.4142
    number_sqrt_sixteen = sqrt(16)    -- 4
    number_sqrt_frac    = sqrt(0.25)  -- 0.5

    -- === Test 2: pow ===
    number_pow_ints   = pow(2, 10)    -- 1024
    number_pow_frac   = pow(9, 0.5)   -- 3 (square root via exponent)
    number_pow_negexp = pow(2, -2)    -- 0.25
    number_pow_ten    = pow(10, 3)    -- 1000

    -- === Test 3: exp ===
    number_exp_zero = exp(0)   -- 1
    number_exp_one  = exp(1)   -- e: 2.7183

    -- === Test 4: log (natural) ===
    number_log_one = log(1)          -- 0
    number_log_e   = log(2.7182818)  -- closes the exp loop: 1
    number_log_ten = log(10)         -- 2.3026

    print(10, 0,   "--- powers/roots/exponentials unit test ---")
    print(10, 20,  "sqrt(2)/sqrt(16): " .. number_sqrt_two
                   .. "/" .. number_sqrt_sixteen)
    print(10, 40,  "pow(2,10)/pow(9,0.5)/pow(2,-2): " .. number_pow_ints
                   .. "/" .. number_pow_frac
                   .. "/" .. number_pow_negexp)
    print(10, 60,  "exp(1)/log(e): " .. number_exp_one
                   .. "/" .. number_log_e)
end

--[[
=== EXPECTED OUTPUT ===

number_sqrt_zero: 0.0000
number_sqrt_two: 1.4142
number_sqrt_sixteen: 4.0000
number_sqrt_frac: 0.5000
number_pow_ints: 1024.0000
number_pow_frac: 3.0000
number_pow_negexp: 0.2500
number_pow_ten: 1000.0000
number_exp_zero: 1.0000
number_exp_one: 2.7183
number_log_one: 0.0000
number_log_e: 1.0000
number_log_ten: 2.3026

--]]
