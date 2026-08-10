--@ Vircon32 Lua Math Library Test Suite
--@ File: math00.lua - Rounding & Absolute Value Tests
--@ Tests: floor, ceil, abs
--@ Screen: 640x360
--@ Run with: v32lua math00.lua

function main()
    ioports.gpu.clear("black")
    print(10, 10, "=== MATH00: ROUNDING & ABSOLUTE VALUE ===")

    -- Test values
    local values = {-2.7, -1.0, -0.5, 0.0, 0.5, 1.0, 2.7}

    -- =========================================================================
    -- COLUMN 1: floor()
    -- =========================================================================
    print(10, 30, "--- floor() ---")
    print(10, 45, "x     | floor")
    print(10, 55, "------+-------")
    for i = 1, 4 do
        local v = values[i]
        print(10, 55 + i*15, string.format("%.1f   | %.1f", v, math.floor(v)))
    end

    -- =========================================================================
    -- COLUMN 2: ceil()
    -- =========================================================================
    print(160, 30, "--- ceil() ---")
    print(160, 45, "x     | ceil")
    print(160, 55, "------+------")
    for i = 1, 4 do
        local v = values[i+3]
        print(160, 55 + i*15, string.format("%.1f   | %.1f", v, math.ceil(v)))
    end

    -- =========================================================================
    -- COLUMN 3: abs()
    -- =========================================================================
    print(280, 30, "--- abs() ---")
    print(280, 45, "x      | abs")
    print(280, 55, "-------+------")
    local abs_vals = {-5.0, -2.5, 0.0, 2.5, 5.0}
    for i = 1, 5 do
        local v = abs_vals[i]
        print(280, 55 + i*15, string.format("% .1f   | %.1f", v, math.abs(v)))
    end

    -- =========================================================================
    -- COLUMN 4: Properties
    -- =========================================================================
    print(400, 30, "--- Properties ---")
    print(400, 45, "floor<=x<floor+1")
    print(400, 55, "ceil-1<x<=ceil")
    print(400, 65, "abs(x)>=0")

    for i = 1, 3 do
        local v = values[i]
        local f = math.floor(v)
        local ok1 = (f <= v) and (v < f + 1)
        print(400, 75 + i*15, string.format("floor(%.1f): %s", v, ok1 and "PASS" or "FAIL"))
    end

    for i = 1, 3 do
        local v = values[i+2]
        local c = math.ceil(v)
        local ok2 = (c - 1 < v) and (v <= c)
        print(400, 120 + i*15, string.format("ceil(%.1f): %s", v, ok2 and "PASS" or "FAIL"))
    end

    for i = 1, 3 do
        local v = abs_vals[i]
        local ok3 = math.abs(v) >= 0
        print(400, 165 + i*15, string.format("abs(% .1f): %s", v, ok3 and "PASS" or "FAIL"))
    end

    print(10, 240, "=== MATH00: ALL TESTS COMPLETE ===")
end
