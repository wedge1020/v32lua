--#title "[v32lua] tonumber() unit test"
--@ Vircon32 Lua tonumber() Unit Test
--@ Tests tonumber() against the actual __builtin_string_to_number scope:
--@   - Accepts the SAME numeric-literal grammar the lexer itself accepts
--@     (decimal with optional fraction, leading-dot decimal, 0x/0X hex
--@     integer) -- nothing more. No exponent notation, no explicit-base
--@     second argument (tonumber(s, base) is a separate, deferred
--@     feature -- calling it with 2 arguments is a compile-time error).
--@   - Leading/trailing whitespace is trimmed; a leading +/- sign is
--@     accepted on the decimal forms.
--@   - Malformed input (leftover garbage, no digits at all, non-string/
--@     non-number types) returns nil, never errors.
--@   - A value that's already a number is returned unchanged.
--@ The value 12 is used as the running example throughout (0xC = 12
--@ decimal, which is a convenient coincidence for the hex tests).
--@ A __debugN label follows every test.

function test_tonumber()
    -- === Test 00: Plain decimal string ===
    number_result00 = tonumber("12")  -- Expected: 12
    __rawasm__("__debug0:")

    -- === Test 01: Leading AND trailing whitespace, both trimmed ===
    number_result01 = tonumber("  12  ")  -- Expected: 12
    __rawasm__("__debug1:")

    -- === Test 02: Leading whitespace only ===
    number_result02 = tonumber("   12")  -- Expected: 12
    __rawasm__("__debug2:")

    -- === Test 03: Trailing whitespace only ===
    number_result03 = tonumber("12   ")  -- Expected: 12
    __rawasm__("__debug3:")

    -- === Test 04: Explicit leading '-' sign ===
    number_result04 = tonumber("-12")  -- Expected: -12
    __rawasm__("__debug4:")

    -- === Test 05: Explicit leading '+' sign ===
    number_result05 = tonumber("+12")  -- Expected: 12
    __rawasm__("__debug5:")

    -- === Test 06: Sign combined with whitespace ===
    number_result06 = tonumber("  -12  ")  -- Expected: -12
    __rawasm__("__debug6:")

    -- === Test 07: Float form, whole-number value ===
    number_result07 = tonumber("12.0")  -- Expected: 12
    __rawasm__("__debug7:")

    -- === Test 08: Float form, fractional value ===
    number_result08 = tonumber("12.5")  -- Expected: 12.5
    __rawasm__("__debug8:")

    -- === Test 09: Leading-dot decimal (no leading integer digit at all) ===
    number_result09 = tonumber(".12")  -- Expected: 0.12
    __rawasm__("__debug9:")

    -- === Test 10: Negative float ===
    number_result10 = tonumber("-12.5")  -- Expected: -12.5
    __rawasm__("__debug10:")

    -- === Test 11: Hex, lowercase prefix and digit -- 0xC = 12 decimal ===
    number_result11 = tonumber("0xc")  -- Expected: 12
    __rawasm__("__debug11:")

    -- === Test 12: Hex, uppercase digit ===
    number_result12 = tonumber("0xC")  -- Expected: 12
    __rawasm__("__debug12:")

    -- === Test 13: Hex, uppercase 'X' prefix ===
    number_result13 = tonumber("0XC")  -- Expected: 12
    __rawasm__("__debug13:")

    -- === Test 14: Hex, multi-digit value ===
    number_result14 = tonumber("0x2C")  -- Expected: 44 (2*16 + 12)
    __rawasm__("__debug14:")

    -- === Test 15: Already a number -- returned unchanged, string parser ===
    -- === never runs at all ===
    number_result15 = tonumber(12)  -- Expected: 12
    __rawasm__("__debug15:")

    -- === Test 16: Already a float -- returned unchanged ===
    number_result16 = tonumber(12.5)  -- Expected: 12.5
    __rawasm__("__debug16:")

    -- === Test 17: Non-string, non-number input -- boolean ===
    boolean_result17 = (tonumber(true) == nil)  -- Expected: true
    __rawasm__("__debug17:")

    -- === Test 18: Non-string, non-number input -- nil ===
    boolean_result18 = (tonumber(nil) == nil)  -- Expected: true
    __rawasm__("__debug18:")

    -- === Test 19: Non-string, non-number input -- table ===
    boolean_result19 = (tonumber({}) == nil)  -- Expected: true
    __rawasm__("__debug19:")

    -- === Test 20: Malformed -- leftover garbage after a clean number ===
    boolean_result20 = (tonumber("12x") == nil)  -- Expected: true
    __rawasm__("__debug20:")

    -- === Test 21: Malformed -- no digits at all ===
    boolean_result21 = (tonumber("abc") == nil)  -- Expected: true
    __rawasm__("__debug21:")

    -- === Test 22: Malformed -- bare sign, no digits ===
    boolean_result22 = (tonumber("-") == nil)  -- Expected: true
    __rawasm__("__debug22:")

    -- === Test 23: Malformed -- empty string ===
    boolean_result23 = (tonumber("") == nil)  -- Expected: true
    __rawasm__("__debug23:")

    -- === Test 24: Malformed -- whitespace only ===
    boolean_result24 = (tonumber("   ") == nil)  -- Expected: true
    __rawasm__("__debug24:")

    -- === Test 25: Malformed -- "0x" prefix with no hex digits after it ===
    boolean_result25 = (tonumber("0x") == nil)  -- Expected: true
    __rawasm__("__debug25:")

    -- === Test 26: Round-trip -- result of tonumber() used in arithmetic ===
    number_result26 = tonumber("12") + tonumber("0xC")  -- Expected: 24 (12 + 12)
    __rawasm__("__debug26:")
