--#title "v32lua keyboard demo"

-- v32kbd keyboard demo: type text on screen (a port of the v32kbd C
-- library's v32kbd.c test program), with rect()/rectfill() for the frame,
-- the cursor and the modifier lights.
--
-- NEEDS A v32io KEYBOARD: the v32io hardware adapter with a USB keyboard
-- (any Vircon32 emulator, with a joystick profile for "v32io:kbd"), or a
-- modified emulator (github.com/wedge1020/ComputerSoftware, branch v32io,
-- or the stock emulator with the v32io patches). Without one, nothing can
-- be typed. See doc/API.md, "Keyboard and mouse:
-- what you need".
--
-- The keyboard is expected in the THIRD gamepad port (port 2, the
-- default): in the modified emulator, pick "v32kbd" in menu Gamepads >
-- Gamepad 3; with the adapter, select its profile for Gamepad 3.
-- Another port: --#keyboard N at the top of this file, or kbd.port(N).

TEXT_MAX = 600

text   = ""
last   = 0

-- one modifier light: a box, filled while the key is held
function light(x, label, held)
    print(x, 4, label)
    if held then
        rectfill(x + 60, 4, x + 75, 19, rgba(255, 200, 0))
    end
    rect(x + 60, 4, x + 75, 19, rgba(160, 160, 160))
end

function main()
    while true do
        -- every key press, as the character it types
        local c = kbd.read()
        while c do
            last = c
            if c == 8 then                                  -- Backspace
                text = string.sub(text, 1, -2)
            elseif #text < TEXT_MAX - 4 then
                if c == 13 then                             -- Enter
                    text = text .. "\n"
                elseif c == 9 then                          -- Tab
                    text = text .. "    "
                elseif c >= 32 and c < 127 then
                    text = text .. string.char(c)
                end
            end
            c = kbd.read()
        end

        ioports.gpu.clear(rgba(16, 16, 40))

        print(4, 4, "LAST KEY: " .. last)
        light(200, "SHIFT", key("shift"))
        light(300, "CTRL",  key("ctrl"))
        light(400, "ALT",   key("alt"))
        light(500, "CAPS",  kbd.capslock())

        if not kbd.connected() then
            print(4, 340, "no keyboard in gamepad port " .. kbd.port())
        end

        rect(0, 28, 639, 359, rgba(90, 90, 140))
        print(8, 36, text .. "_")

        system.wait()                   -- also reads the keyboard
    end
end
