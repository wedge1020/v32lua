--#title "[v32lua] string.char() unit test"
--@ Vircon32 Lua string.char() Unit Test
--@ Tests ONLY string.char(). Split from string.byte() -- see the header
--@ comment in 00_string_byte.lua for why.
--@ A __debugN label follows every individual test.

function test_string_char()
    __rawasm__("__debug0:")
    string_result1 = string.char(65)  -- Expected: "A"
    __rawasm__("__debug1:")

    string_result2 = string.char(97)  -- Expected: "a"
    __rawasm__("__debug2:")

    string_result3 = string.char(48)  -- Expected: "0"
    __rawasm__("__debug3:")

    string_result4 = string.char(72, 101, 108, 108, 111)  -- Expected: "Hello"
    __rawasm__("__debug4:")

    -- Roundtrip through string.byte() to exercise both directions
    -- together, without this file depending on 00_string_byte.lua's
    -- results (string.byte is still needed here as a source of bytes).
    local test_str = "Test123"
    local b1 = string.byte(test_str, 1)
    local b2 = string.byte(test_str, 2)
    local b3 = string.byte(test_str, 3)
    string_result5 = string.char(b1, b2, b3)  -- Expected: "Tes"
    __rawasm__("__debug5:")

    string_result6 = string.char()  -- Expected: "" (degenerate: zero arguments)
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_string_char()

    print(100, 00,  "--- string.char Test ---")
    print(100, 20,  "char(65): " .. string_result1)
    print(100, 40,  "char(97): " .. string_result2)
    print(100, 60,  "char(48): " .. string_result3)
    print(100, 80,  "char multi: " .. string_result4)
    print(100, 100, "roundtrip: " .. string_result5)
    print(100, 120, "char(): '" .. string_result6 .. "'")
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "A"
string_result2: "a"
string_result3: "0"
string_result4: "Hello"
string_result5: "Tes"
string_result6: ""
]]
