--@ Vircon32 Lua Math Library - Complete Test Suite
--@ All tests in one file with main() entry point

-- =============================================================================
-- TEST: Trigonometric Functions
-- =============================================================================
function test_trigonometry()
    print(10, 10, "=== TRIGONOMETRY ===")

    -- Known values
    print(10, 30, string.format("sin(0) = %.4f (expect 0.0000)", math.sin(0)))
    print(10, 50, string.format("cos(0) = %.4f (expect 1.0000)", math.cos(0)))
    print(10, 70, string.format("sin(PI/2) = %.4f (expect 1.0000)", math.sin(math.pi/2)))
    print(10, 90, string.format("cos(PI/2) = %.4f (expect 0.0000)", math.cos(math.pi/2)))
    print(10, 110, string.format("tan(0) = %.4f (expect 0.0000)", math.tan(0)))
    print(10, 130, string.format("tan(PI/4) = %.4f (expect 1.0000)", math.tan(math.pi/4)))
    print(10, 150, string.format("asin(0) = %.4f (expect 0.0000)", math.asin(0)))
    print(10, 170, string.format("asin(1) = %.4f (expect 1.5708)", math.asin(1)))
    print(10, 190, string.format("atan(1) = %.4f (expect 0.7854)", math.atan(1)))
    print(10, 210, string.format("atan2(1,1) = %.4f (expect 0.7854)", math.atan2(1, 1)))
    print(10, 230, string.format("acos(0.5) = %.4f (expect 1.0472)", math.acos(0.5)))

    -- Pythagorean identity
    local angles = {0, math.pi/4, math.pi/2, math.pi}
    for i, a in ipairs(angles) do
        local s, c = math.sin(a), math.cos(a)
        local identity = s*s + c*c
        print(250, 30 + (i-1)*20, string.format("sin(%.2f)^2 + cos(%.2f)^2 = %.6f", a, a, identity))
    end

    -- tan identity: tan(x) = sin(x)/cos(x)
    for i, a in ipairs({0, math.pi/6, math.pi/4, math.pi/3}) do
        local t = math.tan(a)
        local s, c = math.sin(a), math.cos(a)
        local identity = s / c
        print(490, 30 + (i-1)*20, string.format("tan(%.2f)=%.4f, sin/cos=%.4f", a, t, identity))
    end
end

-- =============================================================================
-- TEST: Logarithmic & Exponential Functions
-- =============================================================================
function test_log_exp()
    print(10, 10, "=== LOG/EXP ===")

    -- exp and log are inverses
    local test_vals = {0, 1, 2, 5, 10}
    for i, v in ipairs(test_vals) do
        local e = math.exp(v)
        local l = math.log(e)
        print(10, 30 + (i-1)*20, string.format("exp(%.1f)=%.4f, log(exp)=%.4f", v, e, l))
    end

    -- pow tests
    print(250, 30, string.format("pow(2,3) = %.1f (expect 8.0)", math.pow(2, 3)))
    print(250, 50, string.format("pow(4,0.5) = %.4f (expect 2.0)", math.pow(4, 0.5)))
    print(250, 70, string.format("pow(9,0.5) = %.4f (expect 3.0)", math.pow(9, 0.5)))

    -- sqrt tests
    print(250, 90, string.format("sqrt(4) = %.4f (expect 2.0)", math.sqrt(4)))
    print(250, 110, string.format("sqrt(2) = %.4f (expect 1.4142)", math.sqrt(2)))

    -- log tests
    print(250, 130, string.format("log(1) = %.4f (expect 0.0)", math.log(1)))
    print(250, 150, string.format("log(e) = %.4f (expect 1.0)", math.log(math.exp(1))))
    print(250, 170, string.format("log10(1) = %.4f (expect 0.0)", math.log10(1)))
    print(250, 190, string.format("log10(10) = %.4f (expect 1.0)", math.log10(10)))
    print(250, 210, string.format("log10(100) = %.4f (expect 2.0)", math.log10(100)))

    -- Verify log10 identity: log10(x) = log(x)/log(10)
    for i, v in ipairs({1, 10, 100, 1000}) do
        local l10 = math.log10(v)
        local l = math.log(v) / math.log(10)
        print(490, 30 + (i-1)*20, string.format("log10(%d)=%.4f, log/ln10=%.4f", v, l10, l))
    end
end

-- =============================================================================
-- TEST: Angle Conversion Functions
-- =============================================================================
function test_conversion()
    print(10, 10, "=== ANGLE CONVERSION ===")

    -- deg/rad are inverses
    local angles_deg = {0, 30, 45, 60, 90, 180, 270, 360}
    for i, deg in ipairs(angles_deg) do
        local rad = math.rad(deg)
        local back = math.deg(rad)
        print(10, 30 + (i-1)*20, string.format("deg(%d)=%.4f, rad(%.4f)=%.1f", deg, rad, rad, back))
    end

    -- Test known values
    print(250, 30, string.format("deg(PI) = %.1f (expect 180.0)", math.deg(math.pi)))
    print(250, 50, string.format("deg(PI/2) = %.1f (expect 90.0)", math.deg(math.pi/2)))
    print(250, 70, string.format("rad(180) = %.4f (expect 3.1416)", math.rad(180)))
    print(250, 90, string.format("rad(90) = %.4f (expect 1.5708)", math.rad(90)))

    -- Verify identities
    print(250, 110, string.format("deg(rad(x)) = x: %.1f", math.deg(math.rad(42))))
    print(250, 130, string.format("rad(deg(x)) = x: %.4f", math.rad(math.deg(1.234))))
