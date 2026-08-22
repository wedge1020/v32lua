--#title "[v32lua] string.len() unit test"
--@ Vircon32 Lua string.len() Unit Test
--@ Tests string.len() AND the # operator, split so a failure in one
--@ doesn't hide the status of the other.
--@

function test_hash_operator()
    __rawasm__("__debug_hash_1:")
    -- === Control group: # operator (known-working dispatch path) ===
    number_result1 = #""              -- Expected: 0
    number_result2 = #"X"             -- Expected: 1
    number_result3 = #"Hello"         -- Expected: 5
    number_result4 = #"Hello World"   -- Expected: 11
    number_result5 = #"ABC123!@#"     -- Expected: 9

    __rawasm__("__debug_hash_2:")
    local s = "Part1" .. "Part2"
    number_result6 = #s               -- Expected: 10

    __rawasm__("__debug_hash_3:")
    local cs = string.char(65, 66, 67)
    number_result7 = #cs              -- Expected: 3

    __rawasm__("__debug_hash_done:")
end

function test_string_len_direct()
    __rawasm__("__debug_len_1:")
    -- === string.len() -- the actually-broken dispatch path ===
    number_result8  = string.len("")            -- Expected: 0
    __rawasm__("__debug_len_2:")
    number_result9  = string.len("X")           -- Expected: 1
    __rawasm__("__debug_len_3:")
    number_result10 = string.len("Hello")       -- Expected: 5
    __rawasm__("__debug_len_4:")
    number_result11 = string.len("Hello World") -- Expected: 11
    __rawasm__("__debug_len_done:")
end

function main()
    ioports.gpu.clear("black")

    -- Run the control group first and print immediately, so its results
    -- are on screen/in memory even if the direct-dispatch group below
    -- traps or hangs.
    test_hash_operator()

    print(100, 00,  "--- # operator (control) ---")
    print(100, 20,  "#'': " .. number_result1)
    print(100, 40,  "#'X': " .. number_result2)
    print(100, 60,  "#'Hello': " .. number_result3)
    print(100, 80,  "#'Hello World': " .. number_result4)
    print(100, 100, "#'ABC123!@#': " .. number_result5)
    print(100, 120, "#concat: " .. number_result6)
    print(100, 140, "#char: " .. number_result7)

    test_string_len_direct()

    print(100, 170, "--- string.len() (known broken) ---")
    print(100, 190, "len(''): " .. number_result8)
    print(100, 210, "len('X'): " .. number_result9)
    print(100, 230, "len('Hello'): " .. number_result10)
    print(100, 250, "len('Hello World'): " .. number_result11)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 0.0000
number_result2: 1.0000
number_result3: 5.0000
number_result4: 11.0000
number_result5: 9.0000
number_result6: 10.0000
number_result7: 3.0000
number_result8: 0.0000
number_result9: 1.0000
number_result10: 5.0000
number_result11: 11.0000
]]
