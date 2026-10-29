--#api pico8
--@ Vircon32 Lua PICO-8 all() as a value Unit Test
--@ `for v in all(t)` is lowered inline (see 15_pico8_all_inline.lua); every
--@ other use of all() -- `local it = all(t)`, `f = all`, an iterator kept in
--@ a table, `for v in all(t), x do` -- calls the prelude's all(), which
--@ returns PICO-8's iterator function. Each case must visit exactly what
--@ the inline loop does (PICO-8's deletion-tolerant order); the expected
--@ values were produced by running PICO-8's own definition of all() under
--@ real Lua 5.4.
--@ Results are stored in global variables for automated memory scraping.

-- visits t through an iterator function, up to 20 steps (a runaway iterator
-- shows up as a long string instead of hanging the test)
local function walk(it)
    local s = ""
    for k = 1, 20 do
        local v = it()
        if v == nil then break end
        s = s .. tostr(v) .. ","
    end
    return s
end

local function cat(t)
    return walk(all(t))
end

-- a plain array
string_result00a = cat({1, 2, 3, 4, 5})
-- empty
string_result00b = cat({})
-- false is visited, only nil ends the loop
string_result00c = cat({false, 7, false})
-- repeated values
string_result00d = cat({5, 5, 5, 6})

-- deleting the current element while iterating: every element still seen
local t = {10, 20, 30, 40, 50}
local s = ""
local it = all(t)
for k = 1, 20 do
    local v = it()
    if v == nil then break end
    s = s .. v .. ","
    if v == 20 or v == 40 then del(t, v) end
end
string_result01a = s
number_result01b = #t

-- deleting an earlier element (the current one moves down one slot)
t = {1, 2, 3, 4, 5, 6}
s = ""
it = all(t)
for k = 1, 20 do
    local v = it()
    if v == nil then break end
    s = s .. v .. ","
    if v == 3 then del(t, 1) end
end
string_result01c = s

-- appending while iterating: new elements are visited
t = {1, 2, 3}
s = ""
it = all(t)
for k = 1, 20 do
    local v = it()
    if v == nil then break end
    s = s .. v .. ","
    if v < 3 and #t < 6 then add(t, v + 10) end
end
string_result02a = s

-- all(nil) visits nothing, as in PICO-8
string_result03a = cat(nil)

-- two iterators over one table are independent
t = {1, 2, 3}
local a, b = all(t), all(t)
s = ""
for k = 1, 3 do s = s .. a() .. "," .. b() .. ";" end
string_result04a = s
-- an exhausted iterator keeps returning nil
number_result04b = (a() == nil and a() == nil) and 1 or 0

-- `all` itself is a value
local f = all
string_result05a = walk(f({7, 8, 9}))

-- the iterator is a value too: kept in a table, passed to a function
local holder = {next_item = all({"x", "y", "z"})}
string_result06a = walk(holder.next_item)
local function twice(g) return g(), g() end
local p, q = twice(all({"m", "n", "o"}))
string_result06b = p .. q

-- the explicit-list for-in form keeps its iterator expression as written
s = ""
for v in all({4, 5, 6}), nil do s = s .. v .. "," end
string_result07a = s

function _update() end
function _draw() end

--[[
=== EXPECTED OUTPUT ===

string_result00a: "1,2,3,4,5,"
string_result00b: ""
string_result00c: "false,7,false,"
string_result00d: "5,5,5,6,"
string_result01a: "10,20,30,40,50,"
number_result01b: 3.0000
string_result01c: "1,2,3,4,5,6,"
string_result02a: "1,2,3,11,12,"
string_result03a: ""
string_result04a: "1,1;2,2;3,3;"
number_result04b: 1.0000
string_result05a: "7,8,9,"
string_result06a: "x,y,z,"
string_result06b: "mn"
string_result07a: "4,5,6,"

--]]
