--#title "[v32lua] hex() intrinsic unit test"
--@ Vircon32 Lua hex() Intrinsic Unit Test
--@ hex() is a non-Lua language extension: hex("0x...") is parsed AT
--@ COMPILE TIME (via strtoul on a string LITERAL argument -- not a
--@ runtime string-to-number conversion, and NOT the same thing as
--@ tonumber("0x...")) and emitted as a direct MOV of the exact 32-bit
--@ pattern given. There is NO interpretation, boxing, or "hex to
--@ decimal" conversion involved -- the register simply contains
--@ whatever bits you wrote, reinterpreted as an IEEE-754 float the
--@ moment anything treats it as a Lua number. This is a deliberate,
--@ documented gotcha exercised directly below (Test 05): hex("0xFF")
--@ is NOT the number 255.
--@
--@ hex() only accepts a single STRING LITERAL argument -- hex(somevar)
--@ or hex("0x" .. x) are compile errors, not runtime failures, since
--@ the parsing happens before any code generation at all.
--@
--@ Per project convention, every raw hex()-loaded value below is stored
--@ in a hex_result# variable (not number_result#), regardless of
--@ whether that specific value happens to also be a well-behaved,
--@ printable float -- so the test scraper can set up v32sim memory
--@ inspection consistently for all of them.
--@
--@ Tests 06-07 load bit patterns that are NOT meaningful IEEE floats at
--@ all (a raw debug-marker word, and a pattern that COLLIDES with this
--@ runtime's own internal NaN-boxing tag space). Those two are
--@ deliberately never passed through print()/tostring()/arithmetic --
--@ verify them via direct v32sim memory inspection only. See their
--@ comments for why running them through normal Lua number handling is
--@ specifically avoided here.

function test_hex_intrinsic()
    -- === Test 00: 1.0 as its exact IEEE-754 float32 bit pattern ===
    hex_result00 = hex("0x3F800000")
    boolean_result00 = (hex_result00 == 1.0)  -- Expected: true
    __rawasm__("__debug0:")

    -- === Test 01: 10.0 as its exact bit pattern ===
    hex_result01 = hex("0x41200000")
    boolean_result01 = (hex_result01 == 10.0)  -- Expected: true
    __rawasm__("__debug1:")

    -- === Test 02: 100.0 as its exact bit pattern ===
    hex_result02 = hex("0x42C80000")
    boolean_result02 = (hex_result02 == 100.0)  -- Expected: true
    __rawasm__("__debug2:")

    -- === Test 03: -1.0 as its exact bit pattern (sign bit set) ===
    hex_result03 = hex("0xBF800000")
    boolean_result03 = (hex_result03 == -1.0)  -- Expected: true
    __rawasm__("__debug3:")

    -- === Test 04: 0.0 as its exact bit pattern (all zero bits) ===
    hex_result04 = hex("0x00000000")
    boolean_result04 = (hex_result04 == 0.0)  -- Expected: true
    __rawasm__("__debug4:")

    -- === Test 05: THE GOTCHA -- hex("0xFF") is NOT decimal 255. It's the ===
    -- === raw bit pattern 0x000000FF reinterpreted as a float32, which is ===
    -- === a tiny DENORMALIZED number very close to zero, nowhere near 255. ===
    -- === Checked via a threshold rather than an exact printed value, ===
    -- === since denormal precision isn't worth hand-deriving exactly. ===
    hex_result05 = hex("0xFF")
    boolean_result05a = (hex_result05 ~= 255)          -- Expected: true (it is NOT 255)
    boolean_result05b = (hex_result05 > 0)              -- Expected: true (tiny positive denormal)
    boolean_result05c = (hex_result05 < 0.0001)         -- Expected: true (nowhere near 255)
    __rawasm__("__debug5:")

    -- === Test 06: A raw, non-numeric marker pattern (e.g. for tagging ===
    -- === memory during debugging) -- NOT a meaningful float at all. ===
    -- === Deliberately NOT printed or used in any arithmetic/comparison --
    -- === verify hex_result06 == 0xDEADBEEF via direct v32sim memory ===
    -- === inspection only. ===
    hex_result06 = hex("0xDEADBEEF")
    __rawasm__("__debug6:")

    -- === Test 07: A bit pattern that COLLIDES with this runtime's own ===
    -- === internal NaN-boxing tag space (NAN_VALUE == 0x7F800000 is the ===
    -- === exponent-all-ones pattern every non-number Lua value -- nil, ===
    -- === tables, strings, functions -- is built from). This is real ===
    -- === IEEE positive infinity's bit pattern, but at the Lua level this ===
    -- === value would be misidentified as SOME kind of tagged non-number ===
    -- === by anything that checks "is this a number" the way type()/
    -- === tonumber()/table.sort's default comparator all do. Deliberately
    -- === NOT run through type(), print(), tostring(), or any comparison
    -- === below -- behavior through those paths is undefined and untested.
    -- === Verify hex_result07 == 0x7F800000 via direct v32sim memory
    -- === inspection only.
    hex_result07 = hex("0x7F800000")
    __rawasm__("__debug7:")

    -- === Test 08: A hex()-loaded value used in ordinary arithmetic, to ===
    -- === confirm a well-behaved bit pattern round-trips through normal ===
    -- === Lua number operations exactly like an equivalent literal would ===
    number_result08 = hex("0x41200000") + hex("0x3F800000")  -- 10.0 + 1.0
    boolean_result08 = (number_result08 == 11.0)  -- Expected: true
    __rawasm__("__debug8:")
end

function main()
    ioports.gpu.clear("black")
    test_hex_intrinsic()

    print(  0,   0, "--- hex() Intrinsic Test ---")
    print(  0,  20, "Test 00 - 1.0 pattern: "     .. hex_result00 .. " (" .. tostring(boolean_result00) .. ")")
    print(  0,  40, "Test 01 - 10.0 pattern: "    .. hex_result01 .. " (" .. tostring(boolean_result01) .. ")")
    print(  0,  60, "Test 02 - 100.0 pattern: "   .. hex_result02 .. " (" .. tostring(boolean_result02) .. ")")
    print(  0,  80, "Test 03 - -1.0 pattern: "    .. hex_result03 .. " (" .. tostring(boolean_result03) .. ")")
    print(  0, 100, "Test 04 - 0.0 pattern: "     .. hex_result04 .. " (" .. tostring(boolean_result04) .. ")")
    print(  0, 120, "Test 05 - Not 255: "         .. tostring(boolean_result05a) .. " "
                                                   .. tostring(boolean_result05b) .. " "
                                                   .. tostring(boolean_result05c))
    print(  0, 140, "Test 06 - Raw marker: (see v32sim memory, not printed)")
    print(  0, 160, "Test 07 - Tag collision: (see v32sim memory, not printed)")
    print(  0, 180, "Test 08 - Arithmetic: "      .. number_result08 .. " (" .. tostring(boolean_result08) .. ")")
end

--[[
=== EXPECTED OUTPUT ===
hex_result00: 0x3F800000
boolean_result00: true
hex_result01: 0x41200000
boolean_result01: true
hex_result02: 0x42C80000
boolean_result02: true
hex_result03: 0xBF800000
boolean_result03: true
hex_result04: 0x00000000
boolean_result04: true
hex_result05: 0x000000FF
boolean_result05a: true
boolean_result05b: true
boolean_result05c: true
hex_result06: 0xDEADBEEF
hex_result07: 0x7F800000
number_result08: 11.0000
boolean_result08: true
]]
