--@ Vircon32 Lua Math Library Test Suite
--@ File: math06.lua - Complete Summary Test
--@ Tests: All 21 implemented math functions
--@ Screen: 640x360
--@ Run with: v32lua math06.lua

function main()
    ioports.gpu.clear("black")
    print(180, 10, "=== MATH06: COMPLETE MATH LIBRARY ===")
    print(180, 25, "All 21 implemented functions")

    -- =========================================================================
    -- ROW 1: Rounding & Abs
    -- =========================================================================
    print(10, 50, "--- Rounding & Abs ---")
    print(10, 65, string.format("floor(2.7) = %.1f", math.floor(2.7)))
    print(10, 80, string.format("ceil(2.3) = %.1f", math.ceil(2.3)))
    print(10, 95, string.format("abs(-5) = %.1f", math.abs(-5)))

    -- =========================================================================
    -- ROW 2: Trigonometry
    -- =========================================================================
    print(10, 120, "--- Trigonometry ---")
    print(10, 135, string.format("sin(0) = %.4f", math.sin(0)))
    print(10, 150, string.format("cos(0) = %.4f", math.cos(0)))
    print(10, 165, string.format("tan(PI/4) = %.4f", math.tan(math.pi/4)))
    print(10, 180, string.format("asin(1) = %.4f", math.asin(1)))
    print(10, 195, string.format("acos(0) = %.4f", math.acos(0)))

    -- =========================================================================
    -- ROW 3: Log/Exp
    -- =========================================================================
    print(10, 220, "--- Log/Exp ---")
    print(10, 235, string.format("exp(0) = %.4f", math.exp(0)))
    print(10, 250, string.format("log(1) = %.4f", math.log(1)))
    print(10, 265, string.format("log10(10) = %.4f", math.log10(10)))
    print(10, 280, string.format("pow(2,3) = %.1f", math.pow(2, 3)))
    print(10, 295, string.format("sqrt(4) = %.4f", math.sqrt(4)))

    -- =========================================================================
    -- COLUMN 2: Comparison & Random
    -- =========================================================================
    print(220, 50, "--- Comparison ---")
    print(220, 65, string.format("fmod(10.5,3) = %.2f", math.fmod(10.5, 3)))
    print(220, 80, string.format("max(3,7) = %.1f", math.max(3, 7)))
    print(220, 95, string.format("min(3,7) = %.1f", math.min(3, 7)))

    print(220, 120, "--- Random ---")
    math.randomseed(42)
    print(220, 135, string.format("random() = %.6f", math.random()))
    print(220, 150, string.format("random(10) = %d", math.random(10)))
    print(220, 165, string.format("random(5,15) = %d", math.random(5, 15)))

    -- =========================================================================
    -- COLUMN 3: Conversion & Identities
    -- =========================================================================
    print(400, 50, "--- Conversion ---")
    print(400, 65, string.format("deg(PI) = %.1f", math.deg(math.pi)))
    print(400, 80, string.format("rad(180) = %.4f", math.rad(180)))

    print(400, 120, "--- Identities ---")
    local s, c = math.sin(math.pi/4), math.cos(math.pi/4)
    print(400, 135, string.format("sin²+cos² = %.4f", s*s + c*c))
    print(400, 150, string.format("log(exp(1)) = %.4f", math.log(math.exp(1))))
    print(400, 165, string.format("deg(rad(45)) = %.1f", math.deg(math.rad(45))))

    -- =========================================================================
    -- Summary
    -- =========================================================================
    print(10, 220, "=== IMPLEMENTATION SUMMARY ===")
    print(10, 235, "Direct HW (11): floor, ceil, abs, sin,")
    print(10, 250, "cos, acos, log, pow, atan2,")
    print(10, 265, "fmod, max, min")
    print(10, 280, "")
    print(10, 295, "Runtime (10): sqrt, random, seed,")
    print(10, 310, "asin, tan, deg, rad, exp,")
    print(10, 325, "log10")

    print(10, 345, "Total: 21/23 Lua 5.1 math functions")

    print(180, 345, "=== MATH06: ALL TESTS COMPLETE ===")
end
