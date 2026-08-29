--#title "Vircon32 Native API Demo"

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
-- --#texture registers "player.png" as a cart resource and creates a global
-- Lua variable ("sprites" below) holding its numeric texture id.
------------------------------------------------------------------------------

local player_x     = 100
local player_y     = 100
local speed        = 2
local player_region = 66     -- GPU region id for the player's sprite frame
local facing_left  = false
local jump_count   = 0

function main()
    ioports.gpu.texture = -1   -- select the texture registered above

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
        if btnp(5) then                -- A, current gamepad
            jump_count    = jump_count + 1
            player_region = jump_count % 2   -- swap sprite frame each jump
        end

        if btnp(6, 1) then             -- B, explicit player index (gamepad 1)
            player_region = 67
        end

        -----------------------------------------------------------------
        -- spr(region_id, x, y[, scale_x][, scale_y][, angle_deg]
        --     [, color_mult][, blend_mode])
        --
        -- __builtin_vircon32_spr now looks at the ACTUAL runtime values of
        -- scale_x/scale_y/angle_deg every time it's called and picks the
        -- cheapest matching GPU command itself -- it no longer matters
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
        spr(player_region, player_x + 32, player_y, 1.0, 1.0, spin_angle)

        -- Only scale differs (a horizontal mirror via negative scale_x) ->
        -- GPUCommand_DrawRegionZoomed.
        local scale_x = facing_left and -1.0 or 1.0
        spr(player_region, player_x + 64, player_y, scale_x, 1.0)

        -- Both scale and angle differ -> GPUCommand_DrawRegionRotozoomed,
        -- now with color_mult/blend_mode also applied.
        spr(player_region, player_x + 96, player_y,
            scale_x, 1.0, spin_angle, 0xFFFFFFFF, 0x20)

        ioports.gpu.sync()   -- WAIT for vsync -- required once per frame in main()
    end
end
