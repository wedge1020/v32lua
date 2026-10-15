--#keyboard 0
--@ v32kbd typed characters: drains kbd.event() every frame into LOG (+code
--@ press, -code release), counting them in N, and follows key("a") in
--@ HELD_A. Driven by kbd_text.py (a scripted v32kbd event stream on gamepad 0).
LOG = {}
N = 0
HELD_A = false
function main()
    while true do
        local e = kbd.event()
        while e do
            LOG[N] = e
            N = N + 1
            e = kbd.event()
        end
        HELD_A = key("a")
        system.wait()
    end
end
