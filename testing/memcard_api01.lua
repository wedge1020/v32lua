--#title "MEMCARD API TEST 01: AUTO-APPEND"

-- ============================================================================
-- memcard_autoappend_test.lua
--
-- Self-checking unit test for the auto-append half of the native
-- Vircon32 memcard.* API: memcard.save(value) with NO position (scalar,
-- string, AND table values, through the persistent on-card cursor) and
-- memcard.load_table(). See API.md's "Memory card: memcard.*" section for
-- the full specification this test checks against.
--
-- Split out from the addressing/layout half (memcard_layout_test.lua)
-- purely because 34 checks' worth of output didn't fit one screen
-- legibly. This half's 19 checks still need the two-column wrap below --
-- there was no way to trim this side further without losing coverage of
-- the auto-append tag format itself.
--
-- Each section owns a disjoint range of memcard positions so sections
-- can't accidentally corrupt each other's data:
--   SECTION 1 (auto-append: scalar/string): data positions 0..9 (fresh
--                                            cursor start -- must run
--                                            before anything else uses
--                                            the no-position save() form,
--                                            which this file's main()
--                                            does first)
--   SECTION 2 (auto-append: table):         wherever the cursor is right
--                                            after SECTION 1 -- reads its
--                                            own position back via
--                                            memcard[-1] rather than a
--                                            fixed number
--
-- === EXPECTED OUTPUT ===
-- PASS  cursor starts at 0 on a blank card
-- PASS  cursor after 3 auto-appends
-- PASS  entry1 tag
-- PASS  entry1 value
-- PASS  entry2 tag
-- PASS  entry2 length
-- PASS  entry2 char 1
-- PASS  entry2 char 2
-- PASS  entry3 tag
-- PASS  entry3 value
-- PASS  auto-append save() return value
-- PASS  table save() returns the same table
-- PASS  table restore: not nil
-- PASS  table restore: alice
-- PASS  table restore: bob
-- PASS  table restore: carol
-- PASS  table restore: unknown key is nil
-- PASS  table restore: is a distinct table
-- PASS  load_table() on a non-table entry returns nil
--
-- PASS: 19  FAIL: 0
-- ALL TESTS PASSED
-- === END EXPECTED OUTPUT ===
-- ============================================================================

PASS_COUNT = 0
FAIL_COUNT = 0

-- 19 checks + 3 summary lines = 22 lines -- one column (640x360, 20px
-- BIOS font) only holds 18, so this half still wraps into a second
-- column at x=324.
PRINT_X = 4
PRINT_Y = 0

function report(text)
    print(PRINT_X, PRINT_Y, text)
    PRINT_Y = PRINT_Y + 20
    if PRINT_Y > 340 then
        PRINT_Y = 100
        PRINT_X = PRINT_X + 240
    end
end

function check(name, actual, expected)
    if actual == expected then
        PASS_COUNT = PASS_COUNT + 1
        report("PASS  " .. name)
    else
        FAIL_COUNT = FAIL_COUNT + 1
        report("FAIL  " .. name .. "  expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

function main()
    ioports.gpu.clear("black")

    -- ------------------------------------------------------------------
    -- SECTION 1: memcard.save(value) -- no position -- auto-append
    -- through the persistent on-card cursor. Runs first so the cursor is
    -- genuinely at its starting value here, not however some earlier
    -- no-position save left it.
    -- ------------------------------------------------------------------
    local cursor_before = memcard[-1]
    check("cursor starts at 0 on a blank card", cursor_before, 0)

    memcard.save(42)              -- scalar: 2 words -> cursor 0 -> 2
    __rawasm__("__debug1:")
    memcard.save("HI")            -- string: 2 + 2 chars = 4 words -> cursor 2 -> 6
    __rawasm__("__debug2:")
    memcard.save(true)            -- scalar: 2 words -> cursor 6 -> 8
    __rawasm__("__debug3:")

    check("cursor after 3 auto-appends", memcard[-1], 8)

    -- Entry 1 at data position 0: [TAG_SCALAR][42]
    check("entry1 tag",   memcard[0], 0)
    check("entry1 value", memcard[1], 42)

    -- Entry 2 at data position 2: [TAG_STRING][length][H][I]
    check("entry2 tag",    memcard[2], 1)
    check("entry2 length", memcard[3], 2)
    check("entry2 char 1", memcard[4], string.byte("HI", 1))
    check("entry2 char 2", memcard[5], string.byte("HI", 2))

    -- Entry 3 at data position 6: [TAG_SCALAR][true]
    check("entry3 tag",   memcard[6], 0)
    check("entry3 value", memcard[7], true)

    -- auto-append's return value matches what was saved, same convention
    -- as the explicit-position form
    local ret2 = memcard.save(555)   -- lands at position 8, cursor -> 10
    check("auto-append save() return value", ret2, 555)

    -- ------------------------------------------------------------------
    -- SECTION 2: memcard.save(a_table) / memcard.load_table(position) --
    -- table dump/restore, still through the auto-append form. Continues
    -- directly from this section's own cursor (no explicit position
    -- bookkeeping needed for the save itself) rather than a fixed
    -- position, since the whole point is exercising the auto-append path.
    -- ------------------------------------------------------------------
    local scores = {}
    scores.alice = 500
    scores.bob = 350
    scores.carol = 900

    local table_pos = memcard[-1]   -- wherever the cursor is right now
    local returned_table = memcard.save(scores)
    check("table save() returns the same table", returned_table, scores)

    local restored = memcard.load_table(table_pos)

    check("table restore: not nil",            restored ~= nil, true)
    check("table restore: alice",              restored.alice, 500)
    check("table restore: bob",                restored.bob, 350)
    check("table restore: carol",              restored.carol, 900)
    check("table restore: unknown key is nil", restored.dave, nil)

    -- restored is a genuinely NEW table, not the same object as scores
    check("table restore: is a distinct table", restored ~= scores, true)

    -- Reading a non-table entry as a table should fail gracefully, not
    -- crash or return garbage -- position 0 is SECTION 1's raw scalar
    -- entry (tag word 0, the TAG_SCALAR for the value 42), so the tag
    -- check here reads that 0 and correctly treats it as "not a table".
    local bad = memcard.load_table(0)
    check("load_table() on a non-table entry returns nil", bad, nil)

    -- ------------------------------------------------------------------
    -- Summary
    -- ------------------------------------------------------------------
    report("")
    report("PASS: " .. PASS_COUNT .. "  FAIL: " .. FAIL_COUNT)
    if FAIL_COUNT == 0 then
        report("ALL TESTS PASSED")
    else
        report("SOME TESTS FAILED")
    end

    __rawasm__("__debug_final:")

    ioports.gpu.sync()
end
