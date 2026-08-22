--#title "[v32lua] string.find() unit test"
--@ Vircon32 Lua string.find() Unit Test
--@ Exercises the new string.find(s, pattern) implementation added in this
--@ patch. PLAIN SUBSTRING SEARCH ONLY -- no Lua pattern magic characters
--@ are interpreted, no init/plain-flag arguments, and only the start
--@ index is returned (real Lua's find() returns two values). Hand-traced,
--@ not yet run through v32sim.

function test_string_find()
    number_result1 = string.find("Hello World", "World")  -- Expected: 7 (start index)
    __rawasm__("__debug1:")

    number_result2 = string.find("Hello World", "Hello")  -- Expected: 1
    __rawasm__("__debug2:")

    number_result3 = string.find("Hello World", "xyz")    -- Expected: nil
    __rawasm__("__debug3:")

    number_result4 = string.find("aaa", "a")               -- Expected: 1 (first match)
    __rawasm__("__debug4:")

    number_result5 = string.find("Hello", "")               -- Expected: 1 (empty needle)
    __rawasm__("__debug5:")

    number_result6 = string.find("Hello", "Hello")          -- Expected: 1 (exact full match)
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_string_find()

    print(100, 00,  "--- string.find Test (plain substrings only) ---")
    print(100, 20,  "find('World'): " .. (number_result1 or "nil"))
    print(100, 40,  "find('Hello'): " .. (number_result2 or "nil"))
    print(100, 60,  "find('xyz'): " .. (number_result3 or "nil"))
    print(100, 80,  "find('a') in 'aaa': " .. (number_result4 or "nil"))
    print(100, 100, "find(''): " .. (number_result5 or "nil"))
    print(100, 120, "find(exact): " .. (number_result6 or "nil"))
end

--[[
=== EXPECTED OUTPUT (plain-substring semantics) ===
number_result1: 7.0000
number_result2: 1.0000
number_result3: nan
number_result4: 1.0000
number_result5: 1.0000
number_result6: 1.0000
]]
