--@ Vircon32 Lua Table-Constructor Function Unit Test
--@ Functions defined inside a table constructor (`u = function(m) ... end`,
--@ called as m:u()) are the norm for game objects. Two bugs lived there:
--@ 1. The body inherited the constructor's live, pinned registers, and under
--@    that pressure a register still in use was handed out again:
--@    `m.t - m.smove` compiled to FSUB R1, R1 (witchem_up's boss froze in the
--@    top-left corner; its fields turned into stale strings).
--@ 2. `local x, y = obj:pos()` -- a callee not known at compile time -- got
--@    only its first return value (the boss's orbiting rocks: y = nil).
--@ Results are stored in global variables for automated memory scraping.

pow = math.pow
local function inOutQuad(t, b, c, d)
    t = t / d * 2
    if t < 1 then
        return c / 2 * pow(t, 2) + b
    else
        return -c / 2 * ((t - 1) * (t - 3) - 1) + b
    end
end

defs = {
[4] = {
    l = 50, ht = 0, yinc = 0, rx = 0, ry = 0, rw = 0, rh = 0, dmg = 0,
    moves = {{180, 30}, {160, 40}},
    sh_type = 1, shooting = false;
    sh_time = 100, shoots = 10, rock_rot = 0, rocks = {},
    tnext = 0, inext = 1, smove = 0, from = {0, 0},
    u = function(m)
        if m.tnext < m.t then
            m.tnext = m.t + 200
            m.smove = m.t
            from = {m.a, m.b}
        end
        if m.t < m.smove + 100 then
            m.a = inOutQuad(m.t - m.smove, from[1], m.moves[m.inext][1] - m.x - from[1], 150)
            m.b = inOutQuad(m.t - m.smove, from[2], m.moves[m.inext][2] - m.y - from[2], 150)
        end
        m.t = m.t + 1
    end,
    pos = function(m)
        return m.x + m.a, m.y + m.b + m.yinc
    end,
    three = function(m)
        return 1, 2, 3
    end,
    one = function(m)
        return 7
    end,
    none = function(m)
    end
}}

function new_enemy(type, x, y, arg)
    local def = defs[type]
    local e = {x = x, y = y, a = 0, b = 0, t = 0, run = true, arg = arg}
    for k, v in pairs(def) do
        e[k] = v
    end
    return e
end

function main()
    local m = new_enemy(4, 100, 50)
    m.t = 601

    -- === Test 00: the method body computes with every register ===
    for i = 1, 50 do m:u() end
    string_result00a = type(m.a)
    string_result00b = type(m.b)
    boolean_result00c = math.abs(m.a - 17.0738) < 0.001
    boolean_result00d = math.abs(m.b + 4.2684) < 0.001
    __rawasm__("__debug0:")

    -- === Test 01: every return value of a method called by name ===
    m.a, m.b, m.yinc = 1, 2, 3
    local x, y = m:pos()
    number_result01a = x
    number_result01b = y
    local p, q, r = m:three()
    number_result01c = p + q + r
    __rawasm__("__debug1:")

    -- === Test 02: fewer values than targets are nil ===
    local o1, o2 = m:one()
    number_result02a = o1
    boolean_result02b = o2 == nil
    local n1, n2 = m:none()
    boolean_result02c = n1 == nil and n2 == nil
    local fl = math.floor
    local f1, f2 = fl(2.5)
    number_result02d = f1
    boolean_result02e = f2 == nil
    local f3, f4 = math.floor(3.5)
    number_result02f = f3
    boolean_result02g = f4 == nil
    __rawasm__("__debug2:")

    -- === Test 03: a stale count from an argument's call isn't used ===
    local s1, s2 = math.floor(m:three())
    number_result03a = s1
    boolean_result03b = s2 == nil
    __rawasm__("__debug3:")
end

--[[
=== EXPECTED OUTPUT ===

string_result00a: "number"
string_result00b: "number"
boolean_result00c: true
boolean_result00d: true
number_result01a: 101.0000
number_result01b: 55.0000
number_result01c: 6.0000
number_result02a: 7.0000
boolean_result02b: true
boolean_result02c: true
number_result02d: 2.0000
boolean_result02e: true
number_result02f: 3.0000
boolean_result02g: true
number_result03a: 1.0000
boolean_result03b: true

--]]
