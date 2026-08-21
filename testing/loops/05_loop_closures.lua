--#title "v32lua loop closure capture unit test"
--@ Vircon32 Lua Loop Closure Capture Unit Test
--@ Lua semantics require that a variable local TO a loop's body (or the
--@ loop variable itself, for numeric/generic for) gets a FRESH binding
--@ every iteration -- a closure created in iteration N must keep seeing
--@ iteration N's value even after later iterations change things. A
--@ variable declared OUTSIDE the loop, by contrast, is a single shared
--@ binding for the loop's entire run, and closures over it should all
--@ see whatever its latest value is.
--@
--@ This file tests both halves of that rule -- fresh-per-iteration
--@ binding for loop-local variables (across while, repeat, numeric-for,
--@ and generic-for), and a negative control confirming outer variables
--@ are NOT incorrectly given fresh bindings too.
--@ Results are stored in global variables for automated memory scraping.

function test_loop_closures()
    -- === Test 00: Numeric-for loop VARIABLE captured per-iteration ===
    local closures1 = {}
    for i = 1, 3 do
        closures1[i] = function() return i end
    end
    local sum1 = 0
    for j = 1, 3 do
        sum1 = sum1 + closures1[j]()
    end
    -- If i is correctly a fresh binding each iteration: 1+2+3 = 6.
    -- If all three closures alias one shared cell instead, this would
    -- come out some multiple of whatever i settled to after the loop.
    number_result00 = sum1
    __rawasm__("__debug0:")

    -- === Test 01: Generic-for loop VARIABLES captured per-iteration ===
    local t1 = {"a", "b", "c"}
    local closures2 = {}
    for idx, val in ipairs(t1) do
        closures2[idx] = function() return val end
    end
    local concatenated = ""
    for j = 1, 3 do
        concatenated = concatenated .. closures2[j]()
    end
    -- "abc" if val is fresh per-iteration; "ccc" if all three closures
    -- alias the same final binding instead.
    string_result00 = concatenated
    __rawasm__("__debug1:")

    -- === Test 02: While-loop BODY-LOCAL captured per-iteration ===
    local closures3 = {}
    local k = 1
    while k <= 3 do
        local captured = k * 10
        closures3[k] = function() return captured end
        k = k + 1
    end
    local sum2 = 0
    for j = 1, 3 do
        sum2 = sum2 + closures3[j]()
    end
    number_result01 = sum2  -- 10+20+30 = 60
    __rawasm__("__debug2:")

    -- === Test 03: Repeat/until BODY-LOCAL captured per-iteration ===
    local closures4 = {}
    local m = 1
    repeat
        local captured2 = m * 100
        closures4[m] = function() return captured2 end
        m = m + 1
    until m > 3
    local sum3 = 0
    for j = 1, 3 do
        sum3 = sum3 + closures4[j]()
    end
    number_result02 = sum3  -- 100+200+300 = 600
    __rawasm__("__debug3:")

    -- === Test 04: Nested loops -- closures capture BOTH outer and ===
    -- === inner loop variables independently for every combination ===
    local grid = {}
    for row = 1, 2 do
        for col = 1, 2 do
            grid[row * 10 + col] = function() return row * 100 + col end
        end
    end
    local total = grid[11]() + grid[12]() + grid[21]() + grid[22]()
    number_result03 = total  -- 101+102+201+202 = 606
    __rawasm__("__debug4:")

    -- === Test 05: Two closures created in the SAME iteration (one ===
    -- === reader, one writer) share THAT iteration's binding -- but ===
    -- === are still isolated from every OTHER iteration's binding ===
    local readers = {}
    local writers = {}
    for i = 1, 3 do
        local shared = i
        writers[i] = function() shared = shared + 100 end
        readers[i] = function() return shared end
    end
    writers[2]()  -- only mutate iteration 2's binding
    local r1 = readers[1]()  -- untouched -> 1
    local r2 = readers[2]()  -- mutated   -> 2 + 100 = 102
    local r3 = readers[3]()  -- untouched -> 3
    number_result04 = r1 + r2 + r3  -- 1 + 102 + 3 = 106
    __rawasm__("__debug5:")

    -- === Test 06: NEGATIVE CONTROL -- a variable declared OUTSIDE the ===
    -- === loop must NOT get a fresh binding per iteration. Every closure ===
    -- === that captures it shares the SAME cell and reports its latest ===
    -- === value, not a per-iteration snapshot. ===
    local outer_var = 0
    local closures5 = {}
    for i = 1, 3 do
        outer_var = outer_var + i
        closures5[i] = function() return outer_var end
    end
    local c1 = closures5[1]()
    local c2 = closures5[2]()
    local c3 = closures5[3]()
    -- Correct (single shared cell): all three see the FINAL value (6),
    -- so 6+6+6 = 18. An over-eager "fresh binding" fix applied to
    -- OUTER variables too (not just loop-locals) would instead give
    -- each closure its own iteration's snapshot (1, 3, 6), summing to
    -- 10 -- a regression this test exists specifically to catch.
    number_result05 = c1 + c2 + c3  -- 18
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_loop_closures()

    print(0, 0,   "--- Loop Closures Test ---")
    print(0, 20,  "Test 00 - Numeric-for capture: " .. number_result00)
    print(0, 40,  "Test 01 - Generic-for capture: " .. string_result00)
    print(0, 60,  "Test 02 - While body-local: " ..    number_result01)
    print(0, 80,  "Test 03 - Repeat body-local: " ..   number_result02)
    print(0, 100, "Test 04 - Nested capture: " ..      number_result03)
    print(0, 120, "Test 05 - Same-iter shared: " ..    number_result04)
    print(0, 140, "Test 06 - Outer var control: " ..   number_result05)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 6.0000
string_result00: "abc"
number_result01: 60.0000
number_result02: 600.0000
number_result03: 606.0000
number_result04: 106.0000
number_result05: 18.0000

--]]
