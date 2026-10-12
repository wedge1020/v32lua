--#title "[v32lua] memcard title/ID unit test"

--@ Vircon32 Lua memcard.* Unit Test -- title read form / ID half
--@ Self-checking coverage of the no-argument memcard.title() read form:
--@ the FULL 20-word title block returned as an indexed table, elements
--@ 1..20, one raw card word per element, fixed-width and bit-exact, zero
--@ words included as plain 0. The title block is an ID field, not
--@ display text -- the transaction never stops at a zero word. See
--@ API.md's "Memory card: memcard.*" section for the full specification
--@ this test checks against.
--@
--@ WHY A TABLE (and not a string): this VM's strings are NUL-terminated
--@ and every string operation (string.len, ==, .., print, string.sub)
--@ scans only to the first zero word, so a string return had a blind
--@ spot exactly where an ID field can least afford one -- any words
--@ past a zero were invisible. Table elements have no such blind spot:
--@ each element is the raw card word's integer value (so 'M' reads as
--@ 77, a zero word reads as 0), and a word with the high bit set reads
--@ back as its signed-32-bit value (negative). Comparing two IDs is an
--@ element-wise loop, which Test 04/Test 05 lock in.
--@
--@ Split from the addressing/layout half (00_memcard_basic.lua) purely
--@ because of screen height (640x360): the two together are more
--@ checks than one screen can show. Owns the title positions -24..-5
--@ ONLY -- nothing here touches data positions or the metadata region,
--@ and each test rewrites the title before checking it, so no state
--@ leaks between tests.
--@
--@ Boolean/identity checks are converted to 1/0, same convention the
--@ layout half uses, so every scraped result is a plain number --
--@ nothing here depends on printed text.

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

    -- === Test 00: read form returns a table whose first element is ===
    -- === the title's first character code ('M' = 77) ===
    local t00 = memcard.title()
    number_result00 = (type(t00) == "table" and t00[1] == 77) and 1 or 0  -- Expected: 1
    __rawasm__("__debug00:")

    -- === Test 01: all 18 written characters are legible as elements ===
    -- === 1..18 -- a table has no NUL blind spot, every word reads back ===
    local t01 = memcard.title()
    local chars_ok = true
    for i = 1, string.len(title) do
        if t01[i] ~= string.byte(title, i) then
            chars_ok = false
        end
    end
    number_result01 = chars_ok and 1 or 0  -- Expected: 1
    __rawasm__("__debug01:")

    -- === Test 02: the 2 zero pad words past the 18 characters are ===
    -- === visible as elements 19 and 20 -- the exact thing the string ===
    -- === return could NOT show (a string stops at the first zero) ===
    local t02 = memcard.title()
    number_result02 = (t02[19] == 0 and t02[20] == 0) and 1 or 0  -- Expected: 1
    __rawasm__("__debug02:")

    -- === Test 03: zero word MID-block -- punch a zero between 'A' and ===
    -- === 'C' with a raw save (0.0's bit pattern is all-zero, so ===
    -- === memcard.save(0, pos) writes a true zero word) and the words ===
    -- === PAST the zero stay observable: elements read 65, 0, 67, 68, ===
    -- === 69 -- under the string form, everything after element 2 was ===
    -- === invisible ===
    memcard.title("ABCDE")
    memcard.save(0, -23)              -- zero word between 'A' and 'C'
    local t03 = memcard.title()
    number_result03 = (t03[1] == 65 and t03[2] == 0 and
                       t03[3] == 67 and t03[4] == 68 and t03[5] == 69) and 1 or 0  -- Expected: 1
    __rawasm__("__debug03:")

    -- === Test 04: == on tables is IDENTITY, not content -- two reads of ===
    -- === the same 20 words are two different tables, so == is always ===
    -- === false and must NOT be used for ID comparison (the read form's ===
    -- === one real trade-off vs the string form; use the element-wise ===
    -- === loop in Test 05 instead) ===
    number_result04 = (memcard.title() == memcard.title()) and 1 or 0  -- Expected: 0
    __rawasm__("__debug04:")

    -- === Test 05: ID comparison pattern -- element-wise over the full ===
    -- === fixed 20 words, zeros included: two reads of the same card ===
    -- === agree everywhere ===
    local a05 = memcard.title()
    local b05 = memcard.title()
    local id_ok = true
    for i = 1, 20 do
        if a05[i] ~= b05[i] then
            id_ok = false
        end
    end
    number_result05 = id_ok and 1 or 0  -- Expected: 1
    __rawasm__("__debug05:")

    -- === Test 06: empty title -- all 20 words zero-padded; every ===
    -- === element reads as a plain 0, full width still transacted ===
    memcard.title("")
    local t06 = memcard.title()
    local empty_ok = true
    for i = 1, 20 do
        if t06[i] ~= 0 then
            empty_ok = false
        end
    end
    number_result06 = empty_ok and 1 or 0  -- Expected: 1
    __rawasm__("__debug06:")
end

function main()
    ioports.gpu.clear("black")
    test_memcard_title_id()

    print(  0,   0, "--- memcard title/ID Test ---")
    print(  0,  20, "T00 table + elem1= "     .. number_result00)
    print(  0,  40, "T01 18 chars ok= "      .. number_result01)
    print(  0,  60, "T02 pad zeros ok= "      .. number_result02)
    print(  0,  80, "T03 midzero ok= "        .. number_result03)
    print(  0, 100, "T04 == identity= "       .. number_result04)
    print(  0, 120, "T05 elem compare= "      .. number_result05)
    print(  0, 140, "T06 empty title= "       .. number_result06)

    ioports.gpu.sync()
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 1.0000
number_result01: 1.0000
number_result02: 1.0000
number_result03: 1.0000
number_result04: 0.0000
number_result05: 1.0000
number_result06: 1.0000
]]
