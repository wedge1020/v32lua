--#title "[v32lua] native tilemap unit test"
--#tilemap TESTMAP  "tilemap_basic.map"
--#tilemap OTHERMAP "tilemap_other.map"

--@ Vircon32 Lua native tilemap() Unit Test
--@ --#tilemap NAME "file.csv" declares a tilemap: a rectangular grid of
--@ tile ids, read from a CSV file (comma-separated values, one row per
--@ line) at compile time. Unlike --#texture/--#sound this is NOT a
--@ cart-XML resource -- there's no <textures>/<sounds> entry and no
--@ resource id baked into generated code. Its data is embedded directly
--@ as literal values in the assembled program.
--@
--@ tilemap.get(NAME, x, y) / tilemap.set(NAME, x, y, v) -- NAME must be
--@ a bare --#tilemap-declared identifier, resolved entirely at compile
--@ time. It is NEVER a runtime value: there's no way to compute "which
--@ tilemap" dynamically, the same restriction --#sound/--#texture names
--@ already have and for the same reason (there's nothing sensible for a
--@ dynamic name to even resolve against).
--@
--@ Storage is lazy: a tilemap starts life read-only, sitting wherever
--@ the compiler placed its data. The FIRST tilemap.set() against a given
--@ tilemap promotes it -- allocates a private RAM copy and copies every
--@ cell across -- and only after that does the tilemap become mutable.
--@ Every read or write before that point, and every read or write to a
--@ DIFFERENT tilemap that hasn't been promoted, is unaffected. Test 15
--@ below exists specifically to catch a promotion bug that re-triggers
--@ on a second write and silently discards every edit made so far.
--@
--@ Bounds are enforced but asymmetrically: tilemap.get() out of bounds
--@ returns nil, same as reading past the end of a Lua table. tilemap.set()
--@ out of bounds is a silent no-op -- there's no sensible value to
--@ return for "you tried to write nowhere," so it just declines.
--@
--@ IMPORTANT LIMITATION: tile values are stored and returned as plain
--@ numbers with no clamping -- unlike the TIC-80 compatibility layer's
--@ mset(), which clamps to 0-255 because TIC-80 sprite ids are byte-
--@ sized. The native API makes no such assumption, since a tile value
--@ here is just whatever the calling code wants it to mean (typically a
--@ GPU region id for spr(), which can run well past 255).

function test_tilemap()
    -- === Test 00: ROM read, top-left corner (0,0) ===
    number_result00 = tilemap.get(TESTMAP, 0, 0)  -- Expected: 1
    __rawasm__("__debug00:")

    -- === Test 01: ROM read, top-right corner (2,0) ===
    number_result01 = tilemap.get(TESTMAP, 2, 0)  -- Expected: 3
    __rawasm__("__debug01:")

    -- === Test 02: ROM read, center (1,1) ===
    number_result02 = tilemap.get(TESTMAP, 1, 1)  -- Expected: 5
    __rawasm__("__debug02:")

    -- === Test 03: ROM read, bottom-left corner (0,2) ===
    number_result03 = tilemap.get(TESTMAP, 0, 2)  -- Expected: 7
    __rawasm__("__debug03:")

    -- === Test 04: ROM read, bottom-right corner (2,2) -- this exact cell ===
    -- === gets revisited after promotion below, to confirm the ROM->RAM ===
    -- === copy preserved it ===
    number_result04 = tilemap.get(TESTMAP, 2, 2)  -- Expected: 9
    __rawasm__("__debug04:")

    -- === Test 05: Out-of-bounds read, x too low ===
    number_result05 = (tilemap.get(TESTMAP, -1, 0) == nil) and 1 or 0  -- Expected: 1
    __rawasm__("__debug05:")

    -- === Test 06: Out-of-bounds read, x too high ===
    number_result06 = (tilemap.get(TESTMAP, 3, 0) == nil) and 1 or 0  -- Expected: 1
    __rawasm__("__debug06:")

    -- === Test 07: Out-of-bounds read, y too low -- the original draft of ===
    -- === this test only checked y-too-high; a bounds bug specific to the ===
    -- === lower edge would have gone uncaught ===
    number_result07 = (tilemap.get(TESTMAP, 0, -1) == nil) and 1 or 0  -- Expected: 1
    __rawasm__("__debug07:")

    -- === Test 08: Out-of-bounds read, y too high ===
    number_result08 = (tilemap.get(TESTMAP, 0, 3) == nil) and 1 or 0  -- Expected: 1
    __rawasm__("__debug08:")

    -- === Test 09: First set() call -- promotes TESTMAP from ROM to a RAM ===
    -- === copy. Confirms the write itself lands. ===
    tilemap.set(TESTMAP, 1, 1, 99)
    number_result09 = tilemap.get(TESTMAP, 1, 1)  -- Expected: 99
    __rawasm__("__debug09:")

    -- === Test 10: Confirms the promotion copy preserved a cell OTHER than ===
    -- === the one just written -- this is the ROM->RAM copy loop being right ===
    number_result10 = tilemap.get(TESTMAP, 0, 0)  -- Expected: 1
    __rawasm__("__debug10:")

    -- === Test 11: Same check at the opposite corner from the write ===
    number_result11 = tilemap.get(TESTMAP, 2, 2)  -- Expected: 9
    __rawasm__("__debug11:")

    -- === Test 12: Out-of-bounds set() must be a silent no-op, not a crash ===
    -- === or a write into whatever RAM happens to sit past the buffer ===
    tilemap.set(TESTMAP, 99, 99, 1234)
    number_result12 = tilemap.get(TESTMAP, 2, 2)  -- Expected: 9 (unchanged)
    __rawasm__("__debug12:")

    -- === Test 13: set() at the exact max-valid corner (width-1, height-1) ===
    -- === -- an inclusive/exclusive bounds mixup would misfire exactly here ===
    tilemap.set(TESTMAP, 2, 2, 55)
    number_result13 = tilemap.get(TESTMAP, 2, 2)  -- Expected: 55
    __rawasm__("__debug13:")

    -- === Test 14: Confirms test 13's write didn't disturb test 09's ===
    -- === earlier write -- two independent cells in the same promoted buffer ===
    number_result14 = tilemap.get(TESTMAP, 1, 1)  -- Expected: 99 (still)
    __rawasm__("__debug14:")

    -- === Test 15: A SECOND set() call on an already-promoted tilemap. The ===
    -- === promotion check must key off the saved ram_ptr and skip straight ===
    -- === to the store -- if it fired again, it would re-copy from ROM and ===
    -- === silently erase every write made so far. ===
    tilemap.set(TESTMAP, 0, 1, 42)
    number_result15 = tilemap.get(TESTMAP, 0, 1)  -- Expected: 42
    __rawasm__("__debug15:")

    -- === Test 16: The actual regression check for test 15's concern -- if ===
    -- === set() had wrongly re-promoted, this reads back 5 (the original ===
    -- === ROM value) instead of 99 ===
    number_result16 = tilemap.get(TESTMAP, 1, 1)  -- Expected: 99
    __rawasm__("__debug16:")

    -- === Test 17: Same re-promotion check against test 13's write ===
    number_result17 = tilemap.get(TESTMAP, 2, 2)  -- Expected: 55
    __rawasm__("__debug17:")

    -- === Test 18: A SECOND, independently-declared tilemap -- confirms two ===
    -- === --#tilemap hints don't share a RAM promotion pointer or a ROM ===
    -- === label. Read before any write to OTHERMAP. ===
    number_result18 = tilemap.get(OTHERMAP, 0, 0)  -- Expected: 10
    __rawasm__("__debug18:")

    -- === Test 19: A second cell of OTHERMAP, confirming its own ROM ===
    -- === layout (not just cell 0,0) is correct ===
    number_result19 = tilemap.get(OTHERMAP, 1, 1)  -- Expected: 40
    __rawasm__("__debug19:")

    -- === Test 20: Promote OTHERMAP independently of TESTMAP ===
    tilemap.set(OTHERMAP, 0, 0, 77)
    number_result20 = tilemap.get(OTHERMAP, 0, 0)  -- Expected: 77
    __rawasm__("__debug20:")

    -- === Test 21: The critical cross-talk check -- promoting OTHERMAP ===
    -- === must not disturb TESTMAP's already-promoted RAM copy ===
    number_result21 = tilemap.get(TESTMAP, 1, 1)  -- Expected: 99 (still)
    __rawasm__("__debug21:")

    -- === Test 22: OTHERMAP's OWN untouched cell survived ITS promotion copy ===
    number_result22 = tilemap.get(OTHERMAP, 1, 0)  -- Expected: 20
    __rawasm__("__debug22:")
