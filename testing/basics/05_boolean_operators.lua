--#title "v32lua boolean operations unit test"
--@ Vircon32 Lua Boolean Operations Unit Test
--@ Tests boolean values, operations, and type coercion.
--@ Results are stored in global variables for automated memory scraping.

function test_boolean_operations()
    -- === Test 00: Boolean true value ===
    boolean_result00 = true

    -- === Test 01: Boolean false value ===
    boolean_result01 = false

    -- === Test 02: Boolean equality - true == true ===
    boolean_result02 = (true == true)

    -- === Test 03: Boolean equality - false == false ===
    boolean_result03 = (false == false)

    -- === Test 04: Boolean equality - true == false ===
    boolean_result04 = (true == false)

    -- === Test 05: Boolean inequality - true ~= false ===
    boolean_result05 = (true ~= false)

    -- === Test 06: Boolean inequality - true ~= true ===
    boolean_result06 = (true ~= true)

    -- === Test 07: Boolean AND - true and true ===
    boolean_result07 = (true and true)

    -- === Test 08: Boolean AND - true and false ===
    boolean_result08 = (true and false)

    -- === Test 09: Boolean AND - false and true ===
    boolean_result09 = (false and true)

    -- === Test 10: Boolean AND - false and false ===
    boolean_result10 = (false and false)

    -- === Test 11: Boolean OR - true or true ===
    boolean_result11 = (true or true)

    -- === Test 12: Boolean OR - true or false ===
    boolean_result12 = (true or false)

    -- === Test 13: Boolean OR - false or true ===
    boolean_result13 = (false or true)

    -- === Test 14: Boolean OR - false or false ===
    boolean_result14 = (false or false)

    -- === Test 15: Boolean NOT - not true ===
    boolean_result15 = (not true)

    -- === Test 16: Boolean NOT - not false ===
    boolean_result16 = (not false)

    -- === Test 17: Boolean NOT - double negation ===
    boolean_result17 = (not (not true))

    -- === Test 18: Boolean type check ===
    string_result18 = type(true)

    -- === Test 19: Boolean tostring ===
    string_result19 = tostring(true)

    -- === Test 20: Boolean tostring false ===
    string_result20 = tostring(false)

    -- === Test 21: Boolean in numeric context (truthy) ===
    if true then
        number_result21 = 1
    else
        number_result21 = 0
    end

    -- === Test 22: Boolean in numeric context (falsy) ===
    if false then
        number_result22 = 1
    else
        number_result22 = 0
    end

    -- === Test 23: Boolean comparison with numbers - true == 1 ===
    boolean_result23 = (true == 1)

    -- === Test 24: Boolean comparison with numbers - false == 0 ===
    boolean_result24 = (false == 0)

    -- === Test 25: Boolean short-circuit AND returns value ===
    local result = true and 42
    number_result25 = result or 0

    -- === Test 26: Boolean short-circuit OR returns value ===
    local result2 = false or 99
    number_result26 = result2 or 0

    -- === Test 27: Boolean in conditional expression ===
    local x = 10
    local y = (x > 5) and "yes" or "no"
    string_result27 = y
end

function main()
    ioports.gpu.clear("black")
    test_boolean_operations()

    print(000, 00,  "--- Boolean Operations Test ---")
    print(000, 020, "Test 00 - True: " ..             tostring(boolean_result00))
    print(000, 040, "Test 01 - False: " ..            tostring(boolean_result01))
    print(000, 060, "Test 02 - True == True: " ..     tostring(boolean_result02))
    print(000, 080, "Test 03 - False == False: " ..   tostring(boolean_result03))
    print(000, 100, "Test 04 - True == False: " ..    tostring(boolean_result04))
    print(000, 120, "Test 05 - True ~= False: " ..    tostring(boolean_result05))
    print(000, 140, "Test 06 - True ~= True: " ..     tostring(boolean_result06))
    print(000, 160, "Test 07 - True AND True: " ..    tostring(boolean_result07))
    print(000, 180, "Test 08 - True AND False: " ..   tostring(boolean_result08))
    print(000, 200, "Test 09 - False AND True: " ..   tostring(boolean_result09))
    print(000, 220, "Test 10 - False AND False: " ..  tostring(boolean_result10))
    print(000, 240, "Test 11 - True OR True: " ..     tostring(boolean_result11))
    print(000, 260, "Test 12 - True OR False: " ..    tostring(boolean_result12))
    print(200, 020, "Test 13 - False OR True: " ..    tostring(boolean_result13))
    print(200, 040, "Test 14 - False OR False: " ..   tostring(boolean_result14))
    print(200, 060, "Test 15 - NOT True: " ..         tostring(boolean_result15))
    print(200, 080, "Test 16 - NOT False: " ..        tostring(boolean_result16))
    print(200, 100, "Test 17 - NOT NOT True: " ..     tostring(boolean_result17))
    print(200, 120, "Test 18 - Type true: " ..        string_result18)
    print(200, 140, "Test 19 - tostring true: " ..    string_result19)
    print(200, 160, "Test 20 - tostring false: " ..   string_result20)
    print(200, 180, "Test 21 - If true: " ..          number_result21)
    print(200, 200, "Test 22 - If false: " ..         number_result22)
    print(200, 220, "Test 23 - True == 1: " ..        tostring(boolean_result23))
    print(200, 240, "Test 24 - False == 0: " ..       tostring(boolean_result24))
    print(200, 260, "Test 25 - AND return: " ..       number_result25)
    print(200, 280, "Test 26 - OR return: " ..        number_result26)
    print(200, 300, "Test 27 - Cond expr: " ..        string_result27)
end

--[[
=== EXPECTED OUTPUT ===

boolean_result00: true
boolean_result01: false
boolean_result02: true
boolean_result03: true
boolean_result04: false
boolean_result05: true
boolean_result06: false
boolean_result07: true
boolean_result08: false
boolean_result09: false
boolean_result10: false
boolean_result11: true
boolean_result12: true
boolean_result13: true
boolean_result14: false
boolean_result15: false
boolean_result16: true
boolean_result17: true
string_result18: "boolean"
string_result19: "true"
string_result20: "false"
number_result21: 1.0000
number_result22: 0.0000
boolean_result23: false
boolean_result24: false
number_result25: 42.0000
number_result26: 99.0000
string_result27: "yes"

--]]
