--@ Vircon32 Lua # on long strings (length cache) Unit Test
--@ `#s` shares string.byte's one-entry cache of the last string of 64 or more
--@ characters. Alternating long strings, a short one, a rebuilt string and an
--@ empty one must each report their own length.
--@ Results stored in global variables for automated memory scraping.

function test_len_long()
    local t1, t2 = {}, {}
    for i = 1, 100 do t1[i] = "a" end
    for i = 1, 70 do t2[i] = "b" end
    local s1 = table.concat(t1)
    local s2 = table.concat(t2)
    number_result1 = #s1                       -- Expected: 100
    number_result2 = #s2                       -- Expected: 70
    number_result3 = #s1 + #s1 + #s2           -- Expected: 270
    number_result4 = #"short"                  -- Expected: 5
    local s3 = s1 .. s2
    number_result5 = #s3                       -- Expected: 170
    number_result6 = #s1                       -- Expected: 100
    number_result7 = #""                       -- Expected: 0
    local n = 0
    for i = 1, #s3 do n = n + 1 end
    number_result8 = n                         -- Expected: 170
    number_result9 = #string.rep("xy", 40)     -- Expected: 80
end

function main()
    ioports.gpu.clear("black")
    test_len_long()
    print(100, 0, "len: " .. number_result1 .. " " .. number_result5)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 100.0000
number_result2: 70.0000
number_result3: 270.0000
number_result4: 5.0000
number_result5: 170.0000
number_result6: 100.0000
number_result7: 0.0000
number_result8: 170.0000
number_result9: 80.0000
]]
