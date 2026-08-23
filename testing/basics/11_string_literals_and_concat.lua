--#title "v32lua string literals and concatenation unit test"
--@ Vircon32 Lua String Literals and Concatenation Unit Test
--@ Tests string escape sequences, the concatenation operator's
--@ right-associativity and precedence against arithmetic/comparison,
--@ and deeper (4+ link) concat chains. NOTE: chained concatenation
--@ is flagged in project notes as producing intermediate heap-allocated
--@ buffers -- a known structural issue, not yet fixed. This file gives
--@ that gap a concrete, isolated regression test.
--@ Results are stored in global variables for automated memory scraping.

function test_string_literals_and_concat()
    -- === Test 00: Newline escape ===
    string_result00 = "line1\nline2"

    -- === Test 01: Tab escape ===
    string_result01 = "a\tb"

    -- === Test 02: Carriage return escape ===
    string_result02 = "x\ry"

    -- === Test 03: Backslash escape ===
    string_result03 = "back\\slash"

    -- === Test 04: Escaped double-quote inside a string ===
    string_result04 = "she said \"hi\""

    -- === Test 05: Multiple escapes combined ===
    string_result05 = "a\tb\nc\\d"

    -- === Test 06: Concatenation is right-associative ===
    -- "a" .. "b" .. "c" parses as "a" .. ("b" .. "c") -- observable only
    -- if concat is non-trivial, but the result should be identical either
    -- way for plain strings, so this mainly guards against a parse error.
    string_result06 = "a" .. "b" .. "c"

    -- === Test 07: Concat binds LOOSER than arithmetic ===
    -- "Sum: " .. 1 + 2  must parse as "Sum: " .. (1 + 2), giving "Sum: 3",
    -- not ("Sum: " .. 1) + 2 which would be a type error.
    string_result07 = "Sum- " .. 1 + 2

    -- === Test 08: Concat binds LOOSER than multiplication ===
    string_result08 = "Product- " .. 2 * 3

    -- === Test 09: Concat with a parenthesized arithmetic expression ===
    string_result09 = "Result- " .. (10 - 4)

    -- === Test 10: Concat binds TIGHTER than relational operators ===
    -- ("a" .. "b") == "ab" must parse as ("a"..".b") == "ab", not
    -- "a" .. ("b" == "ab") which would be a type error against a boolean.
    boolean_result10 = "a" .. "b" == "ab"   -- Expected: true

    -- === Test 11: Four-link concat chain ===
    string_result11 = "one" .. "two" .. "three" .. "four"

    -- === Test 12: Six-link concat chain, mixing strings and numbers ===
    string_result12 = "a" .. 1 .. "b" .. 2 .. "c" .. 3

    -- === Test 13: Concat chain built incrementally across statements ===
    -- Exercises repeated re-concatenation of the SAME variable, the
    -- pattern most likely to accumulate intermediate heap buffers.
    local acc = "start"
    acc = acc .. "-1"
    acc = acc .. "-2"
    acc = acc .. "-3"
    acc = acc .. "-4"
    string_result13 = acc

    -- === Test 14: Concat chain inside a loop (stress case) ===
    local looped = ""
    for i = 1, 5 do
        looped = looped .. tostring(i)
    end
    string_result14 = looped         -- Expected: "12345"

    -- === Test 15: Concat with a negative number ===
    string_result15 = "value- " .. -5

    -- === Test 16: Concat with a float ===
    string_result16 = "pi-ish- " .. 3.5
end

function main()
    ioports.gpu.clear("black")
    test_string_literals_and_concat()

    print(000, 000, "--- String Literals & Concat Test ---")
    print(000, 020, "Test 00 - Newline: " ..       string_result00)
    print(000, 040, "Test 01 - Tab: " ..           string_result01)
    print(000, 060, "Test 02 - CR: " ..            string_result02)
    print(000, 080, "Test 03 - Backslash: " ..     string_result03)
    print(000, 100, "Test 04 - Quote: " ..         string_result04)
    print(000, 120, "Test 05 - Combined: " ..      string_result05)
    print(000, 140, "Test 06 - Right assoc: " ..   string_result06)
    print(000, 160, "Test 07 - Concat<add: " ..    string_result07)
    print(000, 180, "Test 08 - Concat<mul: " ..    string_result08)
    print(000, 200, "Test 09 - Concat+parens: " .. string_result09)
    print(000, 220, "Test 10 - Concat<rel: " ..    tostring(boolean_result10))
    print(000, 240, "Test 11 - 4-chain: " ..       string_result11)
    print(000, 260, "Test 12 - 6-chain mixed: " .. string_result12)
    print(200, 020, "Test 13 - Incremental: " ..   string_result13)
    print(200, 040, "Test 14 - Loop concat: " ..   string_result14)
    print(200, 060, "Test 15 - Neg number: " ..    string_result15)
    print(200, 080, "Test 16 - Float: " ..         string_result16)
end

--[[
=== EXPECTED OUTPUT ===

string_result00: "line1\x0Aline2"
string_result01: "a\x09b"
string_result02: "x\x0Dy"
string_result03: "back\slash"
string_result04: "she said "hi""
string_result05: "a\x09b\x0Ac\d"
string_result06: "abc"
string_result07: "Sum- 3"
string_result08: "Product- 6"
string_result09: "Result- 6"
boolean_result10: true
string_result11: "onetwothreefour"
string_result12: "a1b2c3"
string_result13: "start-1-2-3-4"
string_result14: "12345"
string_result15: "value- -5"
string_result16: "pi-ish- 3.500000"

--]]
