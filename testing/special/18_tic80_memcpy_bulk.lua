--#api tic80
--@ Vircon32 Lua TIC-80 memset/memcpy bulk path Unit Test
--@ memset/memcpy of 8 or more bytes inside plain storage (0-0x7FFF, 0xFF84 up,
--@ except the sprite flags) run as SETS / MOVS instead of byte by byte; a range
--@ crossing into the map (0x8000+), an overlapping copy, a fill byte over 255 and
--@ a short run must give the byte-by-byte answer.
--@ Results are stored in global variables for automated memory scraping.

number_result1 = 0
number_result2 = 0
number_result3 = 0
number_result4 = 0
number_result5 = 0
number_result6 = 0
number_result7 = 0
number_result8 = 0
number_result9 = 0
number_result10 = 0
number_result11 = 0

function TIC()
    memset(0x1000, 7, 100)
    number_result1 = peek(0x1000)                  -- Expected: 7
    number_result2 = peek(0x1063)                  -- Expected: 7
    number_result3 = peek(0x1064)                  -- Expected: 0

    for i = 0, 19 do poke(0x2000 + i, i) end
    memcpy(0x3000, 0x2000, 20)
    number_result4 = peek(0x3000 + 13) + peek(0x3000 + 19) -- Expected: 32

    for i = 0, 9 do poke(0x4000 + i, i + 1) end
    memcpy(0x4002, 0x4000, 10)                     -- overlapping: forward copy
    number_result5 = peek(0x4003)                  -- Expected: 2
    number_result6 = peek(0x4004)                  -- Expected: 1

    memset(0x7FF8, 9, 16)                          -- crosses into the map
    number_result7 = peek(0x7FFF) * 100 + peek(0x8000) * 10 + peek(0x8007) -- Expected: 999
    number_result8 = peek(0x8008)                  -- Expected: 0

    memset(0x5000, 300, 10)
    number_result9 = peek(0x5009)                  -- Expected: 44

    memset(0x6000, 5, 3)
    number_result10 = peek(0x6002) * 10 + peek(0x6003) -- Expected: 50

    memset(0x20000 - 0x8000 + 0x8000, 1, 4)        -- 0x20000: past RAM, ignored
    number_result11 = peek(0x5000)                 -- Expected: 44
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 7.0000
number_result2: 7.0000
number_result3: 0.0000
number_result4: 32.0000
number_result5: 2.0000
number_result6: 1.0000
number_result7: 999.0000
number_result8: 0.0000
number_result9: 44.0000
number_result10: 50.0000
number_result11: 44.0000
]]
