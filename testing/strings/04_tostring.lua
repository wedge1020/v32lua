--#title "[v32lua] tostring() unit test"
--@ Vircon32 Lua tostring() Unit Test -- basic/safe cases
--@ Covers nil, true/false, whole numbers, and string passthrough. All of
--@ these go through __tostring_shared_body's PRIMITIVE CHECKS or the
--@ correctly-guarded ROM/RAM string passthrough, none of which are known
--@ to be buggy. table/function/fractional-float cases are split into
--@ 07_string_tostring_function_tag.lua and
--@ 08_string_tostring_float_precision.lua because those DO have known or
--@ suspected issues (see AUDIT sections 4 and 5) and shouldn't be able to
--@ mask the results here if they misbehave.

function test_tostring_basic()
    string_result1 = tostring(nil)     -- Expected: "nil"
    __rawasm__("__debug1:")
    string_result2 = tostring(true)    -- Expected: "true"
    __rawasm__("__debug2:")
    string_result3 = tostring(false)   -- Expected: "false"
    __rawasm__("__debug3:")
    string_result4 = tostring(42)      -- Expected: "42"
    __rawasm__("__debug4:")
    string_result5 = tostring(0)       -- Expected: "0"
    __rawasm__("__debug5:")
    string_result6 = tostring("already a string")  -- Expected: "already a string"
    __rawasm__("__debug6:")
    string_result7 = tostring(123) .. tostring(456)  -- Expected: "123456"
    __rawasm__("__debug7:")
end

function test_tostring_function_tag()
    local t = {x = 1, y = 2}
    string_result8 = tostring(t)  -- Expected: "table" (control group -- known correct tag)

    local func = function() end
    string_result9 = tostring(func)  -- Expected: "function" (suspected wrong tag)

    -- Concatenating the (possibly mistagged) result exercises whether the
    -- bad tag also breaks downstream consumption, not just the memory
    -- scraper's direct read of string_result1.
    string_result10 = "Type was- " .. string_result9

    __rawasm__("__debug8:")
end

function test_tostring_float_precision()
    string_result11 = tostring(42.0)   -- Expected: "42" (control group)
    __rawasm__("__debug9:")

    string_result12 = tostring(3.14)   -- Current: "3.140000"
    __rawasm__("__debug10:")

    string_result13 = tostring(0.5)    -- Current: "0.500000"
    __rawasm__("__debug11:")

    string_result14 = tostring(-2.75)  -- Current: "-2.750000"
    __rawasm__("__debug12:")
end

function main()
    ioports.gpu.clear("black")
    test_tostring_basic()
    test_tostring_function_tag()
    test_tostring_float_precision()

    print(100, 00,  "--- tostring basic Test ---")
    print(100, 20,  "tostring(nil): "   .. string_result1)
    print(100, 40,  "tostring(true): "  .. string_result2)
    print(100, 60,  "tostring(false): " .. string_result3)
    print(100, 80,  "tostring(42): "    .. string_result4)
    print(100, 100, "tostring(0): "     .. string_result5)
    print(100, 120, "tostring(str): "   .. string_result6)
    print(100, 140, "concat tostring: " .. string_result7)

    print(100, 160, "--- tostring(function) tag test ---")
    print(100, 180, "tostring(table): " .. string_result8)
    print(100, 200, "tostring(func): "  .. string_result9)
    print(100, 220, string_result10)

    print(100, 240,  "--- tostring() float precision ---")
    print(100, 260,  "tostring(42.0): " .. string_result11)
    print(100, 280,  "tostring(3.14): " .. string_result12)
    print(100, 300,  "tostring(0.5): " .. string_result13)
    print(100, 320,  "tostring(-2.75): " .. string_result14)
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "nil"
string_result2: "true"
string_result3: "false"
string_result4: "42"
string_result5: "0"
string_result6: "already a string"
string_result7: "123456"
string_result8: "table"
string_result9: "function"
string_result10: "Type was- function"
string_result11: "42"
string_result12: "3.140000"
string_result13: "0.500000"
string_result14: "-2.750000"
]]
