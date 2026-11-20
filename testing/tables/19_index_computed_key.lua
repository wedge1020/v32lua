--@ Vircon32 Lua t[expr] with a computed key.
--@ t[i+1], t[f(x)], t[c*100+r] read the array part inline when the key is a
--@ whole number in range; every other key (fraction, 0, negative, beyond the
--@ array, in the hash part, a string) takes the general lookup. Also string
--@ methods called on strings (s:sub(), s:upper() ...), which resolve without
--@ the general lookup, and on non-strings (a table with a field of that name).
--@ Results stored in global variables for automated memory scraping.

number_result1 = 0
number_result2 = 0
number_result3 = 0
number_result4 = 0
number_result5 = 0
number_result6 = 0
number_result7 = 0
number_result8 = 0
number_result9 = 0
number_result10 = 0

local function id(x) return x end

function test_index_computed_key()
    local t = {10, 20, 30, 40}
    local u = {}
    u[105] = 7
    u[0] = 9
    u[-3] = 4
    local s = 0
    for i = 1, 3 do s = s + t[i + 1] end        -- 20 + 30 + 40
    number_result1 = s                           -- Expected: 90
    number_result2 = t[id(2)] + t[id(4)]         -- Expected: 60
    number_result3 = u[100 + 5] + u[id(1) - 1] + u[id(-2) - 1]   -- Expected: 20
    number_result4 = (t[id(2.5)] == nil and 1 or 0) + (t[id(9)] == nil and 1 or 0) + (t[id(0)] == nil and 1 or 0)   -- Expected: 3
    local names = { alpha = 5, beta = 6 }
    number_result5 = names["al" .. "pha"] + names[id("be") .. "ta"]   -- Expected: 11
    -- a metatable answering for holes and out-of-range keys
    local m = setmetatable({1, 2}, { __index = function(_, k) return k * 10 end })
    number_result6 = m[id(1) + 1] + m[id(1) + 4]   -- 2 + 50 = 52
    local str = "Hello"
    number_result7 = #str:sub(2, 4) + #str:upper() + str:byte(1)   -- 3 + 5 + 72 = 80
    local obj = { sub = function(self, a) return a * 2 end }
    number_result8 = obj:sub(21) + #(("abc"):rep(2))               -- 42 + 6 = 48
    -- sparse numeric keys (y*100+x style): 50 stored, collisions included; 50 misses
    local w = {}
    for k = 0, 9 do for r = 0, 4 do w[k * 100 + r] = k * 100 + r end end
    local sum, miss = 0, 0
    for k = 0, 9 do
        for r = 0, 4 do sum = sum + w[k * 100 + r] end
        for r = 5, 9 do if w[k * 100 + r] == nil then miss = miss + 1 end end
    end
    number_result9 = sum     -- Expected: 22600
    number_result10 = miss   -- Expected: 50
end

function main()
    test_index_computed_key()
    ioports.gpu.clear("black")
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 90.0000
number_result2: 60.0000
number_result3: 20.0000
number_result4: 3.0000
number_result5: 11.0000
number_result6: 52.0000
number_result7: 80.0000
number_result8: 48.0000
number_result9: 22600.0000
number_result10: 50.0000
]]
