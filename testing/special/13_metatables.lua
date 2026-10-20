--@ Vircon32 Lua Metatable Unit Test
--@ setmetatable / getmetatable / rawget / rawset / rawlen / rawequal and
--@ the __index, __newindex, __call, __tostring, __len and __metatable
--@ events. (Arithmetic and comparison events aren't supported: operators
--@ compile to bare float instructions.)
--@ Results are stored in global variables for automated memory scraping.

-- a class, the usual way
Point = {}
Point.__index = Point
function Point.new(x, y)
    local p = setmetatable({}, Point)
    p.x = x
    p.y = y
    return p
end
function Point:len2() return self.x * self.x + self.y * self.y end
function Point:move(dx, dy) self.x = self.x + dx self.y = self.y + dy end

-- inheritance: Point3 -> Point
Point3 = setmetatable({}, {__index = Point})
Point3.__index = Point3
function Point3.new(x, y, z)
    local p = setmetatable(Point.new(x, y), Point3)
    p.z = z
    return p
end
function Point3:len2() return Point.len2(self) + self.z * self.z end

function main()
    -- === Test 00: __index as a table: methods and defaults ===
    local p = Point.new(3, 4)
    number_result00a = p:len2()
    p:move(1, 1)
    number_result00b = p.x + p.y
    boolean_result00c = rawget(p, "len2") == nil
    boolean_result00d = getmetatable(p) == Point
    __rawasm__("__debug0:")

    -- === Test 01: inheritance chains ===
    local q = Point3.new(1, 2, 2)
    number_result01a = q:len2()
    q:move(1, 0)
    number_result01b = q.x
    __rawasm__("__debug1:")

    -- === Test 02: __index as a function, defaults with numeric keys ===
    local d = setmetatable({}, {__index = function(t, k) return k * 10 end})
    d[2] = 5
    number_result02a = d[2] + d[3] + d[100]
    local calls = 0
    local lazy = setmetatable({}, {__index = function(t, k)
        calls = calls + 1
        rawset(t, k, k .. "!")
        return t[k]
    end})
    string_result02b = lazy.a .. lazy.a
    number_result02c = calls
    __rawasm__("__debug2:")

    -- === Test 03: __newindex (a function, and a table) ===
    local log = {}
    local w = setmetatable({}, {__newindex = function(t, k, v)
        log[#log + 1] = k
        rawset(t, k, v * 2)
    end})
    w.a = 1
    w.a = 5              -- present now: an ordinary store
    w.b = 2
    number_result03a = w.a + w.b
    number_result03b = #log
    local store = {}
    local proxy = setmetatable({}, {__newindex = store, __index = store})
    proxy.k = 7
    boolean_result03c = rawget(proxy, "k") == nil
    number_result03d = store.k + proxy.k
    __rawasm__("__debug3:")

    -- === Test 04: __call, __tostring, __len, __metatable ===
    local adder = setmetatable({base = 10}, {__call = function(self, a, b)
        return self.base + a + b
    end})
    number_result04a = adder(1, 2)
    local v = setmetatable({}, {__tostring = function(t) return "vec!" end,
                                __len = function(t) return 42 end})
    string_result04b = tostring(v)
    number_result04c = #v
    number_result04d = rawlen({1, 2, 3})
    local locked = setmetatable({}, {__metatable = "locked"})
    string_result04e = getmetatable(locked)
    local k = 5
    local inc = setmetatable({}, {__call = function(self, a) return a + k end})
    local twice = setmetatable({}, {__call = function(self, a) return inc(inc(a)) end})
    number_result04f = twice(1) + inc(0)
    local total = 0
    for i = 1, 40 do total = total + inc(i) end
    number_result04g = total
    __rawasm__("__debug4:")

    -- === Test 05: raw access, plain tables, removing a metatable ===
    local t = setmetatable({}, {__index = function() return 1 end})
    number_result05a = t.zz
    setmetatable(t, nil)
    boolean_result05b = t.zz == nil
    boolean_result05c = getmetatable({}) == nil
    boolean_result05d = rawequal(t, t) and not rawequal(t, {})
    local plain = {10, 20}
    number_result05e = plain[1] + #plain
    boolean_result05f = plain.nothing == nil
    __rawasm__("__debug5:")
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 25.0000
number_result00b: 9.0000
boolean_result00c: true
boolean_result00d: true
number_result01a: 9.0000
number_result01b: 2.0000
number_result02a: 1035.0000
string_result02b: "a!a!"
number_result02c: 1.0000
number_result03a: 9.0000
number_result03b: 2.0000
boolean_result03c: true
number_result03d: 14.0000
number_result04a: 13.0000
string_result04b: "vec!"
number_result04c: 42.0000
number_result04d: 3.0000
string_result04e: "locked"
number_result04f: 16.0000
number_result04g: 1020.0000
number_result05a: 1.0000
boolean_result05b: true
boolean_result05c: true
boolean_result05d: true
number_result05e: 12.0000
boolean_result05f: true

--]]
