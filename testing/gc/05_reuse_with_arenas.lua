--@ Block reuse together with --gc arena: blocks freed outside arenas are
--@ not handed out while an arena is open (an arena's objects must lie above
--@ its mark, or the release would not free them), a block freed inside an
--@ arena is dropped, and after the release the free lists are reused again
--@ -- with every older table still intact.
--@ Results stored in global variables for automated memory scraping.
--#gc arena

local function filled(n, base)
    local t = {}
    for i = 1, n do t[#t + 1] = base + i end
    return t
end

local function intact(t, n, base)
    if #t ~= n then return 0 end
    for i = 1, n do if t[i] ~= base + i then return 0 end end
    return 1
end

function test_reuse_with_arenas()
    -- free lists get blocks: tables grown outside any arena
    local a = filled(64, 100)
    local b = filled(64, 200)

    -- === Test 1: inside an arena, nothing comes from the free lists ===
    -- The freed 8/16/32 blocks would fit `inside`'s growth. Inside an arena
    -- they must not be used: the heap top rises by the whole table (header
    -- 5 + 8 + 16 + 32 words), so everything made there is above the mark.
    local before = arena.used()
    local m = arena.mark()
    local inside = filled(32, 300)
    local grew = arena.used() - before
    number_result1 = grew >= 61 and 1 or 0                     -- Expected: 1
    arena.release(m)
    number_result2 = arena.used() - before                     -- Expected: 0

    -- === Test 2: an older table grows inside an arena ===
    local c = filled(8, 400)             -- capacity 8
    local m2 = arena.mark()
    for i = 9, 40 do c[#c + 1] = 400 + i end   -- grows 8 -> 16 -> 32 -> 64 inside
    local junk = filled(50, 0)
    arena.release(m2)
    -- reuse happens again now: new tables may take c's old blocks
    local d = filled(64, 500)
    local e = filled(64, 600)
    number_result3 = intact(c, 40, 400)                        -- Expected: 1
    number_result4 = intact(a, 64, 100) + intact(b, 64, 200)   -- Expected: 2
    number_result5 = intact(d, 64, 500) + intact(e, 64, 600)   -- Expected: 2

    -- === Test 3: repeated arenas over a heap with free blocks stay flat ===
    local base = arena.used()
    for r = 1, 200 do
        local mr = arena.mark()
        local t = filled(20, r)
        local s = tostring(r + 0.25) .. "x"
        arena.release(mr)
    end
    number_result6 = arena.used() - base                       -- Expected: 0
    number_result7 = intact(c, 40, 400) + intact(d, 64, 500)   -- Expected: 2
end

function main()
    ioports.gpu.clear("black")
    test_reuse_with_arenas()
    print(100, 0, "--- reuse + arenas ---")
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 1.0000
number_result2: 0.0000
number_result3: 1.0000
number_result4: 2.0000
number_result5: 2.0000
number_result6: 0.0000
number_result7: 2.0000
]]
