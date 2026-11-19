--@ Vircon32 Lua --#hook-fn Unit Test
--@ --#hook-fn FN=HOOK inserts "if HOOK(<FN's parameters>) then return end" at the top
--@ of FN's body: HOOK sees every call; returning true skips FN's own code, anything
--@ else lets it run. FN is not edited.
--@ Results are stored in global variables for automated memory scraping.
--#hook-fn work=gate
--#hook-fn Obj.method=gate2

number_result1 = 0
number_result2 = 0
number_result3 = 0
number_result4 = 0
number_result5 = 0

hook_calls = 0
hook_sum = 0
function gate(a, b)
    hook_calls = hook_calls + 1
    hook_sum = hook_sum + a * 10 + b
    return a > 5                    -- big first arguments are handled by the hook
end

local done = 0
function work(a, b)
    done = done + a + b
    return a
end

Obj = {}
gate2_n = 0
function gate2(self, x) gate2_n = gate2_n + x return false end
function Obj.method(self, x) return x * 2 end

function main()
    local r1 = work(1, 2)               -- runs: done = 3
    local r2 = work(7, 100)             -- skipped by the hook (returns nil)
    local r3 = work(2, 4)               -- runs: done = 9
    number_result1 = done               -- Expected: 9
    number_result2 = hook_calls         -- Expected: 3
    number_result3 = hook_sum           -- Expected: 12 + 170 + 24 = 206
    number_result4 = (r2 == nil) and 1 or 0   -- Expected: 1
    number_result5 = Obj.method(Obj, 21) + gate2_n   -- Expected: 42 + 21 = 63
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 9.0000
number_result2: 3.0000
number_result3: 206.0000
number_result4: 1.0000
number_result5: 63.0000
]]
