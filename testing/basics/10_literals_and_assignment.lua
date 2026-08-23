--#title "[v32lua] literals and assignment unit test"
--@ Vircon32 Lua Literals and Assignment Unit Test
--@ Tests numeric literal forms (hex, leading/trailing dot), uninitialized
--@ local declarations, multiple-assignment count mismatches (fewer/more
--@ values than targets), and semicolons as statement separators.
--@ Results are stored in global variables for automated memory scraping.

function test_literals_and_assignment()
    -- === Test 00: Hex literal, lowercase digits ===
    number_result00 = 0xff           -- Expected: 255

    -- === Test 01: Hex literal, uppercase digits ===
    number_result01 = 0xFF           -- Expected: 255

    -- === Test 02: Hex literal, small value ===
    number_result02 = 0x10           -- Expected: 16

    -- === Test 03: Hex literal used in arithmetic ===
    number_result03 = 0x0A + 0x05    -- Expected: 15

    -- === Test 04: Leading-dot decimal literal ===
    number_result04 = .5             -- Expected: 0.5

    -- === Test 05: Leading-dot decimal in an expression ===
    number_result05 = .25 * 4        -- Expected: 1

    -- === Test 06: Ordinary decimal literal ===
    number_result06 = 3.14159        -- Expected: 3.14159 (printed to 4dp: 3.1416)

    -- === Test 07: Integer-valued literal stays numerically exact ===
    number_result07 = 1000000        -- Expected: 1000000

    -- === Test 08: Uninitialized local declaration is nil ===
    local u
    string_result08 = type(u)        -- Expected: "nil"

    -- === Test 09: Uninitialized local, multiple names, all nil ===
    local p, q, r
    boolean_result09 = (p == nil and q == nil and r == nil)  -- Expected: true

    -- === Test 10: Uninitialized local can be assigned afterward ===
    local later
    later = 77
    number_result10 = later          -- Expected: 77

    -- === Test 11: Multiple assignment, FEWER values than targets ===
    -- Extra targets with no matching value are set to nil.
    local m1, m2, m3 = 10, 20
    number_result11 = m1             -- Expected: 10
    number_result12 = m2             -- Expected: 20
    string_result11  = type(m3)      -- Expected: "nil"

    -- === Test 12: Multiple assignment, MORE values than targets ===
    -- Extra values on the right are evaluated but discarded.
    local n1, n2 = 1, 2, 3
    number_result13 = n1             -- Expected: 1
    number_result14 = n2             -- Expected: 2

    -- === Test 13: Multiple assignment used to swap two variables ===
    local sa, sb = 1, 2
    sa, sb = sb, sa
    number_result15 = sa             -- Expected: 2
    number_result16 = sb             -- Expected: 1

    -- === Test 14: Multiple assignment, all values nil ===
    local x1, x2 = nil, nil
    boolean_result14 = (x1 == nil and x2 == nil)  -- Expected: true

    -- === Test 15: Semicolon as an explicit statement separator ===
    local sv = 1; sv = sv + 1; sv = sv + 1;
    number_result17 = sv             -- Expected: 3

    -- === Test 16: Trailing semicolon after the last statement in a block ===
    do
        local t = 99;
        number_result18 = t;
    end
end

function main()
    ioports.gpu.clear("black")
    test_literals_and_assignment()

    print(000, 000, "--- Literals and Assignment Test ---")
    print(000, 020, "Test 00 - 0xff: " ..          number_result00)
    print(000, 040, "Test 01 - 0xFF: " ..          number_result01)
    print(000, 060, "Test 02 - 0x10: " ..          number_result02)
    print(000, 080, "Test 03 - hex add: " ..       number_result03)
    print(000, 100, "Test 04 - .5: " ..            number_result04)
    print(000, 120, "Test 05 - .25*4: " ..         number_result05)
    print(000, 140, "Test 06 - 3.14159: " ..       number_result06)
    print(000, 160, "Test 07 - 1000000: " ..       number_result07)
    print(000, 180, "Test 08 - Uninit local: " ..  string_result08)
    print(000, 200, "Test 09 - Uninit multi: " ..  tostring(boolean_result09))
    print(000, 220, "Test 10 - Later assign: " ..  number_result10)
    print(000, 240, "Test 11 - Fewer m1: " ..      number_result11)
    print(000, 260, "Test 11 - Fewer m2: " ..      number_result12)
    print(200, 020, "Test 11 - Fewer m3 type: " .. string_result11)
    print(200, 040, "Test 12 - More n1: " ..       number_result13)
    print(200, 060, "Test 12 - More n2: " ..       number_result14)
    print(200, 080, "Test 13 - Swap sa: " ..       number_result15)
    print(200, 100, "Test 13 - Swap sb: " ..       number_result16)
    print(200, 120, "Test 14 - All nil: " ..       tostring(boolean_result14))
    print(200, 140, "Test 15 - Semicolons: " ..    number_result17)
    print(200, 160, "Test 16 - Trailing ;: " ..    number_result18)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 255.0000
number_result01: 255.0000
number_result02: 16.0000
number_result03: 15.0000
number_result04: 0.5000
number_result05: 1.0000
number_result06: 3.1416
number_result07: 1000000.0000
string_result08: "nil"
boolean_result09: true
number_result10: 77.0000
number_result11: 10.0000
number_result12: 20.0000
string_result11: "nil"
number_result13: 1.0000
number_result14: 2.0000
number_result15: 2.0000
number_result16: 1.0000
boolean_result14: true
number_result17: 3.0000
number_result18: 99.0000

--]]
