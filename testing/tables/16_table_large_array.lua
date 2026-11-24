--@ Vircon32 Lua tables with more than 32768 sequential elements.
--@ The array part's capacity is a 16-bit field. Doubling 32768 gave 65536,
--@ which overflowed it: a table holding 32769 elements read back as
--@ empty (every element nil, #t stuck at 32769). Found when BlasTIC's
--@ art loader built a 35,000-entry table and spun forever on nil.
--@ Beyond 65535 the rest lives in the hash part and the border (#t)
--@ follows it, so t[#t+1] = v and table.concat keep working.
--@ Results stored in global variables for automated memory scraping.
--@ Needs a longer run than the default 30 frames (the directive below sets
--@ the cap for tools/headless/unittest.py).
--@ frames: 150

function test_table_large_array()
    local t = {}

    -- === Test 1: just over the old failure point ===
    for i = 1, 33000 do t[#t + 1] = i end
    number_result1 = #t                 -- Expected: 33000
    number_result2 = t[1]               -- Expected: 1
    number_result3 = t[16500]           -- Expected: 16500
    number_result4 = t[33000]           -- Expected: 33000

    -- === Test 2: keep appending across the 65535 array limit ===
    for i = 33001, 65540 do t[#t + 1] = i end
    number_result5 = #t                 -- Expected: 65540
    number_result6 = t[65535]           -- Expected: 65535
    number_result7 = t[65536]           -- Expected: 65536
    number_result8 = t[65540]           -- Expected: 65540

    -- === Test 3: table.concat over the boundary ===
    string_result1 = table.concat(t, ",", 65534, 65537)  -- Expected: "65534,65535,65536,65537"

    -- === Test 4: the fix did not disturb ordinary tables ===
    local s = {10, 20, 30}
    s[#s + 1] = 40
    number_result9 = #s                 -- Expected: 4
    number_result10 = s[4]              -- Expected: 40
end

function main()
    ioports.gpu.clear("black")
    test_table_large_array()
    print(100, 0, "--- large tables ---")
    print(100, 20, "len1: " .. number_result1)
    print(100, 40, "len2: " .. number_result5)
    print(100, 60, "cat: " .. string_result1)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 33000.0000
number_result2: 1.0000
number_result3: 16500.0000
number_result4: 33000.0000
number_result5: 65540.0000
number_result6: 65535.0000
number_result7: 65536.0000
number_result8: 65540.0000
string_result1: "65534,65535,65536,65537"
number_result9: 4.0000
number_result10: 40.0000
]]
