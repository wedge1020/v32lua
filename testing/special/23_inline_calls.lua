--@ Vircon32 Lua inlining / direct calls Unit Test
--@ Calls of named functions are direct CALLs; a call of a function whose body is a
--@ single `return <expr>` with variable / literal arguments is expanded in place.
--@ The expansion must behave exactly like the call: parameters bound to the caller's
--@ variables (even when the names clash), the callee's globals (not the caller's
--@ locals of the same name), missing and extra arguments, and/or on false and nil.
--@ Results are stored in global variables for automated memory scraping.

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

grid = { {1, 2, 3}, {4, 5, 6} }
WALL = 99

function cell(c, r) return grid[r] and grid[r][c] or WALL end   -- inlinable
function sub(a, b) return a - b end                             -- inlinable; order matters
function pick(a, b, c) return c or b or a end                   -- nil/false handling
function scale2(v) return v * 2 + 1 end
function two(x, y) return x end                                 -- an unused parameter
function counter() count = (count or 0) + 1 return count end    -- not inlinable (statement body)
function viaCall(x) return sub(x, 1) end                        -- contains a call: not inlined
function fact(n) if n <= 1 then return 1 end return n * fact(n - 1) end

local function localSq(x) return x * x end                       -- a local function, inlinable

function test_inline()
    local c, r = 3, 1
    number_result1 = cell(c, r)                    -- grid[1][3] = 3
    number_result2 = cell(r, c)                    -- grid[3] is nil -> WALL = 99
    local grid = { {7} }                           -- a caller local named like the callee's global
    number_result3 = cell(1, 1)                    -- still the global grid: 1
    local a, b = 10, 4
    number_result4 = sub(a, b) * 100 + sub(b, a)   -- 6*100 + (-6) = 594
    local c2 = c                                   -- param names equal caller names, swapped
    local r2 = 5
    number_result5 = sub(r2, c2)                   -- 5 - 3 = 2
    local nothing, no = nil, false
    number_result6 = pick(1, nothing, no) + pick(7, nothing, nothing) * 10 + pick(1, 2)   -- (c=false -> b=nil -> a=1): 1 ; pick(7,nil,nil) -> 7*10 ; pick(1,2) -> c=nil,b=2 -> 2   => 1 + 70 + 2 = 73
    number_result7 = scale2(5) + scale2(a) + two(3, 9) + two(8)   -- 11 + 21 + 3 + 8 = 43
    number_result8 = viaCall(10) + localSq(7) + fact(5)           -- 9 + 49 + 120 = 178
    counter() counter()
    number_result9 = counter()                     -- 3
    local f = cell                                 -- the function as a value still works
    number_result10 = f(2, 2) + cell(2, 2, 12345)  -- 5 + 5 (extra argument ignored) = 10
end

function main()
    test_inline()
    ioports.gpu.clear("black")
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 3.0000
number_result2: 99.0000
number_result3: 1.0000
number_result4: 594.0000
number_result5: 2.0000
number_result6: 73.0000
number_result7: 43.0000
number_result8: 178.0000
number_result9: 3.0000
number_result10: 10.0000
]]
