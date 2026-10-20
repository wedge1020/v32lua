--#api tic80
--@ Vircon32 Lua TIC-80 integer drawing coordinates Unit Test
--@ TIC-80 draws at whole pixels: spr/pix/print truncate x and y toward zero
--@ before anything is drawn. The layer must do the same before scaling by
--@ 2.625, or a sprite at y = 112.0 / 112.2 / 112.6 lands on screen rows
--@ 294 / 295 / 296 (superblock_adventure's ground-contact vibration).
--@ The GPU drawing point is read back through its port after each call.
--@ Results are stored in global variables for automated memory scraping.

number_result00a = 0
number_result00b = 0
number_result00c = 0
number_result00d = 0
number_result01a = 0
number_result01b = 0
number_result02a = 0
number_result02b = 0
number_result03a = 0

local function point()
    __rawasm__("IN  R0, GPU_DrawingPointX")
    __rawasm__("CIF R0")
    __rawasm__("MOV [var_number_px], R0")
    __rawasm__("IN  R0, GPU_DrawingPointY")
    __rawasm__("CIF R0")
    __rawasm__("MOV [var_number_py], R0")
end
number_px = 0
number_py = 0

function TIC()
    cls(0)
    -- the same sprite resting at y = 112.0, 112.2 and 112.6: one screen row
    spr(1, 8, 112.0, 0)
    point()
    number_result00a = number_py
    spr(1, 8, 112.2, 0)
    point()
    number_result00b = number_py
    spr(1, 8, 112.6, 0)
    point()
    number_result00c = number_py
    -- x: 10.7 -> 10 -> 26.25 screen px -> 26
    spr(1, 10.7, 0, 0)
    point()
    number_result00d = number_px

    -- pix(5.9, 7.9) is pixel (5, 7): 13.125 -> 13, 18.375 -> 18
    pix(5.9, 7.9, 12)
    point()
    number_result01a = number_px
    number_result01b = number_py

    -- negative coordinates truncate toward zero, as a C cast does
    spr(1, -3.5, -0.5, 0)
    point()
    number_result02a = number_px   -- -3 -> -7.875 -> -8 (round half up)
    number_result02b = number_py   -- 0

    -- integral values are unchanged
    spr(1, 100, 50, 0)
    point()
    number_result03a = number_px + number_py   -- 263 + 131
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 294.0000
number_result00b: 294.0000
number_result00c: 294.0000
number_result00d: 26.0000
number_result01a: 13.0000
number_result01b: 18.0000
number_result02a: -8.0000
number_result02b: 0.0000
number_result03a: 394.0000

--]]
