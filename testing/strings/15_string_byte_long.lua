--@ Vircon32 Lua string.byte() on long strings
--@ The length of a long string is remembered between calls (STRLEN_CACHE);
--@ this checks two long strings used alternately, bounds, and a short one.
--@ Results stored in global variables for automated memory scraping.

function test_string_byte_long()
    local t1, t2 = {}, {}
    for i = 1, 100 do t1[i] = "a" end
    for i = 1, 150 do t2[i] = "b" end
    local s1 = table.concat(t1)         -- 100 x "a"
    local s2 = table.concat(t2)         -- 150 x "b"
    local byte = string.byte

    number_result1 = byte(s1, 100)      -- Expected: 97
    number_result2 = byte(s2, 150)      -- Expected: 98
    number_result3 = byte(s1, 100)      -- Expected: 97
    local x = byte(s1, 101)
    number_result4 = (x == nil) and 1 or 0      -- Expected: 1
    local y = byte(s2, 101)
    number_result5 = y                  -- Expected: 98
    local p, q = byte(s1, 99, 150)
    number_result6 = p + q              -- Expected: 194
    number_result7 = byte(s2, -1)       -- Expected: 98
    number_result8 = byte("hi", 2)      -- Expected: 105
    number_result9 = byte(s1, 1) + byte(s2, 1)  -- Expected: 195
    local u = s1 .. "Z"                 -- a third long string
    number_result10 = byte(u, 101)      -- Expected: 90
    number_result11 = byte(s1, 101) == nil and 1 or 0   -- Expected: 1
end

function main()
    ioports.gpu.clear("black")
    test_string_byte_long()
    print(100, 0, "--- string.byte() long ---")
    print(100, 20, number_result1 .. " " .. number_result2 .. " " .. number_result3)
    print(100, 40, number_result4 .. " " .. number_result5 .. " " .. number_result6)
    print(100, 60, number_result7 .. " " .. number_result8 .. " " .. number_result9)
    print(100, 80, number_result10 .. " " .. number_result11)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 97.0000
number_result2: 98.0000
number_result3: 97.0000
number_result4: 1.0000
number_result5: 98.0000
number_result6: 194.0000
number_result7: 98.0000
number_result8: 105.0000
number_result9: 195.0000
number_result10: 90.0000
number_result11: 1.0000
]]
