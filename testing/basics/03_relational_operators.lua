--#title "v32lua relational operators unit test"
--@ Vircon32 Lua Relational Operators Unit Test
--@ Tests all relational/comparison operators with exhaustive coverage.
--@ Results are stored in global variables for automated memory scraping.

function test_relational_operators()
    -- === Test 00: Equality (==) with numbers - true ===
    boolean_result00 = (10 == 10)

    -- === Test 01: Equality (==) with numbers - false ===
    boolean_result01 = (10 == 20)

    -- === Test 02: Inequality (~=) with numbers - true ===
    boolean_result02 = (10 ~= 20)

    -- === Test 03: Inequality (~=) with numbers - false ===
    boolean_result03 = (10 ~= 10)

    -- === Test 04: Less than (<) with numbers - true ===
    boolean_result04 = (5 < 10)

    -- === Test 05: Less than (<) with numbers - false ===
    boolean_result05 = (10 < 5)

    -- === Test 06: Less than (<) with numbers - equal ===
    boolean_result06 = (10 < 10)

    -- === Test 07: Greater than (>) with numbers - true ===
    boolean_result07 = (15 > 10)

    -- === Test 08: Greater than (>) with numbers - false ===
    boolean_result08 = (10 > 15)

    -- === Test 09: Greater than (>) with numbers - equal ===
    boolean_result09 = (10 > 10)

    -- === Test 10: Less than or equal (<=) with numbers - true (less) ===
    boolean_result10 = (5 <= 10)

    -- === Test 11: Less than or equal (<=) with numbers - true (equal) ===
    boolean_result11 = (10 <= 10)

    -- === Test 12: Less than or equal (<=) with numbers - false ===
    boolean_result12 = (15 <= 10)

    -- === Test 13: Greater than or equal (>=) with numbers - true (greater) ===
    boolean_result13 = (15 >= 10)

    -- === Test 14: Greater than or equal (>=) with numbers - true (equal) ===
    boolean_result14 = (10 >= 10)

    -- === Test 15: Greater than or equal (>=) with numbers - false ===
    boolean_result15 = (5 >= 10)

    -- === Test 16: Equality (==) with strings - true ===
    boolean_result16 = ("hello" == "hello")

    -- === Test 17: Equality (==) with strings - false ===
    boolean_result17 = ("hello" == "world")

    -- === Test 18: Inequality (~=) with strings - true ===
    boolean_result18 = ("hello" ~= "world")

    -- === Test 19: Inequality (~=) with strings - false ===
    boolean_result19 = ("hello" ~= "hello")

    -- === Test 20: Less than (<) with strings - true ===
    boolean_result20 = ("apple" < "banana")

    -- === Test 21: Less than (<) with strings - false ===
    boolean_result21 = ("banana" < "apple")

    -- === Test 22: Greater than (>) with strings - true ===
    boolean_result22 = ("zebra" > "apple")

    -- === Test 23: Greater than (>) with strings - false ===
    boolean_result23 = ("apple" > "zebra")

    -- === Test 24: Equality (==) with booleans - true ===
    boolean_result24 = (true == true)

    -- === Test 25: Equality (==) with booleans - false ===
    boolean_result25 = (true == false)

    -- === Test 26: Inequality (~=) with booleans - true ===
    boolean_result26 = (true ~= false)

    -- === Test 27: Inequality (~=) with booleans - false ===
    boolean_result27 = (true ~= true)

    -- === Test 28: Numeric edge case - zero equality ===
    boolean_result28 = (0 == 0)

    -- === Test 29: Numeric edge case - negative numbers ===
    boolean_result29 = (-5 < -3)

    -- === Test 30: Numeric edge case - floating point ===
    boolean_result30 = (3.14 < 3.15)

    -- === Test 31: Chained comparisons - transitive ===
    local a, b, c = 5, 10, 15
    boolean_result31 = (a < b and b < c)
end

function main()
    ioports.gpu.clear("black")
    test_relational_operators()

    print(000, 00,  "--- Relational Operators Test ---")
    print(000, 020, "Test 00 - Num == true: " ..       tostring(boolean_result00))
    print(000, 040, "Test 01 - Num == false: " ..      tostring(boolean_result01))
    print(000, 060, "Test 02 - Num ~= true: " ..       tostring(boolean_result02))
    print(000, 080, "Test 03 - Num ~= false: " ..      tostring(boolean_result03))
    print(000, 100, "Test 04 - Num < true: " ..        tostring(boolean_result04))
    print(000, 120, "Test 05 - Num < false: " ..       tostring(boolean_result05))
    print(000, 140, "Test 06 - Num < equal: " ..       tostring(boolean_result06))
    print(000, 160, "Test 07 - Num > true: " ..        tostring(boolean_result07))
    print(000, 180, "Test 08 - Num > false: " ..       tostring(boolean_result08))
    print(000, 200, "Test 09 - Num > equal: " ..       tostring(boolean_result09))
    print(000, 220, "Test 10 - Num <= less: " ..       tostring(boolean_result10))
    print(000, 240, "Test 11 - Num <= equal: " ..      tostring(boolean_result11))
    print(000, 260, "Test 12 - Num <= false: " ..      tostring(boolean_result12))
    print(200, 020, "Test 13 - Num >= greater: " ..    tostring(boolean_result13))
    print(200, 040, "Test 14 - Num >= equal: " ..      tostring(boolean_result14))
    print(200, 060, "Test 15 - Num >= false: " ..      tostring(boolean_result15))
    print(200, 080, "Test 16 - Str == true: " ..       tostring(boolean_result16))
    print(200, 100, "Test 17 - Str == false: " ..      tostring(boolean_result17))
    print(200, 120, "Test 18 - Str ~= true: " ..       tostring(boolean_result18))
    print(200, 140, "Test 19 - Str ~= false: " ..      tostring(boolean_result19))
    print(200, 160, "Test 20 - Str < true: " ..        tostring(boolean_result20))
    print(200, 180, "Test 21 - Str < false: " ..       tostring(boolean_result21))
    print(200, 200, "Test 22 - Str > true: " ..        tostring(boolean_result22))
    print(200, 220, "Test 23 - Str > false: " ..       tostring(boolean_result23))
    print(200, 240, "Test 24 - Bool == true: " ..      tostring(boolean_result24))
    print(200, 260, "Test 25 - Bool == false: " ..     tostring(boolean_result25))
    print(200, 280, "Test 26 - Bool ~= true: " ..      tostring(boolean_result26))
    print(200, 300, "Test 27 - Bool ~= false: " ..     tostring(boolean_result27))
end

--[[
=== EXPECTED OUTPUT ===

boolean_result00: true
boolean_result01: false
boolean_result02: true
boolean_result03: false
boolean_result04: true
boolean_result05: false
boolean_result06: false
boolean_result07: true
boolean_result08: false
boolean_result09: false
boolean_result10: true
boolean_result11: true
boolean_result12: false
boolean_result13: true
boolean_result14: true
boolean_result15: false
boolean_result16: true
boolean_result17: false
boolean_result18: true
boolean_result19: false
boolean_result20: true
boolean_result21: false
boolean_result22: true
boolean_result23: false
boolean_result24: true
boolean_result25: false
boolean_result26: true
boolean_result27: false
boolean_result28: true
boolean_result29: true
boolean_result30: true
boolean_result31: true

--]]
