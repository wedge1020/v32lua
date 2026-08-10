--@ Vircon32 Lua Math Library Test Suite
--@ File: math02.lua - Logarithmic & Exponential Tests
--@ Tests: log, log10, exp, pow, sqrt
--@ Screen: 640x360
--@ Run with: v32lua math02.lua

function main()
    ioports.gpu.clear("black")
    print(10, 10, "=== MATH02: LOG/EXP FUNCTIONS ===")

    -- =========================================================================
    -- COLUMN 1: exp() and log() inverses
    -- =========================================================================
    print(10, 30, "--- exp/log Inverses ---")
    print(10, 45, "x     | exp(x)  | log(exp)")
    print(10, 55, "------+--------+---------")

    local exp_tests = {-1, 0, 1, 2}
    for i, x in ipairs(exp_tests) do
        local e = math.exp(x)
        local l = math.log(e)
        local ok = math.abs(l - x) < 0.0001
        print(10, 55 + i*15, string.format("%.1f   | %.4f  | %.4f %s", x, e, l, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- COLUMN 2: pow()
    -- =========================================================================
    print(180, 30, "--- pow() ---")
    print(180, 45, "base | exp | result")
    print(180, 55, "-----+-----+--------")

    local pow_tests = {{2, 3, 8}, {4, 0.5, 2}, {9, 0.5, 3}, {2, 10, 1024}}
    for i, t in ipairs(pow_tests) do
        local b, e, expect = t[1], t[2], t[3]
        local r = math.pow(b, e)
        local ok = math.abs(r - expect) < 0.01
        print(180, 55 + i*15, string.format("%.1f  | %.1f | %.1f %s", b, e, r, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- COLUMN 3: sqrt()
    -- =========================================================================
    print(320, 30, "--- sqrt() ---")
    print(320, 45, "x     | sqrt(x) | x=sqrt^2")
    print(320, 55, "------+--------+---------")

    local sqrt_tests = {0, 1, 2, 4, 9, 16}
    for i, x in ipairs(sqrt_tests) do
        local s = math.sqrt(x)
        local sq = s * s
        local ok = math.abs(sq - x) < 0.0001
        print(320, 55 + i*15, string.format("%d    | %.4f  | %.4f %s", x, s, sq, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- COLUMN 4: log10()
    -- =========================================================================
    print(460, 30, "--- log10() ---")
    print(460, 45, "x      | log10(x)")
    print(460, 55, "-------+--------")

    local log10_tests = {1, 10, 100, 1000, 0.1, 0.01}
    for i, x in ipairs(log10_tests) do
        local l10 = math.log10(x)
        print(460, 55 + i*15, string.format("% .1f  | %.4f", x, l10))
    end

    -- Verify log10 identity
    print(460, 160, "--- log10 Identity ---")
    for i, x in ipairs({10, 100}) do
        local l10 = math.log10(x)
        local l = math.log(x) / math.log(10)
        local ok = math.abs(l10 - l) < 0.0001
        print(460, 175 + i*15, string.format("log10(%d): %.4f %s", x, l10, ok and "PASS" or "FAIL"))
    end

    print(10, 220, "=== MATH02: ALL TESTS COMPLETE ===")
end
