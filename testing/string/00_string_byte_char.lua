--@ Vircon32 Lua string.byte() & string.char() Unit Test
--@ Tests ONLY string.byte and string.char functions.
--@ Results stored in global variables for automated memory scraping.

function test_string_byte_char()
    -- === Test 1: string.byte() - single character ===
    number_result1 = string.byte("A")  -- Expected: 65
    number_result2 = string.byte("a")  -- Expected: 97
    number_result3 = string.byte("0")  -- Expected: 48

    -- === Test 2: string.byte() - with position ===
    number_result4 = string.byte("Hello", 1)  -- Expected: 72 ('H')
    number_result5 = string.byte("Hello", 2)  -- Expected: 101 ('e')
    number_result6 = string.byte("Hello", 5)  -- Expected: 111 ('o')

    -- === Test 3: string.byte() - out of bounds ===
    number_result7 = string.byte("Hi", 10)  -- Expected: nil

    -- === Test 4: string.char() - single byte ===
    string_result1 = string.char(65)  -- Expected: "A"
    string_result2 = string.char(97)  -- Expected: "a"
    string_result3 = string.char(48)  -- Expected: "0"

    -- === Test 5: string.char() - multiple bytes ===
    string_result4 = string.char(72, 101, 108, 108, 111)  -- Expected: "Hello"

    -- === Test 6: string.char() + string.byte() roundtrip ===
    local test_str = "Test123"
    local b1 = string.byte(test_str, 1)
    local b2 = string.byte(test_str, 2)
    local b3 = string.byte(test_str, 3)
    string_result5 = string.char(b1, b2, b3)  -- Expected: "Tes"
end

function main()
    ioports.gpu.clear("black")
    test_string_byte_char()

    print(100, 00,  "--- string.byte/char Test ---")
    print(100, 20,  "byte('A'): " .. number_result1)
    print(100, 40,  "byte('a'): " .. number_result2)
    print(100, 60,  "byte('0'): " .. number_result3)
    print(100, 80,  "byte('Hello',1): " .. number_result4)
    print(100, 100, "byte('Hello',2): " .. number_result5)
    print(100, 120, "byte('Hello',5): " .. number_result6)
    print(100, 140, "byte OOB: " .. (number_result7 or "nil"))
    print(100, 160, "char(65): " .. string_result1)
    print(100, 180, "char(97): " .. string_result2)
    print(100, 200, "char(48): " .. string_result3)
    print(100, 220, "char multi: " .. string_result4)
    print(100, 240, "roundtrip: " .. string_result5)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
number_result1: 65
number_result2: 97
number_result3: 48
number_result4: 72
number_result5: 101
number_result6: 111
number_result7: nil
string_result1: "A"
string_result2: "a"
string_result3: "0"
string_result4: "Hello"
string_result5: "Tes"
]]
