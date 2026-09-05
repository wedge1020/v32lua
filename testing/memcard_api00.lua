--#title "MEMCARD API TEST 00: LAYOUT"

-- ============================================================================
-- memcard_layout_test.lua
--
-- Self-checking unit test for the addressing/layout half of the native
-- Vircon32 memcard.* API: explicit-position save()/load(), the
-- memcard[position] bracket sugar, memcard.title(), and the current
-- title/metadata layout (title: positions -24..-5, reserved metadata:
-- -4..-1). See API.md's "Memory card: memcard.*" section for the full
-- specification this test checks against.
--
-- Split out from the auto-append/table half (memcard_autoappend_test.lua)
-- purely because 34 checks' worth of output didn't fit one screen
-- legibly. This half's 15 checks fit one column with no wrapping needed.
--
-- Each section owns a disjoint range of memcard positions so sections
-- can't accidentally corrupt each other's data:
--   SECTION 1 (explicit-position primitives): data positions 20..24
--   SECTION 2 (bracket sugar):                data positions 30..31
--   SECTION 3 (title):                        title positions -24..-5
--   SECTION 4 (metadata region):              positions -4..-1
--
-- === EXPECTED OUTPUT ===
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
-- PASS  title first char via memcard.load()
-- PASS  metadata word -4 is blank on a fresh card
-- PASS  metadata word -3 is blank on a fresh card
-- PASS  metadata word -2 is blank on a fresh card
-- PASS  metadata word -1 (cursor) matches the bracket-sugar read
--
-- PASS: 15  FAIL: 0
-- ALL TESTS PASSED
-- === END EXPECTED OUTPUT ===
-- ============================================================================

PASS_COUNT = 0
FAIL_COUNT = 0

-- 15 checks + 3 summary lines = 18 lines -- exactly one screen column
-- (640x360, 20px BIOS font line height) with nothing left over. No
-- column-wrap logic needed here, unlike the auto-append half.
PRINT_Y = 0

function report(text)
    print(4, PRINT_Y, text)
    PRINT_Y = PRINT_Y + 20
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
    -- SECTION 1: memcard.save(value, position) / memcard.load(position)
    -- -- the low-level, exactly-one-word primitive. Own range: 20..24.
    -- ------------------------------------------------------------------
    memcard.save(1234, 20)
    __rawasm__("__debug1:")
    memcard.save(true, 21)
    __rawasm__("__debug2:")
    memcard.save(false, 22)
    __rawasm__("__debug3:")
    memcard.save(3.5, 23)
    __rawasm__("__debug4:")

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
    __rawasm__("__debug5:")
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
    -- SECTION 3: memcard.title() -- 20-word display region, one word per
    -- character, zero-padded. Title positions -24..-5. 18 characters here
    -- (was capped at 16 before the title/metadata split -- this string
    -- would have been silently truncated under the old layout).
    -- ------------------------------------------------------------------
    local title = "MEMCARD TITLE DEMO"   -- 18 characters
    memcard.title(title)
    __rawasm__("__debug6:")

    local title_ok = true
    for i = 1, string.len(title) do
        if memcard[-24 + (i - 1)] ~= string.byte(title, i) then
            title_ok = false
        end
    end
    check("title: characters match", title_ok, true)

    local pad_ok = true
    for i = string.len(title) + 1, 20 do
        if memcard[-24 + (i - 1)] ~= 0 then
            pad_ok = false
        end
    end
    check("title: remainder zero-padded", pad_ok, true)

    -- Same first character, read through the function-call form instead
    -- of bracket sugar -- both spellings hit the exact same address.
    check("title first char via memcard.load()", memcard.load(-24), string.byte(title, 1))

    -- ------------------------------------------------------------------
    -- SECTION 4: metadata region -- positions -4..-1, separate from the
    -- title (previously the last 4 words of the title itself). Nothing
    -- in this test ever writes -4..-2, so they should still read as a
    -- blank card's all-zero bit pattern; -1 is the auto-append cursor
    -- (exercised for real in memcard_autoappend_test.lua), checked here
    -- via BOTH spellings to confirm they agree.
    -- ------------------------------------------------------------------
    check("metadata word -4 is blank on a fresh card", memcard.load(-4), 0)
    check("metadata word -3 is blank on a fresh card", memcard[-3], 0)
    check("metadata word -2 is blank on a fresh card", memcard.load(-2), 0)
    check("metadata word -1 (cursor) matches the bracket-sugar read", memcard.load(-1), memcard[-1])

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
