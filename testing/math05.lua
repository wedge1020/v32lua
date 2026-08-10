--@ Vircon32 Lua Math Library Test Suite
--@ File: math05.lua - Angle Conversion Tests
--@ Tests: deg, rad
--@ Screen: 640x360
--@ Run with: v32lua math05.lua

function main()
    ioports.gpu.clear("black")
    print(10, 10, "=== MATH05: ANGLE CONVERSION ===")

    -- =========================================================================
    -- COLUMN 1: deg() - Radians to Degrees
    -- =========================================================================
    print(10, 30, "--- deg() ---")
    print(10, 45, "Radians  | Degrees")
    print(10, 55, "---------+--------")

    local deg_tests = {
        {0, 0},
        {math.pi/6, 30},
        {math.pi/4, 45},
        {math.pi/2, 90},
        {math.pi, 180}
    }

    for i, t in ipairs(deg_tests) do
        local rad, expect = t[1], t[2]
        local deg = math.deg(rad)
        local ok = math.abs(deg - expect) < 0.1
        print(10, 55 + i*15, string.format("%.4f   | %.1f %s", rad, deg, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- COLUMN 2: rad() - Degrees to Radians
    -- =========================================================================
    print(160, 30, "--- rad() ---")
    print(160, 45, "Degrees  | Radians")
    print(160, 55, "---------+--------")

    local rad_tests = {
        {0, 0},
        {30, math.pi/6},
        {45, math.pi/4},
        {90, math.pi/2},
        {180, math.pi}
    }

    for i, t in ipairs(rad_tests) do
        local deg, expect = t[1], t[2]
        local rad = math.rad(deg)
        local ok = math.abs(rad - expect) < 0.001
        print(160, 55 + i*15, string.format("%d       | %.4f %s", deg, rad, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- COLUMN 3: Inverse Relationship
    -- =========================================================================
    print(300, 30, "--- Inverse Relationship ---")
    print(300, 45, "deg(rad(x)) = x")
    print(300, 55, "Value   | Result")
    print(300, 65, "-------+--------")

    local inverse_tests = {0, 45, 90, 135, 180, 270, 360}
    for i, deg in ipairs(inverse_tests) do
        local rad = math.rad(deg)
        local back = math.deg(rad)
        local ok = math.abs(back - deg) < 0.1
        print(300, 65 + i*15, string.format("%-6d | %.1f %s", deg, back, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- Trig Identity with deg/rad
    -- =========================================================================
    print(420, 30, "--- Trig Identity ---")
    print(420, 45, "sin(90°) = sin(PI/2)")
    local sin_90_deg = math.sin(math.rad(90))
    local sin_90_rad = math.sin(math.pi/2)
    print(420, 55, string.format("sin(rad(90)) = %.4f", sin_90_deg))
    print(420, 65, string.format("sin(PI/2)    = %.4f", sin_90_rad))
    print(420, 75, string.format("Match: %s", math.abs(sin_90_deg - sin_90_rad) < 0.001 and "PASS" or "FAIL"))

    print(10, 220, "=== MATH05: ALL TESTS COMPLETE ===")
end
