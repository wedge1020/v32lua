--#title "v32lua do-block unit test"
--@ Vircon32 Lua Do-Block Unit Test
--@ Tests standalone 'do ... end' block scoping: shadowing, nesting,
--@ interaction with closures and loops, and plain statement grouping.
--@ Results are stored in global variables for automated memory scraping.

function test_do_blocks()
    -- === Test 00: A local declared inside 'do...end' shadows only within ===
    -- === the block, and the shadow ends at 'end' ===
    local val = 1
    do
        local val = 2
        number_result00 = val
    end
    number_result01 = val

    -- === Test 01: 'do...end' with NO locals is pure statement grouping -- ===
    -- === it should have no effect on anything outside it ===
    local before = 10
    do
        before = before + 5
        number_result02 = before
    end
    number_result03 = before

    -- === Test 02: Assigning to an OUTER variable from inside a do-block ===
    -- === (no 'local' keyword) modifies the outer variable directly -- ===
    -- === no shadow is created, so this is visible after the block too ===
    local counter = 0
    do
        counter = counter + 1
        counter = counter + 1
    end
    number_result04 = counter

    -- === Test 03: Nested do-blocks -- each 'end' pops exactly one scope ===
    local depth = "outer"
    do
        local depth = "middle"
        do
            local depth = "inner"
            number_result05 = (depth == "inner") and 1 or 0
        end
        number_result06 = (depth == "middle") and 1 or 0
    end
    number_result07 = (depth == "outer") and 1 or 0

    -- === Test 04: Multiple locals declared inside one do-block ===
    do
        local a, b, c = 5, 10, 15
        number_result08 = a + b + c
    end

    -- === Test 05: A do-block-scoped local captured by a closure ===
    -- The closure should keep working (via its box) even though 'secret'
    -- itself is out of scope by the time the closure is actually called --
    -- this is the same guarantee ordinary function-local capture gives,
    -- just with the declaring scope being a do-block instead of a whole
    -- function body.
    local get_secret
    do
        local secret = 99
        get_secret = function() return secret end
    end
    number_result09 = get_secret()

    -- === Test 06: A do-block-scoped local, captured and MUTATED by a ===
    -- === closure defined inside the same block ===
    local bump
    do
        local hidden = 0
        bump = function()
            hidden = hidden + 1
            return hidden
        end
    end
    number_result10 = bump()   -- 1
    number_result11 = bump()   -- 2, same closure, same box

    -- === Test 07: 'do...end' inside a loop body -- one fresh scope per ===
    -- === iteration, each with its own closure capturing that iteration's ===
    -- === do-block-local (mirrors the per-iteration loop-variable capture ===
    -- === semantics, but for a local declared INSIDE the loop's do-block ===
    -- === rather than the loop variable itself) ===
    local fns = {}
    local i = 1
    while i <= 3 do
        do
            local doubled = i * 2
            fns[i] = function() return doubled end
        end
        i = i + 1
    end
    number_result12 = fns[1]()   -- 2
    number_result13 = fns[2]()   -- 4
    number_result14 = fns[3]()   -- 6

    -- === Test 08: A do-block inside an if-block, and vice versa -- ===
    -- === scoping constructs should compose without interfering ===
    if true then
        do
            local composed = 7
            number_result15 = composed
        end
    end
    do
        if true then
            local composed = 8
            number_result16 = composed
        end
    end
end

function main()
    ioports.gpu.clear("black")
    test_do_blocks()

    print(000, 00,  "--- Do-Block Test ---")
    print(000, 020, "Test 00 - Shadow inside: " ..    number_result00)
    print(000, 040, "Test 00 - Outer after: " ..      number_result01)
    print(000, 060, "Test 01 - Grouping inside: " ..  number_result02)
    print(000, 080, "Test 01 - Grouping after: " ..   number_result03)
    print(000, 100, "Test 02 - Outer write: " ..      number_result04)
    print(000, 120, "Test 03 - Nested inner: " ..     number_result05)
    print(000, 140, "Test 03 - Nested middle: " ..    number_result06)
    print(000, 160, "Test 03 - Nested outer: " ..     number_result07)
    print(000, 180, "Test 04 - Multi-local sum: " ..  number_result08)
    print(000, 200, "Test 05 - Block capture: " ..    number_result09)
    print(000, 220, "Test 06 - Mutate capture 1: " .. number_result10)
    print(000, 240, "Test 06 - Mutate capture 2: " .. number_result11)
    print(000, 260, "Test 07 - Loop block[1]: " ..    number_result12)
    print(200, 020, "Test 07 - Loop block[2]: " ..    number_result13)
    print(200, 040, "Test 07 - Loop block[3]: " ..    number_result14)
    print(200, 060, "Test 08 - do-in-if: " ..         number_result15)
    print(200, 080, "Test 08 - if-in-do: " ..         number_result16)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 2.0000
number_result01: 1.0000
number_result02: 15.0000
number_result03: 15.0000
number_result04: 2.0000
number_result05: 1.0000
number_result06: 1.0000
number_result07: 1.0000
number_result08: 30.0000
number_result09: 99.0000
number_result10: 1.0000
number_result11: 2.0000
number_result12: 2.0000
number_result13: 4.0000
number_result14: 6.0000
number_result15: 7.0000
number_result16: 8.0000

--]]
