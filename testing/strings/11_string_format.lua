--#title "[v32lua] string.format() unit test"
--@ Vircon32 Lua string.format() Unit Test
--@ Tests string.format() specifiers individually. Only "%.2f" is
--@ confirmed exercised elsewhere (00_print.lua) -- everything else here
--@ is unverified against the actual emit_string_format_intrinsic
--@ dispatch. Ordered roughly from most to least likely to already work;
--@ a __debugN label follows every test so a build failure or wrong
--@ value on one specifier doesn't obscure the status of the rest.

function test_string_format()
    -- === Test 00: %.2f -- confirmed working elsewhere (00_print.lua) ===
    string_result00 = string.format("%.2f", 3.14159)  -- Expected: "3.14"
    __rawasm__("__debug0:")

    -- === Test 01: %.0f -- zero decimal places ===
    string_result01 = string.format("%.0f", 7.9)  -- Expected: "8"
    __rawasm__("__debug1:")

    -- === Test 02: %.4f -- more decimal places ===
    string_result02 = string.format("%.4f", 1.5)  -- Expected: "1.5000"
    __rawasm__("__debug2:")

    -- === Test 03: %d -- plain integer ===
    string_result03 = string.format("%d", 42)  -- Expected: "42"
    __rawasm__("__debug3:")

    -- === Test 04: %d -- negative integer ===
    string_result04 = string.format("%d", -17)  -- Expected: "-17"
    __rawasm__("__debug4:")

    -- === Test 05: %d -- a float value truncated to an integer ===
    string_result05 = string.format("%d", 9.9)  -- Expected: "9"
    __rawasm__("__debug5:")

    -- === Test 06: %s -- plain string ===
    string_result06 = string.format("%s", "hello")  -- Expected: "hello"
    __rawasm__("__debug6:")

    -- === Test 07: Multiple specifiers in one format string ===
    string_result07 = string.format("%s = %d", "x", 5)  -- Expected: "x = 5"
    __rawasm__("__debug7:")

    -- === Test 08: Literal text mixed with a specifier ===
    string_result08 = string.format("Score- %d points", 100)  -- Expected: "Score: 100 points"
    __rawasm__("__debug8:")

    -- === Test 09: No specifiers at all -- pure passthrough ===
    string_result09 = string.format("no specifiers here")  -- Expected: "no specifiers here"
    __rawasm__("__debug9:")

    -- === Test 10: %% -- literal percent sign ===
    string_result10 = string.format("%d%%", 50)  -- Expected: "50%"
    __rawasm__("__debug10:")

    -- === Test 11: %x -- hexadecimal (SPECULATIVE -- may not be implemented) ===
    string_result11 = string.format("%x", 255)  -- Expected: "ff"
    __rawasm__("__debug11:")

    -- === Test 12: %f with no explicit precision ===
    -- === precision behavior unconfirmed; real Lua/C default is 6 places) ===
    string_result12 = string.format("%f", 2.5)  -- Expected: "2.500000" if C-default precision
    __rawasm__("__debug12:")

    -- === Test 13: Width padding, e.g. %5d ===
    string_result13 = string.format("%5d", 7)  -- Expected: "    7" (padded to width 5)
    __rawasm__("__debug13:")

    -- === Test 14: Width padding, e.g. %-4d ===
    string_result14 = string.format("%-4d", 3)  -- Expected: "3   " (padded to width 4)
    __rawasm__("__debug14:")
end

function main()
    ioports.gpu.clear("black")
    test_string_format()

    print(100, 000, "--- string.format Test ---")
    print(100, 020, "Test 00 - %.2f: " ..        string_result00)
    print(100, 040, "Test 01 - %.0f: " ..        string_result01)
    print(100, 060, "Test 02 - %.4f: " ..        string_result02)
    print(100, 080, "Test 03 - %d: " ..          string_result03)
    print(100, 100, "Test 04 - %d neg: " ..      string_result04)
    print(100, 120, "Test 05 - %d trunc: " ..    string_result05)
    print(100, 140, "Test 06 - %s: " ..          string_result06)
    print(100, 160, "Test 07 - Multi: " ..       string_result07)
    print(100, 180, "Test 08 - Mixed text: " ..  string_result08)
    print(100, 200, "Test 09 - No specs: " ..    string_result09)
    print(100, 220, "Test 10 - %%: " ..          string_result10)
    print(100, 240, "Test 11 - %x: " ..          string_result11)
    print(100, 260, "Test 12 - %f default: " ..  string_result12)
    print(100, 280, "Test 13 - %5d width: '" ..  string_result13 .. "'")
    print(100, 280, "Test 14 - %-4d width: '" ..  string_result13 .. "'")
end

--[[
=== EXPECTED OUTPUT ===
string_result00: "3.14"
string_result01: "8"
string_result02: "1.5000"
string_result03: "42"
string_result04: "-17"
string_result05: "9"
string_result06: "hello"
string_result07: "x = 5"
string_result08: "Score- 100 points"
string_result09: "no specifiers here"
string_result10: "50%"
string_result11: "ff"
string_result12: "2.500000"
string_result13: "    7"
string_result14: "3   "
]]
