--@ --gc arena: a table made BEFORE an arena that grows inside it keeps its
--@ new array and hash blocks after the release (they are pinned), so the
--@ allocations of later arenas cannot overwrite them. A long string made in
--@ an arena is measured again after the release (STRLEN_CACHE forgets it).
--@ Without pinning, Test 1 reads back a corrupted list (checked by patching
--@ __malloc_owned out of the generated assembly: sum -63, then a crash).
--@ Results stored in global variables for automated memory scraping.
--#gc arena

function test_arena_pinning()
    -- === Test 1: an older list grows inside an arena ===
    local list = {}
    local m = arena.mark()
    for i = 1, 100 do list[#list + 1] = i end
    arena.release(m)
    -- fill the heap where the arena was with other data
    local m2 = arena.mark()
    for i = 1, 50 do local junk = { -1, -1, -1, -1, -1, -1, -1, -1 } end
    local sum = 0
    for i = 1, #list do sum = sum + list[i] end
    number_result1 = #list                                     -- Expected: 100
    number_result2 = sum                                       -- Expected: 5050
    arena.release(m2)

    -- === Test 2: an older table's hash part grows inside an arena ===
    local h = { a = 1 }
    local m3 = arena.mark()
    h.b = 2  h.c = 3  h.d = 4  h.e = 5  h.f = 6  h.g = 7  h.h = 8  h.i = 9  h.j = 10
    arena.release(m3)
    local m4 = arena.mark()
    for i = 1, 50 do local junk = { k1 = i, k2 = i, k3 = i, k4 = i } end
    number_result3 = h.a + h.b + h.c + h.d + h.e + h.f + h.g + h.h + h.i + h.j  -- Expected: 55
    arena.release(m4)

    -- === Test 3: the heap does not grow past the pinned blocks ===
    local base = arena.used()
    local m5 = arena.mark()
    local s = "x" .. base
    arena.release(m5)
    number_result4 = arena.used() - base                       -- Expected: 0

    -- === Test 4: string lengths after a release ===
    local m6 = arena.mark()
    local long1 = string.rep("a", 100)
    number_result5 = #long1                                    -- Expected: 100
    arena.release(m6)
    local m7 = arena.mark()
    local long2 = string.rep("b", 70)                          -- same address
    number_result6 = #long2                                    -- Expected: 70
    arena.release(m7)
end

function main()
    ioports.gpu.clear("black")
    test_arena_pinning()
    print(100, 0, "--- arena pinning ---")
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 100.0000
number_result2: 5050.0000
number_result3: 55.0000
number_result4: 0.0000
number_result5: 100.0000
number_result6: 70.0000
]]
