--#title "MEMCARD TEST"

-- ============================================================================
-- memcard_test.lua
--
-- Self-checking unit test for the native Vircon32 memcard.* API: exercises
-- explicit-position save()/load(), the memcard[position] bracket sugar,
-- memcard.title(), the no-position auto-append form (scalar, string, AND
-- table values), and memcard.load_table(), then verifies every value
-- against what should have been written. See API.md's "Memory card:
-- memcard.*" section for the full specification this test checks against.
--
-- Each section owns a disjoint range of memcard positions so sections can't
-- accidentally corrupt each other's data:
--   SECTION 1 (explicit-position primitives): data positions 20..24
--   SECTION 2 (bracket sugar):                data positions 30..31
--   SECTION 3 (title):                        title positions -20..-5
--   SECTION 4 (auto-append: scalar/string):    data positions 0..9 (fresh
--                                              cursor start -- must run
--                                              before anything else uses
--                                              the no-position save() form)
--   SECTION 5 (auto-append: table):           wherever the cursor is right
--                                              after SECTION 4 -- reads its
--                                              own position back via
--                                              memcard[-1] rather than a
--                                              fixed number
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
-- PASS  explicit save/load: number
-- PASS  explicit save/load: true
-- PASS  explicit save/load: false
-- PASS  explicit save/load: float
-- PASS  save() return value
-- PASS  bracket write/read
-- PASS  bracket read-modify-write
-- PASS  bracket: raw string pointer (same run only)
-- PASS  title: characters match
-- PASS  title: remainder zero-padded
--
-- PASS: 29  FAIL: 0
-- ALL TESTS PASSED
-- === END EXPECTED OUTPUT ===
-- ============================================================================

PASS_COUNT = 0
FAIL_COUNT = 0

function check(name, actual, expected)
    if actual == expected then
        PASS_COUNT = PASS_COUNT + 1
        print("PASS  " .. name)
    else
        FAIL_COUNT = FAIL_COUNT + 1
        print("FAIL  " .. name .. "  expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

function main()
    -- ------------------------------------------------------------------
    -- SECTION 4 FIRST: memcard.save(value) -- no position -- auto-append
    -- through the persistent on-card cursor. Runs before every other
    -- section so the cursor is genuinely at its starting value here, not
    -- however some later no-position save left it.
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
    -- SECTION 5: memcard.save(a_table) / memcard.load_table(position) --
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
    -- crash or return garbage -- position 20 is SECTION 1's raw number
    -- (1234), written with no tag at all (explicit-position saves never
    -- write one), so the tag check here reads that 1234 and correctly
    -- rejects it.
    local bad = memcard.load_table(20)
    check("load_table() on a non-table entry returns nil", bad, nil)

    -- ------------------------------------------------------------------
    -- SECTION 1: memcard.save(value, position) / memcard.load(position)
    -- -- the low-level, exactly-one-word primitive. Own range: 20..24.
    -- ------------------------------------------------------------------
    memcard.save(1234, 20)
    __rawasm__("__debug4:")
    memcard.save(true, 21)
    __rawasm__("__debug5:")
    memcard.save(false, 22)
    __rawasm__("__debug6:")
    memcard.save(3.5, 23)
    __rawasm__("__debug7:")

    check("explicit save/load: number", memcard.load(20), 1234)
    check("explicit save/load: true",   memcard.load(21), true)
    check("explicit save/load: false",  memcard.load(22), false)
    check("explicit save/load: float",  memcard.load(23), 3.5)

    local returned = memcard.save(99, 24)
    check("save() return value", returned, 99)

    -- ------------------------------------------------------------------
    -- SECTION 2: memcard[position] bracket sugar -- same primitive,
    -- different spelling. Own range: 30..31.
    -- ------------------------------------------------------------------
    memcard[30] = 777
    __rawasm__("__debug8:")
    check("bracket write/read", memcard[30], 777)

    memcard[30] = memcard[30] + 1
    check("bracket read-modify-write", memcard[30], 778)

    -- A string CAN be written through the explicit-position form -- it's
    -- stored as a raw pointer, valid only within THIS run (see API.md's
    -- safety note under "Type tags"). This confirms the documented
    -- within-a-run behavior actually holds.
    memcard[31] = "same-run string"
    check("bracket: raw string pointer (same run only)", memcard[31], "same-run string")

    -- ------------------------------------------------------------------
    -- SECTION 3: memcard.title() -- 16-word display region, one word per
    -- character, zero-padded. Title positions -20..-5.
    -- ------------------------------------------------------------------
    local title = "TEST CARD"   -- 9 characters
    memcard.title(title)
    __rawasm__("__debug9:")

    local title_ok = true
    for i = 1, string.len(title) do
        if memcard[-20 + (i - 1)] ~= string.byte(title, i) then
            title_ok = false
        end
    end
    check("title: characters match", title_ok, true)

    local pad_ok = true
    for i = string.len(title) + 1, 16 do
        if memcard[-20 + (i - 1)] ~= 0 then
            pad_ok = false
        end
    end
    check("title: remainder zero-padded", pad_ok, true)

    -- ------------------------------------------------------------------
    -- Summary
    -- ------------------------------------------------------------------
    print("")
    print("PASS: " .. PASS_COUNT .. "  FAIL: " .. FAIL_COUNT)
    if FAIL_COUNT == 0 then
        print("ALL TESTS PASSED")
    else
        print("SOME TESTS FAILED")
    end

    __rawasm__("__debug_final:")
end
