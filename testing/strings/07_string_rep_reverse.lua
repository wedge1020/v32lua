--#title "[v32lua] string.rep() / string.reverse() unit test"
--@ Vircon32 Lua string.rep() / string.reverse() Unit Test
--@ Exercises the new string.rep/string.reverse implementation added in
--@ this patch (runtime: __builtin_string_rep / __builtin_string_reverse).
--@ Hand-traced, not yet run through v32sim. string.rep(s,0) and
--@ string.rep("",n) are included deliberately as degenerate-length edge
--@ cases -- a bump-allocator runtime with no bounds checking is exactly
--@ where those tend to bite.

function test_string_rep_reverse()
    string_result1 = string.rep("ab", 3)     -- Expected: "ababab"
    __rawasm__("__debug1:")

    string_result2 = string.rep("X", 1)      -- Expected: "X"
    __rawasm__("__debug2:")

    string_result3 = string.rep("ab", 0)     -- Expected: ""
    __rawasm__("__debug3:")

    string_result4 = string.rep("", 5)       -- Expected: ""
    __rawasm__("__debug4:")

    string_result5 = string.reverse("Hello") -- Expected: "olleH"
    __rawasm__("__debug5:")

    string_result6 = string.reverse("")      -- Expected: ""
    __rawasm__("__debug6:")

    string_result7 = string.reverse("A")     -- Expected: "A"
    __rawasm__("__debug7:")
end

function main()
    ioports.gpu.clear("black")
    test_string_rep_reverse()

    print(100, 00,  "--- string.rep/reverse Test ---")
    print(100, 20,  "rep('ab',3): " .. string_result1)
    print(100, 40,  "rep('X',1): " .. string_result2)
    print(100, 60,  "rep('ab',0): '" .. string_result3 .. "'")
    print(100, 80,  "rep('',5): '" .. string_result4 .. "'")
    print(100, 100, "reverse('Hello'): " .. string_result5)
    print(100, 120, "reverse(''): '" .. string_result6 .. "'")
    print(100, 140, "reverse('A'): " .. string_result7)
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "ababab"
string_result2: "X"
string_result3: ""
string_result4: ""
string_result5: "olleH"
string_result6: ""
string_result7: "A"
]]
