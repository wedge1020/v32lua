--#api pico8
--@ Vircon32 Lua PICO-8 16.16 Literal Unit Test
--@ PICO-8 numbers are 16.16 fixed point: a literal holds the nearest
--@ multiple of 1/65536, so sums of literals are exact -- froggo's
--@ `x_v += 0.4` / `x_v -= 0.4` returns to exactly 0 (in plain float32 it
--@ left 6e-8, and the player crept a pixel at a time). Also `//` comments.
--@ Results are stored in global variables for automated memory scraping.

function _init()
    // a PICO-8 line comment
    -- === Test 00: accumulate and brake back to zero ===
    local v = 0
    for i = 1, 4 do v += 0.4 end
    for i = 1, 4 do v -= 0.4 end
    boolean_result00a = v == 0
    local w = 0
    for i = 1, 4 do w += 0.4 end
    local frames = 0
    while w != 0 and frames < 20 do         // brakes as froggo does
        if w > 0 then w -= 0.4 elseif w < 0 then w += 0.4 end
        frames += 1
    end
    number_result00b = frames
    __rawasm__("__debug0:")

    -- === Test 01: literal values are PICO-8's ===
    boolean_result01a = 0.1 == 0x0.199a
    boolean_result01b = 0.4 == 0x0.6666
    boolean_result01c = split("0.4")[1] == 0.4
    number_result01d = 1.5 + 2.25   // exact values stay exact
    __rawasm__("__debug1:")
end

function _draw()
end

--[[
=== EXPECTED OUTPUT ===

boolean_result00a: true
number_result00b: 4.0000
boolean_result01a: true
boolean_result01b: true
boolean_result01c: true
number_result01d: 3.7500

--]]
