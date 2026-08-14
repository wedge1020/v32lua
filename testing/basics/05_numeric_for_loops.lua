--#title "v32lua numeric for loops unit test"
--@ Vircon32 Lua Numeric For Loops Unit Test
--@ Tests numeric for loop control flow.
--@ Results are stored in global variables for automated memory scraping.

function test_numeric_for_loops()
    -- === Test 1: Basic for loop (1 to 5) ===
    local sum1 = 0
    for i = 1, 5 do
        sum1 = sum1 + i
    end
    number_result1 = sum1  -- Expected: 15

    -- === Test 2: For loop with step ===
    local sum2 = 0
    for i = 2, 10, 2 do
        sum2 = sum2 + i
    end
    number_result2 = sum2  -- Expected: 30 (2+4+6+8+10)

    -- === Test 3: Countdown for loop ===
    local count = 0
    for i = 5, 1, -1 do
        count = count + 1
    end
    number_result3 = count  -- Expected: 5

    -- === Test 4: For loop with non-integer step ===
    local sum3 = 0
    for i = 1, 5, 0.5 do
        sum3 = sum3 + i
    end
    number_result4 = sum3  -- Expected: 27 (1+1.5+2+2.5+3+3.5+4+4.5+5)

    -- === Test 5: Nested for loops ===
    local product = 0
    for i = 1, 3 do
        for j = 1, 2 do
            product = product + (i * j)
        end
    end
    number_result5 = product  -- Expected: 18 (1*1 + 1*2 + 2*1 + 2*2 + 3*1 + 3*2)
end

function main()
    ioports.gpu.clear("black")
    test_numeric_for_loops()

    print(100, 00,  "--- Numeric For Loops Test ---")
    print(100, 20,  "Test 1 - Sum 1-5: " ..       number_result1)
    print(100, 40,  "Test 2 - Sum evens 2-10: " .. number_result2)
    print(100, 60,  "Test 3 - Countdown: " ..      number_result3)
    print(100, 80,  "Test 4 - Float step sum: " .. number_result4)
    print(100, 100, "Test 5 - Nested product: " .. number_result5)
end

--[[
=== EXPECTED OUTPUT ===

number_result1: 15.0000
number_result2: 30.0000
number_result3: 5.0000
number_result4: 27.0000
number_result5: 18.0000

--]]
