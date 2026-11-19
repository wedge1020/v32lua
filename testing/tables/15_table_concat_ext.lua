--@ Vircon32 Lua table.concat() -- extended unit test
--@ table.concat() now measures the result, allocates it once and copies
--@ (it used to strcat one element at a time: quadratic time and memory).
--@ Results stored in global variables for automated memory scraping.

function test_table_concat_ext()
    local t = {"a", "b", "c"}

    -- === Test 1: multi-character separator ===
    string_result1 = table.concat(t, "->")          -- Expected: "a->b->c"

    -- === Test 2: separator with a start index ===
    string_result2 = table.concat(t, ", ", 2)       -- Expected: "b, c"

    -- === Test 3: both bounds ===
    string_result3 = table.concat(t, "-", 2, 3)     -- Expected: "b-c"

    -- === Test 4: empty range (i > j) ===
    string_result4 = table.concat(t, "-", 3, 2)     -- Expected: ""

    -- === Test 5: a single element gets no separator ===
    string_result5 = table.concat({"z"}, "--")      -- Expected: "z"

    -- === Test 6: numbers as elements and as the separator ===
    string_result6 = table.concat({1, 2, 3}, "+")   -- Expected: "1+2+3"
    string_result7 = table.concat({"a", "b"}, 1)    -- Expected: "a1b"
    string_result8 = table.concat({"x", 2.5, "y"})  -- Expected: "x2.5y"

    -- === Test 7: elements built at run time (RAM strings) ===
    local u = {"a" .. "b", "c" .. "d", "e"}
    string_result9 = table.concat(u, "|")           -- Expected: "ab|cd|e"

    -- === Test 8: a long result: 300 one-character elements ===
    local many = {}
    for i = 1, 300 do many[i] = "x" end
    local s = table.concat(many)
    number_result1 = #s                             -- Expected: 300
    string_result10 = string.sub(s, 299, 300)       -- Expected: "xx"

    -- === Test 9: the result is an ordinary string afterwards ===
    local r = table.concat({"p", "q"}, "") .. "!"
    string_result11 = r                             -- Expected: "pq!"
    number_result2 = #table.concat({"ab", "cd"}, "--") -- Expected: 6

    -- === Test 10: two calls in a row do not share a buffer ===
    local first = table.concat({1, 2})
    local second = table.concat({3, 4})
    string_result12 = first .. second               -- Expected: "1234"
end

function main()
    ioports.gpu.clear("black")
    test_table_concat_ext()

    print(100, 0,   "--- table.concat() extended ---")
    print(100, 20,  "1: " .. string_result1)
    print(100, 40,  "2: " .. string_result2)
    print(100, 60,  "3: " .. string_result3)
    print(100, 80,  "4: '" .. string_result4 .. "'")
    print(100, 100, "5: " .. string_result5)
    print(100, 120, "6: " .. string_result6)
    print(100, 140, "7: " .. string_result7)
    print(100, 160, "8: " .. string_result8)
    print(100, 180, "9: " .. string_result9)
    print(100, 200, "10: " .. number_result1 .. string_result10)
    print(100, 220, "11: " .. string_result11 .. number_result2)
    print(100, 240, "12: " .. string_result12)
end

--[[
=== EXPECTED OUTPUT ===
string_result1: "a->b->c"
string_result2: "b, c"
string_result3: "b-c"
string_result4: ""
string_result5: "z"
string_result6: "1+2+3"
string_result7: "a1b"
string_result8: "x2.5y"
string_result9: "ab|cd|e"
number_result1: 300.0000
string_result10: "xx"
string_result11: "pq!"
number_result2: 6.0000
string_result12: "1234"
]]
