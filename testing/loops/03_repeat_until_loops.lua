--#title "v32lua repeat/until loops unit test"
--@ Vircon32 Lua Repeat/Until Loops Unit Test - Comprehensive Coverage
--@ Tests repeat/until's two defining differences from while: the body
--@ always executes at least once, and the until-condition is evaluated
--@ INSIDE the body's own scope (so it can see body-local variables).
--@ Also covers break support and mixed nesting with other loop types.
--@ Results are stored in global variables for automated memory scraping.

function test_repeat_until_loops()
    -- === Test 00: Basic count up (post-test loop) ===
    local i = 1
    local sum = 0
    repeat
        sum = sum + i
        i = i + 1
    until i > 5
    number_result00 = sum
    __rawasm__("__debug0:")

    -- === Test 01: Body executes at least once, even though the ===
    -- === condition is already true before the loop is ever entered ===
    local x = 10
    local run_count = 0
    repeat
        run_count = run_count + 1
        x = x + 1
    until x > 0
    number_result01 = run_count   -- 1 -- runs exactly once, unlike while
    number_result02 = x           -- 11
    __rawasm__("__debug1:")

    -- === Test 02: until-condition sees a LOCAL DECLARED INSIDE THE BODY ===
    -- === -- this is the defining scoping difference from while/for ===
    local n = 0
    local iterations = 0
    repeat
        local done = (n >= 4)
        n = n + 1
        iterations = iterations + 1
    until done
    number_result03 = iterations  -- 5
    number_result04 = n           -- 5
    __rawasm__("__debug2:")

    -- === Test 03: break inside a repeat loop ===
    local count = 0
    repeat
        count = count + 1
        if count == 3 then
            break
        end
    until count >= 100
    number_result05 = count       -- 3
    __rawasm__("__debug3:")

    -- === Test 04: Nested repeat loops ===
    local outer = 1
    local inner_total = 0
    repeat
        local inner = 1
        repeat
            inner_total = inner_total + 1
            inner = inner + 1
        until inner > 2
        outer = outer + 1
    until outer > 3
    number_result06 = inner_total -- 3 outer passes * 2 inner iterations = 6
    __rawasm__("__debug4:")

    -- === Test 05: Complex AND condition in until ===
    local a, b = 0, 0
    local and_count = 0
    repeat
        and_count = and_count + 1
        a = a + 1
        b = b + 1
    until a >= 3 and b >= 3
    number_result07 = and_count   -- 3
    __rawasm__("__debug5:")

    -- === Test 06: Complex OR condition in until, with a safety-valve break ===
    local p, q = 0, 0
    local or_count = 0
    repeat
        or_count = or_count + 1
        p = p + 1
        q = q - 1
        if or_count >= 5 then break end
    until p >= 10 or q <= -10
    number_result08 = or_count    -- 5 -- break fires first; neither side of
                                   -- the OR is reached within 5 iterations
    __rawasm__("__debug6:")

    -- === Test 07: Function call (with side effects) in the until condition ===
    local counter = 0
    local function bump()
        counter = counter + 1
        return counter
    end
    local func_iters = 0
    repeat
        func_iters = func_iters + 1
    until bump() >= 3
    number_result09 = func_iters  -- 3
    __rawasm__("__debug7:")

    -- === Test 08: "until true" always executes the body exactly once, ===
    -- === regardless of what the body does ===
    local always_once = 0
    repeat
        always_once = always_once + 1
    until true
    number_result10 = always_once -- 1
    __rawasm__("__debug8:")

    -- === Test 09: break only exits its OWN (innermost) repeat loop ===
    local outer_passes = 0
    local inner_break_count = 0
    local o = 0
    repeat
        o = o + 1
        outer_passes = outer_passes + 1
        local i2 = 0
        repeat
            i2 = i2 + 1
            if i2 == 2 then
                inner_break_count = inner_break_count + 1
                break
            end
        until i2 >= 10
    until o >= 3
    number_result11 = outer_passes      -- 3 -- outer ran to completion
    number_result12 = inner_break_count -- 3 -- inner broke every pass
    __rawasm__("__debug9:")

    -- === Test 10: Mixed nesting -- generic-for nested inside repeat; ===
    -- === break in the generic-for must not affect the outer repeat ===
    local rows = {1, 2, 3}
    local repeat_passes = 0
    local rp = 0
    repeat
        rp = rp + 1
        repeat_passes = repeat_passes + 1
        for _, v in ipairs(rows) do
            if v == 2 then
                break
            end
        end
    until rp >= 2
    number_result13 = repeat_passes -- 2
    __rawasm__("__debug10:")

    -- === Test 11: Mixed nesting -- repeat nested inside numeric-for ===
    local for_total = 0
    for outer_i = 1, 3 do
        local r = 0
        repeat
            r = r + 1
            for_total = for_total + 1
        until r >= 2
    end
    number_result14 = for_total     -- 3 outer * 2 inner = 6
    __rawasm__("__debug11:")

    -- === Test 12: Table-draining pattern (a real-world repeat/until use) ===
    local stack = {10, 20, 30}
    local drained_count = 0
    repeat
        table.remove(stack)
        drained_count = drained_count + 1
    until #stack == 0
    number_result15 = drained_count -- 3
    __rawasm__("__debug12:")

    -- === Test 13: `return` from inside a repeat loop unwinds correctly ===
    local function first_multiple_of_7_over(threshold)
        local n2 = 0
        repeat
            n2 = n2 + 1
            if n2 % 7 == 0 and n2 > threshold then
                return n2
            end
        until n2 > 1000
        return -1
    end
    number_result16 = first_multiple_of_7_over(10) -- 14
    __rawasm__("__debug13:")

    -- === Test 14: break as the VERY FIRST statement in the loop body ===
    local immediate_break_count2 = 0
    repeat
		break
    until true
    number_result17 = immediate_break_count2   -- 0
    __rawasm__("__debug14:")

    -- === Test 15: Three-level-deep nested repeat loops ===
    local triple_repeat_count = 0
    local ra = 1
    repeat
        local rb = 1
        repeat
            local rc = 1
            repeat
                triple_repeat_count = triple_repeat_count + 1
                rc = rc + 1
            until rc > 2
            rb = rb + 1
        until rb > 2
        ra = ra + 1
    until ra > 2
    number_result18 = triple_repeat_count   -- 2*2*2 = 8
    __rawasm__("__debug15:")
