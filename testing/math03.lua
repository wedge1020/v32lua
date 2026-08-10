--@ Vircon32 Lua Math Library Test Suite
--@ File: math03.lua - Comparison & Modulo Tests
--@ Tests: fmod, max, min
--@ Screen: 640x360
--@ Run with: v32lua math03.lua

function main()
    ioports.gpu.clear("black")
    print(10, 10, "=== MATH03: COMPARISON & MODULO ===")

    -- =========================================================================
    -- COLUMN 1: fmod()
    -- =========================================================================
    print(10, 30, "--- fmod() ---")
    print(10, 45, "x   | y   | fmod")
    print(10, 55, "----+-----+------")

    local fmod_tests = {
        {10.5, 3.0, 1.5},
        {7.0, 2.5, 2.0},
        {-5.0, 2.0, -1.0},
        {0.0, 5.0, 0.0}
    }

    for i, t in ipairs(fmod_tests) do
        local x, y, expect = t[1], t[2], t[3]
        local r = math.fmod(x, y)
        local ok = math.abs(r - expect) < 0.001
        print(10, 55 + i*15, string.format("% .1f| % .1f| % .1f %s", x, y, r, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- COLUMN 2: max()
    -- =========================================================================
    print(160, 30, "--- max() ---")
    print(160, 45, "x   | y   | max")
    print(160, 55, "----+-----+------")

    local max_tests = {
        {3.0, 7.0, 7.0},
        {-5.0, -2.0, -2.0},
        {0.0, -1.0, 0.0},
        {5.0, 5.0, 5.0}
    }

    for i, t in ipairs(max_tests) do
        local x, y, expect = t[1], t[2], t[3]
        local r = math.max(x, y)
        local ok = r == expect
        print(160, 55 + i*15, string.format("% .1f| % .1f| % .1f %s", x, y, r, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- COLUMN 3: min()
    -- =========================================================================
    print(300, 30, "--- min() ---")
    print(300, 45, "x   | y   | min")
    print(300, 55, "----+-----+------")

    local min_tests = {
        {3.0, 7.0, 3.0},
        {-5.0, -2.0, -5.0},
        {0.0, -1.0, -1.0},
        {5.0, 5.0, 5.0}
    }

    for i, t in ipairs(min_tests) do
        local x, y, expect = t[1], t[2], t[3]
        local r = math.min(x, y)
        local ok = r == expect
        print(300, 55 + i*15, string.format("% .1f| % .1f| % .1f %s", x, y, r, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- Properties
    -- =========================================================================
    print(10, 160, "--- Properties ---")
    print(10, 175, "fmod: x = y*floor(x/y) + fmod(x,y)")
    print(10, 185, "max: max(x,y) >= x AND max(x,y) >= y")
    print(10, 195, "min: min(x,y) <= x AND min(x,y) <= y")

    -- Verify fmod property
    for i, t in ipairs(fmod_tests) do
        local x, y = t[1], t[2]
        local f = math.fmod(x, y)
        local floor_div = math.floor(x / y)
        local computed = y * floor_div + f
        local ok = math.abs(computed - x) < 0.001
        print(10, 210 + i*15, string.format("fmod(% .1f,% .1f): %s", x, y, ok and "PASS" or "FAIL"))
    end

    -- Verify max property
    for i, t in ipairs(max_tests) do
        local x, y = t[1], t[2]
        local m = math.max(x, y)
        local ok = (m >= x) and (m >= y)
        print(160, 210 + i*15, string.format("max(% .1f,% .1f): %s", x, y, ok and "PASS" or "FAIL"))
    end

    -- Verify min property
    for i, t in ipairs(min_tests) do
        local x, y = t[1], t[2]
        local m = math.min(x, y)
        local ok = (m <= x) and (m <= y)
        print(300, 210 + i*15, string.format("min(% .1f,% .1f): %s", x, y, ok and "PASS" or "FAIL"))
    end

    print(10, 290, "=== MATH03: ALL TESTS COMPLETE ===")
end
