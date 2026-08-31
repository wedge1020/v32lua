--#title "sound demo"
--#sound MUSIC "music.vsnd"
--#sound BLIP  "blip.vsnd"

ioports.spu.volume = 0.50          -- global volume

function main()
    -- folds to 6 instructions, no CALL:
    --   OUT SPU_SelectedChannel, 0
    --   OUT SPU_ChannelAssignedSound, 0
    --   MOV R1, 1.000000 / OUT SPU_ChannelVolume, R1
    --   OUT SPU_ChannelLoopEnabled, 1
    --   OUT SPU_Command, SPUCommand_PlaySelectedChannel
    play(MUSIC, 0, true)

    local sfx_channel = 1

    while true do
        ioports.gpu.clear("black")
        if btnp(5) then
            play(BLIP, sfx_channel, false, 0.8)   -- still fully folded
        end

        if btnp(4) then
            pause(0)                              -- pause the music only
        end
        if btnp(6) then
            resume(0)                             -- pick it back up
        end
        if btnp(8) then
            stop()                                -- hard stop, all channels
        end

        system.wait()
    end
end

-- Other shapes:
--   local ch = play(MUSIC)              -- ch == 0.0
--   play(MUSIC, ch, true, 1.0, 44100)   -- seek 1s in at 44.1kHz
--   stop(ch)

-- ---------------------------------------------------------------------
-- Lower-level control, for sequences play()/stop()/pause()/resume()
-- don't cover. cmd() acts on whatever SPU_SelectedChannel names and
-- does no defaulting of its own.
-- ---------------------------------------------------------------------
function crossfade_to(sound)
    ioports.spu.channel    = 0
    ioports.spu.chanvolume = 0.0
    ioports.spu.chansound  = sound
    ioports.spu.chanloop   = true
    ioports.spu.cmd("play")

    for v = 0, 10 do
        ioports.spu.chanvolume = v / 10
        system.wait()
    end
end

function check_gamepad()
    -- ioports.inp.status is now a real boolean: true only when a
    -- gamepad is actually connected.
    if ioports.inp.status then
        print(0, 0, "gamepad connected")
    else
        print(0, 0, "no gamepad")
    end
end
