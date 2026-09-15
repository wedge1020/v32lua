--#title "v32lua SPU selection and configuration unit test"
--@ Vircon32 Lua audio unit test -- lib/audio.lua half 1 of 2
--@ Exercises the selection and configuration half of audio.h:
--@ select_sound/select_channel with their get_selected_* readbacks,
--@ the per-sound loop configuration (set_sound_loop, set_sound_loop_
--@ start, set_sound_loop_end -- all confirmed readable back through
--@ ioports.spu in v32sim), and the global volume pair.
--@
--@ All DEFAULT reads happen before any configuration writes on
--@ purpose: v32sim keeps the selected-sound register at -1 ("none")
--@ and the selected channel at 0 on a fresh cart, and the global
--@ volume reads 1 until it is written. The one deliberate smoke
--@ call at the end (set_global_volume) is NOT followed by a readback
--@ because v32sim does not retain SPU volume writes for reading --
--@ on real hardware the write lands; here only the call itself
--@ (compile + port write, no crash) can be verified.

--#include "../../lib/audio.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: fresh-cart defaults, read BEFORE any writes ===
    number_gvol_default   = get_global_volume()   -- 1: full volume
    number_selsound_none  = get_selected_sound()  -- -1: no sound selected
    number_selch_default  = get_selected_channel() -- 0

    -- === Test 2: select_sound / select_channel round-trips ===
    select_sound(3)
    number_selsound_after = get_selected_sound()   -- 3

    select_channel(7)
    number_selch_after = get_selected_channel()    -- 7

    -- === Test 3: per-sound loop configuration, written through the ===
    -- === library, read back through the raw ioports ===
    select_sound(2)  -- the configuration below applies to sound 2

    set_sound_loop(true)
    boolean_soundloop_on = ioports.spu.soundloop    -- true

    set_sound_loop(false)
    boolean_soundloop_off = ioports.spu.soundloop   -- false

    set_sound_loop_start(1000)
    number_loopstart = ioports.spu.loopstart        -- 1000 (samples)

    set_sound_loop_end(2000)
    number_loopend = ioports.spu.loopend            -- 2000 (samples)

    -- === Test 4: set_global_volume -- smoke call only; v32sim does ===
    -- === not keep volume writes readable, so nothing is scraped ===
    set_global_volume(0.5)

    print(10, 0,   "--- SPU selection/configuration unit test ---")
    print(10, 20,  "defaults sound/channel/volume: " .. number_selsound_none
                   .. "/" .. number_selch_default
                   .. "/" .. number_gvol_default)
    print(10, 40,  "selected after writes: " .. number_selsound_after
                   .. "/" .. number_selch_after)
    print(10, 60,  "sound loop on/off: " .. tostring(boolean_soundloop_on)
                   .. "/" .. tostring(boolean_soundloop_off))
    print(10, 80,  "loop start/end: " .. number_loopstart
                   .. "/" .. number_loopend)
end

--[[
=== EXPECTED OUTPUT ===

number_gvol_default: 1.0000
number_selsound_none: -1.0000
number_selch_default: 0.0000
number_selsound_after: 3.0000
number_selch_after: 7.0000
boolean_soundloop_on: true
boolean_soundloop_off: false
number_loopstart: 1000.0000
number_loopend: 2000.0000

--]]
