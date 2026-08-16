--#title "v32lua if statements unit test"
--@ Vircon32 Lua If Statements Unit Test
--@ Tests if/elseif/else control flow with exhaustive coverage.
--@ Results are stored in global variables for automated memory scraping.

function test_if_statements()
    -- === Test 00: Simple if (true) with single statement ===
    if true then
        number_result00 = 1
    end

    -- === Test 01: Simple if (false) with single statement ===
    if false then
        number_result01 = 999
    end
    number_result01 = number_result01 or 0

    -- === Test 02: Simple if (true) with else ===
    if true then
        number_result02 = 1
    else
        number_result02 = 0
    end

    -- === Test 03: Simple if (false) with else ===
    if false then
        number_result03 = 0
    else
        number_result03 = 1
    end

    -- === Test 04: if/elseif/else ladder - first condition true ===
    local x = 1
    if x == 1 then
        number_result04 = 10
    elseif x == 2 then
        number_result04 = 20
    else
        number_result04 = 30
    end

    -- === Test 05: if/elseif/else ladder - second condition true ===
    local y = 2
    if y == 1 then
        number_result05 = 10
    elseif y == 2 then
        number_result05 = 20
    else
        number_result05 = 30
    end

    -- === Test 06: if/elseif/else ladder - no condition true ===
    local z = 3
    if z == 1 then
        number_result06 = 10
    elseif z == 2 then
        number_result06 = 20
    else
        number_result06 = 30
    end

    -- === Test 07: Multiple elseif - third condition true ===
    local w = 3
    if w == 1 then
        number_result07 = 10
    elseif w == 2 then
        number_result07 = 20
    elseif w == 3 then
        number_result07 = 30
    else
        number_result07 = 40
    end

    -- === Test 08: Nested if - both true ===
    local a, b = 5, 10
    if a < b then
        if b > a then
            boolean_result08 = true
        else
            boolean_result08 = false
        end
    else
        boolean_result08 = false
    end

    -- === Test 09: Nested if - outer false ===
    local c, d = 15, 10
    if c < d then
        if d > c then
            boolean_result09 = true
        else
            boolean_result09 = false
        end
    else
        boolean_result09 = false
    end

    -- === Test 10: Nested if - inner false ===
    local e, f = 5, 10
    if e < f then
        if f < e then
            boolean_result10 = true
        else
            boolean_result10 = false
        end
    else
        boolean_result10 = false
    end

    -- === Test 11: Compound statements in if block ===
    if true then
        local temp1 = 10
        local temp2 = 20
        number_result11 = temp1 + temp2
    end

    -- === Test 12: Compound statements in else block ===
    if false then
        number_result12 = 0
    else
        local temp1 = 15
        local temp2 = 25
        number_result12 = temp1 + temp2
    end

    -- === Test 13: if with comparison operator < ===
    if 5 < 10 then
        boolean_result13 = true
    else
        boolean_result13 = false
    end

    -- === Test 14: if with comparison operator > ===
    if 15 > 10 then
        boolean_result14 = true
    else
        boolean_result14 = false
    end

    -- === Test 15: if with comparison operator == ===
    if 10 == 10 then
        boolean_result15 = true
    else
        boolean_result15 = false
    end

    -- === Test 16: if with comparison operator ~= ===
    if 10 ~= 20 then
        boolean_result16 = true
    else
        boolean_result16 = false
    end

    -- === Test 17: if with comparison operator <= ===
    if 10 <= 10 then
        boolean_result17 = true
    else
        boolean_result17 = false
    end

    -- === Test 18: if with comparison operator >= ===
    if 20 >= 10 then
        boolean_result18 = true
    else
        boolean_result18 = false
    end

    -- === Test 19: if with logical AND (both true) ===
    if true and true then
        boolean_result19 = true
    else
        boolean_result19 = false
    end

    -- === Test 20: if with logical AND (first false) ===
    if false and true then
        boolean_result20 = true
    else
        boolean_result20 = false
    end

    -- === Test 21: if with logical OR (first true) ===
    if true or false then
        boolean_result21 = true
    else
        boolean_result21 = false
    end

    -- === Test 22: if with logical OR (both false) ===
    if false or false then
        boolean_result22 = true
    else
        boolean_result22 = false
    end

    -- === Test 23: if with logical NOT ===
    if not false then
        boolean_result23 = true
    else
        boolean_result23 = false
    end
end

function main()
    ioports.gpu.clear("black")
    test_if_statements()

    print(000, 00,  "--- If Statements Test ---")
    print(000, 020, "Test 00 - If true: " ..          number_result00)
    print(000, 040, "Test 01 - If false: " ..         number_result01)
    print(000, 060, "Test 02 - If/else true: " ..     number_result02)
    print(000, 080, "Test 03 - If/else false: " ..    number_result03)
    print(000, 100, "Test 04 - Elseif 1st: " ..       number_result04)
    print(000, 120, "Test 05 - Elseif 2nd: " ..       number_result05)
    print(000, 140, "Test 06 - Elseif none: " ..      number_result06)
    print(000, 160, "Test 07 - Elseif 3rd: " ..       number_result07)
    print(200, 020, "Test 08 - Nested both: " ..      tostring(boolean_result08))
    print(200, 040, "Test 09 - Nested outer: " ..     tostring(boolean_result09))
    print(200, 060, "Test 10 - Nested inner: " ..     tostring(boolean_result10))
    print(200, 080, "Test 11 - Compound if: " ..      number_result11)
    print(200, 100, "Test 12 - Compound else: " ..    number_result12)
    print(200, 120, "Test 13 - Less than: " ..        tostring(boolean_result13))
    print(200, 140, "Test 14 - Greater than: " ..      tostring(boolean_result14))
    print(200, 160, "Test 15 - Equals: " ..          tostring(boolean_result15))
    print(200, 180, "Test 16 - Not equals: " ..      tostring(boolean_result16))
    print(200, 200, "Test 17 - Less/equal: " ..      tostring(boolean_result17))
    print(200, 220, "Test 18 - Greater/equal: " ..   tostring(boolean_result18))
    print(200, 240, "Test 19 - And both: " ..        tostring(boolean_result19))
    print(200, 260, "Test 20 - And first false: " .. tostring(boolean_result20))
    print(200, 280, "Test 21 - Or first true: " ..   tostring(boolean_result21))
    print(200, 300, "Test 22 - Or both false: " ..  tostring(boolean_result22))
    print(200, 320, "Test 23 - Not: " ..            tostring(boolean_result23))
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 1.0000
number_result01: 0.0000
number_result02: 1.0000
number_result03: 1.0000
number_result04: 10.0000
number_result05: 20.0000
number_result06: 30.0000
number_result07: 30.0000
boolean_result08: true
boolean_result09: false
boolean_result10: false
number_result11: 30.0000
number_result12: 40.0000
boolean_result13: true
boolean_result14: true
boolean_result15: true
boolean_result16: true
boolean_result17: true
boolean_result18: true
boolean_result19: true
boolean_result20: false
boolean_result21: true
boolean_result22: false
boolean_result23: true

--]]
