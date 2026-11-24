--@ --gc arena --gc-check: stores that do NOT escape an arena pass the check
--@ (no false positives): numbers and ROM strings anywhere, arena values into
--@ arena tables, older values into arena tables, outer-arena values into
--@ inner-arena tables, upvalues made inside the arena. A panic here would
--@ halt the cart before the results are written.
--@ (The escaping stores -- a global, an older table's value or key, an
--@ upvalue, setmetatable, table.insert -- were each checked to reach the
--@ panic screen by hand; see 06-09 for tests that expect a panic label.)
--@ Results stored in global variables for automated memory scraping.
--#gc arena
--#gc-check

local old_list = {}
gold = "rom literal"

function test_arena_check_clean()
    local m = arena.mark()
    -- numbers and ROM strings may go anywhere
    old_list[1] = 42
    old_list[2] = "literal"
    gold = "another literal"
    count = 7
    -- arena values into arena tables
    local t = { "a" .. count, { count } }
    t.name = "n" .. count
    setmetatable(t, { __index = t })
    -- older values into arena tables
    t[3] = old_list
    -- a closure over an arena local, writing it
    local acc = "s"
    local add = function(x) acc = acc .. x end
    add("1") add("2")
    local len = #acc
    -- nested: an outer-arena table takes inner values only within the inner
    local inner = arena.mark()
    local u = { t }
    u[2] = "x" .. len
    arena.release(inner)
    arena.release(m)

    number_result1 = old_list[1]                               -- Expected: 42
    number_result2 = len                                       -- Expected: 3
    string_result1 = old_list[2]                               -- Expected: "literal"
end

function main()
    ioports.gpu.clear("black")
    test_arena_check_clean()
    print(100, 0, "--- arena check ---")
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 42.0000
number_result2: 3.0000
string_result1: "literal"
]]
