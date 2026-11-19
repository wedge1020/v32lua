--#api tic80
--@ Vircon32 Lua TIC-80 BDR() Unit Test
--@ BDR(row) is the per-scanline callback. Drawing screen RAM (0-0x3FBF) calls it once
--@ per screen row drawn, with row = y + 4, before that row; what it pokes into the
--@ palette is in force for the row. Rows between draws and a cart without BDR cost
--@ nothing. Results are stored in global variables for automated memory scraping.

number_result1 = 0
number_result2 = 0
number_result3 = 0
number_result4 = 0
number_result5 = 0
number_result6 = 0

local rows, first, last = 0, -1, -1

function BDR(row)
    rows = rows + 1
    if first < 0 then first = row end
    last = row
    poke(0x3FC0 + 3, row)                        -- palette entry 1, red
end

function TIC()
    if rows > 0 then return end                  -- one pass
    memset(0, 0x11, 120 * 5)                     -- rows 0-4
    number_result1 = rows                         -- Expected: 5
    number_result2 = first                        -- Expected: 4
    number_result3 = last                         -- Expected: 8
    number_result4 = peek(0x3FC0 + 3)             -- Expected: 8
    poke(120 * 10 + 3, 0x11)                      -- one byte on row 10
    number_result5 = rows                         -- Expected: 6
    number_result6 = last                         -- Expected: 14
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 5.0000
number_result2: 4.0000
number_result3: 8.0000
number_result4: 8.0000
number_result5: 6.0000
number_result6: 14.0000
]]
