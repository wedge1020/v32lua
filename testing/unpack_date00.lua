-- =============================================================================
-- Test harness: __builtin_unpack_date / __builtin_format_date_string
--               __builtin_unpack_time / __builtin_format_time_string
--               system.date() / system.time() (Lua-level multi-return)
--
-- === EXPECTED OUTPUT ===
-- test1:  (2026, 9, 6)     -- actual v32sim dump, 0x07EA00F8
-- test2:  (2026, 1, 1)     -- Jan 1st sanity (elapsedDays = 0)
-- test3:  (2026, 2, 28)    -- non-leap year, last day of February
-- test4:  (2024, 2, 29)    -- LEAP YEAR BOUNDARY: elapsedDays = 59 -> Feb 29
-- test5:  (2024, 3, 1)     -- day immediately after the leap boundary
-- test6:  (2026, 12, 31)   -- non-leap year-end
-- test7:  (2024, 12, 31)   -- leap year-end (elapsedDays = 365)
-- test8:  addr -> "2026-09-06"
-- test9:  addr -> "2024-02-29"   (leap-year boundary)
-- test10: addr -> "2026-01-01"
-- testA:  (3, 0, 4)         -- actual v32sim dump, 0x00002A34
-- testB:  (0, 0, 0)         -- midnight
-- testC:  (23, 59, 59)      -- last second of the day
-- testD:  (1, 1, 1)         -- round-trip check with carries in both fields
-- testE:  addr -> "03:00:04"
-- testF:  addr -> "23:59:59"
-- Lua-level: printed strings/components should read the same as above
-- =============================================================================

test1_year = 0  test1_month = 0  test1_day = 0
test2_year = 0  test2_month = 0  test2_day = 0
test3_year = 0  test3_month = 0  test3_day = 0
test4_year = 0  test4_month = 0  test4_day = 0
test5_year = 0  test5_month = 0  test5_day = 0
test6_year = 0  test6_month = 0  test6_day = 0
test7_year = 0  test7_month = 0  test7_day = 0

hex_result_test8_addr  = 0
hex_result_test9_addr  = 0
hex_result_test10_addr = 0

testA_hour = 0  testA_min = 0  testA_sec = 0
testB_hour = 0  testB_min = 0  testB_sec = 0
testC_hour = 0  testC_min = 0  testC_sec = 0
testD_hour = 0  testD_min = 0  testD_sec = 0

hex_result_testE_addr = 0
hex_result_testF_addr = 0

