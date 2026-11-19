--#api tic80
--@ Vircon32 Lua TIC-80 screen RAM Unit Test
--@ RAM 0x0000-0x3FBF is the 240x136 screen, 4 bits a pixel (the low nibble is
--@ the left pixel). Once a cart writes it, poke/memset/memcpy draw the bytes
--@ and cls(c) fills the screen RAM with c, so what the cart reads back is what
--@ it drew. The palette at 0x3FC0 is not part of the screen and keeps its bytes.
--@ (The drawing itself is checked by tests/audit/screenram/check.sh.)
--@ Results are stored in global variables for automated memory scraping.

number_result1 = 0
number_result2 = 0
number_result3 = 0
number_result4 = 0
number_result5 = 0
number_result6 = 0
number_result7 = 0

function TIC()
    poke(0, 0)                          -- first screen write: cls now fills RAM
    cls(5)
    number_result1 = peek(100)          -- Expected: 85 (0x55)
    poke(100, 0x23)
    number_result2 = peek(100)          -- Expected: 35
    memset(200, 0x77, 20)
    number_result3 = peek(219)          -- Expected: 119
    number_result4 = peek(220)          -- Expected: 85 (still the cls fill)
    memcpy(400, 200, 10)
    number_result5 = peek(409)          -- Expected: 119
    cls(3)
    number_result6 = peek(0x3FBF)       -- Expected: 51 (0x33, last screen byte)
    number_result7 = peek(0x3FC0)       -- Expected: 26 (palette untouched)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 85.0000
number_result2: 35.0000
number_result3: 119.0000
number_result4: 85.0000
number_result5: 119.0000
number_result6: 51.0000
number_result7: 26.0000
]]
