-- title: pmem unit test
--@ Vircon32 Lua TIC-80 pmem() Unit Test
--@ 256 persistent 32-bit slots; pmem(i, v) returns the value BEFORE the
--@ write, values are truncated and read back unsigned, an index outside
--@ 0-255 gives nil. (The headless harness always connects a memory card;
--@ V32_NO_MEMCARD=1 runs the same test on the RAM fallback.)
--@ Results are stored in global variables for automated memory scraping.

function TIC()
    if number_result00 ~= nil then return end

    -- === Test 00: a fresh slot reads 0 ===
    number_result00 = pmem(0)
    __rawasm__("__debug0:")

    -- === Test 01: a write returns the previous value ===
    number_result01a = pmem(0, 123456)
    number_result01b = pmem(0)
    __rawasm__("__debug1:")

    -- === Test 02: 32-bit values, read back unsigned ===
    pmem(1, -1)
    number_result02 = pmem(1)
    __rawasm__("__debug2:")

    -- === Test 03: values are truncated to integers ===
    pmem(255, 3.9)
    number_result03 = pmem(255)
    __rawasm__("__debug3:")

    -- === Test 04: indexes outside 0-255 ===
    boolean_result04a = (pmem(256) == nil)
    boolean_result04b = (pmem(-1) == nil)
    __rawasm__("__debug4:")
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 0.0000
number_result01a: 0.0000
number_result01b: 123456.0000
number_result02: 4294967296.0000
number_result03: 3.0000
boolean_result04a: true
boolean_result04b: true

--]]
