-- time_helpers.lua
--
-- v32lua port of the date/time decomposition logic from the Vircon32 C
-- standard library's time.h. v32lua already exposes the raw values
-- (ioports.tim.date, ioports.tim.time, ioports.tim.frames,
-- ioports.tim.cycles) directly as read-only ports -- what's missing is
-- the arithmetic that turns them into year/month/day and
-- hours/minutes/seconds, which is pure logic and ports over as-is.
--
-- One real adaptation: v32lua has no bitwise operators at all (no >>,
-- no &), where the C original used `date >> 16` and
-- `date & 0x0000FFFF` to split TIM_CurrentDate's packed
-- year/day-of-year fields. Both packed fields are always
-- non-negative, so integer floor division and modulo by 65536 (2^16)
-- give exactly the same result:
--   date >> 16          ==  date // 65536
--   date & 0x0000FFFF    ==  date % 65536

-- timing properties of the console
frames_per_second = 60
frame_time        = 1.0 / 60.0

-- ---------------------------------------------------------------------------
--   READING TIME INFORMATION
-- ---------------------------------------------------------------------------
--
-- These four are trivial -- v32lua already exposes the same values as
-- read-only ports -- but ported C code calls them by these names, so
-- they're included for drop-in parity.

function get_cycle_counter()
    return ioports.tim.cycles
end

function get_frame_counter()
    return ioports.tim.frames
end

function get_date()
    return ioports.tim.date
end

function get_time()
    return ioports.tim.time
end

-- waits for the current frame to end
function end_frame()
    system.wait()
end

-- ---------------------------------------------------------------------------
--   TRANSLATING DATE AND TIME
-- ---------------------------------------------------------------------------

-- Returns a table { year, month, day }. month is 1 (January) to 12
-- (December); day starts from 1. Faithful port of translate_date(),
-- including its leap-year rule (divisible by 4, not by 100 -- the
-- centuries-divisible-by-400 exception is not handled, same as the
-- original).
function translate_date(date)
    local year       = date // 65536
    local daysInYear = date % 65536

    local monthDays = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

    local isLeapYear = (year % 4 == 0) and (year % 100 ~= 0)
    if isLeapYear then
        monthDays[2] = 29
    end

    local month = 1

    for m = 1, 11 do
        if daysInYear < monthDays[m] then
            return { year = year, month = month, day = daysInYear + 1 }
        end

        daysInYear = daysInYear - monthDays[m]
        month = month + 1
    end

    -- if we get here, it's December
    return { year = year, month = 12, day = daysInYear + 1 }
end

-- Returns a table { hours, minutes, seconds }. hours: 0-23, minutes:
-- 0-59, seconds: 0-59.
function translate_time(time)
    return {
        hours   = time // 3600,
        minutes = (time % 3600) // 60,
        seconds = time % 60
    }
end

-- Blocks for the given number of frames. Same polling shape as the C
-- original: read the frame counter, then wait one frame at a time
-- until it's advanced far enough.
function sleep(frames)
    local initialFrames = ioports.tim.frames
    local finalFrames   = initialFrames + frames

    while ioports.tim.frames < finalFrames do
        system.wait()
    end
end
