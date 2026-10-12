--#title "[v32lua] native rect()/rectfill() unit test"

--@ Vircon32 Lua native rect() / rectfill() Unit Test
--@ rect(x1, y1, x2, y2 [, color]) draws a 1-pixel outline, rectfill() a
--@ filled rectangle; (x1, y1) and (x2, y2) are opposite INCLUSIVE corners
--@ in any order, floored. color is a packed 0xAABBGGRR word (default
--@ opaque white). Both draw the BIOS texture's (-1) region 256, a single
--@ white pixel the BIOS defines -- nothing is added to the cartridge --
--@ one zoomed draw for rectfill(), up to 4 non-overlapping ones for
--@ rect().
--@
--@ What memory can show: the GPU state rect()/rectfill() touch is put
--@ back (texture, region, multiply color, scale), they return nothing,
--@ and they cost GPU pixels. The shapes themselves are checked on screen
--@ (and, pixel-exact, against the emulator's quads: see the notes at the
--@ end).

function main()
    ioports.gpu.clear()
    ioports.gpu.texture  = -1
    ioports.gpu.region   = 7
    ioports.gpu.multiply = 0xFF00FF00
    ioports.gpu.scaleX   = 2.5
    ioports.gpu.scaleY   = 0.5

    -- === Test 00: rectfill() returns nil ===
    local r = rectfill(10, 20, 19, 24)
    bool_result00 = (r == nil)                      -- Expected: true
    __rawasm__("__debug00:")

    -- === Test 01: selected texture restored (-1, the BIOS texture) ===
    rectfill(30, 20, 0, -3.5, 0xFF0000FF)           -- corners swapped, floored
    number_result01 = ioports.gpu.texture           -- Expected: -1
    __rawasm__("__debug01:")

    -- === Test 02: selected region restored ===
    rect(100, 100, 109, 104, rgba(255, 0, 0, 128))  -- translucent outline
    number_result02 = ioports.gpu.region            -- Expected: 7
    __rawasm__("__debug02:")

    -- === Test 03: multiply color restored (0xFF00FF00 read as a signed int) ===
    local c = rgba(1, 2, 3)
    rect(200, 200, 200, 200, c)                     -- 1x1: one draw
    number_result03 = ioports.gpu.multiply          -- Expected: -16711936
    __rawasm__("__debug03:")

    -- === Test 04 / 05: drawing scale restored ===
    rect(300, 300, 301, 300)                        -- 2x1: top edge only
    rect(400, 300, 400, 302)                        -- 1x3: top, bottom, left
    number_result04 = ioports.gpu.scaleX            -- Expected: 2.5
    number_result05 = ioports.gpu.scaleY            -- Expected: 0.5
    __rawasm__("__debug04:")

    -- === Test 06: the draws cost GPU pixels ===
    local before = ioports.gpu.pixels
    rectfill(0, 100, 99, 199)                       -- 100 x 100
    bool_result06 = (ioports.gpu.pixels < before)   -- Expected: true
    __rawasm__("__debug06:")

    while true do
        system.wait()
    end
end

--[[
=== EXPECTED OUTPUT ===
bool_result00: true
number_result01: -1.0000
number_result02: 7.0000
number_result03: -16711936.0000
number_result04: 2.5000
number_result05: 0.5000
bool_result06: true

Emulator quads (corner coordinates are pixel edges: 10,20 - 20,25 covers
pixels 10..19 x 20..24), multiply color, texture -1 (BIOS):
  rectfill(10, 20, 19, 24)          FFFFFFFF  10,20 - 20,25
  rectfill(30, 20, 0, -3.5, ...)    FF0000FF   0,-4 - 31,21
  rect(100, 100, 109, 104, ...)     800000FF  100,100 - 110,101  top
                                              100,104 - 110,105  bottom
                                              100,101 - 101,104  left
                                              109,101 - 110,104  right
  rect(200, 200, 200, 200, c)       FF030201  200,200 - 201,201
  rect(300, 300, 301, 300)          FFFFFFFF  300,300 - 302,301
  rect(400, 300, 400, 302)          FFFFFFFF  400,300 - 401,301  top
                                              400,302 - 401,303  bottom
                                              400,301 - 401,302  left
]]
