--@ Vircon32 Lua Conditional Idioms Unit Test
--@ Tests the patterns Lua programmers actually use in place of a
--@ ternary operator or switch/case statement (neither exists in Lua):
--@ the 'cond and a or b' idiom, dispatch tables, elseif-as-switch, and
--@ guard clauses.
--@ Results are stored in global variables for automated memory scraping.

function test_conditional_idioms()
    -- === Test 00: Ternary idiom -- true branch ===
    local age = 25
    string_result00 = (age >= 18) and "adult" or "minor"
    __rawasm__("__debug0:")

    -- === Test 01: Ternary idiom -- false branch ===
    local age2 = 10
    string_result01 = (age2 >= 18) and "adult" or "minor"
    __rawasm__("__debug1:")

    -- === Test 02: Nested ternary idiom ===
    local score = 75
    string_result02 = (score >= 90) and "A"
        or (score >= 80) and "B"
        or (score >= 70) and "C"
        or "F"
    __rawasm__("__debug2:")

    -- === Test 03: Dispatch-table "switch" simulation -- a table of ===
    -- === functions keyed by value, invoked instead of an if/elseif ===
    -- === ladder ===
    local dispatch = {
        [1] = function() return "one" end,
        [2] = function() return "two" end,
        [3] = function() return "three" end,
    }
    string_result03 = dispatch[2]()
    __rawasm__("__debug3:")

    -- === Test 04: Dispatch table with a fallback for an unmapped key ===
    local key = 99
    local handler = dispatch[key]
    if handler then
        string_result04 = handler()
    else
        string_result04 = "unknown"
    end
    __rawasm__("__debug4:")

    -- === Test 05: Elseif ladder used to simulate switch/case over ===
    -- === several discrete values ===
    local day = 3
    if day == 1 then
        string_result05 = "Monday"
    elseif day == 2 then
        string_result05 = "Tuesday"
    elseif day == 3 then
        string_result05 = "Wednesday"
    elseif day == 4 then
        string_result05 = "Thursday"
    else
        string_result05 = "Other"
    end
    __rawasm__("__debug5:")

    -- === Test 06: Guard-clause pattern -- early return avoids ===
    -- === nested else chains ===
    local function classify(n)
        if n < 0 then
            return "negative"
        end
        if n == 0 then
            return "zero"
        end
        return "positive"
    end
    string_result06a = classify(-5)
    string_result06b = classify(0)
    string_result06c = classify(5)
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_conditional_idioms()

    print(000, 00,  "--- Conditional Idioms Test ---")
    print(000, 020, "Test 00 - Ternary adult: " ..   string_result00)
    print(000, 040, "Test 01 - Ternary minor: " ..   string_result01)
    print(000, 060, "Test 02 - Nested ternary: " ..  string_result02)
    print(000, 080, "Test 03 - Dispatch table: " ..  string_result03)
    print(000, 100, "Test 04 - Dispatch fallback: " .. string_result04)
    print(000, 120, "Test 05 - Elseif switch: " ..   string_result05)
    print(000, 140, "Test 06 - Guard negative: " ..  string_result06a)
    print(000, 160, "Test 06 - Guard zero: " ..      string_result06b)
    print(000, 180, "Test 06 - Guard positive: " ..  string_result06c)
end

--[[
=== EXPECTED OUTPUT ===
string_result00: "adult"
string_result01: "minor"
string_result02: "C"
string_result03: "two"
string_result04: "unknown"
string_result05: "Wednesday"
string_result06a: "negative"
string_result06b: "zero"
string_result06c: "positive"
--]]
