--#title "[v32lua] system.date()/system.time() unit number_test"

--@ Vircon32 Lua system.date()/system.time() Unit Test
--@ Covers the full decode chain: __builtin_unpack_date/__builtin_unpack_time
--@ (raw packed-register -> year/month/day or hour/min/sec), the
--@ __builtin_format_date_string/__builtin_format_time_string formatters,
--@ and finally system.date()/system.time() themselves at the real
--@ Lua-level multi-return call site -- not just the underlying builtins.
--@
--@ number_test1-7 exercise __builtin_unpack_date directly against known packed
--@ values (0x07EA00F8 etc: high 16 bits = year, low 16 = elapsed days
--@ since Jan 1 of that year) -- including the Feb 28/29 leap-year
--@ boundary in both directions and both a leap and non-leap year-end.
--@ number_testA-D do the same for __builtin_unpack_time against a packed
--@ seconds-since-midnight value, including midnight and 23:59:59 edges.
--@ number_test8-10/number_testE-F check the string formatters directly. The final
--@ Lua-level section confirms system.date()/system.time() -- the actual
--@ public API -- produce the same values through a real multi-return call.

number_test1year = 0  number_test1month = 0  number_test1day = 0
number_test2year = 0  number_test2month = 0  number_test2day = 0
number_test3year = 0  number_test3month = 0  number_test3day = 0
number_test4year = 0  number_test4month = 0  number_test4day = 0
number_test5year = 0  number_test5month = 0  number_test5day = 0
number_test6year = 0  number_test6month = 0  number_test6day = 0
number_test7year = 0  number_test7month = 0  number_test7day = 0

string_result8  = ""
string_result9  = ""
string_result10 = ""

number_testAhour = 0  number_testA_min = 0  number_testAsec = 0
number_testBhour = 0  number_testB_min = 0  number_testBsec = 0
number_testChour = 0  number_testC_min = 0  number_testCsec = 0
number_testDhour = 0  number_testD_min = 0  number_testDsec = 0

string_resultE = ""
string_resultF = ""

string_luadate = ""
number_luayear     = 0
number_luamonth    = 0
number_luaday      = 0
string_luatime = ""
number_luahour     = 0
number_luaminute   = 0
number_luasecond   = 0