end

-- =============================================================================
-- TEST: Rounding Functions
-- =============================================================================
function test_rounding()
    print(10, 10, "=== ROUNDING ===")

    local values = {-2.7, -1.0, -0.5, 0.0, 0.5, 1.0, 2.7, 3.999}

    -- floor
    print(10, 30, "floor():")
    for i, v in ipairs(values) do
        print(10, 50 + (i-1)*20, string.format("  floor(%.2f) = %.1f", v, math.floor(v)))
    end

    -- ceil
    print(250, 30, "ceil():")
    for i, v in ipairs(values) do
        print(250, 50 + (i-1)*20, string.format("  ceil(%.2f) = %.1f", v, math.ceil(v)))
    end

    -- abs
    print(490, 30, "abs():")
    for i, v in ipairs({-5, -3.14, -0.001, 0, 0.001, 3.14, 5}) do
        print(490, 50 + (i-1)*20, string.format("  abs(%.2f) = %.2f", v, math.abs(v)))
    end
end

-- =============================================================================
-- TEST: Comparison Functions
-- =============================================================================
function test_comparison()
    print(10, 10, "=== COMPARISON ===")

    -- fmod tests
    print(10, 30, "fmod(x, y):")
    print(10, 50, string.format("  fmod(10.5, 3.0) = %.2f (expect 1.50)", math.fmod(10.5, 3.0)))
    print(10, 70, string.format("  fmod(7.0, 2.5) = %.2f (expect 2.00)", math.fmod(7.0, 2.5)))
    print(10, 90, string.format("  fmod(-5.0, 2.0) = %.2f (expect -1.00)", math.fmod(-5.0, 2.0)))
    print(10, 110, string.format("  fmod(0.0, 5.0) = %.2f (expect 0.00)", math.fmod(0.0, 5.0)))

    -- max tests
    print(250, 30, "max(x, y):")
    print(250, 50, string.format("  max(3.0, 7.0) = %.1f (expect 7.0)", math.max(3.0, 7.0)))
    print(250, 70, string.format("  max(-5.0, -2.0) = %.1f (expect -2.0)", math.max(-5.0, -2.0)))
    print(250, 90, string.format("  max(0.0, -1.0) = %.1f (expect 0.0)", math.max(0.0, -1.0)))

    -- min tests
    print(490, 30, "min(x, y):")
    print(490, 50, string.format("  min(3.0, 7.0) = %.1f (expect 3.0)", math.min(3.0, 7.0)))
    print(490, 70, string.format("  min(-5.0, -2.0) = %.1f (expect -5.0)", math.min(-5.0, -2.0)))
    print(490, 90, string.format("  min(0.0, -1.0) = %.1f (expect -1.0)", math.min(0.0, -1.0)))

    -- Verify max/min properties
    local test_pairs = {{3, 7}, {-5, -2}, {0, -1}, {2.5, 2.5}}
    for i, p in ipairs(test_pairs) do
        local a, b = p[1], p[2]
        local m = math.min(a, b)
        local M = math.max(a, b)
        local ok = (m <= a and m <= b) and (M >= a and M >= b) and (m <= M)
        print(10, 150 + (i-1)*20, string.format("  min(%.1f,%.1f)=%.1f, max=%.1f: %s",
            a, b, m, M, ok and "OK" or "FAIL"))
    end
end

-- =============================================================================
-- TEST: Random Functions
-- =============================================================================
function test_random()
    print(10, 10, "=== RANDOM ===")

    -- random() -> [0, 1)
    print(10, 30, "random() in [0,1):")
    for i = 1, 5 do
        print(10, 50 + (i-1)*20, string.format("  %.6f", math.random()))
    end

    -- random(n) -> [1, n]
    print(250, 30, "random(10) in [1,10]:")
    for i = 1, 5 do
        print(250, 50 + (i-1)*20, string.format("  %d", math.random(10)))
    end

    -- random(m, n) -> [m, n]
    print(490, 30, "random(5,15) in [5,15]:")
    for i = 1, 5 do
        print(490, 50 + (i-1)*20, string.format("  %d", math.random(5, 15)))
    end

    -- Seed test
    math.randomseed(42)
    local r1 = math.random()
    math.randomseed(42)
    local r2 = math.random()
    print(10, 150, string.format("Same seed: %.6f == %.6f? %s", r1, r2, r1 == r2 and "YES" or "NO"))
end

-- =============================================================================
-- MAIN: Run all tests
-- =============================================================================
function main()
    ioports.gpu.clear("black")
    test_trigonometry()
    ioports.gpu.sync()

    ioports.gpu.clear("black")
    test_log_exp()
    ioports.gpu.sync()

    ioports.gpu.clear("black")
    test_conversion()
    ioports.gpu.sync()

    ioports.gpu.clear("black")
    test_rounding()
    ioports.gpu.sync()

    ioports.gpu.clear("black")
    test_comparison()
    ioports.gpu.sync()

    ioports.gpu.clear("black")
    test_random()
    ioports.gpu.sync()

    -- Final summary
    ioports.gpu.clear("black")
    print(180, 140, "=== ALL MATH TESTS COMPLETE ===")
    print(180, 160, "Implemented functions (21/23):")
    print(180, 180, "  floor, ceil, sqrt, sin, cos, tan")
    print(180, 200, "  asin, acos, atan, atan2, log")
    print(180, 220, "  log10, exp, pow, fmod, max")
    print(180, 240, "  min, deg, rad, abs, random")
    print(180, 260, "  randomseed")
end