function main()
    ioports.gpu.clear("black")

    -- --- test1: 2026, elapsedDays=248 (0x07EA00F8) -- actual dump ---
    __rawasm__("MOV R0, 0x07EA00F8\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {test1_year}, R0\nMOV {test1_month}, R2\nMOV {test1_day}, R3")
    __rawasm__("__debug1:")

    -- --- test2: 2026, elapsedDays=0 -> Jan 1st ---
    __rawasm__("MOV R0, 0x07EA0000\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {test2_year}, R0\nMOV {test2_month}, R2\nMOV {test2_day}, R3")
    __rawasm__("__debug2:")

    -- --- test3: 2026 (non-leap), elapsedDays=58 -> Feb 28th ---
    __rawasm__("MOV R0, 0x07EA003A\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {test3_year}, R0\nMOV {test3_month}, R2\nMOV {test3_day}, R3")
    __rawasm__("__debug3:")

    -- --- test4: 2024 (LEAP), elapsedDays=59 -> Feb 29th ---
    __rawasm__("MOV R0, 0x07E8003B\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {test4_year}, R0\nMOV {test4_month}, R2\nMOV {test4_day}, R3")
    __rawasm__("__debug4:")

    -- --- test5: 2024 (LEAP), elapsedDays=60 -> Mar 1st (day after the boundary) ---
    __rawasm__("MOV R0, 0x07E8003C\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {test5_year}, R0\nMOV {test5_month}, R2\nMOV {test5_day}, R3")
    __rawasm__("__debug5:")

    -- --- test6: 2026 (non-leap), elapsedDays=364 -> Dec 31st ---
    __rawasm__("MOV R0, 0x07EA016C\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {test6_year}, R0\nMOV {test6_month}, R2\nMOV {test6_day}, R3")
    __rawasm__("__debug6:")

    -- --- test7: 2024 (LEAP), elapsedDays=365 -> Dec 31st ---
    __rawasm__("MOV R0, 0x07E8016D\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {test7_year}, R0\nMOV {test7_month}, R2\nMOV {test7_day}, R3")
    __rawasm__("__debug7:")

    -- --- test8: format (2026, 9, 6) -> "2026-09-06" ---
    __rawasm__("MOV R0, 2026\nPUSH R0\nMOV R0, 9\nPUSH R0\nMOV R0, 6\nPUSH R0\nCALL __builtin_format_date_string\nIADD SP, 3\nAND R0, BOXED_PAYLOAD\nMOV {hex_result_test8_addr}, R0")
    __rawasm__("__debug8:")

    -- --- test9: format (2024, 2, 29) -- leap-year boundary ---
    __rawasm__("MOV R0, 2024\nPUSH R0\nMOV R0, 2\nPUSH R0\nMOV R0, 29\nPUSH R0\nCALL __builtin_format_date_string\nIADD SP, 3\nAND R0, BOXED_PAYLOAD\nMOV {hex_result_test9_addr}, R0")
    __rawasm__("__debug9:")

    -- --- test10: format (2026, 1, 1) -> "2026-01-01" ---
    __rawasm__("MOV R0, 2026\nPUSH R0\nMOV R0, 1\nPUSH R0\nMOV R0, 1\nPUSH R0\nCALL __builtin_format_date_string\nIADD SP, 3\nAND R0, BOXED_PAYLOAD\nMOV {hex_result_test10_addr}, R0")
    __rawasm__("__debug10:")

    -- --- testA: 10804 (0x00002A34) -- actual dump ---
    __rawasm__("MOV R0, 10804\nPUSH R0\nCALL __builtin_unpack_time\nIADD SP, 1\nMOV {testA_hour}, R0\nMOV {testA_min}, R2\nMOV {testA_sec}, R3")
    __rawasm__("__debugA:")

    -- --- testB: 0 -> midnight ---
    __rawasm__("MOV R0, 0\nPUSH R0\nCALL __builtin_unpack_time\nIADD SP, 1\nMOV {testB_hour}, R0\nMOV {testB_min}, R2\nMOV {testB_sec}, R3")
    __rawasm__("__debugB:")

    -- --- testC: 86399 -> 23:59:59 ---
    __rawasm__("MOV R0, 86399\nPUSH R0\nCALL __builtin_unpack_time\nIADD SP, 1\nMOV {testC_hour}, R0\nMOV {testC_min}, R2\nMOV {testC_sec}, R3")
    __rawasm__("__debugC:")

    -- --- testD: 3661 -> 1:01:01 ---
    __rawasm__("MOV R0, 3661\nPUSH R0\nCALL __builtin_unpack_time\nIADD SP, 1\nMOV {testD_hour}, R0\nMOV {testD_min}, R2\nMOV {testD_sec}, R3")
    __rawasm__("__debugD:")

    -- --- testE: format (3, 0, 4) -> "03:00:04" ---
    __rawasm__("MOV R0, 3\nPUSH R0\nMOV R0, 0\nPUSH R0\nMOV R0, 4\nPUSH R0\nCALL __builtin_format_time_string\nIADD SP, 3\nAND R0, BOXED_PAYLOAD\nMOV {hex_result_testE_addr}, R0")
    __rawasm__("__debugE:")

    -- --- testF: format (23, 59, 59) -> "23:59:59" ---
    __rawasm__("MOV R0, 23\nPUSH R0\nMOV R0, 59\nPUSH R0\nMOV R0, 59\nPUSH R0\nCALL __builtin_format_time_string\nIADD SP, 3\nAND R0, BOXED_PAYLOAD\nMOV {hex_result_testF_addr}, R0")
    __rawasm__("__debugF:")

    -- =========================================================================
    -- Lua-level tests: system.date() / system.time() through the real
    -- multi-return call site, not the raw builtin. Printed to screen so
    -- you can eyeball them directly instead of scraping memory.
    -- =========================================================================

    local date_str, year, month, day = system.date()
    print(10, 10,  date_str)
    print(10, 30,  year)
    print(10, 50,  month)
    print(10, 70,  day)

    local time_str, hour, minute, second = system.time()
    print(10, 100, time_str)
    print(10, 120, hour)
    print(10, 140, minute)
    print(10, 160, second)

    __rawasm__("__debug_lua_level:")

    ioports.gpu.sync()

end
