--#title "[v32lua] table.move() unit test"
--@ Vircon32 Lua table.move() Unit Test
--@ Tests ONLY the table.move() library function (Lua 5.3+).
--@ Results are stored in global variables for automated memory scraping.
--@
--@ table.move(a1, f, e, t, [a2]) copies a1[f..e] into a2[t..t+(e-f)] and
--@ touches NOTHING outside that destination range -- it is a bounded
--@ range-copy, not a full-array shift or rotate. Every expected value
--@ below was re-derived directly from that definition (previous version
--@ of this file had three expectations that assumed indices OUTSIDE the
--@ destination range would also change, which isn't how table.move works
--@ in real Lua -- corrected here, with the reasoning left in-line).

function test_table_move()
    -- === Test 1: Move within same table (non-overlapping) ===
    -- Copies t1[1..3] into t1[4..6]. Destination range is 4-6, so ONLY
    -- indices 4, 5, 6 are ever written. Index 1 is read (as part of the
    -- source range) but never written, so it keeps its original value.
    local t1 = {"a", "b", "c", "d", "e"}
    table.move(t1, 1, 3, 4)
    string_result1 = t1[4]  -- Expected: "a" (moved from 1->4)
    string_result2 = t1[5]  -- Expected: "b" (moved from 2->5)
    string_result3 = t1[6]  -- Expected: "c" (moved from 3->6)
    string_result4 = t1[1]  -- Expected: "a" (source index, untouched as a destination)

    -- === Test 2: Move with overlap (forward destination) ===
    -- Source range 1-2, destination range 2-3 -- these overlap at index 2.
    -- Because t(2) > f(1), a correct implementation must copy backward
    -- (index 2 before index 1) so the read of t2[2] happens before it
    -- gets overwritten by the first copy step.
    local t2 = {"a", "b", "c", "d"}
    table.move(t2, 1, 2, 2)
    string_result5 = t2[2]  -- Expected: "a" (overwrote "b")
    string_result6 = t2[3]  -- Expected: "b" (overwrote "c")

    -- === Test 3: Move between DIFFERENT tables ===
    -- Destination range is t4[2..3] only. t4[4] is never a destination
    -- here (range is 2-3, not 2-4), so it must keep its original value.
    local t3 = {"x", "y", "z"}
    local t4 = {1, 2, 3, 4}
    table.move(t3, 1, 2, 2, t4)
    string_result7 = t4[2]  -- Expected: "x"
    string_result8 = t4[3]  -- Expected: "y"
    number_result1 = t4[4]  -- Expected: 4 (outside the destination range, untouched)

    -- === Test 4: Move to beginning (overlap, forward-safe direction) ===
    -- Source range 2-3, destination range 1-2. t(1) is NOT > f(2), so
    -- this is the forward-safe overlap case (no backward copy needed).
    -- Destination range is only 1-2, so index 3 is never a destination
    -- and must keep its original value.
    local t5 = {"a", "b", "c"}
    table.move(t5, 2, 3, 1)
    string_result9 = t5[1]   -- Expected: "b"
    string_result10 = t5[2]  -- Expected: "c"
    string_result11 = t5[3]  -- Expected: "c" (source index, untouched as a destination)

    -- === Test 5: Same table, explicitly passed as its own a2 ===
    -- Identical to omitting a2, but exercises the explicit-a2-equals-a1
    -- path specifically (a2 argument present, not defaulted via nil) --
    -- this must still trigger the overlap/backward-copy logic, not skip
    -- it just because a2 was written out explicitly.
    local t6 = {"p", "q", "r", "s"}
    table.move(t6, 1, 2, 3, t6)
    string_result12 = t6[3]  -- Expected: "p"
    string_result13 = t6[4]  -- Expected: "q"

    -- === Test 6: Empty/reversed range (e < f) is a no-op ===
    -- Nothing to copy, so the destination table must come back completely
    -- unchanged, and table.move should still return a2.
    local t7 = {"x", "y", "z"}
    local returned = table.move(t7, 3, 1, 1)  -- e(1) < f(3): empty range
    string_result14 = t7[1]  -- Expected: "x" (unchanged)
    string_result15 = t7[2]  -- Expected: "y" (unchanged)
    string_result16 = t7[3]  -- Expected: "z" (unchanged)
    boolean_result1 = (returned == t7)  -- Expected: true (still returns a2)
end

function main()
    ioports.gpu.clear("black")
    test_table_move()

    print(100, 00,  "--- table.move() Test ---")
    print(100, 20,  "Test 1 - Dest[4]: " .. string_result1)
    print(100, 40,  "Test 1 - Dest[5]: " .. string_result2)
    print(100, 60,  "Test 1 - Dest[6]: " .. string_result3)
    print(100, 80,  "Test 1 - Src[1] untouched: " .. string_result4)
    print(100, 100, "Test 2 - Overlap[2]: " .. string_result5)
    print(100, 120, "Test 2 - Overlap[3]: " .. string_result6)
    print(100, 140, "Test 3 - Dest[2]: " .. string_result7)
    print(100, 160, "Test 3 - Dest[3]: " .. string_result8)
    print(100, 180, "Test 3 - Outside range: " .. number_result1)
    print(100, 200, "Test 4 - To start[1]: " .. string_result9)
    print(100, 220, "Test 4 - To start[2]: " .. string_result10)
    print(100, 240, "Test 4 - Src[3] untouched: " .. string_result11)
    print(100, 260, "Test 5 - Explicit self[3]: " .. string_result12)
    print(100, 280, "Test 5 - Explicit self[4]: " .. string_result13)
    print(100, 300, "Test 6 - Empty range[1]: " .. string_result14)
    print(100, 320, "Test 6 - Empty range[2]: " .. string_result15)
    print(100, 340, "Test 6 - Empty range[3]: " .. string_result16)
    print(100, 360, "Test 6 - Returns a2: " .. tostring(boolean_result1))
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "a"
string_result2: "b"
string_result3: "c"
string_result4: "a"
string_result5: "a"
string_result6: "b"
string_result7: "x"
string_result8: "y"
number_result1: 4.0000
string_result9: "b"
string_result10: "c"
string_result11: "c"
string_result12: "p"
string_result13: "q"
string_result14: "x"
string_result15: "y"
string_result16: "z"
boolean_result1: true
]]
