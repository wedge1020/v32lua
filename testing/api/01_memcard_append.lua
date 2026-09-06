--#title "[v32lua] memcard auto-append unit test"

--@ Vircon32 Lua memcard.* Unit Test -- auto-append/table half
--@ Self-checking coverage of the auto-append side of the native
--@ memcard.* API: memcard.save(value) with NO position (scalar, string,
--@ AND table values, through the persistent on-card cursor) and
--@ memcard.load_table(). See API.md's "Memory card: memcard.*" section
--@ for the full specification this test checks against.
--@
--@ Split from the addressing/layout half (memcard_api00.lua) purely
--@ because the two together are too many checks for one screen.
--@
--@ SECTION 1 must run FIRST in a fresh run -- it checks the cursor starts
--@ at 0, which is only true before anything else has used the
--@ no-position save() form on this card. SECTION 2 reads its own start
--@ position back via memcard[-1] rather than a fixed number, so it's
--@ unaffected by exactly how many words SECTION 1 used.
--@
--@ Boolean/identity/nil checks are converted to 1/0, same convention the
--@ tilemap unit test's out-of-bounds checks use.

function test_memcard_autoappend()
    -- ------------------------------------------------------------------
    -- SECTION 1: memcard.save(value) -- no position -- auto-append
    -- through the persistent on-card cursor.
    -- ------------------------------------------------------------------

    -- === Test 00: cursor starts at 0 on a blank card ===
    number_result00 = memcard[-1]  -- Expected: 0
    __rawasm__("__debug00:")

    memcard.save(42)              -- scalar: 2 words -> cursor 0 -> 2
    __rawasm__("__debug_save1:")
    memcard.save("HI")            -- string: 2 + 2 chars = 4 words -> cursor 2 -> 6
    __rawasm__("__debug_save2:")
    memcard.save(true)            -- scalar: 2 words -> cursor 6 -> 8
    __rawasm__("__debug_save3:")

    -- === Test 01: cursor after 3 auto-appends ===
    number_result01 = memcard[-1]  -- Expected: 8
    __rawasm__("__debug01:")

    -- === Test 02/03: entry 1 at data position 0: [TAG_SCALAR][42] ===
    number_result02 = memcard[0]  -- Expected: 0 (TAG_SCALAR)
    __rawasm__("__debug02:")
    number_result03 = memcard[1]  -- Expected: 42
    __rawasm__("__debug03:")

    -- === Test 04-07: entry 2 at data position 2: [TAG_STRING][length][H][I] ===
    number_result04 = memcard[2]  -- Expected: 1 (TAG_STRING)
    __rawasm__("__debug04:")
    number_result05 = memcard[3]  -- Expected: 2 (length)
    __rawasm__("__debug05:")
    number_result06 = memcard[4]  -- Expected: 72 (ASCII 'H')
    __rawasm__("__debug06:")
    number_result07 = memcard[5]  -- Expected: 73 (ASCII 'I')
    __rawasm__("__debug07:")

    -- === Test 08/09: entry 3 at data position 6: [TAG_SCALAR][true] ===
    number_result08 = memcard[6]  -- Expected: 0 (TAG_SCALAR)
    __rawasm__("__debug08:")
    number_result09 = (memcard[7] == true) and 1 or 0  -- Expected: 1
    __rawasm__("__debug09:")

    -- === Test 10: auto-append save()'s return value matches what was ===
    -- === saved, same convention as the explicit-position form ===
    number_result10 = memcard.save(555)   -- lands at position 8, cursor -> 10
    -- Expected: 555
    __rawasm__("__debug10:")

    -- ------------------------------------------------------------------
    -- SECTION 2: memcard.save(a_table) / memcard.load_table(position) --
    -- table dump/restore, still through the auto-append form.
    -- ------------------------------------------------------------------
    local scores = {}
    scores.alice = 500
    scores.bob = 350
    scores.carol = 900

    local table_pos = memcard[-1]   -- wherever the cursor is right now

    -- === Test 11: table save() returns the same table it was given ===
    local returned_table = memcard.save(scores)
    number_result11 = (returned_table == scores) and 1 or 0  -- Expected: 1
    __rawasm__("__debug11:")

    local restored = memcard.load_table(table_pos)

    -- === Test 12: table restore is not nil ===
    number_result12 = (restored ~= nil) and 1 or 0  -- Expected: 1
    __rawasm__("__debug12:")

    -- === Test 13-15: restored key/value pairs round-trip correctly ===
    number_result13 = restored.alice  -- Expected: 500
    __rawasm__("__debug13:")
    number_result14 = restored.bob    -- Expected: 350
    __rawasm__("__debug14:")
    number_result15 = restored.carol  -- Expected: 900
    __rawasm__("__debug15:")

    -- === Test 16: a key that was never saved reads nil, not garbage ===
    number_result16 = (restored.dave == nil) and 1 or 0  -- Expected: 1
    __rawasm__("__debug16:")

    -- === Test 17: restored is a genuinely NEW table, not the same ===
    -- === object as scores ===
    number_result17 = (restored ~= scores) and 1 or 0  -- Expected: 1
    __rawasm__("__debug17:")

    -- === Test 18: reading a non-table entry as a table fails gracefully -- ===
    -- === position 0 is SECTION 1's raw scalar entry (tag word 0, the ===
    -- === TAG_SCALAR for the value 42), correctly read as "not a table" ===
    local bad = memcard.load_table(0)
    number_result18 = (bad == nil) and 1 or 0  -- Expected: 1
    __rawasm__("__debug18:")
