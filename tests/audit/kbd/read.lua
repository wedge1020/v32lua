--#keyboard 0
--@ v32kbd typed characters: drains kbd.read() every frame into LOG (with its
--@ kbd.glyph() in GLY), counts what it read in N. Driven by kbd_text.py,
--@ which feeds a scripted v32kbd event stream through gamepad 0.
LOG = {}
GLY = {}
N = 0
HELD_A = false
function main()
    while true do
        local c = kbd.read()
        while c do
            LOG[N] = c
            local g = kbd.glyph(c)
            if g then GLY[N] = g else GLY[N] = -1 end
            N = N + 1
            c = kbd.read()
        end
        HELD_A = key("a")
        system.wait()
    end
end
