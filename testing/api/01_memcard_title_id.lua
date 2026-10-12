--#title "[v32lua] memcard title/ID unit test"

--@ Vircon32 Lua memcard.* Unit Test -- title read form / ID half
--@ Self-checking coverage of the no-argument memcard.title() read form:
--@ the FULL 20-word title block returned as a string, fixed-width and
--@ bit-exact, zero words included as embedded NUL characters. The
--@ title block is an ID field, not display text -- the transaction
--@ never stops at a zero word. See API.md's "Memory card: memcard.*"
--@ section for the full specification this test checks against.
--@
--@ Split from the addressing/layout half (00_memcard_basic.lua) purely
--@ because of screen height (640x360): the two together are more
--@ checks than one screen can show. Owns the title positions -24..-5
--@ ONLY -- nothing here touches data positions or the metadata region,
--@ and each test rewrites the title before checking it, so no state
--@ leaks between tests.
--@
--@ Boolean/identity checks are converted to 1/0, same convention the
--@ layout half uses, so every scraped result is a plain number or
--@ string -- nothing here depends on printed text.
--@
--@ NUL-SCAN CAVEAT the last three checks lock in: this VM's string
--@ operations scan to the first zero word -- string.len, ==, .., print,
--@ string.sub all see only the prefix before one. The read form's
--@ buffer physically holds all 20 words either way; two IDs differing
--@ only after a zero word are indistinguishable through the string API.

function test_memcard_title_id()
    -- ------------------------------------------------------------------
    -- SECTION 1: write a title first -- the read form's counterpart,
    -- memcard.title(str) -- so the read form has known 20-word content
    -- to return. 18 characters, deliberately 2 short of the full 20, so
    -- the zero-pad handling is exercised too.
    -- ------------------------------------------------------------------
    local title = "MEMCARD TITLE DEMO"   -- 18 characters
    memcard.title(title)
    __rawasm__("__debug_title_write:")

    -- === Test 00: read form returns the written title ===
    string_result00 = memcard.title()  -- Expected: "MEMCARD TITLE DEMO"
    __rawasm__("__debug00:")

    -- === Test 01: read form result equals the original ===
    -- (== scans to the first zero word on both sides: 18 characters +
    -- 2 pad words here, so the comparison sees the whole visible title)
    number_result01 = (memcard.title() == title) and 1 or 0  -- Expected: 1
    __rawasm__("__debug01:")

    -- === Test 02: ID round trip -- writing the read form's result back ===
    -- === reproduces the same 20 words (the write/read pair is bit-exact ===
    -- === now that the writer's CIF is gone and the reader copies verbatim) ===
    local reread02 = memcard.title()
    memcard.title(reread02)
    local roundtrip = memcard.title()
    local roundtrip_ok = true
    for i = 1, string.len(title) do
        if string.byte(roundtrip, i) ~= string.byte(title, i) then
            roundtrip_ok = false
        end
    end
    number_result02 = roundtrip_ok and 1 or 0  -- Expected: 1
    __rawasm__("__debug02:")

    -- === Test 03: NUL-scan prefix length -- string.len stops at the ===
    -- === first zero word, so the 18-char title + 2 pad words reads as 18 ===
    -- === (the buffer physically holds all 20; the pad is invisible to ===
    -- === every NUL-scanning string operation) ===
    number_result03 = string.len(memcard.title())  -- Expected: 18
    __rawasm__("__debug03:")

    -- === Test 04: zero word mid-block -- the read form never stops at ===
    -- === one, but it ends the VISIBLE string: punch a zero word in with ===
    -- === a raw save (0.0's bit pattern is all-zero, so memcard.save(0, ===
    -- === pos) writes a true zero word) and only 'A' stays legible ===
    memcard.title("ABCDE")
    memcard.save(0, -23)              -- zero word between 'A' and 'C'
    number_result04 = string.len(memcard.title())  -- Expected: 1
    __rawasm__("__debug04:")

    -- === Test 05: the read form compares equal to its visible prefix ===
    -- ('A' + zero + 'CDE...' is indistinguishable from "A" through the
    -- string API -- the words past the zero are still in the buffer and
    -- on the card)
    number_result05 = (memcard.title() == "A") and 1 or 0  -- Expected: 1
    __rawasm__("__debug05:")

    -- === Test 06: empty title -- all 20 words zero-padded; the read ===
    -- === form returns a 20-zero-word buffer, which every NUL-scanning ===
    -- === operation sees as the empty string ===
    memcard.title("")
    number_result06 = (memcard.title() == "" and string.len(memcard.title()) == 0) and 1 or 0  -- Expected: 1
    __rawasm__("__debug06:")
end

function main()
    ioports.gpu.clear("black")
    test_memcard_title_id()

    print(  0,   0, "--- memcard title/ID Test ---")
    print(  0,  20, "T00 title() read= "     .. string_result00)
    print(  0,  40, "T01 title() == orig= "  .. number_result01)
    print(  0,  60, "T02 ID roundtrip= "     .. number_result02)
    print(  0,  80, "T03 title() len= "      .. number_result03)
    print(  0, 100, "T04 midzero len= "       .. number_result04)
    print(  0, 120, "T05 midzero prefix= "    .. number_result05)
    print(  0, 140, "T06 empty title= "       .. number_result06)

    ioports.gpu.sync()
end

--[[
=== EXPECTED OUTPUT ===
string_result00: "MEMCARD TITLE DEMO"
number_result01: 1.0000
number_result02: 1.0000
number_result03: 18.0000
number_result04: 1.0000
number_result05: 1.0000
number_result06: 1.0000
]]
