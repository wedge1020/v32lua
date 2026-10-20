--#title "[v32lua] long comment unit test"
--@ Vircon32 Lua Long Comment Unit Test
--@ --[[ ... ]] and --[==[ ... ]==] comments, including one that ends on
--@ the line it starts with code after it (that code used to be dropped
--@ as part of the comment), and a level-n comment containing ]] .

function add(a, b) --[[ inline ]] return a + b end
--[==[ level 2
with ]] and ]=] inside
]==] number_result00a = 5
--[[ multi
line ]] number_result00b = 6

function main()
    number_result01a = add(1, 2) --[=[ between ]=] + number_result00a
    number_result01b = 10 --[[ ]] - 3
    __rawasm__("__debug0:")
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 5.0000
number_result00b: 6.0000
number_result01a: 8.0000
number_result01b: 7.0000

--]]
