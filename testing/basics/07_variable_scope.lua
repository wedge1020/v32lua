--#title "v32lua scope unit test"
--@ Vircon32 Lua Scope Unit Test
--@ Tests local vs global variable scoping, shadowing, visibility, and
--@ closures (captured-variable access, mutation, nesting, per-iteration
--@ loop capture). Results are stored in global variables for automated
--@ memory scraping.

function test_scope()
    -- === Test 00: Global variable access ===
    global_var = 100
    number_result00 = global_var

    -- === Test 01: Local variable shadowing global, SCOPED to a block ===
    -- The 'do...end' block matters: without it, 'local global_var' would
    -- shadow the global for the REST of test_scope(), and test 02 below
    -- would also read the shadowed value (200), not the true global (100)
    -- -- that's real Lua scoping, not a bug. Scoping the shadow to its own
    -- block is what makes "global unaffected by the shadow" a valid claim.
    do
        local global_var = 200
        number_result01 = global_var
    end

    -- === Test 02: Global variable unchanged after a SCOPED local shadow ===
    -- The shadow from test 01 went out of scope at 'end' above, so this
    -- reads the real global again.
    number_result02 = global_var

    -- === Test 03: Local variable in function ===
    local function test_local()
        local local_var = 42
        return local_var
    end
    number_result03 = test_local()

    -- === Test 04: Name not visible outside the function that declares it ===
    -- 'local_var' only exists inside test_local() above -- it was never
    -- declared here, so this resolves as an (unset) global, and 'or 0'
    -- catches that.
    local function try_access()
        return local_var or 0
    end
    number_result04 = try_access()

    -- === Test 05: Closure captures an enclosing local, READ ONLY ===
    -- Single mechanism, isolated: one level of nesting, one captured
    -- variable, read (not written) by the inner function.
    local function make_reader()
        local captured = 15
        local function reader()
            return captured
        end
        return reader()
    end
    number_result05 = make_reader()

    -- === Test 06: Closure captures a PARAMETER, not a local ===
    -- Isolated from test 05: here the captured variable is the enclosing
    -- function's own parameter, which arrives on the stack differently
    -- (as a raw pushed argument, boxed at function entry) than a 'local'
    -- declared inside the function body.
    local function make_adder(x)
        return function(y)
            return x + y
        end
    end
    local add5 = make_adder(5)
    number_result06 = add5(10)

    -- === Test 07: Closure that MUTATES its captured variable ===
    -- Distinct from read-only capture (test 05): the write must go through
    -- the same box the read does, and must be visible on subsequent calls
    -- to the SAME closure instance.
    local function make_counter()
        local count = 0
        return function()
            count = count + 1
            return count
        end
    end
    local counter = make_counter()
    number_result07 = counter()   -- first call: count becomes 1
    number_result08 = counter()   -- second call, SAME closure: count becomes 2

    -- === Test 09: Two independent closures from the same factory don't ===
    -- === share state ===
    -- Each call to make_counter() should allocate its OWN box for 'count'.
    -- If boxing were somehow shared across calls instead of per-activation,
    -- this counter would start from where the test 07/08 counter left off
    -- instead of from 0.
    local counter2 = make_counter()
    number_result10 = counter2()   -- independent counter: should be 1, not 3

    -- === Test 11: Two-level nesting -- captured value threads through an ===
    -- === intermediate function that doesn't itself use it ===
    -- outer_scope's local 'hidden' is captured by inner_scope, two levels
    -- down. inner_scope itself has no local named 'hidden' -- it only
    -- exists so we can verify the box pointer correctly passes THROUGH a
    -- level that doesn't declare the variable, not just directly across
    -- one level of nesting (already covered by test 05).
    local function outer_scope()
        local hidden = 100
        local function inner_scope()
            return hidden
        end
        return inner_scope()
    end
    number_result12 = outer_scope()

    -- === Test 12: Shadowing across nested closures ===
    -- Three different variables all named 'shadow_test', one per nesting
    -- level. Each closure should resolve to the ONE declared in its own
    -- (or nearest enclosing) scope, not leak into a sibling's.
    local shadow_test = 1
    local function level1()
        local shadow_test = 2
        return function()
            local shadow_test = 3
            return shadow_test
        end
    end
    local get_innermost = level1()
    number_result13 = get_innermost()   -- expect 3, the innermost shadow

    -- === Test 13: Global variable modified from inside a function ===
    -- Not a capture at all -- globals need no boxing, this exercises the
    -- ordinary global-write path for contrast with the capture tests above.
    global_mod = 50
    local function modify_global()
        global_mod = global_mod + 10
    end
    modify_global()
    number_result14 = global_mod

    -- === Test 14: Global variable persists across separate calls ===
    global_counter = global_counter or 0
    global_counter = global_counter + 1
    number_result15 = global_counter

    -- === Test 15: Local variable in an if-block, scoped correctly ===
    if true then
        local if_local = 50
        number_result16 = if_local
    end

    -- === Test 16: That if-block local is NOT visible after the block ===
    number_result17 = if_local or 0

    -- === Test 17: Per-ITERATION capture in a loop ===
    -- Each closure created in a different loop iteration must capture its
    -- OWN copy of the loop variable, not all alias the same box. Lua
    -- semantics: this must print 1, 2, 3 -- not 3, 3, 3.
    local fns = {}
    local i = 1
    while i <= 3 do
        local captured_i = i
        fns[i] = function() return captured_i end
        i = i + 1
    end

    number_result18 = fns[1]()
    number_result19 = fns[2]()
    number_result20 = fns[3]()

    -- === Test 18: Multiple local declarations ===
    local a, b, c = 1, 2, 3
    number_result21 = a + b + c

    -- === Test 19: Local variable reassignment (no capture involved) ===
    local x = 10
    x = x + 5
    number_result22 = x

    -- === Test 20: Local variable shadowing a builtin name ===
    local print = 999
    number_result23 = print

    -- === Test 21: Multiple assignment, mixed with arithmetic ===
    local mixed_a, mixed_b = 10, 20
    number_result24 = mixed_a + mixed_b
