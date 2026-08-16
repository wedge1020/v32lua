--#title "v32lua logical operators unit test"
--@ Vircon32 Lua Logical Operators Unit Test
--@ Tests logical AND, OR, NOT operators with exhaustive coverage.
--@ Results are stored in global variables for automated memory scraping.

function test_logical_operators()
    -- === Test 00: AND - true and true ===
    boolean_result00 = (true and true)

    -- === Test 01: AND - true and false ===
    boolean_result01 = (true and false)

    -- === Test 02: AND - false and true ===
    boolean_result02 = (false and true)

    -- === Test 03: AND - false and false ===
    boolean_result03 = (false and false)

    -- === Test 04: OR - true or true ===
    boolean_result04 = (true or true)

    -- === Test 05: OR - true or false ===
    boolean_result05 = (true or false)

    -- === Test 06: OR - false or true ===
    boolean_result06 = (false or true)

    -- === Test 07: OR - false or false ===
    boolean_result07 = (false or false)

    -- === Test 08: NOT - not true ===
    boolean_result08 = (not true)

    -- === Test 09: NOT - not false ===
    boolean_result09 = (not false)

    -- === Test 10: NOT - double negation true ===
    boolean_result10 = (not (not true))

    -- === Test 11: NOT - double negation false ===
    boolean_result11 = (not (not false))

    -- === Test 12: AND with numeric truthy values ===
    boolean_result12 = (1 and 2)

    -- === Test 13: AND with numeric falsy value (0) ===
    boolean_result13 = (0 and 1)

    -- === Test 14: OR with numeric truthy values ===
    boolean_result14 = (1 or 2)

    -- === Test 15: OR with numeric falsy value (0) ===
    boolean_result15 = (0 or 1)

    -- === Test 16: NOT with numeric truthy value ===
    boolean_result16 = (not 1)

    -- === Test 17: NOT with numeric falsy value (0) ===
    boolean_result17 = (not 0)

    -- === Test 18: Combined AND/OR - (true and false) or true ===
    boolean_result18 = ((true and false) or true)

    -- === Test 19: Combined AND/OR - true and (false or true) ===
    boolean_result19 = (true and (false or true))

    -- === Test 20: Combined AND/OR - (true or false) and true ===
    boolean_result20 = ((true or false) and true)

    -- === Test 21: Combined AND/OR - true or (false and true) ===
    boolean_result21 = (true or (false and true))

    -- === Test 22: Complex expression - true and true or false and true ===
    boolean_result22 = (true and true or false and true)

    -- === Test 23: Complex expression - not (true and false) or false ===
    boolean_result23 = (not (true and false) or false)

    -- === Test 24: Short-circuit AND - returns second value when first is truthy ===
    local function return_true() return true end
    local function return_false() return false end
    local function return_value() return 42 end
    
    -- AND short-circuit: if first is truthy, evaluate second
    if return_true() and return_value() then
        number_result24 = 1
    else
        number_result24 = 0
    end

    -- === Test 25: Short-circuit AND - doesn't evaluate second when first is falsy ===
    if return_false() and return_value() then
        number_result25 = 1
    else
        number_result25 = 0
    end

    -- === Test 26: Short-circuit OR - returns first value when truthy ===
    if return_true() or return_value() then
        number_result26 = 1
    else
        number_result26 = 0
    end

    -- === Test 27: Short-circuit OR - evaluates second when first is falsy ===
    if return_false() or return_value() then
        number_result27 = 1
    else
        number_result27 = 0
    end
end

function main()
    ioports.gpu.clear("black")
    test_logical_operators()

    print(000, 00,  "--- Logical Operators Test ---")
    print(000, 020, "Test 00 - AND T&T: " ..         tostring(boolean_result00))
    print(000, 040, "Test 01 - AND T&F: " ..         tostring(boolean_result01))
    print(000, 060, "Test 02 - AND F&T: " ..         tostring(boolean_result02))
    print(000, 080, "Test 03 - AND F&F: " ..         tostring(boolean_result03))
    print(000, 100, "Test 04 - OR T|T: " ..          tostring(boolean_result04))
    print(000, 120, "Test 05 - OR T|F: " ..          tostring(boolean_result05))
    print(000, 140, "Test 06 - OR F|T: " ..          tostring(boolean_result06))
    print(000, 160, "Test 07 - OR F|F: " ..          tostring(boolean_result07))
    print(000, 180, "Test 08 - NOT T: " ..           tostring(boolean_result08))
    print(000, 200, "Test 09 - NOT F: " ..           tostring(boolean_result09))
    print(000, 220, "Test 10 - NOT NOT T: " ..       tostring(boolean_result10))
    print(000, 240, "Test 11 - NOT NOT F: " ..       tostring(boolean_result11))
    print(000, 260, "Test 12 - AND num T: " ..        tostring(boolean_result12))
    print(200, 020, "Test 13 - AND num F: " ..        tostring(boolean_result13))
    print(200, 040, "Test 14 - OR num T: " ..         tostring(boolean_result14))
    print(200, 060, "Test 15 - OR num F: " ..         tostring(boolean_result15))
    print(200, 080, "Test 16 - NOT num T: " ..        tostring(boolean_result16))
    print(200, 100, "Test 17 - NOT num F: " ..        tostring(boolean_result17))
    print(200, 120, "Test 18 - (T&F)|T: " ..          tostring(boolean_result18))
    print(200, 140, "Test 19 - T&(F|T): " ..          tostring(boolean_result19))
    print(200, 160, "Test 20 - (T|F)&T: " ..          tostring(boolean_result20))
    print(200, 180, "Test 21 - T|(F&T): " ..          tostring(boolean_result21))
    print(200, 200, "Test 22 - T&T|F&T: " ..          tostring(boolean_result22))
    print(200, 220, "Test 23 - NOT(T&F)|F: " ..       tostring(boolean_result23))
    print(200, 240, "Test 24 - AND short T: " ..      number_result24)
    print(200, 260, "Test 25 - AND short F: " ..      number_result25)
    print(200, 280, "Test 26 - OR short T: " ..       number_result26)
    print(200, 300, "Test 27 - OR short F: " ..       number_result27)
end

--[[
=== EXPECTED OUTPUT ===

boolean_result00: true
boolean_result01: false
boolean_result02: false
boolean_result03: false
boolean_result04: true
boolean_result05: true
boolean_result06: true
boolean_result07: false
boolean_result08: false
boolean_result09: true
boolean_result10: true
boolean_result11: false
boolean_result12: true
boolean_result13: false
boolean_result14: true
boolean_result15: true
boolean_result16: false
boolean_result17: true
boolean_result18: true
boolean_result19: true
boolean_result20: true
boolean_result21: true
boolean_result22: true
boolean_result23: true
number_result24: 1.0000
number_result25: 0.0000
number_result26: 1.0000
number_result27: 1.0000

--]]
