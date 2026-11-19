--@ Vircon32 Lua strings holding NUL bytes: string.char(0)
--@ Strings end at the first 0 word, so a NUL byte is stored as the word 256
--@ and read back as 0 by string.byte. Binary data built with string.char and
--@ table.concat (BlasTIC's packed sprite runs) keeps every byte.
--@ Results stored in global variables for automated memory scraping.

function test_string_nul_byte()
    local s = string.char(65, 0, 66)
    number_result1 = #s                              -- Expected: 3
    number_result2 = string.byte(s, 2)               -- Expected: 0
    number_result3 = string.byte(s, 3)               -- Expected: 66

    local t = {}
    for i = 1, 100 do t[i] = string.char(i % 3 == 0 and 0 or 65 + i % 7) end
    local big = table.concat(t)
    number_result4 = #big                            -- Expected: 100
    local sum = 0
    for i = 1, 100 do sum = sum + string.byte(big, i) end
    local want = 0
    for i = 1, 100 do want = want + (i % 3 == 0 and 0 or 65 + i % 7) end
    number_result5 = sum - want                      -- Expected: 0

    local a, b, c = string.byte(s, 1, 3)
    number_result6 = a * 10000 + b * 100 + c         -- Expected: 650066

    local u = s .. "xy"
    number_result7 = #u                              -- Expected: 5
    number_result8 = string.byte(u, 4)               -- Expected: 120
    local sub = string.sub(u, 2, 3)
    number_result9 = #sub                            -- Expected: 2
    number_result10 = string.byte(sub, 1)            -- Expected: 0

    number_result11 = (string.char(0) == string.char(0)) and 1 or 0   -- Expected: 1
    number_result12 = (string.char(0) == string.char(1)) and 1 or 0   -- Expected: 0
end

function main()
    ioports.gpu.clear("black")
    test_string_nul_byte()
    print(100, 0, "NUL bytes: " .. number_result1 .. " " .. number_result5)
    print(100, 20, string.char(65, 0, 66))
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 3.0000
number_result2: 0.0000
number_result3: 66.0000
number_result4: 100.0000
number_result5: 0.0000
number_result6: 650066.0000
number_result7: 5.0000
number_result8: 120.0000
number_result9: 2.0000
number_result10: 0.0000
number_result11: 1.0000
number_result12: 0.0000
]]
