--#api pico8
--@ Vircon32 Lua PICO-8 stat() Unit Test
--@ stat(n) answers every id that maps onto console state: memory (0), CPU
--@ (1), version (5), frame rates (7-9), the sound channels and music
--@ (16-26 / 46-57), the clock (80-85 / 90-95) and the string / nil / false
--@ ids (4, 6, 30, 31, 100, 101, 110); anything else is 0. The devkit mouse
--@ (32-34) is in 27_pico8_stat_mouse.lua. Values that depend on the machine
--@ (memory, CPU, the clock) are checked as ranges and relations.
--@ Results are stored in global variables for automated memory scraping.

local frame = 0
local c0, c1, m0, m1, junk

function _init()
    cpu_init = stat(1)
end

function _update()
    frame = frame + 1
    if frame == 5 then
        c0 = stat(1)
        local x = 0
        for i = 1, 4000 do x = x + i * 2 end
        c1 = stat(1)
        m0 = stat(0)
        junk = {}
        for i = 1, 100 do junk[i] = {i, i} end
        m1 = stat(0)
    end
end

function _draw()
    if frame ~= 5 then return end

    -- fixed answers of this cart (an _update cart: 30 fps)
    number_version = stat(5)
    number_fps_current = stat(7)
    number_fps_target = stat(8)
    number_fps_host = stat(9)
    number_fps_fraction = stat(7.9)

    -- memory (KB): nothing allocated yet reads 0, and it grows with allocation
    boolean_mem_in_use = m0 >= 0 and m0 < 2048 and m1 > 0
    boolean_mem_grows = m1 > m0 and (m1 - m0) < 64

    -- CPU: 0 before the first tick's work, rising with work, sane in _draw
    boolean_cpu_init = cpu_init >= 0 and cpu_init < 8
    boolean_cpu_rises = c1 > c0 and c0 >= 0
    local cpu = stat(1)
    boolean_cpu_draw = cpu >= c1 and cpu < 8
    number_system_cpu = stat(2)

    -- the clock: one clock, so the local ids are the UTC ids
    local y, mo, d = stat(80), stat(81), stat(82)
    local h, mi, s = stat(83), stat(84), stat(85)
    boolean_year = y >= 2020 and y < 2200
    boolean_month = mo >= 1 and mo <= 12
    boolean_day = d >= 1 and d <= 31
    boolean_hour = h >= 0 and h <= 23
    boolean_minute = mi >= 0 and mi <= 59
    boolean_second = s >= 0 and s <= 59
    boolean_integral = y == flr(y) and mo == flr(mo) and d == flr(d) and
                       h == flr(h) and mi == flr(mi) and s == flr(s)
    boolean_local_date = stat(90) == y and stat(91) == mo and stat(92) == d
    boolean_local_time = stat(93) >= 0 and stat(93) <= 23 and
                         stat(94) >= 0 and stat(94) <= 59 and
                         stat(95) >= 0 and stat(95) <= 59

    -- no sound in this cart: every channel idle, no music
    number_sfx0 = stat(46)
    number_sfx3 = stat(49)
    number_sfx_old0 = stat(16)
    number_sfx_old3 = stat(19)
    number_note0 = stat(50)
    number_note_old3 = stat(23)
    number_pattern = stat(54)
    number_pattern_old = stat(24)
    boolean_music = stat(57)
    number_patterns_played = stat(55)
    number_ticks = stat(56)
    number_patterns_played_old = stat(25)
    number_ticks_old = stat(26)

    -- strings, nil and false
    string_clipboard = stat(4)
    string_param = stat(6)
    string_key = stat(31)
    boolean_key_waiting = stat(30)
    boolean_frame_by_frame = stat(110)
    boolean_breadcrumb_nil = stat(100) == nil
    boolean_bbs_nil = stat(101) == nil

    -- everything else is 0
    number_unknown3 = stat(3)
    number_unknown35 = stat(35)
    number_unknown36 = stat(36)
    number_unknown999 = stat(999)
    number_negative = stat(-1)
    number_nil_id = stat(nil)
    number_string_id = stat("x")
    number_no_arg = stat()

    -- stat is a value
    local g = stat
    number_as_value = g(5)
    number_as_value_str = (g(4) == "") and 1 or 0

    -- diagnostics (not checked)
    number_diag_cpu_init = cpu_init
    number_diag_cpu_c0 = c0
    number_diag_cpu_c1 = c1
    number_diag_cpu_draw = cpu
    number_diag_mem0 = m0
    number_diag_mem1 = m1
    number_diag_year = y
    number_diag_hour = h
end

--[[
=== EXPECTED OUTPUT ===

number_version: 43.0000
number_fps_current: 30.0000
number_fps_target: 30.0000
number_fps_host: 60.0000
number_fps_fraction: 30.0000
boolean_mem_in_use: true
boolean_mem_grows: true
boolean_cpu_init: true
boolean_cpu_rises: true
boolean_cpu_draw: true
number_system_cpu: 0.0000
boolean_year: true
boolean_month: true
boolean_day: true
boolean_hour: true
boolean_minute: true
boolean_second: true
boolean_integral: true
boolean_local_date: true
boolean_local_time: true
number_sfx0: -1.0000
number_sfx3: -1.0000
number_sfx_old0: -1.0000
number_sfx_old3: -1.0000
number_note0: -1.0000
number_note_old3: -1.0000
number_pattern: -1.0000
number_pattern_old: -1.0000
boolean_music: false
number_patterns_played: 0.0000
number_ticks: 0.0000
number_patterns_played_old: 0.0000
number_ticks_old: 0.0000
string_clipboard: ""
string_param: ""
string_key: ""
boolean_key_waiting: false
boolean_frame_by_frame: false
boolean_breadcrumb_nil: true
boolean_bbs_nil: true
number_unknown3: 0.0000
number_unknown35: 0.0000
number_unknown36: 0.0000
number_unknown999: 0.0000
number_negative: 0.0000
number_nil_id: 0.0000
number_string_id: 0.0000
number_no_arg: 0.0000
number_as_value: 43.0000
number_as_value_str: 1.0000

--]]