end

function main()
    ioports.gpu.clear("black")
    test_scope()

    print(000, 00,  "--- Scope Test ---")
    print(000, 020, "Test 00 - Global access: " ..      number_result00)
    print(000, 040, "Test 01 - Scoped shadow: " ..      number_result01)
    print(000, 060, "Test 02 - Global unchanged: " ..   number_result02)
    print(000, 080, "Test 03 - Local in func: " ..      number_result03)
    print(000, 100, "Test 04 - Local not visible: " ..  number_result04)
    print(000, 120, "Test 05 - Read capture: " ..       number_result05)
    print(000, 140, "Test 06 - Param capture: " ..      number_result06)
    print(000, 160, "Test 07 - Mutate capture 1: " ..   number_result07)
    print(000, 180, "Test 08 - Mutate capture 2: " ..   number_result08)
    print(000, 200, "Test 09 - Independent closure: " .. number_result10)
    print(000, 220, "Test 10 - Two-level capture: " ..  number_result12)
    print(000, 240, "Test 11 - Shadow nesting: " ..     number_result13)
    print(000, 260, "Test 12 - Modify global: " ..      number_result14)
    print(200, 020, "Test 13 - Global persist: " ..     number_result15)
    print(200, 040, "Test 14 - If-block local: " ..     number_result16)
    print(200, 060, "Test 15 - After if-block: " ..     number_result17)
    print(200, 080, "Test 16 - Loop capture[1]: " ..    number_result18)
    print(200, 100, "Test 16 - Loop capture[2]: " ..    number_result19)
    print(200, 120, "Test 16 - Loop capture[3]: " ..    number_result20)
    print(200, 140, "Test 17 - Multi local: " ..        number_result21)
    print(200, 160, "Test 18 - Reassign: " ..           number_result22)
    print(200, 180, "Test 19 - Shadow builtin: " ..     number_result23)
    print(200, 200, "Test 20 - Mixed assign: " ..       number_result24)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 100.0000
number_result01: 200.0000
number_result02: 100.0000
number_result03: 42.0000
number_result04: 0.0000
number_result05: 15.0000
number_result06: 15.0000
number_result07: 1.0000
number_result08: 2.0000
number_result10: 1.0000
number_result12: 100.0000
number_result13: 3.0000
number_result14: 60.0000
number_result15: 1.0000
number_result16: 50.0000
number_result17: 0.0000
number_result18: 1.0000
number_result19: 2.0000
number_result20: 3.0000
number_result21: 6.0000
number_result22: 15.0000
number_result23: 999.0000
number_result24: 30.0000

--]]
