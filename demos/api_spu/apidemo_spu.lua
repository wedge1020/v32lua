--#title "sound demo"
--#sound MUSIC "music.vsnd"
--#sound BLIP  "blip.vsnd"

ioports.spu.volume = 0.50          -- global volume

function main()
    -- Channel 0 is the music channel, channel 1 is the sfx channel.
    -- Keeping them separate is what makes pause(0)/resume(0) meaningful:
    -- they act on ONE channel, so a blip on channel 1 is unaffected.
    play(MUSIC, 0, true)

    local sfx_channel = 1

    while true do
        ioports.gpu.clear("black")

        if btnp(5) then                                -- A
            play(BLIP, sfx_channel, false, 0.8)
        end

        if btnp(4) then                                -- Start
            pause(0)                                   -- pause the music
        end
        if btnp(6) then                                -- B
            resume(0)                                  -- pick it back up
        end
        if btnp(8) then                                -- Y
            stop()                                     -- hard stop, all channels
        end

        system.wait()
    end
end
