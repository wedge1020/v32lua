-- spu_helpers.lua
--
-- v32lua port of the per-sound / per-channel SPU convenience functions
-- from the Vircon32 C standard library's audio.h. These are thin
-- wrappers over ioports.spu.* and ioports.spu.cmd() -- v32lua already
-- exposes every port audio.h used, this just restores the C-style
-- "select + act" call shapes so ported C code (or C-literate authors)
-- don't have to hand-write the ioports.spu.channel = ... dance
-- everywhere.
--
-- This is a companion to the compiler's own music.*/sfx.* namespaces,
-- not a replacement: those give you channel bookkeeping (auto
-- round-robin, a reserved music channel, boolean-safe loop handling)
-- for free. Reach for these instead when you want raw C-style control,
-- e.g. porting existing Vircon32 C audio code, or driving channels by
-- hand outside what music/sfx assume.
--
-- IMPORTANT -- port write ordering (see vircon32-spu-port-ordering.md):
--   * A sound can only be assigned to a STOPPED channel; assigning to a
--     playing/paused channel is silently dropped by the hardware.
--   * The Play command overwrites both the channel's loop flag and its
--     position, using the SOUND's own loop flag as the new value. Any
--     set_channel_loop()/set_channel_position() call meant to override
--     that must happen AFTER play_channel(), never before.
-- audio.h's own functions don't handle this for you either (it's a
-- hardware behavior, not a library bug) -- these ports are exactly as
-- faithful, and exactly as easy to misuse, as the C originals. Callers
-- driving channels by hand still need to know the rule.

-- ---------------------------------------------------------------------------
--   GENERAL DEFINITIONS
-- ---------------------------------------------------------------------------

sound_channels = 16

-- states of a sound channel
channel_stopped = 0x40
channel_paused  = 0x41
channel_playing = 0x42

-- ---------------------------------------------------------------------------
--   SPU SELECTED ELEMENTS
-- ---------------------------------------------------------------------------

function select_sound(soundId)
    ioports.spu.sound = soundId
end

function select_channel(channelId)
    ioports.spu.channel = channelId
end

function get_selected_sound()
    return ioports.spu.sound
end

function get_selected_channel()
    return ioports.spu.channel
end

-- ---------------------------------------------------------------------------
--   CONFIGURATION OF SPU SOUNDS (applies to the currently selected sound)
-- ---------------------------------------------------------------------------

function set_sound_loop(enabled)
    ioports.spu.soundloop = enabled
end

-- position is given from sound start, in samples
function set_sound_loop_start(position)
    ioports.spu.loopstart = position
end

-- position is given from sound start, in samples
function set_sound_loop_end(position)
    ioports.spu.loopend = position
end

-- ---------------------------------------------------------------------------
--   CONFIGURATION OF SPU CHANNELS (applies to the currently selected channel)
-- ---------------------------------------------------------------------------

function set_channel_volume(volume)
    ioports.spu.chanvolume = volume
end

function set_channel_speed(speed)
    ioports.spu.chanspeed = speed
end

-- write AFTER play_channel() if it's meant to seek a just-started sound --
-- the Play command resets position to 0.
function set_channel_position(position)
    ioports.spu.chanpos = position
end

-- write AFTER play_channel() if it's meant to override the sound's own
-- loop flag -- the Play command overwrites this with SOUND.PlayWithLoop.
function set_channel_loop(enabled)
    ioports.spu.chanloop = enabled
end

-- selects channelId, then assigns soundId to it. Per the hardware rule
-- above, this only takes effect if channelId is currently stopped;
-- stop_channel(channelId) first if that isn't guaranteed.
function assign_channel_sound(channelId, soundId)
    ioports.spu.channel = channelId
    ioports.spu.chansound = soundId
end

-- ---------------------------------------------------------------------------
--   QUERYING STATE OF SPU CHANNELS
-- ---------------------------------------------------------------------------

function get_channel_speed(channelId)
    ioports.spu.channel = channelId
    return ioports.spu.chanspeed
end

function get_channel_position(channelId)
    ioports.spu.channel = channelId
    return ioports.spu.chanpos
end

-- returns channel_stopped / channel_paused / channel_playing
function get_channel_state(channelId)
    ioports.spu.channel = channelId
    return ioports.spu.state
end

-- ---------------------------------------------------------------------------
--   GLOBAL SPU PARAMETERS
-- ---------------------------------------------------------------------------

-- range is 0 to 2
function set_global_volume(volume)
    ioports.spu.volume = volume
end

function get_global_volume()
    return ioports.spu.volume
end

-- ---------------------------------------------------------------------------
--   SINGLE-CHANNEL SPU COMMANDS
-- ---------------------------------------------------------------------------

function play_channel(channelId)
    ioports.spu.channel = channelId
    ioports.spu.cmd("play")
end

function pause_channel(channelId)
    ioports.spu.channel = channelId
    ioports.spu.cmd("pause")
end

function stop_channel(channelId)
    ioports.spu.channel = channelId
    ioports.spu.cmd("stop")
end

-- ---------------------------------------------------------------------------
--   ALL-CHANNEL SPU COMMANDS
-- ---------------------------------------------------------------------------

function pause_all_channels()
    ioports.spu.cmd("pauseall")
end

function stop_all_channels()
    ioports.spu.cmd("stopall")
end

-- there is no per-channel resume command on real hardware -- ResumeAll
-- is a genuine SPU command, but resuming a single paused channel is
-- play_channel() on that channel (see vircon32-spu-port-ordering.md).
function resume_all_channels()
    ioports.spu.cmd("resumeall")
end

-- ---------------------------------------------------------------------------
--   PRACTICAL SOUND-PLAY FUNCTIONS
-- ---------------------------------------------------------------------------

-- selects channelId, assigns soundId, and plays it -- same caveat as
-- assign_channel_sound(): the assignment is dropped unless channelId
-- is already stopped.
function play_sound_in_channel(soundId, channelId)
    ioports.spu.channel = channelId
    ioports.spu.chansound = soundId
    ioports.spu.cmd("play")
end

-- Searches channels 0..sound_channels-1 for the first STOPPED one,
-- assigns soundId to it and plays it, returning the channel used (or
-- -1 if every channel is busy). This is a straight port of audio.h's
-- play_sound(): it costs up to sound_channels port reads in the worst
-- case, same tradeoff the compiler's own sfx.play() deliberately
-- avoids by round-robining instead (see vircon32-sound-api.md). Reach
-- for this one when you actually need a genuinely free channel and
-- can afford the search; reach for sfx.play() on the hot path.
--
-- Unlike sfx.play(), this does not reserve channel 0 for music -- it
-- will happily hand out channel 0. If you're also using music.play(),
-- keep channel 0 off limits yourself (e.g. start the search at 1).
function play_sound(soundId)
    for channelId = 0, sound_channels - 1 do
        ioports.spu.channel = channelId

        if ioports.spu.state == channel_stopped then
            ioports.spu.chansound = soundId
            ioports.spu.cmd("play")
            return channelId
        end
    end

    return -1
end