end

function main()
    ioports.gpu.clear("black")
    test_memcard_autoappend()

    -- Column A: x=0 -- title + tests 00-09
    print(  0,   0, "--- memcard autoappend (1/2) ---")
    print(  0,  20, "T00 cursor start= "    .. number_result00)
    print(  0,  40, "T01 cursor after 3= "  .. number_result01)
    print(  0,  60, "T02 e1 tag= "          .. number_result02)
    print(  0,  80, "T03 e1 value= "        .. number_result03)
    print(  0, 100, "T04 e2 tag= "          .. number_result04)
    print(  0, 120, "T05 e2 length= "       .. number_result05)
    print(  0, 140, "T06 e2 char1= "        .. number_result06)
    print(  0, 160, "T07 e2 char2= "        .. number_result07)
    print(  0, 180, "T08 e3 tag= "          .. number_result08)
    print(  0, 200, "T09 e3 value= "        .. number_result09)

    -- Column B: x=320 -- title + tests 10-18
    print(320,   0, "--- memcard autoappend (2/2) ---")
    print(320,  20, "T10 save() retval= "   .. number_result10)
    print(320,  40, "T11 table save ret= "  .. number_result11)
    print(320,  60, "T12 restore !nil= "    .. number_result12)
    print(320,  80, "T13 alice= "           .. number_result13)
    print(320, 100, "T14 bob= "             .. number_result14)
    print(320, 120, "T15 carol= "           .. number_result15)
    print(320, 140, "T16 unknown nil= "     .. number_result16)
    print(320, 160, "T17 distinct table= "  .. number_result17)
    print(320, 180, "T18 bad load nil= "    .. number_result18)

    ioports.gpu.sync()
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 0.0000
number_result01: 8.0000
number_result02: 0.0000
number_result03: 42.0000
number_result04: 1.0000
number_result05: 2.0000
number_result06: 72.0000
number_result07: 73.0000
number_result08: 0.0000
number_result09: 1.0000
number_result10: 555.0000
number_result11: 1.0000
number_result12: 1.0000
number_result13: 500.0000
number_result14: 350.0000
number_result15: 900.0000
number_result16: 1.0000
number_result17: 1.0000
number_result18: 1.0000
]]
