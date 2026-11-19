--@ Vircon32 Lua string.byte() -- multiple return values, function value, method form
--@ string.byte(s, i, j) returns j-i+1 values; it also works through a local
--@ alias (local byte = string.byte) and as s:byte(i, j).
--@ Results stored in global variables for automated memory scraping.

local byte = string.byte

local function count(...)
    local t = { ... }
    return #t
end

function test_string_byte_multi()
    local s = "ABCDEFG"

    -- === Test 1: direct call, four values ===
    local a, b, c, d = string.byte(s, 2, 5)
    number_result1 = a + b + c + d                  -- Expected: 270

    -- === Test 2: through a local alias ===
    local e, f, g, h = byte(s, 2, 5)
    number_result2 = e + f + g + h                  -- Expected: 270

    -- === Test 3: method form ===
    local m, n = s:byte(1, 2)
    number_result3 = m * 100 + n                    -- Expected: 6566

    -- === Test 4: single value forms still work ===
    number_result4 = byte(s, 3)                     -- Expected: 67
    number_result5 = string.byte(s)                 -- Expected: 65
    number_result6 = s:byte(-1)                     -- Expected: 71

    -- === Test 5: out of range / empty ===
    local x = byte(s, 10, 12)
    number_result7 = (x == nil) and 1 or 0          -- Expected: 1

    -- === Test 6: negative and clamped ranges ===
    local p, q, r = string.byte(s, -3, -1)
    number_result8 = p + q + r                      -- Expected: 210
    local t1, t2 = byte(s, 6, 100)
    number_result9 = t1 + t2                        -- Expected: 70+71 = 141

    -- === Test 7: all bytes into a table ===
    local tt = { string.byte(s, 1, 7) }
    number_result10 = #tt                           -- Expected: 7
    number_result11 = tt[7]                         -- Expected: 71

    -- === Test 8: as the last argument of a call ===
    number_result12 = count(string.byte(s, 1, 4))   -- Expected: 4
    number_result13 = count(byte(s, 1, 3))          -- Expected: 3

    -- === Test 9: RAM string built at run time ===
    local u = "xy" .. "z"
    local k, l, o = u:byte(1, 3)
    number_result14 = k + l + o                     -- Expected: 363
end

function main()
    ioports.gpu.clear("black")
    test_string_byte_multi()

    print(100, 0,   "--- string.byte() multi ---")
    print(100, 20,  "1: " .. number_result1 .. " 2: " .. number_result2)
    print(100, 40,  "3: " .. number_result3 .. " 4: " .. number_result4)
    print(100, 60,  "5: " .. number_result5 .. " 6: " .. number_result6)
    print(100, 80,  "7: " .. number_result7 .. " 8: " .. number_result8)
    print(100, 100, "9: " .. number_result9 .. " 10: " .. number_result10)
    print(100, 120, "11: " .. number_result11 .. " 12: " .. number_result12)
    print(100, 140, "13: " .. number_result13 .. " 14: " .. number_result14)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 270.0000
number_result2: 270.0000
number_result3: 6566.0000
number_result4: 67.0000
number_result5: 65.0000
number_result6: 71.0000
number_result7: 1.0000
number_result8: 210.0000
number_result9: 141.0000
number_result10: 7.0000
number_result11: 71.0000
number_result12: 4.0000
number_result13: 3.0000
number_result14: 363.0000
]]
