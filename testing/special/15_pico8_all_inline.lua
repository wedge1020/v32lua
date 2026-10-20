--#api pico8
--@ Vircon32 Lua PICO-8 all() Unit Test
--@ `for v in all(t)` steps through the array part inline and falls back to
--@ the runtime step for the end of the loop, deletions, holes, growth and
--@ non-array tables. Every case here must give the same visits as the
--@ runtime step alone (PICO-8's deletion-tolerant order).
--@ Results are stored in global variables for automated memory scraping.

local function cat(t)
    local s = ""
    for v in all(t) do s = s .. tostr(v) .. "," end
    return s
end

-- a plain array
string_result00a = cat({1, 2, 3, 4, 5})
-- empty
string_result00b = cat({})
-- false is visited, only nil ends the loop
string_result00c = cat({false, 7, false})
-- repeated values (the survived-check compares values)
string_result00d = cat({5, 5, 5, 6})

-- deleting the current element while iterating: every element still seen
local t = {10, 20, 30, 40, 50}
local s = ""
for v in all(t) do
    s = s .. v .. ","
    if v == 20 or v == 40 then del(t, v) end
end
string_result01a = s
number_result01b = #t

-- deleting an earlier element (the current one moves down one slot)
t = {1, 2, 3, 4, 5, 6}
s = ""
for v in all(t) do
    s = s .. v .. ","
    if v == 3 then del(t, 1) end
end
string_result01c = s

-- appending while iterating: new elements are visited
t = {1, 2, 3}
s = ""
for v in all(t) do
    s = s .. v .. ","
    if v < 3 and #t < 6 then add(t, v + 10) end
end
string_result02a = s

-- a removed last element shortens the loop
t = {1, 2, 3, 4, 5}
t[5] = nil
string_result02b = cat(t)

-- an array built in the hash part (keys set out of order)
t = {}
t[3] = "c"
t[2] = "b"
t[1] = "a"
string_result02c = cat(t)

-- nested loops over the same table, break, and tables as elements
local objs = {}
for i = 1, 6 do add(objs, {id = i}) end
local pairs_n = 0
for a in all(objs) do
    for b in all(objs) do
        if a ~= b then pairs_n += 1 end
    end
end
number_result03a = pairs_n
s = ""
for o in all(objs) do
    if o.id == 4 then break end
    s = s .. o.id .. ","
end
string_result03b = s

-- deleting objects inside the nested loop (a collision-style sweep)
local ids = ""
for a in all(objs) do
    for b in all(objs) do
        if a ~= b and a.id + b.id == 7 then del(objs, b) end
    end
    ids = ids .. a.id .. ","
end
string_result03c = ids
number_result03d = #objs

-- all(nil) visits nothing (PICO-8 is forgiving here)
local visits = 0
local nothing = nil
for v in all(nothing) do visits += 1 end
number_result04a = visits

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
string_result02b: "1,2,3,4,"
string_result02c: "a,b,c,"
number_result03a: 30.0000
string_result03b: "1,2,3,"
string_result03c: "1,2,3,"
number_result03d: 3.0000
number_result04a: 0.0000

--]]
