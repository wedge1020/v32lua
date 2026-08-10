--@ Vircon32 Lua Math Library Test Suite
--@ File: math01.lua - Trigonometric Function Tests
--@ Tests: sin, cos, tan, asin, acos, atan, atan2
--@ Screen: 640x360
--@ Run with: v32lua math01.lua

function main()
    ioports.gpu.clear("black")
    print(10, 10, "=== MATH01: TRIGONOMETRIC FUNCTIONS ===")

    -- =========================================================================
    -- SCREEN 1: Basic Trig Values
    -- =========================================================================
    print(10, 30, "--- Known Values ---")
    print(10, 45, "Func | x=0    | x=PI/2  | x=PI")
    print(10, 55, "-----+--------+---------+--------")

    local pi_2 = math.pi / 2
    local pi = math.pi

    print(10, 65, string.format("sin  | %.4f  | %.4f   | %.4f",
        math.sin(0), math.sin(pi_2), math.sin(pi)))
    print(10, 75, string.format("cos  | %.4f  | %.4f   | %.4f",
        math.cos(0), math.cos(pi_2), math.cos(pi)))
    print(10, 85, string.format("tan  | %.4f  | %.4f   | N/A",
        math.tan(0), math.tan(pi_2)))

    print(10, 100, string.format("asin | %.4f  | %.4f   | N/A",
        math.asin(0), math.asin(1)))
    print(10, 110, string.format("acos | %.4f  | %.4f   | %.4f",
        math.acos(1), math.acos(0), math.acos(-1)))
    print(10, 120, string.format("atan | %.4f  | %.4f   | N/A",
        math.atan(0), math.atan(1)))

    -- =========================================================================
    -- SCREEN 2: Identities (after sync)
    -- =========================================================================
    ioports.gpu.sync()

    ioports.gpu.clear("black")
    print(10, 10, "=== MATH01: IDENTITIES ===")

    print(10, 30, "--- Pythagorean: sin^2 + cos^2 = 1 ---")
    local angles = {0, pi_2/2, pi_2, pi_2*1.5, pi}
    for i, a in ipairs(angles) do
        local s, c = math.sin(a), math.cos(a)
        local identity = s*s + c*c
        local ok = math.abs(identity - 1) < 0.001
        print(10, 45 + i*15, string.format("x=%.2f: %.6f %s", a, identity, ok and "PASS" or "FAIL"))
    end

    print(200, 30, "--- tan = sin/cos ---")
    for i, a in ipairs({0, pi/6, pi/4, pi/3}) do
        local t = math.tan(a)
        local s, c = math.sin(a), math.cos(a)
        local identity = s / c
        local ok = math.abs(t - identity) < 0.001
        print(200, 45 + i*15, string.format("x=%.2f: %.4f %s", a, t, ok and "PASS" or "FAIL"))
    end

    print(350, 30, "--- asin/acos range ---")
    print(350, 45, "asin(0)=0, asin(1)=PI/2")
    print(350, 55, string.format("%.4f, %.4f", math.asin(0), math.asin(1)))
    print(350, 70, "acos(0)=PI/2, acos(1)=0")
    print(350, 80, string.format("%.4f, %.4f", math.acos(0), math.acos(1)))

    print(10, 180, "=== MATH01: ALL TESTS COMPLETE ===")
end
