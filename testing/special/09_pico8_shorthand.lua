--#api pico8
--@ Vircon32 Lua PICO-8 Shorthand / Cart-Idiom Unit Test
--@ PICO-8's then-less `if (c) ...` and do-less `while (c) ...`: the body is
--@ the rest of the line (return with a value, several statements, else).
--@ Also idioms from ppwr.p8: unpack() spread into calls and constructors,
--@ builtins looked up through _ENV, deli, oval, poke(a, unpack(t)), split.
--@ Results are stored in global variables for automated memory scraping.

function f1(n)
if (n==1) return 12
return 5
end

function f2(a) if (a) return 1 end

function g3(a, b, c) return a + b + c end

function _init()
    -- === Test 00: return with a value, one-line function ===
    number_result00a = f1(1)
    number_result00b = f1(2)
    number_result00c = f2(true) + (f2(false) or 2)
    __rawasm__("__debug0:")

    -- === Test 01: several statements, else, nesting, comments ===
    local x, y, z = 0, 0, 0
    if (x == 0) x = 1 y = 2 -- two statements, then a comment
    number_result01a = x + y
    if (x == 5) z = 1 else z = 2
    number_result01b = z
    local w = 0
    if (x == 1) if (y == 2) w = 7
    number_result01c = w
    if(x==1)w=w+1
    number_result01d = w
    __rawasm__("__debug1:")

    -- === Test 02: conditions that continue after the parentheses ===
    local a, b = 3, 4
    local r = 0
    if (a) < (b) then r = 1 end
    number_result02a = r
    if (a + 1) == b and (b - 1) == a then
        r = 2
    end
    number_result02b = r
    string_result02c = "if (a) b"
    --[[ if (a) b ]]
    __rawasm__("__debug2:")

    -- === Test 03: a body spanning lines, while ===
    local calls = 0
    local function run(fn) fn() end
    if (a == 3) run(function()
        calls = calls + 1
    end)
    number_result03a = calls
    local n = 0
    while (n < 5) n = n + 1
    number_result03b = n
    __rawasm__("__debug3:")

    -- === Test 04: unpack() spreads, deli, split ===
    local t = {1, 2, 3}
    number_result04a = g3(unpack(t))
    local c = {unpack({5, 6, 7, 8})}
    number_result04b = #c
    number_result04c = deli(c, 1) * 10 + #c
    local s = split("10,x,,20")
    number_result04d = s[1] + s[4]
    string_result04e = s[2]
    number_result04f = #s
    string_result04g = type(split("1,2", ",", false)[1])
    __rawasm__("__debug4:")

    -- === Test 05: builtins by name, oval, poke(a, unpack(t)) ===
    string_result05a = type(_ENV["rectfill"])
    local k = "circfill"
    string_result05b = type(_ENV[k])
    ovalfill(10, 10, 30, 20, 8)
    oval(10, 10, 30, 20, 7)
    poke(0x4300, unpack(split("7,8,9")))
    number_result05c = peek(0x4300) + peek(0x4301) + peek(0x4302)
    number_result05d = assert(42)
    __rawasm__("__debug5:")
end

function _draw()
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 12.0000
number_result00b: 5.0000
number_result00c: 3.0000
number_result01a: 3.0000
number_result01b: 2.0000
number_result01c: 7.0000
number_result01d: 8.0000
number_result02a: 1.0000
number_result02b: 2.0000
string_result02c: "if (a) b"
number_result03a: 1.0000
number_result03b: 5.0000
number_result04a: 6.0000
number_result04b: 4.0000
number_result04c: 53.0000
number_result04d: 30.0000
string_result04e: "x"
number_result04f: 4.0000
string_result04g: "string"
string_result05a: "function"
string_result05b: "function"
number_result05c: 24.0000
number_result05d: 42.0000

--]]
