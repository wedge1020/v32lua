--#api pico8
--@ Vircon32 Lua PICO-8 Glyph String Unit Test
--@ A .p8 stores PICO-8's glyph characters (button glyphs, heart, star, ...)
--@ as Unicode emoji; in a string each is ONE P8SCII character (128-153), so
--@ #, sub() and ord() agree with PICO-8. Also Lua's \ddd and \xHH escapes.
--@ Results are stored in global variables for automated memory scraping.

function _init()
    -- === Test 00: a glyph is one character ===
    number_result00a = #"🅾️"
    number_result00b = #"press ❎+🅾️"
    __rawasm__("__debug0:")

    -- === Test 01: P8SCII codes ===
    number_result01a = ord("🅾️")
    number_result01b = ord("❎")
    number_result01c = ord("⬅️") + ord("➡️") + ord("⬆️") + ord("⬇️")
    number_result01d = ord("♥")
    __rawasm__("__debug1:")

    -- === Test 02: sub() and chr() ===
    boolean_result02a = sub("a★b", 2, 2) == "★"
    boolean_result02b = chr(135) == "♥"
    __rawasm__("__debug2:")

    -- === Test 03: decimal and hex escapes ===
    string_result03 = "\65\x42\067"
    __rawasm__("__debug3:")
end

function _draw()
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 1.0000
number_result00b: 9.0000
number_result01a: 142.0000
number_result01b: 151.0000
number_result01c: 563.0000
number_result01d: 135.0000
boolean_result02a: true
boolean_result02b: true
string_result03: "ABC"

--]]
