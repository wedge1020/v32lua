--@ Vircon32 Lua If/Elseif Chains Unit Test
--@ Tests elseif ladders of varying depth: 2-branch, 3-branch, deep
--@ chains, every position matching (first/middle/last/none), and an
--@ elseif chain nested inside another branch.
--@ Results are stored in global variables for automated memory scraping.

function test_elseif_chains()
    -- === Test 00: Two-branch ladder -- first condition true ===
    local x = 1
    if x == 1 then
        number_result00 = 10
    else
        number_result00 = 20
    end
    __rawasm__("__debug0:")

    -- === Test 01: Two-branch ladder -- else taken ===
    local y = 2
    if y == 1 then
        number_result01 = 10
    else
        number_result01 = 20
    end
    __rawasm__("__debug1:")

    -- === Test 02: Three-branch ladder -- first condition true ===
    local a = 1
    if a == 1 then
        number_result02 = 10
    elseif a == 2 then
        number_result02 = 20
    else
        number_result02 = 30
    end
    __rawasm__("__debug2:")

    -- === Test 03: Three-branch ladder -- middle condition true ===
    local b = 2
    if b == 1 then
        number_result03 = 10
    elseif b == 2 then
        number_result03 = 20
    else
        number_result03 = 30
    end
    __rawasm__("__debug3:")

    -- === Test 04: Three-branch ladder -- none match, else taken ===
    local c = 3
    if c == 1 then
        number_result04 = 10
    elseif c == 2 then
        number_result04 = 20
    else
        number_result04 = 30
    end
    __rawasm__("__debug4:")

    -- === Test 05: Deep chain (5 branches) -- matches the 4th ===
    local d = 4
    if d == 1 then
        number_result05 = 100
    elseif d == 2 then
        number_result05 = 200
    elseif d == 3 then
        number_result05 = 300
    elseif d == 4 then
        number_result05 = 400
    elseif d == 5 then
        number_result05 = 500
    else
        number_result05 = 600
    end
    __rawasm__("__debug5:")

    -- === Test 06: Elseif chain nested inside another branch's ===
    -- === else-body ===
    local outer_flag = false
    local inner_value = 3
    if outer_flag then
        number_result06 = 1
    else
        if inner_value == 1 then
            number_result06 = 10
        elseif inner_value == 2 then
            number_result06 = 20
        elseif inner_value == 3 then
            number_result06 = 30
        else
            number_result06 = 40
        end
    end
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_elseif_chains()

    print(000, 00,  "--- Elseif Chains Test ---")
    print(000, 020, "Test 00 - Two-branch 1st: " ..   number_result00)
    print(000, 040, "Test 01 - Two-branch else: " ..  number_result01)
    print(000, 060, "Test 02 - Three-branch 1st: " .. number_result02)
    print(000, 080, "Test 03 - Three-branch mid: " .. number_result03)
    print(000, 100, "Test 04 - Three-branch none: " .. number_result04)
    print(000, 120, "Test 05 - Deep chain 4th: " ..   number_result05)
    print(000, 140, "Test 06 - Nested elseif: " ..    number_result06)
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 10.0000
number_result01: 20.0000
number_result02: 10.0000
number_result03: 20.0000
number_result04: 30.0000
number_result05: 400.0000
number_result06: 30.0000
--]]
