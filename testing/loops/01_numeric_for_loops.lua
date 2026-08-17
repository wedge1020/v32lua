--#title "v32lua numeric for loops unit test"
--@ Vircon32 Lua Numeric For Loops Unit Test - Comprehensive Coverage
--@ Tests all numeric for loop scenarios including edge cases and interactions.
--@ Results are stored in global variables for automated memory scraping.

function test_numeric_for_loops()
    -- === Test 00: Basic for loop (1 to 5) ===
    local sum1 = 0
    for i = 1, 5 do
        sum1 = sum1 + i
    end
    number_result00 = sum1

    -- === Test 01: For loop with step ===
    local sum2 = 0
    for i = 2, 10, 2 do
        sum2 = sum2 + i
    end
    number_result01 = sum2

    -- === Test 02: Countdown for loop ===
    local count = 0
    for i = 5, 1, -1 do
        count = count + 1
    end
    number_result02 = count

    -- === Test 03: For loop with non-integer step ===
    local sum3 = 0
    for i = 1, 5, 0.5 do
        sum3 = sum3 + i
    end
    number_result03 = sum3

    -- === Test 04: Nested for loops ===
    local product = 0
    for i = 1, 3 do
        for j = 1, 2 do
            product = product + (i * j)
        end
    end
    number_result04 = product

    -- === Test 05: Loop variable scope (should be local to loop) ===
    local scope_test
    for i = 1, 3 do
        scope_test = i
    end
    number_result05 = scope_test or 0

    -- === Test 06: Loop variable after loop (should be nil or last value) ===
    for i = 1, 5 do
        -- do nothing
    end
    number_result06 = i or 0

    -- === Test 07: Negative start and limit ===
    local neg_sum = 0
    for i = -5, -1 do
        neg_sum = neg_sum + i
    end
    number_result07 = neg_sum

    -- === Test 08: Step = 0 (should loop forever, but we break) ===
    local zero_step_count = 0
    for i = 1, 10, 0 do
        zero_step_count = zero_step_count + 1
        if zero_step_count >= 5 then break end
    end
    number_result08 = zero_step_count

    -- === Test 09: Step > limit (should not execute) ===
    local no_exec = 0
    for i = 10, 5, 1 do
        no_exec = no_exec + 1
    end
    number_result09 = no_exec

    -- === Test 10: Floating point boundaries ===
    local float_sum = 0
    for i = 1.5, 5.5, 1 do
        float_sum = float_sum + i
    end
    number_result10 = float_sum

    -- === Test 11: Expression boundaries ===
    local start = 3
    local expr_sum = 0
    for i = start, start + 4 do
        expr_sum = expr_sum + i
    end
    number_result11 = expr_sum

    -- === Test 12: Variable step ===
    local step = 3
    local var_step_sum = 0
    for i = 1, 10, step do
        var_step_sum = var_step_sum + i
    end
    number_result12 = var_step_sum

    -- === Test 13: For loop with break ===
    local break_val = 0
    for i = 1, 10 do
        if i == 5 then
            break_val = i
            break
        end
    end
    number_result13 = break_val

    -- === Test 14: For loop with early break ===
    local early_break = 0
    for i = 1, 100 do
        early_break = i
        if i == 1 then break end
    end
    number_result14 = early_break

    -- === Test 15: For loop with return (in function) ===
    local function for_with_return()
        for i = 1, 10 do
            if i == 3 then
                return i * 10
            end
        end
        return 0
    end
    number_result15 = for_with_return()

    -- === Test 16: Nested for with break (inner) ===
    local nested_break = 0
    for i = 1, 5 do
        for j = 1, 5 do
            if j == 3 then
                nested_break = i * 10 + j
                break
            end
        end
    end
    number_result16 = nested_break

    -- === Test 17: Nested for with break (outer) ===
    local outer_break_val = 0
    for i = 1, 5 do
        for j = 1, 5 do
            if i == 2 then
                outer_break_val = i * 100 + j
                break
            end
        end
        if i == 2 then
            break
        end
    end
    number_result17 = outer_break_val

    -- === Test 18: For loop with negative step ===
    local neg_step_sum = 0
    for i = 10, 1, -3 do
        neg_step_sum = neg_step_sum + i
    end
    number_result18 = neg_step_sum

    -- === Test 19: For loop with large range ===
    local large_count = 0
    for i = 1, 100, 10 do
        large_count = large_count + 1
    end
    number_result19 = large_count

    -- === Test 20: For loop with step > 1 ===
    local step3_sum = 0
    for i = 0, 10, 3 do
        step3_sum = step3_sum + i
    end
    number_result20 = step3_sum

    -- === Test 21: For loop with fractional step ===
    local frac_sum = 0
    local frac_count = 0
    for i = 0, 2, 0.5 do
        frac_sum = frac_sum + i
        frac_count = frac_count + 1
        if frac_count >= 5 then break end
    end
    number_result21 = frac_sum

    -- === Test 22: For loop with expression step ===
    local base_step = 2
    local expr_step_sum = 0
    for i = 1, 10, base_step + 1 do
        expr_step_sum = expr_step_sum + i
    end
    number_result22 = expr_step_sum

    -- === Test 23: For loop with modifying loop variable (should not affect loop) ===
    local mod_loop_val = 0
    for i = 1, 5 do
        mod_loop_val = mod_loop_val + i
        i = 100  -- This should not affect the loop
    end
    number_result23 = mod_loop_val
