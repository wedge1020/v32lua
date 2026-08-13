--#title "v32lua type() unit test"
--@ Vircon32 Lua type() Function Unit Test
--@ Tests the type() builtin function across all Lua types.
--@ Results are stored in global variables for automated memory scraping.

function test_type_function()
    -- === Test 1: nil type ===
    string_result1 = type(nil)  -- Expected: "nil"

    -- === Test 2: boolean type (true) ===
    string_result2 = type(true)  -- Expected: "boolean"

    -- === Test 3: boolean type (false) ===
    string_result3 = type(false)  -- Expected: "boolean"

    -- === Test 4: number type (integer) ===
    string_result4 = type(0)  -- Expected: "number"

    -- === Test 5: number type (positive integer) ===
    string_result5 = type(123)  -- Expected: "number"

    -- === Test 6: number type (negative integer) ===
    string_result6 = type(-42)  -- Expected: "number"

    -- === Test 7: number type (float) ===
    string_result7 = type(3.14)  -- Expected: "number"

    -- === Test 8: string type (empty string) ===
    string_result8 = type("")  -- Expected: "string"

    -- === Test 9: string type (non-empty) ===
    string_result9 = type("hello world")  -- Expected: "string"

    -- === Test 10: table type (empty) ===
    string_result10 = type({})  -- Expected: "table"

    -- === Test 11: table type (non-empty) ===
    string_result11 = type({x = 1, y = 2})  -- Expected: "table"

    -- === Test 12: function type (anonymous) ===
    string_result12 = type(function() return 42 end)  -- Expected: "function"

    -- === Test 13: function type (named) ===
    local function myfunc() return "test" end
    string_result13 = type(myfunc)  -- Expected: "function"

    -- === Test 14: type of a variable holding nil ===
    local var_nil = nil
    string_result14 = type(var_nil)  -- Expected: "nil"

    -- === Test 15: type of a variable holding a number ===
    local var_num = 99.9
    string_result15 = type(var_num)  -- Expected: "number"

    -- === Test 16: type of a variable holding a string ===
    local var_str = "test"
    string_result16 = type(var_str)  -- Expected: "string"

    -- === Test 17: type of a variable holding a table ===
    local var_tbl = {a = 1}
    string_result17 = type(var_tbl)  -- Expected: "table"

    -- === Test 18: type of a variable holding a function ===
    local var_fn = function() end
    string_result18 = type(var_fn)  -- Expected: "function"

    -- === Test 19: type of a variable holding a boolean ===
    local var_bool = true
    string_result19 = type(var_bool)  -- Expected: "boolean"

    -- === Test 20: type of a table key value (number) ===
    local t = {key = 42}
    string_result20 = type(t.key)  -- Expected: "number"

    -- === Test 21: type of a table key value (string) ===
    local t2 = {name = "value"}
    string_result21 = type(t2.name)  -- Expected: "string"

    -- === Test 22: type of a table key value (table) ===
    local t3 = {nested = {inner = "data"}}
    string_result22 = type(t3.nested)  -- Expected: "table"

    -- === Test 23: type of array element (number) ===
    local arr = {10, 20, 30}
    string_result23 = type(arr[1])  -- Expected: "number"

    -- === Test 24: type of array element (string) ===
    local arr2 = {"a", "b", "c"}
    string_result24 = type(arr2[2])  -- Expected: "string"
end

function main()
    ioports.gpu.clear("black")
    test_type_function()

    -- Double column layout: left at x=0, right at x=320
    -- Left column (Tests 1-12)
    print(0,   0,   "Test 1  - type(nil): " ..        string_result1)
    print(0,   20,  "Test 2  - type(true): " ..       string_result2)
    print(0,   40,  "Test 3  - type(false): " ..      string_result3)
    print(0,   60,  "Test 4  - type(0): " ..          string_result4)
    print(0,   80,  "Test 5  - type(123): " ..        string_result5)
    print(0,   100, "Test 6  - type(-42): " ..        string_result6)
    print(0,   120, "Test 7  - type(3.14): " ..       string_result7)
    print(0,   140, "Test 8  - type(''): " ..         string_result8)
    print(0,   160, "Test 9  - type('hello'): " ..    string_result9)
    print(0,   180, "Test 10 - type({}): " ..        string_result10)
    print(0,   200, "Test 11 - type({x=1,y=2}): " ..  string_result11)
    print(0,   220, "Test 12 - type(fn): " ..         string_result12)

    -- Right column (Tests 13-24)
    print(320, 0,   "Test 13 - type(named fn): " ..   string_result13)
    print(320, 20,  "Test 14 - type(var nil): " ..    string_result14)
    print(320, 40,  "Test 15 - type(var num): " ..    string_result15)
    print(320, 60,  "Test 16 - type(var str): " ..    string_result16)
    print(320, 80,  "Test 17 - type(var tbl): " ..    string_result17)
    print(320, 100, "Test 18 - type(var fn): " ..     string_result18)
    print(320, 120, "Test 19 - type(var bool): " ..   string_result19)
    print(320, 140, "Test 20 - type(t.key): " ..      string_result20)
    print(320, 160, "Test 21 - type(t.name): " ..     string_result21)
    print(320, 180, "Test 22 - type(t.nested): " ..   string_result22)
    print(320, 200, "Test 23 - type(arr[1]): " ..     string_result23)
    print(320, 220, "Test 24 - type(arr2[2]): " ..    string_result24)
end

--[[
=== EXPECTED OUTPUT ===

string_result1:  "nil"
string_result2:  "boolean"
string_result3:  "boolean"
string_result4:  "number"
string_result5:  "number"
string_result6:  "number"
string_result7:  "number"
string_result8:  "string"
string_result9:  "string"
string_result10: "table"
string_result11: "table"
string_result12: "function"
string_result13: "function"
string_result14: "nil"
string_result15: "number"
string_result16: "string"
string_result17: "table"
string_result18: "function"
string_result19: "boolean"
string_result20: "number"
string_result21: "string"
string_result22: "table"
string_result23: "number"
string_result24: "string"

--]]
