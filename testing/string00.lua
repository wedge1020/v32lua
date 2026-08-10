--@ Vircon32 Lua String Library Test Suite - Part 00
--@ Tests string.char() and string.byte() basic functionality

-- Global helper to format test results
function format_result(label, value)
    return label .. ": " .. tostring(value)
end

-- --- TEST 1: string.char() Basic Functionality ---
function test_string_char()
    print(10, 10, "--- TEST 1: string.char() ---")

    -- Single byte
    local single = string.char(65)
    print(10, 30, format_result("char(65)", single))

    -- Multiple bytes
    local multi = string.char(72, 101, 108, 108, 111)  -- "Hello"
    print(10, 50, format_result("char(72,101,108,108,111)", multi))

    -- ASCII boundaries
    local null_char = string.char(0)
    print(10, 70, format_result("char(0) [null]", null_char))

    local max_ascii = string.char(127)
    print(10, 90, format_result("char(127) [DEL]", max_ascii))

    -- Common ASCII
    local space = string.char(32)
    print(10, 110, format_result("char(32) [space]", space))

    -- Empty call
    local empty = string.char()
    print(10, 130, format_result("char() [empty]", empty))

    -- Numeric values
    local nums = string.char(49, 50, 51)  -- "123"
    print(10, 150, format_result("char(49,50,51)", nums))

    return 0
end

-- --- TEST 2: string.byte() Basic Functionality ---
function test_string_byte()
    print(320, 10, "--- TEST 2: string.byte() ---")

    -- Single character positions
    local b_a = string.byte("ABC", 1)
    print(320, 30, format_result("byte('ABC', 1)", b_a))

    local b_b = string.byte("ABC", 2)
    print(320, 50, format_result("byte('ABC', 2)", b_b))

    local b_c = string.byte("ABC", 3)
    print(320, 70, format_result("byte('ABC', 3)", b_c))

    -- Default position
    local b_default = string.byte("X")
    print(320, 90, format_result("byte('X') [default]", b_default))

    -- Special characters
    local b_space = string.byte(" ")
    print(320, 110, format_result("byte(' ')", b_space))

    local b_zero = string.byte("0")
    print(320, 130, format_result("byte('0')", b_zero))

    -- Null character
    local b_null = string.byte(string.char(0))
    print(320, 150, format_result("byte(char(0))", b_null))

    return 0
end

-- --- TEST 3: string.byte() with Index Ranges ---
function test_string_byte_ranges()
    print(10, 190, "--- TEST 3: string.byte() Ranges ---")

    local test_str = "Hello World"

    -- Explicit range (single)
    local b1 = string.byte(test_str, 1, 1)
    print(10, 210, format_result("byte('Hello World', 1, 1)", b1))

    -- Range to 'W'
    local b2 = string.byte(test_str, 8, 8)
    print(10, 230, format_result("byte('Hello World', 8, 8)", b2))

    -- Range to 'o'
    local b3 = string.byte(test_str, 11, 11)
    print(10, 250, format_result("byte('Hello World', 11, 11)", b3))

    return 0
end

-- --- TEST 4: Round-trip Conversion ---
function test_roundtrip()
    print(320, 190, "--- TEST 4: Round-trip ---")

    -- Test char->byte consistency
    local test_values = {65, 66, 67, 97, 98, 99, 48, 49, 50}
    local success_count = 0
    local total_tests = 0

    for i, val in ipairs(test_values) do
        local ch = string.char(val)
        local byte_val = string.byte(ch, 1)
        if byte_val == val then
            success_count = success_count + 1
        end
        total_tests = total_tests + 1
    end

    print(320, 210, format_result("Round-trip passed", success_count .. "/" .. total_tests))

    -- Reconstruct string
    local original = "ABC"
    local reconstructed = ""
    for i = 1, #original do
        local b = string.byte(original, i)
        reconstructed = reconstructed .. string.char(b)
    end
    print(320, 230, format_result("Reconstruct 'ABC'", reconstructed))

    return 0
end

-- --- PROGRAM ENTRY POINT ---
function main()
    ioports.gpu.clear("black")

    test_string_char()
    test_string_byte()
    test_string_byte_ranges()
    test_roundtrip()

    print(10, 290, "--- PART 00 COMPLETE ---")
end
