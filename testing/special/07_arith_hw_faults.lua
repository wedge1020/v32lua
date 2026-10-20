--@ Vircon32 Lua Arithmetic Hardware-Fault Unit Test
--@ The Vircon32 CPU raises a hardware error (a system fault screen) for
--@ FDIV/FMOD by zero, ATAN2(0, 0), ACOS outside [-1, 1], LOG of x <= 0 and
--@ POW of a negative base by a non-integer exponent. Lua's answers there
--@ are +-inf or NaN, which NaN-boxing can't carry, so each is given a safe
--@ value instead: x % 0 = 0, x // 0 = +-huge, fmod(x, 0) = 0,
--@ atan2(0, 0) = 0, acos clamps, log(x <= 0) = -huge, (-8)^0.5 = 0.
--@ Results are stored in global variables for automated memory scraping.

function main()
    local zero = 0
    local neg  = -8

    -- === Test 00: modulo and floor division by zero ===
    number_result00a = 7 % zero
    number_result00b = -7 % 3
    boolean_result00c = (7 // zero) == math.huge
    boolean_result00d = (-7 // zero) == -math.huge
    number_result00e = -7 // 2
    __rawasm__("__debug0:")

    -- === Test 01: math.fmod by zero, function value too ===
    number_result01a = math.fmod(7, zero)
    number_result01b = math.fmod(7, 3)
    local fm = math.fmod
    number_result01c = fm(7, zero)
    __rawasm__("__debug1:")

    -- === Test 02: powers with a negative base ===
    number_result02a = neg ^ 0.5
    number_result02b = neg ^ 2
    number_result02c = neg ^ (1 + zero)
    number_result02d = math.pow(neg, 1.5)
    local pw = math.pow
    number_result02e = pw(neg, 1.5)
    number_result02f = pw(2, 10)
    number_result02g = math.sqrt(-4)
    __rawasm__("__debug2:")

    -- === Test 03: atan2, acos, log at the edges ===
    number_result03a = math.atan2(zero, zero)
    number_result03b = math.acos(1.0000001)
    boolean_result03c = math.abs(math.acos(-1.5) - math.pi) < 0.0001
    boolean_result03d = math.log(zero) == -math.huge
    boolean_result03e = math.log10(zero) == -math.huge
    number_result03f = math.log10(100)
    __rawasm__("__debug3:")
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 0.0000
number_result00b: 2.0000
boolean_result00c: true
boolean_result00d: true
number_result00e: -4.0000
number_result01a: 0.0000
number_result01b: 1.0000
number_result01c: 0.0000
number_result02a: 0.0000
number_result02b: 64.0000
number_result02c: -8.0000
number_result02d: 0.0000
number_result02e: 0.0000
number_result02f: 1024.0000
number_result02g: 0.0000
number_result03a: 0.0000
number_result03b: 0.0000
boolean_result03c: true
boolean_result03d: true
boolean_result03e: true
number_result03f: 2.0000

--]]
