--#title "v32lua SPU channel state and playback unit test"
--@ Vircon32 Lua audio unit test -- lib/audio.lua half 2 of 2
--@ Exercises the channel half of audio.h: the channel_stopped/
--@ channel_paused/channel_playing constants and sound_channels,
--@ get_channel_state / get_channel_speed / get_channel_position,
--@ set_channel_position, assign_channel_sound, play_sound_in_channel,
--@ and play_sound's stopped-channel search.
--@
--@ v32sim properties this is written against (all confirmed against
--@ the simulator): every channel reads channel_stopped (0x40) with
--@ default speed 1 and position 0; the SPU Play/Pause/Stop commands
--@ are accepted but do NOT transition channel state in the emulator
--@ (on hardware play_channel would move the channel to playing), and
--@ volume/speed/loop writes are not retained for reading. So the
--@ playback commands at the bottom are smoke calls -- verified to
--@ compile and run without halting, with nothing scraped -- while
--@ everything with an observable register effect is asserted above.
--@ play_sound(17) returns 0 because channel 0 is the first stopped
--@ channel it finds; on hardware with channel 0 busy it would hand
--@ back the next free one (or -1 when all 16 are busy -- unreachable
--@ in v32sim, where states never leave stopped).

--#include "../../lib/audio.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: constants from audio.h ===
    number_channels_const  = sound_channels    -- 16
    number_stopped_const   = channel_stopped   -- 0x40 = 64
    number_paused_const    = channel_paused    -- 0x41 = 65
    number_playing_const   = channel_playing   -- 0x42 = 66

    -- === Test 2: fresh channel defaults, read BEFORE any writes ===
    number_chsound_none   = ioports.spu.chansound  -- -1: nothing assigned
    number_state_ch0      = get_channel_state(0)   -- 64: stopped
    number_state_ch15     = get_channel_state(15)  -- 64: last channel too
    boolean_state_stopped = (get_channel_state(3) == channel_stopped)
    number_speed_default  = get_channel_speed(5)   -- 1: normal speed
    number_pos_default    = get_channel_position(5) -- 0: at sound start

    -- === Test 3: set_channel_position / get_channel_position round ===
    -- === trip. set_channel_* follow audio.h's select-then-act shape: ===
    -- === they take only the value and act on the SELECTED channel, so ===
    -- === channel 2 is selected first (same-channel round trip only: ===
    -- === v32sim keeps one shared position register rather than ===
    -- === per-channel storage) ===
    select_channel(2)
    set_channel_position(100)
    number_pos_roundtrip = get_channel_position(2)  -- 100

    -- === Test 4: assign_channel_sound -- selects, then assigns ===
    assign_channel_sound(4, 9)
    number_assigned_ch    = ioports.spu.channel   -- 4 (selected as a side effect)
    number_assigned_sound = ioports.spu.chansound -- 9

    -- === Test 5: play_sound_in_channel -- same writes plus Play ===
    play_sound_in_channel(5, 3)
    number_psch_ch    = ioports.spu.channel   -- 3
    number_psch_sound = ioports.spu.chansound -- 5

    -- === Test 6: play_sound -- searches for a stopped channel ===
    number_playsound_ch    = play_sound(17)      -- 0: first stopped channel
    number_playsound_sound = ioports.spu.chansound  -- 17: assigned there

    -- === Test 7: playback commands -- smoke calls; v32sim accepts ===
    -- === the SPU commands but never moves state away from stopped, ===
    -- === so there is nothing observable to scrape (see header). The ===
    -- === set_channel_* calls select their channel first, per the ===
    -- === select-then-act convention ===
    play_channel(6)
    pause_channel(6)
    stop_channel(6)
    pause_all_channels()
    resume_all_channels()
    stop_all_channels()
    select_channel(6)
    set_channel_volume(0.5)
    set_channel_speed(1.5)
    set_channel_loop(true)

    print(10, 0,   "--- SPU channels/playback unit test ---")
    print(10, 20,  "channels/stopped/paused/playing: " .. number_channels_const
                   .. "/" .. number_stopped_const
                   .. "/" .. number_paused_const
                   .. "/" .. number_playing_const)
    print(10, 40,  "state ch0/ch15: " .. number_state_ch0
                   .. "/" .. number_state_ch15)
    print(10, 60,  "speed/pos defaults: " .. number_speed_default
                   .. "/" .. number_pos_default)
    print(10, 80,  "play_sound(17) -> channel " .. number_playsound_ch
                   .. " with sound " .. number_playsound_sound)
end

--[[
=== EXPECTED OUTPUT ===

number_channels_const: 16.0000
number_stopped_const: 64.0000
number_paused_const: 65.0000
number_playing_const: 66.0000
number_chsound_none: -1.0000
number_state_ch0: 64.0000
number_state_ch15: 64.0000
boolean_state_stopped: true
number_speed_default: 1.0000
number_pos_default: 0.0000
number_pos_roundtrip: 100.0000
number_assigned_ch: 4.0000
number_assigned_sound: 9.0000
number_psch_ch: 3.0000
number_psch_sound: 5.0000
number_playsound_ch: 0.0000
number_playsound_sound: 17.0000

--]]
