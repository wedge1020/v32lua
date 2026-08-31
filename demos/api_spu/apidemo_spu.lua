--#title "sound demo"
--#sound MUSIC "music.vsnd"
--#sound BLIP  "blip.vsnd"

ioports.spu.volume = 0.50          -- global volume (0-2)

-- Optional: the short names are no longer built in, because play/pause/
-- resume/stop are exactly the identifiers a game is most likely to want for
-- itself. Declaring them is a compile-time alias -- play(...) below compiles
-- to the identical inline OUT sequence music.play(...) would have.
play = music.play

function main()
    -- Channel 0 is the music channel. sfx.play() with no channel
    -- round-robins over 1-15, so effects never cut the music off.
    play(MUSIC, 0, true)

    while true do
        ioports.gpu.clear("black")

        if btnp(5) then                       -- A: fire a sound effect
            sfx.play(BLIP)
        end

        if btnp(4) then                       -- Start: pause <-> resume
            -- Ask the hardware, not a Lua flag. A flag drifts the moment a
            -- sound ends on its own: the program still thinks it is playing,
            -- and the next press pauses an already-stopped channel instead
            -- of resuming it. SPU_ChannelState cannot drift.
            if music.playing(0) then
                music.pause(0)
            else
                music.resume(0)
            end
        end

        if btnp(6) then                       -- B: quieter effect, lower pitch
            sfx.play(BLIP, nil, 0.5, 0.75)
        end

        if btnp(8) then                       -- Y: silence effects only
            sfx.stop()                        -- music on channel 0 keeps going
        end

        if btnp(7) then                       -- X: stop everything
            music.stop()
            sfx.stop()
        end

        system.wait()
    end
end
