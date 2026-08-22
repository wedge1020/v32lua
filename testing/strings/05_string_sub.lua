--#title "[v32lua] string.sub() unit test"
--@ Vircon32 Lua string.sub() Unit Test
--@ Exercises the new string.sub(s, i [, j]) implementation added in this
--@ patch (compiler dispatch: emit_string_sub_intrinsic; runtime:
--@ __builtin_string_sub in patch_runtime_s_string_routines.txt). This has
--@ been hand-traced against every case below but NOT run through v32sim --
--@ see the header comment in that patch file before trusting it blindly.
--@ Semantics match real Lua 5.1: i, j are 1-based; negative indices count
--@ from the end (-1 = last char); j defaults to the end of the string;
--@ out-of-range indices are clamped, not errors.

function test_string_sub()
    string_result1 = string.sub("Hello World", 1, 5)    -- Expected: "Hello"
    __rawasm__("__debug1:")

    string_result2 = string.sub("Hello World", 7)       -- Expected: "World"
    __rawasm__("__debug2:")

    string_result3 = string.sub("Hello World", -5)      -- Expected: "World"
    __rawasm__("__debug3:")

    string_result4 = string.sub("Hello World", 1, -7)   -- Expected: "Hello"
    __rawasm__("__debug4:")

    string_result5 = string.sub("Hello", 1, 100)        -- Expected: "Hello" (clamped)
    __rawasm__("__debug5:")

    string_result6 = string.sub("Hello", 10, 20)        -- Expected: "" (out of range)
    __rawasm__("__debug6:")

    string_result7 = string.sub("", 1)                  -- Expected: "" (empty source)
    __rawasm__("__debug7:")

    string_result8 = string.sub("Hello", 1, 1)          -- Expected: "H" (single char)
    __rawasm__("__debug8:")
end

function main()
    ioports.gpu.clear("black")
    test_string_sub()

    print(100, 00,  "--- string.sub Test ---")
    print(100, 20,  "sub(1,5): " .. string_result1)
    print(100, 40,  "sub(7): " .. string_result2)
    print(100, 60,  "sub(-5): " .. string_result3)
    print(100, 80,  "sub(1,-7): " .. string_result4)
    print(100, 100, "sub(1,100): " .. string_result5)
    print(100, 120, "sub(10,20): '" .. string_result6 .. "'")
    print(100, 140, "sub('',1): '" .. string_result7 .. "'")
    print(100, 160, "sub(1,1): " .. string_result8)
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "Hello"
string_result2: "World"
string_result3: "World"
string_result4: "Hello"
string_result5: "Hello"
string_result6: ""
string_result7: ""
string_result8: "H"
]]
