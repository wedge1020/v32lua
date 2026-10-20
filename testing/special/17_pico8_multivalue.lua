--#api pico8
--@ Vircon32 Lua PICO-8 multi-value Unit Test
--@ unpack(), `...` and calls returning several values spread into the last
--@ argument, return list, table field and assignment (node/multivalue.c),
--@ as just_one_boss's promise chains need; add/del/count/foreach on nil
--@ do nothing, as in PICO-8.
--@ Results are stored in global variables for automated memory scraping.

local function n(...) return #{...} end
local function cat(...)
    local s = ""
    for v in all({...}) do s = s .. tostr(v) .. "," end
    return s
end

-- PICO-8's unpack(t, i, j): every value, not just 8
local big = {}
for i = 1, 20 do add(big, i) end
number_result00a = n(unpack(big))
string_result00b = cat(unpack(big, 18))
string_result00c = cat(unpack({1, 2, 3}, 2, 3))
string_result00d = cat(1, unpack({}))

-- a promise-style dispatcher: fn(unpack(args)) and ctx[name](ctx, unpack(args))
local obj = {base = 100}
function obj.go(self, a, b, c) return self.base + a + b * 10 + (c or 0) * 100 end
local function call(ctx, name, ...)
    local args = {...}
    return ctx[name](ctx, unpack(args))
end
number_result01a = call(obj, "go", 1, 2, 3)
number_result01b = call(obj, "go", 4, 5)

-- forwarding `...` through several levels, into a method with a long list
local function seq(self, first, ...)
    local rest = {...}
    if #rest > 0 then return first .. seq(self, ...) end
    return first
end
local function fwd(...) return seq(nil, ...) end
string_result02a = fwd("a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l")

-- a cart's own recursive unpack (just_one_boss defines one)
local function myunpack(list, from, to)
    from, to = from or 1, to or #list
    if from <= to then return list[from], myunpack(list, from + 1, to) end
end
string_result03a = cat(myunpack({5, 6, 7, 8, 9, 10, 11, 12, 13, 14}))
local a, b, c = myunpack({"x", "y"})
string_result03b = tostr(a) .. tostr(b) .. tostr(c)

-- table constructor and return list tails
local function two() return 1, 2 end
string_result04a = cat(unpack({0, two()}))
local function pre(...) return "p", ... end
string_result04b = cat(pre(two()))

-- nil-tolerant list helpers
local none = nil
number_result05a = count(none)
local r = add(none, 1)
boolean_result05b = r == nil
del(none, 1)
foreach(none, print)
boolean_result05c = true

function _update() end
function _draw() end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 20.0000
string_result00b: "18,19,20,"
string_result00c: "2,3,"
string_result00d: "1,"
number_result01a: 421.0000
number_result01b: 154.0000
string_result02a: "abcdefghijkl"
string_result03a: "5,6,7,8,9,10,11,12,13,14,"
string_result03b: "xy[nil]"
string_result04a: "0,1,2,"
string_result04b: "p,1,2,"
number_result05a: 0.0000
boolean_result05b: true
boolean_result05c: true

--]]