function main()
    ioports.gpu.clear("black")

    -- --- number_test1: 2026, elapsedDays=248 (0x07EA00F8) -- actual v32sim dump ---
    __rawasm__("MOV R0, 0x07EA00F8\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {number_test1year}, R0\nMOV {number_test1month}, R2\nMOV {number_test1day}, R3")
    __rawasm__("__debug1:")

    -- --- number_test2: 2026, elapsedDays=0 -> Jan 1st ---
    __rawasm__("MOV R0, 0x07EA0000\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {number_test2year}, R0\nMOV {number_test2month}, R2\nMOV {number_test2day}, R3")
    __rawasm__("__debug2:")

    -- --- number_test3: 2026 (non-leap), elapsedDays=58 -> Feb 28th ---
    __rawasm__("MOV R0, 0x07EA003A\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {number_test3year}, R0\nMOV {number_test3month}, R2\nMOV {number_test3day}, R3")
    __rawasm__("__debug3:")

    -- --- number_test4: 2024 (LEAP), elapsedDays=59 -> Feb 29th ---
    __rawasm__("MOV R0, 0x07E8003B\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {number_test4year}, R0\nMOV {number_test4month}, R2\nMOV {number_test4day}, R3")
    __rawasm__("__debug4:")

    -- --- number_test5: 2024 (LEAP), elapsedDays=60 -> Mar 1st (day after the boundary) ---
    __rawasm__("MOV R0, 0x07E8003C\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {number_test5year}, R0\nMOV {number_test5month}, R2\nMOV {number_test5day}, R3")
    __rawasm__("__debug5:")

    -- --- number_test6: 2026 (non-leap), elapsedDays=364 -> Dec 31st ---
    __rawasm__("MOV R0, 0x07EA016C\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {number_test6year}, R0\nMOV {number_test6month}, R2\nMOV {number_test6day}, R3")
    __rawasm__("__debug6:")

    -- --- number_test7: 2024 (LEAP), elapsedDays=365 -> Dec 31st ---
    __rawasm__("MOV R0, 0x07E8016D\nPUSH R0\nCALL __builtin_unpack_date\nIADD SP, 1\nMOV {number_test7year}, R0\nMOV {number_test7month}, R2\nMOV {number_test7day}, R3")
    __rawasm__("__debug7:")

    -- --- number_test8: format (2026, 9, 6) -> "2026-09-06" ---
    __rawasm__("MOV R0, 2026\nPUSH R0\nMOV R0, 9\nPUSH R0\nMOV R0, 6\nPUSH R0\nCALL __builtin_format_date_string\nIADD SP, 3\nMOV {string_result8}, R0")
    __rawasm__("__debug8:")

    -- --- number_test9: format (2024, 2, 29) -- leap-year boundary ---
    __rawasm__("MOV R0, 2024\nPUSH R0\nMOV R0, 2\nPUSH R0\nMOV R0, 29\nPUSH R0\nCALL __builtin_format_date_string\nIADD SP, 3\nMOV {string_result9}, R0")
    __rawasm__("__debug9:")

    -- --- number_test10: format (2026, 1, 1) -> "2026-01-01" ---
    __rawasm__("MOV R0, 2026\nPUSH R0\nMOV R0, 1\nPUSH R0\nMOV R0, 1\nPUSH R0\nCALL __builtin_format_date_string\nIADD SP, 3\nMOV {string_result10}, R0")
    __rawasm__("__debug10:")

    -- --- number_testA: 10804 (0x00002A34) -- actual v32sim dump ---
    __rawasm__("MOV R0, 10804\nPUSH R0\nCALL __builtin_unpack_time\nIADD SP, 1\nMOV {number_testAhour}, R0\nMOV {number_testA_min}, R2\nMOV {number_testAsec}, R3")
    __rawasm__("__debugA:")

    -- --- number_testB: 0 -> midnight ---
    __rawasm__("MOV R0, 0\nPUSH R0\nCALL __builtin_unpack_time\nIADD SP, 1\nMOV {number_testBhour}, R0\nMOV {number_testB_min}, R2\nMOV {number_testBsec}, R3")
    __rawasm__("__debugB:")

    -- --- number_testC: 86399 -> 23:59:59 ---
    __rawasm__("MOV R0, 86399\nPUSH R0\nCALL __builtin_unpack_time\nIADD SP, 1\nMOV {number_testChour}, R0\nMOV {number_testC_min}, R2\nMOV {number_testCsec}, R3")
    __rawasm__("__debugC:")

    -- --- number_testD: 3661 -> 1:01:01 ---
    __rawasm__("MOV R0, 3661\nPUSH R0\nCALL __builtin_unpack_time\nIADD SP, 1\nMOV {number_testDhour}, R0\nMOV {number_testD_min}, R2\nMOV {number_testDsec}, R3")
    __rawasm__("__debugD:")

    -- --- number_testE: format (3, 0, 4) -> "03:00:04" ---
    __rawasm__("MOV R0, 3\nPUSH R0\nMOV R0, 0\nPUSH R0\nMOV R0, 4\nPUSH R0\nCALL __builtin_format_time_string\nIADD SP, 3\nMOV {string_resultE}, R0")
    __rawasm__("__debugE:")

    -- --- number_testF: format (23, 59, 59) -> "23:59:59" ---
    __rawasm__("MOV R0, 23\nPUSH R0\nMOV R0, 59\nPUSH R0\nMOV R0, 59\nPUSH R0\nCALL __builtin_format_time_string\nIADD SP, 3\nMOV {string_resultF}, R0")
    __rawasm__("__debugF:")

    -- =========================================================================
    -- Lua-level: system.date()/system.time() through the real multi-return
    -- call site, not the raw builtins -- captured to globals (not just
    -- printed) so the harness can scrape these the same as everything above.
    -- =========================================================================
    string_luadate, number_luayear, number_luamonth, number_luaday       = system.date()
    string_luatime, number_luahour, number_luaminute, number_luasecond   = system.time()
    __rawasm__("__debug_lua_level:")

    print(10, 10,  string_luadate)
    print(10, 30,  number_luayear)
    print(10, 50,  number_luamonth)
    print(10, 70,  number_luaday)
    print(10, 100, string_luatime)
    print(10, 120, number_luahour)
    print(10, 140, number_luaminute)
    print(10, 160, number_luasecond)

    ioports.gpu.sync()
end

--[[
=== EXPECTED OUTPUT ===
number_test1year: 2026.0000
number_test1month: 9.0000
number_test1day: 6.0000
number_test2year: 2026.0000
number_test2month: 1.0000
number_test2day: 1.0000
number_test3year: 2026.0000
number_test3month: 2.0000
number_test3day: 28.0000
number_test4year: 2024.0000
number_test4month: 2.0000
number_test4day: 29.0000
number_test5year: 2024.0000
number_test5month: 3.0000
number_test5day: 1.0000
number_test6year: 2026.0000
number_test6month: 12.0000
number_test6day: 31.0000
number_test7year: 2024.0000
number_test7month: 12.0000
number_test7day: 31.0000
string_result8: "2026-09-06"
string_result9: "2024-02-29"
string_result10: "2026-01-01"
number_testAhour: 3.0000
number_testA_min: 0.0000
number_testAsec: 4.0000
number_testBhour: 0.0000
number_testB_min: 0.0000
number_testBsec: 0.0000
number_testChour: 23.0000
number_testC_min: 59.0000
number_testCsec: 59.0000
number_testDhour: 1.0000
number_testD_min: 1.0000
number_testDsec: 1.0000
string_resultE: "03:00:04"
string_resultF: "23:59:59"
string_luadate: "2026-09-06"
number_luayear: 2026.0000
number_luamonth: 9.0000
number_luaday: 6.0000
string_luatime: "03:00:04"
number_luahour: 3.0000
number_luaminute: 0.0000
number_luasecond: 4.0000
]]
