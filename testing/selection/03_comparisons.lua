--@ Vircon32 Lua Comparison Operators Unit Test
--@ Tests <, >, <=, >=, ==, ~= across numeric and string operands, plus
--@ cross-type equality (which must be false, not an error) and chained
--@ range comparisons via 'and'.
--@ Results are stored in global variables for automated memory scraping.

function test_comparisons()
    -- === Test 00: Numeric less-than ===
    boolean_result00 = 5 < 10
    __rawasm__("__debug0:")

    -- === Test 01: Numeric greater-than ===
    boolean_result01 = 15 > 10
    __rawasm__("__debug1:")

    -- === Test 02: Numeric less-or-equal (boundary case) ===
    boolean_result02 = 10 <= 10
    __rawasm__("__debug2:")

    -- === Test 03: Numeric greater-or-equal (boundary case) ===
    boolean_result03 = 20 >= 20
    __rawasm__("__debug3:")

    -- === Test 04: Numeric equality and inequality ===
    boolean_result04a = 10 == 10
    boolean_result04b = 10 ~= 20
    __rawasm__("__debug4:")

    -- === Test 05: String lexicographic comparison ===
    boolean_result05a = "apple" < "banana"
    boolean_result05b = "zebra" > "apple"
    __rawasm__("__debug5:")

    -- === Test 06: Cross-type equality is false, not an error -- a ===
    -- === number and its string form are never equal in Lua ===
    boolean_result06 = (1 == "1")
    __rawasm__("__debug6:")

    -- === Test 07: Chained range check via 'and' ===
    local n = 5
    boolean_result07a = (n > 0 and n < 10)   -- true, in range
    local m = 15
    boolean_result07b = (m > 0 and m < 10)   -- false, out of range
    __rawasm__("__debug7:")
end

function main()
    ioports.gpu.clear("black")
    test_comparisons()

    print(000, 00,  "--- Comparisons Test ---")
    print(000, 020, "Test 00 - Less than: " ..       tostring(boolean_result00))
    print(000, 040, "Test 01 - Greater than: " ..    tostring(boolean_result01))
    print(000, 060, "Test 02 - Less/equal: " ..      tostring(boolean_result02))
    print(000, 080, "Test 03 - Greater/equal: " ..   tostring(boolean_result03))
    print(000, 100, "Test 04 - Numeric eq: " ..      tostring(boolean_result04a))
    print(000, 120, "Test 04 - Numeric neq: " ..     tostring(boolean_result04b))
    print(000, 140, "Test 05 - String lt: " ..       tostring(boolean_result05a))
    print(000, 160, "Test 05 - String gt: " ..       tostring(boolean_result05b))
    print(000, 180, "Test 06 - Cross-type eq: " ..   tostring(boolean_result06))
    print(000, 200, "Test 07 - In range: " ..        tostring(boolean_result07a))
    print(000, 220, "Test 07 - Out of range: " ..    tostring(boolean_result07b))
end

--[[
=== EXPECTED OUTPUT ===
boolean_result00: true
boolean_result01: true
boolean_result02: true
boolean_result03: true
boolean_result04a: true
boolean_result04b: true
boolean_result05a: true
boolean_result05b: true
boolean_result06: false
boolean_result07a: true
boolean_result07b: false
--]]
