--@ Vircon32 Lua Call / Assignment Statement Forms Unit Test
--@ Forms the grammar handles since its duplicated call and assignment
--@ rules were merged (%expect 2): a call on a call's result as a statement,
--@ table-field targets with several values, and f"s" / f{...} on fields.
--@ Results are stored in global variables for automated memory scraping.

function make_setter()
    return function(x) number_result00 = x end
end

function id(t) return t end

function test_forms()
    -- === Test 00: g()(x) as a statement ===
    make_setter()(5)
    __rawasm__("__debug0:")

    -- === Test 01: t.a = x, y (extra values are dropped) ===
    local t = { f = id }
    t.a = 7, 8
    number_result01 = t.a
    __rawasm__("__debug1:")

    -- === Test 02: t.f{...} and t.f"s" ===
    number_result02 = t.f{ 9 }[1]
    string_result02 = t.f"s"
    __rawasm__("__debug2:")

    -- === Test 03: field and index targets in one assignment ===
    local u = {}
    u.x, u[2] = 3, 4
    number_result03 = u.x + u[2]
    __rawasm__("__debug3:")

    -- === Test 04: values are evaluated before any target is assigned ===
    local v = 1
    v, t.b = t.a + 1, v
    number_result04 = v * 10 + t.b
    __rawasm__("__debug4:")
end

function main()
    test_forms()
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 5.0000
number_result01: 7.0000
number_result02: 9.0000
string_result02: "s"
number_result03: 7.0000
number_result04: 81.0000

--]]
