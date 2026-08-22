--#title "[v32lua] string.upper() / string.lower() unit test"
--@ Vircon32 Lua string.upper() / string.lower() Unit Test
--@ Exercises the new string.upper/string.lower implementation added in
--@ this patch (compiler dispatch: emit_string_upper_intrinsic /
--@ emit_string_lower_intrinsic; runtime: __builtin_string_upper /
--@ __builtin_string_lower). Hand-traced, not yet run through v32sim.

function test_string_case()
    __rawasm__("__debug0:")
    string_result0 = string.upper("hi")  -- Expected: "HELLO WORLD"
    __rawasm__("__debug0_done:")

    string_result1 = string.upper("hello world")  -- Expected: "HELLO WORLD"
    __rawasm__("__debug1:")

    string_result2 = string.lower("HELLO WORLD")  -- Expected: "hello world"
    __rawasm__("__debug2:")

    string_result3 = string.upper("Already Mixed CASE 123!")  -- Expected: "ALREADY MIXED CASE 123!"
    __rawasm__("__debug3:")

    string_result4 = string.lower("Already Mixed CASE 123!")  -- Expected: "already mixed case 123!"
    __rawasm__("__debug4:")

    string_result5 = string.upper("")  -- Expected: ""
    __rawasm__("__debug5:")

    string_result6 = string.lower("no change needed")  -- Expected: "no change needed"
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_string_case()

    print(100, 00,  "--- string.upper/lower Test ---")
    print(100, 20,  "upper: " .. string_result0)
    print(100, 20,  "upper: " .. string_result1)
    print(100, 40,  "lower: " .. string_result2)
    print(100, 60,  "upper mixed: " .. string_result3)
    print(100, 80,  "lower mixed: " .. string_result4)
    print(100, 100, "upper empty: '" .. string_result5 .. "'")
    print(100, 120, "lower unchanged: " .. string_result6)
end

--[[
=== EXPECTED OUTPUT ===
string_result0: "HI"
string_result1: "HELLO WORLD"
string_result2: "hello world"
string_result3: "ALREADY MIXED CASE 123!"
string_result4: "already mixed case 123!"
string_result5: ""
string_result6: "no change needed"
]]
