--#title "v32lua time counters and frame waiting unit test"
--@ Vircon32 Lua time unit test -- lib/time.lua half 2 of 2
--@ Exercises the ioports-backed half of time.h: get_cycle_counter,
--@ get_frame_counter, get_date, get_time, plus end_frame() and
--@ sleep() through their system.wait() plumbing.
--@
--@ Two v32sim properties shape what is assertable here, and both
--@ are confirmed against the simulator rather than assumed:
--@   * the frame and cycle counters advance ONLY on waits/execution,
--@     never with wall-clock time -- so end_frame() is expected to
--@     advance the frame counter by EXACTLY 1 and sleep(3) by
--@     EXACTLY 3 (asserted as deltas, which also keeps this test
--@     independent of whatever frame the cart happens to start on);
--@   * ioports.tim.time is the wall clock at simulation start and
--@     ioports.tim.date tracks the real calendar, so their RAW
--@     values are deliberately NOT scraped (they change between
--@     runs). Instead the live values are pushed through the
--@     translate_date/translate_time decoders and the RESULTS are
--@     range-checked -- any decode failure or out-of-range field
--@     would fail the test, which is the property that matters.

--#include "../../lib/time.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: get_cycle_counter -- never runs backwards ===
    local c1 = get_cycle_counter()
    local spin = 0
    for i = 1, 200 do
        spin = spin + i
    end
    local c2 = get_cycle_counter()
    boolean_cycles_nondecreasing = (c2 >= c1)

    -- === Test 2: end_frame -- exactly one frame of waiting ===
    local f0 = get_frame_counter()
    end_frame()
    local f1 = get_frame_counter()
    number_endframe_delta = f1 - f0
    boolean_frames_advance = (f1 > f0)

    -- === Test 3: sleep -- waits for the requested frame count ===
    sleep(3)
    local f2 = get_frame_counter()
    number_sleep_delta = f2 - f1

    -- === Test 4: get_date -- live port, decoded and range-checked ===
    local d = translate_date(get_date())
    boolean_getdate_year_valid  = (d.year >= 2000 and d.year <= 2099)
    boolean_getdate_month_valid = (d.month >= 1 and d.month <= 12)
    boolean_getdate_day_valid   = (d.day >= 1 and d.day <= 31)

    -- === Test 5: get_time -- live port, range-checked directly and ===
    -- === through the translate_time decoder ===
    local t = get_time()
    boolean_gettime_seconds_valid = (t >= 0 and t <= 86399)

    local tm = translate_time(get_time())
    boolean_gettime_hms_valid = (tm.hours >= 0 and tm.hours <= 23)
        and (tm.minutes >= 0 and tm.minutes <= 59)
        and (tm.seconds >= 0 and tm.seconds <= 59)

    print(10, 0,   "--- time counters/frame waiting unit test ---")
    print(10, 20,  "cycles nondecreasing: " .. tostring(boolean_cycles_nondecreasing))
    print(10, 40,  "end_frame delta: " .. number_endframe_delta)
    print(10, 60,  "sleep(3) delta: " .. number_sleep_delta)
    print(10, 80,  "live date decode valid: " .. tostring(boolean_getdate_year_valid)
                   .. tostring(boolean_getdate_month_valid)
                   .. tostring(boolean_getdate_day_valid))
    print(10, 100, "live time decode valid: " .. tostring(boolean_gettime_hms_valid))
end

--[[
=== EXPECTED OUTPUT ===

boolean_cycles_nondecreasing: true
number_endframe_delta: 1.0000
boolean_frames_advance: true
number_sleep_delta: 3.0000
boolean_getdate_year_valid: true
boolean_getdate_month_valid: true
boolean_getdate_day_valid: true
boolean_gettime_seconds_valid: true
boolean_gettime_hms_valid: true

--]]
