--#title "v32lua GPU texture region unit test"
--@ Vircon32 Lua video unit test -- lib/video.lua
--@ Exercises the region-editor helpers ported from video.h:
--@ select_region, define_region, define_region_topleft,
--@ define_region_center and define_region_matrix, with every
--@ definition verified by selecting the region again and reading
--@ its coordinates back through ioports.gpu (v32sim stores region
--@ definitions per region id, so later definitions cannot disturb
--@ earlier ones -- matrix cells included).
--@
--@ Two porting details get specific attention: define_region_topleft
--@ writes only min/max and relies on the compiler's minX->hotX,
--@ minY->hotY auto-pairing to pin the hotspot at the corner (the
--@ same trick video.h's version plays with the console's paired
--@ register writes) -- confirmed here by reading hotX/hotY back;
--@ and define_region_center computes the hotspot with floor
--@ division, checked on both an odd-sized and an offset region.
--@
--@ select_texture is exercised as a smoke call only: with no
--@ textures in this cart, v32sim's texture port reads back -1
--@ ("none") no matter what was written, so the write has no
--@ observable effect to assert here.

--#include "../../lib/video.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: select_region, verified by reading the port back ===
    select_region(4)
    number_region_selected = ioports.gpu.region   -- 4

    -- === Test 2: define_region -- all six coordinates, explicit hotspot ===
    define_region(0, 1, 2, 3, 4, 5)
    number_dr_minx = ioports.gpu.minX   -- 0
    number_dr_miny = ioports.gpu.minY   -- 1
    number_dr_maxx = ioports.gpu.maxX   -- 2
    number_dr_maxy = ioports.gpu.maxY   -- 3
    number_dr_hotx = ioports.gpu.hotX   -- 4 (explicit, over the auto-paired 0)
    number_dr_hoty = ioports.gpu.hotY   -- 5

    -- === Test 3: define_region_topleft -- hotspot auto-paired to the corner ===
    select_region(5)
    define_region_topleft(10, 20, 30, 40)
    number_top_minx = ioports.gpu.minX  -- 10
    number_top_hotx = ioports.gpu.hotX  -- 10: paired from minX, never written
    number_top_hoty = ioports.gpu.hotY  -- 20: paired from minY
    number_top_maxy = ioports.gpu.maxY  -- 40

    -- === Test 4: define_region_center -- hotspot at the middle, ===
    -- === floor division on odd sizes and on offset regions ===
    select_region(6)
    define_region_center(0, 0, 99, 99)
    number_c1_hotx = ioports.gpu.hotX   -- (0+99)//2 = 49
    number_c1_hoty = ioports.gpu.hotY   -- 49

    select_region(7)
    define_region_center(100, 50, 199, 99)
    number_c2_hotx = ioports.gpu.hotX   -- (100+199)//2 = 149
    number_c2_hoty = ioports.gpu.hotY   -- (50+99)//2 = 74

    -- === Test 5: define_region_matrix -- 4x2 grid of 16x16 regions, ===
    -- === gap 4 (advance 20 in both axes), ids 10..17, hotspot at (8,8) ===
    define_region_matrix(10, 0, 0, 15, 15, 8, 8, 4, 2, 4)

    select_region(10)  -- top-left cell
    number_m10_minx = ioports.gpu.minX  -- 0
    number_m10_maxx = ioports.gpu.maxX  -- 15

    select_region(11)  -- one cell right
    number_m11_minx = ioports.gpu.minX  -- 20
    number_m11_hotx = ioports.gpu.hotX  -- 28

    select_region(14)  -- first cell of the second row
    number_m14_miny = ioports.gpu.minY  -- 20
    number_m14_hoty = ioports.gpu.hotY  -- 28

    select_region(17)  -- bottom-right cell
    number_m17_minx = ioports.gpu.minX  -- 60
    number_m17_maxy = ioports.gpu.maxY  -- 35
    number_m17_hotx = ioports.gpu.hotX  -- 68
    number_m17_hoty = ioports.gpu.hotY  -- 28

    -- === Test 6: select_texture -- smoke call; the texture port ===
    -- === reads -1 with no textures in the cart (see header) ===
    select_texture(2)

    print(10, 0,   "--- GPU region unit test ---")
    print(10, 20,  "define_region hot: " .. number_dr_hotx
                   .. "/" .. number_dr_hoty)
    print(10, 40,  "topleft-paired hot: " .. number_top_hotx
                   .. "/" .. number_top_hoty)
    print(10, 60,  "center hot (0..99): " .. number_c1_hotx
                   .. "/" .. number_c1_hoty)
    print(10, 80,  "matrix r11 min/hot x: " .. number_m11_minx
                   .. "/" .. number_m11_hotx)
    print(10, 100, "matrix r17 min/hot x: " .. number_m17_minx
                   .. "/" .. number_m17_hotx)
end

--[[
=== EXPECTED OUTPUT ===

number_region_selected: 4.0000
number_dr_minx: 0.0000
number_dr_miny: 1.0000
number_dr_maxx: 2.0000
number_dr_maxy: 3.0000
number_dr_hotx: 4.0000
number_dr_hoty: 5.0000
number_top_minx: 10.0000
number_top_hotx: 10.0000
number_top_hoty: 20.0000
number_top_maxy: 40.0000
number_c1_hotx: 49.0000
number_c1_hoty: 49.0000
number_c2_hotx: 149.0000
number_c2_hoty: 74.0000
number_m10_minx: 0.0000
number_m10_maxx: 15.0000
number_m11_minx: 20.0000
number_m11_hotx: 28.0000
number_m14_miny: 20.0000
number_m14_hoty: 28.0000
number_m17_minx: 60.0000
number_m17_maxy: 35.0000
number_m17_hotx: 68.0000
number_m17_hoty: 28.0000

--]]
