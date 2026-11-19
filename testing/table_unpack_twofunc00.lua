--#title "[v32lua] table.unpack in two functions"
--@ table.unpack used in two different functions. Each used to emit the
--@ same __unpack_nil_N label (the per-function label counter restarted),
--@ so the assembler refused it: "label already declared".

local function f(t) local a, b, c = table.unpack(t) return a + b + c end
local function g(t) local a, b, c, d = table.unpack(t) return a + b + c + d end

function main()
    number_result1 = f({1, 2, 3})        -- Expected: 6
    number_result2 = g({1, 2, 3, 4})     -- Expected: 10
    print(100, 100, "f: " .. number_result1)
    print(100, 120, "g: " .. number_result2)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 6.0000
number_result2: 10.0000
]]
