--@ Vircon32 Lua String Library Test Suite - Part 01
--@ Tests string.char() and string.byte() edge cases and practical use

-- Global helper to format test results
function format_result(label, value)
    return label .. ": " .. tostring(value)
end

-- --- TEST 5: Edge Cases and Error Handling ---
function test_edge_cases()
    print(10, 10, "--- TEST 5: Edge Cases ---")

    -- Empty string
    local empty_byte = string.byte("")
    print(10, 30, format_result("byte('') [empty]", empty_byte))

    -- Out of bounds (positive)
    local out_of_bounds = string.byte("A", 100)
    print(10, 50, format_result("byte('A', 100) [OOB]", out_of_bounds))

    -- Out of bounds (negative)
    local neg_bounds = string.byte("A", -5)
    print(10, 70, format_result("byte('A', -5) [neg]", neg_bounds))

    -- Zero index
    local zero_idx = string.byte("ABC", 0)
	print(10, 90, format_result("byte('ABC', 0) [zero]", zero_idx))

    -- String with null bytes
    local with_null = string.char(65, 0, 66)
    local b1 = string.byte(with_null, 1)
    local b2 = string.byte(with_null, 2)
    local b3 = string.byte(with_null, 3)
    print(10, 110, format_result("byte(char(65,0,66), 1)", b1))
    print(10, 130, format_result("byte(char(65,0,66), 2)", b2))
    print(10, 150, format_result("byte(char(65,0,66), 3)", b3))

    return 0
end

-- --- TEST 6: String Length Verification ---
function test_string_length()
    print(320, 10, "--- TEST 6: Length Verification ---")

    -- Single char
    local s1 = string.char(65)
    local len1 = #s1
    print(320, 30, format_result("#char(65)", len1))

    -- Multiple chars
    local s2 = string.char(65, 66, 67, 68)
    local len2 = #s2
    print(320, 50, format_result("#char(65,66,67,68)", len2))

    -- Empty
    local s3 = string.char()
    local len3 = #s3
    print(320, 70, format_result("#char() [empty]", len3))

    -- Length of known strings
    local s4 = "Vircon32"
    local len4 = #s4
    print(320, 90, format_result("#'Vircon32'", len4))

    return 0
end

-- --- TEST 7: Practical Use Cases ---
function test_practical()
    print(10, 190, "--- TEST 7: Practical Examples ---")

    -- Build string from byte array
    local bytes = {72, 101, 108, 108, 111}  -- "Hello"
    local built = ""
    for i, b in ipairs(bytes) do
        built = built .. string.char(b)
    end
    print(10, 210, format_result("Built from bytes", built))

    -- Get ASCII values
    local text = "Lua"
    local first = string.byte(text, 1)
    local second = string.byte(text, 2)
    local third = string.byte(text, 3)
    print(10, 230, format_result("ASCII of 'Lua'", first .. "," .. second .. "," .. third))

    -- Simple encryption
    local secret = "ABC"
    local encoded = ""
    for i = 1, #secret do
        local original_byte = string.byte(secret, i)
        local encoded_byte = original_byte + 1
        encoded = encoded .. string.char(encoded_byte)
    end
    print(10, 250, format_result("Encoded 'ABC'", encoded))

    -- Decode back
    local decoded = ""
    for i = 1, #encoded do
        local encoded_byte = string.byte(encoded, i)
        local decoded_byte = encoded_byte - 1
        decoded = decoded .. string.char(decoded_byte)
    end
    print(10, 270, format_result("Decoded back", decoded))

    return 0
end

-- --- TEST 8: Combined Operations ---
function test_combined()
    print(320, 190, "--- TEST 8: Combined Ops ---")

    -- Chain char and byte
    local val = 65
    local ch = string.char(val)
    local back = string.byte(ch, 1)
    print(320, 210, format_result("65->char->byte", back))

    -- Build and inspect
    local s = string.char(84, 101, 115, 116)  -- "Test"
    local b1 = string.byte(s, 1)
    local b2 = string.byte(s, 2)
    local b3 = string.byte(s, 3)
    local b4 = string.byte(s, 4)
    print(320, 230, format_result("Bytes of 'Test'", b1 .. "," .. b2 .. "," .. b3 .. "," .. b4))

    -- Length and byte access
    local test = "12345"
    local len = #test
    local first_byte = string.byte(test, 1)
    local last_byte = string.byte(test, len)
    print(320, 250, format_result("First/Last of '12345'", first_byte .. "/" .. last_byte))

    return 0
end

-- --- PROGRAM ENTRY POINT ---
function main()
    ioports.gpu.clear("black")

    test_edge_cases()
    test_string_length()
    test_practical()
    test_combined()

    print(10, 290, "--- PART 01 COMPLETE ---")
end