end

function main()
    ioports.gpu.clear("black")
    test_numeric_for_loops()

    print(000, 00,  "--- Numeric For Loops Expanded Test ---")
    print(000, 020, "Test 00 - Sum 1-5: " ..         number_result00)
    print(000, 040, "Test 01 - Sum evens 2-10: " ..   number_result01)
    print(000, 060, "Test 02 - Countdown: " ..        number_result02)
    print(000, 080, "Test 03 - Float step: " ..      number_result03)
    print(000, 100, "Test 04 - Nested: " ..          number_result04)
    print(000, 120, "Test 05 - Scope: " ..           number_result05)
    print(000, 140, "Test 06 - After loop: " ..      number_result06)
    print(000, 160, "Test 07 - Negative: " ..        number_result07)
    print(000, 180, "Test 08 - Zero step: " ..       number_result08)
    print(000, 200, "Test 09 - No exec: " ..         number_result09)
    print(000, 220, "Test 10 - Float bounds: " ..    number_result10)
    print(000, 240, "Test 11 - Expr bounds: " ..     number_result11)
    print(000, 260, "Test 12 - Var step: " ..        number_result12)
    print(200, 020, "Test 13 - Break: " ..           number_result13)
    print(200, 040, "Test 14 - Early break: " ..     number_result14)
    print(200, 060, "Test 15 - Return: " ..          number_result15)
    print(200, 080, "Test 16 - Nested break: " ..   number_result16)
    print(200, 100, "Test 17 - Outer break: " ..    number_result17)
    print(200, 120, "Test 18 - Neg step: " ..       number_result18)
    print(200, 140, "Test 19 - Large range: " ..     number_result19)
    print(200, 160, "Test 20 - Step 3: " ..         number_result20)
    print(200, 180, "Test 21 - Frac step: " ..      number_result21)
    print(200, 200, "Test 22 - Expr step: " ..      number_result22)
    print(200, 220, "Test 23 - Mod loop var: " ..   number_result23)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 15.0000
number_result01: 30.0000
number_result02: 5.0000
number_result03: 27.0000
number_result04: 18.0000
number_result05: 3.0000
number_result06: 0.0000
number_result07: -15.0000
number_result08: 5.0000
number_result09: 0.0000
number_result10: 17.5000
number_result11: 25.0000
number_result12: 22.0000
number_result13: 5.0000
number_result14: 1.0000
number_result15: 30.0000
number_result16: 53.0000
number_result17: 201.0000
number_result18: 22.0000
number_result19: 10.0000
number_result20: 18.0000
number_result21: 5.0000
number_result22: 22.0000
number_result23: 15.0000

--]]
