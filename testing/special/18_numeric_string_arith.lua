--#api pico8
--@ Vircon32 Lua numeric-string arithmetic Unit Test
--@ A numeric string operand of + - * / % ^ \ and unary - becomes its
--@ number, as in Lua and PICO-8 ("12" + 1 == 13). nanoman decodes its
--@ levels with ("0x"..digit) + 0; without this the sums stayed strings and
--@ its level loader ran away in mset() loops (100% CPU, no progress).
--@ Results are stored in global variables for automated memory scraping.

local d = "a"
number_result00a = ("0x" .. d) + 0
number_result00b = "12" + 1
number_result00c = "0x1f" * 2
number_result00d = 10 - "2.5"
number_result00e = -"3"
number_result00f = "7" % 4
number_result00g = "2" ^ 3
number_result00h = "9" \ 2
local t = {("0x" .. sub("7c", 1, 2)) + 0}
number_result01a = t[1]
local s = "40"
number_result01b = s / "8"
-- still numbers when they already are
number_result01c = 1.5 + 2

function _draw() end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 10.0000
number_result00b: 13.0000
number_result00c: 62.0000
number_result00d: 7.5000
number_result00e: -3.0000
number_result00f: 3.0000
number_result00g: 8.0000
number_result00h: 4.0000
number_result01a: 124.0000
number_result01b: 5.0000
number_result01c: 3.5000

--]]
