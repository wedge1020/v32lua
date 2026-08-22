--#title "[v32lua] string.byte() unit test"
--@ Vircon32 Lua string.byte() Unit Test
--@ Tests ONLY string.byte(). Split from string.char() into its own file
--@ so a failure in one can never be confused with, or hide, a failure in
--@ the other -- they exercise completely different runtime routines
--@ (__builtin_string_byte vs __builtin_string_char).
--@ A __debugN label follows every individual test so v32sim can identify
--@ exactly which sub-test a hang/crash/wrong-value happens at.

function test_string_byte()
    number_result1 = string.byte("A")  -- Expected: 65
    __rawasm__("__debug1:")

    number_result2 = string.byte("a")  -- Expected: 97
    __rawasm__("__debug2:")

    number_result3 = string.byte("0")  -- Expected: 48
    __rawasm__("__debug3:")

    number_result4 = string.byte("Hello", 1)  -- Expected: 72 ('H')
    __rawasm__("__debug4:")

    number_result5 = string.byte("Hello", 2)  -- Expected: 101 ('e')
    __rawasm__("__debug5:")

    number_result6 = string.byte("Hello", 5)  -- Expected: 111 ('o')
    __rawasm__("__debug6:")

    number_result7 = string.byte("Hi", 10)  -- Expected: nil (out of bounds)
    __rawasm__("__debug7:")

    number_result8 = string.byte("Hello", 1, 1)  -- Expected: 72 (3-arg form, single char)
    __rawasm__("__debug8:")
end

function main()
    ioports.gpu.clear("black")
    test_string_byte()

    print(100, 00,  "--- string.byte Test ---")
    print(100, 20,  "byte('A'): " .. number_result1)
    print(100, 40,  "byte('a'): " .. number_result2)
    print(100, 60,  "byte('0'): " .. number_result3)
    print(100, 80,  "byte('Hello',1): " .. number_result4)
    print(100, 100, "byte('Hello',2): " .. number_result5)
    print(100, 120, "byte('Hello',5): " .. number_result6)
    print(100, 140, "byte OOB: " .. (number_result7 or "nil"))
    print(100, 160, "byte('Hello',1,1): " .. number_result8)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 65.0000
number_result2: 97.0000
number_result3: 48.0000
number_result4: 72.0000
number_result5: 101.0000
number_result6: 111.0000
number_result7: nan
number_result8: 72.0000
]]
