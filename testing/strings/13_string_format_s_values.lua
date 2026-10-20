--@ Vircon32 Lua string.format %s Coercion Unit Test
--@ %s applies tostring() to its argument. Numbers were unboxed as if they
--@ were string pointers, reading from a wild address -- the "invalid memory
--@ read" on tomb_of_the_tic's level-clear screen
--@ (string.format("%s / %s .. DOTS COLLECTED", score, score + dots)).
--@ Results are stored in global variables for automated memory scraping.

function test_format_s_values()
    local score, dots = 12, 3

    -- === Test 00: numbers ===
    string_result00 = string.format("%s / %s", score, score + dots)
    __rawasm__("__debug0:")

    -- === Test 01: width, left-justify, boolean, nil, string ===
    string_result01 = string.format("[%5s|%-6s|%s|%s]", 2.5, true, nil, "x")
    __rawasm__("__debug1:")

    -- === Test 02: a table is formatted as tostring() does ===
    local t = {}
    boolean_result02 = (string.format("%s", t) == tostring(t))
    __rawasm__("__debug2:")

    -- === Test 03: mixed with other specifiers ===
    string_result03 = string.format("%s-%d-%s", 1, 7, false)
    __rawasm__("__debug3:")

    -- === Test 04: %q quotes strings, writes other values as literals ===
    string_result04 = string.format("%q|%q|%q", "hi", 5, true)
    __rawasm__("__debug4:")
end

function main()
    ioports.gpu.clear("black")
    test_format_s_values()

    print(000, 000, "--- string.format %s Test ---")
    print(000, 020, "Test 00: " .. string_result00)
    print(000, 040, "Test 01: " .. string_result01)
    print(000, 060, "Test 02: " .. tostring(boolean_result02))
    print(000, 080, "Test 03: " .. string_result03)
    print(000, 100, "Test 04: " .. string_result04)
end

--[[
=== EXPECTED OUTPUT ===

string_result00: "12 / 15"
string_result01: "[  2.5|true  |nil|x]"
boolean_result02: true
string_result03: "1-7-false"
string_result04: ""hi"|5|true"

--]]
