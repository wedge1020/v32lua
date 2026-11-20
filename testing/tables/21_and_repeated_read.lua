--@ Vircon32 Lua `X and X[k]` where X is the same table read twice.
--@ map[r] and map[r][c] or D (the tile-lookup idiom), t.a and t.a.b, and
--@ g[i][j] chains. The second read of X reuses the first (no metatables in
--@ play); a missing row, a false row, a missing column and a column of
--@ 0 / false must all behave as in plain Lua.
--@ Results stored in global variables for automated memory scraping.

number_result1 = 0
number_result2 = 0
number_result3 = 0
number_result4 = 0
number_result5 = 0
number_result6 = 0
number_result7 = 0
number_result8 = 0

map = {}
cfg = { a = { b = 7, z = 0 }, f = false }

function mget(c, r) return map[r] and map[r][c] or 99 end

function test_and_repeated_read()
    map[0] = { [0] = 1, 2, 3 }
    map[1] = { 4, 5, false, 0 }
    map[2] = false
    number_result1 = mget(1, 0) + mget(2, 0) + mget(0, 0)   -- 2 + 3 + 1 = 6
    number_result2 = mget(1, 1) + mget(4, 1)                -- 4 + 0 = 4
    number_result3 = mget(3, 1) + mget(9, 1)                -- false -> 99, nil -> 99 = 198
    number_result4 = mget(1, 2) + mget(1, 7)                -- false row, missing row = 198
    number_result5 = (cfg.a and cfg.a.b or -1) + (cfg.q and cfg.q.b or -1)   -- 7 - 1 = 6
    local g = { { 10, 20 }, { 30, 40 } }
    local i, j = 2, 1
    number_result6 = (g[i] and g[i][j] or 0) + (g[3] and g[3][1] or 5)   -- 30 + 5 = 35
    local zero = (cfg.a and cfg.a.z)
    number_result7 = zero + 1                               -- 0 is truthy: 1
    local f = cfg.f and cfg.f.b
    number_result8 = (f == false) and 1 or 0                -- Expected: 1
end

function main()
    test_and_repeated_read()
    ioports.gpu.clear("black")
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 6.0000
number_result2: 4.0000
number_result3: 198.0000
number_result4: 198.0000
number_result5: 6.0000
number_result6: 35.0000
number_result7: 1.0000
number_result8: 1.0000
]]
