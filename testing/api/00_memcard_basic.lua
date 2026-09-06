--#title "[v32lua] memcard layout unit test"

--@ Vircon32 Lua memcard.* Unit Test -- addressing/layout half
--@ Self-checking coverage of the addressing/layout side of the native
--@ memcard.* API: explicit-position save()/load(), the memcard[position]
--@ bracket sugar, memcard.title(), and the title/metadata layout (title:
--@ positions -24..-5, reserved metadata: -4..-1). See API.md's "Memory
--@ card: memcard.*" section for the full specification this test checks
--@ against.
--@
--@ Split from the auto-append/table half (memcard_api01.lua) purely
--@ because the two together are too many checks for one screen. Each
--@ section below owns a disjoint memcard position range so sections
--@ can't corrupt each other's data:
--@   SECTION 1 (explicit-position primitives): data positions 20..24
--@   SECTION 2 (bracket sugar):                data positions 30..31
--@   SECTION 3 (title):                        title positions -24..-5
--@   SECTION 4 (metadata region):              positions -4..-1
--@
--@ Boolean/identity checks are converted to 1/0, same convention the
--@ tilemap unit test's out-of-bounds checks use, so every scraped result
--@ is a plain number or string -- nothing here depends on printed text.

function test_memcard_layout()
    -- ------------------------------------------------------------------
    -- SECTION 1: memcard.save(value, position) / memcard.load(position)
    -- -- the low-level, exactly-one-word primitive. Own range: 20..24.
    -- ------------------------------------------------------------------

    -- === Test 00: explicit save/load, number ===
    memcard.save(1234, 20)
    number_result00 = memcard.load(20)  -- Expected: 1234
    __rawasm__("__debug00:")

    -- === Test 01: explicit save/load, true ===
    memcard.save(true, 21)
    number_result01 = (memcard.load(21) == true) and 1 or 0  -- Expected: 1
    __rawasm__("__debug01:")

    -- === Test 02: explicit save/load, false ===
    memcard.save(false, 22)
    number_result02 = (memcard.load(22) == false) and 1 or 0  -- Expected: 1
    __rawasm__("__debug02:")

    -- === Test 03: explicit save/load, float ===
    memcard.save(3.5, 23)
    number_result03 = memcard.load(23)  -- Expected: 3.5
    __rawasm__("__debug03:")

    -- === Test 04: save() returns the value it was given ===
    number_result04 = memcard.save(99, 24)  -- Expected: 99
    __rawasm__("__debug04:")

    -- ------------------------------------------------------------------
    -- SECTION 2: memcard[position] bracket sugar -- same primitive,
    -- different spelling. Own range: 30..31.
    -- ------------------------------------------------------------------

    -- === Test 05: bracket write/read ===
    memcard[30] = 777
    number_result05 = memcard[30]  -- Expected: 777
    __rawasm__("__debug05:")

    -- === Test 06: bracket read-modify-write ===
    memcard[30] = memcard[30] + 1
    number_result06 = memcard[30]  -- Expected: 778
    __rawasm__("__debug06:")

    -- === Test 07: bracket form CAN carry a string -- stored as a raw ===
    -- === pointer, valid only within this run (API.md's safety note ===
    -- === under "Type tags") -- confirms the documented within-a-run ===
    -- === behavior actually holds ===
    memcard[31] = "same-run string"
    string_result07 = memcard[31]  -- Expected: "same-run string"
    __rawasm__("__debug07:")

    -- ------------------------------------------------------------------
    -- SECTION 3: memcard.title() -- 20-word display region, one word per
    -- character, zero-padded. Title positions -24..-5. 18 characters here
    -- (was capped at 16 before the title/metadata split -- this string
    -- would have been silently truncated under the old layout).
    -- ------------------------------------------------------------------
    local title = "MEMCARD TITLE DEMO"   -- 18 characters
    memcard.title(title)
    __rawasm__("__debug_title_write:")

    -- === Test 08: every character landed correctly ===
    local title_ok = true
    for i = 1, string.len(title) do
        if memcard[-24 + (i - 1)] ~= string.byte(title, i) then
            title_ok = false
        end
    end
    number_result08 = title_ok and 1 or 0  -- Expected: 1
    __rawasm__("__debug08:")

    -- === Test 09: remainder of the 20-word title is zero-padded ===
    local pad_ok = true
    for i = string.len(title) + 1, 20 do
        if memcard[-24 + (i - 1)] ~= 0 then
            pad_ok = false
        end
    end
    number_result09 = pad_ok and 1 or 0  -- Expected: 1
    __rawasm__("__debug09:")

    -- === Test 10: title's first character, read via memcard.load() ===
    -- === instead of bracket sugar -- both spellings hit the same address ===
    number_result10 = memcard.load(-24)  -- Expected: 77 (ASCII 'M')
    __rawasm__("__debug10:")

    -- ------------------------------------------------------------------
    -- SECTION 4: metadata region -- positions -4..-1, separate from the
    -- title. Nothing above ever writes -4..-2, so they should still read
    -- as a blank card's all-zero bit pattern; -1 is the auto-append
    -- cursor (exercised for real in memcard_api01.lua), checked here via
    -- both spellings.
    -- ------------------------------------------------------------------

    -- === Test 11: metadata word -4 is blank on a fresh card ===
    number_result11 = memcard.load(-4)  -- Expected: 0
    __rawasm__("__debug11:")

    -- === Test 12: metadata word -3 is blank on a fresh card ===
    number_result12 = memcard[-3]  -- Expected: 0
    __rawasm__("__debug12:")

    -- === Test 13: metadata word -2 is blank on a fresh card ===
    number_result13 = memcard.load(-2)  -- Expected: 0
    __rawasm__("__debug13:")

    -- === Test 14: metadata word -1 (the cursor) agrees between spellings ===
    number_result14 = (memcard.load(-1) == memcard[-1]) and 1 or 0  -- Expected: 1
    __rawasm__("__debug14:")
end

function main()
    ioports.gpu.clear("black")
    test_memcard_layout()

    print(  0,   0, "--- memcard layout Test ---")
    print(  0,  20, "T00 explicit number= "     .. number_result00)
    print(  0,  40, "T01 explicit true= "       .. number_result01)
    print(  0,  60, "T02 explicit false= "      .. number_result02)
    print(  0,  80, "T03 explicit float= "      .. number_result03)
    print(  0, 100, "T04 save() retval= "       .. number_result04)
    print(  0, 120, "T05 bracket write/read= "  .. number_result05)
    print(  0, 140, "T06 bracket RMW= "         .. number_result06)
    print(  0, 160, "T07 bracket string= "      .. string_result07)
    print(  0, 180, "T08 title chars ok= "      .. number_result08)
    print(  0, 200, "T09 title pad ok= "        .. number_result09)
    print(  0, 220, "T10 title char via load= " .. number_result10)
    print(  0, 240, "T11 meta -4 blank= "       .. number_result11)
    print(  0, 260, "T12 meta -3 blank= "       .. number_result12)
    print(  0, 280, "T13 meta -2 blank= "       .. number_result13)
    print(  0, 300, "T14 cursor agrees= "       .. number_result14)

    ioports.gpu.sync()
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 1234.0000
number_result01: 1.0000
number_result02: 1.0000
number_result03: 3.5000
number_result04: 99.0000
number_result05: 777.0000
number_result06: 778.0000
string_result07: "same-run string"
number_result08: 1.0000
number_result09: 1.0000
number_result10: 77.0000
number_result11: 0.0000
number_result12: 0.0000
number_result13: 0.0000
number_result14: 1.0000
]]
