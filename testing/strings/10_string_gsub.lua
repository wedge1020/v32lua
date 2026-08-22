--#title "[v32lua] string.gsub() unit test"
--@ Vircon32 Lua string.gsub() Unit Test
--@ Exercises the new string.gsub(s, pattern, repl) implementation added
--@ in this patch. PLAIN SUBSTITUTION ONLY -- same limitation as
--@ string.find (13_string_find.lua): pattern is always a literal
--@ substring, never a Lua pattern. No n-limit argument, and only the
--@ resulting string is returned (real Lua's gsub also returns a
--@ substitution count as a second value).
--@
--@ __builtin_string_gsub is the most register-heavy, highest-risk routine
--@ in this whole patch (uses all 14 general-purpose registers across a
--@ two-pass count-then-copy algorithm) -- see the header comment in
--@ patch_runtime_s_string_routines.txt. If anything in this patch needs
--@ v32sim attention first, it's this file.

function test_string_gsub()
    string_result1 = string.gsub("Hello World", "World", "Lua")  -- Expected: "Hello Lua"
    __rawasm__("__debug1:")

    string_result2 = string.gsub("aaa", "a", "b")                -- Expected: "bbb" (all occurrences)
    __rawasm__("__debug2:")

    string_result3 = string.gsub("Hello", "xyz", "abc")          -- Expected: "Hello" (no match -> unchanged)
    __rawasm__("__debug3:")

    string_result4 = string.gsub("", "a", "b")                   -- Expected: "" (empty input)
    __rawasm__("__debug4:")

    string_result5 = string.gsub("Hello World", "o", "0")        -- Expected: "Hell0 W0rld" (repl shorter than pattern... same length here, exercises equal-length substitution)
    __rawasm__("__debug5:")

    string_result6 = string.gsub("aaa", "aa", "b")               -- Expected: "ba" (non-overlapping: matches "aa" once at position 1, leaves trailing "a")
    __rawasm__("__debug6:")

    string_result7 = string.gsub("Hi", "Hi", "Hello there")      -- Expected: "Hello there" (repl LONGER than pattern -- exercises growing buffer size math)
    __rawasm__("__debug7:")
end

function main()
    ioports.gpu.clear("black")
    test_string_gsub()

    print(100, 00,  "--- string.gsub Test (plain substrings only) ---")
    print(100, 20,  "gsub(World->Lua): " .. string_result1)
    print(100, 40,  "gsub(a->b, all): " .. string_result2)
    print(100, 60,  "gsub(no match): " .. string_result3)
    print(100, 80,  "gsub(empty): '" .. string_result4 .. "'")
    print(100, 100, "gsub(o->0): " .. string_result5)
    print(100, 120, "gsub(aa->b): " .. string_result6)
    print(100, 140, "gsub(grow): " .. string_result7)
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "Hello Lua"
string_result2: "bbb"
string_result3: "Hello"
string_result4: ""
string_result5: "Hell0 W0rld"
string_result6: "ba"
string_result7: "Hello there"
]]
