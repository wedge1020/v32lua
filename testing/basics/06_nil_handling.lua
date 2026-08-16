--#title "v32lua nil handling unit test"
--@ Vircon32 Lua Nil Handling Unit Test
--@ Tests nil values, type checking, and nil behavior in operations.
--@ Results are stored in global variables for automated memory scraping.

function test_nil_handling()
    -- === Test 00: Nil value assignment ===
    local n = nil
    string_result00 = type(n)

    -- === Test 01: Nil comparison - nil == nil ===
    boolean_result01 = (nil == nil)

    -- === Test 02: Nil comparison - nil ~= nil ===
    boolean_result02 = (nil ~= nil)

    -- === Test 03: Nil comparison with number ===
    boolean_result03 = (nil == 0)

    -- === Test 04: Nil comparison with string ===
    boolean_result04 = (nil == "")

    -- === Test 05: Nil comparison with boolean ===
    boolean_result05 = (nil == false)

    -- === Test 06: Nil in logical AND - nil and true ===
    local result = nil and true
    boolean_result06 = (result == nil)

    -- === Test 07: Nil in logical AND - true and nil ===
    local result2 = true and nil
    boolean_result07 = (result2 == nil)

    -- === Test 08: Nil in logical OR - nil or true ===
    local result3 = nil or true
    boolean_result08 = (result3 == true)

    -- === Test 09: Nil in logical OR - true or nil ===
    local result4 = true or nil
    boolean_result09 = (result4 == true)

    -- === Test 10: Nil in logical NOT ===
    boolean_result10 = (not nil)

    -- === Test 11: Nil in conditional - if nil ===
    if nil then
        number_result11 = 1
    else
        number_result11 = 0
    end

    -- === Test 12: Nil in conditional - if not nil ===
    if not nil then
        number_result12 = 1
    else
        number_result12 = 0
    end

    -- === Test 13: Nil type check ===
    string_result13 = type(nil)

    -- === Test 14: Nil tostring ===
    string_result14 = tostring(nil)

    -- === Test 15: Nil in arithmetic - addition ===
    local arithmetic_result = nil + 5
    string_result15 = type(arithmetic_result)

    -- === Test 16: Nil in arithmetic - multiplication ===
    local arithmetic_result2 = nil * 10
    string_result16 = type(arithmetic_result2)

    -- === Test 17: Nil in string concatenation ===
    local concat_result = nil .. "hello"
    string_result17 = tostring(concat_result)

    -- === Test 18: Nil in comparison - nil < 5 ===
    boolean_result18 = (nil < 5)

    -- === Test 19: Nil in comparison - nil > 5 ===
    boolean_result19 = (nil > 5)

    -- === Test 20: Nil in comparison - nil <= 5 ===
    boolean_result20 = (nil <= 5)

    -- === Test 21: Nil in comparison - nil >= 5 ===
    boolean_result21 = (nil >= 5)

    -- === Test 22: Nil in function parameter ===
    local function check_nil(x)
        return x == nil
    end
    boolean_result22 = check_nil(nil)

    -- === Test 23: Nil in function return ===
    local function return_nil()
        return nil
    end
    local ret = return_nil()
    boolean_result23 = (ret == nil)

    -- === Test 24: Nil in table access (simulated via function) ===
    local function get_nil_from_table()
        return nil
    end
    boolean_result24 = (get_nil_from_table() == nil)

    -- === Test 25: Nil in multiple assignment ===
    local a, b, c = nil, 10, nil
    boolean_result25 = (a == nil and c == nil)
    number_result25 = b or 0

    -- === Test 26: Nil in or chain ===
    local result5 = nil or nil or 42
    number_result26 = result5 or 0

    -- === Test 27: Nil in and chain ===
    local result6 = true and nil and false
    boolean_result27 = (result6 == nil)
end

function main()
    ioports.gpu.clear("black")
    test_nil_handling()

    print(000, 00,  "--- Nil Handling Test ---")
    print(000, 020, "Test 00 - Type nil: " ..         string_result00)
    print(000, 040, "Test 01 - nil == nil: " ..      tostring(boolean_result01))
    print(000, 060, "Test 02 - nil ~= nil: " ..      tostring(boolean_result02))
    print(000, 080, "Test 03 - nil == 0: " ..        tostring(boolean_result03))
    print(000, 100, "Test 04 - nil == empty str: " .. tostring(boolean_result04))
    print(000, 120, "Test 05 - nil == false: " ..    tostring(boolean_result05))
    print(000, 140, "Test 06 - nil AND true: " ..     tostring(boolean_result06))
    print(000, 160, "Test 07 - true AND nil: " ..    tostring(boolean_result07))
    print(000, 180, "Test 08 - nil OR true: " ..      tostring(boolean_result08))
    print(000, 200, "Test 09 - true OR nil: " ..      tostring(boolean_result09))
    print(000, 220, "Test 10 - NOT nil: " ..          tostring(boolean_result10))
    print(000, 240, "Test 11 - If nil: " ..           number_result11)
    print(000, 260, "Test 12 - If not nil: " ..       number_result12)
    print(200, 020, "Test 13 - Type of nil: " ..      string_result13)
    print(200, 040, "Test 14 - tostring nil: " ..     string_result14)
    print(200, 060, "Test 15 - nil + 5 type: " ..     string_result15)
    print(200, 080, "Test 16 - nil * 10 type: " ..    string_result16)
    print(200, 100, "Test 17 - nil .. str: " ..      string_result17)
    print(200, 120, "Test 18 - nil < 5: " ..          tostring(boolean_result18))
    print(200, 140, "Test 19 - nil > 5: " ..          tostring(boolean_result19))
    print(200, 160, "Test 20 - nil <= 5: " ..         tostring(boolean_result20))
    print(200, 180, "Test 21 - nil >= 5: " ..         tostring(boolean_result21))
    print(200, 200, "Test 22 - Param nil: " ..        tostring(boolean_result22))
    print(200, 220, "Test 23 - Return nil: " ..      tostring(boolean_result23))
    print(200, 240, "Test 24 - Table nil: " ..        tostring(boolean_result24))
    print(200, 260, "Test 25 - Multi assign: " ..     tostring(boolean_result25) .. " " .. number_result25)
    print(200, 280, "Test 26 - OR chain: " ..         number_result26)
    print(200, 300, "Test 27 - AND chain: " ..        tostring(boolean_result27))
end

--[[
=== EXPECTED OUTPUT ===

string_result00: "nil"
boolean_result01: true
boolean_result02: false
boolean_result03: false
boolean_result04: false
boolean_result05: false
boolean_result06: true
boolean_result07: true
boolean_result08: true
boolean_result09: true
boolean_result10: true
number_result11: 0.0000
number_result12: 1.0000
string_result13: "nil"
string_result14: "nil"
string_result15: "nil"
string_result16: "nil"
string_result17: "nilhello"
boolean_result18: false
boolean_result19: false
boolean_result20: false
boolean_result21: false
boolean_result22: true
boolean_result23: true
boolean_result24: true
boolean_result25: true
number_result25: 10.0000
number_result26: 42.0000
boolean_result27: true

--]]