end

function main()
    ioports.gpu.clear("black")
    test_tonumber()

    print(  0,   0, "--- tonumber() Test ---")
    print(  0,  20, "Test 00 - Plain: "           .. number_result00)
    print(  0,  40, "Test 01 - Both ws: "         .. number_result01)
    print(  0,  60, "Test 02 - Leading ws: "      .. number_result02)
    print(  0,  80, "Test 03 - Trailing ws: "     .. number_result03)
    print(  0, 100, "Test 04 - Neg sign: "        .. number_result04)
    print(  0, 120, "Test 05 - Pos sign: "        .. number_result05)
    print(  0, 140, "Test 06 - Sign + ws: "       .. number_result06)
    print(  0, 160, "Test 07 - Float whole: "     .. number_result07)
    print(  0, 180, "Test 08 - Float frac: "      .. number_result08)
    print(  0, 200, "Test 09 - Leading dot: "     .. number_result09)
    print(  0, 220, "Test 10 - Neg float: "       .. number_result10)
    print(  0, 240, "Test 11 - Hex lower: "       .. number_result11)
    print(  0, 260, "Test 12 - Hex upper digit: " .. number_result12)
    print(  0, 280, "Test 13 - Hex upper X: "     .. number_result13)
    print(320,  20, "Test 14 - Hex multi-digit: " .. number_result14)
    print(320,  40, "Test 15 - Already number: "  .. number_result15)
    print(320,  60, "Test 16 - Already float: "   .. number_result16)
    print(320,  80, "Test 17 - Boolean->nil: "    .. tostring(boolean_result17))
    print(320, 100, "Test 18 - Nil->nil: "        .. tostring(boolean_result18))
    print(320, 120, "Test 19 - Table->nil: "      .. tostring(boolean_result19))
    print(320, 140, "Test 20 - Garbage->nil: "    .. tostring(boolean_result20))
    print(320, 160, "Test 21 - No digits->nil: "  .. tostring(boolean_result21))
    print(320, 180, "Test 22 - Bare sign->nil: "  .. tostring(boolean_result22))
    print(320, 200, "Test 23 - Empty->nil: "      .. tostring(boolean_result23))
    print(320, 220, "Test 24 - Ws only->nil: "    .. tostring(boolean_result24))
    print(320, 240, "Test 25 - Bare 0x->nil: "    .. tostring(boolean_result25))
    print(320, 260, "Test 26 - Round-trip sum: "  .. number_result26)
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 12.0000
number_result01: 12.0000
number_result02: 12.0000
number_result03: 12.0000
number_result04: -12.0000
number_result05: 12.0000
number_result06: -12.0000
number_result07: 12.0000
number_result08: 12.5000
number_result09: 0.1200
number_result10: -12.5000
number_result11: 12.0000
number_result12: 12.0000
number_result13: 12.0000
number_result14: 44.0000
number_result15: 12.0000
number_result16: 12.5000
boolean_result17: true
boolean_result18: true
boolean_result19: true
boolean_result20: true
boolean_result21: true
boolean_result22: true
boolean_result23: true
boolean_result24: true
boolean_result25: true
number_result26: 24.0000
]]
