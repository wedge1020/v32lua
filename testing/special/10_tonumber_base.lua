--@ Vircon32 Lua tonumber(s, base) Unit Test
--@ Lua 5.4's rules: s a string, base 2..36, surrounding whitespace, one
--@ optional '-', at least one digit below base (0-9, a-z, A-Z) and nothing
--@ else -- otherwise nil.
--@ Results are stored in global variables for automated memory scraping.

function main()
    -- === Test 00: common bases ===
    number_result00a = tonumber("ff", 16)
    number_result00b = tonumber("FF", 16)
    number_result00c = tonumber("1010", 2)
    number_result00d = tonumber("777", 8)
    number_result00e = tonumber("zz", 36)
    number_result00f = tonumber("123", 10)
    __rawasm__("__debug0:")

    -- === Test 01: whitespace and sign ===
    number_result01a = tonumber("  7f  ", 16)
    number_result01b = tonumber("-101", 2)
    number_result01c = tonumber("\t10\n", 3)
    __rawasm__("__debug1:")

    -- === Test 02: nil cases ===
    boolean_result02a = tonumber("12", 2) == nil
    boolean_result02b = tonumber("0x10", 16) == nil
    boolean_result02c = tonumber("", 10) == nil
    boolean_result02d = tonumber("-", 10) == nil
    boolean_result02e = tonumber("1 2", 10) == nil
    boolean_result02f = tonumber("10", 1) == nil
    boolean_result02g = tonumber("10", 37) == nil
    boolean_result02h = tonumber(10, 16) == nil
    __rawasm__("__debug2:")

    -- === Test 03: the base from a variable, one-argument form unchanged ===
    local b = 16
    number_result03a = tonumber("10", b)
    number_result03b = tonumber("0x10")
    number_result03c = tonumber("  2.5 ")
    __rawasm__("__debug3:")
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 255.0000
number_result00b: 255.0000
number_result00c: 10.0000
number_result00d: 511.0000
number_result00e: 1295.0000
number_result00f: 123.0000
number_result01a: 127.0000
number_result01b: -5.0000
number_result01c: 3.0000
boolean_result02a: true
boolean_result02b: true
boolean_result02c: true
boolean_result02d: true
boolean_result02e: true
boolean_result02f: true
boolean_result02g: true
boolean_result02h: true
number_result03a: 16.0000
number_result03b: 16.0000
number_result03c: 2.5000

--]]
