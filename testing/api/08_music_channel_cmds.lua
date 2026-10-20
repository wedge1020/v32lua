--#title "[v32lua] music.pause/resume/stop channel command unit test"
--@ Vircon32 Lua music.* Unit Test -- pause() / resume() / stop() command emission
--@ Self-checking coverage of the SPU command each form sends and the channel it
--@ selects, read back from the SPU_Command / SPU_SelectedChannel ports:
--@   pause  ()  PauseAllChannels 0x33     pause  (ch) PauseSelectedChannel 0x31
--@   resume ()  ResumeAllChannels 0x34    resume (ch) PlaySelectedChannel  0x30
--@   stop   ()  StopAllChannels   0x35    stop   (ch) StopSelectedChannel  0x32
--@ and, for a channel that is a variable, the run-time rules: nil means all
--@ channels, the number is truncated and clamped to 0-15.
--@
--@ REGRESSION: the dynamic-channel form once emitted "MOV R0, SPUCommand_..."
--@ -- the SPUCommand_* names are only valid as OUT operands, so the cart did
--@ not assemble (and no test used a variable channel, so nothing noticed).
--@
--@ resume(ch) sends Play ONLY to a channel whose state is PAUSED (0x41):
--@ PlayChannel() restarts a stopped channel and retriggers a playing one from
--@ position 0, which is not "resume". SPU_ChannelState is read-only on the
--@ console; simulators keep it as plain storage, so this test sets it with raw
--@ OUTs. SPU_Command is write-only on the console -- read back here only
--@ because the simulators store it. NOT a cart for real hardware.

last_cmd = 0

function clear_cmd()
    __rawasm__("MOV R0, 0\nOUT SPU_Command, R0")
end

function read_cmd()
    __rawasm__("IN R0, SPU_Command\nCIF R0\nMOV {last_cmd}, R0")
end

function set_state(s)
    -- s: 64 stopped, 65 paused, 66 playing
    __rawasm__("MOV R0, {s}\nCFI R0\nOUT SPU_ChannelState, R0")
end

function test_music_channel_cmds()
    local live = 321

    -- === Tests 00-02: no channel -> the all-channels commands ===
    clear_cmd()
    music.pause()
    read_cmd()
    number_result00 = last_cmd          -- 0x33 = 51
    clear_cmd()
    music.resume()
    read_cmd()
    number_result01 = last_cmd          -- 0x34 = 52
    clear_cmd()
    music.stop()
    read_cmd()
    number_result02 = last_cmd          -- 0x35 = 53
    __rawasm__("__debug02:")

    -- === Tests 03-05: literal channel -> per-channel command + channel ===
    clear_cmd()
    music.pause(3)
    read_cmd()
    number_result03 = last_cmd          -- 0x31 = 49
    number_result04 = ioports.spu.channel   -- 3
    clear_cmd()
    music.stop(5)
    read_cmd()
    number_result05 = last_cmd          -- 0x32 = 50
    __rawasm__("__debug05:")

    -- === Tests 06-08: VARIABLE channel (the form that did not assemble) ===
    local c4 = 4
    clear_cmd()
    music.pause(c4)
    read_cmd()
    number_result06 = last_cmd          -- 49
    number_result07 = ioports.spu.channel   -- 4
    clear_cmd()
    music.stop(c4)
    read_cmd()
    number_result08 = last_cmd          -- 50
    __rawasm__("__debug08:")

    -- === Tests 09-10: nil variable -> all channels ===
    local cnil = nil
    clear_cmd()
    music.pause(cnil)
    read_cmd()
    number_result09 = last_cmd          -- 51
    clear_cmd()
    music.stop(cnil)
    read_cmd()
    number_result10 = last_cmd          -- 53
    __rawasm__("__debug10:")

    -- === Tests 11-13: clamp and truncate ===
    local hi, lo, fr = 99, -5, 2.7
    music.pause(hi)
    number_result11 = ioports.spu.channel   -- 15
    music.pause(lo)
    number_result12 = ioports.spu.channel   -- 0
    music.pause(fr)
    number_result13 = ioports.spu.channel   -- 2
    __rawasm__("__debug13:")

    -- === Tests 14-17: resume(ch) on a PAUSED channel -> Play (0x30 = 48) ===
    set_state(65)
    clear_cmd()
    music.resume(3)
    read_cmd()
    number_result14 = last_cmd          -- 48
    clear_cmd()
    music.resume(c4)
    read_cmd()
    number_result15 = last_cmd          -- 48
    number_result16 = ioports.spu.channel   -- 4
    clear_cmd()
    music.resume(cnil)                  -- nil -> ResumeAllChannels
    read_cmd()
    number_result17 = last_cmd          -- 52
    __rawasm__("__debug17:")

    -- === Tests 18-21: resume(ch) on a PLAYING or STOPPED channel -> no ===
    -- === command at all (Play would retrigger / restart it from 0)    ===
    set_state(66)
    clear_cmd()
    music.resume(3)
    music.resume(c4)
    read_cmd()
    number_result18 = last_cmd          -- 0: nothing was sent
    set_state(64)
    clear_cmd()
    music.resume(3)
    music.resume(c4)
    read_cmd()
    number_result19 = last_cmd          -- 0
    number_result20 = ioports.spu.channel   -- 4: the channel was still selected
    __rawasm__("__debug20:")

    -- === Test 21: caller state survives every form above ===
    number_result21 = live              -- 321
    __rawasm__("__debug21:")
end

function main()
    test_music_channel_cmds()
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 51.0000
number_result01: 52.0000
number_result02: 53.0000
number_result03: 49.0000
number_result04: 3.0000
number_result05: 50.0000
number_result06: 49.0000
number_result07: 4.0000
number_result08: 50.0000
number_result09: 51.0000
number_result10: 53.0000
number_result11: 15.0000
number_result12: 0.0000
number_result13: 2.0000
number_result14: 48.0000
number_result15: 48.0000
number_result16: 4.0000
number_result17: 52.0000
number_result18: 0.0000
number_result19: 0.0000
number_result20: 4.0000
number_result21: 321.0000
]]
