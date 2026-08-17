--#title "v32lua break statement unit test"
--@ Vircon32 Lua Break Statement Unit Test
--@ Tests 'break' inside while loops, numeric for loops, and generic for
--@ loops, including conditional breaks and nested-loop scoping (break
--@ only exits its own innermost loop). Results are stored in global
--@ variables for automated memory scraping.

function test_break()
    -- === Test 00: break in a while loop, unconditional after a count ===
    local count = 0
    while true do
        count = count + 1
        if count == 3 then
            break
        end
    end
    number_result00 = count

    -- === Test 01: break in a while loop leaves the loop's OWN state ===
    -- === exactly as it was at the point of the break (no extra iteration) ===
    local sum = 0
    local n = 0
    while n < 100 do
        n = n + 1
        if n > 5 then
            break
        end
        sum = sum + n
    end
    number_result01 = sum   -- 1+2+3+4+5 = 15, NOT 6 (n=6 never added)
    number_result02 = n     -- 6, the value that triggered the break

    -- === Test 02: break in a numeric for loop stops before reaching ===
    -- === the loop's own upper bound ===
    local total = 0
    for i = 1, 10 do
        if i > 4 then
            break
        end
        total = total + i
    end
    number_result03 = total   -- 1+2+3+4 = 10, not 1..10 = 55

    -- === Test 03: break in a numeric for loop with a non-default step ===
    local last_seen = 0
    for i = 0, 20, 5 do
        last_seen = i
        if i == 10 then
            break
        end
    end
    number_result04 = last_seen   -- 10, not 20

    -- === Test 04: break in a generic for loop (pairs/ipairs iteration) ===
    local items = {10, 20, 30, 40, 50}
    local seen_count = 0
    local running_total = 0
    for idx, value in ipairs(items) do
        seen_count = seen_count + 1
        running_total = running_total + value
        if idx == 3 then
            break
        end
    end
    number_result05 = seen_count      -- 3, not 5
    number_result06 = running_total   -- 10+20+30 = 60, not 150

    -- === Test 05: break only exits its OWN (innermost) loop -- the ===
    -- === outer loop keeps running normally ===
    local outer_iterations = 0
    local inner_breaks = 0
    for i = 1, 3 do
        outer_iterations = outer_iterations + 1
        for j = 1, 10 do
            if j == 2 then
                inner_breaks = inner_breaks + 1
                break
            end
        end
    end
    number_result07 = outer_iterations   -- 3 -- outer loop ran to completion
    number_result08 = inner_breaks       -- 3 -- inner loop broke every time

    -- === Test 06: break inside a generic for loop nested inside a ===
    -- === while loop -- mixing loop types, break must target the ===
    -- === CORRECT (innermost, generic-for) exit label, not the while's ===
    local rows = {1, 2, 3}
    local while_passes = 0
    local w = 0
    while w < 2 do
        w = w + 1
        while_passes = while_passes + 1
        for _, v in ipairs(rows) do
            if v == 2 then
                break
            end
        end
    end
    number_result09 = while_passes   -- 2 -- outer while completed both passes
end

function main()
    ioports.gpu.clear("black")
    test_break()

    print(000, 00,  "--- Break Statement Test ---")
    print(000, 020, "Test 00 - While count: " ..       number_result00)
    print(000, 040, "Test 01 - While sum: " ..         number_result01)
    print(000, 060, "Test 01 - While break val: " ..   number_result02)
    print(000, 080, "Test 02 - Numeric for sum: " ..   number_result03)
    print(000, 100, "Test 03 - Stepped for last: " ..  number_result04)
    print(000, 120, "Test 04 - Generic for count: " .. number_result05)
    print(000, 140, "Test 04 - Generic for total: " .. number_result06)
    print(000, 160, "Test 05 - Outer iterations: " ..  number_result07)
    print(000, 180, "Test 05 - Inner breaks: " ..      number_result08)
    print(000, 200, "Test 06 - Mixed nesting: " ..     number_result09)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 3.0000
number_result01: 15.0000
number_result02: 6.0000
number_result03: 10.0000
number_result04: 10.0000
number_result05: 3.0000
number_result06: 60.0000
number_result07: 3.0000
number_result08: 3.0000
number_result09: 2.0000

--]]
