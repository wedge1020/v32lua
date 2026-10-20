--#title "v32lua date/time translation unit test"
--@ Vircon32 Lua time unit test -- lib/time.lua half 1 of 2
--@ Exercises the pure decomposition half of time.h: translate_date,
--@ translate_time, and the frames_per_second / frame_time constants.
--@
--@ IMPORTANT -- why the leap-year matrix below uses "small" years
--@ (98/100/104): v32lua numbers are 32-bit floats with a 24-bit
--@ mantissa, so a packed date (year * 65536 + day-of-year) is only
--@ exactly representable while the whole value stays under 2^24 --
--@ which holds for every year up to 255. Above that the LITERAL
--@ ITSELF rounds to the nearest float32 BEFORE translate_date ever
--@ runs, and the function then faithfully decodes the rounded value.
--@ The boundary matrix (Feb 28/29, Mar 1, Dec 31, and the century
--@ rule) therefore runs on years 98/100/104 where every input is
--@ exact; two realistic 2026 values are included that happen to be
--@ exact as well (elapsed day counts that are multiples of 8), and
--@ one deliberately NON-exact literal is decoded at the bottom to
--@ document what the rounding actually does -- 0x07EA003A (elapsed
--@ day 58) cannot exist as a float32 and arrives as ...992, which
--@ decodes to Feb 26, not Feb 28. That is the number model at work,
--@ not a translate_date bug; see 08_time_counters.lua for the live
--@ ioports.tim.date path.

--#include "../../lib/time.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: console timing constants ===
    number_fps_const        = frames_per_second  -- 60
    number_frame_time_const = frame_time         -- 1/60, prints as 0.0167

    -- === Test 2: translate_date, exact-input boundary matrix ===
    -- year 104 = 0x68: divisible by 4, not by 100 -> LEAP YEAR
    local d = translate_date(0x00680000)   -- elapsed 0
    number_td104_jan1_year  = d.year    -- 104
    number_td104_jan1_month = d.month   -- 1
    number_td104_jan1_day   = d.day     -- 1

    local d = translate_date(0x0068001F) -- elapsed 31: last day of January counted
    number_td104_feb1_month = d.month   -- 2
    number_td104_feb1_day   = d.day     -- 1

    local d = translate_date(0x0068003B) -- elapsed 59: LEAP-YEAR BOUNDARY
    number_td104_feb29_month = d.month  -- 2
    number_td104_feb29_day   = d.day    -- 29 (Feb 29 exists in 104)

    local d = translate_date(0x0068003C) -- elapsed 60: day after the boundary
    number_td104_mar1_month = d.month   -- 3
    number_td104_mar1_day   = d.day     -- 1

    local d = translate_date(0x0068016D) -- elapsed 365: leap-year end
    number_td104_dec31_month = d.month  -- 12
    number_td104_dec31_day   = d.day    -- 31

    -- year 100 = 0x64: divisible by 4 AND by 100 -> NOT leap (no
    -- 400 exception in this port, same as the C original)
    local d = translate_date(0x0064003B) -- elapsed 59 in a NON-leap year
    number_td100_mar1_year  = d.year    -- 100
    number_td100_mar1_month = d.month   -- 3 (not Feb 29 -- century rule)
    number_td100_mar1_day   = d.day     -- 1

    local d = translate_date(0x0064016C) -- elapsed 364: non-leap year end
    number_td100_dec31_month = d.month  -- 12
    number_td100_dec31_day   = d.day    -- 31

    -- year 98 = 0x62: not divisible by 4 -> plain non-leap mid-year case
    local d = translate_date(0x006200F8) -- elapsed 248
    number_td98_sep6_year  = d.year     -- 98
    number_td98_sep6_month = d.month    -- 9
    number_td98_sep6_day   = d.day      -- 6

    -- === Test 3: translate_date, realistic 2026 values that are ===
    -- === exactly representable (elapsed days 0 and 248 = 8*31) ===
    local d = translate_date(0x07EA0000)
    number_td2026_jan1_year  = d.year   -- 2026
    number_td2026_jan1_month = d.month  -- 1
    number_td2026_jan1_day   = d.day    -- 1

    local d = translate_date(0x07EA00F8)
    number_td2026_sep6_month = d.month  -- 9
    number_td2026_sep6_day   = d.day    -- 6

    -- === Test 4: translate_date, NON-exact input -- documents the ===
    -- === float32 literal rounding (see header): 0x07EA003A wants ===
    -- === elapsed day 58 (Feb 28) but arrives rounded to ...992, ===
    -- === i.e. elapsed 56, which decodes as Feb 26 ===
    local d = translate_date(0x07EA003A)
    number_td2026_rounded_month = d.month  -- 2
    number_td2026_rounded_day   = d.day    -- 26 (NOT 28 -- input rounding)

    -- === Test 5: translate_time, seconds-since-midnight matrix ===
    local t = translate_time(0)  -- midnight
    number_tt_midnight_hours   = t.hours    -- 0
    number_tt_midnight_minutes = t.minutes  -- 0
    number_tt_midnight_seconds = t.seconds  -- 0

    local t = translate_time(3661)  -- carries in both fields
    number_tt_carries_hours   = t.hours    -- 1
    number_tt_carries_minutes = t.minutes  -- 1
    number_tt_carries_seconds = t.seconds  -- 1

    local t = translate_time(86399)  -- last second of the day
    number_tt_lastsec_hours   = t.hours    -- 23
    number_tt_lastsec_minutes = t.minutes  -- 59
    number_tt_lastsec_seconds = t.seconds  -- 59

    local t = translate_time(10804)  -- actual v32sim tim.time dump
    number_tt_dump_hours   = t.hours    -- 3
    number_tt_dump_minutes = t.minutes  -- 0
    number_tt_dump_seconds = t.seconds  -- 4

    local t = translate_time(3599)  -- one second before the hour mark
    number_tt_prehour_hours   = t.hours    -- 0
    number_tt_prehour_minutes = t.minutes  -- 59
    number_tt_prehour_seconds = t.seconds  -- 59

    local t = translate_time(3600)  -- exactly on the hour mark
    number_tt_hourmark_hours   = t.hours    -- 1
    number_tt_hourmark_minutes = t.minutes  -- 0
    number_tt_hourmark_seconds = t.seconds  -- 0

    print(10, 0,   "--- date/time translation unit test ---")
    print(10, 20,  "leap 104 day 59/60: " .. number_td104_feb29_day
                   .. "/" .. number_td104_mar1_day)
    print(10, 40,  "century 100 day 59: " .. number_td100_mar1_month
                   .. "/" .. number_td100_mar1_day)
    print(10, 60,  "2026 elapsed 248 -> " .. number_td2026_sep6_month
                   .. "/" .. number_td2026_sep6_day)
    print(10, 80,  "time 86399 -> " .. number_tt_lastsec_hours
                   .. "/" .. number_tt_lastsec_minutes
                   .. "/" .. number_tt_lastsec_seconds)
    print(10, 100, "fps/frame_time: " .. number_fps_const
                   .. "/" .. number_frame_time_const)
