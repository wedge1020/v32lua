--#title "v32lua mouse demo"

-- v32mouse demo: draw on screen with the mouse (a port of the v32io
-- library's v32mouse.c test program), drawn with rect()/rectfill().
--
--   left button:   hold to draw
--   right button:  clear the drawing
--   middle button: change the drawing color
--
-- NEEDS A v32io MOUSE: the v32io hardware adapter with a USB mouse (any
-- Vircon32 emulator, with a joystick profile for "v32io:mouse"), or a
-- modified emulator (github.com/wedge1020/ComputerSoftware, branch v32io,
-- or the stock emulator with the v32io patches). Without one, the pointer
-- never moves. See doc/API.md,
-- "Keyboard and mouse: what you need".
--
-- The mouse is expected in the FOURTH gamepad port (port 3, the default):
-- in the modified emulator, pick "v32mouse" in menu Gamepads > Gamepad 4;
-- with the adapter, select the "v32io:mouse" profile for Gamepad 4. Another
-- port: --#mouse N at the top of this file, or mouse.port(N).

DOTS_MAX = 500

palette = { rgba(255, 255, 255), rgba(255, 64, 64), rgba(64, 255, 64), rgba(255, 255, 64) }
color   = 1                           -- index into palette
dots    = 0
dotx, doty, dotcolor = {}, {}, {}
lastdx, lastdy = 0, 0

function main()
    while true do
        local x, y, left, middle, right = mouse()

        -- movement in this frame: only update the shown values when the
        -- mouse moved, so that they can be read
        local dx, dy = mouse.delta()
        if dx ~= 0 or dy ~= 0 then
            lastdx, lastdy = dx, dy
        end

        if mouse.pressed(2) then          -- right: clear
            dots = 0
        end
        if mouse.pressed(4) then          -- middle: next color
            color = color % 4 + 1
        end
        if left and dots < DOTS_MAX then  -- left held: draw
            dotx[dots], doty[dots], dotcolor[dots] = x, y, color
            dots = dots + 1
        end

        ioports.gpu.clear(rgba(0, 0, 0))

        for i = 0, dots - 1 do
            local c = palette[dotcolor[i]]
            rectfill(dotx[i] - 1, doty[i] - 1, dotx[i] + 1, doty[i] + 1, c)
        end

        print(0, 0, "X: " .. x .. "  Y: " .. y .. "  DX: " .. lastdx .. "  DY: " .. lastdy)
        print(400, 0, "[L] [M] [R]")
        if left   then rectfill(410, 20, 419, 23, rgba(0, 255, 255)) end
        if middle then rectfill(450, 20, 459, 23, rgba(0, 255, 255)) end
        if right  then rectfill(490, 20, 499, 23, rgba(0, 255, 255)) end
        rectfill(530, 4, 545, 19, palette[color])

        if not mouse.connected() then
            print(4, 340, "no mouse in gamepad port " .. mouse.port())
        end

        -- the pointer: a small cross
        rect(x - 4, y, x + 4, y, rgba(0, 255, 255))
        rect(x, y - 4, x, y + 4, rgba(0, 255, 255))

        system.wait()                    -- also reads the mouse
    end
end
