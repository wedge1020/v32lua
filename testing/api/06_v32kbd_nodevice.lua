--#title "[v32lua] v32kbd keyboard, no device, unit test"
--#keyboard 1

--@ Vircon32 Lua v32kbd keyboard Unit Test -- without a device
--@ key()/keyp()/kbd.* read a v32kbd keyboard (a USB keyboard the console
--@ sees as a gamepad). This test runs with NOTHING plugged into the
--@ keyboard's port, so it checks the "no keyboard" answers, the port
--@ handling, and that the keyboard never disturbs the gamepad the
--@ program has selected (the runtime remembers the selection in
--@ V32IO_GAMEPAD: the emulators can't read INP_SelectedGamepad back).
--@ Key events need a v32io device -- the hardware adapter or the modified
--@ emulator (github.com/wedge1020/ComputerSoftware, branch v32io): see
--@ doc/API.md, "Keyboard and mouse: what you need".
--@
--@ --#keyboard 1 above: the keyboard's default port is 1 in this test
--@ (not the built-in default, 2, so the hint is what's being checked).

function main()
    -- === Test 00: --#keyboard sets the default port ===
    number_result00 = kbd.port()                    -- Expected: 1
    __rawasm__("__debug00:")

    -- === Test 01-04: no key down, nothing typed ===
    bool_result01 = key("a")                        -- Expected: false
    bool_result02 = key()                           -- Expected: false
    bool_result03 = keyp("shift", 10, 5)            -- Expected: false
    bool_result04 = (kbd.read() == nil)             -- Expected: true
    __rawasm__("__debug01:")

    -- === Test 05-06: events, caps lock ===
    bool_result05 = (kbd.event() == nil)            -- Expected: true
    bool_result06 = kbd.capslock()                  -- Expected: false
    __rawasm__("__debug05:")

    -- === Test 07: kbd.port(n) sets and returns, clamped to 0-3 ===
    number_result07 = kbd.port(9)                   -- Expected: 3
    __rawasm__("__debug07:")

    -- === Test 08: nothing plugged into port 3 ===
    bool_result08 = kbd.connected()                 -- Expected: false
    __rawasm__("__debug08:")

    -- === Test 09: the program's gamepad selection survives keyboard reads ===
    ioports.inp.gamepad = 1
    kbd.clear()
    local unused = key("enter")
    number_result09 = ioports.inp.gamepad           -- Expected: 1
    __rawasm__("__debug09:")

    -- === Test 10: an out-of-range selection is ignored, as by the hardware ===
    ioports.inp.gamepad = 7
    number_result10 = ioports.inp.gamepad           -- Expected: 1
    __rawasm__("__debug10:")

    while true do
        system.wait()                               -- reads the keyboard too
    end
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 1.0000
bool_result01: false
bool_result02: false
bool_result03: false
bool_result04: true
bool_result05: true
bool_result06: false
number_result07: 3.0000
bool_result08: false
number_result09: 1.0000
number_result10: 1.0000
]]
