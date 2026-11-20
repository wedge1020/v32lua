--@ Vircon32 Lua t[expr] where expr is provably a number.
--@ Such keys skip the "is it a number" test of the inline array read; a NaN,
--@ zero, negative, fractional or too-large key must still miss (nil) rather
--@ than read outside the array. Literal keys (t[3], t[20]) and a for
--@ variable key take the same inline path.
--@ Results stored in global variables for automated memory scraping.

number_result1 = 0
number_result2 = 0
number_result3 = 0
number_result4 = 0
number_result5 = 0
number_result6 = 0
number_result7 = 0

function test_index_known_number_key()
    local t = {10, 20, 30}
    local n = 0 / 0
    local z = 0
    local big = 1e9
    local miss = 0
    if t[n + 0] == nil then miss = miss + 1 end
    if t[z + 0] == nil then miss = miss + 1 end
    if t[big * 1] == nil then miss = miss + 1 end
    if t[-1 + z] == nil then miss = miss + 1 end
    if t[4 + z] == nil then miss = miss + 1 end
    if t[1.5 * 1] == nil then miss = miss + 1 end
    number_result1 = miss                 -- Expected: 6
    number_result2 = t[3 + z]             -- Expected: 30
    local s = 0
    for i = 1, 3 do s = s + t[i] end
    number_result3 = s                    -- Expected: 60
    number_result4 = t[3] + (t[4] == nil and 1 or 0)   -- Expected: 31
    local m = setmetatable({1, 2}, { __index = function(_, k) return k * 10 end })
    number_result5 = m[1 + 1] + m[1 + 4] + m[z + 0]    -- Expected: 52
    local u = {}
    for i = 1, 20 do u[i] = i * 2 end
    number_result6 = u[20] + u[17] + (u[21] == nil and 1 or 0)   -- Expected: 75
    local w = {5, 6, 7, 8}
    local acc = 0
    for r = 0, 1 do for c = 1, 2 do acc = acc + w[r * 2 + c] end end
    number_result7 = acc                  -- Expected: 26
end

function main()
    test_index_known_number_key()
    ioports.gpu.clear("black")
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 6.0000
number_result2: 30.0000
number_result3: 60.0000
number_result4: 31.0000
number_result5: 52.0000
number_result6: 75.0000
number_result7: 26.0000
]]
