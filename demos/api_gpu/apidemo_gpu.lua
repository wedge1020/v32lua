--#title "Vircon32 Native API spr() Demo"
--#texture sprites "assets/apidemo_gpu_sprites.png"

------------------------------------------------------------------------------
-- Native Vircon32 API demo: spr(), btn(), btnp()
--
-- spr()/btn()/btnp() are the SAME function names used by v32lua's PICO-8
-- and TIC-80 compatibility layers. This cart does NOT declare a "--#api"
-- hint (no --#api "pico8" or --#api "tic80"), so neither compatibility flag
-- gets set, and the compiler routes all three calls to the native Vircon32
-- implementations in intrinsics/vircon32.s instead of the PICO-8/TIC-80
-- emulation paths.
--
-- --#texture registers the sheet as a cart resource and creates a global
-- Lua variable ("sprites" above) holding its numeric texture id. Regions
-- are then carved out of it below -- see "Defining texture regions" in
-- API.md, which this demo's init() follows exactly, including the one
-- part that's easy to get wrong: hotX/hotY must match minX/minY, NOT be
-- left at 0. Found the hard way while building tilemap.render() -- a
-- region cut from anywhere but the sheet's own top-left corner draws
-- offset by roughly its own minX/minY if the hotspot isn't set to match.
--
-- Regions used here (found by scanning the sheet's alpha channel for
-- gaps, same technique as the tilemap demo):
--   1 = WIZARD_A  45x63  (6,6)-(50,68)     -- walk frame A
--   2 = WIZARD_B  45x63  (57,6)-(101,68)   -- walk frame B
--   3 = SLIME     48x36  (6,221)-(53,256)  -- gamepad-2 transform, below
------------------------------------------------------------------------------

local player_x     = 100
local player_y     = 100
local speed        = 2
local player_region = 1      -- GPU region id for the player's sprite frame
local facing_left  = false
local jump_count   = 0

function init()
    ioports.gpu.texture = sprites

    ioports.gpu.region = 1
    ioports.gpu.minX = 6
    ioports.gpu.minY = 6
    ioports.gpu.maxX = 50
    ioports.gpu.maxY = 68
    ioports.gpu.hotX = 6
    ioports.gpu.hotY = 6

    ioports.gpu.region = 2
    ioports.gpu.minX = 57
    ioports.gpu.minY = 6
    ioports.gpu.maxX = 101
    ioports.gpu.maxY = 68
    ioports.gpu.hotX = 57
    ioports.gpu.hotY = 6

    ioports.gpu.region = 3
    ioports.gpu.minX = 6
    ioports.gpu.minY = 221
    ioports.gpu.maxX = 53
    ioports.gpu.maxY = 256
    ioports.gpu.hotX = 6
    ioports.gpu.hotY = 221
end

function main()
	ioports.gpu.clear("black")
    while true do
        -----------------------------------------------------------------
        -- btn(id[, player]): continuous/held state -- true every single
        -- frame the button stays down. Good for movement.
        --
        -- Button IDs: 0=Left 1=Right 2=Up 3=Down 4=Start
        --             5=A 6=B 7=X 8=Y 9=L 10=R
        -----------------------------------------------------------------
        if btn(0) then                 -- Left, current gamepad
            player_x    = player_x - speed
            facing_left = true
        end
        if btn(1) then                 -- Right, current gamepad
            player_x    = player_x + speed
            facing_left = false
        end
        if btn(2) then                 -- Up
            player_y = player_y - speed
        end
        if btn(3) then                 -- Down
            player_y = player_y + speed
        end

        -----------------------------------------------------------------
        -- btnp(id[, player]): edge-triggered -- true only on the single
        -- frame the button transitions from up to down, no matter how
        -- long it's then held. Good for jumps, menu moves, single shots.
        -----------------------------------------------------------------
        if btnp(5) then                -- A, current gamepad: swap walk frame
            jump_count    = jump_count + 1
            player_region = 1 + (jump_count % 2)   -- alternates region 1 / 2
        end

        if btnp(6, 1) then             -- B, explicit player index (gamepad 1):
            player_region = 3           -- turn into a slime for a moment
        end

        -----------------------------------------------------------------
        -- spr(region_id, x, y[, scale_x][, scale_y][, angle_deg]
        --     [, color_mult][, blend_mode])
        --
        -- __builtin_vircon32_spr looks at the ACTUAL runtime values of
        -- scale_x/scale_y/angle_deg every time it's called and picks the
        -- cheapest matching GPU command itself -- it doesn't matter
        -- whether a call spells the trailing arguments out; what matters
        -- is whether they evaluate to the defaults (1.0, 1.0, 0.0).
        -----------------------------------------------------------------
        ioports.gpu.clear("black")

        -- All default -> GPUCommand_DrawRegion (cheapest).
        spr(player_region, player_x, player_y)

        -- Explicit scale_x/scale_y that still equal 1.0 at runtime ->
        -- still resolves to GPUCommand_DrawRegion. Only the actual values
        -- matter now, not whether they were written out in the call.
        spr(player_region, player_x, player_y, 1.0, 1.0, 0.0)

        -- Only angle differs from default -> GPUCommand_DrawRegionRotated
        -- (scale left alone, cheaper than a full rotozoom).
        local spin_angle = (jump_count * 15.0) % 360.0
        spr(player_region, player_x + 64, player_y, 1.0, 1.0, spin_angle)

        -- Only scale differs (a horizontal mirror via negative scale_x) ->
        -- GPUCommand_DrawRegionZoomed.
        local scale_x = facing_left and -1.0 or 1.0
        spr(player_region, player_x + 128, player_y, scale_x, 1.0)

        -- Both scale and angle differ -> GPUCommand_DrawRegionRotozoomed,
        -- now with color_mult/blend_mode also applied.
        spr(player_region, player_x + 192, player_y,
            scale_x, 1.0, spin_angle, 0xFFFFFFFF, 0x20)

        ioports.gpu.sync()   -- WAIT for vsync -- required once per frame in main()
    end
end
