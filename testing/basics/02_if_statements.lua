--#title "v32lua if statements unit test"
--@ Vircon32 Lua If Statements Unit Test
--@ Tests if/elseif/else control flow.
--@ Results are stored in global variables for automated memory scraping.

function test_if_statements()
    -- === Test 1: Simple if (true) ===
    if true then
        number_result1 = 1
    end

    -- === Test 2: Simple if (false) ===
    if false then
        number_result2 = 999
    else
        number_result2 = 2
    end

    -- === Test 3: if/elseif/else ladder ===
    local x = 2
    if x == 1 then
        number_result3 = 10
    elseif x == 2 then
        number_result3 = 20
    else
        number_result3 = 30
    end

    -- === Test 4: Nested if ===
    local a, b = 5, 10
    if a < b then
        if b > a then
            boolean_result1 = true
        else
            boolean_result1 = false
        end
    else
        boolean_result1 = false
    end

    -- === Test 5: Comparison operators ===
    local y, z = 15, 15
    boolean_result2 = (y == z)
    boolean_result3 = (y ~= z)
    boolean_result4 = (y < z)
    boolean_result5 = (y <= z)
    boolean_result6 = (y > z)
    boolean_result7 = (y >= z)

    -- === Test 6: Logical operators ===
    boolean_result8 = (true and false)
    boolean_result9 = (true or false)
    boolean_result10 = not true
end

function main()
    ioports.gpu.clear("black")
    test_if_statements()

    print(100, 00,  "--- If Statements Test ---")
    print(100, 20,  "Test 1 - If true: " ..        number_result1)
    print(100, 40,  "Test 2 - If false: " ..       number_result2)
    print(100, 60,  "Test 3 - Elseif: " ..         number_result3)
    print(100, 80,  "Test 4 - Nested if: " ..      tostring(boolean_result1))
    print(100, 100, "Test 5 - Equals: " ..         tostring(boolean_result2))
    print(100, 120, "Test 5 - Not equals: " ..     tostring(boolean_result3))
    print(100, 140, "Test 5 - Less than: " ..      tostring(boolean_result4))
    print(100, 160, "Test 5 - Less/equal: " ..     tostring(boolean_result5))
    print(100, 180, "Test 5 - Greater: " ..        tostring(boolean_result6))
    print(100, 200, "Test 5 - Greater/equal: " ..   tostring(boolean_result7))
    print(100, 220, "Test 6 - And: " ..            tostring(boolean_result8))
    print(100, 240, "Test 6 - Or: " ..             tostring(boolean_result9))
    print(100, 260, "Test 6 - Not: " ..            tostring(boolean_result10))
end

--[[
=== EXPECTED OUTPUT ===

number_result1: 1.0000
number_result2: 2.0000
number_result3: 20.0000
boolean_result1: true
boolean_result2: true
boolean_result3: false
boolean_result4: false
boolean_result5: true
boolean_result6: false
boolean_result7: true
boolean_result8: false
boolean_result9: true
boolean_result10: false

--]]
