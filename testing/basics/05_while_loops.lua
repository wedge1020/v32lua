--#title "v32lua while loops unit test"
--@ Vircon32 Lua While Loops Unit Test
--@ Tests while loop control flow.
--@ Results are stored in global variables for automated memory scraping.

function test_while_loops()
    -- === Test 1: Basic while loop (count up) ===
    local i = 1
    local sum = 0
    while i <= 5 do
        sum = sum + i
        i = i + 1
    end
    number_result1 = sum  -- Expected: 15 (1+2+3+4+5)

    -- === Test 2: While loop with break ===
    local j = 1
    while true do
        if j >= 3 then
            break
        end
        j = j + 1
    end
    number_result2 = j  -- Expected: 3

    -- === Test 3: Nested while loops ===
    local outer = 1
    local inner_sum = 0
    while outer <= 3 do
        local inner = 1
        while inner <= 2 do
            inner_sum = inner_sum + 1
            inner = inner + 1
        end
        outer = outer + 1
    end
    number_result3 = inner_sum  -- Expected: 6 (3 outer * 2 inner)

    -- === Test 4: While loop condition ===
    local k = 10
    local iterations = 0
    while k > 0 do
        iterations = iterations + 1
        k = k - 2
    end
    number_result4 = iterations  -- Expected: 5 (10,8,6,4,2)
end

function main()
    ioports.gpu.clear("black")
    test_while_loops()

    print(100, 00,  "--- While Loops Test ---")
    print(100, 20,  "Test 1 - Sum 1-5: " ..     number_result1)
    print(100, 40,  "Test 2 - Break at 3: " ..   number_result2)
    print(100, 60,  "Test 3 - Nested sum: " ..  number_result3)
    print(100, 80,  "Test 4 - Iterations: " ..  number_result4)
end

--[[
=== EXPECTED OUTPUT ===

number_result1: 15.0000
number_result2: 3.0000
number_result3: 6.0000
number_result4: 5.0000

--]]
