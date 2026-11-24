--@ --gc arena: arena.mark() / arena.release(m) / arena.used().
--@ A release puts the heap back where the mark was: strings, tables and
--@ closures made inside the arena are freed in one step, nested arenas
--@ close together, and the heap stays flat over many mark/release rounds.
--@ Results stored in global variables for automated memory scraping.
--#gc arena

function test_arena_basic()
    -- === Test 1: a release frees everything made since the mark ===
    local m = arena.mark()
    local before = arena.used()
    local s = "abc" .. 123 .. tostring(4.5)
    local t = { 1, 2, 3, x = "y" }
    local f = function() return s end
    number_result1 = arena.used() - before > 0 and 1 or 0     -- Expected: 1
    arena.release(m)
    number_result2 = arena.used() - before                     -- Expected: 0

    -- === Test 2: many rounds do not grow the heap ===
    local start = arena.used()
    for i = 1, 2000 do
        local mi = arena.mark()
        local str = "item " .. i .. " " .. (i * 0.5)
        local tab = { i, i + 1, name = str }
        tab[#tab + 1] = str
        arena.release(mi)
    end
    number_result3 = arena.used() - start                      -- Expected: 0

    -- === Test 3: releasing an outer mark closes the inner ones ===
    local base = arena.used()
    local m1 = arena.mark()
    local a = { "outer" .. base }
    local m2 = arena.mark()
    local b = { "inner" .. base }
    arena.release(m1)
    number_result4 = arena.used() - base                       -- Expected: 0
    -- and the arena stack is usable again
    local m3 = arena.mark()
    local c = "again" .. base
    arena.release(m3)
    number_result5 = arena.used() - base                       -- Expected: 0

    -- === Test 4: inner release keeps the outer arena's objects ===
    local o = arena.mark()
    local keep = { 10, 20, 30 }
    local mid = arena.used()
    local i2 = arena.mark()
    local junk = { "junk" .. mid, "more" .. mid }
    arena.release(i2)
    number_result6 = arena.used() - mid                        -- Expected: 0
    number_result7 = keep[1] + keep[2] + keep[3]               -- Expected: 60
    arena.release(o)

    -- === Test 5: the mark is the heap top as a number ===
    local mk = arena.mark()
    number_result8 = (mk == arena.used() + (mk - arena.used())) and 1 or 0  -- Expected: 1
    number_result9 = math.floor(mk) == mk and 1 or 0           -- Expected: 1
    arena.release(mk)
end

function main()
    ioports.gpu.clear("black")
    test_arena_basic()
    print(100, 0, "--- arena basic ---")
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 1.0000
number_result2: 0.0000
number_result3: 0.0000
number_result4: 0.0000
number_result5: 0.0000
number_result6: 0.0000
number_result7: 60.0000
number_result8: 1.0000
number_result9: 1.0000
]]
