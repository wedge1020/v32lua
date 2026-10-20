--#title "[v32lua] color() intrinsic unit test"
--@ Vircon32 Lua color() Intrinsic Unit Test
--@ color(n) turns a number into the raw 32-bit word (0xAABBGGRR for a
--@ color): floored, then wrapped into 32 bits (-1 -> 0xFFFFFFFF), as the
--@ bitwise operators convert. Literals fold at compile time, exactly; a
--@ number computed at run time is a float32, exact only up to 24
--@ significant bits: 128 * 2^24 + 0x2040FF (0x802040FF, 32 significant
--@ bits) has already been rounded to 0x80204100 before color() sees it.
--@ That is why rgba() exists; color() suits small values and words that
--@ fit in 24 significant bits.
--@ Results that are raw words go in hex_ globals (memory scraping).
--@ None of the words below collides with a NaN-box tag.

local function half(x) return x / 2 end

function test_color()
    -- === Test 00: literal folds ===
    hex_result00a = color(0xFF0000FF)        -- exact, all 32 bits
    hex_result00b = color(0x04030201)
    hex_result00c = color(-1)                -- 0xFFFFFFFF
    hex_result00d = color(255.9)             -- floored: 0xFF
    __rawasm__("__debug0:")

    -- === Test 01: run time ===
    local a, c = 128, 0x2040FF
    hex_result01a = color(a * 16777216 + c)  -- 0x802040FF, rounded by float32 to 0x80204100
    local m = -1
    hex_result01b = color(m)                 -- 0xFFFFFFFF
    local f = 1000.75
    hex_result01c = color(f)                 -- 0x000003E8
    local neg = -256
    hex_result01d = color(neg)               -- 0xFFFFFF00
    hex_result01e = color(half(0x7F000000) * 2)  -- a call inside: 0x7F000000
    __rawasm__("__debug1:")

    -- === Test 02: into the GPU ===
    ioports.gpu.multiply = color(a * 16777216 + c)   -- the same rounded word
    __rawasm__("IN R0, GPU_MultiplyColor")
    __rawasm__("MOV [var_hex_result02a], R0")
    ioports.gpu.multiply = color(0x0A0B0C0D)
    __rawasm__("IN R0, GPU_MultiplyColor")
    __rawasm__("MOV [var_hex_result02b], R0")
    ioports.gpu.multiply = color(-1)
    __rawasm__("__debug2:")
end

hex_result02a = 0
hex_result02b = 0

function main()
    ioports.gpu.clear("black")
    test_color()
end

--[[
=== EXPECTED OUTPUT ===

hex_result00a: 0xFF0000FF
hex_result00b: 0x04030201
hex_result00c: 0xFFFFFFFF
hex_result00d: 0x000000FF
hex_result01a: 0x80204100
hex_result01b: 0xFFFFFFFF
hex_result01c: 0x000003E8
hex_result01d: 0xFFFFFF00
hex_result01e: 0x7F000000
hex_result02a: 0x80204100
hex_result02b: 0x0A0B0C0D

--]]
