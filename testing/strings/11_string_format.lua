--#title "[v32lua] string.format() unit test"
--@ Vircon32 Lua string.format() Unit Test
--@ Tests string.format() specifiers individually. Every expected value
--@ below is checked against the actual emit_string_format_intrinsic /
--@ __builtin_string_format implementation, not assumed:
--@   - %d/%i/%u, %f, %s, %c, %q, and literal %% are implemented.
--@   - %e/%E/%g/%G exist but are NOT true scientific notation -- they're
--@     aliased straight to the same fixed-point formatting %f uses.
--@   - Flags: '-' (left-justify, spaces after the value) and '0'
--@     (width-based zero-pad, right-justify only -- '-' takes precedence
--@     if both are given, matching C). Other flags ('+', ' ', '#') are
--@     NOT recognized and silently misparse -- see the width/flag
--@     parsing code for why.
--@   - Zero-padding a NEGATIVE value places zeros BEFORE the sign
--@     (e.g. "%08d" on -5 gives "000000-5", not C's "-0000005") --
--@     copy_string() fills generically without knowing the string
--@     contains a sign character. Flagging as a known simplification,
--@     not exercised by the tests below since it doesn't come up for
--@     the %x/%X use case this was built for.
--@   - %x/%X (hex) format the value's MAGNITUDE with a leading '-' for
--@     negatives -- sign+magnitude, not C's two's-complement bit-pattern
--@     behavior (C's %x on -1 gives "ffffffff"; this gives "-1").
--@ A __debugN label follows every test.

function test_string_format()
    -- === Test 00: %.2f -- precision explicitly given ===
    string_result00 = string.format("%.2f", 3.14159)  -- Expected: "3.14"
    __rawasm__("__debug0:")

    -- === Test 01: %.0f -- zero decimal places, rounds to integer ===
    string_result01 = string.format("%.0f", 7.9)  -- Expected: "8"
    __rawasm__("__debug1:")

    -- === Test 02: %.4f -- more decimal places ===
    string_result02 = string.format("%.4f", 1.5)  -- Expected: "1.5000"
    __rawasm__("__debug2:")

    -- === Test 03: %f -- NO explicit precision defaults to 6 places ===
    -- (confirmed: the -1 "unspecified" sentinel maps to precision 6 in
    -- __ftoa_shared_body, matching C's/Lua's own %f default)
    string_result03 = string.format("%f", 2.5)  -- Expected: "2.500000"
    __rawasm__("__debug3:")

    -- === Test 04: %d -- plain integer ===
    string_result04 = string.format("%d", 42)  -- Expected: "42"
    __rawasm__("__debug4:")

    -- === Test 05: %d -- negative integer ===
    string_result05 = string.format("%d", -17)  -- Expected: "-17"
    __rawasm__("__debug5:")

    -- === Test 06: %d -- a float value truncated/rounded to an integer ===
    string_result06 = string.format("%d", 9.9)  -- Expected: "9" (precision 0 = round to integer, matches %.0f)
    __rawasm__("__debug6:")

    -- === Test 07: %i -- alias for %d, separate dispatch branch ===
    string_result07 = string.format("%i", 42)  -- Expected: "42"
    __rawasm__("__debug7:")

    -- === Test 08: %u -- separate dispatch branch from %d/%i ===
    string_result08 = string.format("%u", 42)  -- Expected: "42"
    __rawasm__("__debug8:")

    -- === Test 09: %s -- plain string ===
    string_result09 = string.format("%s", "hello")  -- Expected: "hello"
    __rawasm__("__debug9:")

    -- === Test 10: %c -- character code to single character ===
    string_result10 = string.format("%c", 65)  -- Expected: "A"
    __rawasm__("__debug10:")

    -- === Test 11: %q -- quoted string (surrounding quotes added) ===
    -- Kept deliberately free of characters that would need escaping
    -- (quotes, backslashes, newlines) -- real Lua's %q escaping rules
    -- for those are more involved and not confirmed here.
    string_result11 = string.format("%q", "hello")  -- Expected: '"hello"'
    __rawasm__("__debug11:")

    -- === Test 12: %e -- implemented, but NOT true scientific notation -- ===
    -- === aliased to the same fixed-point formatting %f uses ===
    string_result12 = string.format("%.2e", 3.14159)  -- Expected: "3.14" (NOT "3.14e+00")
    __rawasm__("__debug12:")

    -- === Test 13: %g -- same fixed-point alias as %e ===
    string_result13 = string.format("%.2g", 3.14159)  -- Expected: "3.14" (NOT shortest-representation)
    __rawasm__("__debug13:")

    -- === Test 14: Multiple specifiers in one format string ===
    string_result14 = string.format("%s = %d", "x", 5)  -- Expected: "x = 5"
    __rawasm__("__debug14:")

    -- === Test 15: Literal text mixed with a specifier ===
    string_result15 = string.format("Score- %d points", 100)  -- Expected: "Score: 100 points"
    __rawasm__("__debug15:")

    -- === Test 16: No specifiers at all -- pure passthrough ===
    string_result16 = string.format("no specifiers here")  -- Expected: "no specifiers here"
    __rawasm__("__debug16:")

    -- === Test 17: %% -- literal percent sign ===
    string_result17 = string.format("%d%%", 50)  -- Expected: "50%"
    __rawasm__("__debug17:")

    -- === Test 18: Width specifier -- right-justified padding ===
    string_result18 = string.format("%5d", 7)  -- Expected: "    7" (4 spaces + "7")
    __rawasm__("__debug18:")

    -- === Test 19: %x -- lowercase hex ===
    string_result19 = string.format("%x", 255)  -- Expected: "ff"
    __rawasm__("__debug19:")

    -- === Test 20: %X -- uppercase hex ===
    string_result20 = string.format("%X", 255)  -- Expected: "FF"
    __rawasm__("__debug20:")

    -- === Test 21: %x -- zero ===
    string_result21 = string.format("%x", 0)  -- Expected: "0"
    __rawasm__("__debug21:")

    -- === Test 22: %x -- negative value, SIGN+MAGNITUDE (not two's ===
    -- === complement -- see header comment) ===
    string_result22 = string.format("%x", -255)  -- Expected: "-ff" (NOT "ffffff01")
    __rawasm__("__debug22:")

    -- === Test 23: %x -- a float value, truncated toward zero first ===
    -- === (same __string_format_trunc_toward_zero helper %d/%u use) ===
    string_result23 = string.format("%x", 15.9)  -- Expected: "f" (15, not 16)
    __rawasm__("__debug23:")

    -- === Test 24: %x combined with width padding ===
    string_result24 = string.format("%5x", 255)  -- Expected: "   ff" (3 spaces + "ff")
    __rawasm__("__debug24:")

    -- === Test 25: %-Nd -- left-justify flag (spaces AFTER the value) ===
    string_result25 = string.format("%-4d", 3)  -- Expected: "3   " ('3' + 3 trailing spaces)
    __rawasm__("__debug25:")

    -- === Test 26: %.NX -- PRECISION-based zero-padding on hex (this is ===
    -- === what "0x%.8X" style formatting actually uses -- precision means ===
    -- === "minimum digit count, zero-padded", distinct from the width- ===
    -- === based '0' flag tested below) ===
    string_result26 = string.format("0x%.8X", 65195)  -- Expected: "0x0000FEAB"
    __rawasm__("__debug26:")

    -- === Test 27: %0Nx -- WIDTH-based zero-pad flag, exact-width fit ===
    -- === (0xDEADBEEF is exactly 8 hex digits, so %08x produces ZERO ===
    -- === visible padding here -- included as a valid "no padding ===
    -- === needed" edge case, not a demonstration of padding itself) ===
    string_result27 = string.format("%08x", 3735928559)  -- Expected: "deadbeef" (0xDEADBEEF)
    __rawasm__("__debug27:")

    -- === Test 28: %0Nx -- WIDTH-based zero-pad flag, ACTUALLY padded ===
    -- === (0xBEEF is only 4 hex digits, so %08x visibly adds 4 leading ===
    -- === zeros -- this is the one that demonstrates the feature) ===
    string_result28 = string.format("%08x", 48879)  -- Expected: "0000beef" (0xBEEF)
    __rawasm__("__debug28:")
end

function main()
    ioports.gpu.clear("black")
    test_string_format()

    print(100, 000, "--- string.format Test ---")
    print(100, 020, "Test 00 - %.2f: " ..        string_result00)
    print(100, 040, "Test 01 - %.0f: " ..        string_result01)
    print(100, 060, "Test 02 - %.4f: " ..        string_result02)
    print(100, 080, "Test 03 - %f default: " ..  string_result03)
    print(100, 100, "Test 04 - %d: " ..          string_result04)
    print(100, 120, "Test 05 - %d neg: " ..      string_result05)
    print(100, 140, "Test 06 - %d trunc: " ..    string_result06)
    print(100, 160, "Test 07 - %i: " ..          string_result07)
    print(100, 180, "Test 08 - %u: " ..          string_result08)
    print(100, 200, "Test 09 - %s: " ..          string_result09)
    print(100, 220, "Test 10 - %c: " ..          string_result10)
    print(100, 240, "Test 11 - %q: " ..          string_result11)
    print(100, 260, "Test 12 - %e (fixed-pt): " .. string_result12)
    print(100, 280, "Test 13 - %g (fixed-pt): " .. string_result13)
    print(320, 020, "Test 14 - Multi: " ..       string_result14)
    print(320, 040, "Test 15 - Mixed text: " ..  string_result15)
    print(320, 060, "Test 16 - No specs: " ..    string_result16)
    print(320, 080, "Test 17 - %%: " ..          string_result17)
    print(320, 100, "Test 18 - Width padded: '" .. string_result18 .. "'")
    print(320, 120, "Test 19 - %x: " ..          string_result19)
    print(320, 140, "Test 20 - %X: " ..          string_result20)
    print(320, 160, "Test 21 - %x zero: " ..     string_result21)
    print(320, 180, "Test 22 - %x negative: " .. string_result22)
    print(320, 200, "Test 23 - %x truncated: " .. string_result23)
    print(320, 220, "Test 24 - %x + width: '" .. string_result24 .. "'")
    print(320, 240, "Test 25 - %-4d left-just: '" .. string_result25 .. "'")
    print(320, 260, "Test 26 - 0x%.8X precision: " .. string_result26)
    print(320, 280, "Test 27 - %08x exact fit: " .. string_result27)
    print(600, 020, "Test 28 - %08x padded: " .. string_result28)
end

--[[
=== EXPECTED OUTPUT ===
string_result00: "3.14"
string_result01: "8"
string_result02: "1.5000"
string_result03: "2.500000"
string_result04: "42"
string_result05: "-17"
string_result06: "9"
string_result07: "42"
string_result08: "42"
string_result09: "hello"
string_result10: "A"
string_result11: ""hello""
string_result12: "3.14"
string_result13: "3.14"
string_result14: "x = 5"
string_result15: "Score- 100 points"
string_result16: "no specifiers here"
string_result17: "50%"
string_result18: "    7"
string_result19: "ff"
string_result20: "FF"
string_result21: "0"
string_result22: "-ff"
string_result23: "f"
string_result24: "   ff"
string_result25: "3   "
string_result26: "0x0000FEAB"
string_result27: "deadbeef"
string_result28: "0000beef"
]]