end

function main()
    ioports.gpu.clear("black")
    test_repeat_until_loops()

    print(  0,   0,  "--- Repeat/Until Loops Test ---")
    print(  0,  20, "Test 00 - Count up sum: " ..        number_result00)
    print(  0,  40, "Test 01 - Runs once: " ..           number_result01)
    print(  0,  60, "Test 01 - Final x: " ..             number_result02)
    print(  0,  80, "Test 02 - Body-scope iters: " ..    number_result03)
    print(  0, 100, "Test 02 - Body-scope n: " ..        number_result04)
    print(  0, 120, "Test 03 - Break count: " ..         number_result05)
    print(  0, 140, "Test 04 - Nested total: " ..        number_result06)
    print(  0, 160, "Test 05 - AND cond: " ..            number_result07)
    print(  0, 180, "Test 06 - OR cond + break: " ..     number_result08)
    print(  0, 200, "Test 07 - Func in cond: " ..        number_result09)
    print(  0, 220, "Test 08 - Until true: " ..          number_result10)
    print(  0, 240, "Test 09 - Outer passes: " ..        number_result11)
    print(  0, 260, "Test 09 - Inner breaks: " ..        number_result12)
    print(320,  20, "Test 10 - Mixed (for-in-repeat): " .. number_result13)
    print(320,  40, "Test 11 - Mixed (repeat-in-for): " .. number_result14)
    print(320,  60, "Test 12 - Table drain: " ..         number_result15)
    print(320,  80, "Test 13 - Return unwind: " ..       number_result16)
    print(320, 100, "Test 14 - Immediate break: " ..     number_result17)
    print(320, 120, "Test 15 - Triple nested: " ..       number_result18)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 15.0000
number_result01: 1.0000
number_result02: 11.0000
number_result03: 5.0000
number_result04: 5.0000
number_result05: 3.0000
number_result06: 6.0000
number_result07: 3.0000
number_result08: 5.0000
number_result09: 3.0000
number_result10: 1.0000
number_result11: 3.0000
number_result12: 3.0000
number_result13: 2.0000
number_result14: 6.0000
number_result15: 3.0000
number_result16: 14.0000
number_result17: 0.0000
number_result18: 8.0000

--]]