end

--[[
=== EXPECTED OUTPUT ===

number_fps_const: 60.0000
number_frame_time_const: 0.0167
number_td104_jan1_year: 104.0000
number_td104_jan1_month: 1.0000
number_td104_jan1_day: 1.0000
number_td104_feb1_month: 2.0000
number_td104_feb1_day: 1.0000
number_td104_feb29_month: 2.0000
number_td104_feb29_day: 29.0000
number_td104_mar1_month: 3.0000
number_td104_mar1_day: 1.0000
number_td104_dec31_month: 12.0000
number_td104_dec31_day: 31.0000
number_td100_mar1_year: 100.0000
number_td100_mar1_month: 3.0000
number_td100_mar1_day: 1.0000
number_td100_dec31_month: 12.0000
number_td100_dec31_day: 31.0000
number_td98_sep6_year: 98.0000
number_td98_sep6_month: 9.0000
number_td98_sep6_day: 6.0000
number_td2026_jan1_year: 2026.0000
number_td2026_jan1_month: 1.0000
number_td2026_jan1_day: 1.0000
number_td2026_sep6_month: 9.0000
number_td2026_sep6_day: 6.0000
number_td2026_rounded_month: 2.0000
number_td2026_rounded_day: 26.0000
number_tt_midnight_hours: 0.0000
number_tt_midnight_minutes: 0.0000
number_tt_midnight_seconds: 0.0000
number_tt_carries_hours: 1.0000
number_tt_carries_minutes: 1.0000
number_tt_carries_seconds: 1.0000
number_tt_lastsec_hours: 23.0000
number_tt_lastsec_minutes: 59.0000
number_tt_lastsec_seconds: 59.0000
number_tt_dump_hours: 3.0000
number_tt_dump_minutes: 0.0000
number_tt_dump_seconds: 4.0000
number_tt_prehour_hours: 0.0000
number_tt_prehour_minutes: 59.0000
number_tt_prehour_seconds: 59.0000
number_tt_hourmark_hours: 1.0000
number_tt_hourmark_minutes: 0.0000
number_tt_hourmark_seconds: 0.0000

--]]