end

function main()
    ioports.gpu.clear("black")
    test_tilemap()

    -- Column A: x=0 -- title + tests 00-10
    print(  0,   0, "--- tilemap Test (1/2) ---")
    print(  0,  20, "T00 (0,0)= "        .. number_result00)
    print(  0,  40, "T01 (2,0)= "        .. number_result01)
    print(  0,  60, "T02 (1,1)= "        .. number_result02)
    print(  0,  80, "T03 (0,2)= "        .. number_result03)
    print(  0, 100, "T04 (2,2)= "        .. number_result04)
    print(  0, 120, "T05 x-lo nil= "     .. number_result05)
    print(  0, 140, "T06 x-hi nil= "     .. number_result06)
    print(  0, 160, "T07 y-lo nil= "     .. number_result07)
    print(  0, 180, "T08 y-hi nil= "     .. number_result08)
    print(  0, 200, "T09 set lands= "    .. number_result09)
    print(  0, 220, "T10 keep(0,0)= "    .. number_result10)

    -- Column B: x=320 -- title + tests 11-22
    print(320,   0, "--- tilemap Test (2/2) ---")
    print(320,  20, "T11 keep(2,2)= "    .. number_result11)
    print(320,  40, "T12 oob set= "      .. number_result12)
    print(320,  60, "T13 set max= "      .. number_result13)
    print(320,  80, "T14 prior ok= "     .. number_result14)
    print(320, 100, "T15 2nd set= "      .. number_result15)
    print(320, 120, "T16 no repromo= "   .. number_result16)
    print(320, 140, "T17 no repromo2= "  .. number_result17)
    print(320, 160, "T18 OTHER(0,0)= "   .. number_result18)
    print(320, 180, "T19 OTHER(1,1)= "   .. number_result19)
    print(320, 200, "T20 OTHER set= "    .. number_result20)
    print(320, 220, "T21 no crosstalk= " .. number_result21)
    print(320, 240, "T22 OTHER keep= "   .. number_result22)
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 1.0000
number_result01: 3.0000
number_result02: 5.0000
number_result03: 7.0000
number_result04: 9.0000
number_result05: 1.0000
number_result06: 1.0000
number_result07: 1.0000
number_result08: 1.0000
number_result09: 99.0000
number_result10: 1.0000
number_result11: 9.0000
number_result12: 9.0000
number_result13: 55.0000
number_result14: 99.0000
number_result15: 42.0000
number_result16: 99.0000
number_result17: 55.0000
number_result18: 10.0000
number_result19: 40.0000
number_result20: 77.0000
number_result21: 99.0000
number_result22: 20.0000
]]
