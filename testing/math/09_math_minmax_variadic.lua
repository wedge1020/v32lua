
--#title "[v32lua] math.min / math.max variadic unit test"
--@ Vircon32 Lua math.min()/math.max() with any number of arguments.
--@ Real Lua folds left over one or more arguments; this used to be
--@ refused for anything but exactly two ("math.min() expects exactly
--@ two arguments"), which broke e.g. math.min(1, v.t/200, (v.len-v.t)/300).
--@ Results stored in global variables for automated memory scraping.

local function id(x) return x end

function test_math_minmax_variadic()
    -- === Test 1: three arguments ===
    number_result1 = math.min(3, 1, 2)            -- Expected: 1
    number_result2 = math.max(3, 1, 2)            -- Expected: 3

    -- === Test 2: a single argument is returned unchanged ===
    number_result3 = math.min(5)                  -- Expected: 5
    number_result4 = math.max(-7)                 -- Expected: -7

    -- === Test 3: five arguments, mixed signs and a fraction ===
    number_result5 = math.min(4, 9, -2, 6, 0.5)   -- Expected: -2
    number_result6 = math.max(4, 9, -2, 6, 0.5)   -- Expected: 9

    -- === Test 4: the expression that exposed it (BlasTIC's envelope) ===
    local t, len = 50, 300
    number_result7 = math.min(1, t / 200, (len - t) / 300)   -- Expected: 0.25

    -- === Test 5: calls among the arguments (registers don't survive a CALL) ===
    number_result8  = math.max(id(2), 8, id(5))   -- Expected: 8
    number_result9  = math.min(9, id(4), id(6))   -- Expected: 4
    number_result10 = math.max(0, id(3), id(11), 2)   -- Expected: 11
    number_result11 = math.min(id(7), id(3), id(5))   -- Expected: 3

    -- === Test 6: nested, and two arguments still work ===
    number_result12 = math.max(math.min(8, 2, 6), math.min(1, 5, 3))   -- Expected: 2
    number_result13 = math.min(5, 10)             -- Expected: 5
end

function main()
    ioports.gpu.clear("black")
    test_math_minmax_variadic()

    print(100, 00,  "--- math.min/max variadic ---")
    print(100, 20,  "min(3,1,2): " .. number_result1)
    print(100, 40,  "max(3,1,2): " .. number_result2)
    print(100, 60,  "min(5): " .. number_result3)
    print(100, 80,  "max(-7): " .. number_result4)
    print(100, 100, "min(5 args): " .. number_result5)
    print(100, 120, "max(5 args): " .. number_result6)
    print(100, 140, "envelope: " .. number_result7)
    print(100, 160, "max(f,8,f): " .. number_result8)
    print(100, 180, "min(9,f,f): " .. number_result9)
    print(100, 200, "max(0,f,f,2): " .. number_result10)
    print(100, 220, "min(f,f,f): " .. number_result11)
    print(100, 240, "nested: " .. number_result12)
    print(100, 260, "min(5,10): " .. number_result13)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 1.0000
number_result2: 3.0000
number_result3: 5.0000
number_result4: -7.0000
number_result5: -2.0000
number_result6: 9.0000
number_result7: 0.2500
number_result8: 8.0000
number_result9: 4.0000
number_result10: 11.0000
number_result11: 3.0000
number_result12: 2.0000
number_result13: 5.0000
]]
