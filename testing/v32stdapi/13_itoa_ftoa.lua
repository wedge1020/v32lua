--#title "v32lua itoa/ftoa unit test"
--@ Vircon32 Lua itoa/ftoa unit test
--@ Exercises the lib/string.lua ports of string.h's number-to-string
--@ converters: itoa in every calling convention and several bases
--@ (including the unsigned-32-bit readings of negative values), ftoa's
--@ formatting and trailing-zero trim, and itoa's out-of-range-base
--@ refusal. The --#include below is resolved relative to this file,
--@ pulling the compatibility library in from the repository's lib/
--@ directory -- which also makes this the first unit test to exercise
--@ the --#include preprocessor itself.

--#include "../../lib/string.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: itoa base 10 (value taken as signed) ===
    string_itoa_zero     = itoa(0, nil, 10)
    string_itoa_pos      = itoa(42, nil, 10)
    string_itoa_neg      = itoa(-42, nil, 10)
    string_itoa_int32min = itoa(-2147483648, nil, 10)

    -- === Test 2: itoa other bases (value taken as unsigned 32-bit) ===
    string_itoa_hex      = itoa(255, nil, 16)
    string_itoa_hexbig   = itoa(11259375, nil, 16)
    string_itoa_binary   = itoa(10, nil, 2)
    string_itoa_neg_hex  = itoa(-1, nil, 16)
    string_itoa_min_hex  = itoa(-2147483648, nil, 16)

    -- === Test 3: itoa calling conventions ===
    -- the C positional form keeps the unused buffer slot as argument 2;
    -- the Lua-natural spelling passes the base as argument 2 instead
    string_itoa_positional = itoa(255, nil, 16)
    string_itoa_natural    = itoa(255, 16)

    -- === Test 4: itoa with base out of [2-16] does nothing ===
    boolean_itoa_badbase = (itoa(5, nil, 20) == nil)

    -- === Test 5: ftoa formatting and trailing-zero trim ===
    string_ftoa_whole = ftoa(10, nil)
    string_ftoa_frac  = ftoa(2.5, nil)
    string_ftoa_pi    = ftoa(3.14159, nil)
    string_ftoa_lead0 = ftoa(0.05, nil)
    string_ftoa_neg   = ftoa(-2.5, nil)
    string_ftoa_trim  = ftoa(100.25, nil)

    print(10, 0,  "--- itoa/ftoa unit test ---")
    print(10, 20,  "itoa 42: "     .. string_itoa_pos)
    print(10, 40,  "itoa -1 hex: " .. string_itoa_neg_hex)
    print(10, 60,  "ftoa pi: "     .. string_ftoa_pi)
    print(10, 80,  "ftoa 2.5: "    .. string_ftoa_frac)
end

--[[
=== EXPECTED OUTPUT ===

string_itoa_zero: "0"
string_itoa_pos: "42"
string_itoa_neg: "-42"
string_itoa_int32min: "-2147483648"
string_itoa_hex: "FF"
string_itoa_hexbig: "ABCDEF"
string_itoa_binary: "1010"
string_itoa_neg_hex: "FFFFFFFF"
string_itoa_min_hex: "80000000"
string_itoa_positional: "FF"
string_itoa_natural: "FF"
boolean_itoa_badbase: true
string_ftoa_whole: "10"
string_ftoa_frac: "2.5"
string_ftoa_pi: "3.14159"
string_ftoa_lead0: "0.05"
string_ftoa_neg: "-2.5"
string_ftoa_trim: "100.25"

--]]
