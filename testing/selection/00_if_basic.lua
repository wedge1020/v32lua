--@ Vircon32 Lua If Statements Basic Unit Test
--@ Tests bare if/else forms: single-branch, two-branch, empty bodies,
--@ compound statement blocks, and nesting.
--@ Results are stored in global variables for automated memory scraping.

function test_if_basic()
    -- === Test 00: Bare if(true) executes its body ===
    if true then
        number_result00 = 1
    end
    __rawasm__("__debug0:")

    -- === Test 01: Bare if(false) does not execute its body ===
    if false then
        number_result01 = 999
    end
    number_result01 = number_result01 or 0
    __rawasm__("__debug1:")

    -- === Test 02: if/else -- true branch taken ===
    if true then
        number_result02 = 1
    else
        number_result02 = 0
    end
    __rawasm__("__debug2:")

    -- === Test 03: if/else -- false branch taken ===
    if false then
        number_result03 = 0
    else
        number_result03 = 1
    end
    __rawasm__("__debug3:")

    -- === Test 04: Empty then-body -- must not crash, execution ===
    -- === continues normally afterward ===
    if true then
    end
    number_result04 = 42
    __rawasm__("__debug4:")

    -- === Test 05: Nested if -- both true ===
    local a, b = 5, 10
    if a < b then
        if b > a then
            boolean_result05 = true
        else
            boolean_result05 = false
        end
    else
        boolean_result05 = false
    end
    __rawasm__("__debug5:")

    -- === Test 06: Nested if -- outer false short-circuits the whole ===
    -- === branch, inner body never runs ===
    local inner_ran = false
    if false then
        inner_ran = true
    end
    boolean_result06 = inner_ran
    __rawasm__("__debug6:")

    -- === Test 07: Compound multi-statement then-block ===
    if true then
        local temp1 = 10
        local temp2 = 20
        number_result07 = temp1 + temp2
    end
    __rawasm__("__debug7:")
end

function main()
    ioports.gpu.clear("black")
    test_if_basic()

    print(000, 00,  "--- If Basic Test ---")
    print(000, 020, "Test 00 - If true: " ..        number_result00)
    print(000, 040, "Test 01 - If false: " ..       number_result01)
    print(000, 060, "Test 02 - If/else true: " ..   number_result02)
    print(000, 080, "Test 03 - If/else false: " ..  number_result03)
    print(000, 100, "Test 04 - Empty body: " ..     number_result04)
    print(000, 120, "Test 05 - Nested both: " ..    tostring(boolean_result05))
    print(000, 140, "Test 06 - Outer false: " ..    tostring(boolean_result06))
    print(000, 160, "Test 07 - Compound: " ..       number_result07)
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 1.0000
number_result01: 0.0000
number_result02: 1.0000
number_result03: 1.0000
number_result04: 42.0000
boolean_result05: true
boolean_result06: false
number_result07: 30.0000
--]]
