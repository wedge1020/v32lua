--#title "[v32lua] v32mouse, no device, unit test"
--#mouse 2

--@ Vircon32 Lua v32mouse Unit Test -- without a device
--@ mouse()/mouse.* read a v32mouse (a USB mouse the console sees as a
--@ gamepad). This test runs with NOTHING plugged into the mouse's port, so
--@ it checks the "no mouse" answers, the pointer's own state (position,
--@ bounds, scale) and the 7 values of mouse(). Movement needs a device (or
--@ a simulated one): see doc/API.md.
--@
--@ --#mouse 2 above: the mouse's default port is 2 in this test.

function main()
    -- === Test 00: --#mouse sets the default port ===
    number_result00 = mouse.port()                  -- Expected: 2
    __rawasm__("__debug00:")

    -- === Test 01-07: mouse(): pointer at the screen's center, no buttons ===
    local x, y, l, m, r, sx, sy = mouse()
    number_result01 = x                             -- Expected: 320
    number_result02 = y                             -- Expected: 180
    bool_result03 = l                               -- Expected: false
    bool_result04 = m                               -- Expected: false
    bool_result05 = r                               -- Expected: false
    number_result06 = sx                            -- Expected: 0
    number_result07 = sy                            -- Expected: 0
    __rawasm__("__debug01:")

    -- === Test 08: mouse() gives 7 values in a list ===
    local t = {mouse()}
    number_result08 = #t                            -- Expected: 7
    __rawasm__("__debug08:")

    -- === Test 09-11: no movement, no buttons, no device ===
    local dx, dy = mouse.delta()
    number_result09 = dx + dy                       -- Expected: 0
    bool_result10 = mouse.pressed()                 -- Expected: false
    bool_result11 = mouse.connected()               -- Expected: false
    __rawasm__("__debug09:")

    -- === Test 12-13: bounds pull the pointer inside ===
    mouse.bounds(0, 0, 99, 49)
    local px, py = mouse.position()
    number_result12 = px                            -- Expected: 99
    number_result13 = py                            -- Expected: 49
    __rawasm__("__debug12:")

    -- === Test 14-15: position() places it, floored and kept within bounds ===
    local qx, qy = mouse.position(10.7, 500)
    number_result14 = qx                            -- Expected: 10
    number_result15 = qy                            -- Expected: 49
    __rawasm__("__debug14:")

    -- === Test 16-17: scale: default 2, set to 5, 0 is refused ===
    number_result16 = mouse.scale()                 -- Expected: 2
    mouse.scale(5)
    number_result17 = mouse.scale(0)                -- Expected: 5
    __rawasm__("__debug16:")

    -- === Test 18: buttons held ===
    number_result18 = mouse.buttons()               -- Expected: 0
    __rawasm__("__debug18:")

    while true do
        system.wait()                               -- reads the mouse too
    end
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 2.0000
number_result01: 320.0000
number_result02: 180.0000
bool_result03: false
bool_result04: false
bool_result05: false
number_result06: 0.0000
number_result07: 0.0000
number_result08: 7.0000
number_result09: 0.0000
bool_result10: false
bool_result11: false
number_result12: 99.0000
number_result13: 49.0000
number_result14: 10.0000
number_result15: 49.0000
number_result16: 2.0000
number_result17: 5.0000
number_result18: 0.0000
]]
