--@ Vircon32 Lua Math Library Test Suite
--@ File: math04.lua - Random Number Tests
--@ Tests: random, randomseed
--@ Screen: 640x360
--@ Run with: v32lua math04.lua

function main()
    ioports.gpu.clear("black")
    print(10, 10, "=== MATH04: RANDOM NUMBERS ===")

    -- =========================================================================
    -- COLUMN 1: random() - [0, 1)
    -- =========================================================================
    print(10, 30, "--- random() in [0,1) ---")
    for i = 1, 8 do
        local r = math.random()
        local ok = (r >= 0) and (r < 1)
        print(10, 45 + i*15, string.format("[%d] %.6f %s", i, r, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- COLUMN 2: random(n) - [1, n]
    -- =========================================================================
    print(160, 30, "--- random(10) in [1,10] ---")
    for i = 1, 8 do
        local r = math.random(10)
        local ok = (r >= 1) and (r <= 10) and (r == math.floor(r))
        print(160, 45 + i*15, string.format("[%d] %d %s", i, r, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- COLUMN 3: random(m,n) - [m, n]
    -- =========================================================================
    print(300, 30, "--- random(5,15) in [5,15] ---")
    for i = 1, 8 do
        local r = math.random(5, 15)
        local ok = (r >= 5) and (r <= 15) and (r == math.floor(r))
        print(300, 45 + i*15, string.format("[%d] %d %s", i, r, ok and "PASS" or "FAIL"))
    end

    -- =========================================================================
    -- Reproducibility Tests
    -- =========================================================================
    print(10, 180, "--- Reproducibility ---")
    print(10, 195, "Same seed -> same sequence")

    math.randomseed(42)
    local r1 = math.random()
    math.randomseed(42)
    local r2 = math.random()
    print(10, 210, string.format("Seed 42: %.6f == %.6f? %s", r1, r2, r1 == r2 and "PASS" or "FAIL"))

    math.randomseed(123)
    local r3 = math.random()
    math.randomseed(456)
    local r4 = math.random()
    print(10, 225, string.format("Diff seeds: %.6f != %.6f? %s", r3, r4, r3 ~= r4 and "PASS" or "FAIL"))

    print(10, 250, "=== MATH04: ALL TESTS COMPLETE ===")
end
