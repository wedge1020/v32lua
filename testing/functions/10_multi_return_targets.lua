--@ Vircon32 Lua Multi-Return Targets Unit Test
--@ Multiple return values assigned to table fields and indexes, and
--@ functions that forward another function's results when that function
--@ is defined LATER in the file. Regression test for warm_wheels: its
--@ `o.vx, o.vy = rotate(...)` silently left both fields unchanged, and
--@ `vector()` (defined before `rotate()`, which it returns) was counted as
--@ returning one value, so `local x, y = vector(...)` read y from a stale
--@ register -- every car's velocity became NaN on the first frame.
--@ Results are stored in global variables for automated memory scraping.

function forward(a, b)          -- defined BEFORE the function it forwards
    return pair(a, b)
end

function pair(a, b)
    return a + b, a * b
end

function test_multi_return_targets()
    -- === Test 00: two table fields from one call ===
    local o = { vx = 1, vy = 2 }
    o.vx, o.vy = pair(3, 4)
    number_result00a = o.vx     -- 7
    number_result00b = o.vy     -- 12
    __rawasm__("__debug0:")

    -- === Test 01: nested table fields and a computed index ===
    local t = { inner = {} }
    local k = 2
    t.inner.a, t[k + 1] = pair(5, 6)
    number_result01a = t.inner.a   -- 11
    number_result01b = t[3]        -- 30
    __rawasm__("__debug1:")

    -- === Test 02: more targets than values: the extra one is nil ===
    local u = { x = 1, y = 2, z = 3 }
    u.x, u.y, u.z = pair(1, 1)
    number_result02a = u.x      -- 2
    number_result02b = u.y      -- 1
    boolean_result02 = (u.z == nil)   -- true
    __rawasm__("__debug2:")

    -- === Test 03: forwarding a function defined later ===
    local s, p = forward(2, 5)
    number_result03a = s        -- 7
    number_result03b = p        -- 10
    __rawasm__("__debug3:")

    -- === Test 04: forwarded values into table fields ===
    local v = {}
    v.s, v.p = forward(3, 3)
    number_result04 = v.s + v.p   -- 15
    __rawasm__("__debug4:")

    -- === Test 05: table.unpack into table fields ===
    local w = {}
    w.a, w.b = table.unpack({ 8, 9 })
    number_result05 = w.a * 10 + w.b   -- 89
    __rawasm__("__debug5:")
end

function main()
    ioports.gpu.clear("black")
    test_multi_return_targets()

    print(000, 000, "--- Multi-Return Targets Test ---")
    print(000, 020, "Test 00: " .. number_result00a .. " " .. number_result00b)
    print(000, 040, "Test 01: " .. number_result01a .. " " .. number_result01b)
    print(000, 060, "Test 02: " .. number_result02a .. " " .. number_result02b .. " " .. tostring(boolean_result02))
    print(000, 080, "Test 03: " .. number_result03a .. " " .. number_result03b)
    print(000, 100, "Test 04: " .. number_result04)
    print(000, 120, "Test 05: " .. number_result05)
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 7.0000
number_result00b: 12.0000
number_result01a: 11.0000
number_result01b: 30.0000
number_result02a: 2.0000
number_result02b: 1.0000
boolean_result02: true
number_result03a: 7.0000
number_result03b: 10.0000
number_result04: 15.0000
number_result05: 89.0000

--]]
