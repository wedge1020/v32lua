--#title "v32lua scope unit test"
--@ Vircon32 Lua Scope Unit Test
--@ Tests local vs global variable scoping, shadowing, and visibility.
--@ Results are stored in global variables for automated memory scraping.

function test_scope()
    -- === Test 00: Global variable access ===
    global_var = 100
    number_result00 = global_var

    -- === Test 01: Local variable shadowing global ===
    local global_var = 200
    number_result01 = global_var

    -- === Test 02: Global variable unchanged after local shadow ===
    -- After test 01, global_var should still be 100
    number_result02 = global_var

    -- === Test 03: Local variable in function ===
    local function test_local()
        local local_var = 42
        return local_var
    end
    number_result03 = test_local()

    -- === Test 04: Local variable not accessible outside function ===
    -- This should not affect global state
    local function try_access()
        return local_var or 0
    end
    number_result04 = try_access()

    -- === Test 05: Nested local variables ===
    local function outer()
        local outer_var = 10
        local function inner()
            local inner_var = 20
            return outer_var + inner_var
        end
        return inner()
    end
    number_result05 = outer()

    -- === Test 06: Nested function accessing outer local ===
    local function make_adder(x)
        return function(y)
            return x + y
        end
    end
    local add5 = make_adder(5)
    number_result06 = add5(10)

    -- === Test 07: Local variable in if block ===
    if true then
        local if_local = 50
        number_result07 = if_local
    end

    -- === Test 08: Local variable not accessible after if block ===
    -- if_local should be nil here
    number_result08 = if_local or 0

    -- === Test 09: Local variable in while-like block (using if) ===
    local block_local
    if true then
        local block_local = 75
        number_result09 = block_local
    end

    -- === Test 10: Multiple local declarations ===
    local a, b, c = 1, 2, 3
    number_result10 = a + b + c

    -- === Test 11: Local variable reassignment ===
    local x = 10
    x = x + 5
    number_result11 = x

    -- === Test 12: Local variable with same name as builtin ===
    local print = 999
    number_result12 = print

    -- === Test 13: Global variable persists across function calls ===
    global_counter = global_counter or 0
    global_counter = global_counter + 1
    number_result13 = global_counter

    -- === Test 14: Local variable in different scopes ===
    local function scope_test()
        local test_var = 1
        return function()
            local test_var = 2
            return function()
                local test_var = 3
                return test_var
            end
        end
    end
    local getter = scope_test()()
    number_result14 = getter()

    -- === Test 15: Modifying captured local variable ===
    local function make_counter()
        local count = 0
        return function()
            count = count + 1
            return count
        end
    end
    local counter = make_counter()
    number_result15 = counter()
    number_result16 = counter()

    -- === Test 16: Global variable modified in function ===
    global_mod = 50
    local function modify_global()
        global_mod = global_mod + 10
    end
    modify_global()
    number_result17 = global_mod

    -- === Test 17: Local variable not visible to nested function without capture ===
    local function outer_scope()
        local hidden = 100
        local function inner_scope()
            return hidden
        end
        return inner_scope()
    end
    number_result18 = outer_scope()

    -- === Test 18: Shadowing in nested scopes ===
    local shadow_test = 1
    local function level1()
        local shadow_test = 2
        return function()
            local shadow_test = 3
            return shadow_test
        end
    end
    local inner = level1()
    number_result19 = inner()

    -- === Test 19: Global vs local precedence ===
    local precedence_test = 10
    global_precedence_test = 20
    number_result20 = precedence_test

    -- === Test 20: Accessing global when local doesn't exist ===
    number_result21 = global_precedence_test

    -- === Test 21: Local variable in for-like loop (using while) ===
    local i = 1
    local sum = 0
    while i <= 5 do
        local loop_var = i * 2
        sum = sum + loop_var
        i = i + 1
    end
    number_result22 = sum

    -- === Test 22: Local variable declared after use (forward reference) ===
    -- This should work with local declaration
    local forward_ref
    forward_ref = 42
    number_result23 = forward_ref

    -- === Test 23: Multiple assignment with mixed local/global ===
    local mixed_a, mixed_b = 10, 20
    number_result24 = mixed_a + mixed_b
end

function main()
    ioports.gpu.clear("black")
    test_scope()

    print(000, 00,  "--- Scope Test ---")
    print(000, 020, "Test 00 - Global access: " ..     number_result00)
    print(000, 040, "Test 01 - Local shadow: " ..      number_result01)
    print(000, 060, "Test 02 - Global unchanged: " ..   number_result02)
    print(000, 080, "Test 03 - Local in func: " ..     number_result03)
    print(000, 100, "Test 04 - Local not visible: " .. number_result04)
    print(000, 120, "Test 05 - Nested local: " ..     number_result05)
    print(000, 140, "Test 06 - Closure outer: " ..     number_result06)
    print(000, 160, "Test 07 - If local: " ..         number_result07)
    print(000, 180, "Test 08 - After if: " ..         number_result08)
    print(000, 200, "Test 09 - Block local: " ..      number_result09)
    print(000, 220, "Test 10 - Multi local: " ..       number_result10)
    print(000, 240, "Test 11 - Reassign: " ..          number_result11)
    print(000, 260, "Test 12 - Shadow builtin: " ..    number_result12)
    print(200, 020, "Test 13 - Global persist: " ..     number_result13)
    print(200, 040, "Test 14 - Nested scope: " ..     number_result14)
    print(200, 060, "Test 15 - Counter 1: " ..        number_result15)
    print(200, 080, "Test 16 - Counter 2: " ..        number_result16)
    print(200, 100, "Test 17 - Modify global: " ..     number_result17)
    print(200, 120, "Test 18 - Nested capture: " ..    number_result18)
    print(200, 140, "Test 19 - Shadow nest: " ..      number_result19)
    print(200, 160, "Test 20 - Local prec: " ..       number_result20)
    print(200, 180, "Test 21 - Global access: " ..     number_result21)
    print(200, 200, "Test 22 - Loop local: " ..       number_result22)
    print(200, 220, "Test 23 - Forward ref: " ..      number_result23)
    print(200, 240, "Test 24 - Mixed assign: " ..     number_result24)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 100.0000
number_result01: 200.0000
number_result02: 100.0000
number_result03: 42.0000
number_result04: 0.0000
number_result05: 30.0000
number_result06: 15.0000
number_result07: 50.0000
number_result08: 0.0000
number_result09: 75.0000
number_result10: 6.0000
number_result11: 15.0000
number_result12: 999.0000
number_result13: 1.0000
number_result14: 3.0000
number_result15: 1.0000
number_result16: 2.0000
number_result17: 60.0000
number_result18: 100.0000
number_result19: 3.0000
number_result20: 10.0000
number_result21: 20.0000
number_result22: 50.0000
number_result23: 42.0000
number_result24: 30.0000

--]]
